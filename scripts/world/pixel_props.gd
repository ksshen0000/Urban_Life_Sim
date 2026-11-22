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
		"door_mat", "menu_board", "poster", "clock", "window_in", "wall_shelf", "price_banner", "chair_left", "chair_right":
			pass
		"shelf", "cashier_counter", "order_counter", "kitchen":
			PixelArt.shadow(canvas, foot + Vector2(0, -1), 46.0, 5.0, 0.18)
		"crane":
			PixelArt.shadow(canvas, foot + Vector2(0, -2), 26.0, 6.0, 0.18)
		"fountain":
			PixelArt.shadow(canvas, foot + Vector2(0, -2), 40.0, 8.0, 0.15)
		"bench", "board", "chess_table", "flowers", "table", "bricks", "laundry", "fridge", "drink_machine", "plant", "snack_rack", "trash_bin":
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
		"crane":
			# tower crane: lattice mast, jib, counterweight, hanging hook
			a = PixelArt.new(80, 140)
			var y := Color("#e0b030")
			for yy in range(14, 136):
				a.px(36, yy, y.darkened(0.2))
				a.px(43, yy, y.darkened(0.2))
				if yy % 6 == 0:
					for xx in range(36, 44):
						a.px(xx, yy, y)
				if yy % 6 < 3:
					a.px(37 + (yy % 6) * 2, yy, y)
			a.rect(4, 10, 76, 4, y)
			for xx in range(4, 78, 5):
				a.px(xx, 9, y.darkened(0.2))
			a.rect(4, 14, 12, 7, Color("#6c757a"))   # counterweight
			a.rect(34, 2, 12, 8, Color("#3a6fd8"))   # cab
			a.rect(36, 4, 5, 3, Color("#9cc6da"))
			a.rect(66, 14, 1, 40, Color("#3a3f46"))   # cable
			a.rect(64, 54, 5, 3, Color("#3a3f46"))
			a.rect(30, 134, 20, 6, Color("#8a8f99"))
		"bricks":
			a = PixelArt.new(22, 14)
			for r in 3:
				for i in 4 - r:
					a.rect(1 + i * 5 + r * 2, 10 - r * 4, 5, 4, Color("#b0563a") if (i + r) % 2 == 0 else Color("#9a4a32"))
			a.shade()
		"laundry":
			# drying rack with clothes (every old compound has one)
			a = PixelArt.new(36, 30)
			a.rect(2, 6, 2, 23, Color("#8a8f99"))
			a.rect(32, 6, 2, 23, Color("#8a8f99"))
			a.rect(2, 6, 32, 1, Color("#5a5f66"))
			a.rect(6, 7, 7, 9, Color("#3a6fd8"))
			a.rect(15, 7, 6, 12, Color("#f4f1e8"))
			a.rect(23, 7, 8, 7, Color("#e07aa0"))
			a.rect(24, 14, 2, 4, Color("#e07aa0"))
			a.rect(29, 14, 2, 4, Color("#e07aa0"))
			a.shade()
		"barber_pole":
			a = PixelArt.new(8, 30)
			a.rect(1, 0, 6, 3, Color("#d8dbe0"))
			for yy in range(3, 24):
				for xx in range(1, 7):
					var band := (xx + yy) % 6
					a.px(xx, yy, Color("#d84a4a") if band < 2 else (Color("#2f6fb0") if band < 4 else Color("#f4f1e8")))
			a.rect(1, 24, 6, 2, Color("#d8dbe0"))
			a.rect(3, 26, 2, 4, Color("#5a5f66"))
			a.shade(0.15, 0.15)
		"fountain":
			a = PixelArt.new(64, 36)
			a.ellipse(0, 14, 64, 22, Color("#b9b5aa"))
			a.ellipse(4, 16, 56, 17, Color("#5a9ac8"))
			a.ellipse(10, 19, 12, 3, Color("#a8d4ee"))
			a.rect(29, 6, 6, 16, Color("#cfcbc0"))
			a.ellipse(22, 2, 20, 8, Color("#cfcbc0"))
			a.rect(31, 0, 2, 4, Color("#a8d4ee"))
			for p: Array in [[26, 10], [37, 10], [24, 14], [40, 14]]:
				a.px(p[0], p[1], Color("#a8d4ee"))
			a.shade(0.08, 0.12)
		"fridge":
			a = PixelArt.new(16, 30)
			a.rect(0, 0, 16, 30, Color("#d8dbe0"))
			a.rect(1, 2, 14, 24, Color("#9cc6da"))
			for r in [6, 11, 16, 21]:
				a.rect(1, r, 14, 1, Color("#7d8a96"))
				for i in 6:
					a.rect(2 + i * 2, r - 3, 1, 3, [Color("#d84a4a"), Color("#3fa06a"), Color("#f2c94c"), Color("#3a6fd8")][(i + r) % 4])
			a.rect(1, 2, 1, 24, Color(1, 1, 1, 0.6))
			a.rect(13, 12, 1, 4, Color("#7d8a96"))
			a.rect(0, 27, 16, 3, Color("#7d8a96"))
			a.rect(2, 0, 12, 2, Color("#3fa06a"))
			a.shade(0.06, 0.12)
		"shelf":
			a = PixelArt.new(48, 26)
			a.rect(0, 0, 48, 26, Color("#c9ccd2"))
			for r in [2, 9, 16]:
				a.rect(1, r + 6, 46, 1, Color("#8a8f99"))
				var x := 2
				while x < 46:
					var w: int = 2 + (x * 7 + r) % 3
					a.rect(x, r + 1 + (x % 2), w, 5 - (x % 2), [Color("#e07a2e"), Color("#f2c94c"), Color("#d84a4a"),
						Color("#3a6fd8"), Color("#3fa06a"), Color("#f4f1e8")][(x + r) % 6])
					x += w + 1
			a.rect(0, 23, 48, 3, Color("#8a8f99"))
			a.shade(0.05, 0.1)
		"snack_rack":
			a = PixelArt.new(16, 22)
			a.rect(1, 0, 14, 20, Color("#b0473c"))
			for r in [2, 8, 14]:
				for i in 4:
					a.rect(2 + i * 3, r, 2, 4, [Color("#f2c94c"), Color("#e07a2e"), Color("#3fa06a"), Color("#f4f1e8")][(i + r) % 4])
			a.rect(2, 20, 2, 2, Color("#4a4a4a"))
			a.rect(12, 20, 2, 2, Color("#4a4a4a"))
			a.shade()
		"cashier_counter":
			a = PixelArt.new(48, 22)
			a.rect(0, 6, 48, 16, Color("#3fa06a"))
			a.rect(0, 4, 48, 3, Color("#e8e4da"))
			a.rect(2, 10, 44, 1, Color("#2f7a4a"))
			# register, card reader, a candy box
			a.rect(26, 0, 12, 5, Color("#4a4f58"))
			a.rect(27, 1, 6, 2, Color("#4ad0a0"))
			a.rect(40, 2, 3, 3, Color("#2a2a2e"))
			a.rect(6, 1, 8, 4, Color("#f2c94c"))
			a.rect(7, 2, 2, 2, Color("#d84a4a"))
			a.shade(0.06, 0.12)
		"order_counter":
			a = PixelArt.new(48, 22)
			a.rect(0, 6, 48, 16, Color("#e07a2e"))
			a.rect(0, 4, 48, 3, Color("#d8dbe0"))
			for x in range(4, 46, 8):
				a.rect(x, 9, 4, 10, Color("#c96a22"))
			a.rect(20, 0, 9, 5, Color("#4a4f58"))
			a.rect(21, 1, 5, 2, Color("#4ad0e0"))
			a.rect(34, 1, 8, 4, Color("#f4f1e8"))   # tray
			a.rect(35, 1, 3, 2, Color("#d84a4a"))
			a.shade(0.06, 0.12)
		"kitchen":
			a = PixelArt.new(48, 26)
			a.rect(0, 8, 48, 18, Color("#b9c0c8"))
			a.rect(0, 6, 48, 3, Color("#dfe4ea"))
			a.rect(3, 11, 18, 12, Color("#8a9298"))   # oven
			a.rect(5, 13, 14, 6, Color("#2a2a2e"))
			a.rect(27, 0, 18, 7, Color("#4a4f58"))    # fryer
			a.rect(28, 1, 7, 4, Color("#e0b84a"))
			a.rect(37, 1, 7, 4, Color("#e0b84a"))
			a.rect(6, 3, 6, 3, Color("#3a3f46"))      # pot
			a.px(8, 2, Color(1, 1, 1, 0.6))
			a.shade(0.06, 0.12)
		"table":
			a = PixelArt.new(18, 16)
			a.rect(7, 6, 4, 9, Color("#6b4a2f"))
			a.rect(4, 14, 10, 2, Color("#5a3d2b"))
			a.ellipse(0, 0, 18, 9, Color("#c98f5a"))
			a.rect(5, 2, 5, 3, Color("#f4f1e8"))      # a plate
			a.rect(6, 2, 2, 1, Color("#e07a2e"))
			a.shade(0.08, 0.12)
		"chair_left", "chair_right":
			a = PixelArt.new(12, 16)
			var wood := Color("#a87448")
			var back := 1 if kind == "chair_left" else 9
			a.rect(back, 0, 2, 12, wood)
			a.rect(1, 8, 10, 3, wood)
			a.rect(1, 11, 2, 5, wood.darkened(0.2))
			a.rect(9, 11, 2, 5, wood.darkened(0.2))
			a.shade()
		"plant":
			a = PixelArt.new(14, 24)
			a.rect(3, 16, 8, 8, Color("#b06a3a"))
			a.rect(2, 15, 10, 2, Color("#c98050"))
			a.ellipse(0, 2, 14, 15, Color("#4f9a45"))
			a.ellipse(3, 0, 7, 8, Color("#5aaa4a"))
			a.shade(0.1, 0.15)
		"drink_machine":
			a = PixelArt.new(16, 30)
			a.rect(0, 0, 16, 30, Color("#d84a4a"))
			a.rect(2, 3, 9, 16, Color("#9cc6da"))
			for r in [5, 9, 13]:
				for i in 3:
					a.rect(3 + i * 3, r, 2, 3, [Color("#f2c94c"), Color("#3fa06a"), Color("#f4f1e8")][i])
			a.rect(12, 4, 3, 8, Color("#f4f1e8"))
			a.rect(3, 22, 8, 3, Color("#2a2a2e"))
			a.shade(0.08, 0.14)
		"trash_bin":
			a = PixelArt.new(10, 14)
			a.rect(1, 2, 8, 12, Color("#5a7a6a"))
			a.rect(0, 0, 10, 3, Color("#7a9a8a"))
			a.rect(3, 6, 4, 1, Color("#3a5a4a"))
			a.shade()
		"door_mat":
			a = PixelArt.new(16, 8)
			a.rect(0, 0, 16, 8, Color("#5a4a6a"))
			for x in range(1, 15, 2):
				a.rect(x, 1, 1, 6, Color("#6a5a7a"))
		"menu_board":
			a = PixelArt.new(46, 26)
			a.rect(0, 0, 46, 26, Color("#2a2420"))
			a.rect(2, 2, 42, 22, Color("#3a322c"))
			for i in 3:
				a.rect(4 + i * 14, 4, 11, 8, [Color("#e07a2e"), Color("#f2c94c"), Color("#d84a4a")][i])
				a.rect(5 + i * 14, 14, 9, 1, Color("#f4f1e8"))
				a.rect(5 + i * 14, 17, 6, 1, Color("#f4f1e8"))
				a.rect(10 + i * 14, 20, 3, 2, Color("#f2c94c"))
		"poster":
			a = PixelArt.new(14, 18)
			a.rect(0, 0, 14, 18, Color("#f4f1e8"))
			a.rect(1, 1, 12, 10, Color("#e07aa0"))
			a.ellipse(3, 3, 8, 7, Color("#f2c94c"))
			a.rect(2, 13, 10, 1, Color("#3a3f46"))
			a.rect(2, 15, 7, 1, Color("#3a3f46"))
		"clock":
			a = PixelArt.new(12, 12)
			a.ellipse(0, 0, 12, 12, Color("#3a3f46"))
			a.ellipse(1, 1, 10, 10, Color("#f4f1e8"))
			a.rect(5, 2, 1, 4, Color("#2a2420"))
			a.rect(6, 5, 3, 1, Color("#2a2420"))
		"window_in":
			a = PixelArt.new(26, 18)
			a.rect(0, 0, 26, 18, Color("#8a6a52"))
			a.rect(2, 2, 22, 14, Color("#9cc6da"))
			a.rect(12, 2, 2, 14, Color("#8a6a52"))
			a.rect(3, 3, 3, 1, Color(1, 1, 1, 0.8))
			a.rect(3, 4, 1, 2, Color(1, 1, 1, 0.6))
		"wall_shelf":
			a = PixelArt.new(48, 26)
			a.rect(0, 0, 48, 26, Color("#8a6a52"))
			for r in [2, 10, 18]:
				a.rect(1, r + 6, 46, 1, Color("#6a4a32"))
				for i in 11:
					a.rect(2 + i * 4, r + 1, 3, 5, [Color("#f4f1e8"), Color("#d84a4a"), Color("#3a6fd8"), Color("#f2c94c")][(i + r) % 4])
		"price_banner":
			a = PixelArt.new(64, 10)
			a.rect(0, 0, 64, 10, Color("#3fa06a"))
			for i in 8:
				a.rect(3 + i * 8, 3, 5, 4, Color("#f4f1e8"))
				a.rect(4 + i * 8, 4, 3, 2, Color("#d84a4a"))
		_:
			a = PixelArt.new(4, 4)
			a.rect(0, 0, 4, 4, Color.MAGENTA)
	a.outline()
	return a
