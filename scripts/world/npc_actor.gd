class_name NpcActor
extends Interactable
## A named NPC standing at a location anchor (T013). Created and removed by CityWorld from the
## NPC schedule; talking to it opens that NPC's dialogue (T014). Visual only — where the NPC is
## comes from NpcScheduleSystem, never from this node. Drawn as a PixelPerson with a name tag.

var npc_id := ""
var look: Dictionary = {}
var _t := 0.0
var _phase := 0.0
var _blink := false


func setup_npc(npc: Dictionary, location_id: String, tile: Vector2i, tile_size: int) -> void:
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


func _process(delta: float) -> void:
	_t += delta
	var blink := fmod(_t + _phase, 4.0) < 0.14
	if blink != _blink:
		_blink = blink
		queue_redraw()


func _draw() -> void:
	PixelPerson.draw(self, look, {"facing": "down", "legs": "stand", "blink": _blink})
