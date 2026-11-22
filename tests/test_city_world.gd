extends "res://tests/framework/test_case.gd"
## T005–T008 scene tests on the real city map with real physics frames:
## spawn, 4-direction movement, wall collision, interaction, HUD sync, modal pause, shop /
## inventory / sleep through the UI.

const Sessions := preload("res://tests/framework/session_factory.gd")
const WORLD_SCENE := preload("res://scenes/world/city_world.tscn")
const ACTIONS := ["move_up", "move_down", "move_left", "move_right", "interact", "pause_menu", "open_inventory"]

var session: SimulationSession
var bus: GameEventBus
var world: CityWorld


func _start(overrides: Dictionary = {}) -> void:
	Localizer.install(Sessions.content())
	session = Sessions.create(overrides)
	bus = GameEventBus.new()
	bus.attach(session.processor)
	world = WORLD_SCENE.instantiate()
	world.setup(session, bus)
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	await wait_physics_frames(3)


func after_each() -> void:
	for a: String in ACTIONS:
		Input.action_release(a)
	if world != null:
		world.ui.close()
		world.queue_free()
		await wait_process_frames(2)
	(Engine.get_main_loop() as SceneTree).paused = false
	if bus != null:
		bus.detach(session.processor)
		bus.free()
	world = null
	bus = null


func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	await wait_physics_frames(frames)
	Input.action_release(action)
	await wait_physics_frames(1)


func _press_once(action: String) -> void:
	Input.action_press(action)
	await wait_process_frames(2)
	Input.action_release(action)
	await wait_process_frames(1)


func _place(tile: Vector2i) -> void:
	world.player.position = world.tile_center(tile)
	await wait_physics_frames(2)


## HUD cash text for the starting money + `delta_minor`.
func _cash(delta_minor: int) -> String:
	return "现金 " + MoneyFormat.format_minor(Sessions.start_money() + delta_minor, "CNY", 2)


func _button(node_name: String) -> Button:
	return world.ui.get_panel_content().find_child(GameUi.button_name(node_name), true, false) as Button


# --- T005 ---------------------------------------------------------------------------------

func test_spawns_at_city_default_spawn() -> void:
	await _start()
	assert_eq(world.player.position, world.tile_center(Vector2i(35, 11)), "old_town_bus_stop spawn tile")
	assert_eq(world.ground.get_used_cells().size(), 56 * 32, "whole map built from content")


func test_player_moves() -> void:
	await _start()
	var x0: float = world.player.position.x
	await _hold("move_left", 20)
	assert_true(world.player.position.x < x0 - 20.0, "moved left (%s -> %s)" % [x0, world.player.position.x])


func test_border_wall_blocks() -> void:
	await _start()
	await _place(Vector2i(1, 1))
	await _hold("move_left", 40)
	await _hold("move_up", 40)
	# wall tiles occupy 0..32 px; the feet box is 16 x 10 px above the feet origin
	assert_true(world.player.position.x >= 32.0 + 8.0 - 0.5, "x=%s" % world.player.position.x)
	assert_true(world.player.position.y >= 32.0 + 10.0 - 0.5, "y=%s" % world.player.position.y)


func test_building_blocks() -> void:
	await _start()
	await _place(Vector2i(3, 6))  # just below the apartment wall (rows 2..5)
	await _hold("move_up", 40)
	assert_true(world.player.position.y >= 6 * 32 + 10 - 0.5, "stopped at the building, y=%s" % world.player.position.y)


func test_four_direction_movement_last_pressed_wins() -> void:
	await _start()
	await _place(Vector2i(25, 13))
	var start: Vector2 = world.player.position
	Input.action_press("move_right")
	await wait_physics_frames(2)
	Input.action_press("move_down")
	await wait_physics_frames(10)
	assert_eq(world.player.get_move_direction(), Vector2.DOWN)
	var after_down: Vector2 = world.player.position
	await wait_physics_frames(10)
	assert_eq(world.player.position.x, after_down.x, "no diagonal drift while down is held last")
	Input.action_release("move_down")
	await wait_physics_frames(2)
	assert_eq(world.player.get_move_direction(), Vector2.RIGHT, "falls back to the still-held key")
	assert_true(world.player.position.y > start.y)


