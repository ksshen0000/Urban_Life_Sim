extends "res://tests/framework/test_case.gd"
## D-035: walking on from the old town into Xinhe (building site, barber, old compound), the
## Route 1 bus to downtown (towers, luxury shops, café), and the day / night cycle.

const Sessions := preload("res://tests/framework/session_factory.gd")
const WORLD_SCENE := preload("res://scenes/world/city_world.tscn")
const P := SimulationSession.PLAYER_ID

var world: CityWorld
var bus: GameEventBus


func after_each() -> void:
	for a in ["move_right", "move_left"]:
		Input.action_release(a)
	if world != null:
		world.ui.close()
		world.queue_free()
		await wait_process_frames(2)
	world = null
	(Engine.get_main_loop() as SceneTree).paused = false
	if bus != null:
		bus.free()
	bus = null


func _open(s: SimulationSession) -> void:
	Localizer.install(Sessions.content())
	bus = GameEventBus.new()
	bus.attach(s.processor)
	world = WORLD_SCENE.instantiate()
	world.setup(s, bus)
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	await wait_physics_frames(3)


func _walk_until_map_changes(action: String) -> void:
	var start: String = world.map["id"]
	Input.action_press(action)
	for i in 120:
		await wait_physics_frames(1)
		if world.map["id"] != start:
			break
	Input.action_release(action)
	await wait_process_frames(2)


func test_walk_east_into_xinhe_and_back() -> void:
	var s := Sessions.create()
	await _open(s)
	world.player.position = world.tile_center(Vector2i(53, 8))
	await _walk_until_map_changes("move_right")
	assert_eq(world.map["id"], "map_xinhe", "walked off the end of Old Street")
	assert_eq(world.player_tile(), Vector2i(2, 8), "arrived at the Xinhe crossing")
	assert_eq(s.world.clock.get_minute(), GameClock.minute_from_day_time(1, 8), "walking over takes no clock time")
	await _walk_until_map_changes("move_left")
	assert_eq(world.map["id"], "map_old_town", "and back")
	assert_eq(world.player_tile(), Vector2i(53, 8))


func test_construction_job_in_xinhe() -> void:
	var s := Sessions.create()
	s.submit("advance_time", {"minutes": GameClock.minute_from_day_time(1, 20) - s.world.clock.get_minute()}, "system")
	assert_true(s.submit("book_shift", {"job_id": "job_construction_labor", "day": 2, "template_id": "day"}).ok)
	s.submit("advance_time", {"minutes": GameClock.minute_from_day_time(2, 6, 50) - s.world.clock.get_minute()}, "system")
	assert_eq(s.submit("work_shift", {"shift_id": JobsSystem.shift_id_for("job_construction_labor", 2, "day")}).error_code, "E_NOT_HERE")
	assert_true(Sessions.go(s, "construction_site"), "walk over to the site")
	var energy := s.needs.get_value(P, "energy")
	var r := s.submit("work_shift", {"shift_id": JobsSystem.shift_id_for("job_construction_labor", 2, "day")})
	assert_true(r.ok, str(r.error_code))
	assert_eq(s.jobs.get_shift(JobsSystem.shift_id_for("job_construction_labor", 2, "day"))["gross_minor"], 3800 * 6)
	assert_eq(s.needs.get_value(P, "energy"), maxi(energy - 66, 0), "-11 energy an hour for 6 hours: the hardest job there is")


func test_barber() -> void:
	var s := Sessions.create()
	var args := {"barber_id": "door_barber", "hair_style": "bob", "hair": "#a83a3a"}
	assert_eq(s.submit("get_haircut", args).error_code, "E_NOT_HERE")
	Sessions.go(s, "barber_shop")
	var cash := s.economy.get_balance(P)
	var t := s.world.clock.get_minute()
	assert_true(s.submit("get_haircut", args).ok)
	assert_eq(cash - s.economy.get_balance(P), 3000)
	assert_eq(s.world.clock.get_minute() - t, 30)
	assert_eq(s.profile.get_look(P)["hair_style"], "bob")
	assert_eq(s.profile.get_look(P)["hair"], "#a83a3a")
	assert_eq(s.profile.get_look(P)["top"], ProfileSystem.DEFAULT_LOOK["top"], "only the hair changes")
	assert_eq(s.submit("get_haircut", {"barber_id": "door_barber", "hair_style": "mohawk", "hair": "#000000"}).error_code, "E_INVALID_ARGUMENTS")
	var poor := Sessions.create({"starting_money_minor": 1000})
	Sessions.go(poor, "barber_shop")
	assert_eq(poor.submit("get_haircut", args).error_code, "E_INSUFFICIENT_FUNDS")


