class_name CommandJournal
extends RefCounted
## Part of WorldState (saved with it): the event id sequence and a bounded memory of committed
## proposal ids for idempotency. Only successful commands are remembered — a failed command
## changed nothing, so retrying it with the same id is safe and re-evaluated.
##
## The window is bounded (FIFO). Domain rules still guard their own invariants (e.g. a shift is
## paid once by shift_id) so correctness never depends on this window alone (D-009).

const SCHEMA_VERSION := 1
const DEFAULT_CAPACITY := 4096
const SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"next_event_seq": {"type": "int", "required": true, "min": 1},
	"entries": {"type": "array", "required": true, "items": {"type": "object", "fields": {
		"proposal_id": {"type": "string", "required": true, "min_length": 1},
		"fingerprint": {"type": "string", "required": true},
		"result": {"type": "map", "required": true, "values_spec": {"type": "any"}},
	}}},
}}

var next_event_seq := 1
var capacity := DEFAULT_CAPACITY
var _order: Array[String] = []
var _entries: Dictionary = {}  # proposal_id -> {fingerprint, result}


func _init(p_capacity: int = DEFAULT_CAPACITY) -> void:
	capacity = maxi(p_capacity, 1)


func allocate_event_id() -> String:
	var id := "evt_%08d" % next_event_seq
	next_event_seq += 1
	return id


func lookup(proposal_id: String) -> Dictionary:
	return _entries.get(proposal_id, {})


func remember(proposal_id: String, fingerprint: String, result: Dictionary) -> void:
	if not _entries.has(proposal_id):
		_order.append(proposal_id)
	_entries[proposal_id] = {"fingerprint": fingerprint, "result": result.duplicate(true)}
	while _order.size() > capacity:
		_entries.erase(_order.pop_front())


func size() -> int:
	return _order.size()


func to_dict() -> Dictionary:
	var entries: Array = []
	for id in _order:
		entries.append({"proposal_id": id, "fingerprint": _entries[id]["fingerprint"],
			"result": (_entries[id]["result"] as Dictionary).duplicate(true)})
	return {"schema_version": SCHEMA_VERSION, "next_event_seq": next_event_seq, "entries": entries}


func from_dict(data: Dictionary) -> String:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, SCHEMA)
	if not v.is_ok():
		return "E_INVALID_JOURNAL_STATE"
	next_event_seq = d["next_event_seq"]
	_order.clear()
	_entries.clear()
	for e: Dictionary in d["entries"]:
		remember(e["proposal_id"], e["fingerprint"], e["result"])
	return ""