func test_sign_in_range_at_spawn_and_interaction_opens_transit() -> void:
	await _start()
	var focus: Interactable = world.player.get_focus()
	assert_not_null(focus, "bus stop sign is next to the spawn")
	if focus == null:
		return
	assert_eq(focus.get_interactable_id(), "sign_bus_stop")
	assert_eq(world.ui.hud.get_prompt_text(), "[E] 公交站牌")
	var seen: Array[String] = []
	world.interacted.connect(func(id: String) -> void: seen.append(id))
	Input.action_press("interact")
	await wait_physics_frames(2)
	Input.action_release("interact")
	assert_eq(seen, ["sign_bus_stop"])
	assert_eq(world.ui.get_panel_kind(), "transit")
	var body := world.ui.get_panel_content().find_child("Body", true, false) as Label
	assert_true(body != null and body.text.contains("12 路"), "sign text shown")
	assert_not_null(_button("Ride_route_12_to_industrial"))


func test_job_board_sign_opens_message_free_reading() -> void:
	await _start()
	await _place(Vector2i(20, 13))
	assert_eq(world.player.get_focus().get_interactable_id(), "sign_job_board")


func test_out_of_range_has_no_prompt() -> void:
	await _start()
	await _place(Vector2i(25, 14))
	assert_eq(world.player.get_focus(), null)
	assert_eq(world.ui.hud.get_prompt_text(), "")


# --- T006 ---------------------------------------------------------------------------------

func test_hud_shows_initial_state() -> void:
	await _start()
	assert_eq(world.ui.hud.get_day_text(), "第 1 天  08:00")
	assert_eq(world.ui.hud.get_cash_text(), _cash(0))
	assert_eq(world.ui.hud.get_need_text("hunger"), "25/100")
	assert_eq(world.ui.hud.get_need_text("energy"), "80/100")
	assert_eq(world.ui.hud.get_need_text("stress"), "20/100")


func test_hud_follows_committed_changes() -> void:
	await _start()
	session.submit("buy_item", {"shop_id": "shop_convenience_store", "item_id": "item_drink"})
	assert_eq(world.ui.hud.get_cash_text(), _cash(-500))
	session.submit("advance_time", {"minutes": 60}, "system")
	assert_eq(world.ui.hud.get_day_text(), "第 1 天  09:00")
	assert_eq(world.ui.hud.get_need_text("hunger"), "29/100")


func test_exploration_time_runs_and_pauses_with_menu() -> void:
	await _start()
	var m0 := session.world.clock.get_minute()
	world._process(5.0)
	assert_eq(session.world.clock.get_minute(), m0 + 5)
	assert_eq(world.ui.hud.get_day_text(), "第 1 天  08:05")
	await _press_once("pause_menu")
	assert_eq(world.ui.get_panel_kind(), "pause")
	assert_true((Engine.get_main_loop() as SceneTree).paused, "tree paused under the menu")
	assert_true(session.world.clock.is_paused())
	world._process(30.0)
	assert_eq(session.world.clock.get_minute(), m0 + 5, "no time passes while paused")
	await _press_once("pause_menu")
	assert_false(world.ui.is_modal())
	assert_false((Engine.get_main_loop() as SceneTree).paused)
	assert_false(session.world.clock.is_paused())


# --- T007 / T008 through the UI -----------------------------------------------------------

func test_shop_ui_buy_until_broke() -> void:
	await _start({"starting_money_minor": 2000})
	world.ui.open_shop("shop_fast_food")
	var buy := _button("Buy_item_simple_meal")
	assert_not_null(buy)
	assert_false(buy.disabled)
	buy.pressed.emit()
	assert_eq(session.economy.get_balance("player"), 200)
	assert_eq(world.ui.hud.get_cash_text(), "现金 ¥2.00")
	var feedback := world.ui.get_panel_content().find_child("Feedback", true, false) as Label
	assert_true(feedback != null and feedback.text.contains("¥18.00"), "purchase confirmed with price")
	assert_true(_button("Buy_item_simple_meal").disabled, "cannot afford a second meal")
	assert_true(_button("Buy_item_drink").disabled, "¥5.00 drink is also out of reach with ¥2.00")


