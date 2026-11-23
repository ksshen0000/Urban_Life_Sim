extends "res://tests/framework/test_case.gd"
## D-038 minigames: the plugin registry, every game's own rules (xiangqi, billiards physics,
## breakout, rhythm, cashier, order-up, sorting, bricklaying), work pay from performance, and the
## full-screen host (pause, start / skip / stop, result).

const Sessions := preload("res://tests/framework/session_factory.gd")
const P := SimulationSession.PLAYER_ID

var nodes: Array[Node] = []


func after_each() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	(Engine.get_main_loop() as SceneTree).paused = false


func _game(id: String) -> Minigame:
	Localizer.install(Sessions.content())
	var g := MinigameRegistry.create(id)
	assert_not_null(g, id)
	g.size = Vector2(1920, 1016)
	(Engine.get_main_loop() as SceneTree).root.add_child(g)
	nodes.append(g)
	g.start()
	return g


# --- registry ---------------------------------------------------------------------------------

func test_every_minigame_in_content_is_registered_and_runs() -> void:
	var ids := {}
	for table in ["jobs", "activities"]:
		for r in Sessions.content().get_records(table):
			if r.has("minigame"):
				ids[r["minigame"]] = true
	assert_true(ids.size() >= 9, str(ids.keys()))
	for id: String in ids:
		assert_true(MinigameRegistry.has(id), "%s is registered" % id)
		var g := _game(id)
		await wait_process_frames(5)
		var result := []
		g.finished.connect(func(score: int, lines: PackedStringArray) -> void: result.append(score))
		g.quit_early()
		assert_eq(result.size(), 1, "%s ends when stopped" % id)
		assert_true(result[0] >= 0 and result[0] <= 100)
		assert_false(g.title().begins_with("mg."), "%s has a title" % id)
		assert_false(g.help().begins_with("mg."), "%s has instructions" % id)


# --- xiangqi -------------------------------------------------------------------------------

func test_xiangqi_rules() -> void:
	var b := XiangqiRules.start_position()
	assert_eq(b.legal_moves("r").size(), 44, "standard opening move count")
	assert_eq(b.legal_moves("b").size(), 44)
	# horse leg: the red horse at (1,9) is blocked towards (2,7)? its leg (1,8) is empty -> allowed
	assert_true(b.piece_moves(Vector2i(1, 9)).has(Vector2i(2, 7)))
	var blocked := XiangqiRules.start_position()
	blocked.cells[Vector2i(1, 8)] = "rP"
	assert_false(blocked.piece_moves(Vector2i(1, 9)).has(Vector2i(2, 7)), "lame horse")
	# elephant eye
	var eye := XiangqiRules.start_position()
	eye.cells[Vector2i(3, 8)] = "rP"
	assert_false(eye.piece_moves(Vector2i(2, 9)).has(Vector2i(4, 7)), "blocked elephant")
	# cannon captures over exactly one screen
	assert_true(b.piece_moves(Vector2i(1, 7)).has(Vector2i(1, 0)), "cannon takes the horse over a screen")
	assert_false(b.piece_moves(Vector2i(1, 7)).has(Vector2i(1, 2)), "no capture without a screen... and nothing there")
	# flying general: an empty file between the generals is illegal
	var fly := XiangqiRules.new()
	fly.cells = {Vector2i(4, 0): "bK", Vector2i(3, 9): "rK", Vector2i(0, 5): "rR"}
	var moves := fly.legal_moves("r")
	assert_false(moves.any(func(m: Array) -> bool: return m[0] == Vector2i(3, 9) and m[1] == Vector2i(4, 9)),
		"the general may not step onto the open file facing the enemy general")


