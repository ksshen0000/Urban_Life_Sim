extends "res://tests/framework/test_case.gd"
## D-037: hunger, exhaustion and stress have consequences: slower walking, lower work efficiency
## (pay x efficiency), and no starting a shift when exhausted or at breaking point. Hunger never
## blocks work, and every block can be cleared for free (no dead ends).

const Sessions := preload("res://tests/framework/session_factory.gd")
const WORLD_SCENE := preload("res://scenes/world/city_world.tscn")
const P := SimulationSession.PLAYER_ID
const SHIFT := "job_convenience_clerk.d2.morning"

var world: CityWorld
var bus: GameEventBus


func after_each() -> void:
	if world != null:
		world.queue_free()
		await wait_process_frames(2)
	world = null
	if bus != null:
		bus.free()
	bus = null


func _set_needs(s: SimulationSession, values: Dictionary) -> void:
	var d := s.needs.to_dict()
	for k: String in values:
		d["values"][P][k] = values[k]
	assert_eq(s.needs.from_dict(d), "")


## Rested session at day 2 08:55, shift booked, standing in the store.
func _ready_to_work() -> SimulationSession:
	var s := Sessions.create({"need_effects": true})
	s.submit("book_shift", {"job_id": "job_convenience_clerk", "day": 2, "template_id": "morning"})
	s.submit("advance_time", {"minutes": GameClock.minute_from_day_time(2, 8, 55) - s.world.clock.get_minute()}, "system")
	Sessions.go(s, "convenience_store")
	_set_needs(s, {"hunger": 30, "energy": 80, "stress": 20})
	return s


func test_states_and_factors() -> void:
	var c := Sessions.content()
	assert_eq(NeedStates.active(c, {"hunger": 30, "energy": 80, "stress": 20}), [] as Array[Dictionary])
	var st := NeedStates.active(c, {"hunger": 92, "energy": 15, "stress": 75})
	var ids := st.map(func(x: Dictionary) -> String: return x["id"])
	assert_eq(ids.size(), 4, str(ids))  # hungry + starving, tired (15 is not exhausted), stressed
	assert_true(ids.has("starving") and ids.has("tired") and ids.has("stressed"))
	assert_true(absf(NeedStates.walk_factor(st) - 0.85 * 0.65 * 0.85) < 0.001)
	assert_eq(NeedStates.work_efficiency_bp(st), 10000 * 90 / 100 * 75 / 100 * 85 / 100 * 85 / 100)
	assert_eq(NeedStates.work_block(st), "", "hunger, tiredness and stress below 90 never block work")
	assert_eq(NeedStates.work_block(NeedStates.active(c, {"energy": 3})), "E_TOO_TIRED")
	assert_eq(NeedStates.work_block(NeedStates.active(c, {"stress": 95})), "E_TOO_STRESSED")
	assert_eq(NeedStates.work_block(NeedStates.active(c, {"hunger": 100})), "", "starving still may work (no dead ends)")


func test_full_pay_when_fine() -> void:
	var s := _ready_to_work()
	assert_true(s.submit("work_shift", {"shift_id": SHIFT}).ok)
	assert_eq(s.jobs.get_shift(SHIFT)["gross_minor"], 8800)


func test_hungry_works_for_less() -> void:
	var s := _ready_to_work()
	_set_needs(s, {"hunger": 92})
	assert_true(s.submit("work_shift", {"shift_id": SHIFT}).ok, "hunger never blocks work")
	assert_eq(s.jobs.get_shift(SHIFT)["gross_minor"], 8800 * 90 / 100 * 75 / 100, "hungry x starving efficiency")
	assert_true(s.processor.get_event_log().any(func(e: DomainEvent) -> bool: return e.type == "work_efficiency"))


func test_exhausted_must_rest_first() -> void:
	var s := _ready_to_work()
	_set_needs(s, {"energy": 3})
	var t := s.world.clock.get_minute()
	assert_eq(s.submit("work_shift", {"shift_id": SHIFT}).error_code, "E_TOO_TIRED")
	assert_eq(s.world.clock.get_minute(), t, "refused before anything happened")
	assert_eq(s.jobs.get_shift(SHIFT)["status"], "booked", "the shift is still yours")


func test_breaking_point_can_be_cleared_for_free() -> void:
	var s := Sessions.create({"need_effects": true})
	s.submit("book_shift", {"job_id": "job_convenience_clerk", "day": 2, "template_id": "morning"})
	s.submit("advance_time", {"minutes": GameClock.minute_from_day_time(2, 7, 10) - s.world.clock.get_minute()}, "system")
	Sessions.go(s, "convenience_store")
	_set_needs(s, {"hunger": 30, "energy": 80, "stress": 95})
	assert_eq(s.submit("work_shift", {"shift_id": SHIFT}).error_code, "E_TOO_STRESSED")
	var cash := s.economy.get_balance(P)
	Sessions.go(s, "park")
	assert_true(s.submit("perform_activity", {"activity_id": "activity_rest", "minutes": 120}).ok, "two free hours on the bench")
	assert_true(s.needs.get_value(P, "stress") < 90)
	assert_eq(s.economy.get_balance(P), cash, "recovering cost nothing")
	Sessions.go(s, "convenience_store")
	assert_true(s.submit("work_shift", {"shift_id": SHIFT}).ok, "calm enough to work")


func test_effects_can_be_switched_off_for_mechanics_tests() -> void:
	var s := Sessions.create()
	assert_eq(s.need_states(), [] as Array[Dictionary])


func test_slower_walk_and_hud_status() -> void:
	Localizer.install(Sessions.content())
	var s := Sessions.create({"need_effects": true})
	_set_needs(s, {"hunger": 95})
	bus = GameEventBus.new()
	bus.attach(s.processor)
	world = WORLD_SCENE.instantiate()
	world.setup(s, bus)
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	await wait_physics_frames(3)
	world.ui.close()
	await wait_process_frames(2)
	world.ui.hud.refresh()
	assert_true(world.player.speed_factor < 0.6, "starving: you can barely walk (%.2f)" % world.player.speed_factor)
	var text: String = world.ui.hud.get_state_text()
	assert_true(text.contains("饿得发慌") and text.contains("走得慢"), text)
	_set_needs(s, {"hunger": 20})
	world.ui.hud.refresh()
	await wait_process_frames(2)
	assert_eq(world.ui.hud.get_state_text(), "", "fine again")
	assert_eq(world.player.speed_factor, 1.0)
