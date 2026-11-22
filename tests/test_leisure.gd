extends "res://tests/framework/test_case.gd"
## Leisure around the old town: arcade and billiards (paid by the hour, opening hours), the park's
## chess, singing, tai chi and square dancing (free, at set times), and the park regulars who show
## up exactly while those activities are on.

const Sessions := preload("res://tests/framework/session_factory.gd")
const WORLD_SCENE := preload("res://scenes/world/city_world.tscn")
const P := SimulationSession.PLAYER_ID

var world: CityWorld
var bus: GameEventBus


func after_each() -> void:
	if world != null:
		world.ui.close()
		world.queue_free()
		await wait_process_frames(2)
	world = null
	(Engine.get_main_loop() as SceneTree).paused = false
	if bus != null:
		bus.free()
	bus = null


func _at(day: int, hour: int, minute: int = 0, overrides: Dictionary = {}) -> SimulationSession:
	var s := Sessions.create(overrides)
	var target := GameClock.minute_from_day_time(day, hour, minute)
	if target > s.world.clock.get_minute():
		s.submit("advance_time", {"minutes": target - s.world.clock.get_minute()}, "system")
	return s


func _do(s: SimulationSession, id: String, minutes: int) -> CommandResult:
	return s.submit("perform_activity", {"activity_id": id, "minutes": minutes})


func test_rules_hours_and_price() -> void:
	var arcade := Sessions.content().get_record("activities", "activity_arcade_games")
	assert_false(ActivityRules.is_open(arcade, 9 * 60 + 59))
	assert_true(ActivityRules.is_open(arcade, 10 * 60))
	assert_eq(ActivityRules.minutes_left(arcade, 23 * 60 + 30), 30)
	assert_eq(ActivityRules.cost_minor(arcade, 60), 1500)
	assert_eq(ActivityRules.cost_minor(arcade, 50), 1250)
	assert_eq(ActivityRules.cost_minor({"price_per_hour_minor": 1000}, 1), 17, "rounded up to the fen")
	assert_eq(ActivityRules.cost_minor({}, 120), 0, "free")
	assert_eq(ActivityRules.hours_text(Sessions.content().get_record("activities", "activity_park_singing")),
		"07:00–10:00, 18:00–21:00")
	assert_true(ActivityRules.is_open({}, 3 * 60), "no hours = always")


func test_arcade_charges_by_the_hour() -> void:
	var s := _at(1, 8)
	assert_eq(_do(s, "activity_arcade_games", 60).error_code, "E_ACTIVITY_CLOSED", "opens at 10:00")
	s.submit("advance_time", {"minutes": 120}, "system")
	var cash := s.economy.get_balance(P)
	var stress := s.needs.get_value(P, "stress")
	assert_true(_do(s, "activity_arcade_games", 60).ok)
	assert_eq(cash - s.economy.get_balance(P), 1500)
	assert_true(s.needs.get_value(P, "stress") < stress)
	assert_true(s.economy.get_ledger(P).any(func(e: Dictionary) -> bool: return e["reason"] == "activity:activity_arcade_games"))
	assert_true(_do(s, "activity_dance_machine", 15).ok)
	assert_eq(cash - s.economy.get_balance(P), 1500 + 600)


func test_cannot_play_past_closing_or_without_money() -> void:
	var s := _at(1, 23, 30)
	assert_eq(_do(s, "activity_billiards", 60).error_code, "E_CLOSES_BEFORE_END")
	assert_true(_do(s, "activity_billiards", 30).ok)
	var poor := _at(1, 13, 0, {"starting_money_minor": 500})
	var t0 := poor.world.clock.get_minute()
	assert_eq(_do(poor, "activity_billiards", 60).error_code, "E_INSUFFICIENT_FUNDS")
	assert_eq(poor.world.clock.get_minute(), t0, "nothing happened")
	assert_eq(poor.economy.get_balance(P), 500)


func test_must_be_in_the_old_town() -> void:
	var s := _at(1, 11)
	s.submit("take_route", {"route_id": "route_12_to_industrial"})
	assert_eq(_do(s, "activity_arcade_games", 30).error_code, "E_NOT_HERE")
	assert_eq(_do(s, "activity_watch_chess", 30).error_code, "E_NOT_HERE")