func test_xiangqi_checkmate_and_ai() -> void:
	# black general on rank 0, a rook guarding rank 1 and one giving check along rank 0
	var b := XiangqiRules.new()
	b.cells = {Vector2i(4, 0): "bK", Vector2i(0, 1): "rR", Vector2i(8, 0): "rR", Vector2i(3, 9): "rK"}
	assert_true(b.is_checkmated("b"), "two rooks mate")
	var free_piece := XiangqiRules.start_position()
	free_piece.cells[Vector2i(4, 4)] = "rR"   # a red rook left hanging next to a black soldier
	var t0 := Time.get_ticks_msec()
	var m := free_piece.best_move("b", 2)
	assert_true(Time.get_ticks_msec() - t0 < 5000, "the old man answers in time")
	assert_eq(m[1], Vector2i(4, 4), "takes the hanging rook")


func test_xiangqi_game_click_flow() -> void:
	var g: Minigame = _game("xiangqi")
	g.click(Vector2i(1, 7))       # red cannon
	assert_true(g.targets.size() > 0)
	g.click(Vector2i(4, 7))       # central cannon
	assert_eq(g.board.cells.get(Vector2i(4, 7)), "rC")
	assert_eq(g.turn, "b")
	for i in 120:
		await wait_process_frames(1)
		if g.turn == "r":
			break
	assert_eq(g.turn, "r", "the old man replied")


# --- billiards ------------------------------------------------------------------------------

func test_billiards_physics_pots_a_ball() -> void:
	var g: Minigame = _game("billiards")
	var pocket: Vector2 = g.pockets()[2]   # top right
	var ball: Dictionary = g.balls[1]
	ball["pos"] = pocket + Vector2(-80, 80)
	g.cue()["pos"] = pocket + Vector2(-200, 200)
	for b in g.balls.slice(2):
		b["in"] = true
	g.shoot((pocket - (g.cue()["pos"] as Vector2)).angle(), 0.6)
	assert_eq(g.shots_left, 9)
	for i in 600:
		g.step(1.0 / 120.0)
	assert_eq(g.potted, 1, "the ball went in")
	assert_false(g.moving())


func test_billiards_scratch_puts_cue_back() -> void:
	var g: Minigame = _game("billiards")
	var pocket: Vector2 = g.pockets()[0]
	g.cue()["pos"] = pocket + Vector2(60, 60)
	g.shoot((pocket - (g.cue()["pos"] as Vector2)).angle(), 0.5)
	for i in 300:
		g.step(1.0 / 120.0)
	assert_false(g.cue()["in"], "the cue ball comes back")
	assert_eq(g.potted, 0)


# --- arcade / rhythm ------------------------------------------------------------------------

func test_breakout_scores_bricks() -> void:
	var g: Minigame = _game("breakout")
	assert_eq(g.current_score(), 0)
	g.bricks.resize(g.total / 2)
	g.brick_rows.resize(g.total / 2)
	assert_eq(g.current_score(), 50)


func test_rhythm_judging() -> void:
	var g: Minigame = _game("dance")
	var n: Dictionary = g.notes[0]
	assert_eq(g.press(n["lane"], float(n["t"]) + 0.02), "perfect")
	var n2: Dictionary = g.notes[1]
	assert_eq(g.press(n2["lane"], float(n2["t"]) + 0.15), "good")
	assert_eq(g.press((int(g.notes[2]["lane"]) + 1) % 4, float(g.notes[2]["t"])), "", "wrong key or no note: nothing")
	var slow: Minigame = _game("square_dance")
	assert_true(slow.bpm < g.bpm, "square dancing is gentler")


# --- work games -----------------------------------------------------------------------------

func test_cashier_change() -> void:
	var g: Minigame = _game("cashier")
	while not g.all_scanned():
		g.scan_next()
	assert_true(g.paid >= g.total())
	var due: int = g.change_due()
	for coin: int in g.COINS:
		while due - g.given >= coin:
			g.give(coin)
	g.submit()
	assert_eq(g.served, 1)
	while not g.all_scanned():
		g.scan_next()
	g.give(g.change_due() + 10)  # ten fen too much
	g.submit()
	assert_eq(g.mistakes, 1)
	assert_eq(g.current_score(), 10, "+20 - 10")


