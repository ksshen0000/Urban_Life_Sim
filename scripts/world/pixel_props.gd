class_name PixelProps
extends RefCounted
## Pixel-art scenery and furniture (trees, flower beds, lamps, benches, signs, stone chess
## tables, loudspeakers, the park pavilion), painted procedurally like PixelPerson and cached.
## Every texture's bottom-centre is the object's ground contact point (its y-sort anchor).

static func texture(kind: String, variant: int = 0) -> ImageTexture:
	return PixelArt.cached("prop:%s:%d" % [kind, variant], func() -> PixelArt: return _paint(kind, variant))


static func draw(canvas: CanvasItem, kind: String, variant: int = 0, foot: Vector2 = Vector2.ZERO) -> void:
	match kind:
		"tree":
			PixelArt.shadow(canvas, foot + Vector2(0, -2), 18.0, 6.0)
		"pavilion":
			PixelArt.shadow(canvas, foot + Vector2(0, 2), 52.0, 10.0, 0.18)
		"bench", "board", "chess_table", "flowers":
			PixelArt.shadow(canvas, foot + Vector2(0, -2), 14.0, 4.0)
		_:
			PixelArt.shadow(canvas, foot + Vector2(0, -1), 6.0, 2.5)
	PixelArt.draw_at(canvas, texture(kind, variant), foot)