func test_shop_ui_disables_unaffordable_items() -> void:
	await _start({"starting_money_minor": 600})
	world.ui.open_shop("shop_convenience_store")
	assert_true(_button("Buy_item_simple_meal").disabled)
	assert_true(_button("Buy_item_instant_food").disabled)
	assert_false(_button("Buy_item_drink").disabled)
	var body := world.ui.get_panel_content().get_children().filter(
		func(n: Node) -> bool: return n is HBoxContainer and n.find_child("Buy_item_instant_food", true, false) != null)
	assert_eq(body.size(), 1)
	var labels: Array = (body[0] as Node).get_children().filter(func(n: Node) -> bool: return n is Label) \
		.map(func(l: Label) -> String: return l.text)
	assert_has(labels, "钱不够", "unaffordable state is spelled out, not colour-only")


func test_inventory_ui_use_item() -> void:
	await _start()
	session.submit("buy_item", {"shop_id": "shop_fast_food", "item_id": "item_simple_meal"})
	await _press_once("open_inventory")
	assert_eq(world.ui.get_panel_kind(), "inventory")
	_button("Use_item_simple_meal").pressed.emit()
	assert_eq(session.inventory.count("player", "item_simple_meal"), 0)
	assert_eq(world.ui.hud.get_need_text("hunger"), "1/100")
	assert_true(_button("Use_item_simple_meal") == null, "used-up item disappears from the list")


func test_lease_then_sleep_via_apartment_door() -> void:
	await _start()
	await _place(Vector2i(5, 6))  # just below the apartment door
	var focus: Interactable = world.player.get_focus()
	assert_true(focus != null and focus.get_interactable_id() == "door_apartment")
	Input.action_press("interact")
	await wait_physics_frames(2)
	Input.action_release("interact")
	assert_eq(world.ui.get_panel_kind(), "home")
	assert_true(_button("Sleep") == null, "no bed before signing")
	_button("Lease_home_shared_room_01").pressed.emit()
	assert_eq(world.ui.hud.get_cash_text(), _cash(-60000), "deposit paid")
	_button("Sleep").pressed.emit()
	assert_eq(world.ui.get_panel_kind(), "activity", "choose how long to sleep")
	assert_true(_button("Until") == null, "07:00 tomorrow is 23 h away, beyond the 12 h limit")
	_button("Minutes_480").pressed.emit()
	assert_eq(GameClock.format_debug(session.world.clock.get_minute()), "D1 16:00")
	assert_eq(world.ui.get_panel_kind(), "message")
	assert_eq(world.ui.hud.get_day_text(), "第 1 天  16:00")
	assert_eq(world.ui.hud.get_need_text("energy"), "90/100")


func test_bus_ride_switches_map() -> void:
	await _start()
	var maps: Array[String] = []
	world.map_changed.connect(func(id: String) -> void: maps.append(id))
	world.ui.open_transit("old_town_bus_stop")
	_button("Ride_route_12_to_industrial").pressed.emit()
	assert_eq(maps, ["map_industrial"])
	assert_eq(world.map["id"], "map_industrial")
	assert_eq(world.player.position, world.tile_center(Vector2i(28, 12)), "arrived at the industrial stop")
	assert_eq(world.ground.get_used_cells().size(), 32 * 18)
	assert_eq(world.ui.hud.get_cash_text(), _cash(-300))
	assert_eq(world.ui.hud.get_day_text(), "第 1 天  08:30")
	world.ui.close()
	await _place(Vector2i(8, 6))
	assert_eq(world.player.get_focus().get_interactable_id(), "door_warehouse")


