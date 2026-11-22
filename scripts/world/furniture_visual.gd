class_name FurnitureVisual
extends StaticBody2D
## A piece of indoor furniture (D-034) from a map `furniture` record: a PixelProps sprite
## anchored at the bottom-centre of its footprint (y-sort), blocking the footprint
## (ContentSchemas.FURNITURE) unless it is walk-through (chairs, door mats).

var kind := ""


func setup(record: Dictionary, tile_size: int, index: int) -> void:
	kind = record["kind"]
	name = "furniture_%s_%d" % [kind, index]
	var size: Array = ContentSchemas.FURNITURE[kind]
	var w := maxi(int(size[0]), 1)
	position = (Vector2(record["tile"][0], record["tile"][1]) + Vector2(w / 2.0, 1.0)) * float(tile_size)
	collision_layer = CityMapBuilder.WORLD_COLLISION_LAYER
	collision_mask = 0
	if int(size[0]) > 0:
		var shape := RectangleShape2D.new()
		shape.size = Vector2(int(size[0]), int(size[1])) * float(tile_size)
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = Vector2(0, -shape.size.y / 2.0)
		add_child(cs)
	queue_redraw()


func is_blocking() -> bool:
	return int(ContentSchemas.FURNITURE[kind][0]) > 0


func _draw() -> void:
	PixelProps.draw(self, kind)
