class_name SaveManager
extends RefCounted
## Save files (T017, spec §4.4). A save is plain JSON: an envelope (versions, city, content packs,
## player scene/spawn, a short summary for the slot list) around the authoritative snapshot
## `WorldState.to_dict()`, which already holds the clock, wallet + ledger, needs, inventory,
## locations, jobs, housing, flags, stats, relationships, fired events, the story queue and
## quests. Nothing in a save is executed or deserialized into objects.
##
## Writing: serialize → write `<slot>.json.tmp` → read it back → fully restore it into a scratch
## session (the same checks as a real load) → move the previous file to `<slot>.json.bak` →
## rename the temp file into place. A save that fails any step never touches the old file.
## Loading: size limit → JSON parse → explicit migrations → envelope schema → content packs,
## city, region and currency must match → component restore (each validates ranges and ids) →
## cross-reference checks against content. Any failure leaves the running game untouched.

const SAVE_SCHEMA_VERSION := 2
const DEFAULT_DIR := "user://saves"
const SLOT_IDS: PackedStringArray = ["slot_01", "slot_02", "slot_03"]
const MAX_FILE_BYTES := 4 * 1024 * 1024
const SLOT_PATTERN := "^slot_[0-9]{2}$"

const ENVELOPE_SCHEMA := {"type": "object", "fields": {
	"save_schema_version": {"type": "int", "required": true, "min": 1, "max": SAVE_SCHEMA_VERSION},
	"game_version": {"type": "string", "required": true},
	"saved_at_unix": {"type": "int", "required": true, "min": 0},
	"region_id": {"type": "string", "required": true, "min_length": 1},
	"city_id": {"type": "string", "required": true, "min_length": 1},
	"currency_code": {"type": "string", "required": true, "min_length": 3},
	"packs": {"type": "map", "required": true, "values_spec": {"type": "object", "fields": {
		"pack_version": {"type": "string", "required": true},
		"content_hash": {"type": "string", "required": true},
	}}},
	"player": {"type": "object", "required": true, "fields": {
		"actor_id": {"type": "id", "required": true},
		"scene_id": {"type": "id", "required": true},
		"spawn_id": {"type": "id", "required": true},
		"tile": {"type": "array", "nullable": true, "min_items": 2, "max_items": 2,
			"items": {"type": "int", "min": 0, "max": 4096}},
	}},
	"clock_minute": {"type": "int", "required": true, "min": 0},
	"summary": {"type": "object", "required": true, "fields": {
		"day_index": {"type": "int", "required": true, "min": 1},
		"minute_of_day": {"type": "int", "required": true, "min": 0, "max": 1439},
		"balance_minor": {"type": "int", "required": true},
		"player_name": {"type": "string", "max_length": 32},
	}},
	# No game rule uses randomness yet; the field exists so a later RNG needs no format break.
	"rng": {"type": "object", "required": true, "fields": {
		"seed": {"type": "int", "required": true},
		"state": {"type": "int", "required": true},
	}},
	"session": {"type": "object", "required": true, "fields": {
		"proposal_seq": {"type": "int", "required": true, "min": 0},
	}},
	"world": {"type": "map", "required": true, "values_spec": {"type": "any"}},
}}

var save_dir: String


func _init(p_save_dir: String = DEFAULT_DIR) -> void:
	save_dir = p_save_dir


# --- pure: session <-> dictionary -----------------------------------------------------------

