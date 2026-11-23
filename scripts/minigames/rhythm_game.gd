extends Minigame
## Rhythm game for the dance machine ("dance") and the plaza ("square_dance", slower, gentler):
## arrows rise to the target line; press the matching arrow key as each one arrives.
## Perfect / good / miss windows; score = weighted accuracy.

const LANES := ["ui_left", "ui_down", "ui_up", "ui_right"]
const KEYS := [KEY_LEFT, KEY_DOWN, KEY_UP, KEY_RIGHT]
const SYMBOLS := ["←", "↓", "↑", "→"]
const LANE_COLORS := [Color("#e04aa0"), Color("#4ad0e0"), Color("#3fa06a"), Color("#f2c94c")]
const PERFECT := 0.08
const GOOD := 0.18

var notes: Array[Dictionary] = []  # {t, lane, state: "" | "perfect" | "good" | "miss"}
var bpm := 128.0
var travel := 1.6  # seconds from spawn to target
var flash := ""
var _flash_t := 0.0


func _on_start() -> void:
	var gentle := game_id() == "square_dance"
	bpm = 92.0 if gentle else 128.0
	time_limit = 45.0 if gentle else 50.0
	travel = 2.0 if gentle else 1.5
	var beat := 60.0 / bpm
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024 if gentle else 1997  # fixed charts: the same song every time
	var t := 2.0
	while t < time_limit - 1.0:
		notes.append({"t": t, "lane": rng.randi() % 4, "state": ""})
		if not gentle and rng.randf() < 0.25:
			t += beat / 2.0
		else:
			t += beat * (2.0 if gentle and rng.randf() < 0.4 else 1.0)


func current_score() -> int:
	var judged := 0
	var points := 0.0
	for n in notes:
		if n["state"] != "":
			judged += 1
			points += 1.0 if n["state"] == "perfect" else (0.6 if n["state"] == "good" else 0.0)
	return int(100.0 * points / maxf(judged, 1.0)) if judged > 0 else 0


## Judge a key press on `lane` at time `now` (also used by tests).
func press(lane: int, now: float) -> String:
	var best: Dictionary = {}
	var best_d := INF
	for n in notes:
		if n["state"] == "" and n["lane"] == lane:
			var d := absf(float(n["t"]) - now)
			if d < best_d:
				best_d = d
				best = n
	if best.is_empty() or best_d > GOOD:
		return ""
	best["state"] = "perfect" if best_d <= PERFECT else "good"
	flash = tr("mg.rhythm." + str(best["state"]))
	_flash_t = 0.4
	return best["state"]


func _input(event: InputEvent) -> void:
	if not running or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var lane := KEYS.find((event as InputEventKey).keycode)
	if lane < 0:
		lane = ["a", "s", "w", "d"].find(OS.get_keycode_string((event as InputEventKey).keycode).to_lower())
	if lane >= 0:
		press(lane, elapsed)


func _tick(delta: float) -> void:
	_flash_t -= delta
	for n in notes:
		if n["state"] == "" and elapsed - float(n["t"]) > GOOD:
			n["state"] = "miss"


func _draw() -> void:
	var lane_w := 140.0
	var x0 := (size.x - lane_w * 4) / 2.0
	var target_y := 140.0
	var speed := (size.y - 80 - target_y) / travel
	for i in 4:
		draw_rect(Rect2(x0 + i * lane_w + 6, 20, lane_w - 12, size.y - 40), Color(1, 1, 1, 0.04))
		var held := Input.is_key_pressed(KEYS[i])
		draw_rect(Rect2(x0 + i * lane_w + 14, target_y - 34, lane_w - 28, 68), (LANE_COLORS[i] as Color) * Color(1, 1, 1, 0.9 if held else 0.35), false, 4.0)
		text_at(Vector2(x0 + i * lane_w, target_y + 14), SYMBOLS[i], 40, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER, lane_w)
	for n in notes:
		if n["state"] != "":
			continue
		var y := target_y + (float(n["t"]) - elapsed) * speed
		if y > size.y or y < -60:
			continue
		var lane: int = n["lane"]
		draw_rect(Rect2(x0 + lane * lane_w + 18, y - 28, lane_w - 36, 56), LANE_COLORS[lane])
		text_at(Vector2(x0 + lane * lane_w, y + 14), SYMBOLS[lane], 40, Color("#14131a"), HORIZONTAL_ALIGNMENT_CENTER, lane_w)
	if _flash_t > 0.0:
		text_at(Vector2(0, target_y + 120), flash, 48, Color("#f2d27a"), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	text_at(Vector2(40, 60), tr("mg.rhythm.accuracy") % current_score(), 26)
