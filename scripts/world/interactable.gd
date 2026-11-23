class_name Interactable
extends Area2D
## A thing the player can use: sign, shop entrance, bed, bench (T005). Built from a map record.
## It only *describes* what it is; CityWorld decides what interacting does, and every resulting
## state change goes through a command. Detected by the player's sensor on collision layer 3.
## Origin = bottom-centre of its tile (y-sort anchor, D-019); the detection area covers the tile.

const INTERACTABLE_COLLISION_LAYER := 4  # layer 3
var data: Dictionary = {}
var _size := 32.0


func setup(record: Dictionary, tile_size: int) -> void:
	data = record.duplicate(true)
	_size = tile_size
	name = record["id"]
	position = (Vector2(record["tile"][0], record["tile"][1]) + Vector2(0.5, 1.0)) * float(tile_size)
	collision_layer = INTERACTABLE_COLLISION_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	var shape := RectangleShape2D.new()
	shape.size = Vector2(tile_size, tile_size)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = Vector2(0, -tile_size / 2.0)
	add_child(cs)
	queue_redraw()


func get_interactable_id() -> String:
	return data.get("id", "")


func get_kind() -> String:
	return data.get("kind", "")


func get_display_name() -> String:
	return tr(data.get("name_key", ""))


## Street ends (`walk_in` doors): entered by walking onto them, not by the interact key.
func is_walk_through() -> bool:
	return data.get("walk_in", false)


func get_prop() -> String:
	return data.get("prop", "none")


func _draw() -> void:
	if is_walk_through():
		_draw_exit_arrow()
		return
	var prop := get_prop()
	if prop != "none" and prop != "":
		PixelProps.draw(self, prop)


## A faint chevron on the road pointing off the map edge (left on the west edge, else right).
func _draw_exit_arrow() -> void:
	var dir := -1.0 if int(data["tile"][0]) == 0 else 1.0
	var c := Color(1, 1, 1, 0.55)
	for i in 2:
		var x := (-6.0 + i * 8.0) * dir
		var pts := PackedVector2Array([Vector2(x - 4 * dir, -24), Vector2(x + 4 * dir, -16), Vector2(x - 4 * dir, -8)])
		draw_polyline(pts, c, 3.0)
