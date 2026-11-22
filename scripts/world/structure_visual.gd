class_name StructureVisual
extends Node2D
## A building in 3/4 view (D-019), painted as pixel art (16 art pixels per tile, shown 2x like
## every other sprite) from a map `structures` record: a tiled roof with ridge and eave, a facade
## whose texture depends on the style, framed windows (some with curtains, plants or an air
## conditioner), storefront glass and striped awnings, a door. The sign board's text is a
## smoothly filtered Label on top so it stays readable.
## Origin = bottom-left corner of the footprint, which is the y-sort anchor: the player is drawn
## in front when standing below it and behind it (under the roof) when walking along its back.
## While the player is hidden behind it, the building fades so the player stays visible.

const PALETTES := {
	"apartment": {"wall": Color("#d8b48c"), "roof": Color("#6f7782"), "trim": Color("#8a6a52"), "accent": Color("#e8e2d0")},
	"shop": {"wall": Color("#e8e4da"), "roof": Color("#4a6a8a"), "trim": Color("#7d8a96"), "accent": Color("#3fa06a")},
	"restaurant": {"wall": Color("#ecd2a8"), "roof": Color("#9a4233"), "trim": Color("#9a6b45"), "accent": Color("#e07a2e")},
	"warehouse": {"wall": Color("#a3acb2"), "roof": Color("#5f7f6a"), "trim": Color("#6c757a"), "accent": Color("#e0b84a")},
	"block": {"wall": Color("#c4a48a"), "roof": Color("#5d6470"), "trim": Color("#8a857d"), "accent": Color("#cfd6dd")},
	"arcade": {"wall": Color("#3b3550"), "roof": Color("#2e2a3e"), "trim": Color("#6a5a8a"), "accent": Color("#e04aa0"), "accent2": Color("#4ad0e0")},
	"billiards": {"wall": Color("#ddd3bd"), "roof": Color("#2f5a42"), "trim": Color("#6a5a45"), "accent": Color("#2f7a4a")},
}
## Styles with shop windows and an awning on the ground floor.
const STOREFRONT_STYLES := ["shop", "restaurant", "arcade", "billiards"]
const FADED_ALPHA := 0.45
const A := 16  # art pixels per tile
const SIGN_FONT_SIZE := 12

var data: Dictionary = {}
var _ts := 32.0
var _w := 0
var _h := 0
var _wall_rows := 1
var _overhang := 0
var _sign_rect := Rect2()
var _tex: ImageTexture


func setup(record: Dictionary, tile_size: int) -> void:
	data = record.duplicate(true)
	name = record["id"]
	_ts = tile_size
	var t: Array = record["tiles"]
	_w = t[2]
	_h = t[3]
	_wall_rows = record["wall_rows"]
	_overhang = record["roof_overhang_rows"]
	position = Vector2(t[0], t[1] + t[3]) * _ts
	_tex = PixelArt.cached("building:" + JSON.stringify(data, "", true), _paint)
	if record.has("sign_key"):
		_add_sign(tr(record["sign_key"]))
	queue_redraw()


## Pixel rect (world space) covered by the drawing, used for the fade check.
func get_visual_rect() -> Rect2:
	var height := (_h + _overhang) * _ts
	return Rect2(position.x, position.y - height, _w * _ts, height)


func update_fade(player_feet: Vector2) -> void:
	var behind := player_feet.y < position.y and get_visual_rect().grow(-2).has_point(player_feet + Vector2(0, -8))
	var target := FADED_ALPHA if behind else 1.0
	modulate.a = lerpf(modulate.a, target, 0.35) if absf(modulate.a - target) > 0.01 else target


func is_faded() -> bool:
	return modulate.a < 0.99


func _add_sign(text: String) -> void:
	var board_w := minf(_w * _ts - 12.0, WorldText.measure(text, SIGN_FONT_SIZE) + 16.0)
	_sign_rect = Rect2((_w * _ts - board_w) / 2.0, -_wall_rows * _ts - 8.0, board_w, SIGN_FONT_SIZE + 8.0)
	var label := WorldText.make(text, _sign_rect, SIGN_FONT_SIZE, Color("#2a2420"))
	label.name = "SignText"
	add_child(label)


