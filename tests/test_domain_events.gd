extends "res://tests/framework/test_case.gd"
## T004b (pre-T022): idempotent proposals, stable event ids, bounded logs, signal fan-out,
## world snapshot round trip.


class Gate extends CommandHandler:
	var open := false

	func get_action() -> String:
		return "gate"

	func validate(_ctx: CommandContext) -> String:
		return "" if open else "E_GATE_CLOSED"

	func apply(ctx: CommandContext) -> String:
		ctx.world.clock.advance_minutes(1)
		ctx.emit("gate_passed")
		return ""


var world: WorldState
var processor: CommandProcessor


func before_each() -> void:
	world = WorldState.new(GameClock.minute_from_day_time(1, 8))
	processor = CommandProcessor.new(world)
	processor.register_handler(AdvanceTimeHandler.new())


func _advance(pid: String, minutes: int) -> CommandResult:
	return processor.apply(ActionProposal.create(pid, "system", "advance_time", {"minutes": minutes}))


func test_same_proposal_id_applies_once() -> void:
	var first := _advance("shift_pay_001", 60)
	var again := _advance("shift_pay_001", 60)
	assert_true(again.ok)
	assert_true(again.duplicate)
	assert_false(first.duplicate)
	assert_eq(again.emitted_event_ids, first.emitted_event_ids, "replay returns the original result")
	assert_eq(world.clock.get_minute(), 540, "applied once")
	assert_eq(world.revision, 1)
	assert_eq(processor.get_event_log().size(), 1)


func test_reusing_an_id_for_a_different_request_is_rejected() -> void:
	_advance("p1", 60)
	var r := _advance("p1", 90)
	assert_eq(r.error_code, "E_PROPOSAL_ID_REUSED")
	assert_eq(world.clock.get_minute(), 540)


func test_failed_proposal_can_be_retried_with_same_id() -> void:
	var gate := Gate.new()
	processor.register_handler(gate)
	var p := ActionProposal.create("g1", "system", "gate")
	assert_eq(processor.apply(p).error_code, "E_GATE_CLOSED")
	gate.open = true
	var r := processor.apply(p)
	assert_true(r.ok)
	assert_false(r.duplicate, "the failure was not cached")


func test_json_floats_do_not_change_identity() -> void:
	var parsed := ActionProposal.from_dict(JSON.parse_string(
		'{"schema_version": 1, "proposal_id": "p1", "actor_id": "system", "action": "advance_time", "arguments": {"minutes": 60}}'))
	assert_true(parsed["ok"])
	var from_json: ActionProposal = parsed["proposal"]
	assert_eq(typeof(from_json.arguments["minutes"]), TYPE_INT)
	assert_true(processor.apply(from_json).ok)
	assert_true(_advance("p1", 60).duplicate, "code-built proposal matches the JSON one")


func test_malformed_json_proposal_reports_paths() -> void:
	var parsed := ActionProposal.from_dict({"schema_version": 1, "proposal_id": "p 1", "action": "Advance"})
	assert_false(parsed["ok"])
	assert_eq(parsed["error_code"], "E_MALFORMED_PROPOSAL")
	var paths: Array = parsed["errors"].map(func(e: Dictionary) -> String: return e["path"])
	assert_has(paths, "/proposal_id")
	assert_has(paths, "/actor_id")
	assert_has(paths, "/action")


func test_event_ids_are_sequential_and_never_reused() -> void:
	var gate := Gate.new()
	processor.register_handler(gate)
	_advance("a", 1)
	processor.apply(ActionProposal.create("closed", "system", "gate"))  # fails, consumes nothing
	_advance("b", 1)
	var ids: Array = processor.get_event_log().map(func(e: DomainEvent) -> String: return e.event_id)
	assert_eq(ids, ["evt_00000001", "evt_00000002"])


