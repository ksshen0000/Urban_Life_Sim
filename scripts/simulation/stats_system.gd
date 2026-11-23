class_name StatsSystem
extends RefCounted
## Lifetime counters per actor (food eaten, trips...), used by quest and story conditions so
## they never depend on the bounded event log.

const SCHEMA_VERSION := 1
const STATE_SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"actors": {"type": "map", "required": true, "values_spec": {"type": "map",
		"key_pattern": ContentSchemas.FLAG_KEY_PATTERN, "values_spec": {"type": "int", "min": 0}}},
}}

var _actors: Dictionary = {}


func get_stat(actor_id: String, key: String) -> int:
	return (_actors.get(actor_id, {}) as Dictionary).get(key, 0)


func increment(ctx: CommandContext, actor_id: String, key: String, amount: int = 1) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	if not _actors.has(actor_id):
		_actors[actor_id] = {}
	_actors[actor_id][key] = get_stat(actor_id, key) + amount
	return ""


## Records a value outright (e.g. the minute the player last walked up to an NPC).
func set_stat(ctx: CommandContext, actor_id: String, key: String, value: int) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	if not _actors.has(actor_id):
		_actors[actor_id] = {}
	_actors[actor_id][key] = maxi(value, 0)
	return ""


func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "actors": _actors.duplicate(true)}


func from_dict(data: Dictionary) -> String:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, STATE_SCHEMA)
	if not v.is_ok():
		return "E_INVALID_STATS_STATE"
	_actors = d["actors"]
	return ""
