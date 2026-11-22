class_name AmbientActor
extends Node2D
## A park regular or passer-by (map `ambient` record): presentation only, never world state, not
## interactive. CityWorld shows it while its activity is open (or during its own hours) so the
## park visibly comes alive at the right times. Origin = feet (y-sort anchor).


var record: Dictionary = {}
var look: Dictionary = {}
var _facing := "down"
var _t := 0.0
var _phase := 0.0


func setup(p_record: Dictionary, map: Dictionary) -> void:
	record = p_record.duplicate(true)
	name = "ambient_" + str(record["id"])
	position = CityMapBuilder.tile_foot(map, Vector2i(record["tile"][0], record["tile"][1]))
	_facing = record.get("facing", "down")
	var raw := {"top": record["shirt"], "hair": record["hair"]}
	for k in ["hair_style", "outfit", "figure", "bottom", "skin", "shoes", "vest"]:
		if record.has(k):
			raw[k] = record[k]
	look = PixelPerson.normalize_look(raw)
	_phase = float(absi(str(record["id"]).hash()) % 1000) / 1000.0 * TAU  # desync neighbours


## Shown now? Linked to an activity: while it is open. Own hours: inside one. Else: always.
static func is_visible_at(p_record: Dictionary, content: ContentRegistry, minute_of_day: int) -> bool:
	if p_record.has("activity_id"):
		return ActivityRules.is_open(content.get_record("activities", p_record["activity_id"]), minute_of_day)
	if p_record.has("hours"):
		return ActivityRules.is_open({"hours": p_record["hours"]}, minute_of_day)
	return true


func get_pose() -> String:
	return record.get("pose", "stand")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## Sprite state for the pose at time t (seconds, desynchronized per person).
func pose_state(t: float) -> Dictionary:
	var st := {"facing": _facing, "legs": "stand", "blink": fmod(t, 4.0) < 0.14}
	match get_pose():
		"chess":
			# think, think, think... move a piece
			st["legs"] = "sit"
			st["arm_r"] = "forward" if sin(t * 0.8) > 0.75 else "down"
		"sing":
			st["arm_l"] = "forward"
			st["arm_r"] = "forward"
			st["mouth"] = "open" if fmod(t, 0.9) < 0.55 else "closed"
		"erhu":
			st["legs"] = "sit"
			st["arm_r"] = "forward"
		"dance":
			var beat := int(t / 0.45) % 2 == 0
			st["arm_l"] = "up" if beat else "out"
			st["arm_r"] = "out" if beat else "up"
			st["legs"] = "step_l" if beat else "step_r"
		"taichi":
			var k := int(t / 1.3) % 3
			st["arm_l"] = ["forward", "out", "forward"][k]
			st["arm_r"] = ["forward", "out", "down"][k]
		"eat":
			st["legs"] = "sit"
			st["arm_r"] = "forward" if fmod(t, 1.6) < 0.5 else "down"
		"work":
			# hammering / shovelling: arms up and down
			var up := fmod(t, 0.8) < 0.4
			st["arm_l"] = "up" if up else "forward"
			st["arm_r"] = "up" if up else "forward"
		"browse":
			st["arm_r"] = "forward" if fmod(t, 3.0) < 0.8 else "down"
		"fish":
			st["legs"] = "sit"
			st["arm_r"] = "forward"
			st["arm_l"] = "forward"
	return st


func _draw() -> void:
	var t := _t + _phase
	var sway := Vector2.ZERO
	if get_pose() == "sing":
		sway.x = 2.0 if fmod(t, 2.4) < 1.2 else 0.0
	PixelPerson.draw(self, look, pose_state(t), sway)
	match get_pose():
		"sing":
			for i in 2:
				var k := fmod(t * 0.5 + i * 0.5, 1.0)
				_note(Vector2(12 + k * 8, -58 - k * 18), Color(0.98, 0.9, 0.5, 1.0 - k))
		"erhu":
			var x := 10.0 if _facing == "right" else -10.0
			draw_line(Vector2(x, -10), Vector2(x + 2, -40), Color("#3a2218"), 2.0)
			draw_rect(Rect2(x - 3, -16, 6, 5), Color("#5a3322"))
			var bow := sin(t * 2.4) * 7.0
			draw_line(Vector2(x - 12 + bow, -22), Vector2(x + 8 + bow, -24), Color("#e8dcb8"), 1.5)
		"fish":
			draw_line(Vector2(4, -14), Vector2(26, -46), Color("#6b4a2f"), 2.0)
			var bob := sin(t * 1.3) * 1.5
			draw_line(Vector2(26, -46), Vector2(32, 30 + bob), Color(1, 1, 1, 0.45), 1.0)
			draw_circle(Vector2(32, 30 + bob), 2.0, Color("#e04a4a"))


## A little eighth note (no font glyph needed).
func _note(p: Vector2, c: Color) -> void:
	draw_circle(p, 2.5, c)
	draw_line(p + Vector2(2.2, 0), p + Vector2(2.2, -9), c, 1.2)
	draw_line(p + Vector2(2.2, -9), p + Vector2(6, -6), c, 1.2)
