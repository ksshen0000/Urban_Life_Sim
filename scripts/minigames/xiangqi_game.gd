extends Minigame
## Chinese chess against the old man in the park (red = you, moves first). Click a piece, then
## a highlighted point. Ends on checkmate, after 40 moves each (then judged on material), or when
## you stop. Score: win 100; otherwise from the material balance; loss 15.

const MAX_MOVES := 40
const AI_DEPTH := 2

var board := XiangqiRules.start_position()
var selected := Vector2i(-1, -1)
var targets: Array[Vector2i] = []
var moves_played := 0
var last_move: Array = []
var turn := "r"
var message := ""
var _ai_wait := 0.0


func _on_start() -> void:
	message = tr("mg.xiangqi.your_move")


func current_score() -> int:
	return clampi(50 + board.evaluate("r") / 40, 5, 95)


func _cell() -> float:
	return minf((size.y - 120) / 10.0, (size.x - 200) / 9.0)


func _origin() -> Vector2:
	var c := _cell()
	return Vector2((size.x - 8 * c) / 2.0, (size.y - 9 * c) / 2.0 + 10)


func point(p: Vector2i) -> Vector2:
	return _origin() + Vector2(p) * _cell()


func _input(event: InputEvent) -> void:
	if not running or turn != "r":
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local := (event as InputEventMouseButton).position - global_position
		var c := _cell()
		var p := Vector2i(roundi((local.x - _origin().x) / c), roundi((local.y - _origin().y) / c))
		if XiangqiRules.on_board(p):
			click(p)


## Select a red piece / move the selected piece to `p` (also used by tests).
func click(p: Vector2i) -> void:
	if targets.has(p) and selected.x >= 0:
		_play(selected, p)
		return
	if board.side_of(p) == "r":
		selected = p
		targets.clear()
		for m: Array in board.legal_moves("r"):
			if m[0] == p:
				targets.append(m[1])
	queue_redraw()


func _play(from: Vector2i, to: Vector2i) -> void:
	board.apply(from, to)
	last_move = [from, to]
	selected = Vector2i(-1, -1)
	targets.clear()
	moves_played += 1
	if board.is_checkmated("b"):
		finish(100, [tr("mg.xiangqi.you_won")])
		return
	turn = "b"
	message = tr("mg.xiangqi.thinking")
	_ai_wait = 0.5


func _tick(delta: float) -> void:
	if turn != "b":
		return
	_ai_wait -= delta
	if _ai_wait > 0.0:
		return
	var m := board.best_move("b", AI_DEPTH)
	if m.is_empty():
		finish(100, [tr("mg.xiangqi.you_won")])
		return
	board.apply(m[0], m[1])
	last_move = m
	turn = "r"
	if board.is_checkmated("r"):
		finish(15, [tr("mg.xiangqi.you_lost")])
		return
	if moves_played >= MAX_MOVES:
		finish(current_score(), [tr("mg.xiangqi.draw_by_moves")])
		return
	message = tr("mg.xiangqi.check") if board.in_check("r") else tr("mg.xiangqi.your_move")


func _draw() -> void:
	var c := _cell()
	if c < 8.0:
		return  # not laid out yet
	var o := _origin()
	panel(Rect2(o - Vector2(c * 0.7, c * 0.7), Vector2(8 * c, 9 * c) + Vector2(c * 1.4, c * 1.4)), Color("#d9b07a"), Color("#6b4a2f"))
	var line := Color("#5a3a22")
	for y in 10:
		draw_line(point(Vector2i(0, y)), point(Vector2i(8, y)), line, 2.0)
	for x in 9:
		if x == 0 or x == 8:
			draw_line(point(Vector2i(x, 0)), point(Vector2i(x, 9)), line, 2.0)
		else:
			draw_line(point(Vector2i(x, 0)), point(Vector2i(x, 4)), line, 2.0)
			draw_line(point(Vector2i(x, 5)), point(Vector2i(x, 9)), line, 2.0)
	for py in [0, 7]:
		draw_line(point(Vector2i(3, py)), point(Vector2i(5, py + 2)), line, 2.0)
		draw_line(point(Vector2i(5, py)), point(Vector2i(3, py + 2)), line, 2.0)
	var river := o + Vector2(0, 4.5 * c)
	text_at(river + Vector2(c * 1.0, c * 0.18), "楚 河", int(c * 0.45), Color("#5a3a22"))
	text_at(river + Vector2(c * 5.2, c * 0.18), "汉 界", int(c * 0.45), Color("#5a3a22"))
	if last_move.size() == 2:
		for q: Vector2i in last_move:
			draw_rect(Rect2(point(q) - Vector2(c, c) * 0.48, Vector2(c, c) * 0.96), Color(0.2, 0.6, 1.0, 0.25))
	for p: Vector2i in board.cells:
		var piece: String = board.cells[p]
		var center := point(p)
		var r := c * 0.42
		draw_circle(center + Vector2(2, 3), r, Color(0, 0, 0, 0.3))
		draw_circle(center, r, Color("#f4e2bc"))
		var col := Color("#c0392b") if piece[0] == "r" else Color("#222222")
		draw_arc(center, r * 0.84, 0, TAU, 32, col, 2.0)
		if p == selected:
			draw_arc(center, r + 4, 0, TAU, 32, Color("#f2d27a"), 4.0)
		var fs := int(c * 0.5)
		text_at(center + Vector2(-r, fs * 0.36), XiangqiRules.NAMES[piece], fs, col, HORIZONTAL_ALIGNMENT_CENTER, r * 2)
	for t in targets:
		draw_circle(point(t), c * 0.14, Color(0.15, 0.65, 0.3, 0.85))
	text_at(Vector2(40, 60), message, 30, Color("#fbf3dc"))
	text_at(Vector2(40, 100), tr("mg.xiangqi.moves") % [moves_played, MAX_MOVES], 22, Color("#a9a294"))
