extends "res://tests/framework/test_case.gd"
## D-039: passers-by walking their routes (and their line of chat), and the one-day strangers
## (Xiao Wu's wallet, lost Doudou, Granny Liu) with their choices and consequences.

const Sessions := preload("res://tests/framework/session_factory.gd")
const ContentFixture := preload("res://tests/framework/content_fixture.gd")
const WORLD_SCENE := preload("res://scenes/world/city_world.tscn")
const P := SimulationSession.PLAYER_ID
const MAP := "regions/cn/cities/linchuan/maps/old_town.json"

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
	s.submit("advance_time", {"minutes": GameClock.minute_from_day_time(day, hour, minute) - s.world.clock.get_minute()}, "system")
	return s


func _choose(s: SimulationSession, tree: String, node: String, choice: String) -> CommandResult:
	return s.submit("choose_dialogue", {"tree_id": tree, "node_id": node, "choice_id": choice})


# --- strangers --------------------------------------------------------------------------------

func test_strangers_only_on_their_day() -> void:
	var sched := NpcScheduleSystem.new(Sessions.content())
	assert_eq(sched.location_of("npc_xiao_wu", GameClock.minute_from_day_time(2, 8, 30)), "old_town_bus_stop")
	assert_eq(sched.location_of("npc_xiao_wu", GameClock.minute_from_day_time(3, 8, 30)), "", "only on day 2")
	assert_eq(sched.location_of("npc_doudou", GameClock.minute_from_day_time(3, 17)), "park")
	assert_eq(sched.location_of("npc_doudou", GameClock.minute_from_day_time(4, 17)), "")
	assert_eq(sched.location_of("npc_granny_liu", GameClock.minute_from_day_time(4, 7, 30)), "old_town_east_end")


func test_wallet_take_the_reward_or_not() -> void:
	var a := _at(2, 8, 30)
	var cash := a.economy.get_balance(P)
	assert_true(_choose(a, "dialogue_xiao_wu_intro", "start", "help").ok)
	assert_true(_choose(a, "dialogue_xiao_wu_intro", "found", "accept").ok)
	assert_eq(a.economy.get_balance(P) - cash, 2000, "he insists on twenty yuan")
	var b := _at(2, 8, 30)
	var stress := b.needs.get_value(P, "stress")
	_choose(b, "dialogue_xiao_wu_intro", "start", "help")
	assert_true(_choose(b, "dialogue_xiao_wu_intro", "found", "refuse").ok)
	assert_true(b.relationships.get_value("npc_xiao_wu") > a.relationships.get_value("npc_xiao_wu"), "refusing earns more respect")
	assert_true(b.needs.get_value(P, "stress") < stress, "and feels good")
	assert_eq(b.flags.get_flag("story.refused_reward"), true)


func test_lost_kid_grandma_gives_a_rice_ball() -> void:
	var s := _at(3, 17)
	Sessions.go(s, "park")
	assert_true(_choose(s, "dialogue_doudou_intro", "start", "help").ok)
	assert_true(_choose(s, "dialogue_doudou_intro", "found", "ok").ok)
	assert_eq(s.inventory.count(P, "item_simple_meal"), 1, "a warm rice ball")
	assert_eq(s.flags.get_flag("story.helped_kid"), true)


func test_events_fire_face_to_face() -> void:
	var s := _at(2, 8, 10, {"story_enabled": true})
	assert_false(s.events.has_fired("event_lost_wallet"))
	assert_true(s.submit("approach_npc", {"npc_id": "npc_xiao_wu"}).ok)
	assert_true(s.events.has_fired("event_lost_wallet"))
	assert_true(s.dialogue.get_pending().any(func(e: Dictionary) -> bool: return e.get("tree_id") == "dialogue_xiao_wu_intro"),
		"his scene is queued (after the arrival narration nobody answered here)")


func test_give_item_is_limited() -> void:
	var v := func(effects: Array) -> Array:
		var e := {"id": "event_fixture", "city_id": "CN_LINCHUAN", "priority": 1, "once": true, "conditions": [], "effects": effects}
		return StoryValidator.validate_event(e, Sessions.content()).map(func(x: Dictionary) -> String: return x["code"])
	assert_eq(v.call([{"type": "give_item", "item_id": "item_simple_meal", "count": 1}]), [])
	assert_has(v.call([{"type": "give_item", "item_id": "item_simple_meal", "count": 5}]), "E_STORY_AUTHORITY")
	assert_has(v.call([{"type": "give_item", "item_id": "item_gold_bar", "count": 1}]), "E_STORY_UNKNOWN_REF")


func test_old_saves_without_the_strangers_still_load() -> void:
	var s := Sessions.create()
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveManager.build(s)))
	var npcs: Dictionary = data["world"]["components"]["relationships"]["npcs"]
	for id in ["npc_xiao_wu", "npc_doudou", "npc_granny_liu"]:
		npcs.erase(id)
	var r := SaveManager.restore(s.content, RegionPolicyRegistry.with_builtin_implementations(), data)
	assert_true(r["ok"], str(r["message"]))
	assert_eq((r["session"] as SimulationSession).relationships.get_value("npc_xiao_wu"), 0)


# --- pedestrians ------------------------------------------------------------------------------

func _route_errors(path: Array) -> PackedStringArray:
	var fx := ContentFixture.new()
	fx.load_real()
	fx.data(MAP)["pedestrians"][0]["path"] = path
	var reg := ContentRegistry.new()
	reg.load_root(fx.write())
	var errors := reg.get_error_strings()
	fx.cleanup()
	return errors


func test_routes_must_be_straight_and_walkable() -> void:
	assert_true(Array(_route_errors([[2, 7], [5, 9]])).any(func(e: String) -> bool: return e.contains("E_MAP_PATH")), "diagonal route")
	assert_true(Array(_route_errors([[2, 7], [2, 1]])).any(func(e: String) -> bool: return e.contains("E_MAP_BLOCKED")), "into a building")
	assert_eq(_route_errors([[2, 7], [30, 7]]).size(), 0, "the shipped route is fine")


func _open(s: SimulationSession) -> void:
	Localizer.install(Sessions.content())
	bus = GameEventBus.new()
	bus.attach(s.processor)
	world = WORLD_SCENE.instantiate()
	world.setup(s, bus)
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	await wait_physics_frames(3)


func test_pedestrians_walk_and_chat() -> void:
	var s := _at(1, 9)
	await _open(s)
	assert_true(world.pedestrians.has("auntie_shopping"), "out shopping at 09:00")
	assert_false(world.pedestrians.has("students"), "students are at school")
	var p: Pedestrian = world.pedestrians["auntie_shopping"]
	var start := p.position
	await wait_process_frames(30)
	assert_ne(p.position, start, "walking")
	world.player.position = p.position + Vector2(0, 20)
	await wait_physics_frames(2)
	world.ui.close()
	if world.player.get_focus() == p:
		world._on_interact_requested(p)
		assert_eq(world.ui.get_panel_kind(), "message")
		var body := world.ui.get_panel_content().find_child("Body", true, false) as Label
		assert_eq(body.text, tr(p.line_for_day(1)))
	assert_eq(p.line_for_day(4), p.line_for_day(4), "same line all day")
	s.submit("advance_time", {"minutes": 12 * 60}, "system")  # 21:00
	await wait_process_frames(2)
	assert_false(world.pedestrians.has("auntie_shopping"), "home by evening")