func _draw() -> void:
	draw_rect(Rect2(0, -2, _w * _ts, 8), Color(0, 0, 0, 0.18))  # contact shadow
	var size := Vector2(_tex.get_width(), _tex.get_height()) * PixelArt.SCALE
	draw_texture_rect(_tex, Rect2(Vector2(-PixelArt.SCALE, -size.y + PixelArt.SCALE), size), false)
	if _sign_rect.size.x > 0.0:
		var pal: Dictionary = PALETTES.get(data.get("style", "block"), PALETTES["block"])
		draw_rect(_sign_rect.grow(2.0), Color("#3a2e26"))
		draw_rect(_sign_rect, Color("#f6eed8"))
		draw_rect(Rect2(_sign_rect.position, Vector2(_sign_rect.size.x, 2)), Color("#fffaea"))
		draw_rect(Rect2(_sign_rect.position + Vector2(0, _sign_rect.size.y - 2), Vector2(_sign_rect.size.x, 2)),
			(pal["accent"] as Color))


# --- pixel painting ---------------------------------------------------------------------------

static func _h01(x: int, y: int, salt: int) -> float:
	return CityMapBuilder._hash01(x, y, salt)


@warning_ignore("integer_division")
func _paint() -> PixelArt:
	var style: String = data.get("style", "block")
	var pal: Dictionary = PALETTES.get(style, PALETTES["block"])
	var W := _w * A
	var total := (_h + _overhang) * A
	var wall_h := _wall_rows * A
	var a := PixelArt.new(W + 2, total + 2)
	var o := Vector2i(1, 1)
	var fy := total - wall_h  # facade top
	var salt := str(data["id"]).hash()
	# facade
	var wall: Color = pal["wall"]
	for y in wall_h:
		for x in W:
			a.px(o.x + x, o.y + fy + y, _wall_texture(style, wall, x, y, salt))
	a.rect(o.x, o.y + total - 3, W, 3, wall.darkened(0.3))   # plinth
	a.rect(o.x, o.y + total - 3, W, 1, wall.darkened(0.15))
	var door_col := -1
	if data.has("door"):
		door_col = int(data["door"][0]) - int(data["tiles"][0])
	var storefront := style in STOREFRONT_STYLES
	for row in _wall_rows:
		var ry := fy + row * A
		var ground := row == _wall_rows - 1
		if row > 0:
			a.rect(o.x, o.y + ry, W, 2, (pal["trim"] as Color).lightened(0.1))   # floor band
			a.rect(o.x, o.y + ry + 2, W, 1, wall.darkened(0.2))
		for col in _w:
			var x := col * A
			if ground and col == door_col:
				_door(a, o + Vector2i(x, ry), pal, style)
			elif ground and storefront:
				_shop_window(a, o + Vector2i(x, ry), pal, style, col)
			elif style == "warehouse" and ground:
				_shutter(a, o + Vector2i(x, ry), pal)
			else:
				_window(a, o + Vector2i(x, ry), pal, style, _h01(col, row, salt))
	if storefront and style != "arcade":
		_awning(a, o + Vector2i(0, total - A - 3), W, pal)
	elif style == "arcade":
		a.rect(o.x, o.y + total - A - 2, W, 3, Color("#1c1a26"))
		a.rect(o.x + 2, o.y + total - A - 1, W - 4, 1, pal["accent"])
		a.rect(o.x, o.y + fy, W, 2, Color("#1c1a26"))
		a.rect(o.x + 2, o.y + fy, W - 4, 1, pal["accent2"])
	# roof
	_roof(a, o, W, fy, pal, style)
	a.outline(0.55)
	return a


func _wall_texture(style: String, wall: Color, x: int, y: int, salt: int) -> Color:
	match style:
		"block":  # brick
			var off := 4 if (y / 4) % 2 == 1 else 0
			if y % 4 == 0 or (x + off) % 8 == 0:
				return wall.darkened(0.18)
			return wall.darkened(0.06) if _h01(x / 8, y / 4, salt) > 0.7 else wall
		"warehouse":  # corrugated metal
			return wall.darkened(0.12) if x % 3 == 0 else (wall.lightened(0.06) if x % 3 == 1 else wall)
		"shop":  # ceramic tiles
			return wall.darkened(0.08) if x % 8 == 0 or y % 8 == 0 else wall
		"arcade":
			return wall.lightened(0.05) if (x + y) % 6 == 0 else wall
		_:  # plaster with faint lines
			if y % 8 == 7:
				return wall.darkened(0.05)
			return wall.darkened(0.04) if _h01(x, y, salt) > 0.93 else wall


