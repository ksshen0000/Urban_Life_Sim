extends "res://tests/framework/test_case.gd"
## T004b (pre-T021): CommandProcessor is the only write path; failed commands leave no trace.


class MutateThenFail extends CommandHandler:
	func get_action() -> String:
		return "mutate_then_fail"

	func apply(ctx: CommandContext) -> String:
		ctx.world.clock.advance_minutes(60)
		ctx.emit("test_partial", {"step": 1})
		return "E_TEST_FAILURE"


class MutatesInValidate extends CommandHandler:
	func get_action() -> String:
		return "sneaky"

	func validate(ctx: CommandContext) -> String:
		ctx.world.clock.advance_minutes(5)
		return ""

	func apply(_ctx: CommandContext) -> String:
		return ""


class EmitsInValidate extends CommandHandler:
	func get_action() -> String:
		return "early_emit"

	func validate(ctx: CommandContext) -> String:
		ctx.emit("too_early")
		return ""

	func apply(_ctx: CommandContext) -> String:
		return ""


class Reentrant extends CommandHandler:
	var processor: CommandProcessor
	var inner_result: CommandResult

	func get_action() -> String:
		return "reentrant"

	func apply(ctx: CommandContext) -> String:
		inner_result = processor.apply(ActionProposal.create("inner", "system", "advance_time", {"minutes": 1}))
		ctx.emit("outer_done")
		return ""


var world: WorldState
var processor: CommandProcessor
var commits := 0


func before_each() -> void:
	world = WorldState.new(GameClock.minute_from_day_time(1, 23, 50))
	processor = CommandProcessor.new(world)
	processor.register_handler(AdvanceTimeHandler.new())
	processor.committed.connect(func(_r: CommandResult, _e: Array[DomainEvent]) -> void: commits += 1)
	commits = 0


func after_each() -> void:
	# Lambdas capturing this test instance + processor form RefCounted cycles; break them.
	for c: Dictionary in processor.committed.get_connections():
		processor.committed.disconnect(c["callable"])


func _advance(pid: String, minutes: Variant, actor := "system") -> CommandResult:
	return processor.apply(ActionProposal.create(pid, actor, "advance_time", {"minutes": minutes}))


func _assert_untouched(start_minute: int) -> void:
	assert_eq(world.clock.get_minute(), start_minute, "clock unchanged")
	assert_eq(world.revision, 0, "revision unchanged")
	assert_eq(world.journal.next_event_seq, 1, "no event ids consumed")
	assert_eq(processor.get_event_log().size(), 0, "no events logged")
	assert_eq(commits, 0, "no commit notification")


func test_advance_time_commits_events() -> void:
	var r := _advance("p1", 30)
	assert_true(r.ok, str(r.error_code))
	assert_eq(r.error_code, null)
	assert_eq(r.world_revision, 1)
	assert_eq(r.emitted_event_ids, PackedStringArray(["evt_00000001", "evt_00000002", "evt_00000003"]))
	assert_eq(GameClock.format_debug(world.clock.get_minute()), "D2 00:20")
	var log := processor.get_event_log()
	assert_eq(log.map(func(e: DomainEvent) -> String: return e.type), ["time_advanced", "day_changed", "time_advanced"])
	assert_eq(log.map(func(e: DomainEvent) -> int: return e.game_minute), [1440, 1440, 1460])
	for e in log:
		assert_eq(e.cause_id, "p1")
		assert_eq(e.actor_id, "system")
		assert_eq(e.world_revision, 1)
	assert_eq(commits, 1)


func test_failed_apply_rolls_back_everything() -> void:
	processor.register_handler(MutateThenFail.new())
	var start := world.clock.get_minute()
	var r := processor.apply(ActionProposal.create("p1", "system", "mutate_then_fail"))
	assert_false(r.ok)
	assert_eq(r.error_code, "E_TEST_FAILURE")
	assert_eq(r.emitted_event_ids.size(), 0)
	_assert_untouched(start)


