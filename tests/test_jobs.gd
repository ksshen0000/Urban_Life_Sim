extends "res://tests/framework/test_case.gd"
## T009 / T010 + spec §8.1 #4 PayIdempotency, #5 RegionPolicySwap.

const Sessions := preload("res://tests/framework/session_factory.gd")
const ContentFixture := preload("res://tests/framework/content_fixture.gd")
const FlatFeePolicy := preload("res://tests/fixtures/flat_fee_region_policy.gd")
const P := SimulationSession.PLAYER_ID
const CLERK := "job_convenience_clerk"


func _wait(s: SimulationSession, minutes: int) -> void:
	assert_true(s.submit("advance_time", {"minutes": minutes}, "system").ok)


func _book(s: SimulationSession, job: String, day: int, tpl: String) -> CommandResult:
	return s.submit("book_shift", {"job_id": job, "day": day, "template_id": tpl})


func _to(s: SimulationSession, day: int, hour: int, minute: int = 0) -> void:
	_wait(s, GameClock.minute_from_day_time(day, hour, minute) - s.world.clock.get_minute())


func test_jobs_loaded_from_content() -> void:
	var ids := Sessions.content().get_ids("jobs")
	assert_eq(ids, PackedStringArray(["job_convenience_clerk", "job_restaurant_server", "job_warehouse_sorter"]))


func test_booking_rules() -> void:
	var s := Sessions.create()
	assert_eq(_book(s, CLERK, 1, "evening").error_code, "E_JOB_NOT_OPEN", "clerk hires from day 2")
	assert_true(_book(s, CLERK, 2, "morning").ok, "tomorrow's shift can be booked on day 1")
	assert_eq(_book(s, CLERK, 2, "morning").error_code, "E_SHIFT_UNAVAILABLE", "already booked")
	assert_eq(_book(s, CLERK, 3, "morning").error_code, "E_SHIFT_UNAVAILABLE", "only today/tomorrow")
	assert_eq(_book(s, "job_restaurant_server", 2, "lunch").error_code, "E_SHIFT_CONFLICT", "overlaps 09:00-13:00")
	assert_true(_book(s, "job_restaurant_server", 2, "dinner").ok)
	assert_eq(_book(s, "job_warehouse_sorter", 2, "day").error_code, "E_JOB_NOT_OPEN", "warehouse from day 4")
	assert_eq(_book(s, CLERK, 2, "night").error_code, "E_INVALID_ARGUMENTS")
	assert_eq(_book(s, "job_astronaut", 2, "morning").error_code, "E_UNKNOWN_JOB")
	_to(s, 2, 9, 30)
	assert_eq(_book(s, CLERK, 2, "evening").error_code, "E_SHIFT_CONFLICT", "17:00-21:00 dinner overlaps 18:00")


func test_region_daily_limit_applies_to_booking() -> void:
	var s := Sessions.create()
	_to(s, 4, 6)
	assert_true(_book(s, "job_warehouse_sorter", 4, "day").ok)        # 08-13
	assert_true(_book(s, "job_warehouse_sorter", 4, "afternoon").ok)  # 14-19 (600 min total)
	assert_eq(_book(s, CLERK, 4, "evening").error_code, "E_SHIFT_CONFLICT")
	assert_eq(s.jobs.check_booking(P, "job_restaurant_server", 4, "dinner", s.world.clock.get_minute(), s.policy),
		"E_SHIFT_CONFLICT")
	# 600 booked + 240 would exceed the CN gamified 720-minute daily cap even without overlap
	var w := s.jobs.window(Sessions.content().get_record("jobs", CLERK), 4, "evening")
	assert_false(s.policy.validate_work_shift({}, 240, {"worked_minutes_today": 600}))
	assert_true(w["start"] > 0)


func test_work_shift_pays_once_with_region_take_home() -> void:
	var s := Sessions.create()
	_book(s, CLERK, 2, "morning")
	_to(s, 2, 9)
	var before := s.economy.get_balance(P)
	var id := JobsSystem.shift_id_for(CLERK, 2, "morning")
	var r := s.submit("work_shift", {"shift_id": id})
	assert_true(r.ok, str(r.error_code))
	assert_eq(GameClock.format_debug(s.world.clock.get_minute()), "D2 13:00")
	assert_eq(s.economy.get_balance(P) - before, 8360, "¥88.00 gross - 5% = ¥83.60")
	var sh := s.jobs.get_shift(id)
	assert_eq([sh["status"], sh["gross_minor"], sh["net_minor"], sh["worked_minutes"]], ["completed", 8800, 8360, 240])
	assert_eq(s.submit("work_shift", {"shift_id": id}).error_code, "E_SHIFT_NOT_BOOKED", "a paid shift cannot be worked again")
	assert_eq(s.economy.get_balance(P) - before, 8360, "paid exactly once")
	var wages := s.economy.get_ledger(P).filter(func(t: Dictionary) -> bool: return str(t["reason"]) == "wage:" + id)
	assert_eq(wages.size(), 1)


