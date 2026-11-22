extends "res://tests/framework/test_case.gd"
## T011 + spec §8.1 #6 RentDue: on-time billing, overdue without negative balance, no double
## charges across fast-forwards or save/load.

const Sessions := preload("res://tests/framework/session_factory.gd")
const Grant := preload("res://tests/framework/grant_handler.gd")
const P := SimulationSession.PLAYER_ID
const HOME := "home_shared_room_01"


func _session(money: int = 150000) -> SimulationSession:
	var s := Sessions.create({"starting_money_minor": money})
	s.processor.register_handler(Grant.new())
	return s


func _to_day(s: SimulationSession, day: int, hour: int = 8) -> void:
	assert_true(s.submit("advance_time", {"minutes": GameClock.minute_from_day_time(day, hour) - s.world.clock.get_minute()}, "system").ok)


func _events(s: SimulationSession, type: String) -> Array:
	return s.processor.get_event_log().filter(func(e: DomainEvent) -> bool: return e.type == type)


func test_sign_lease_pays_deposit() -> void:
	var s := _session()
	var r := s.submit("sign_lease", {"housing_id": HOME})
	assert_true(r.ok, str(r.error_code))
	assert_eq(s.economy.get_balance(P), 90000)
	assert_eq(s.housing.get_lease(P)["next_due_day"], 7)
	assert_eq(s.submit("sign_lease", {"housing_id": HOME}).error_code, "E_ALREADY_LEASED")


func test_sign_lease_requirements() -> void:
	var poor := _session(50000)
	assert_eq(poor.submit("sign_lease", {"housing_id": HOME}).error_code, "E_INSUFFICIENT_FUNDS")
	assert_eq(poor.economy.get_balance(P), 50000)
	var away := _session()
	away.submit("take_route", {"route_id": "route_12_to_industrial"})
	assert_eq(away.submit("sign_lease", {"housing_id": HOME}).error_code, "E_NOT_HERE")


func test_reminder_and_collection_on_due_day() -> void:
	var s := _session()
	s.submit("sign_lease", {"housing_id": HOME})
	_to_day(s, 6)
	assert_eq(_events(s, "rent_reminder").size(), 1)
	assert_eq(s.economy.get_balance(P), 90000)
	_to_day(s, 7)
	assert_eq(s.economy.get_balance(P), 30000, "¥600 collected at the start of day 7")
	var paid := _events(s, "rent_paid")
	assert_eq(paid.size(), 1)
	assert_eq(paid[0].game_minute, GameClock.minute_from_day_time(7, 0), "collected at midnight")
	assert_eq(s.housing.get_lease(P)["next_due_day"], 14)


func test_fast_forward_settles_every_period_once() -> void:
	var s := _session(500000)
	s.submit("sign_lease", {"housing_id": HOME})
	s.submit("advance_time", {"minutes": 20 * GameClock.MINUTES_PER_DAY}, "system")  # day 1 -> day 21
	assert_eq(_events(s, "rent_paid").size(), 3, "days 7, 14 and 21")
	assert_eq(s.economy.get_balance(P), 500000 - 60000 - 3 * 60000)
	assert_eq(s.housing.get_lease(P)["periods_paid"], 3)


func test_overdue_never_goes_negative_and_recovers() -> void:
	var s := _session(100000)
	s.submit("sign_lease", {"housing_id": HOME})  # 40000 left
	_to_day(s, 7)
	assert_eq(s.economy.get_balance(P), 40000, "not charged")
	assert_true(s.housing.is_overdue(P))
	assert_eq(s.housing.get_lease(P)["overdue_since_day"], 7)
	assert_eq(s.submit("pay_rent").error_code, "E_INSUFFICIENT_FUNDS")
	_to_day(s, 8)
	assert_eq(s.economy.get_balance(P), 40000)
	assert_eq(s.housing.get_lease(P)["overdue_since_day"], 7, "overdue since the first missed day")
	s.submit("test_grant", {"amount": 30000})
	assert_true(s.submit("pay_rent").ok)
	assert_eq(s.economy.get_balance(P), 10000)
	assert_false(s.housing.is_overdue(P))
	assert_eq(s.housing.get_lease(P)["next_due_day"], 14)
	assert_eq(s.submit("pay_rent").error_code, "E_NOTHING_DUE")


func test_overdue_is_collected_automatically_when_money_arrives() -> void:
	var s := _session(100000)
	s.submit("sign_lease", {"housing_id": HOME})
	_to_day(s, 7)
	s.submit("test_grant", {"amount": 30000})
	_to_day(s, 8)
	assert_false(s.housing.is_overdue(P), "retried at the start of day 8")
	assert_eq(s.economy.get_balance(P), 10000)


func test_reload_does_not_charge_again() -> void:
	var s := _session()
	s.submit("sign_lease", {"housing_id": HOME})
	_to_day(s, 7, 9)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.world.to_dict()))
	var loaded := _session()
	assert_eq(loaded.world.from_dict(saved), "")
	assert_eq(loaded.economy.get_balance(P), 30000)
	loaded.submit("advance_time", {"minutes": 600}, "system")  # rest of day 7
	assert_eq(loaded.economy.get_balance(P), 30000, "day 7 rent already paid before the save")
	assert_eq(loaded.housing.get_lease(P)["periods_paid"], 1)


func test_rent_goes_through_region_policy() -> void:
	var s := _session()
	assert_eq(HousingSystem.rent_due(s.policy, Sessions.content().get_record("housing", HOME), P), 60000)
