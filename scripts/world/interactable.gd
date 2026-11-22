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


func get_prop() -> String:
	return data.get("prop", "none")


func _draw() -> void:
	var prop := get_prop()
	if prop != "none" and prop != "":
		PixelProps.draw(self, prop)
