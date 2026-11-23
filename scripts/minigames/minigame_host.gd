class_name MinigameHost
extends Control
## Full-screen frame around a minigame (D-038): intro card (title, how to play, Start / Skip),
## a top bar while playing (title, time left, Esc to stop), and a result card (rating, score,
## notes, Continue). Pauses the scene tree and the game clock while open; calls on_done with
## {"skipped": bool, "score": int, "lines": PackedStringArray} when it closes.

const PAUSE_REASON := "minigame"

var game: Minigame
var _on_done: Callable
var _session: SimulationSession
var _skip_allowed := true
var _bar: Label
var _timer: Label
var _card: PanelContainer
var _stage: Control
var _result := {}
var _paused_tree := false


## Opens `game_id` full screen over `parent` (a CanvasLayer / Control). Returns the host.
static func open(parent: Node, game_id: String, context: Dictionary, session: SimulationSession,
		on_done: Callable, skip_allowed: bool = true) -> MinigameHost:
	var h := MinigameHost.new()
	h.name = "MinigameHost"
	h.game = MinigameRegistry.create(game_id)
	h.game.setup(context)
	h._on_done = on_done
	h._session = session
	h._skip_allowed = skip_allowed
	parent.add_child(h)
	return h


func _ready() -> void:
	# explicit full-window size (no anchors: setting both makes Godot warn and override the size;
	# anchors would also only resolve after a layout pass, and games measure themselves on start)
	position = Vector2.ZERO
	size = get_viewport_rect().size
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _session != null:
		_session.world.clock.push_pause(PAUSE_REASON)
	if not get_tree().paused:
		get_tree().paused = true
		_paused_tree = true
	var bg := ColorRect.new()
	bg.color = Color("#14131a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var top := ColorRect.new()
	top.color = Color("#1f1d28")
	top.position = Vector2.ZERO
	top.size = Vector2(size.x, 64)
	add_child(top)
	_bar = _label(top, game.title(), 30, Color("#fbf3dc"))
	_bar.position = Vector2(32, 12)
	_timer = _label(top, "", 26, Color("#f2d27a"))
	_timer.position = Vector2(size.x / 2.0 - 80, 14)
	var esc := _label(top, tr("mg.common.esc"), 20, Color("#a9a294"))
	esc.position = Vector2(size.x - 220, 20)
	_stage = Control.new()
	_stage.position = Vector2(0, 64)
	_stage.size = Vector2(size.x, size.y - 64)
	_stage.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_stage)
	_stage.add_child(game)
	game.visible = false
	game.finished.connect(_on_game_finished)
	_show_intro()


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _card_with(title: String, body: String, buttons: Array) -> void:
	if _card != null:
		_card.queue_free()
	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#262433")
	sb.set_border_width_all(3)
	sb.border_color = Color("#f2d27a")
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(36)
	_card.add_theme_stylebox_override("panel", sb)
	var center := CenterContainer.new()
	center.position = Vector2.ZERO
	center.size = size
	center.name = "CardCenter"
	add_child(center)
	center.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	_card.add_child(box)
	var t := _label(box, title, 44, Color("#f2d27a"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b := _label(box, body, 24, Color("#fbf3dc"))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.x = 720
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	for spec: Array in buttons:
		var btn := Button.new()
		btn.name = spec[0]
		btn.text = spec[1]
		btn.custom_minimum_size = Vector2(200, 56)
		btn.pressed.connect(spec[2])
		row.add_child(btn)
	(row.get_child(0) as Button).grab_focus()


func _close_card() -> void:
	var c := get_node_or_null("CardCenter")
	if c != null:
		remove_child(c)
		c.queue_free()
	_card = null


func _show_intro() -> void:
	var buttons: Array = [["Start", tr("mg.common.start"), begin]]
	if _skip_allowed:
		buttons.append(["Skip", tr("mg.common.skip"), skip])
	_card_with(game.title(), game.help(), buttons)


func begin() -> void:
	_close_card()
	game.visible = true
	game.position = Vector2.ZERO
	game.size = _stage.size
	game.start()


func skip() -> void:
	_close_card()
	_result = {"skipped": true, "score": 50, "lines": PackedStringArray()}
	_close()


func _process(_delta: float) -> void:
	if game == null or not game.running:
		return
	var left := game.time_left()
	_timer.text = "" if left < 0.0 else tr("mg.common.time_left") % ceili(left)
	if Input.is_action_just_pressed("pause_menu"):
		game.quit_early()


func _on_game_finished(score: int, lines: PackedStringArray) -> void:
	_result = {"skipped": false, "score": score, "lines": lines}
	var body := tr("mg.common.score") % score
	if not lines.is_empty():
		body += "\n" + "\n".join(lines)
	_card_with(rating(score), body, [["Continue", tr("mg.common.continue"), _close]])


static func rating(score: int) -> String:
	if score >= 85:
		return TranslationServer.translate("mg.common.rating_great")
	if score >= 60:
		return TranslationServer.translate("mg.common.rating_good")
	if score >= 35:
		return TranslationServer.translate("mg.common.rating_ok")
	return TranslationServer.translate("mg.common.rating_poor")


func _close() -> void:
	if _session != null:
		_session.world.clock.pop_pause(PAUSE_REASON)
	if _paused_tree:
		get_tree().paused = false
	var cb := _on_done
	var res := _result
	queue_free()
	if cb.is_valid():
		cb.call(res)
