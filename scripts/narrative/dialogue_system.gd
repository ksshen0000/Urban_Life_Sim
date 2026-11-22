class_name DialogueSystem
extends RefCounted
## Story presentation queue + dialogue progress (T014/T015). Events enqueue dialogue trees or
## frozen summaries; the UI shows the head of the queue and answers through commands. Also
## remembers which non-repeatable trees are completed (an NPC's intro is offered only once).

const SCHEMA_VERSION := 1
const MAX_PENDING := 10
const STATE_SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"next_entry_seq": {"type": "int", "required": true, "min": 1},
	"completed": {"type": "map", "required": true, "values_spec": {"type": "int", "min": 0}},
	"pending": {"type": "array", "required": true, "items": {"type": "object", "fields": {
		"entry_id": {"type": "string", "required": true, "min_length": 1},
		"kind": {"type": "string", "required": true, "values": ["dialogue", "summary"]},
		"source": {"type": "string", "required": true},
		"tree_id": {"type": "id"},
		"node_id": {"type": "id"},
		"lines": {"type": "array", "items": {"type": "string"}},
	}}},
}}

var _completed: Dictionary = {}
var _pending: Array[Dictionary] = []
var _next_seq := 1


func is_completed(tree_id: String) -> bool:
	return _completed.has(tree_id)


func has_pending() -> bool:
	return not _pending.is_empty()


func peek() -> Dictionary:
	return _pending[0].duplicate(true) if has_pending() else {}


func get_pending() -> Array[Dictionary]:
	return _pending.duplicate(true)


func find_entry(entry_id: String) -> Dictionary:
	for e in _pending:
		if e["entry_id"] == entry_id:
			return e.duplicate(true)
	return {}


func can_enqueue() -> bool:
	return _pending.size() < MAX_PENDING


func enqueue_tree(ctx: CommandContext, tree_id: String, start_node: String, source: String) -> String:
	return _enqueue(ctx, {"kind": "dialogue", "tree_id": tree_id, "node_id": start_node, "source": source})


func enqueue_summary(ctx: CommandContext, lines: PackedStringArray, source: String) -> String:
	return _enqueue(ctx, {"kind": "summary", "lines": Array(lines), "source": source})


func set_entry_node(ctx: CommandContext, entry_id: String, node_id: String) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	for e in _pending:
		if e["entry_id"] == entry_id:
			e["node_id"] = node_id
			return ""
	return "E_DIALOGUE_DONE"


func finish_entry(ctx: CommandContext, entry_id: String) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	for i in _pending.size():
		if _pending[i]["entry_id"] == entry_id:
			_pending.remove_at(i)
			ctx.emit("story_entry_finished", {"entry_id": entry_id})
			return ""
	return "E_DIALOGUE_DONE"


func mark_completed(ctx: CommandContext, tree_id: String) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	_completed[tree_id] = ctx.current_minute()
	return ""


func _enqueue(ctx: CommandContext, entry: Dictionary) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	if not can_enqueue():
		return "E_STORY_QUEUE_FULL"
	entry["entry_id"] = "story_%06d" % _next_seq
	_next_seq += 1
	_pending.append(entry)
	ctx.emit("story_entry_queued", entry.duplicate(true))
	return ""


func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "next_entry_seq": _next_seq, "completed": _completed.duplicate(),
		"pending": _pending.duplicate(true)}


func from_dict(data: Dictionary) -> String:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, STATE_SCHEMA)
	if not v.is_ok():
		return "E_INVALID_DIALOGUE_STATE"
	_next_seq = d["next_entry_seq"]
	_completed = d["completed"]
	_pending.assign(d["pending"])
	return ""
