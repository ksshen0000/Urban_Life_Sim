class_name PixelArt
extends RefCounted
## A tiny procedural pixel-art canvas (no art files, spec §6 / D-003). Sprites are painted at low
## resolution with flat colours, then `shade()` adds light from the top-left and `outline()` wraps
## every shape in a one-pixel outline made from a darker shade of the colour it borders: the
## handheld-RPG / farming-sim look. Shown at 2 world pixels per art pixel with nearest filtering.

const SCALE := 2  # world pixels per art pixel (the camera zooms the world 2x again)

static var _cache: Dictionary = {}

var img: Image
var width: int
var height: int


func _init(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	img = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)


func px(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < width and y < height:
		img.set_pixel(x, y, c)


func rect(x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			px(xx, yy, c)


## Filled ellipse inside the box (x, y, w, h).
func ellipse(x: int, y: int, w: int, h: int, c: Color) -> void:
	var rx := w / 2.0
	var ry := h / 2.0
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			var dx := (xx + 0.5 - x - rx) / rx
			var dy := (yy + 0.5 - y - ry) / ry
			if dx * dx + dy * dy <= 1.0:
				px(xx, yy, c)


func get_px(x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= width or y >= height:
		return Color(0, 0, 0, 0)
	return img.get_pixel(x, y)


func is_solid(x: int, y: int) -> bool:
	return get_px(x, y).a > 0.5


## Light from the top-left: pixels on a top/left edge get lighter, bottom/right edges darker.
func shade(light: float = 0.12, dark: float = 0.2) -> void:
	var src := img.duplicate() as Image
	for y in height:
		for x in width:
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var lit := not _solid_in(src, x, y - 1) or not _solid_in(src, x - 1, y)
			var dim := not _solid_in(src, x, y + 1) or not _solid_in(src, x + 1, y)
			if dim:
				img.set_pixel(x, y, c.darkened(dark))
			elif lit:
				img.set_pixel(x, y, c.lightened(light))


## One-pixel outline around every shape, coloured as a dark version of the darkest neighbour.
func outline(amount: float = 0.6) -> void:
	var src := img.duplicate() as Image
	for y in height:
		for x in width:
			if src.get_pixel(x, y).a > 0.5:
				continue
			var darkest := Color(0, 0, 0, 0)
			var best := 99.0
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _solid_in(src, x + d.x, y + d.y):
					var c := src.get_pixel(x + d.x, y + d.y)
					var lum := c.get_luminance()
					if lum < best:
						best = lum
						darkest = c
			if best < 99.0:
				var o := darkest.darkened(amount)
				o.a = 1.0
				img.set_pixel(x, y, o)


func flip_h() -> void:
	img.flip_x()


func texture() -> ImageTexture:
	return ImageTexture.create_from_image(img)


static func _solid_in(image: Image, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return false
	return image.get_pixel(x, y).a > 0.5


## Memoized texture: `build` paints a PixelArt and returns it; called once per key.
static func cached(key: String, build: Callable) -> ImageTexture:
	if not _cache.has(key):
		var art: PixelArt = build.call()
		_cache[key] = art.texture()
	return _cache[key]


## Draws `tex` with its bottom-centre at `foot` (world pixels), scaled to SCALE.
static func draw_at(canvas: CanvasItem, tex: Texture2D, foot: Vector2 = Vector2.ZERO, bottom_margin: int = 1) -> void:
	var size := Vector2(tex.get_width(), tex.get_height()) * SCALE
	canvas.draw_texture_rect(tex, Rect2(foot + Vector2(-size.x / 2.0, -size.y + bottom_margin * SCALE), size), false)


static func shadow(canvas: CanvasItem, center: Vector2, rx: float, ry: float, alpha: float = 0.22) -> void:
	canvas.draw_set_transform(center, 0.0, Vector2(1.0, ry / rx))
	canvas.draw_circle(Vector2.ZERO, rx, Color(0, 0, 0, alpha))
	canvas.draw_set_transform(Vector2.ZERO)