## `player_tile` is presentation only (where to stand after loading); Vector2i(-1, -1) = unknown.
static func build(session: SimulationSession, player_tile: Vector2i = Vector2i(-1, -1),
		saved_at_unix: int = 0) -> Dictionary:
	var packs := {}
	for pack_id in session.content.get_pack_ids():
		var m := session.content.get_pack(pack_id)
		packs[pack_id] = {"pack_version": str(m.get("pack_version", "")), "content_hash": str(m.get("content_hash", ""))}
	var v := session.view_player()
	return {
		"save_schema_version": SAVE_SCHEMA_VERSION,
		"game_version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"saved_at_unix": maxi(saved_at_unix, 0),
		"region_id": str(session.city["region_id"]),
		"city_id": str(session.city["id"]),
		"currency_code": session.economy.get_currency_code(),
		"packs": packs,
		"player": {
			"actor_id": SimulationSession.PLAYER_ID,
			"scene_id": v["map_id"],
			"spawn_id": v["location_id"],
			"tile": [player_tile.x, player_tile.y] if player_tile.x >= 0 and player_tile.y >= 0 else null,
		},
		"clock_minute": v["minute"],
		"summary": {"day_index": v["day_index"], "minute_of_day": v["minute_of_day"], "balance_minor": v["balance_minor"],
			"player_name": session.profile.get_display_name(SimulationSession.PLAYER_ID)},
		"rng": {"seed": 0, "state": 0},
		"session": {"proposal_seq": session.get_proposal_seq()},
		"world": session.world.to_dict(),
	}


## Returns {ok, error_code, message, session, player, warnings}. `data` may come straight from
## JSON (floats for numbers). Never modifies anything outside the new session it returns.
static func restore(content: ContentRegistry, policies: RegionPolicyRegistry, data: Dictionary) -> Dictionary:
	var migrated := SaveMigrations.migrate(data, SAVE_SCHEMA_VERSION)
	if not migrated["ok"]:
		return _fail(migrated["error_code"], "save version %s cannot be read" % str(data.get("save_schema_version")))
	var v := SchemaValidator.new()
	var d: Variant = v.validate(migrated["data"], ENVELOPE_SCHEMA)
	if not v.is_ok():
		return _fail("E_SAVE_CORRUPT", "%s: %s" % [v.errors[0]["path"], v.errors[0]["message"]])
	var save: Dictionary = d

	# Content: every pack the save was made with must still be loaded (spec §16.3: no silent
	# substitution). Different versions are allowed; ids are re-checked below.
	var warnings: PackedStringArray = []
	for pack_id: String in save["packs"]:
		if not content.get_pack_ids().has(pack_id):
			return _fail("E_SAVE_PACK_MISSING", "content pack '%s' is not installed" % pack_id)
		var m := content.get_pack(pack_id)
		if str(m.get("content_hash", "")) != save["packs"][pack_id]["content_hash"]:
			warnings.append("pack '%s' changed since the save (%s → %s)" % [pack_id,
				save["packs"][pack_id]["pack_version"], m.get("pack_version", "")])
	if not content.has_record("cities", save["city_id"]):
		return _fail("E_SAVE_UNKNOWN_CITY", "city '%s' is not defined" % save["city_id"])
	var city := content.get_record("cities", save["city_id"])
	if city["region_id"] != save["region_id"]:
		return _fail("E_SAVE_REGION_MISMATCH", "city '%s' belongs to region '%s', save says '%s'" % [
			save["city_id"], city["region_id"], save["region_id"]])
	if city["currency_code"] != save["currency_code"]:
		return _fail("E_CURRENCY_MISMATCH", "save currency %s, city currency %s" % [save["currency_code"], city["currency_code"]])

	var created := SimulationSession.create_new(content, policies, save["city_id"])
	if not created["ok"]:
		return _fail(created["error_code"], created["message"])
	var session: SimulationSession = created["session"]
	var err := session.world.from_dict(save["world"])
	if not err.is_empty():
		return _fail(err, "world state rejected")
	err = check_references(session)
	if not err.is_empty():
		return _fail(err, "save refers to content that does not exist")
	var view := session.view_player()
	if view["minute"] != save["clock_minute"] or view["map_id"] != save["player"]["scene_id"] \
			or view["location_id"] != save["player"]["spawn_id"] \
			or view["balance_minor"] != save["summary"]["balance_minor"]:
		return _fail("E_SAVE_INCONSISTENT", "envelope does not match the world snapshot")
	if not session.economy.has_account(SimulationSession.PLAYER_ID) or not session.needs.has_owner(SimulationSession.PLAYER_ID):
		return _fail("E_SAVE_INCONSISTENT", "player state missing")
	session.set_proposal_seq(save["session"]["proposal_seq"])
	var tile: Variant = save["player"]["tile"]
	return {"ok": true, "error_code": null, "message": "", "session": session, "warnings": warnings,
		"player": {"scene_id": save["player"]["scene_id"], "spawn_id": save["player"]["spawn_id"],
			"tile": Vector2i(tile[0], tile[1]) if tile != null else Vector2i(-1, -1)}}


