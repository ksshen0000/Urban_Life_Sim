extends "res://tests/framework/test_case.gd"
## Sleeping and resting for a chosen length: duration range, per-activity need rates, access rules.

const Sessions := preload("res://tests/framework/session_factory.gd")
const P := SimulationSession.PLAYER_ID

var s: SimulationSession


func before_each() -> void:
	s = Sessions.create()
	s.submit("sign_lease", {"housing_id": "home_shared_room_01"})


func _do(activity_id: String, minutes: int = -1) -> CommandResult:
	var args := {"activity_id": activity_id}
	if minutes > 0:
		args["minutes"] = minutes
	return s.submit("perform_activity", args)


func test_default_length_still_works() -> void:
	var t0 := s.world.clock.get_minute()
	assert_true(_do("activity_sleep").ok)
	assert_eq(s.world.clock.get_minute() - t0, 480)


func test_chosen_length() -> void:
	var t0 := s.world.clock.get_minute()
	assert_true(_do("activity_sleep", 90).ok, "a nap")
	assert_eq(s.world.clock.get_minute() - t0, 90)
	assert_true(_do("activity_phone_news", 15).ok)
	assert_eq(s.world.clock.get_minute() - t0, 105)


func test_length_outside_range_rejected() -> void:
	var t0 := s.world.clock.get_minute()
	assert_eq(_do("activity_sleep", 20).error_code, "E_INVALID_DURATION")
	assert_eq(_do("activity_sleep", 721).error_code, "E_INVALID_DURATION")
	assert_eq(_do("activity_short_videos", 241).error_code, "E_INVALID_DURATION")
	assert_eq(s.world.clock.get_minute(), t0, "nothing happened")


func test_pastimes_have_their_own_rates() -> void:
	var a := Sessions.create()
	var b := Sessions.create()
	var c := Sessions.create()
	for x: SimulationSession in [a, b, c]:
		x.submit("sign_lease", {"housing_id": "home_shared_room_01"})
	a.submit("perform_activity", {"activity_id": "activity_short_videos", "minutes": 120})
	b.submit("perform_activity", {"activity_id": "activity_phone_news", "minutes": 120})
	c.submit("perform_activity", {"activity_id": "activity_home_lie_down", "minutes": 120})
	# start: energy 80, stress 20
	assert_eq(a.needs.get_value(P, "energy"), 76, "videos: -2/h")
	assert_eq(a.needs.get_value(P, "stress"), 6, "videos: -7/h")
	assert_eq(b.needs.get_value(P, "energy"), 82, "news: +1/h")
	assert_eq(b.needs.get_value(P, "stress"), 16, "news: -2/h")
	assert_eq(c.needs.get_value(P, "energy"), 84, "lying down: resting +2/h")
	assert_eq(c.needs.get_value(P, "stress"), 12, "lying down: resting -4/h")
	for x: SimulationSession in [a, b, c]:
		assert_eq(x.needs.get_value(P, "hunger"), 31, "hunger: resting +3/h")


func test_home_pastimes_need_a_home() -> void:
	var homeless := Sessions.create()
	for id in ["activity_short_videos", "activity_phone_news", "activity_home_lie_down", "activity_sleep"]:
		assert_eq(homeless.submit("perform_activity", {"activity_id": id, "minutes": 30}).error_code, "E_NO_HOME", id)


func test_work_rates_unchanged_by_generalized_overrides() -> void:
	# Base rates apply when an activity lists no override (sleep keeps its 90 cap).
	assert_true(_do("activity_sleep", 720).ok)
	assert_eq(s.needs.get_value(P, "energy"), 90)
