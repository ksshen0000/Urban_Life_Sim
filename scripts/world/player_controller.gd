class_name PlayerController
extends CharacterBody2D
## Player avatar (T005, 3/4 view per D-019): 4-direction movement (the most recently pressed
## direction wins, no diagonals), wall collision with a feet-sized box, and an interaction sensor
## that tracks the nearest Interactable. Origin = feet (y-sort anchor); the sprite is ~2 tiles
## tall so it overlaps facades when standing in front of them. Presentation only.

signal focus_changed(target: Interactable)
signal interact_requested(target: Interactable)

const SPEED := 140.0
const DIRECTIONS := {
	"move_up": Vector2.UP, "move_down": Vector2.DOWN, "move_left": Vector2.LEFT, "move_right": Vector2.RIGHT,
}

var facing := Vector2.DOWN
## Frozen in place during a short cutscene (an NPC walking over to talk, D-036).
var locked := false
## Hunger and exhaustion slow you down (NeedStates.walk_factor, D-037); set by CityWorld.
var speed_factor := 1.0
## The player's look (PixelPerson): a young newcomer in a blue jacket.
var look: Dictionary = PixelPerson.normalize_look({"hair": "#2b2b33", "hair_style": "spiky", "top": "#3a6fd8",
	"bottom": "#3d4656", "shoes": "#e8e4da"})
const FACING_NAMES := {Vector2.DOWN: "down", Vector2.UP: "up", Vector2.LEFT: "left", Vector2.RIGHT: "right"}
var _held: Array[String] = []
var _step := 0.0
var _focus: Interactable = null

@onready var _sensor: Area2D = $InteractionSensor
@onready var _camera: Camera2D = $Camera2D


func get_camera_zoom() -> Vector2:
	return _camera.zoom


func set_camera_limits(bounds: Rect2i) -> void:
	_camera.limit_left = bounds.position.x
	_camera.limit_top = bounds.position.y
	_camera.limit_right = bounds.end.x
	_camera.limit_bottom = bounds.end.y
	_camera.reset_smoothing()


func get_focus() -> Interactable:
	return _focus if is_instance_valid(_focus) else null


func get_move_direction() -> Vector2:
	if locked:
		return Vector2.ZERO
	return DIRECTIONS[_held[-1]] if not _held.is_empty() else Vector2.ZERO


func _physics_process(_delta: float) -> void:
	_update_held()
	var dir := get_move_direction()
	if dir != Vector2.ZERO and dir != facing:
		facing = dir
		queue_redraw()
	velocity = dir * SPEED * speed_factor
	var before := position
	move_and_slide()
	var moved := position.distance_to(before)
	if moved > 0.01:
		_step += moved
		queue_redraw()
	elif _step != 0.0:
		_step = 0.0
		queue_redraw()
	_update_focus()
	if Input.is_action_just_pressed("interact") and get_focus() != null and not locked:
		interact_requested.emit(get_focus())


func _update_held() -> void:
	for action: String in DIRECTIONS:
		var pressed := Input.is_action_pressed(action)
		if pressed and not _held.has(action):
			_held.append(action)
		elif not pressed and _held.has(action):
			_held.erase(action)


func _update_focus() -> void:
	var best: Interactable = null
	var best_d := INF
	for area in _sensor.get_overlapping_areas():
		# street ends are walked through, never "used": no [E] prompt for them
		if area is Interactable and not (area as Interactable).is_walk_through():
			var d := global_position.distance_squared_to(area.global_position)
			if d < best_d:
				best_d = d
				best = area
	if best != _focus:
		_focus = best
		focus_changed.emit(best)


func _draw() -> void:
	PixelPerson.draw(self, look, {"facing": FACING_NAMES.get(facing, "down"), "legs": PixelPerson.walk_legs(_step)})
