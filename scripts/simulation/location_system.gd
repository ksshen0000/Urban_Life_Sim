class_name LocationSystem
extends RefCounted
## Where actors are, at map granularity (D-020): {map_id, location_id of the last arrival}. Walking
## inside a map is presentation; changing maps (bus) is a command. Commands that happen at a
## place (buy, work, sleep, ride) require the actor to be on that place's map.

const SCHEMA_VERSION := 1
const STATE_SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"actors": {"type": "map", "required": true, "values_spec": {"type": "object", "fields": {
		"map_id": {"type": "id", "required": true},
		"location_id": {"type": "id", "required": true},
	}}},
}}

var _content: ContentRegistry
var _actors: Dictionary = {}


func _init(content: ContentRegistry = null) -> void:
	_content = content


## World setup only.
func place(actor_id: String, location_id: String) -> bool:
	if _content == null or not _content.has_record("locations", location_id):
		return false
	_actors[actor_id] = {"map_id": _content.get_record("locations", location_id)["map_id"], "location_id": location_id}
	return true


func has_actor(actor_id: String) -> bool:
	return _actors.has(actor_id)


func get_map_id(actor_id: String) -> String:
	return (_actors.get(actor_id, {}) as Dictionary).get("map_id", "")


func get_location_id(actor_id: String) -> String:
	return (_actors.get(actor_id, {}) as Dictionary).get("location_id", "")


func map_of_location(location_id: String) -> String:
	return _content.get_record("locations", location_id).get("map_id", "") if _content.has_record("locations", location_id) else ""


func is_on_map_of(actor_id: String, location_id: String) -> bool:
	var m := map_of_location(location_id)
	return not m.is_empty() and m == get_map_id(actor_id)


func move_to(ctx: CommandContext, actor_id: String, location_id: String) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	if not has_actor(actor_id) or not _content.has_record("locations", location_id):
		return "E_INVALID_ARGUMENTS"
	var previous := get_map_id(actor_id)
	_actors[actor_id] = {"map_id": map_of_location(location_id), "location_id": location_id}
	ctx.emit("location_changed", {"actor_id": actor_id, "location_id": location_id,
		"map_id": _actors[actor_id]["map_id"], "previous_map_id": previous})
	return ""


func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "actors": _actors.duplicate(true)}


func from_dict(data: Dictionary) -> String:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, STATE_SCHEMA)
	if not v.is_ok():
		return "E_INVALID_LOCATION_STATE"
	for actor: String in d["actors"]:
		var a: Dictionary = d["actors"][actor]
		if map_of_location(a["location_id"]) != a["map_id"]:
			return "E_INVALID_LOCATION_STATE"
	_actors = d["actors"]
	return ""
