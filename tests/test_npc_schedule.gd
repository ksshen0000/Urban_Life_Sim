extends "res://tests/framework/test_case.gd"
## T013: NPC whereabouts follow their schedules; consistent after time skips and map changes.

const Sessions := preload("res://tests/framework/session_factory.gd")


func _at(day: int, hour: int, minute: int = 0) -> int:
	return GameClock.minute_from_day_time(day, hour, minute)


func test_location_follows_schedule() -> void:
	var sched := NpcScheduleSystem.new(Sessions.content())
	assert_eq(sched.location_of("npc_chen_yu", _at(1, 7, 59)), "", "at home before 08:00")
	assert_eq(sched.location_of("npc_chen_yu", _at(1, 8)), "convenience_store")
	assert_eq(sched.location_of("npc_chen_yu", _at(3, 15, 59)), "convenience_store")
	assert_eq(sched.location_of("npc_chen_yu", _at(3, 16)), "", "between slots: walking home")
	assert_eq(sched.location_of("npc_chen_yu", _at(3, 17)), "park")
	assert_eq(sched.location_of("npc_landlord_wang", _at(2, 12)), "old_town_apartment")
	assert_eq(sched.location_of("npc_lao_zhou", _at(5, 10)), "industrial_warehouse")
	assert_eq(sched.location_of("npc_lao_zhou", _at(5, 20, 30)), "fast_food_restaurant")
	assert_eq(sched.location_of("npc_nobody", _at(1, 9)), "")


func test_present_on_map() -> void:
	var sched := NpcScheduleSystem.new(Sessions.content())
	assert_eq(sched.present_on_map("map_old_town", _at(1, 9)), {"npc_landlord_wang": "park"})
	assert_eq(sched.present_on_map("map_convenience_interior", _at(1, 9)), {"npc_chen_yu": "convenience_store"},
		"Chen works inside the store (D-034)")
	assert_eq(sched.present_on_map("map_industrial", _at(1, 9)), {"npc_lao_zhou": "industrial_warehouse"})
	assert_eq(sched.present_on_map("map_old_town", _at(1, 23)), {})


func test_session_view_matches_player_map() -> void:
	var s := Sessions.create()
	s.submit("advance_time", {"minutes": 60}, "system")  # 09:00
	assert_eq(s.present_npcs(), {"npc_landlord_wang": "park"})
	s.submit("take_route", {"route_id": "route_12_to_industrial"})
	assert_eq(s.present_npcs(), {"npc_lao_zhou": "industrial_warehouse"})
	s.submit("take_route", {"route_id": "route_12_to_old_town"})
	Sessions.go(s, "convenience_store")
	assert_eq(s.present_npcs(), {"npc_chen_yu": "convenience_store"}, "same answer after coming back, inside the store")


func test_every_schedule_location_has_an_anchor() -> void:
	var content := Sessions.content()
	for npc in content.get_records("npcs"):
		for slot: Dictionary in npc["schedule"]:
			var loc := content.get_record("locations", slot["location_id"])
			var map := content.get_record("maps", loc["map_id"])
			assert_ne(CityMapBuilder.spawn_tile(map, loc["id"]), Vector2i(-1, -1), "%s @ %s" % [npc["id"], loc["id"]])
