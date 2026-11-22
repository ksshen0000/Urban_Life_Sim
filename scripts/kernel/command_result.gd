class_name CommandResult
extends RefCounted
## Outcome of CommandProcessor.apply (spec §13.1): ok, error_code (null on success),
## world_revision, emitted_event_ids. `duplicate` marks an idempotent replay of a committed id.

var ok := false
var error_code: Variant = null
var message := ""
var proposal_id := ""
var world_revision := 0
var emitted_event_ids: PackedStringArray = []
var duplicate := false


static func success(p_proposal_id: String, revision: int, event_ids: PackedStringArray) -> CommandResult:
	var r := CommandResult.new()
	r.ok = true
	r.proposal_id = p_proposal_id
	r.world_revision = revision
	r.emitted_event_ids = event_ids
	return r


static func failure(p_proposal_id: String, code: String, revision: int, p_message: String = "") -> CommandResult:
	var r := CommandResult.new()
	r.ok = false
	r.error_code = code
	r.message = p_message
	r.proposal_id = p_proposal_id
	r.world_revision = revision
	return r


func to_dict() -> Dictionary:
	return {
		"ok": ok,
		"error_code": error_code,
		"message": message,
		"proposal_id": proposal_id,
		"world_revision": world_revision,
		"emitted_event_ids": Array(emitted_event_ids),
		"duplicate": duplicate,
	}


static func from_dict(d: Dictionary) -> CommandResult:
	var r := CommandResult.new()
	r.ok = d.get("ok", false)
	r.error_code = d.get("error_code")
	r.message = d.get("message", "")
	r.proposal_id = d.get("proposal_id", "")
	r.world_revision = int(d.get("world_revision", 0))
	r.emitted_event_ids = PackedStringArray(d.get("emitted_event_ids", []))
	r.duplicate = d.get("duplicate", false)
	return r
