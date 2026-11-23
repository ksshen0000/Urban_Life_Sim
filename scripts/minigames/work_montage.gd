class_name WorkMontage
extends Control
## The "skip" path of a shift or pastime (D-038): instead of jumping straight to "done", a short
## full-screen scene of the player at the station while the clock runs from start to end, with
## a progress bar and changing captions. Click or any key hurries it along. Emits `finished`.

signal finished

const DURATION := 4.0

var look: Dictionary = {}
var station := "cashier_counter"
var title_text := ""
var captions: PackedStringArray = []
var from_minute := 0
var to_minute := 0
var _t := 0.0
var _done := false


func _ready() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	queue_redraw()
	if _t >= DURATION:
		_done = true
		finished.emit()


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed):
		_t = maxf(_t, DURATION - 0.3)


func hurry() -> void:
	_t = DURATION


func progress() -> float:
	return clampf(_t / DURATION, 0.0, 1.0)


func _draw() -> void:
	var r := get_rect()
	draw_rect(Rect2(Vector2.ZERO, r.size), Color("#14131a"))
	var cx := r.size.x / 2.0
	# a warm pool of light, the station and the player working at it (scaled pixel art)
	draw_circle(Vector2(cx, r.size.y * 0.52), 300.0, Color(1.0, 0.9, 0.6, 0.06))
	var f := WorldText.font()
	draw_string(f, Vector2(0, 110), title_text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 44, Color("#f2d27a"))
	# sprites drawn scaled by hand (the shared draw helpers reset the canvas transform)
	var k := int(_t / 0.35) % 2
	var person := PixelPerson.texture(PixelPerson.normalize_look(look), {"facing": "down",
		"arm_l": "forward" if k == 0 else "up", "arm_r": "up" if k == 0 else "forward"})
	var foot := Vector2(cx, r.size.y * 0.6)
	_sprite(person, foot + Vector2(0, -78), 6.0)  # behind the station, facing us
	_sprite(PixelProps.texture(station), foot, 6.0)
	# clock and progress
	var m := from_minute + int((to_minute - from_minute) * progress())
	var mod := GameClock.minute_of_day_of(m)
	@warning_ignore("integer_division")
	var clock := "%02d:%02d" % [mod / 60, mod % 60]
	draw_string(f, Vector2(0, r.size.y * 0.74), clock, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 56, Color("#fbf3dc"))
	var bar := Rect2(cx - 300, r.size.y * 0.78, 600, 16)
	draw_rect(bar, Color(1, 1, 1, 0.12))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress(), bar.size.y)), Color("#f2d27a"))
	if not captions.is_empty():
		var c := captions[int(_t / (DURATION / captions.size())) % captions.size()]
		draw_string(f, Vector2(0, r.size.y * 0.86), c, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 28, Color("#c9c2b0"))


## Draws `tex` with its bottom-centre at `foot`, `scale` screen px per art px.
func _sprite(tex: Texture2D, foot: Vector2, scale: float) -> void:
	var sz := Vector2(tex.get_width(), tex.get_height()) * scale
	draw_texture_rect(tex, Rect2(foot - Vector2(sz.x / 2.0, sz.y), sz), false)
