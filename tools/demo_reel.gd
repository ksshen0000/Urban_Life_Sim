extends SceneTree
## Promo / gameplay reel (episode 1): plays the real game like a player, shot by shot, with
## captions, for Godot's Movie Maker:
##   godot --path . --resolution 1920x1080 --write-movie <out.avi> --fixed-fps 30 -s res://tools/demo_reel.gd
## Everything on screen is the live game; only the caption strip and the title / end cards are
## overlays added here. Needs a display. Uses its own save folder and settings file.

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

	# --- title card --------------------------------------------------------------------------
	await _card("Everyday City", "临川市 · 七日生活", "实机演示 · 第一期", 4.0)

	# --- character creator -------------------------------------------------------------------
	var creator := CharacterCreator.make({}, "ui.creator.title", "ui.creator.start")
	root.add_child(creator)
	creator.position = Vector2.ZERO
	creator.size = root.get_visible_rect().size  # a bare Control under the window is not auto-sized
	await _hide_card()
	_caption("先捏一个自己", "Create your character")
	await _wait(0.8)
	creator._set_gender("f")
	await _wait(0.7)
	for i in 3:
		creator._cycle_hair(1)
		await _wait(0.45)
	creator._set_look("hair", CharacterCreator.HAIR[3])
	await _wait(0.4)
	creator._set_look("top", CharacterCreator.TOP[6])
	await _wait(0.4)
	creator._set_look("outfit", "dress")
	creator._turn(1)
	await _wait(0.6)
	creator._turn(1)
	creator._set_look("top", CharacterCreator.TOP[2])
	await _wait(0.6)
	creator._turn(1)
	await _wait(0.6)
	var profile: Dictionary = creator.profile.duplicate(true)
	profile["name"] = "小林"
	creator.queue_free()

	# --- start the game: morning on Old Street ------------------------------------------------
	gs.start_new_game("", profile)
	var s: SimulationSession = gs.session
	s.story_enabled = false
	_clear_story(s)
	world = load("res://scenes/world/city_world.tscn").instantiate()
	root.add_child(world)
	await process_frame
	world.ui.close()
	_place(Vector2i(31, 6))
	_caption("清晨的老街", "Morning on Old Street")
	await _walk("move_left", 3.2)
	await _walk("move_up", 0.3)

	# --- inside the corner store --------------------------------------------------------------
	s.submit("use_door", {"door_id": "door_convenience_store"})
	await _frames(2)
	_caption("推门进店，陈雨在收银台后", "Walk into the corner store")
	await _walk("move_right", 1.2)
	await _walk("move_up", 0.4)
	await _wait(1.6)
	s.submit("use_door", {"door_id": "door_convenience_exit"})

	# --- the park, 08:30 ------------------------------------------------------------------------
	_to(s, 1, 8, 25)
	await _frames(2)
	_place(Vector2i(11, 24))
	_caption("公园里，下棋的、唱歌的、打太极的街坊", "Neighbours in the park")
	await _walk("move_right", 4.6)
	await _wait(1.0)

	# --- on foot into Xinhe ------------------------------------------------------------------
	_to(s, 1, 9, 20)
	_place(Vector2i(51, 9))
	_caption("走出老街，就是新河里", "Walk on into Xinhe")
	await _walk("move_right", 2.4)
	_caption("工地、理发店、老小区", "Building site, barber, old compound")
	await _walk("move_right", 2.6)
	await _walk("move_down", 0.5)
	await _wait(1.2)

	# --- Route 1 to downtown -----------------------------------------------------------------
	s.submit("use_door", {"door_id": "street_west_8"})
	s.submit("take_route", {"route_id": "route_1_to_downtown"})
	_clear_story(s)
	await _frames(2)
	world.ui.close()
	_caption("坐 1 路去市中心：高楼、奢侈品、咖啡", "Take Route 1 downtown")
	await _walk("move_left", 3.4)
	await _wait(0.8)
	_place(Vector2i(14, 13))
	await _walk("move_right", 2.6)

	# --- dusk to night on Old Street (time-lapse) ---------------------------------------------
	s.submit("take_route", {"route_id": "route_1_to_old_town"})
	_to(s, 1, 17, 0)
	_clear_story(s)
	await _frames(2)
	world.ui.close()
	_place(Vector2i(27, 7))
	world.player.facing = Vector2.DOWN
	_caption("从黄昏到入夜，路灯一盏盏亮起", "From dusk to night")
	for i in 150:   # 17:00 -> 19:30 in five seconds
		s.submit("advance_time", {"minutes": 1}, "system")
		await process_frame
	_clear_story(s)

	# --- square dancing -----------------------------------------------------------------------
	_to(s, 1, 19, 35)
	_place(Vector2i(28, 23))
	_caption("晚上七点，广场舞准时开场", "Square dancing at seven")
	await _walk("move_right", 1.4)
	await _wait(3.2)

	# --- the fast-food place, Lao Zhou -------------------------------------------------------
	_to(s, 1, 20, 15)
	s.submit("use_door", {"door_id": "door_fast_food"})
	await _frames(2)
	_caption("快餐店里，碰到下班吃饭的老周", "Dinner with Lao Zhou")
	await _walk("move_up", 1.0)
	await _walk("move_right", 1.4)
	await _wait(1.2)

	# --- downtown at night -------------------------------------------------------------------
	s.submit("use_door", {"door_id": "door_fast_food_exit"})
	s.submit("take_route", {"route_id": "route_1_to_downtown"})
	_clear_story(s)
	await _frames(2)
	world.ui.close()
	_place(Vector2i(16, 12))
	_caption("夜里的市中心", "Downtown at night")
	await _walk("move_right", 4.0)
	await _wait(1.0)

	# --- end card ----------------------------------------------------------------------------
	_caption("", "")
	await _card("Everyday City", "第一期 · 实机演示", "开发中的版本，画面与内容仍会调整", 4.5)
	quit()


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


func _caption(main: String, sub: String) -> void:
	if OS.get_cmdline_user_args().has("--trace"):
		print("[%d] %s | map=%s | %s" % [Engine.get_process_frames(), main,
			world.map.get("id", "-") if world != null else "-",
			GameClock.format_debug(gs.session.world.clock.get_minute()) if gs.session != null else "-"])
	cap_panel.visible = not main.is_empty()
	cap_main.text = main
	cap_sub.text = sub
	cap_panel.reset_size()
	var view := root.get_visible_rect().size
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
