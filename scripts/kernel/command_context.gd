class_name CommandContext
extends RefCounted
## What a CommandHandler sees while one proposal is processed: the proposal, the world, read-only
## services (content registry, region policy...) and an event buffer. Events can only be emitted
## during the APPLY phase; they become visible (log, signals) only if the command commits.

enum Phase { AUTHORIZE, VALIDATE, APPLY, DONE }

var proposal: ActionProposal
var world: WorldState
var phase: Phase = Phase.AUTHORIZE
## Optional human-readable detail for a failure (error codes stay the stable contract).
var message := ""
## While time is being advanced segment by segment, events default to this game minute
## instead of the clock's final minute (set by TimeFlow). -1 = use the clock.
var time_cursor := -1

var _services: Dictionary
var _events: Array[DomainEvent] = []
var _violations: PackedStringArray = []


func _init(p_proposal: ActionProposal, p_world: WorldState, services: Dictionary) -> void:
	proposal = p_proposal
	world = p_world
	_services = services


func current_minute() -> int:
	return time_cursor if time_cursor >= 0 else world.clock.get_minute()


## True only while handler.apply runs: domain systems refuse writes otherwise.
func can_write() -> bool:
	return phase == Phase.APPLY


func get_service(service_name: String) -> Variant:
	return _services.get(service_name)


## Returns the new event_id (usable as cause_id of later events), or "" if not allowed now.
func emit(type: String, payload: Dictionary = {}, cause_id: String = "", game_minute: int = -1) -> String:
	if phase != Phase.APPLY:
		_violations.append("emit('%s') outside apply phase" % type)
		return ""
	var e := DomainEvent.new()
	e.event_id = world.journal.allocate_event_id()
	e.type = type
	e.game_minute = game_minute if game_minute >= 0 else current_minute()
	e.actor_id = proposal.actor_id
	e.cause_id = cause_id if not cause_id.is_empty() else proposal.proposal_id
	e.payload = payload.duplicate(true)
	_events.append(e)
	return e.event_id


## Emits drafts of the form {type, payload, game_minute?} (e.g. from GameClock.advance_minutes).
func emit_drafts(drafts: Array, cause_id: String = "") -> void:
	for d: Dictionary in drafts:
		emit(d["type"], d.get("payload", {}), cause_id, int(d.get("game_minute", -1)))


func get_events() -> Array[DomainEvent]:
	return _events


func get_violations() -> PackedStringArray:
	return _violations
