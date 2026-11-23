extends SceneTree
## Promo / gameplay reel, episode 2 ("街头人情"): passers-by, the one-day strangers (Xiao Wu's
## wallet, lost Doudou, Granny Liu) met through the walk-over cutscene, and the minigames
## (cashier, the skip cutscene, chess, billiards). Same rules as episode 1 (tools/demo_reel.gd):
## the live game, played by script, plus captions and title / end cards.
##   godot --path . --resolution 1920x1080 --write-movie <out.avi> --fixed-fps 30 -s res://tools/demo_reel_2.gd
## Nights are slept at home and meals eaten, so the needs stay honest.

const FPS := 30

var gs: Node
var world: CityWorld
var cap_layer: CanvasLayer
var cap_panel: PanelContainer
var cap_main: Label
var cap_sub: Label
var card: ColorRect


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	GameSettings.storage_path = "user://demo_settings.cfg"
	TranslationServer.set_locale("zh_CN")
	gs = root.get_node("GameSession")
	gs.saves = SaveManager.new("user://demo_saves")
	gs._ensure_content()
	_build_overlay()
	await _card("Everyday City", "临川市 · 七日生活", "实机演示 · 第二期 · 街头人情", 3.5)

	var look := ProfileSystem.DEFAULT_LOOK.duplicate()
	look.merge({"hair_style": "long", "hair": "#3a2a22", "top": "#e07aa0", "outfit": "dress", "figure": "f"}, true)
	for k in look.keys():
		if not ProfileSystem.LOOK_SCHEMA["fields"].has(k):
			look.erase(k)
	var started: Dictionary = gs.start_new_game("", {"name": "小林", "look": look})
	if not started["ok"]:
		push_error("demo: " + str(started))
	var s: SimulationSession = gs.session
	s.story_enabled = false
	_clear_story(s)
	_do(s, "sign_lease", {"housing_id": "home_shared_room_01"})
	_clear_story(s)
	_do(s, "book_shift", {"job_id": "job_convenience_clerk", "day": 2, "template_id": "morning"})
	_do(s, "book_shift", {"job_id": "job_restaurant_server", "day": 2, "template_id": "dinner"})
	world = load("res://scenes/world/city_world.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await _sleep_until_morning(s)
	_to(s, 2, 7, 52)
	await _hide_card()

	# --- passers-by on Old Street -------------------------------------------------------------
	_place(Vector2i(4, 9))
	_caption("街上多了来来往往的行人", "Passers-by on Old Street")
	await _walk("move_right", 3.0)
	var ped := _nearest_pedestrian()
	if ped != null:
		_place_beside(ped)
		await _frames(2)
		world._on_interact_requested(ped)
		_caption("走到身边按 E，聊上一句", "Press E for a word with them")
		await _wait(2.4)
		world.ui.close()

	# --- Xiao Wu's wallet (day 2, the bus stop) ----------------------------------------------
	_to(s, 2, 8, 12)
	_story_on(s, "npc_xiao_wu")
	_place(Vector2i(25, 9))
	world.player.facing = Vector2.RIGHT
	_caption("公交站台前，有人急得团团转", "Someone in trouble at the bus stop")
	await _walk("move_right", 0.8)
	await _story_scene([["help", 1.6], ["refuse", 1.6]], 14.0)
	_caption("帮他找到钱包，二十块钱不收", "Find his wallet, keep your twenty")
	await _wait(1.6)
	s.story_enabled = false

	# --- cashier minigame (09:00 shift) -------------------------------------------------------
	_to(s, 2, 8, 58)
	_do(s, "use_door", {"door_id": "door_convenience_store"})
	await _frames(2)
	_to(s, 2, 9, 0)
	world.ui.open_work("convenience_store")
	_caption("上班也是小游戏：便利店收银", "Work is a minigame: the till")
	await _wait(1.4)
	await _press("Play")
	await _wait(1.6)
	await _press("Start")
	_caption("扫码、找零，算对了才不亏", "Scan, then count out the change", true)
	var host: MinigameHost = world.ui.get_minigame_host()
	var g: Minigame = host.game
	for round in 2:
		while not g.all_scanned():
			g.scan_next()
			await _wait(0.45)
		var due: int = g.change_due()
		for coin: int in g.COINS:
			while due - g.given >= coin:
				g.give(coin)
				await _wait(0.3)
		await _wait(0.4)
		g.submit()
		await _wait(0.9)
	_caption("干得越好，工资越多", "Better work, better pay", true)
	g.quit_early()
	await _wait(2.2)
	await _press("Continue")
	_caption("", "")
	await _wait(2.0)
	world.ui.close()
	_do(s, "use_door", {"door_id": "door_convenience_exit"})
	await _frames(2)

	# --- skip -> work montage (17:00 dinner shift) --------------------------------------------
	_eat(s)
	_to(s, 2, 16, 58)
	_do(s, "use_door", {"door_id": "door_fast_food"})
	await _frames(2)
	_to(s, 2, 17, 0)
	world.ui.open_work("fast_food_restaurant")
	_caption("不想玩？直接干完，看一段过场", "Or skip it and watch the shift go by")
	await _wait(1.4)
	await _press("Skip")
	await _wait(4.6)
	await _wait(1.6)
	world.ui.close()
	_do(s, "use_door", {"door_id": "door_fast_food_exit"})
	await _frames(2)
	_eat(s)
	await _sleep_until_morning(s)

	# --- chess in the park (day 3) ------------------------------------------------------------
	_to(s, 3, 15, 0)
	_place(Vector2i(10, 22))
	world.player.facing = Vector2.UP
	await _frames(2)
	world.ui._perform_activity("activity_play_chess", 60)
	_caption("公园石桌，和大爷杀一盘", "Chinese chess with the old men")
	await _wait(1.2)
	await _press("Play")
	await _wait(1.4)
	await _press("Start")
	_caption("完整规则，\n大爷会算两步", "Full rules;\nhe thinks two moves ahead", "right")
	host = world.ui.get_minigame_host()
	g = host.game
	for mv: Array in [[Vector2i(1, 7), Vector2i(4, 7)], [Vector2i(7, 9), Vector2i(6, 7)], [Vector2i(0, 9), Vector2i(0, 8)]]:
		g.click(mv[0])
		await _wait(0.6)
		g.click(mv[1])
		await _wait(0.3)
		for i in 90:
			await process_frame
			if not g.running or g.turn == "r":
				break
		await _wait(0.5)
	g.quit_early()
	await _wait(1.6)
	await _press("Continue")
	_caption("", "")
	await _wait(1.6)
	world.ui.close()

	# --- lost Doudou (day 3, the park) --------------------------------------------------------
	_to(s, 3, 16, 40)
	_story_on(s, "npc_doudou")
	_place(Vector2i(16, 24))
	_caption("一个小男孩哭着跑了过来", "A little boy runs up in tears")
	await _story_scene([["help", 1.8], ["ok", 1.8]], 14.0)
	_caption("帮他找到奶奶，奶奶塞来一个饭团", "Find his grandma; she gives you a rice ball")
	await _wait(1.6)
	s.story_enabled = false

	# --- billiards (evening) ------------------------------------------------------------------
	_eat(s)
	_to(s, 3, 20, 0)
	_place(Vector2i(51, 6))
	await _frames(2)
	world.ui._perform_activity("activity_billiards", 60)
	_caption("晚上去台球厅打两杆", "A few frames of pool")
	await _wait(1.2)
	await _press("Play")
	await _wait(1.2)
	await _press("Start")
	_caption("瞄准、蓄力、出杆", "Aim, charge, strike", true)
	host = world.ui.get_minigame_host()
	g = host.game
	for shot in 4:
		var plan := _best_shot(g)
		var aim_to: float = plan[0]
		for i in 20:
			g.aim = lerp_angle(g.aim, aim_to, 0.25)
			await process_frame
		g.aim = aim_to
		g._charge(true)
		for i in int(ceilf(float(plan[1]) / 0.8 * FPS)):
			await process_frame
		g._charge(false)
		for i in 200:
			await process_frame
			if not g.moving():
				break
		await _wait(0.3)
		if OS.get_cmdline_user_args().has("--trace"):
			print("    shot %d: potted %d, shots left %d" % [shot, g.potted, g.shots_left])
		if g.potted > 0 and shot >= 1:
			break
	g.quit_early()
	await _wait(1.6)
	await _press("Continue")
	_caption("", "")
	await _wait(1.4)
	world.ui.close()
	await _sleep_until_morning(s)

	# --- Granny Liu (day 4, early) ------------------------------------------------------------
	_to(s, 4, 7, 15)
	_story_on(s, "npc_granny_liu")
	_place(Vector2i(44, 9))
	world.player.facing = Vector2.RIGHT
	_caption("清晨，有位奶奶在问路", "A granny asking the way")
	await _walk("move_right", 0.6)
	await _story_scene([["walk", 2.0]], 14.0)
	_caption("陪她走一段，累一点，心里暖", "Walk her there: a bit tiring, but it feels good")
	await _wait(1.8)
	s.story_enabled = false

	# --- downtown crowd -----------------------------------------------------------------------
	_to(s, 4, 11, 0)
	_do(s, "take_route", {"route_id": "route_1_to_downtown"})
	_clear_story(s)
	await _frames(2)
	world.ui.close()
	_place(Vector2i(8, 13))
	_caption("市中心的人潮", "The downtown crowd")
	await _walk("move_right", 4.0)
	await _wait(0.8)

	_caption("", "")
	await _card("Everyday City", "第二期 · 街头人情", "开发中的版本，画面与内容仍会调整", 4.0)
	quit()


# --- episode 2 helpers -------------------------------------------------------------------------

## Story on for one stranger's scene: other NPCs' first meetings (skipped while the reel kept
## the story off) are marked as greeted so they don't walk over first.
func _story_on(s: SimulationSession, npc_id: String) -> void:
	s.story_enabled = true
	for id in s.events.greeting_npcs(s.world):
		if id != npc_id:
			world._greeted[id] = true


## Waits for the walk-over cutscene and answers the dialogue with `answers` ([choice id, pause]).
func _story_scene(answers: Array, timeout: float) -> void:
	var t := 0
	var i := 0
	while t < int(timeout * FPS) and i < answers.size():
		await process_frame
		t += 1
		var b := world.ui.find_child(GameUi.button_name("Choice_" + str(answers[i][0])), true, false) as Button
		if b != null and b.is_visible_in_tree():
			await _wait(answers[i][1])
			b.pressed.emit()
			i += 1
	if i < answers.size():
		print("    pending=", gs.session.dialogue.get_pending(), " panel=", world.ui.get_panel_kind(), " phase=", world._greet_phase,
			" paused=", paused, " fired=", gs.session.events.has_fired("event_lost_wallet"), " npc_at=", world.greeting.position if world.greeting else Vector2.ZERO, " me=", world.player.position, " walking=", world.greeting.is_walking() if world.greeting else false)
		push_error("demo: story scene answered %d/%d (greeting=%s)" % [i, answers.size(), str(world.greeting)])
	await _wait(0.6)
	_clear_story(gs.session)


## Ghost-ball aim: the free ball / pocket pair with the straightest cut, cue path unobstructed.
func _best_shot(g: Minigame) -> Array:
	var cue_pos: Vector2 = g.cue()["pos"]
	var best := [0.0, 0.9]
	var best_cut := INF
	for b: Dictionary in g.balls.slice(1):
		if b["in"]:
			continue
		for pk: Vector2 in g.pockets():
			var to_pocket := (pk - (b["pos"] as Vector2)).normalized()
			var ghost: Vector2 = (b["pos"] as Vector2) - to_pocket * g.R * 2.0
			var cut := absf((ghost - cue_pos).normalized().angle_to(to_pocket))
			if cut > 1.0:
				continue
			var clear := true
			for o: Dictionary in g.balls.slice(1):
				if o == b or o["in"]:
					continue
				if Geometry2D.get_closest_point_to_segment(o["pos"], cue_pos, ghost).distance_to(o["pos"]) < g.R * 2.1:
					clear = false
					break
			if clear and cut < best_cut:
				best_cut = cut
				# speed decays ~1.33/s (friction 0.978 per 1/60 s): reach the pocket with some to spare
				var need := (cue_pos.distance_to(ghost) + (b["pos"] as Vector2).distance_to(pk) * 1.6 + 200.0) * 1.33
				best = [(ghost - cue_pos).angle(), clampf(need / g.MAX_SPEED / maxf(cos(cut), 0.4), 0.35, 0.97)]
	return best


func _press(button: String) -> void:
	for i in 60:
		var b := root.find_child(button, true, false) as Button
		if b != null and b.is_visible_in_tree():
			b.pressed.emit()
			await _frames(2)
			return
		await process_frame
	push_error("demo: no button " + button)


func _nearest_pedestrian() -> Pedestrian:
	var best: Pedestrian = null
	for p: Pedestrian in world.pedestrians.values():
		if best == null or p.position.distance_to(world.player.position) < best.position.distance_to(world.player.position):
			best = p
	return best


func _place_beside(p: Pedestrian) -> void:
	p.set_process(false)
	world.player.position = p.position + Vector2(0, 26)
	world.player.reset_physics_interpolation()
	world.player.facing = Vector2.UP
	await _frames(1)
	p.set_process(true)


## Buy a meal at the corner store and eat it (keeps hunger honest across the jumps).
func _eat(s: SimulationSession) -> void:
	var here := s.locations.get_map_id(SimulationSession.PLAYER_ID)
	if here == "map_old_town":
		s.submit("use_door", {"door_id": "door_fast_food"})
	var inside := s.locations.get_map_id(SimulationSession.PLAYER_ID)
	var shop := "shop_fast_food" if inside == "map_fast_food_interior" else "shop_convenience_store"
	if _do(s, "buy_item", {"shop_id": shop, "item_id": "item_simple_meal", "quantity": 1}).ok:
		_do(s, "use_item", {"item_id": "item_simple_meal"})
	if here == "map_old_town" and inside == "map_fast_food_interior":
		_do(s, "use_door", {"door_id": "door_fast_food_exit"})
	_clear_story(s)


func _do(s: SimulationSession, action: String, args: Dictionary, actor := "") -> CommandResult:
	var r: CommandResult = s.submit(action, args, actor) if not actor.is_empty() else s.submit(action, args)
	if not r.ok:
		push_error("demo: %s %s -> %s" % [action, str(args), r.error_code])
	return r


## Home and sleep until 07:00 (the game's own sleep), as a real player would.
func _sleep_until_morning(s: SimulationSession) -> void:
	_clear_story(s)
	var day := s.world.clock.get_day_index()
	var target := GameClock.minute_from_day_time(day, 22, 30)
	if s.world.clock.get_minute() < target:
		_do(s, "advance_time", {"minutes": target - s.world.clock.get_minute()}, "system")
	_eat(s)
	_do(s, "perform_activity", {"activity_id": "activity_sleep", "minutes": 510})
	_clear_story(s)
	await _frames(2)


# --- helpers ---------------------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait(seconds: float) -> void:
	await _frames(int(seconds * FPS))


func _walk(action: String, seconds: float) -> void:
	Input.action_press(action)
	await _wait(seconds)
	Input.action_release(action)
	await _frames(1)


func _place(tile: Vector2i) -> void:
	world.player.position = world.tile_center(tile)
	world.player.reset_physics_interpolation()


## Jump the clock to day/hour/minute (no-op if already past), keeping story popups away.
func _to(s: SimulationSession, day: int, hour: int, minute: int) -> void:
	var target := GameClock.minute_from_day_time(day, hour, minute)
	if target > s.world.clock.get_minute():
		s.submit("advance_time", {"minutes": target - s.world.clock.get_minute()}, "system")
	_clear_story(s)


func _clear_story(s: SimulationSession) -> void:
	var guard := 0
	while s.dialogue.has_pending() and guard < 20:
		guard += 1
		var e := s.dialogue.peek()
		if e["kind"] == "summary":
			s.submit("dismiss_story_entry", {"entry_id": e["entry_id"]})
			continue
		var tree := s.content.get_record("dialogues", e["tree_id"])
		var node: Dictionary = (tree["nodes"] as Array).filter(func(n: Dictionary) -> bool: return n["id"] == e["node_id"])[0]
		if not s.submit("choose_dialogue", {"tree_id": e["tree_id"], "node_id": e["node_id"],
				"choice_id": node["choices"][0]["id"], "entry_id": e["entry_id"]}).ok:
			s.submit("dismiss_story_entry", {"entry_id": e["entry_id"]})
	if world != null:
		world.ui.close()


func _build_overlay() -> void:
	cap_layer = CanvasLayer.new()
	cap_layer.layer = 30
	root.add_child.call_deferred(cap_layer)
	cap_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.72)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	cap_panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	cap_panel.add_child(box)
	cap_main = Label.new()
	cap_main.add_theme_font_size_override("font_size", 44)
	cap_main.add_theme_color_override("font_color", Color("#fbf3dc"))
	cap_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap_main)
	cap_sub = Label.new()
	cap_sub.add_theme_font_size_override("font_size", 22)
	cap_sub.add_theme_color_override("font_color", Color("#c9c2b0"))
	cap_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap_sub)
	cap_layer.add_child(cap_panel)
	cap_panel.visible = false
	card = ColorRect.new()
	card.color = Color("#14131a")
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.visible = false
	cap_layer.add_child(card)


