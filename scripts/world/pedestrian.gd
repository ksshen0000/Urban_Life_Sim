class_name Pedestrian
extends Interactable
## A passer-by from a map's `pedestrians` (D-039): walks its route back and forth at its own pace,
## and has a line of chat when you press E next to it (CityWorld routes kind "pedestrian").
## Presentation only: nothing about passers-by is in the world state or the save.

var record: Dictionary = {}
var look: Dictionary = {}
var _points: Array[Vector2] = []
var _target := 1
var _dir := 1
var _step := 0.0
var _facing := "down"
var speed := 45.0


func setup_pedestrian(p_record: Dictionary, map: Dictionary) -> void:
	record = p_record.duplicate(true)
	var path: Array = record["path"]
	setup({"id": "ped_" + str(record["id"]), "kind": "pedestrian", "location_id": "", "tile": path[0],
		"name_key": record["name_key"]}, map["tile_size"])
	for t: Array in path:
		_points.append(CityMapBuilder.tile_foot(map, Vector2i(t[0], t[1])))
	position = _points[0]
	speed = float(record.get("speed", 45))
	var raw := {"top": record["shirt"], "hair": record["hair"]}
	for k in ["hair_style", "outfit", "figure", "bottom", "skin", "shoes", "vest"]:
		if record.has(k):
			raw[k] = record[k]
	look = PixelPerson.normalize_look(raw)


## Today's line: one of `lines`, chosen by the day so it stays the same all day.
func line_for_day(day: int) -> String:
	var lines: Array = record["lines"]
	return lines[(day + absi(str(record["id"]).hash())) % lines.size()]


static func is_visible_at(p_record: Dictionary, minute_of_day: int) -> bool:
	return not p_record.has("hours") or ActivityRules.is_open({"hours": p_record["hours"]}, minute_of_day)


func _process(delta: float) -> void:
	if _points.size() < 2:
		return
	var to := _points[_target] - position
	var step := speed * delta
	if to.length() <= step:
		position = _points[_target]
		if _target + _dir < 0 or _target + _dir >= _points.size():
			_dir = -_dir
		_target += _dir
	else:
		position += to.normalized() * step
		_facing = ("right" if to.x > 0 else "left") if absf(to.x) > absf(to.y) else ("down" if to.y > 0 else "up")
	_step += step
	queue_redraw()


func _draw() -> void:
	PixelPerson.draw(self, look, {"facing": _facing, "legs": PixelPerson.walk_legs(_step)})