func test_job_board_booking_and_work_via_shop_door() -> void:
	await _start()
	world.ui.open_job_board()
	var book := _button("Book_job_convenience_clerk.d2.morning")
	assert_not_null(book)
	assert_false(book.disabled)
	assert_true(_button("Book_job_warehouse_sorter.d2.day") == null, "warehouse not hiring before day 4")
	book.pressed.emit()
	assert_eq(session.jobs.get_shift("job_convenience_clerk.d2.morning")["status"], "booked")
	assert_true(_button("Book_job_convenience_clerk.d2.morning").disabled, "shown as booked")
	world.ui.close()
	session.submit("advance_time", {"minutes": GameClock.minute_from_day_time(2, 8, 50) - session.world.clock.get_minute()}, "system")
	await _place(Vector2i(20, 6))
	Input.action_press("interact")
	await wait_physics_frames(2)
	Input.action_release("interact")
	assert_eq(world.ui.get_panel_kind(), "menu", "shop door offers work and shopping")
	_button("Work").pressed.emit()
	assert_eq(world.ui.get_panel_kind(), "confirm")
	var cash_before := session.economy.get_balance("player")
	_button("Confirm").pressed.emit()
	assert_eq(session.economy.get_balance("player") - cash_before, 8360)
	var body := world.ui.get_panel_content().find_child("Body", true, false) as Label
	assert_true(body.text.contains("¥83.60"), body.text)
	assert_eq(world.ui.hud.get_day_text(), "第 2 天  13:00")


func test_shop_door_opens_shop() -> void:
	await _start()
	await _place(Vector2i(20, 6))
	Input.action_press("interact")
	await wait_physics_frames(2)
	Input.action_release("interact")
	assert_eq(world.ui.get_panel_kind(), "shop")
	var title := world.ui.get_panel_content().find_child("Title", true, false) as Label
	assert_eq(title.text, "转角便利店")


func test_start_map_has_spawn_for_default_spawn() -> void:
	# Cross-file rule not expressible in the schema: guarded here for the shipped city.
	var content := Sessions.content()
	for city in content.get_records("cities"):
		var map := content.get_record("maps", city["start_map_id"])
		assert_ne(CityMapBuilder.spawn_tile(map, city["default_spawn"]), Vector2i(-1, -1), city["id"])


# --- T005b: 3/4 view ----------------------------------------------------------------------

func test_structures_trees_and_props_are_y_sorted_entities() -> void:
	await _start()
	assert_true(world.entities.y_sort_enabled)
	assert_eq(world.structures.size(), 8)
	assert_not_null(world.entities.get_node_or_null("tree_3_12"), "tree prop from the 'T' cell")
	var apt := world.get_structure("bld_apartment")
	assert_eq(apt.position, Vector2(2 * 32, 6 * 32), "anchored at the footprint's bottom edge")


func test_player_in_front_of_and_behind_a_building() -> void:
	await _start()
	var apt := world.get_structure("bld_apartment")
	await _place(Vector2i(5, 6))
	for i in 10:
		world._process(0.0)
	assert_true(world.player.position.y > apt.position.y, "in front: drawn over the facade")
	assert_false(apt.is_faded())
	await _place(Vector2i(5, 1))  # the walkway behind the apartment, under its roof overhang
	for i in 10:
		world._process(0.0)
	assert_true(world.player.position.y < apt.position.y, "behind: the building sorts over the player")
	assert_true(apt.is_faded(), "building fades so the player stays visible")
	await _place(Vector2i(12, 1))  # behind the gap between buildings
	for i in 10:
		world._process(0.0)
	assert_false(apt.is_faded())


# --- M3: NPCs, story, tutorial in the scene -----------------------------------------------

func test_npcs_appear_by_schedule_and_can_be_talked_to() -> void:
	await _start()
	world._process(0.0)
	assert_eq(world.npcs.keys().size(), 2, "Chen at the store, Wang in the park at 08:00")
	var chen: NpcActor = world.npcs["npc_chen_yu"]
	assert_eq(chen.position, CityMapBuilder.tile_foot(world.map, Vector2i(21, 6)), "next to the store anchor")
	await _place(Vector2i(22, 6))
	assert_eq(world.player.get_focus().get_interactable_id(), "npc_chen_yu")
	assert_eq(world.ui.hud.get_prompt_text(), "[E] 陈雨")
	Input.action_press("interact")
	await wait_physics_frames(2)
	Input.action_release("interact")
	assert_eq(world.ui.get_panel_kind(), "dialogue")
	_button("Choice_thanks").pressed.emit()
	assert_eq(session.relationships.get_value("npc_chen_yu"), 5)
	assert_false(world.ui.is_modal())
	session.submit("advance_time", {"minutes": 9 * 60}, "system")  # 17:00: Chen moved to the park
	world._process(0.0)
	assert_eq(world.npcs["npc_chen_yu"].location_id_of(), "park")