func test_validate_must_not_mutate() -> void:
	processor.register_handler(MutatesInValidate.new())
	var start := world.clock.get_minute()
	var r := processor.apply(ActionProposal.create("p1", "system", "sneaky"))
	assert_eq(r.error_code, "E_HANDLER_CONTRACT")
	_assert_untouched(start)


func test_emit_outside_apply_is_a_contract_violation() -> void:
	processor.register_handler(EmitsInValidate.new())
	var r := processor.apply(ActionProposal.create("p1", "system", "early_emit"))
	assert_eq(r.error_code, "E_HANDLER_CONTRACT")
	_assert_untouched(world.clock.get_minute())


func test_malformed_and_unknown_proposals() -> void:
	var start := world.clock.get_minute()
	assert_eq(processor.apply(null).error_code, "E_MALFORMED_PROPOSAL")
	assert_eq(processor.apply(ActionProposal.create("", "system", "advance_time")).error_code, "E_MALFORMED_PROPOSAL")
	assert_eq(processor.apply(ActionProposal.create("p1", "", "advance_time")).error_code, "E_MALFORMED_PROPOSAL")
	assert_eq(processor.apply(ActionProposal.create("p1", "Player One", "advance_time")).error_code, "E_MALFORMED_PROPOSAL")
	assert_eq(processor.apply(ActionProposal.create("p1", "system", "teleport")).error_code, "E_UNKNOWN_ACTION")
	_assert_untouched(start)


func test_npc_cannot_advance_world_time() -> void:
	var start := world.clock.get_minute()
	assert_eq(_advance("p1", 30, "npc_chen_yu").error_code, "E_FORBIDDEN_ACTOR")
	_assert_untouched(start)
	assert_true(_advance("p2", 30, "player").ok)
	assert_true(_advance("p3", 30, "system:event/event_first_rent").ok)


func test_invalid_arguments() -> void:
	var start := world.clock.get_minute()
	for bad: Variant in [0, -5, 1.5, "30", GameClock.MAX_ADVANCE_MINUTES + 1]:
		assert_eq(_advance("p_%s" % str(bad), bad).error_code, "E_INVALID_ARGUMENTS", "minutes=%s" % str(bad))
	assert_eq(processor.apply(ActionProposal.create("p_none", "system", "advance_time")).error_code, "E_INVALID_ARGUMENTS")
	_assert_untouched(start)


func test_revision_conflict() -> void:
	var p := ActionProposal.create("p1", "system", "advance_time", {"minutes": 1})
	p.expected_world_revision = 5
	assert_eq(processor.apply(p).error_code, "E_REVISION_CONFLICT")
	p.expected_world_revision = 0
	assert_true(processor.apply(p).ok)
	var stale := ActionProposal.create("p2", "system", "advance_time", {"minutes": 1})
	stale.expected_world_revision = 0
	assert_eq(processor.apply(stale).error_code, "E_REVISION_CONFLICT", "world moved on to revision 1")


func test_nested_apply_is_refused() -> void:
	var h := Reentrant.new()
	h.processor = processor
	processor.register_handler(h)
	var start := world.clock.get_minute()
	var r := processor.apply(ActionProposal.create("outer", "system", "reentrant"))
	assert_true(r.ok)
	assert_eq(h.inner_result.error_code, "E_REENTRANT_COMMAND")
	assert_eq(world.clock.get_minute(), start, "inner command did not run")
	h.processor = null  # break handler <-> processor cycle


func test_commands_from_commit_subscribers_run_afterwards() -> void:
	var follow_up: Array[CommandResult] = []
	processor.committed.connect(func(r: CommandResult, _e: Array[DomainEvent]) -> void:
		if r.proposal_id == "p1":
			follow_up.append(_advance("p2", 10)))
	assert_true(_advance("p1", 10).ok)
	assert_eq(follow_up.size(), 1)
	assert_true(follow_up[0].ok, "follow-up allowed once the first command finished")
	assert_eq(world.revision, 2)


func test_register_handler_rules() -> void:
	assert_false(processor.register_handler(AdvanceTimeHandler.new()), "duplicate action")
	assert_false(processor.register_handler(CommandHandler.new()), "empty action")
	assert_false(processor.register_handler(null))
	assert_true(processor.has_handler("advance_time"))
