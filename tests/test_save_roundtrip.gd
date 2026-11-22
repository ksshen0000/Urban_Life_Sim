extends "res://tests/framework/test_case.gd"
## T017 / spec §8 SaveRoundTrip + EventOnce across saves: a save with wages, a relationship, a
## lease, rent, story progress and a pending story entry restores field-for-field; play continues
## identically; damaged or tampered saves are rejected without touching the running game or the
## previous good file; migrations run in order.

const Sessions := preload("res://tests/framework/session_factory.gd")
const P := SimulationSession.PLAYER_ID
const DIR := "user://test_saves"

var saves: SaveManager


func before_each() -> void:
	_clear_dir()
	saves = SaveManager.new(DIR)


func after_each() -> void:
	_clear_dir()


func _clear_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)


func _policies() -> RegionPolicyRegistry:
	return RegionPolicyRegistry.with_builtin_implementations()


func _json(v: Variant) -> String:
	return JSON.stringify(v, "", true)


## Day 1 → day 7 morning with money, work, a lease, rent paid, a relationship and story state.
func _played_session() -> SimulationSession:
	var s := Sessions.create({"story_enabled": true})
	s.run_story_rules()
	_answer(s)
	assert_true(s.submit("sign_lease", {"housing_id": "home_shared_room_01"}).ok, "lease")
	Sessions.go(s, "fast_food_restaurant")
	assert_true(s.submit("buy_item", {"shop_id": "shop_fast_food", "item_id": "item_simple_meal", "quantity": 1}).ok, "buy")
	assert_true(s.submit("book_shift", {"job_id": "job_convenience_clerk", "day": 2, "template_id": "morning"}).ok, "book")
	_to(s, 1, 9)
	Sessions.go(s, "convenience_store")
	assert_true(s.submit("choose_dialogue", {"tree_id": "dialogue_chen_yu_intro", "node_id": "start", "choice_id": "thanks"}).ok, "talk")
	_to(s, 2, 7)
	assert_true(s.submit("work_shift", {"shift_id": JobsSystem.shift_id_for("job_convenience_clerk", 2, "morning")}).ok, "work")
	_answer(s)
	_to(s, 7, 9)
	return s


func _to(s: SimulationSession, day: int, hour: int) -> void:
	var target := GameClock.minute_from_day_time(day, hour)
	while s.world.clock.get_minute() < target:
		s.submit("advance_time", {"minutes": mini(120, target - s.world.clock.get_minute())}, "system")
		# Answer everything except leave the newest entry pending at the end (saved mid-story).
		if s.world.clock.get_minute() < target:
			_answer(s)


func _answer(s: SimulationSession) -> void:
	var guard := 0
	while s.dialogue.has_pending() and guard < 20:
		guard += 1
		var e := s.dialogue.peek()
		if e["kind"] == "summary":
			s.submit("dismiss_story_entry", {"entry_id": e["entry_id"]})
			continue
		var node: Dictionary = s.content.get_record("dialogues", e["tree_id"])["nodes"].filter(
			func(n: Dictionary) -> bool: return n["id"] == e["node_id"])[0]
		for c: Dictionary in node["choices"]:
			if s.submit("choose_dialogue", {"tree_id": e["tree_id"], "node_id": e["node_id"], "choice_id": c["id"],
					"entry_id": e["entry_id"]}).ok:
				break


func _save_and_load(s: SimulationSession, tile := Vector2i(12, 9)) -> Dictionary:
	var w := saves.save_session("slot_01", s, tile)
	assert_true(w["ok"], "save: %s %s" % [w["error_code"], w["message"]])
	var r := saves.load_slot("slot_01", s.content, _policies())
	assert_true(r["ok"], "load: %s %s" % [r["error_code"], r["message"]])
	return r


func test_roundtrip_restores_every_field() -> void:
	var s := _played_session()
	assert_false(s.housing.get_lease(P).is_empty(), "has a lease")
	assert_true(s.economy.get_ledger(P).any(func(e: Dictionary) -> bool: return str(e["reason"]).contains("rent")), "rent was charged")
	assert_true(s.jobs.get_shifts(P).any(func(sh: Dictionary) -> bool: return sh["status"] == "completed"), "has a paid shift")
	assert_true(s.relationships.get_value("npc_chen_yu") > 0, "has a relationship")
	assert_true(s.events.fired_ids().size() >= 3, "story progressed")
	var r := _save_and_load(s)
	var loaded: SimulationSession = r["session"]
	assert_eq(_json(loaded.world.to_dict()), _json(s.world.to_dict()), "world snapshot identical")
	assert_eq(loaded.get_proposal_seq(), s.get_proposal_seq())
	assert_eq(_json(loaded.view_player()), _json(s.view_player()))
	assert_eq(loaded.economy.get_ledger(P).size(), s.economy.get_ledger(P).size(), "ledger kept")
	assert_eq(r["player"]["tile"], Vector2i(12, 9))
	assert_eq(r["player"]["scene_id"], s.locations.get_map_id(P))
	assert_eq(r["warnings"].size(), 0)


