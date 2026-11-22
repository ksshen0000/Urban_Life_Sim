class_name QuestSystem
extends RefCounted
## Tracked objectives (T016). Each quest is a sequence of steps; the current step completes when
## its conditions hold (checked after every command by the session's story pass), so players can
## do things in any order and the tracker catches up.

const SCHEMA_VERSION := 1
const STATE_SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"quests": {"type": "map", "required": true, "values_spec": {"type": "int", "min": 0}},
}}

var _content: ContentRegistry
var _step_index: Dictionary = {}  # quest_id -> index of the current step (== steps.size() when done)


func _init(content: ContentRegistry = null) -> void:
	_content = content
	if content != null:
		for q in content.get_records("quests"):
			_step_index[q["id"]] = 0


func get_step_index(quest_id: String) -> int:
	return _step_index.get(quest_id, 0)


func is_complete(quest_id: String) -> bool:
	return get_step_index(quest_id) >= (_content.get_record("quests", quest_id)["steps"] as Array).size()


## Current step record, or {} when the quest is complete.
func current_step(quest_id: String) -> Dictionary:
	var steps: Array = _content.get_record("quests", quest_id)["steps"]
	var i := get_step_index(quest_id)
	return (steps[i] as Dictionary).duplicate(true) if i < steps.size() else {}


func can_advance(quest_id: String, world: WorldState) -> bool:
	if not _step_index.has(quest_id) or is_complete(quest_id):
		return false
	return StoryConditions.all_true(current_step(quest_id)["conditions"], world, _content)


func advanceable_quests(world: WorldState) -> PackedStringArray:
	var ids := PackedStringArray(_step_index.keys())
	ids.sort()
	var out: PackedStringArray = []
	for id in ids:
		if can_advance(id, world):
			out.append(id)
	return out


func advance(ctx: CommandContext, quest_id: String) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	var step := current_step(quest_id)
	_step_index[quest_id] = get_step_index(quest_id) + 1
	ctx.emit("quest_step_completed", {"quest_id": quest_id, "step_id": step["id"]})
	if is_complete(quest_id):
		ctx.emit("quest_completed", {"quest_id": quest_id})
	return ""


func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "quests": _step_index.duplicate()}


func from_dict(data: Dictionary) -> String:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, STATE_SCHEMA)
	if not v.is_ok():
		return "E_INVALID_QUEST_STATE"
	for id: String in d["quests"]:
		if not _content.has_record("quests", id):
			return "E_INVALID_QUEST_STATE"
	_step_index = d["quests"]
	return ""
