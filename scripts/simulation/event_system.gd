class_name EventSystem
extends RefCounted
## Story events (T015, spec §4.3): which events have fired. Eligibility = not yet fired (all
## current events are `once`) and every condition true; candidates are ordered by priority
## (high first) then id, so the same world state always picks the same event.

const SCHEMA_VERSION := 1
const STATE_SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"fired": {"type": "map", "required": true, "values_spec": {"type": "object", "fields": {
		"count": {"type": "int", "required": true, "min": 1},
		"last_minute": {"type": "int", "required": true, "min": 0},
	}}},
}}

var _content: ContentRegistry
var _fired: Dictionary = {}


func _init(content: ContentRegistry = null) -> void:
	_content = content


func has_fired(event_id: String) -> bool:
	return _fired.has(event_id)


func fired_ids() -> PackedStringArray:
	var ids := PackedStringArray(_fired.keys())
	ids.sort()
	return ids


func is_eligible(event_id: String, world: WorldState) -> bool:
	if not _content.has_record("events", event_id):
		return false
	var ev := _content.get_record("events", event_id)
	if ev["once"] and has_fired(event_id):
		return false
	return StoryConditions.all_true(ev["conditions"], world, _content)


func eligible_events(world: WorldState) -> PackedStringArray:
	var records := _content.get_records("events")
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["priority"]) > int(b["priority"]) or (int(a["priority"]) == int(b["priority"]) and a["id"] < b["id"]))
	var out: PackedStringArray = []
	for ev in records:
		if is_eligible(ev["id"], world):
			out.append(ev["id"])
	return out


## NPCs who have a face-to-face story beat waiting (D-036): an unfired event with an
## `npc_nearby` condition for them whose other conditions already hold. The world then lets the
## NPC notice the player and walk over (the walk ends with `approach_npc`, which fires it).
func greeting_npcs(world: WorldState) -> PackedStringArray:
	var out: PackedStringArray = []
	for ev in _content.get_records("events"):
		if has_fired(ev["id"]):
			continue
		var npc := ""
		var others_hold := true
		for c: Dictionary in ev["conditions"]:
			if c["type"] == "npc_nearby":
				npc = c["npc_id"]
			elif not StoryConditions.evaluate(c, world, _content):
				others_hold = false
				break
		if not npc.is_empty() and others_hold and not out.has(npc):
			out.append(npc)
	return out


func mark_fired(ctx: CommandContext, event_id: String) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	var prev: Dictionary = _fired.get(event_id, {"count": 0, "last_minute": 0})
	_fired[event_id] = {"count": int(prev["count"]) + 1, "last_minute": ctx.current_minute()}
	return ""


func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "fired": _fired.duplicate(true)}


func from_dict(data: Dictionary) -> String:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, STATE_SCHEMA)
	if not v.is_ok():
		return "E_INVALID_EVENT_STATE"
	_fired = d["fired"]
	return ""
