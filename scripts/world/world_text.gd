class_name WorldText
extends Node2D
## Readable text in the pixel world (shop signs, name tags): drawn with the project font and
## linear filtering, centred in `rect`, over an optional background, so it stays crisp under the
## 2x camera while the sprites around it stay pixelated.

var text := ""
var rect := Rect2()
var font_size := 12
var color := Color("#2a2420")
var background := Color(0, 0, 0, 0)


static func make(p_text: String, p_rect: Rect2, p_size: int, p_color: Color, p_background := Color(0, 0, 0, 0)) -> WorldText:
	var t := WorldText.new()
	t.text = p_text
	t.rect = p_rect
	t.font_size = p_size
	t.color = p_color
	t.background = p_background
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return t


static func font() -> Font:
	var theme := ThemeDB.get_project_theme()
	if theme != null and theme.default_font != null:
		return theme.default_font
	return ThemeDB.fallback_font


## Width the text needs at this size (for sizing boards and tags).
static func measure(p_text: String, p_size: int) -> float:
	return font().get_string_size(p_text, HORIZONTAL_ALIGNMENT_LEFT, -1, p_size).x


func _draw() -> void:
	if background.a > 0.0:
		draw_rect(rect, background)
	var f := font()
	var baseline := rect.position.y + (rect.size.y + f.get_ascent(font_size) - f.get_descent(font_size)) / 2.0
	draw_string(f, Vector2(rect.position.x, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, color)
