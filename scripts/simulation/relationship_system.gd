class_name RelationshipSystem
extends RefCounted
## Player <-> NPC relationship scores, -100..100 (T014). Positive changes coming from repeatable
## small talk are rate-limited: at most one per NPC per game day ("互动冷却"), so chatting the
## same line again and again cannot farm affection.

const SCHEMA_VERSION := 1
const MIN_VALUE := -100
const MAX_VALUE := 100
const STATE_SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"npcs": {"type": "map", "required": true, "values_spec": {"type": "object", "fields": {
		"value": {"type": "int", "required": true, "min": MIN_VALUE, "max": MAX_VALUE},
		"last_positive_day": {"type": "int", "required": true, "min": 0},
	}}},
}}

var _content: ContentRegistry
var _npcs: Dictionary = {}


func _init(content: ContentRegistry = null) -> void:
	_content = content
	if content != null:
		for npc in content.get_records("npcs"):
			_npcs[npc["id"]] = {"value": clampi(int(npc["initial_relationship"]), MIN_VALUE, MAX_VALUE), "last_positive_day": 0}


func get_value(npc_id: String) -> int:
	return (_npcs.get(npc_id, {}) as Dictionary).get("value", 0)


func get_all() -> Dictionary:
	var out := {}
	for id: String in _npcs:
		out[id] = _npcs[id]["value"]
	return out


func max_value() -> int:
	var best := MIN_VALUE
	for id: String in _npcs:
		best = maxi(best, int(_npcs[id]["value"]))
	return best


## Positive repeatable gains already used today?
func is_on_cooldown(npc_id: String, day: int) -> bool:
	return int((_npcs.get(npc_id, {}) as Dictionary).get("last_positive_day", 0)) >= day


## Returns the applied delta (0 when blocked by cooldown or clamping) via ctx event; "" or error.
func change(ctx: CommandContext, npc_id: String, delta: int, rate_limited: bool, reason: String) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	if not _npcs.has(npc_id):
		return "E_UNKNOWN_NPC"
	var day := ctx.world.clock.get_day_index()
	if delta > 0 and rate_limited:
		if is_on_cooldown(npc_id, day):
			ctx.emit("relationship_cooldown", {"npc_id": npc_id, "day": day})
			return ""
		_npcs[npc_id]["last_positive_day"] = day
	var old: int = _npcs[npc_id]["value"]
	var new_value := clampi(old + delta, MIN_VALUE, MAX_VALUE)
	_npcs[npc_id]["value"] = new_value
	if new_value != old:
		ctx.emit("relationship_changed", {"npc_id": npc_id, "value": new_value, "delta": new_value - old, "reason": reason})
	return ""


func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "npcs": _npcs.duplicate(true)}


func from_dict(data: Dictionary) -> String:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, STATE_SCHEMA)
	if not v.is_ok():
		return "E_INVALID_RELATIONSHIP_STATE"
	for id: String in d["npcs"]:
		if _content != null and not _content.has_record("npcs", id):
			return "E_INVALID_RELATIONSHIP_STATE"
	_npcs = d["npcs"]
	return ""
