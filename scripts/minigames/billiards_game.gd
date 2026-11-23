extends Minigame
## Billiards: pocket the seven coloured balls in at most 10 shots. Aim with the mouse (or ←/→),
## hold the left button (or Space) to build power, release to strike. Simple physics: rolling
## friction, elastic equal-mass collisions, cushions, six pockets. Pocketing the cue ball costs
## the shot and puts it back. Score = coloured balls pocketed / 7.

const SHOTS := 10
const R := 13.0
const FRICTION := 0.978
const POCKET_R := 26.0
const MAX_SPEED := 1500.0
const COLORS := [Color("#f2c94c"), Color("#2f6fb0"), Color("#d84a4a"), Color("#8a5ad0"), Color("#e07a2e"),
	Color("#3fa06a"), Color("#8a3b2e")]

var table := Rect2()
var balls: Array[Dictionary] = []  # {pos, vel, color, cue, in}
var shots_left := SHOTS
var aim := 0.0
var power := 0.0
var charging := false
var potted := 0
var note := ""


func _on_start() -> void:
	var w := minf(size.x - 160, 1300.0)
	var h := w * 0.5
	table = Rect2((size.x - w) / 2.0, (size.y - h) / 2.0 + 20, w, h)
	balls.clear()
	balls.append({"pos": table.position + Vector2(w * 0.25, h * 0.5), "vel": Vector2.ZERO, "color": Color.WHITE, "cue": true, "in": false})
	var apex := table.position + Vector2(w * 0.68, h * 0.5)
	var i := 0
	for row in 4:
		for k in row + 1:
			if i >= COLORS.size():
				break
			var p := apex + Vector2(row * R * 1.8, (k - row / 2.0) * R * 2.05)
			balls.append({"pos": p, "vel": Vector2.ZERO, "color": COLORS[i], "cue": false, "in": false})
			i += 1


func current_score() -> int:
	return potted * 100 / COLORS.size()


func cue() -> Dictionary:
	return balls[0]


func moving() -> bool:
	for b in balls:
		if not b["in"] and (b["vel"] as Vector2).length() > 12.0:
			return true
	return false


func pockets() -> Array[Vector2]:
	var t := table
	return [t.position, Vector2(t.get_center().x, t.position.y), Vector2(t.end.x, t.position.y),
		Vector2(t.position.x, t.end.y), Vector2(t.get_center().x, t.end.y), t.end] as Array[Vector2]


## Strike the cue ball (also used by tests). `strength` 0..1.
func shoot(angle: float, strength: float) -> void:
	if moving() or shots_left <= 0:
		return
	cue()["vel"] = Vector2.from_angle(angle) * MAX_SPEED * clampf(strength, 0.05, 1.0)
	shots_left -= 1
	note = ""


func _input(event: InputEvent) -> void:
	if not running:
		return
	if event is InputEventMouseMotion:
		var local := (event as InputEventMouseMotion).position - global_position
		aim = (local - (cue()["pos"] as Vector2)).angle()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_charge(event.pressed)
	elif event is InputEventKey and (event as InputEventKey).keycode == KEY_SPACE and not event.echo:
		_charge(event.pressed)


func _charge(pressed: bool) -> void:
	if pressed and not moving():
		charging = true
		power = 0.0
	elif not pressed and charging:
		charging = false
		shoot(aim, power)


func _tick(delta: float) -> void:
	if Input.is_key_pressed(KEY_LEFT):
		aim -= 1.6 * delta
	if Input.is_key_pressed(KEY_RIGHT):
		aim += 1.6 * delta
	if charging:
		power = fmod(power + delta * 0.8, 1.0)
	var steps := 4
	for s in steps:
		step(delta / steps)
	if not moving() and shots_left <= 0:
		finish(current_score(), [tr("mg.billiards.result") % [potted, COLORS.size()]])
	elif potted >= COLORS.size():
		finish(100, [tr("mg.billiards.cleared")])


func step(dt: float) -> void:
	for b in balls:
		if b["in"]:
			continue
		b["pos"] += b["vel"] * dt
		b["vel"] *= pow(FRICTION, dt * 60.0)
		if (b["vel"] as Vector2).length() < 12.0:
			b["vel"] = Vector2.ZERO
		var p: Vector2 = b["pos"]
		var v: Vector2 = b["vel"]
		if p.x < table.position.x + R:
			p.x = table.position.x + R
			v.x = absf(v.x) * 0.85
		if p.x > table.end.x - R:
			p.x = table.end.x - R
			v.x = -absf(v.x) * 0.85
		if p.y < table.position.y + R:
			p.y = table.position.y + R
			v.y = absf(v.y) * 0.85
		if p.y > table.end.y - R:
			p.y = table.end.y - R
			v.y = -absf(v.y) * 0.85
		b["pos"] = p
		b["vel"] = v
		for pk in pockets():
			if p.distance_to(pk) < POCKET_R:
				_pot(b)
				break
	for i in balls.size():
		for j in range(i + 1, balls.size()):
			var a: Dictionary = balls[i]
			var c: Dictionary = balls[j]
			if a["in"] or c["in"]:
				continue
			var d: Vector2 = (c["pos"] as Vector2) - (a["pos"] as Vector2)
			var dist := d.length()
			if dist > 0.0 and dist < 2 * R:
				var n := d / dist
				var overlap := 2 * R - dist
				a["pos"] -= n * overlap / 2.0
				c["pos"] += n * overlap / 2.0
				var rel := ((a["vel"] as Vector2) - (c["vel"] as Vector2)).dot(n)
				if rel > 0.0:
					a["vel"] -= n * rel
					c["vel"] += n * rel


func _pot(b: Dictionary) -> void:
	if b["cue"]:
		b["pos"] = table.position + Vector2(table.size.x * 0.25, table.size.y * 0.5)
		b["vel"] = Vector2.ZERO
		note = tr("mg.billiards.scratch")
		return
	b["in"] = true
	b["vel"] = Vector2.ZERO
	potted += 1


func _draw() -> void:
	panel(table.grow(30), Color("#6b4a2f"), Color("#3a2618"))
	draw_rect(table, Color("#2f7a4a"))
	for pk in pockets():
		draw_circle(pk, POCKET_R, Color("#14131a"))
	for b in balls:
		if b["in"]:
			continue
		draw_circle((b["pos"] as Vector2) + Vector2(2, 3), R, Color(0, 0, 0, 0.3))
		draw_circle(b["pos"], R, b["color"])
		draw_circle((b["pos"] as Vector2) + Vector2(-4, -4), 4, Color(1, 1, 1, 0.5))
	if not moving() and shots_left > 0:
		var from: Vector2 = cue()["pos"]
		var dir := Vector2.from_angle(aim)
		draw_line(from + dir * (R + 6), from + dir * 320, Color(1, 1, 1, 0.35), 2.0)
		var back := 30.0 + power * 80.0
		draw_line(from - dir * back, from - dir * (back + 260), Color("#c9a060"), 6.0)
	var bar := Rect2(table.position.x, table.end.y + 50, 300, 18)
	draw_rect(bar, Color(1, 1, 1, 0.12))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * power, bar.size.y)), Color("#f2d27a"))
	text_at(Vector2(table.position.x + 320, table.end.y + 66), tr("mg.billiards.status") % [shots_left, potted, COLORS.size()], 24)
	if not note.is_empty():
		text_at(Vector2(table.position.x, table.position.y - 44), note, 24, Color("#f2a35a"))