@warning_ignore("integer_division")
static func _paint(kind: String, v: int) -> PixelArt:
	var a: PixelArt
	match kind:
		"tree":
			a = PixelArt.new(30, 38)
			var trunk := Color("#7a5232")
			a.rect(13, 25, 4, 12, trunk)
			a.rect(16, 25, 1, 12, trunk.darkened(0.25))
			a.rect(12, 35, 6, 2, trunk)
			var leaf := Color("#4f9a45") if v % 2 == 0 else Color("#5aa04a")
			var blobs := [[3, 12, 12, 12], [15, 11, 12, 13], [7, 3, 16, 14], [9, 15, 13, 11]]
			if v % 2 == 1:
				blobs = [[4, 10, 11, 13], [15, 9, 11, 14], [8, 1, 14, 15], [6, 15, 18, 10]]
			for b: Array in blobs:
				a.ellipse(b[0], b[1], b[2], b[3], leaf)
			for b: Array in blobs:  # darker underside of each clump
				a.ellipse(b[0] + 2, b[1] + b[3] / 2, b[2] - 3, b[3] / 2, leaf.darkened(0.18))
			for b: Array in blobs:  # lit top-left of each clump
				a.ellipse(b[0] + 2, b[1] + 1, b[2] / 2, b[3] / 3, leaf.lightened(0.2))
			if v == 2:  # a few blossoms
				for p: Array in [[10, 8], [19, 12], [13, 17], [7, 15], [22, 18]]:
					a.px(p[0], p[1], Color("#f2a7b8"))
			a.shade(0.06, 0.12)
		"flowers":
			a = PixelArt.new(18, 9)
			a.ellipse(1, 3, 16, 6, Color("#6b4a2f"))
			a.ellipse(2, 2, 14, 5, Color("#4f8a3e"))
			var cols := [Color("#e0507a"), Color("#f2c94c"), Color("#f4f1e8"), Color("#9a6ad8")]
			for i in 9:
				var x := 3 + (i * 5) % 12
				var y := 2 + (i * 3) % 4
				a.px(x, y, cols[(i + v) % cols.size()])
				a.px(x + 1, y, cols[(i + v) % cols.size()].darkened(0.15))
		"lamp":
			a = PixelArt.new(9, 30)
			var pole := Color("#3a4048")
			a.rect(3, 6, 2, 22, pole)
			a.rect(2, 27, 4, 2, pole)
			a.rect(1, 2, 7, 2, pole)
			a.rect(2, 4, 5, 3, Color("#f6e7a8"))
			a.px(4, 0, pole)
			a.rect(3, 1, 3, 1, pole)
			a.shade()
		"bench":
			a = PixelArt.new(18, 12)
			var wood := Color("#a87448")
			a.rect(1, 1, 16, 3, wood)
			a.rect(1, 5, 16, 3, wood)
			a.rect(1, 4, 16, 1, wood.darkened(0.3))
			a.rect(2, 8, 2, 3, Color("#4a4a4a"))
			a.rect(14, 8, 2, 3, Color("#4a4a4a"))
			a.shade()
		"board":
			a = PixelArt.new(18, 20)
			var post := Color("#6b4a2f")
			a.rect(2, 10, 2, 9, post)
			a.rect(14, 10, 2, 9, post)
			a.rect(1, 1, 16, 11, Color("#9a7450"))
			a.rect(2, 2, 14, 9, Color("#c9a77a"))
			a.rect(3, 3, 5, 4, Color("#f4f1e8"))
			a.rect(9, 3, 6, 3, Color("#f2e2b0"))
			a.rect(9, 7, 4, 3, Color("#e9edf2"))
			a.rect(4, 8, 3, 2, Color("#f4c0c0"))
			a.px(5, 3, Color("#d84a4a"))
			a.px(11, 3, Color("#3a6fd8"))
			a.shade()
		"bus_sign":
			a = PixelArt.new(12, 30)
			a.rect(5, 8, 2, 21, Color("#5a5f66"))
			a.ellipse(1, 0, 10, 10, Color("#2f7fd0"))
			a.ellipse(3, 2, 6, 6, Color("#f4f1e8"))
			a.rect(4, 4, 4, 2, Color("#2f7fd0"))
			a.rect(2, 12, 8, 7, Color("#f4f1e8"))
			for r in [13, 15, 17]:
				a.rect(3, r, 6, 1, Color("#8a8f99"))
			a.shade()
		"signpost":
			a = PixelArt.new(14, 20)
			a.rect(6, 6, 2, 13, Color("#5a5f66"))
			a.rect(1, 1, 12, 6, Color("#e8d27a"))
			a.shade()
		"chess_table":
			a = PixelArt.new(18, 14)
			a.rect(7, 6, 4, 7, Color("#8a8a86"))
			a.rect(5, 12, 8, 1, Color("#7a7a76"))
			a.ellipse(0, 0, 18, 8, Color("#a9a9a4"))
			a.ellipse(2, 1, 14, 6, Color("#e0c48a"))
			for r in [2, 4, 6]:
				a.rect(4, r, 10, 1, Color("#b89a5e"))
			for p: Array in [[5, 3], [10, 2], [12, 5]]:
				a.px(p[0], p[1], Color("#c0392b"))
			for p: Array in [[7, 5], [13, 3]]:
				a.px(p[0], p[1], Color("#222222"))
			a.shade(0.08, 0.1)
		"speaker":
			a = PixelArt.new(10, 16)
			a.rect(1, 0, 8, 9, Color("#2a2a2e"))
			a.ellipse(2, 2, 6, 6, Color("#555560"))
			a.rect(4, 4, 2, 2, Color("#1a1a1e"))
			a.px(2, 1, Color("#e04a4a"))
			a.rect(4, 9, 2, 3, Color("#4a4a4a"))
			a.rect(2, 12, 1, 3, Color("#4a4a4a"))
			a.rect(7, 12, 1, 3, Color("#4a4a4a"))
			a.rect(3, 11, 4, 1, Color("#4a4a4a"))
			a.shade()
		"pavilion":
			a = PixelArt.new(66, 46)
			var red := Color("#b03a2e")
			for x in [6, 22, 42, 58]:
				a.rect(x - 1, 18, 3, 26, red)
				a.px(x + 1, 30, red.darkened(0.3))
			a.rect(4, 43, 58, 2, Color("#9a958c"))
			a.rect(8, 18, 50, 2, Color("#7a2a22"))   # beam
			var tile := Color("#2f6a4f")
			# upturned roof: wide eave, narrowing to the ridge
			a.rect(1, 15, 64, 3, tile)
			a.px(0, 14, tile)
			a.px(65, 14, tile)
			a.rect(5, 11, 56, 4, tile)
			a.rect(10, 7, 46, 4, tile)
			a.rect(16, 4, 34, 3, tile)
			for y in [8, 12, 15]:
				for x in range(6, 60, 4):
					a.px(x, y, tile.darkened(0.25))
			a.rect(1, 17, 64, 1, Color("#e0c06a"))
			a.rect(28, 0, 10, 4, Color("#e0c06a"))
			a.rect(31, 1, 4, 2, Color("#f2d88a"))
			a.shade(0.1, 0.15)
		_:
			a = PixelArt.new(4, 4)
			a.rect(0, 0, 4, 4, Color.MAGENTA)
	a.outline()
	return a