func test_story_entries_pop_up_and_hud_shows_objective() -> void:
	Localizer.install(Sessions.content())
	session = Sessions.create({"story_enabled": true})
	bus = GameEventBus.new()
	bus.attach(session.processor)
	session.run_story_rules()
	world = WORLD_SCENE.instantiate()
	world.setup(session, bus)
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	await wait_physics_frames(2)
	world._process(0.0)
	assert_eq(world.ui.get_panel_kind(), "dialogue", "arrival narration shown")
	var title := world.ui.get_panel_content().find_child("Title", true, false) as Label
	assert_eq(title.text, "旁白")
	await _press_once("pause_menu")
	assert_eq(world.ui.get_panel_kind(), "pause", "Esc on a story entry opens the pause menu (no trap)")
	await _press_once("pause_menu")
	world._process(0.0)
	assert_eq(world.ui.get_panel_kind(), "dialogue", "the unanswered story entry comes back")
	_button("Choice_go").pressed.emit()
	assert_false(world.ui.is_modal())
	assert_eq(world.ui.hud.get_objective_text(), "目标：租下住处")
	session.submit("sign_lease", {"housing_id": "home_shared_room_01"})
	assert_eq(world.ui.hud.get_objective_text(), "目标：预约一个班次")
	await _press_once("open_journal")
	assert_eq(world.ui.get_panel_kind(), "journal")
	var texts: Array = world.ui.get_panel_content().get_children().filter(func(n: Node) -> bool: return n is Label) \
		.map(func(l: Label) -> String: return l.text)
	assert_has(texts, "✓ 租下住处")
	assert_has(texts, "→ 预约一个班次")
	await _press_once("open_journal")
	assert_false(world.ui.is_modal())


func test_home_rest_choices_and_sleep_until_morning() -> void:
	await _start()
	session.submit("sign_lease", {"housing_id": "home_shared_room_01"})
	world.ui.open_home("old_town_apartment")
	_button("Rest").pressed.emit()
	assert_eq(world.ui.get_panel_kind(), "home_rest")
	for id in ["activity_home_lie_down", "activity_phone_news", "activity_short_videos"]:
		assert_not_null(_button("Rest_" + id), id)
	assert_true(_button("Rest_activity_rest") == null, "the park bench is not at home")
	_button("Rest_activity_short_videos").pressed.emit()
	assert_eq(world.ui.get_panel_kind(), "activity")
	var stress0 := session.needs.get_value("player", "stress")
	var energy0 := session.needs.get_value("player", "energy")
	_button("Minutes_60").pressed.emit()
	assert_eq(GameClock.format_debug(session.world.clock.get_minute()), "D1 09:00")
	assert_true(session.needs.get_value("player", "stress") < stress0, "short videos relax")
	assert_true(session.needs.get_value("player", "energy") < energy0, "but tire you out")
	world.ui.close()
	session.submit("advance_time", {"minutes": 13 * 60 + 17}, "system")  # 22:17
	world.ui.open_activity("activity_sleep")
	var until := _button("Until")
	assert_true(until.text.contains("07:00"), until.text)
	until.pressed.emit()
	assert_eq(GameClock.format_debug(session.world.clock.get_minute()), "D2 07:00")


func test_sleep_options_warn_about_booked_shift() -> void:
	await _start()
	session.submit("sign_lease", {"housing_id": "home_shared_room_01"})
	session.submit("book_shift", {"job_id": "job_convenience_clerk", "day": 2, "template_id": "morning"})
	session.submit("advance_time", {"minutes": 15 * 60}, "system")  # 23:00
	world.ui.open_activity("activity_sleep")
	assert_false(_button("Minutes_480").text.contains("耽误"), "until 07:00 is fine for a 09:00 shift")
	assert_true(_button("Minutes_600").text.contains("耽误"), "until 09:00 is late")