func _caption(main: String, sub: String, where: Variant = "bottom") -> void:
	if typeof(where) == TYPE_BOOL:
		where = "top" if where else "bottom"
	if OS.get_cmdline_user_args().has("--trace") and gs.session != null:
		print("    needs=%s cash=%d" % [str(gs.session.need_states()), gs.session.economy.get_balance(SimulationSession.PLAYER_ID)])
	if OS.get_cmdline_user_args().has("--trace"):
		print("[%d] %s | map=%s | %s" % [Engine.get_process_frames(), main,
			world.map.get("id", "-") if world != null else "-",
			GameClock.format_debug(gs.session.world.clock.get_minute()) if gs.session != null else "-"])
	cap_panel.visible = not main.is_empty()
	cap_main.text = main
	cap_sub.text = sub
	cap_panel.reset_size()
	var view := root.get_visible_rect().size
	match where:
		"top":
			cap_panel.position = Vector2((view.x - cap_panel.size.x) / 2.0, 90.0)
		"right":
			cap_panel.position = Vector2(view.x - cap_panel.size.x - 60, (view.y - cap_panel.size.y) / 2.0)
		_:
			cap_panel.position = Vector2((view.x - cap_panel.size.x) / 2.0, view.y - cap_panel.size.y - 70)


func _card(title: String, line1: String, line2: String, seconds: float) -> void:
	for c in card.get_children():
		c.queue_free()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	for spec: Array in [[title, 96, Color("#fbf3dc")], [line1, 48, Color("#f2d27a")], [line2, 28, Color("#a9a294")]]:
		var l := Label.new()
		l.text = spec[0]
		l.add_theme_font_size_override("font_size", spec[1])
		l.add_theme_color_override("font_color", spec[2])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	card.visible = true
	card.modulate.a = 0.0
	var n := int(0.6 * FPS)
	for i in n:
		card.modulate.a = float(i + 1) / n
		await process_frame
	await _wait(seconds - 0.6)


func _hide_card() -> void:
	var n := int(0.5 * FPS)
	for i in n:
		card.modulate.a = 1.0 - float(i + 1) / n
		await process_frame
	card.visible = false
