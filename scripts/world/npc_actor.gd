class_name NpcActor
extends Interactable
## A named NPC standing at a location anchor (T013). Created and removed by CityWorld from the
## NPC schedule; talking to it opens that NPC's dialogue (T014). Visual only — where the NPC is
## comes from NpcScheduleSystem, never from this node. Drawn as a PixelPerson with a name tag.

signal arrived

## Walking speed for cutscene walks (world px / s).
const WALK_SPEED := 100.0

var npc_id := ""
## Shows a "!" bubble (the NPC has noticed the player).
var alert := false
var _path: Array[Vector2] = []
var _step := 0.0
var look: Dictionary = {}
var _t := 0.0
var _phase := 0.0
var _blink := false


var pose := "stand"
var facing := "down"


func setup_npc(npc: Dictionary, location_id: String, tile: Vector2i, tile_size: int,
		p_pose: String = "stand", p_facing: String = "down") -> void:
	pose = p_pose
	facing = p_facing
	setup({"id": npc["id"], "kind": "npc", "location_id": location_id, "tile": [tile.x, tile.y],
		"name_key": npc["name_key"]}, tile_size)
	npc_id = npc["id"]
	look = PixelPerson.normalize_look(npc["appearance"])
	_phase = float(absi(npc_id.hash()) % 100) / 25.0
	# The name tag is separate, smoothly filtered text; the sprite stays pixel-crisp.
	var label := tr(npc["name_key"])
	var w := WorldText.measure(label, 10) + 10.0
	var tag := WorldText.make(label, Rect2(-w / 2.0, -74, w, 14), 10, Color("#fbf7ec"), Color(0.08, 0.07, 0.1, 0.72))
	tag.name = "NameTag"
	add_child(tag)
	queue_redraw()


func location_id_of() -> String:
	return data.get("location_id", "")


## Walks through `points` (world positions, tile by tile); emits `arrived` at the end.
func walk_path(points: Array[Vector2]) -> void:
	_path = points.duplicate()
	if _path.is_empty():
		arrived.emit()


func is_walking() -> bool:
	return not _path.is_empty()


func face_towards(target: Vector2) -> void:
	var d := target - position
	facing = ("right" if d.x > 0 else "left") if absf(d.x) > absf(d.y) else ("down" if d.y > 0 else "up")
	queue_redraw()


func _process(delta: float) -> void:
	if not _path.is_empty():
		var to := _path[0] - position
		var step := WALK_SPEED * delta
		if to.length() <= step:
			position = _path[0]
			_path.remove_at(0)
			if _path.is_empty():
				_step = 0.0
				queue_redraw()
				arrived.emit()
				return
		else:
			face_towards(_path[0])
			position += to.normalized() * step
			_step += step
		queue_redraw()
	_t += delta
	var blink := fmod(_t + _phase, 4.0) < 0.14
	if blink != _blink:
		_blink = blink
		queue_redraw()


func _draw() -> void:
	var walking := not _path.is_empty()
	PixelPerson.draw(self, look, {"facing": facing,
		"legs": PixelPerson.walk_legs(_step) if walking else ("sit" if pose == "sit" else "stand"),
		"arm_r": "forward" if pose == "sit" and not walking else "down", "blink": _blink})
	if alert:
		# speech bubble with an exclamation mark, pixel style
		draw_rect(Rect2(-9, -96, 18, 20), Color("#2a2420"))
		draw_rect(Rect2(-7, -94, 14, 16), Color("#fbf7ec"))
		draw_rect(Rect2(-2, -80, 4, 4), Color("#2a2420"))
		draw_rect(Rect2(-2, -92, 4, 8), Color("#d84a4a"))
		draw_rect(Rect2(-2, -82, 4, 2), Color("#d84a4a"))
