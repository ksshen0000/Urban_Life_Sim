extends Minigame
## Building-site bricklaying: the brick slides back and forth; press Space (or click) to set it
## on the wall. Only the part over the brick below stays; miss completely and the round ends.
## 15 courses. Score from courses laid and how much of the width you kept.

const COURSES := 15
const START_W := 280.0
const H := 34.0

var stack: Array[Rect2] = []
var current := Rect2()
var dir := 1.0
var perfects := 0


func _on_start() -> void:
	var base := Rect2(size.x / 2.0 - START_W / 2.0, size.y - 120, START_W, H)
	stack = [base]
	_new_brick()


func _new_brick() -> void:
	var top: Rect2 = stack[-1]
	current = Rect2(size.x / 2.0 - 500, top.position.y - H, top.size.x, H)
	dir = 1.0


func speed() -> float:
	return 360.0 + stack.size() * 28.0


func current_score() -> int:
	var laid := stack.size() - 1
	return clampi(int(100.0 * laid / COURSES * (0.5 + 0.5 * stack[-1].size.x / START_W)), 0, 100)


## Drop the moving brick (also used by tests). Returns the width that stayed.
func drop() -> float:
	var top: Rect2 = stack[-1]
	var left := maxf(current.position.x, top.position.x)
	var right := minf(current.end.x, top.end.x)
	if right <= left:
		finish(current_score(), [tr("mg.bricks.fell")])
		return 0.0
	if absf(current.position.x - top.position.x) < 6.0:
		left = top.position.x
		right = top.end.x
		perfects += 1
	stack.append(Rect2(left, current.position.y, right - left, H))
	if stack.size() - 1 >= COURSES:
		finish(current_score(), [tr("mg.bricks.done") % perfects])
	else:
		_new_brick()
	return right - left


func _input(event: InputEvent) -> void:
	if not running:
		return
	if (event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_SPACE) \
			or (event is InputEventMouseButton and event.pressed):
		drop()


func _tick(delta: float) -> void:
	current.position.x += dir * speed() * delta
	if current.position.x < size.x / 2.0 - 520 or current.end.x > size.x / 2.0 + 520:
		dir = -dir


func _draw() -> void:
	var shift := maxf(0.0, (stack.size() - 8) * H)
	draw_set_transform(Vector2(0, shift))
	draw_rect(Rect2(0, size.y - 86, size.x, 86), Color("#a8835a"))
	for i in stack.size():
		_brick(stack[i], i == 0)
	if running:
		_brick(current, false)
	draw_set_transform(Vector2.ZERO)
	text_at(Vector2(40, 60), tr("mg.bricks.status") % [stack.size() - 1, COURSES], 26)


func _brick(r: Rect2, base: bool) -> void:
	draw_rect(r, Color("#8a8f99") if base else Color("#b0563a"))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 5)), Color(1, 1, 1, 0.2))
	draw_rect(r, Color(0, 0, 0, 0.4), false, 2.0)
