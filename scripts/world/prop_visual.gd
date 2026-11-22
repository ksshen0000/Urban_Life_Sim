class_name PropVisual
extends Node2D
## Y-sorted scenery (tree, pavilion, lamp, flower bed) drawn as PixelProps sprites. Origin = the
## feet / ground contact point, so it sorts correctly against the player.

var kind := "tree"
var variant := 0


func setup(p_kind: String, foot: Vector2, prop_name: String) -> void:
	kind = p_kind
	position = foot
	name = prop_name
	variant = absi(prop_name.hash()) % 3
	queue_redraw()


func _draw() -> void:
	PixelProps.draw(self, kind, variant)