func _window(a: PixelArt, at: Vector2i, pal: Dictionary, style: String, roll: float) -> void:
	var frame: Color = (pal["trim"] as Color)
	var r := Rect2i(at + Vector2i(3, 4), Vector2i(10, 9))
	a.rect(r.position.x - 1, r.position.y - 1, r.size.x + 2, r.size.y + 2, frame)
	var glass := Color("#8fbcd6") if style != "arcade" else Color("#2a2440")
	for yy in r.size.y:
		a.rect(r.position.x, r.position.y + yy, r.size.x, 1, glass.lightened(0.18 - yy * 0.03))
	# shine
	a.px(r.position.x + 1, r.position.y + 1, Color(1, 1, 1, 0.9))
	a.px(r.position.x + 2, r.position.y + 1, Color(1, 1, 1, 0.6))
	a.px(r.position.x + 1, r.position.y + 2, Color(1, 1, 1, 0.6))
	if roll < 0.3:  # warm curtains
		a.rect(r.position.x, r.position.y, 3, r.size.y, Color("#e8a85a"))
		a.rect(r.end.x - 3, r.position.y, 3, r.size.y, Color("#e8a85a"))
	elif roll < 0.45:
		a.rect(r.position.x, r.position.y, r.size.x, 4, Color("#e8d6b8"))
	a.rect(r.position.x + 4, r.position.y, 1, r.size.y, frame)   # mullion
	a.rect(r.position.x - 2, r.end.y + 1, r.size.x + 4, 1, frame.lightened(0.25))  # sill
	if (style == "apartment" or style == "block") and roll > 0.72:
		# air conditioner hanging below the window
		a.rect(r.end.x - 5, r.end.y + 2, 6, 3, Color("#d8dbe0"))
		a.rect(r.end.x - 4, r.end.y + 3, 4, 1, Color("#8a9096"))
	elif roll > 0.55 and roll < 0.62:
		a.rect(r.position.x, r.end.y - 1, 3, 2, Color("#4f9a45"))  # potted plant
		a.px(r.position.x + 1, r.end.y - 2, Color("#e0507a"))


func _shop_window(a: PixelArt, at: Vector2i, pal: Dictionary, style: String, col: int) -> void:
	var frame: Color = (pal["trim"] as Color).darkened(0.1)
	var r := Rect2i(at + Vector2i(1, 4), Vector2i(14, 9))
	a.rect(r.position.x - 1, r.position.y - 1, r.size.x + 2, r.size.y + 2, frame)
	match style:
		"arcade":
			a.rect(r.position.x, r.position.y, r.size.x, r.size.y, Color("#1e1a30"))
			var c1: Color = pal["accent2"] if col % 2 == 0 else pal["accent"]
			a.rect(r.position.x + 2, r.position.y + 2, 5, 4, c1)
			a.rect(r.position.x + 8, r.position.y + 3, 4, 3, (pal["accent"] as Color) if col % 2 == 0 else (pal["accent2"] as Color))
			a.rect(r.position.x + 2, r.position.y + 7, 10, 1, Color("#3a3458"))
		"billiards":
			a.rect(r.position.x, r.position.y, r.size.x, r.size.y, Color("#a9c2c9"))
			a.rect(r.position.x + 1, r.position.y + 5, r.size.x - 2, 3, pal["accent"])
			a.rect(r.position.x + 1, r.position.y + 5, r.size.x - 2, 1, Color("#6b4a2f"))
			a.px(r.position.x + 4, r.position.y + 6, Color.WHITE)
			a.px(r.position.x + 9, r.position.y + 6, Color("#d84a4a"))
		_:
			a.rect(r.position.x, r.position.y, r.size.x, r.size.y, Color("#a8d0e2"))
			a.rect(r.position.x, r.position.y + r.size.y - 3, r.size.x, 3, (pal["accent"] as Color).darkened(0.1))
			# goods on the shelf
			for i in 4:
				a.rect(r.position.x + 1 + i * 3, r.position.y + r.size.y - 5, 2, 2,
					[Color("#e07a2e"), Color("#f2c94c"), Color("#d84a4a"), Color("#3a6fd8")][(i + col) % 4])
	a.px(r.position.x + 1, r.position.y + 1, Color(1, 1, 1, 0.85))
	a.px(r.position.x + 2, r.position.y + 1, Color(1, 1, 1, 0.5))


