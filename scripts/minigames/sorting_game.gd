extends Minigame
## Warehouse sorting: parcels ride down the belt; send each one to its chute with ← (A, red),
## ↓ (B, blue) or → (C, green) while it is in the yellow zone. The belt speeds up. 60 seconds.
## Score from correct parcels (wrong or missed ones cost points).

const CHUTES := ["A", "B", "C"]
const CHUTE_COLORS := [Color("#d84a4a"), Color("#2f6fb0"), Color("#3fa06a")]
const KEYS := [KEY_LEFT, KEY_DOWN, KEY_RIGHT]

var rng := RandomNumberGenerator.new()
var parcels: Array[Dictionary] = []  # {y, chute, done}
var correct := 0
var wrong := 0
var missed := 0
var _spawn := 0.0


func _on_start() -> void:
	time_limit = 60.0
	rng.seed = int(context.get("seed", 37))


func speed() -> float:
	return 170.0 + elapsed * 3.0


func zone() -> Vector2:
	return Vector2(size.y - 330, size.y - 210)


func current_score() -> int:
	return clampi(correct * 4 - wrong * 4 - missed * 2, 0, 100)


## Route the parcel in the zone to chute `c` (also used by tests). Returns true if it was right.
func route(c: int) -> bool:
	var z := zone()
	for p in parcels:
		if not p["done"] and float(p["y"]) >= z.x and float(p["y"]) <= z.y:
			p["done"] = true
			if int(p["chute"]) == c:
				correct += 1
				return true
			wrong += 1
			return false
	return false


func _input(event: InputEvent) -> void:
	if running and event is InputEventKey and event.pressed and not event.echo:
		var c := KEYS.find((event as InputEventKey).keycode)
		if c < 0:
			c = ["a", "s", "d"].find(OS.get_keycode_string((event as InputEventKey).keycode).to_lower())
		if c >= 0:
			route(c)


func _tick(delta: float) -> void:
	_spawn -= delta
	if _spawn <= 0.0:
		parcels.append({"y": 40.0, "chute": rng.randi() % 3, "done": false})
		_spawn = maxf(0.55, 1.3 - elapsed * 0.012)
	for p in parcels:
		p["y"] = float(p["y"]) + speed() * delta
		if not p["done"] and float(p["y"]) > zone().y:
			p["done"] = true
			missed += 1
	parcels = parcels.filter(func(p: Dictionary) -> bool: return float(p["y"]) < size.y + 40 and not (p["done"] and float(p["y"]) < zone().x))


func _draw() -> void:
	var cx := size.x / 2.0
	draw_rect(Rect2(cx - 110, 20, 220, size.y - 40), Color("#3a3f46"))
	for y in range(int(fmod(elapsed * speed(), 40.0)), int(size.y), 40):
		draw_line(Vector2(cx - 110, y), Vector2(cx + 110, y), Color(0, 0, 0, 0.3), 2.0)
	var z := zone()
	draw_rect(Rect2(cx - 120, z.x, 240, z.y - z.x), Color(0.95, 0.8, 0.3, 0.18))
	for i in 3:
		var chute := Rect2(cx - 420 + i * 300, size.y - 120, 240, 90)
		panel(chute, CHUTE_COLORS[i])
		text_at(chute.position + Vector2(0, 58), "%s  %s" % [["←", "↓", "→"][i], CHUTES[i]], 36, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, chute.size.x)
	for p in parcels:
		if p["done"]:
			continue
		var r := Rect2(cx - 60, float(p["y"]) - 45, 120, 90)
		panel(r, Color("#c9a77a"), Color("#6b4a2f"))
		draw_rect(Rect2(r.position + Vector2(30, 24), Vector2(60, 42)), CHUTE_COLORS[p["chute"]])
		text_at(r.position + Vector2(0, 58), CHUTES[p["chute"]], 32, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	text_at(Vector2(40, 60), tr("mg.sorting.status") % [correct, wrong, missed], 26)