func test_replayed_work_command_is_not_paid_twice() -> void:
	var s := Sessions.create()
	_book(s, CLERK, 2, "morning")
	_to(s, 2, 9)
	var p := ActionProposal.create("ui.work.1", P, "work_shift", {"shift_id": JobsSystem.shift_id_for(CLERK, 2, "morning")})
	var first := s.processor.apply(p)
	var balance := s.economy.get_balance(P)
	var again := s.processor.apply(p)
	assert_true(first.ok)
	assert_true(again.duplicate)
	assert_eq(s.economy.get_balance(P), balance)


func test_work_needs_use_job_rates() -> void:
	var s := Sessions.create()
	_book(s, CLERK, 2, "morning")
	_to(s, 2, 9)
	var e0 := s.needs.get_value(P, "energy")
	var st0 := s.needs.get_value(P, "stress")
	s.submit("work_shift", {"shift_id": JobsSystem.shift_id_for(CLERK, 2, "morning")})
	assert_eq(s.needs.get_value(P, "energy"), maxi(e0 - 20, 0), "-5/h for 4h")
	assert_true(s.needs.get_value(P, "stress") >= st0 + 8, "+2/h for 4h (+ pressure if hungry)")


func test_early_arrival_waits_and_late_arrival_is_docked() -> void:
	var s := Sessions.create()
	_book(s, CLERK, 2, "morning")
	_book(s, "job_restaurant_server", 2, "dinner")
	_to(s, 2, 7, 30)
	assert_true(s.submit("work_shift", {"shift_id": JobsSystem.shift_id_for(CLERK, 2, "morning")}).ok)
	var early := s.jobs.get_shift(JobsSystem.shift_id_for(CLERK, 2, "morning"))
	assert_eq([early["worked_minutes"], early["late_minutes"]], [240, 0], "waited until 09:00, full pay")
	_to(s, 2, 18, 0)  # dinner started 17:00: 60 min late
	var r := s.submit("work_shift", {"shift_id": JobsSystem.shift_id_for("job_restaurant_server", 2, "dinner")})
	assert_true(r.ok)
	var late := s.jobs.get_shift(JobsSystem.shift_id_for("job_restaurant_server", 2, "dinner"))
	assert_eq([late["worked_minutes"], late["late_minutes"], late["gross_minor"]], [180, 60, 7500])
	assert_eq(GameClock.format_debug(s.world.clock.get_minute()), "D2 21:00", "shift still ends on schedule")


func test_start_window() -> void:
	var s := Sessions.create()
	_book(s, CLERK, 2, "morning")
	var id := JobsSystem.shift_id_for(CLERK, 2, "morning")
	_to(s, 2, 6, 59)
	assert_eq(s.submit("work_shift", {"shift_id": id}).error_code, "E_SHIFT_NOT_STARTED")
	_to(s, 2, 12, 31)
	assert_eq(s.submit("work_shift", {"shift_id": id}).error_code, "E_SHIFT_TOO_LATE")


func test_missed_shift() -> void:
	var s := Sessions.create()
	_book(s, CLERK, 2, "morning")
	var missed: Array = []
	_to(s, 2, 14)
	for e in s.processor.get_event_log():
		if e.type == "shift_missed":
			missed.append(e.payload["shift_id"])
	assert_eq(missed, [JobsSystem.shift_id_for(CLERK, 2, "morning")])
	assert_eq(s.jobs.count_with_status(P, "missed"), 1)
	assert_eq(s.jobs.count_with_status(P, "completed"), 0)


func test_must_be_at_workplace() -> void:
	var s := Sessions.create()
	_to(s, 4, 6)
	_book(s, "job_warehouse_sorter", 4, "day")
	var id := JobsSystem.shift_id_for("job_warehouse_sorter", 4, "day")
	_to(s, 4, 7, 30)
	assert_eq(s.submit("work_shift", {"shift_id": id}).error_code, "E_NOT_HERE", "warehouse is in the industrial zone")
	assert_true(s.submit("take_route", {"route_id": "route_12_to_industrial"}).ok)
	assert_true(s.submit("work_shift", {"shift_id": id}).ok)
	assert_eq(s.jobs.get_shift(id)["net_minor"], 15200, "¥160.00 gross - 5%")


func test_region_policy_swap_changes_pay_not_flow() -> void:
	var fx := ContentFixture.new()
	fx.load_real()
	fx.data("regions/cn/policy_config.json")["implementation"] = "flat_fee"
	fx.data("regions/cn/policy_config.json")["settings"] = {"flat_fee_minor": 1000}
	var content := ContentRegistry.new()
	assert_true(content.load_root(fx.write()), "\n".join(content.get_error_strings()))
	var policies := RegionPolicyRegistry.with_builtin_implementations()
	policies.register_implementation("flat_fee", FlatFeePolicy)
	var r := SimulationSession.create_new(content, policies, "CN_LINCHUAN")
	assert_true(r["ok"])
	var s: SimulationSession = r["session"]
	_book(s, CLERK, 2, "morning")
	_to(s, 2, 9)
	var before := s.economy.get_balance(P)
	assert_true(s.submit("work_shift", {"shift_id": JobsSystem.shift_id_for(CLERK, 2, "morning")}).ok)
	assert_eq(s.economy.get_balance(P) - before, 7800, "same WorkShiftHandler, different policy: ¥88 - ¥10 fee")
	fx.cleanup()