func test_event_log_is_bounded() -> void:
	var small := CommandProcessor.new(world, {}, 3)
	small.register_handler(AdvanceTimeHandler.new())
	small.apply(ActionProposal.create("p", "system", "advance_time", {"minutes": 3 * GameClock.MINUTES_PER_DAY}))
	var log := small.get_event_log()
	assert_eq(log.size(), 3)
	assert_eq(log[-1].type, "time_advanced", "newest kept")
	assert_eq(log[-1].game_minute, world.clock.get_minute())


func test_journal_capacity_evicts_oldest() -> void:
	var j := CommandJournal.new(2)
	j.remember("a", "fa", {})
	j.remember("b", "fb", {})
	j.remember("c", "fc", {})
	assert_eq(j.size(), 2)
	assert_true(j.lookup("a").is_empty())
	assert_eq(j.lookup("c")["fingerprint"], "fc")


func test_bus_rebroadcasts_committed_events_only() -> void:
	var bus := GameEventBus.new()
	bus.attach(processor)
	var days: Array[int] = []
	var segments: Array = []
	bus.day_changed.connect(func(d: int) -> void: days.append(d))
	bus.time_advanced.connect(func(a: int, b: int) -> void: segments.append([a, b]))
	_advance("p1", 2 * GameClock.MINUTES_PER_DAY + 60)
	assert_eq(days, [2, 3], "every crossed day announced once, in order")
	assert_eq(segments, [[480, 1440], [1440, 2880], [2880, 3420]])
	_advance("p_bad", 0)
	processor.apply(ActionProposal.create("p_npc", "npc_chen_yu", "advance_time", {"minutes": 5}))
	assert_eq(days.size(), 2, "failed commands publish nothing")
	assert_eq(segments.size(), 3)
	bus.detach(processor)
	_advance("p2", GameClock.MINUTES_PER_DAY)
	assert_eq(days.size(), 2, "detached bus is silent")
	bus.free()


func test_domain_event_round_trip() -> void:
	_advance("p1", 30)
	var e: DomainEvent = processor.get_event_log()[0]
	var copy := DomainEvent.from_dict(JSON.parse_string(JSON.stringify(e.to_dict())))
	assert_not_null(copy)
	if copy != null:
		assert_eq(copy.to_dict(), e.to_dict())
	assert_eq(DomainEvent.from_dict({"event_id": "x"}), null)


func test_world_round_trip_keeps_idempotency() -> void:
	_advance("p1", 600)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict()))

	var loaded := WorldState.new()
	assert_eq(loaded.from_dict(saved), "")
	assert_eq(loaded.to_dict(), world.to_dict())
	var loaded_processor := CommandProcessor.new(loaded)
	loaded_processor.register_handler(AdvanceTimeHandler.new())
	var replay := loaded_processor.apply(ActionProposal.create("p1", "system", "advance_time", {"minutes": 600}))
	assert_true(replay.duplicate, "a committed command stays committed across save/load")
	assert_eq(loaded.clock.get_minute(), 1080)
	var next := loaded_processor.apply(ActionProposal.create("p2", "system", "advance_time", {"minutes": 1}))
	assert_eq(next.emitted_event_ids, PackedStringArray(["evt_00000002"]), "event ids continue after load")


func test_world_restore_is_all_or_nothing() -> void:
	_advance("p1", 60)
	var before := world.to_dict()
	var bad := before.duplicate(true)
	bad["components"]["clock"]["minute"] = -1
	assert_eq(world.from_dict(bad), "E_INVALID_CLOCK_STATE")
	assert_eq(world.to_dict(), before)
	var unknown := before.duplicate(true)
	unknown["components"]["teleporter"] = {}
	assert_eq(world.from_dict(unknown), "E_UNKNOWN_COMPONENT")
	var missing := before.duplicate(true)
	missing["components"].erase("clock")
	assert_eq(world.from_dict(missing), "E_MISSING_COMPONENT")
	assert_eq(world.to_dict(), before)