func test_park_activities_follow_the_day() -> void:
	var s := _at(1, 8)
	assert_true(_do(s, "activity_park_singing", 30).ok, "morning singing")
	assert_true(_do(s, "activity_watch_chess", 30).ok, "chess from 08:00")
	assert_eq(_do(s, "activity_square_dance", 30).error_code, "E_ACTIVITY_CLOSED", "dancing is in the evening")
	var cash := s.economy.get_balance(P)
	s.submit("advance_time", {"minutes": GameClock.minute_from_day_time(1, 19) - s.world.clock.get_minute()}, "system")
	assert_true(_do(s, "activity_square_dance", 60).ok)
	assert_eq(s.economy.get_balance(P), cash, "the park is free")
	assert_eq(_do(s, "activity_tai_chi", 30).error_code, "E_ACTIVITY_CLOSED", "tai chi is early morning")


func _open_world(s: SimulationSession) -> void:
	Localizer.install(Sessions.content())
	bus = GameEventBus.new()
	world = WORLD_SCENE.instantiate()
	world.setup(s, bus)
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	await wait_physics_frames(3)


func test_park_regulars_appear_with_their_activities() -> void:
	var s := _at(1, 8)
	await _open_world(s)
	assert_true(world.ambient.has("chess_a_left"), "chess players out at 08:00")
	assert_true(world.ambient.has("taichi_1"), "tai chi until 09:00")
	assert_true(world.ambient.has("sing_1"), "morning singing")
	assert_false(world.ambient.has("dance_1"))
	assert_true(world.ambient.has("fisher"))
	s.submit("advance_time", {"minutes": 11 * 60 + 30}, "system")  # 19:30
	await wait_process_frames(2)
	assert_true(world.ambient.has("dance_1"), "square dancing at 19:30")
	assert_false(world.ambient.has("chess_a_left"), "chess players went home")
	assert_false(world.ambient.has("taichi_1"))
	assert_true(world.ambient.has("sing_2"), "evening singing")
	assert_false(world.ambient.has("fisher"), "fisher left at 18:00")
	assert_not_null(world.entities.get_node_or_null("pavilion_0"), "decor built")


func test_arcade_door_lists_machines_and_charges() -> void:
	var s := _at(1, 8)
	await _open_world(s)
	world.player.position = world.tile_center(Vector2i(43, 6))
	await wait_physics_frames(2)
	assert_eq(world.player.get_focus().get_interactable_id(), "door_arcade")
	Input.action_press("interact")
	await wait_physics_frames(2)
	Input.action_release("interact")
	assert_eq(world.ui.get_panel_kind(), "activity_menu")
	var games := world.ui.get_panel_content().find_child("Act_activity_arcade_games", true, false) as Button
	assert_true(games.disabled, "closed before 10:00")
	world.ui.close()
	s.submit("advance_time", {"minutes": 150}, "system")  # 10:30
	world.ui.open_activity_menu("星光游戏厅", ["activity_arcade_games", "activity_dance_machine"])
	games = world.ui.get_panel_content().find_child("Act_activity_arcade_games", true, false) as Button
	assert_false(games.disabled)
	games.pressed.emit()
	assert_eq(world.ui.get_panel_kind(), "activity")
	var hour := world.ui.get_panel_content().find_child("Minutes_60", true, false) as Button
	assert_true(hour.text.contains("¥15.00"), hour.text)
	var cash := s.economy.get_balance(P)
	hour.pressed.emit()
	assert_eq(cash - s.economy.get_balance(P), 1500)
	var body := world.ui.get_panel_content().find_child("Body", true, false) as Label
	assert_true(body.text.contains("¥15.00"), "receipt shown: " + body.text)


func test_late_evening_only_offers_what_fits() -> void:
	var s := _at(1, 23, 15)
	await _open_world(s)
	world.ui.open_activity("activity_billiards")
	var c := world.ui.get_panel_content()
	assert_not_null(c.find_child("Minutes_30", true, false))
	assert_true(c.find_child("Minutes_60", true, false) == null, "would run past midnight")


func test_menus_with_wrapped_descriptions_are_not_cut_off() -> void:
	var s := _at(1, 10, 30)
	s.submit("sign_lease", {"housing_id": "home_shared_room_01"})
	await _open_world(s)
	for open: Callable in [world.ui.open_activity_menu.bind("星光游戏厅", ["activity_arcade_games", "activity_dance_machine"]),
			world.ui.open_home_rest.bind("old_town_apartment")]:
		open.call()
		await wait_process_frames(3)
		var scroll := world.ui.get_panel_content().get_parent() as ScrollContainer
		var need := world.ui.get_panel_content().get_combined_minimum_size().y
		assert_true(need <= GameUi.MAX_PANEL_HEIGHT, "fits without scrolling (%.0f)" % need)
		assert_true(scroll.size.y >= need - 1.0, "%s: panel %.0f tall, content %.0f" % [world.ui.get_panel_kind(), scroll.size.y, need])
		world.ui.close()
