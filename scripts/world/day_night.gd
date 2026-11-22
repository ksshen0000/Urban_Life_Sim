class_name DayNight
extends Node
## Day / night presentation (D-035). Darkens the outdoor world by tinting each world drawing
## (`self_modulate` of the ground, road markings and every y-sorted entity, so children such as
## name tags and window glows are left untouched), and drives the light that must stay bright:
##  - lamp pools: a ground-level layer between the decals and the entities (people stand in them);
##  - lit windows: each building's own WindowGlow child, y-sorted with the building, so a person
##    standing in front of a building is drawn over its windows.
## Indoor maps (`indoor: true`) are lamp-lit and stay untinted.

## Shared glow strength (0 by day, 1 deep at night) read by WindowGlow / lamp heads.
static var glow_strength := 0.0

var indoor := false
var _tinted: Array[CanvasItem] = []
var _entities: Node
var _ground_glow: _GroundGlow
var _tint := Color.WHITE


func setup(ground: CanvasItem, markings: CanvasItem, entities: Node) -> void:
	_tinted = [ground, markings]
	_entities = entities
	_ground_glow = _GroundGlow.new()
	_ground_glow.name = "GroundGlow"
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_ground_glow.material = add
	# between the decals and the entities
	entities.get_parent().add_child(_ground_glow)
	entities.get_parent().move_child(_ground_glow, entities.get_index())


func set_sources(lamps: Array[Vector2], p_indoor: bool) -> void:
	indoor = p_indoor
	_ground_glow.lamps = lamps
	_ground_glow.queue_redraw()


func update(minute_of_day: float) -> void:
	_tint = Color.WHITE if indoor else DayCycle.tint(minute_of_day)
	for c in _tinted:
		c.self_modulate = _tint
	for c in _entities.get_children():
		if c is CanvasItem and (c as CanvasItem).self_modulate != _tint:
			(c as CanvasItem).self_modulate = _tint
	var d := 0.0 if indoor else DayCycle.darkness(minute_of_day)
	if absf(d - glow_strength) > 0.01 or (d == 0.0 and glow_strength != 0.0):
		glow_strength = d
		_ground_glow.strength = d
		_ground_glow.queue_redraw()
		for c in _entities.get_children():
			var g := c.get_node_or_null("WindowGlow")
			if g != null:
				(g as CanvasItem).queue_redraw()


func get_tint() -> Color:
	return _tint


func get_glow_strength() -> float:
	return glow_strength


static func release_static() -> void:
	glow_strength = 0.0
	_GroundGlow.release()


static func pool_texture() -> GradientTexture2D:
	return _GroundGlow.pool()


class _GroundGlow extends Node2D:
	var lamps: Array[Vector2] = []
	var strength := 0.0
	static var _pool: GradientTexture2D

	static func pool() -> GradientTexture2D:
		if _pool == null:
			_pool = GradientTexture2D.new()
			_pool.fill = GradientTexture2D.FILL_RADIAL
			_pool.fill_from = Vector2(0.5, 0.5)
			_pool.fill_to = Vector2(1.0, 0.5)
			var g := Gradient.new()
			g.set_color(0, Color(1.0, 0.85, 0.55, 0.6))
			g.set_color(1, Color(1.0, 0.85, 0.55, 0.0))
			_pool.gradient = g
			_pool.width = 64
			_pool.height = 64
		return _pool

	static func release() -> void:
		_pool = null

	func _draw() -> void:
		if strength <= 0.01:
			return
		for p in lamps:
			draw_texture_rect(pool(), Rect2(p + Vector2(-56, -36), Vector2(112, 60)), false, Color(1, 1, 1, strength))
			# halo around the lamp head (the lamp sprite itself is tinted; this ring shows around it)
			draw_texture_rect(pool(), Rect2(p + Vector2(-16, -70), Vector2(32, 26)), false, Color(1, 1, 1, strength))