## Ids that components store but cannot check themselves (they do not hold content).
## Returns "" or an error code.
static func check_references(session: SimulationSession) -> String:
	var content := session.content
	for item_id: String in session.inventory.get_items(SimulationSession.PLAYER_ID):
		if not content.has_record("items", item_id):
			return "E_SAVE_UNKNOWN_ID"
	for event_id in session.events.fired_ids():
		if not content.has_record("events", event_id):
			return "E_SAVE_UNKNOWN_ID"
	var dialogue_state := session.dialogue.to_dict()
	for tree_id: String in dialogue_state["completed"]:
		if not content.has_record("dialogues", tree_id):
			return "E_SAVE_UNKNOWN_ID"
	for entry: Dictionary in dialogue_state["pending"]:
		if entry["kind"] == "dialogue":
			var tree := content.get_record("dialogues", str(entry.get("tree_id", "")))
			if tree.is_empty():
				return "E_SAVE_UNKNOWN_ID"
			var found := false
			for node: Dictionary in tree["nodes"]:
				found = found or node["id"] == entry.get("node_id", "")
			if not found:
				return "E_SAVE_UNKNOWN_ID"
		else:
			for key: String in entry.get("lines", []):
				if not content.has_record("text", key):
					return "E_SAVE_UNKNOWN_ID"
	for quest in content.get_records("quests"):
		if session.quests.get_step_index(quest["id"]) > (quest["steps"] as Array).size():
			return "E_SAVE_UNKNOWN_ID"
	return ""


static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error_code": code, "message": message, "session": null, "player": {}, "warnings": PackedStringArray()}


# --- files ----------------------------------------------------------------------------------

func slot_path(slot_id: String) -> String:
	return save_dir.path_join(slot_id + ".json")


static func is_valid_slot(slot_id: String) -> bool:
	var re := RegEx.create_from_string(SLOT_PATTERN)
	return re.search(slot_id) != null


