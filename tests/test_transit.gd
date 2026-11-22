extends "res://tests/framework/test_case.gd"
## T012 + spec §8.1 #3 InsufficientFunds (transit part) + presence rules (D-020).

const Sessions := preload("res://tests/framework/session_factory.gd")
const P := SimulationSession.PLAYER_ID


func test_ride_to_industrial() -> void:
	var s := Sessions.create()
	var before := s.world.clock.get_minute()
	var r := s.submit("take_route", {"route_id": "route_12_to_industrial"})
	assert_true(r.ok, str(r.error_code))
	assert_eq(s.economy.get_balance(P), Sessions.start_money() - 300)
	assert_eq(s.world.clock.get_minute(), before + 30)
	assert_eq(s.locations.get_map_id(P), "map_industrial")
	assert_eq(s.locations.get_location_id(P), "industrial_bus_stop")
	assert_true(s.submit("take_route", {"route_id": "route_12_to_old_town"}).ok)
	assert_eq(s.locations.get_map_id(P), "map_old_town")


func test_insufficient_funds_changes_nothing() -> void:
	var s := Sessions.create({"starting_money_minor": 200})
	var before := s.world.to_dict()
	assert_eq(s.submit("take_route", {"route_id": "route_12_to_industrial"}).error_code, "E_INSUFFICIENT_FUNDS")
	assert_eq(s.world.to_dict(), before)


func test_service_hours() -> void:
	var s := Sessions.create()
	s.submit("advance_time", {"minutes": 15 * 60}, "system")  # 23:00
	assert_eq(s.submit("take_route", {"route_id": "route_12_to_industrial"}).error_code, "E_NO_DEPARTURE")
	s.submit("advance_time", {"minutes": 7 * 60 - 1}, "system")  # 05:59
	assert_eq(s.submit("take_route", {"route_id": "route_12_to_industrial"}).error_code, "E_NO_DEPARTURE")
	s.submit("advance_time", {"minutes": 1}, "system")
	assert_true(s.submit("take_route", {"route_id": "route_12_to_industrial"}).ok, "first bus 06:00")


func test_wrong_stop() -> void:
	var s := Sessions.create()
	assert_eq(s.submit("take_route", {"route_id": "route_12_to_old_town"}).error_code, "E_NOT_HERE")
	assert_eq(s.submit("take_route", {"route_id": "route_99"}).error_code, "E_UNKNOWN_ROUTE")


func test_presence_gates_shops_and_bench() -> void:
	var s := Sessions.create()
	s.submit("take_route", {"route_id": "route_12_to_industrial"})
	assert_eq(s.submit("buy_item", {"shop_id": "shop_fast_food", "item_id": "item_drink"}).error_code, "E_NOT_HERE")
	assert_eq(s.submit("perform_activity", {"activity_id": "activity_rest"}).error_code, "E_NOT_HERE")


func test_location_state_round_trip_and_validation() -> void:
	var s := Sessions.create()
	s.submit("take_route", {"route_id": "route_12_to_industrial"})
	var loc := LocationSystem.new(Sessions.content())
	assert_eq(loc.from_dict(s.locations.to_dict()), "")
	assert_eq(loc.get_map_id(P), "map_industrial")
	var bad := s.locations.to_dict()
	bad["actors"]["player"]["map_id"] = "map_old_town"  # inconsistent with location
	assert_eq(loc.from_dict(bad), "E_INVALID_LOCATION_STATE")
