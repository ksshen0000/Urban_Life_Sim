extends "res://tests/framework/test_case.gd"
## T008 + spec §8.1 #7 NeedBounds: needs change with time, eating, resting and sleep.

const Sessions := preload("res://tests/framework/session_factory.gd")
const P := SimulationSession.PLAYER_ID


func _lease(s: SimulationSession) -> void:
	assert_true(s.submit("sign_lease", {"housing_id": "home_shared_room_01"}).ok, "lease")


func _wait(s: SimulationSession, minutes: int) -> CommandResult:
	return s.submit("advance_time", {"minutes": minutes}, "system")


func test_initial_values_from_content() -> void:
	var s := Sessions.create()
	assert_eq(s.needs.get_values(P), {"energy": 80, "hunger": 25, "stress": 20})


func test_awake_hour_rates() -> void:
	var s := Sessions.create()
	_wait(s, 60)
	assert_eq(s.needs.get_values(P), {"energy": 77, "hunger": 29, "stress": 20})


func test_small_ticks_equal_one_big_step() -> void:
	var a := Sessions.create()
	var b := Sessions.create()
	for i in 600:
		_wait(a, 1)
	_wait(b, 600)
	assert_eq(a.needs.get_values(P), b.needs.get_values(P), "carry makes tick size irrelevant")
	assert_eq(a.needs.to_dict(), b.needs.to_dict())


func test_values_stay_in_bounds() -> void:
	var s := Sessions.create()
	_wait(s, 3 * GameClock.MINUTES_PER_DAY)  # awake for three days straight
	for need: String in s.needs.get_need_ids():
		var v := s.needs.get_value(P, need)
		assert_true(v >= 0 and v <= 100, "%s=%d" % [need, v])
	assert_eq(s.needs.get_value(P, "hunger"), 100)
	assert_eq(s.needs.get_value(P, "energy"), 0)
	assert_true(s.needs.get_value(P, "stress") > 20, "hunger/exhaustion pressure raised stress")


func test_hunger_pressure_raises_stress() -> void:
	var s := Sessions.create()
	_wait(s, 11 * 60)  # hunger 25 + 44 = 69: no pressure yet
	assert_eq(s.needs.get_value(P, "stress"), 20)
	_wait(s, 120)      # rules are checked at the start of each hour: 69 (no), then 73 (yes, +2)
	assert_eq(s.needs.get_value(P, "hunger"), 77)
	assert_eq(s.needs.get_value(P, "stress"), 22)


func test_sleep_restores_energy_to_cap_and_changes_day() -> void:
	var s := Sessions.create()
	_wait(s, 14 * 60)  # 08:00 -> 22:00, energy 80 - 42 = 38
	assert_eq(s.needs.get_value(P, "energy"), 38)
	_lease(s)
	var days: Array[int] = []
	var bus := GameEventBus.new()
	bus.attach(s.processor)
	bus.day_changed.connect(func(d: int) -> void: days.append(d))
	var r := s.submit("perform_activity", {"activity_id": "activity_sleep"})
	assert_true(r.ok, str(r.error_code))
	assert_eq(GameClock.format_debug(s.world.clock.get_minute()), "D2 06:00")
	assert_eq(days, [2], "sleep crossed midnight and announced the new day")
	assert_eq(s.needs.get_value(P, "energy"), 90, "38 + 80 capped at 90")
	assert_eq(s.needs.get_value(P, "hunger"), 25 + 56 + 16, "awake 14h x4, asleep 8h x2")
	bus.free()


func test_sleep_never_lowers_energy_above_cap() -> void:
	var s := Sessions.create()
	_lease(s)
	s.submit("perform_activity", {"activity_id": "activity_sleep"})  # 80 -> 90
	s.submit("perform_activity", {"activity_id": "activity_sleep"})
	assert_eq(s.needs.get_value(P, "energy"), 90)


func test_rest_on_bench() -> void:
	var s := Sessions.create()
	var r := s.submit("perform_activity", {"activity_id": "activity_rest"})
	assert_true(r.ok)
	assert_eq(s.needs.get_values(P), {"energy": 82, "hunger": 28, "stress": 16})


func test_activity_validation() -> void:
	var s := Sessions.create()
	assert_eq(s.submit("perform_activity", {"activity_id": "activity_party"}).error_code, "E_UNKNOWN_ACTIVITY")
	assert_eq(s.submit("perform_activity", {"activity_id": "activity_sleep"}, "npc_chen_yu").error_code,
		"E_FORBIDDEN_ACTOR")
	assert_eq(s.submit("perform_activity", {"activity_id": "activity_sleep"}).error_code, "E_NO_HOME",
		"no bed without a lease")


func test_need_events_carry_segment_minutes() -> void:
	var s := Sessions.create()
	_lease(s)
	_wait(s, 14 * 60 + 30)  # to 22:30
	s.submit("perform_activity", {"activity_id": "activity_sleep"})
	var log := s.processor.get_event_log()
	var day_event_minute := -1
	for e in log:
		if e.type == "day_changed":
			day_event_minute = e.game_minute
	assert_eq(day_event_minute, GameClock.MINUTES_PER_DAY, "day_changed stamped at midnight, not wake-up time")
	var need_minutes: Array = []
	for e in log:
		if e.type == "need_changed" and e.cause_id == log[-1].cause_id:
			need_minutes.append(e.game_minute)
	assert_true(need_minutes.has(GameClock.MINUTES_PER_DAY), "pre-midnight segment stamped at midnight")
	assert_true(need_minutes.has(s.world.clock.get_minute()), "post-midnight segment stamped at wake-up")


func test_failed_command_rolls_back_needs() -> void:
	var s := Sessions.create()
	_wait(s, 30)
	var before := s.world.to_dict()
	assert_eq(_wait(s, GameClock.MAX_ADVANCE_MINUTES + 1).error_code, "E_INVALID_ARGUMENTS")
	assert_eq(s.world.to_dict(), before)


func test_needs_state_round_trip_and_validation() -> void:
	var s := Sessions.create()
	_wait(s, 95)
	var copy := NeedsSystem.new(Sessions.content().get_records("needs"))
	assert_eq(copy.from_dict(JSON.parse_string(JSON.stringify(s.needs.to_dict()))), "")
	assert_eq(copy.to_dict(), s.needs.to_dict())
	var bad := s.needs.to_dict()
	bad["values"]["player"]["hunger"] = 101
	assert_eq(copy.from_dict(bad), "E_INVALID_NEEDS_STATE")
	var unknown := s.needs.to_dict()
	unknown["values"]["player"]["thirst"] = 5
	assert_eq(copy.from_dict(unknown), "E_INVALID_NEEDS_STATE")
