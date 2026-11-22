class_name CommandProcessor
extends RefCounted
## The single authoritative write path (spec §2.1, §13.1): validate → apply → emit.
##
## Pipeline for apply(proposal):
##   1. structure check, handler lookup              E_MALFORMED_PROPOSAL, E_UNKNOWN_ACTION
##   2. idempotency: committed id → original result  (duplicate = true), E_PROPOSAL_ID_REUSED
##   3. optimistic concurrency                       E_REVISION_CONFLICT
##   4. handler.authorize / handler.validate         handler codes; must not mutate (E_HANDLER_CONTRACT)
##   5. handler.apply inside a transaction           any error → full rollback, no events
##   6. commit: revision+1, events stamped, logged, `committed` emitted
## Nested apply() from inside a handler is refused (E_REENTRANT_COMMAND); subscribers of
## `committed` may submit follow-up commands, which run after the current one finished.

signal committed(result: CommandResult, events: Array[DomainEvent])

const DEFAULT_EVENT_LOG_LIMIT := 2048

## Compares world snapshots around authorize/validate to enforce the read-only contract.
var verify_read_only_phases := true

var _world: WorldState
var _services: Dictionary
var _handlers: Dictionary = {}
var _event_log: Array[DomainEvent] = []
var _event_log_limit: int
var _applying := false


func _init(world: WorldState, services: Dictionary = {}, event_log_limit: int = DEFAULT_EVENT_LOG_LIMIT) -> void:
	_world = world
	_services = services
	_event_log_limit = maxi(event_log_limit, 1)


func register_handler(handler: CommandHandler) -> bool:
	if handler == null:
		return false
	var action := handler.get_action()
	if action.is_empty() or _handlers.has(action):
		return false
	_handlers[action] = handler
	return true


func has_handler(action: String) -> bool:
	return _handlers.has(action)


func get_world() -> WorldState:
	return _world


## Bounded, most recent last. Snapshots (saves) are the source of truth; this log serves
## replay tests, debugging and the future narrative layer (spec §13.1 implementation note).
func get_event_log() -> Array[DomainEvent]:
	return _event_log.duplicate()


func apply(proposal: ActionProposal) -> CommandResult:
	if proposal == null:
		return CommandResult.failure("", "E_MALFORMED_PROPOSAL", _world.revision, "null proposal")
	var pid := proposal.proposal_id
	if _applying:
		return CommandResult.failure(pid, "E_REENTRANT_COMMAND", _world.revision,
			"commands cannot be applied from inside another command")
	var structural := proposal.validate_structure()
	if not structural.is_empty():
		return CommandResult.failure(pid, structural, _world.revision)
	var handler: CommandHandler = _handlers.get(proposal.action)
	if handler == null:
		return CommandResult.failure(pid, "E_UNKNOWN_ACTION", _world.revision,
			"no handler for action '%s'" % proposal.action)

	var fingerprint := proposal.fingerprint()
	var prior := _world.journal.lookup(pid)
	if not prior.is_empty():
		if prior["fingerprint"] != fingerprint:
			return CommandResult.failure(pid, "E_PROPOSAL_ID_REUSED", _world.revision,
				"proposal id was already used for a different request")
		var replay := CommandResult.from_dict(prior["result"])
		replay.duplicate = true
		return replay

	if proposal.expected_world_revision >= 0 and proposal.expected_world_revision != _world.revision:
		return CommandResult.failure(pid, "E_REVISION_CONFLICT", _world.revision,
			"expected revision %d, world is at %d" % [proposal.expected_world_revision, _world.revision])

	_applying = true
	var outcome := _run(handler, proposal, fingerprint)
	_applying = false
	var result: CommandResult = outcome["result"]
	if result.ok:
		committed.emit(result, outcome["events"])
	return result


func _run(handler: CommandHandler, proposal: ActionProposal, fingerprint: String) -> Dictionary:
	var pid := proposal.proposal_id
	var ctx := CommandContext.new(proposal, _world, _services)
	var before := _world.capture()

	ctx.phase = CommandContext.Phase.AUTHORIZE
	var err := handler.authorize(ctx)
	if err.is_empty():
		ctx.phase = CommandContext.Phase.VALIDATE
		err = handler.validate(ctx)
	if verify_read_only_phases and _world.capture() != before:
		_world.rollback(before)
		return _failed(pid, "E_HANDLER_CONTRACT", "authorize/validate of '%s' mutated the world" % proposal.action)
	if not ctx.get_violations().is_empty():
		return _failed(pid, "E_HANDLER_CONTRACT", "; ".join(ctx.get_violations()))
	if not err.is_empty():
		return _failed(pid, err, ctx.message)

	ctx.phase = CommandContext.Phase.APPLY
	err = handler.apply(ctx)
	if err.is_empty() and not ctx.get_violations().is_empty():
		err = "E_HANDLER_CONTRACT"
		ctx.message = "; ".join(ctx.get_violations())
	if not err.is_empty():
		_world.rollback(before)
		return _failed(pid, err, ctx.message)

	ctx.phase = CommandContext.Phase.DONE
	_world.revision += 1
	var events := ctx.get_events()
	var ids: PackedStringArray = []
	for e in events:
		e.world_revision = _world.revision
		ids.append(e.event_id)
	var result := CommandResult.success(pid, _world.revision, ids)
	_world.journal.remember(pid, fingerprint, result.to_dict())
	_event_log.append_array(events)
	if _event_log.size() > _event_log_limit:
		_event_log = _event_log.slice(_event_log.size() - _event_log_limit)
	return {"result": result, "events": events}


func _failed(pid: String, code: String, message: String = "") -> Dictionary:
	var events: Array[DomainEvent] = []
	return {"result": CommandResult.failure(pid, code, _world.revision, message), "events": events}