func test_bus_to_downtown_luxury_and_cafe() -> void:
	var s := Sessions.create({"starting_money_minor": 2000000})
	assert_true(s.submit("take_route", {"route_id": "route_1_to_downtown"}).ok)
	assert_eq(s.locations.get_map_id(P), "map_downtown")
	assert_eq(GameClock.format_debug(s.world.clock.get_minute()), "D1 08:35")
	assert_true(s.submit("buy_item", {"shop_id": "shop_downtown_cafe", "item_id": "item_latte", "quantity": 1}).ok)
	assert_true(s.submit("use_item", {"item_id": "item_latte"}).ok, "a latte is drunk")
	assert_eq(s.submit("buy_item", {"shop_id": "shop_watch_store", "item_id": "item_luxury_watch", "quantity": 1}).error_code,
		"E_INSUFFICIENT_FUNDS", "¥36,000 is out of reach")
	assert_true(s.submit("buy_item", {"shop_id": "shop_luxury_boutique", "item_id": "item_luxury_bag", "quantity": 1}).ok)
	assert_eq(s.submit("use_item", {"item_id": "item_luxury_bag"}).error_code, "E_NOT_USABLE", "a bag is kept, not used up")
	assert_eq(s.inventory.count(P, "item_luxury_bag"), 1)
	assert_eq(s.submit("perform_activity", {"activity_id": "activity_window_shopping", "minutes": 60}).error_code,
		"E_ACTIVITY_CLOSED", "the mall opens at 10:00")
	s.submit("advance_time", {"minutes": GameClock.minute_from_day_time(1, 10) - s.world.clock.get_minute()}, "system")
	assert_true(s.submit("perform_activity", {"activity_id": "activity_window_shopping", "minutes": 60}).ok)
	assert_true(s.submit("take_route", {"route_id": "route_1_to_old_town"}).ok)
	assert_eq(s.locations.get_map_id(P), "map_old_town")


func test_keepsake_has_no_use_button() -> void:
	var s := Sessions.create({"starting_money_minor": 2000000})
	s.submit("take_route", {"route_id": "route_1_to_downtown"})
	s.submit("buy_item", {"shop_id": "shop_luxury_boutique", "item_id": "item_perfume", "quantity": 1})
	await _open(s)
	assert_eq(world.map["id"], "map_downtown")
	world.ui.open_inventory()
	var c := world.ui.get_panel_content()
	assert_true(c.find_child("Use_item_perfume", true, false) == null)


func test_day_cycle() -> void:
	assert_eq(DayCycle.phase(6 * 60), "morning")
	assert_eq(DayCycle.phase(12 * 60), "day")
	assert_eq(DayCycle.phase(18 * 60), "dusk")
	assert_eq(DayCycle.phase(22 * 60), "night")
	assert_eq(DayCycle.phase(2 * 60), "night")
	assert_eq(DayCycle.tint(12 * 60), Color(1, 1, 1))
	assert_eq(DayCycle.darkness(12 * 60), 0.0)
	assert_true(DayCycle.darkness(23 * 60) > 0.8)
	assert_true(DayCycle.darkness(18 * 60) > 0.0 and DayCycle.darkness(18 * 60) < DayCycle.darkness(23 * 60))


func test_night_outdoors_but_lit_indoors() -> void:
	var s := Sessions.create()
	s.submit("advance_time", {"minutes": 15 * 60}, "system")  # 23:00
	await _open(s)
	await wait_process_frames(2)
	assert_eq(world.ui.hud.get_phase_text(), "夜里")
	assert_true(world.day_night.get_tint().v < 0.8, "the street is dark")
	assert_true(world.day_night.get_glow_strength() > 0.8, "lamps and windows glow")
	var s2 := Sessions.create()
	s2.submit("advance_time", {"minutes": 15 * 60 - 60}, "system")  # 22:00, store still has a door
	Sessions.go(s2, "convenience_store")
	world.queue_free()
	await wait_process_frames(2)
	bus.free()
	bus = null
	await _open(s2)
	await wait_process_frames(2)
	assert_eq(world.day_night.get_tint(), Color.WHITE, "indoors stays lamp-lit")
	assert_eq(world.day_night.get_glow_strength(), 0.0)


## Night light must respect depth: window glow belongs to its building (so people in front of the
## building cover it) and lamp pools lie under the entities.
func test_night_light_layering() -> void:
	var s := Sessions.create()
	s.submit("advance_time", {"minutes": 14 * 60}, "system")  # 22:00
	await _open(s)
	var store := world.get_structure("bld_convenience_store")
	assert_not_null(store.get_node_or_null("WindowGlow"), "glow is a child of the building, y-sorted with it")
	var ground_glow := world.get_node("GroundGlow")
	assert_true(ground_glow.get_index() < world.entities.get_index(), "lamp pools are drawn under people")
	assert_eq(world.player.self_modulate, world.day_night.get_tint(), "people are darkened like the street")
	assert_true(DayNight.glow_strength > 0.5)