## Writes `session` to `slot_id`. Returns {ok, error_code, message}. The old file survives any failure.
func save_session(slot_id: String, session: SimulationSession, player_tile: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	return write_data(slot_id, build(session, player_tile, int(Time.get_unix_time_from_system())),
		session.content, RegionPolicyRegistry.with_builtin_implementations())


## Lower level: writes an already-built save dictionary after verifying it restores.
func write_data(slot_id: String, data: Dictionary, content: ContentRegistry, policies: RegionPolicyRegistry) -> Dictionary:
	if not is_valid_slot(slot_id):
		return {"ok": false, "error_code": "E_SAVE_BAD_SLOT", "message": slot_id}
	var mk := DirAccess.make_dir_recursive_absolute(save_dir)
	if mk != OK and not DirAccess.dir_exists_absolute(save_dir):
		return {"ok": false, "error_code": "E_SAVE_WRITE_FAILED", "message": "cannot create %s (%s)" % [save_dir, error_string(mk)]}
	var text := JSON.stringify(data, "\t")
	if text.length() > MAX_FILE_BYTES:
		return {"ok": false, "error_code": "E_SAVE_TOO_LARGE", "message": "%d bytes" % text.length()}
	var final_path := slot_path(slot_id)
	var tmp_path := final_path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error_code": "E_SAVE_WRITE_FAILED", "message": error_string(FileAccess.get_open_error())}
	f.store_string(text)
	f.flush()
	var write_err := f.get_error()
	f.close()
	if write_err != OK:
		DirAccess.remove_absolute(tmp_path)
		return {"ok": false, "error_code": "E_SAVE_WRITE_FAILED", "message": error_string(write_err)}
	# Verify what is actually on disk, exactly as a later load would read it.
	var check := read_file(tmp_path, content, policies)
	if not check["ok"]:
		DirAccess.remove_absolute(tmp_path)
		return {"ok": false, "error_code": "E_SAVE_VERIFY_FAILED", "message": "%s %s" % [check["error_code"], check["message"]]}
	var bak_path := final_path + ".bak"
	if FileAccess.file_exists(final_path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		if DirAccess.rename_absolute(final_path, bak_path) != OK:
			DirAccess.remove_absolute(tmp_path)
			return {"ok": false, "error_code": "E_SAVE_WRITE_FAILED", "message": "cannot keep backup"}
	if DirAccess.rename_absolute(tmp_path, final_path) != OK:
		if FileAccess.file_exists(bak_path):
			DirAccess.rename_absolute(bak_path, final_path)
		DirAccess.remove_absolute(tmp_path)
		return {"ok": false, "error_code": "E_SAVE_WRITE_FAILED", "message": "cannot replace %s" % final_path}
	return {"ok": true, "error_code": null, "message": ""}


## Reads and fully validates a slot. If the slot file is missing but a backup exists (a save was
## interrupted between the two renames), the backup is used. Returns the `restore()` result.
func load_slot(slot_id: String, content: ContentRegistry, policies: RegionPolicyRegistry) -> Dictionary:
	if not is_valid_slot(slot_id):
		return _fail("E_SAVE_BAD_SLOT", slot_id)
	var path := slot_path(slot_id)
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".bak"):
		path += ".bak"
	return read_file(path, content, policies)


func read_file(path: String, content: ContentRegistry, policies: RegionPolicyRegistry) -> Dictionary:
	var parsed := _parse_file(path)
	if not parsed["ok"]:
		return _fail(parsed["error_code"], parsed["message"])
	return restore(content, policies, parsed["data"])


## Slot list for menus without restoring the world: [{slot_id, state, summary, saved_at_unix}].
## state: "empty" | "ok" | "corrupt" (cheap envelope check; a full check happens on load).
func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot_id in SLOT_IDS:
		var path := slot_path(slot_id)
		if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".bak"):
			path += ".bak"
		if not FileAccess.file_exists(path):
			out.append({"slot_id": slot_id, "state": "empty"})
			continue
		var parsed := _parse_file(path)
		var info := {"slot_id": slot_id, "state": "corrupt"}
		if parsed["ok"]:
			var d: Dictionary = parsed["data"]
			var migrated := SaveMigrations.migrate(d, SAVE_SCHEMA_VERSION)
			var v := SchemaValidator.new()
			var env: Variant = v.validate(migrated["data"], ENVELOPE_SCHEMA) if migrated["ok"] else null
			if migrated["ok"] and v.is_ok():
				info = {"slot_id": slot_id, "state": "ok", "summary": env["summary"],
					"saved_at_unix": env["saved_at_unix"], "city_id": env["city_id"]}
		out.append(info)
	return out


func has_any_save() -> bool:
	for s in list_slots():
		if s["state"] == "ok":
			return true
	return false


func _parse_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error_code": "E_SAVE_NOT_FOUND", "message": path}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error_code": "E_SAVE_READ_FAILED", "message": error_string(FileAccess.get_open_error())}
	if f.get_length() > MAX_FILE_BYTES:
		f.close()
		return {"ok": false, "error_code": "E_SAVE_TOO_LARGE", "message": path}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"ok": false, "error_code": "E_SAVE_CORRUPT", "message": "%s: not a JSON object (line %d)" % [path, json.get_error_line()]}
	return {"ok": true, "data": json.data}
