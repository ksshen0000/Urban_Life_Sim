class_name Minigame
extends Control
## Base of every minigame plugin (D-038). A minigame is a full-screen Control that plays on its
## own (the world and the clock are paused by MinigameHost) and ends with a 0..100 score.
## Subclasses override: game_id(), title(), help(), _on_start(), _tick(delta), current_score(),
## and call finish() when done. They never touch the world: the host turns the score into a
## command (work pay) or just shows it (leisure).

signal finished(score: int, lines: PackedStringArray)

## Seconds the round lasts (0 = until the game ends itself). Shown in the host's top bar.
var time_limit := 0.0
var elapsed := 0.0
var running := false
var context: Dictionary = {}  # {"kind": "work" | "leisure", "look": player look, ...}
var _done := false


## The registry id this instance was created for (one script can serve several ids).
func game_id() -> String:
	return str(get_meta("game_id", ""))


func title() -> String:
	return tr("mg.%s.title" % game_id())


func help() -> String:
	return tr("mg.%s.help" % game_id())


func setup(p_context: Dictionary) -> void:
	context = p_context


func start() -> void:
	running = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	focus_mode = Control.FOCUS_ALL
	grab_focus()
	_on_start()


func time_left() -> float:
	return maxf(time_limit - elapsed, 0.0) if time_limit > 0.0 else -1.0


func is_done() -> bool:
	return _done


func _process(delta: float) -> void:
	if not running or _done:
		return
	elapsed += delta
	_tick(delta)
	if time_limit > 0.0 and elapsed >= time_limit and not _done:
		finish(current_score(), [tr("mg.common.time_up")])
	queue_redraw()


func finish(score: int, lines: PackedStringArray = []) -> void:
	if _done:
		return
	_done = true
	running = false
	finished.emit(clampi(score, 0, 100), lines)


## The player left early: the game ends with what has been achieved so far.
func quit_early() -> void:
	finish(current_score(), [tr("mg.common.quit_early")])


# --- overridables ---------------------------------------------------------------------------

func _on_start() -> void:
	pass


func _tick(_delta: float) -> void:
	pass


func current_score() -> int:
	return 0


# --- drawing helpers shared by the games ------------------------------------------------------

func font() -> Font:
	return WorldText.font()


func text_at(pos: Vector2, s: String, size: int, color: Color = Color("#fbf3dc"),
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font(), pos, s, align, width, size, color)


func panel(r: Rect2, fill: Color, border: Color = Color(0, 0, 0, 0.6)) -> void:
	draw_rect(r, fill)
	draw_rect(r, border, false, 3.0)


## Size of the play area (the whole host minus its top bar).
func area() -> Rect2:
	return Rect2(Vector2.ZERO, size)
