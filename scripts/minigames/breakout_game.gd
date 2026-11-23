extends Minigame
## Arcade "打砖块": move the paddle with the mouse or ←/→, keep the ball up, clear the wall.
## 3 lives, 90 seconds. Score = share of bricks broken (all cleared = 100).

const COLS := 12
const ROWS := 6
const PADDLE_W := 160.0
const BALL_R := 9.0
const ROW_COLORS := [Color("#e04aa0"), Color("#d84a4a"), Color("#e07a2e"), Color("#f2c94c"), Color("#3fa06a"), Color("#4ad0e0")]

var field := Rect2()
var bricks: Array[Rect2] = []
var brick_rows: Array[int] = []
var total := 0
var paddle_x := 0.0
var ball := Vector2.ZERO
var vel := Vector2.ZERO
var lives := 3
var launched := false


func _on_start() -> void:
	time_limit = 90.0
	var w := minf(size.x - 200, 1100.0)
	field = Rect2((size.x - w) / 2.0, 40, w, size.y - 80)
	var bw := (w - 20) / COLS
	for r in ROWS:
		for c in COLS:
			bricks.append(Rect2(field.position.x + 10 + c * bw + 2, field.position.y + 60 + r * 30, bw - 4, 24))
			brick_rows.append(r)
	total = bricks.size()
	paddle_x = field.get_center().x
	_reset_ball()


func _reset_ball() -> void:
	launched = false
	ball = Vector2(paddle_x, field.end.y - 60)
	vel = Vector2.ZERO


func launch() -> void:
	if not launched:
		launched = true
		vel = Vector2(260, -520)


func current_score() -> int:
	return (total - bricks.size()) * 100 / maxi(total, 1)


func _input(event: InputEvent) -> void:
	if not running:
		return
	if event is InputEventMouseMotion:
		paddle_x = clampf((event as InputEventMouseMotion).position.x - global_position.x, field.position.x + PADDLE_W / 2, field.end.x - PADDLE_W / 2)
	elif (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_SPACE):
		launch()


func _tick(delta: float) -> void:
	var dir := float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
	paddle_x = clampf(paddle_x + dir * 700 * delta, field.position.x + PADDLE_W / 2, field.end.x - PADDLE_W / 2)
	if not launched:
		ball = Vector2(paddle_x, field.end.y - 60)
		return
	step(delta)


func step(delta: float) -> void:
	ball += vel * delta
	if ball.x < field.position.x + BALL_R or ball.x > field.end.x - BALL_R:
		vel.x = -vel.x
		ball.x = clampf(ball.x, field.position.x + BALL_R, field.end.x - BALL_R)
	if ball.y < field.position.y + BALL_R:
		vel.y = absf(vel.y)
	var paddle := Rect2(paddle_x - PADDLE_W / 2, field.end.y - 44, PADDLE_W, 16)
	if vel.y > 0 and paddle.grow(BALL_R).has_point(ball):
		var off := (ball.x - paddle_x) / (PADDLE_W / 2)
		vel = Vector2(off * 480, -absf(vel.y) * 1.02).limit_length(900)
	for i in range(bricks.size() - 1, -1, -1):
		if bricks[i].grow(BALL_R).has_point(ball):
			var b := bricks[i]
			if ball.x < b.position.x or ball.x > b.end.x:
				vel.x = -vel.x
			else:
				vel.y = -vel.y
			bricks.remove_at(i)
			brick_rows.remove_at(i)
			break
	if bricks.is_empty():
		finish(100, [tr("mg.breakout.cleared")])
	elif ball.y > field.end.y:
		lives -= 1
		if lives <= 0:
			finish(current_score(), [tr("mg.breakout.no_lives")])
		else:
			_reset_ball()


func _draw() -> void:
	panel(field, Color("#1c1a2e"), Color("#4ad0e0"))
	for i in bricks.size():
		draw_rect(bricks[i], ROW_COLORS[brick_rows[i] % ROW_COLORS.size()])
		draw_rect(Rect2(bricks[i].position, Vector2(bricks[i].size.x, 4)), Color(1, 1, 1, 0.25))
	draw_rect(Rect2(paddle_x - PADDLE_W / 2, field.end.y - 44, PADDLE_W, 16), Color("#fbf3dc"))
	draw_circle(ball, BALL_R, Color("#f2d27a"))
	text_at(field.position + Vector2(10, 36), tr("mg.breakout.status") % [lives, current_score()], 24)
	if not launched:
		text_at(Vector2(field.position.x, field.end.y - 100), tr("mg.breakout.launch"), 26, Color("#f2d27a"), HORIZONTAL_ALIGNMENT_CENTER, field.size.x)