func _door(a: PixelArt, at: Vector2i, pal: Dictionary, style: String) -> void:
	var frame: Color = pal["trim"]
	var r := Rect2i(at + Vector2i(3, 2), Vector2i(10, 14))
	a.rect(r.position.x - 1, r.position.y - 1, r.size.x + 2, r.size.y + 1, frame.darkened(0.15))
	var wood := Color("#6a4630") if style != "arcade" else Color("#2a2440")
	a.rect(r.position.x, r.position.y, r.size.x, r.size.y, wood)
	a.rect(r.position.x + 1, r.position.y + 1, r.size.x - 2, 5, Color("#9cc6da") if style != "arcade" else (pal["accent2"] as Color))
	a.rect(r.position.x + 4, r.position.y + 1, 1, 5, wood)
	a.rect(r.position.x + 1, r.position.y + 8, r.size.x - 2, 1, wood.darkened(0.2))
	a.px(r.end.x - 2, r.position.y + 9, Color("#e8d27a"))
	a.rect(r.position.x - 2, r.end.y - 1, r.size.x + 4, 1, Color("#a9a59a"))   # step


func _shutter(a: PixelArt, at: Vector2i, pal: Dictionary) -> void:
	var r := Rect2i(at + Vector2i(1, 3), Vector2i(14, 13))
	a.rect(r.position.x, r.position.y, r.size.x, r.size.y, Color("#8a9298"))
	for yy in range(0, r.size.y, 2):
		a.rect(r.position.x, r.position.y + yy, r.size.x, 1, Color("#747c82"))
	a.rect(r.position.x, r.position.y, r.size.x, 1, pal["accent"])


func _awning(a: PixelArt, at: Vector2i, width: int, pal: Dictionary) -> void:
	var accent: Color = pal["accent"]
	for x in width:
		var stripe := accent if (x / 4) % 2 == 0 else Color("#f6f2e8")
		a.rect(at.x + x, at.y, 1, 4, stripe)
		a.px(at.x + x, at.y, stripe.lightened(0.15))
		if x % 4 != 3:   # scalloped edge
			a.px(at.x + x, at.y + 4, stripe.darkened(0.12))
	a.rect(at.x, at.y + 5, width, 1, Color(0, 0, 0, 0.25))


@warning_ignore("integer_division")
func _roof(a: PixelArt, o: Vector2i, W: int, fy: int, pal: Dictionary, style: String) -> void:
	var roof: Color = pal["roof"]
	var top := 3
	# eave: dark underside plus a row of tile ends
	for y in range(top, fy):
		for x in W:
			var c := roof
			match style:
				"warehouse":
					c = roof.darkened(0.15) if x % 4 == 0 else (roof.lightened(0.06) if x % 4 == 1 else roof)
				"arcade":
					c = roof.lightened(0.04) if (x / 8 + y / 8) % 2 == 0 else roof
				_:
					# clay/grey tile courses: rows every 4 px, alternating ridges every 4 px
					var course := (y - top) / 4
					var xi := (x + (2 if course % 2 == 1 else 0)) % 4
					if (y - top) % 4 == 3:
						c = roof.darkened(0.22)
					elif xi == 0:
						c = roof.darkened(0.12)
					elif xi == 1:
						c = roof.lightened(0.1)
			a.px(o.x + x, o.y + y, c)
	# ridge along the top with slightly upturned ends (old-town tiled roofs)
	var ridge := roof.darkened(0.3) if style != "warehouse" else roof.darkened(0.2)
	a.rect(o.x + 2, o.y + top - 2, W - 4, 3, ridge)
	a.rect(o.x + 2, o.y + top - 2, W - 4, 1, ridge.lightened(0.25))
	if style in ["apartment", "block", "restaurant", "billiards"]:
		a.rect(o.x, o.y + top - 3, 3, 2, ridge)
		a.rect(o.x + W - 3, o.y + top - 3, 3, 2, ridge)
	# eave
	a.rect(o.x, o.y + fy - 3, W, 2, roof.darkened(0.35))
	for x in range(0, W, 3):
		a.px(o.x + x, o.y + fy - 2, roof.lightened(0.15))
	a.rect(o.x, o.y + fy - 1, W, 1, Color(0, 0, 0, 0.35))
	if style == "arcade":
		# rooftop units
		for i in range(0, W - 10, 18):
			a.rect(o.x + 6 + i, o.y + top + 4, 8, 5, Color("#8a9096"))
			a.rect(o.x + 7 + i, o.y + top + 5, 6, 1, Color("#5a6066"))