func test_play_continues_identically_after_load() -> void:
	var s := _played_session()
	var loaded: SimulationSession = _save_and_load(s)["session"]
	for sess: SimulationSession in [s, loaded]:
		_answer(sess)
		Sessions.go(sess, "fast_food_restaurant")
		sess.submit("buy_item", {"shop_id": "shop_fast_food", "item_id": "item_simple_meal", "quantity": 1})
		sess.submit("book_shift", {"job_id": "job_convenience_clerk", "day": 7, "template_id": "evening"})
		_to(sess, 8, 8)
		_answer(sess)
	assert_eq(_json(loaded.world.to_dict()), _json(s.world.to_dict()), "same commands → same world, journal and event ids")


func test_once_events_stay_fired_after_load() -> void:
	var s := _played_session()
	var fired := s.events.fired_ids()
	var loaded: SimulationSession = _save_and_load(s)["session"]
	loaded.run_story_rules()
	_answer(loaded)
	for id in fired:
		assert_eq(loaded.events.to_dict()["fired"][id]["count"], 1, "%s fired once" % id)


func test_save_file_is_plain_json_with_spec_fields() -> void:
	var s := _played_session()
	saves.save_session("slot_02", s, Vector2i(-1, -1))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(saves.slot_path("slot_02")))
	for key in ["save_schema_version", "game_version", "region_id", "city_id", "packs", "player", "clock_minute",
			"rng", "world", "currency_code"]:
		assert_has(data, key)
	assert_eq(data["region_id"], "CN")
	assert_eq(data["player"]["tile"], null)
	for comp in ["clock", "economy", "needs", "inventory", "jobs", "housing", "relationships", "flags", "events", "dialogue", "quests"]:
		assert_has(data["world"]["components"], comp)
	assert_false(FileAccess.file_exists(saves.slot_path("slot_02") + ".tmp"), "no temp file left")


func test_damaged_file_reports_error() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for garbage: String in ["", "{not json", "[1, 2]", "{\"save_schema_version\": 1}", "{\"save_schema_version\": \"x\"}"]:
		var f := FileAccess.open(saves.slot_path("slot_03"), FileAccess.WRITE)
		f.store_string(garbage)
		f.close()
		var r := saves.load_slot("slot_03", Sessions.content(), _policies())
		assert_false(r["ok"], "rejected: " + garbage)
		assert_eq(r["error_code"], "E_SAVE_CORRUPT", garbage)
		assert_eq(r["session"], null)
	assert_eq(saves.list_slots()[2]["state"], "corrupt")
	assert_eq(saves.list_slots()[0]["state"], "empty")
	assert_eq(saves.load_slot("slot_01", Sessions.content(), _policies())["error_code"], "E_SAVE_NOT_FOUND")
	assert_eq(saves.load_slot("../evil", Sessions.content(), _policies())["error_code"], "E_SAVE_BAD_SLOT")


func test_failed_save_keeps_old_file() -> void:
	var s := _played_session()
	assert_true(saves.save_session("slot_01", s)["ok"])
	var before := FileAccess.get_file_as_string(saves.slot_path("slot_01"))
	var bad := SaveManager.build(s)
	bad["world"]["components"]["needs"]["values"][P]["hunger"] = 500  # out of range
	var w := saves.write_data("slot_01", bad, s.content, _policies())
	assert_false(w["ok"])
	assert_eq(w["error_code"], "E_SAVE_VERIFY_FAILED")
	assert_eq(FileAccess.get_file_as_string(saves.slot_path("slot_01")), before, "old save untouched")
	assert_false(FileAccess.file_exists(saves.slot_path("slot_01") + ".tmp"))
	assert_true(saves.load_slot("slot_01", s.content, _policies())["ok"], "old save still loads")


func test_second_save_keeps_backup_and_backup_is_used_if_main_missing() -> void:
	var s := _played_session()
	assert_true(saves.save_session("slot_01", s)["ok"])
	var first_minute := s.world.clock.get_minute()
	s.submit("advance_time", {"minutes": 30}, "system")
	assert_true(saves.save_session("slot_01", s)["ok"])
	assert_true(FileAccess.file_exists(saves.slot_path("slot_01") + ".bak"))
	DirAccess.remove_absolute(saves.slot_path("slot_01"))  # interrupted between the two renames
	var r := saves.load_slot("slot_01", s.content, _policies())
	assert_true(r["ok"], "backup used")
	assert_eq((r["session"] as SimulationSession).world.clock.get_minute(), first_minute)