func test_order_up() -> void:
	var g: Minigame = _game("order_up")
	for dish: String in g.ticket:
		for i in g.ticket[dish]:
			g.add_dish(dish)
	g.serve()
	assert_eq(g.served, 1)
	g.add_dish("cola")
	g.add_dish("cola")
	g.add_dish("cola")
	g.add_dish("cola")
	g.serve()
	assert_eq(g.mistakes, 1)


func test_sorting() -> void:
	var g: Minigame = _game("sorting")
	var z: Vector2 = g.zone()
	g.parcels.append({"y": (z.x + z.y) / 2.0, "chute": 2, "done": false})
	assert_true(g.route(2))
	g.parcels.append({"y": (z.x + z.y) / 2.0, "chute": 0, "done": false})
	assert_false(g.route(1))
	assert_eq([g.correct, g.wrong], [1, 1])


func test_bricks() -> void:
	var g: Minigame = _game("bricks")
	var top: Rect2 = g.stack[-1]
	g.current.position.x = top.position.x + 2
	assert_eq(g.drop(), top.size.x, "a near-perfect drop keeps the full width")
	g.current.position.x = g.stack[-1].end.x + 50
	var done := []
	g.finished.connect(func(s: int, l: PackedStringArray) -> void: done.append(s))
	assert_eq(g.drop(), 0.0)
	assert_eq(done.size(), 1, "missing entirely ends the round")


# --- pay and host -----------------------------------------------------------------------------

func test_performance_changes_pay() -> void:
	assert_eq(WorkShiftHandler.performance_bp(50), 10000)
	assert_eq(WorkShiftHandler.performance_bp(100), 11000)
	assert_eq(WorkShiftHandler.performance_bp(0), 9000)
	for perf in [0, 50, 100]:
		var s := Sessions.create()
		s.submit("book_shift", {"job_id": "job_convenience_clerk", "day": 2, "template_id": "morning"})
		s.submit("advance_time", {"minutes": GameClock.minute_from_day_time(2, 9) - s.world.clock.get_minute()}, "system")
		Sessions.go(s, "convenience_store")
		assert_true(s.submit("work_shift", {"shift_id": "job_convenience_clerk.d2.morning", "performance": perf}).ok)
		assert_eq(s.jobs.get_shift("job_convenience_clerk.d2.morning")["gross_minor"], 8800 * WorkShiftHandler.performance_bp(perf) / 10000)
	var s2 := Sessions.create()
	assert_eq(s2.submit("work_shift", {"shift_id": "x", "performance": 101}).error_code, "E_INVALID_ARGUMENTS")


func test_host_pauses_and_returns_the_score() -> void:
	Localizer.install(Sessions.content())
	var s := Sessions.create()
	var layer := CanvasLayer.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(layer)
	nodes.append(layer)
	var got := []
	var host := MinigameHost.open(layer, "bricks", {}, s, func(r: Dictionary) -> void: got.append(r))
	await wait_process_frames(2)
	assert_true((Engine.get_main_loop() as SceneTree).paused, "the world waits")
	assert_true(s.world.clock.is_paused())
	assert_false(host.game.running, "intro card first")
	(host.find_child("Start", true, false) as Button).pressed.emit()
	assert_true(host.game.running)
	host.game.quit_early()
	await wait_process_frames(1)
	(host.find_child("Continue", true, false) as Button).pressed.emit()
	await wait_process_frames(2)
	assert_eq(got.size(), 1)
	assert_false(got[0]["skipped"])
	assert_false((Engine.get_main_loop() as SceneTree).paused)
	assert_false(s.world.clock.is_paused())
	var host2 := MinigameHost.open(layer, "cashier", {}, s, func(r: Dictionary) -> void: got.append(r))
	await wait_process_frames(2)
	(host2.find_child("Skip", true, false) as Button).pressed.emit()
	await wait_process_frames(2)
	assert_true(got[1]["skipped"])
	assert_eq(got[1]["score"], 50)