func test_tampered_saves_rejected() -> void:
	var s := _played_session()
	var good := SaveManager.build(s)
	var cases := {
		"E_SAVE_TOO_NEW": func(d: Dictionary) -> void: d["save_schema_version"] = SaveManager.SAVE_SCHEMA_VERSION + 1,
		"E_SAVE_PACK_MISSING": func(d: Dictionary) -> void: d["packs"]["city_xx_nowhere"] = {"pack_version": "1", "content_hash": "x"},
		"E_SAVE_UNKNOWN_CITY": func(d: Dictionary) -> void: d["city_id"] = "XX_NOWHERE",
		"E_SAVE_REGION_MISMATCH": func(d: Dictionary) -> void: d["region_id"] = "US",
		"E_CURRENCY_MISMATCH": func(d: Dictionary) -> void: d["currency_code"] = "USD",
		"E_INVALID_NEEDS_STATE": func(d: Dictionary) -> void: d["world"]["components"]["needs"]["values"][P]["energy"] = -1,
		"E_INVALID_ECONOMY_STATE": func(d: Dictionary) -> void: d["world"]["components"]["economy"]["balances"][P] = "lots",
		"E_INVALID_LOCATION_STATE": func(d: Dictionary) -> void: d["world"]["components"]["locations"]["actors"][P]["location_id"] = "nowhere",
		"E_INVALID_JOBS_STATE": func(d: Dictionary) -> void:
			for id: String in d["world"]["components"]["jobs"]["shifts"]:
				d["world"]["components"]["jobs"]["shifts"][id]["job_id"] = "job_astronaut",
		"E_SAVE_UNKNOWN_ID": func(d: Dictionary) -> void: d["world"]["components"]["inventory"]["owners"][P]["item_gold_bar"] = 1,
		"E_SAVE_INCONSISTENT": func(d: Dictionary) -> void: d["clock_minute"] = int(d["clock_minute"]) + 1,
		"E_MISSING_COMPONENT": func(d: Dictionary) -> void: d["world"]["components"].erase("housing"),
		"E_SAVE_CORRUPT": func(d: Dictionary) -> void: d.erase("player"),
	}
	for code: String in cases:
		var d: Dictionary = JSON.parse_string(JSON.stringify(good))
		(cases[code] as Callable).call(d)
		var r := SaveManager.restore(s.content, _policies(), d)
		assert_false(r["ok"], code)
		assert_eq(r["error_code"], code)
	# The untampered copy (after a JSON trip, numbers as floats) loads.
	assert_true(SaveManager.restore(s.content, _policies(), JSON.parse_string(JSON.stringify(good)))["ok"])


func test_unknown_story_ids_rejected() -> void:
	var s := _played_session()
	var good := SaveManager.build(s)
	var d: Dictionary = good.duplicate(true)
	d["world"]["components"]["events"]["fired"]["event_alien_invasion"] = {"count": 1, "last_minute": 10}
	assert_eq(SaveManager.restore(s.content, _policies(), d)["error_code"], "E_SAVE_UNKNOWN_ID")
	d = good.duplicate(true)
	d["world"]["components"]["dialogue"]["pending"].append({"entry_id": "story_999999", "kind": "dialogue",
		"source": "x", "tree_id": "dialogue_chen_yu_intro", "node_id": "no_such_node"})
	assert_eq(SaveManager.restore(s.content, _policies(), d)["error_code"], "E_SAVE_UNKNOWN_ID")


func test_migrations_run_in_order() -> void:
	var steps := {
		1: func(d: Dictionary) -> Dictionary:
			d["trail"] = ["1to2"]
			return d,
		2: func(d: Dictionary) -> Dictionary:
			(d["trail"] as Array).append("2to3")
			return d,
	}
	var r := SaveMigrations.migrate({"save_schema_version": 1.0}, 3, steps)
	assert_true(r["ok"])
	assert_eq(r["data"]["trail"], ["1to2", "2to3"])
	assert_eq(r["data"]["save_schema_version"], 3)
	assert_eq(SaveMigrations.migrate({"save_schema_version": 1}, 4, steps)["error_code"], "E_SAVE_NO_MIGRATION")
	assert_eq(SaveMigrations.migrate({"save_schema_version": 5}, 3, steps)["error_code"], "E_SAVE_TOO_NEW")
	assert_eq(SaveMigrations.migrate({"save_schema_version": 1}, 2,
		{1: func(_d: Dictionary) -> Dictionary: return {}})["error_code"], "E_SAVE_MIGRATION_FAILED")
	assert_eq(SaveMigrations.migrate({}, 1)["error_code"], "E_SAVE_CORRUPT")
	var current := SaveMigrations.migrate({"save_schema_version": SaveManager.SAVE_SCHEMA_VERSION}, SaveManager.SAVE_SCHEMA_VERSION)
	assert_true(current["ok"], "current version needs no steps")


func test_slot_list_summary() -> void:
	var s := _played_session()
	saves.save_session("slot_02", s)
	var slots := saves.list_slots()
	assert_eq(slots.size(), 3)
	assert_eq(slots[1]["state"], "ok")
	assert_eq(slots[1]["summary"]["day_index"], 7)
	assert_eq(slots[1]["summary"]["balance_minor"], s.economy.get_balance(P))
	assert_true(saves.has_any_save())
