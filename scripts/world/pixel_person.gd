class_name PixelPerson
extends RefCounted
## Procedural chibi pixel-art people (player, NPCs, park regulars): a big head (~40% of the
## height), four facings, a 4-frame walk, and poses (sitting, arms out / up / forward, singing).
## Who someone is reads from the silhouette: hair style (short, spiky, buzz, bald, long, bob,
## ponytail, bun, perm), outfit (trousers, skirt, dress, optional work vest) and figure (narrower
## shoulders, lashes and blush for "f"). Painted on a 20 x 28 art grid plus a 1-pixel outline
## margin, then shaded and outlined by PixelArt; textures are cached per look + state.
##
## look  = {skin, hair, hair_style, top, bottom, shoes, outfit, figure, vest?}  (colours "#rrggbb")
## state = {facing: down|up|left|right, legs: stand|step_l|step_r|sit,
##          arm_l / arm_r: down|out|up|forward, mouth: closed|open, blink: bool}

const W := 20
const H := 28
const M := 1  # outline margin
const EYE := Color("#2a1e1e")
const BLUSH := Color("#ef9a9a")
const MOUTH_OPEN := Color("#8a3030")
const STOOL := Color("#9a968c")
const HAIR_STYLES := ["short", "spiky", "buzz", "bald", "long", "bob", "ponytail", "bun", "perm"]
const OUTFITS := ["pants", "skirt", "dress"]

const DEFAULT_LOOK := {"skin": "#f2c9a0", "hair": "#3a2a22", "hair_style": "short", "top": "#3a6fd8",
	"bottom": "#34405a", "shoes": "#4a3328", "outfit": "pants", "figure": "m"}


## Fills missing keys; accepts the old {shirt, hair} appearance.
static func normalize_look(raw: Dictionary) -> Dictionary:
	var look := DEFAULT_LOOK.duplicate()
	for k: String in raw:
		look[k] = raw[k]
	if raw.has("shirt") and not raw.has("top"):
		look["top"] = raw["shirt"]
	return look


static func texture(look: Dictionary, state: Dictionary) -> ImageTexture:
	var key := JSON.stringify([look, state], "", true)
	return PixelArt.cached("person:" + key, func() -> PixelArt: return _paint(look, state))


## Draws a person standing at `foot` (shadow + sprite).
static func draw(canvas: CanvasItem, look: Dictionary, state: Dictionary, foot: Vector2 = Vector2.ZERO) -> void:
	PixelArt.shadow(canvas, foot + Vector2(0, -1), 9.0, 3.5)
	PixelArt.draw_at(canvas, texture(look, state), foot)


## Walk frame from distance walked (0 = standing).
static func walk_legs(step: float) -> String:
	if step <= 0.0:
		return "stand"
	return ["step_l", "stand", "step_r", "stand"][int(step / 7.0) % 4]


static func _paint(look: Dictionary, state: Dictionary) -> PixelArt:
	var a := PixelArt.new(W + 2 * M, H + 2 * M)
	var facing: String = state.get("facing", "down")
	var side := facing == "left" or facing == "right"
	var p := _Painter.new(a, look, state)
	if side:
		p.side_view()
	else:
		p.front_view(facing == "up")
	a.shade()
	a.outline()
	if facing == "left":
		a.flip_h()
	return a


## Paints in content coordinates (0..W-1, 0..H-1); the canvas adds the outline margin.
class _Painter:
	var a: PixelArt
	var look: Dictionary
	var state: Dictionary
	var skin: Color
	var hair: Color
	var top: Color
	var bottom: Color
	var shoes: Color
	var fem: bool
	var dy := 0  # vertical offset of the upper body (sitting)

	func _init(p_art: PixelArt, p_look: Dictionary, p_state: Dictionary) -> void:
		a = p_art
		look = p_look
		state = p_state
		skin = Color(look["skin"])
		hair = Color(look["hair"])
		top = Color(look["top"])
		bottom = Color(look["bottom"])
		shoes = Color(look["shoes"])
		fem = look.get("figure", "m") == "f"

	func px(x: int, y: int, c: Color) -> void:
		a.px(x + PixelPerson.M, y + PixelPerson.M, c)

	func rect(x: int, y: int, w: int, h: int, c: Color) -> void:
		a.rect(x + PixelPerson.M, y + PixelPerson.M, w, h, c)

	# --- front / back ---------------------------------------------------------------------

	func front_view(back: bool) -> void:
		var sit: bool = state.get("legs", "stand") == "sit"
		dy = 3 if sit else 0
		var tl := 6 if fem else 5          # torso left column
		var tr := 13 if fem else 14        # torso right column
		if sit:
			rect(5, 22, 10, 2, PixelPerson.STOOL)
			rect(6, 24, 2, 4, PixelPerson.STOOL.darkened(0.2))
			rect(12, 24, 2, 4, PixelPerson.STOOL.darkened(0.2))
		_legs_front(tl, tr, sit)
		_torso_front(tl, tr)
		# arms behind the body when seen from the back are drawn first
		if back:
			_arm_front(tl, tr, true, state.get("arm_l", "down"))
			_arm_front(tl, tr, false, state.get("arm_r", "down"))
		_head_front(back)
		if not back:
			_arm_front(tl, tr, true, state.get("arm_l", "down"))
			_arm_front(tl, tr, false, state.get("arm_r", "down"))

	func _head_blob(c: Color) -> void:
		rect(6, 3 + dy, 8, 1, c)
		rect(5, 4 + dy, 10, 1, c)
		rect(4, 5 + dy, 12, 8, c)
		rect(5, 13 + dy, 10, 1, c)

	func _head_front(back: bool) -> void:
		var y := dy
		_head_blob(skin)
		if back:
			_hair_back()
			return
		# face
		if state.get("blink", false):
			rect(7, 9 + y, 2, 1, PixelPerson.EYE)
			rect(11, 9 + y, 2, 1, PixelPerson.EYE)
		else:
			rect(7, 8 + y, 1, 2, PixelPerson.EYE)
			rect(12, 8 + y, 1, 2, PixelPerson.EYE)
			px(8, 8 + y, Color.WHITE.darkened(0.05))
			px(13, 8 + y, Color.WHITE.darkened(0.05))
			if fem:
				px(6, 8 + y, PixelPerson.EYE)
				px(13, 7 + y, PixelPerson.EYE)
		if fem:
			px(6, 10 + y, PixelPerson.BLUSH)
			px(13, 10 + y, PixelPerson.BLUSH)
		if state.get("mouth", "closed") == "open":
			rect(9, 11 + y, 2, 2, PixelPerson.MOUTH_OPEN)
		else:
			rect(9, 11 + y, 2, 1, skin.darkened(0.25))
		_hair_front()

	func _hair_front() -> void:
		var y := dy
		var style: String = look.get("hair_style", "short")
		var hl := hair.lightened(0.25)
		var cap := func() -> void:
			rect(6, 3 + y, 8, 1, hair)
			rect(5, 4 + y, 10, 1, hair)
			rect(4, 5 + y, 12, 2, hair)
			rect(7, 4 + y, 4, 1, hl)
		match style:
			"bald":
				rect(4, 7 + y, 1, 4, hair)
				rect(15, 7 + y, 1, 4, hair)
				rect(4, 6 + y, 2, 1, hair)
				rect(14, 6 + y, 2, 1, hair)
				px(8, 4 + y, skin.lightened(0.3))
			"buzz":
				rect(6, 3 + y, 8, 1, hair)
				rect(5, 4 + y, 10, 1, hair)
				rect(4, 5 + y, 1, 3, hair)
				rect(15, 5 + y, 1, 3, hair)
			"perm":
				rect(6, 1 + y, 8, 1, hair)
				rect(4, 2 + y, 12, 1, hair)
				rect(3, 3 + y, 14, 4, hair)
				for x in [5, 8, 11, 14]:
					px(x, 2 + y, hair.lightened(0.18))
					px(x - 1, 5 + y, hair.darkened(0.2))
				rect(3, 7 + y, 2, 5, hair)
				rect(15, 7 + y, 2, 5, hair)
				for x in [4, 8, 12]:
					px(x, 3 + y, hl)
				px(3, 12 + y, hair)
				px(16, 12 + y, hair)
			"long":
				cap.call()
				rect(4, 7 + y, 5, 1, hair)
				rect(11, 7 + y, 5, 1, hair)
				rect(3, 6 + y, 2, 13, hair)
				rect(15, 6 + y, 2, 13, hair)
			"bob":
				cap.call()
				rect(4, 7 + y, 12, 1, hair)
				rect(3, 6 + y, 2, 7, hair)
				rect(15, 6 + y, 2, 7, hair)
			"ponytail":
				cap.call()
				rect(4, 7 + y, 6, 1, hair)
				rect(4, 7 + y, 1, 3, hair)
				rect(15, 7 + y, 1, 3, hair)
				rect(15, 1 + y, 3, 4, hair)
				px(15, 4 + y, Color("#d84a4a"))
			"bun":
				cap.call()
				rect(4, 7 + y, 5, 1, hair)
				rect(11, 7 + y, 5, 1, hair)
				rect(4, 7 + y, 1, 3, hair)
				rect(15, 7 + y, 1, 3, hair)
				_bun_top()
			"spiky":
				cap.call()
				for x in [5, 8, 11, 14]:
					px(x, 2 + y, hair)
				rect(4, 7 + y, 4, 1, hair)
				px(9, 7 + y, hair)
				rect(4, 7 + y, 1, 2, hair)
				rect(15, 7 + y, 1, 2, hair)
			_:  # short
				cap.call()
				rect(4, 7 + y, 6, 1, hair)
				rect(4, 7 + y, 1, 2, hair)
				rect(15, 7 + y, 1, 2, hair)

	## A round bun sitting on the crown, separated from the head by a darker band.
	func _bun_top() -> void:
		var y := dy
		rect(8, 0 + y, 4, 1, hair)
		rect(7, 1 + y, 6, 2, hair)
		rect(8, 1 + y, 2, 1, hair.lightened(0.25))
		rect(7, 3 + y, 6, 1, hair.darkened(0.35))

	func _hair_back() -> void:
		var y := dy
		var style: String = look.get("hair_style", "short")
		if style == "bald":
			rect(4, 8 + y, 12, 5, hair)
			rect(5, 13 + y, 10, 1, hair)
			return
		_head_blob(hair)
		rect(7, 4 + y, 5, 1, hair.lightened(0.25))
		match style:
			"long":
				rect(5, 14 + y, 10, 6, hair)
			"bob":
				rect(4, 13 + y, 12, 1, hair)
			"ponytail":
				rect(9, 13 + y, 2, 6, hair)
				rect(9, 13 + y, 2, 1, Color("#d84a4a"))
			"bun":
				_bun_top()
			"perm":
				rect(6, 1 + y, 8, 1, hair)
				rect(4, 2 + y, 12, 1, hair)
				rect(3, 3 + y, 14, 9, hair)
			"spiky":
				for x in [5, 8, 11, 14]:
					px(x, 2 + y, hair)

	func _torso_front(tl: int, tr: int) -> void:
		var y := dy
		var w := tr - tl + 1
		rect(tl + 1, 14 + y, w - 2, 1, top)
		rect(tl, 15 + y, w, 5, top)
		if look.has("vest"):
			var v := Color(look["vest"])
			rect(tl, 15 + y, 2, 5, v)
			rect(tr - 1, 15 + y, 2, 5, v)
			px(tl + 2, 16 + y, v.lightened(0.4))  # name badge
		# collar
		rect(9, 14 + y, 2, 1, top.darkened(0.25))

	func _legs_front(tl: int, tr: int, sit: bool) -> void:
		var legs: String = state.get("legs", "stand")
		var outfit: String = look.get("outfit", "pants")
		var lower := top if outfit == "dress" else bottom
		var lift_l := 1 if legs == "step_l" else 0
		var lift_r := 1 if legs == "step_r" else 0
		if sit:
			# knees toward the viewer, feet on the ground in front of the stool
			if outfit == "pants":
				rect(6, 20 + dy - 1, 8, 2, bottom)
			else:
				rect(tl - 1, 19 + dy - 1, tr - tl + 3, 3, lower)
			rect(6, 23, 3, 3, skin if outfit != "pants" else bottom)
			rect(11, 23, 3, 3, skin if outfit != "pants" else bottom)
			rect(5, 26, 4, 2, shoes)
			rect(11, 26, 4, 2, shoes)
			return
		if outfit == "pants":
			rect(6, 20, 3, 6 - lift_l, bottom)
			rect(11, 20, 3, 6 - lift_r, bottom)
			rect(tl + 1, 20, tr - tl - 1, 1, bottom)
		else:
			rect(tl, 20, tr - tl + 1, 1, lower)
			rect(tl - 1, 21, tr - tl + 3, 1, lower)
			rect(tl - 2, 22, tr - tl + 5, 1, lower)
			rect(tl, 22, 2, 1, lower.lightened(0.15))
			rect(7, 23, 2, 3 - lift_l, skin)
			rect(11, 23, 2, 3 - lift_r, skin)
		rect(5, 26 - lift_l, 4, 2, shoes)
		rect(11, 26 - lift_r, 4, 2, shoes)

	func _arm_front(tl: int, tr: int, left: bool, mode: String) -> void:
		var y := dy
		var sleeve := top.darkened(0.08)
		var x0 := tl - 2 if left else tr + 1   # 2-px arm column next to the torso
		match mode:
			"out":
				var xs := tl - 4 if left else tr + 1
				rect(xs, 15 + y, 4, 2, sleeve)
				rect(tl - 6 if left else tr + 5, 15 + y, 2, 2, skin)
			"up":
				# raised beside and above the head
				var xa := tl - 4 if left else tr + 3
				rect(xa, 5 + y, 2, 10, sleeve)
				rect(mini(xa, x0), 14 + y, absi(xa - x0) + 2, 2, sleeve)
				rect(xa, 3 + y, 2, 2, skin)
			"forward":
				rect(x0, 15 + y, 2, 3, sleeve)
				rect(x0 + (1 if left else -1), 18 + y, 2, 1, sleeve)
				rect(8 if left else 10, 18 + y, 2, 2, skin)
			_:
				var swing := 0
				var legs: String = state.get("legs", "stand")
				if legs == "step_l":
					swing = 1 if left else -1
				elif legs == "step_r":
					swing = -1 if left else 1
				rect(x0, 15 + y, 2, 4 - maxi(swing, 0), sleeve)
				rect(x0, 19 + y - maxi(swing, 0), 2, 1, skin)

	# --- profile (facing right; left is mirrored) ---------------------------------------------

	func side_view() -> void:
		var legs: String = state.get("legs", "stand")
		var sit := legs == "sit"
		dy = 3 if sit else 0
		var outfit: String = look.get("outfit", "pants")
		var lower := top if outfit == "dress" else bottom
		var arm: String = state.get("arm_r", "down")
		if arm == "down" and state.get("arm_l", "down") != "down":
			arm = state.get("arm_l", "down")
		if sit:
			rect(5, 22, 8, 2, PixelPerson.STOOL)
			rect(6, 24, 2, 4, PixelPerson.STOOL.darkened(0.2))
			rect(10, 24, 2, 4, PixelPerson.STOOL.darkened(0.2))
			rect(8, 20, 7, 2, lower)          # thighs forward
			rect(13, 22, 2, 4, skin if outfit != "pants" else bottom)
			rect(13, 26, 4, 2, shoes)
		elif outfit == "pants":
			if legs == "stand":
				rect(8, 20, 4, 6, bottom)
				rect(8, 26, 5, 2, shoes)
			else:
				rect(10, 20, 3, 6, bottom)
				rect(7, 20, 3, 6, bottom.darkened(0.15))
				rect(10, 26, 4, 2, shoes)
				rect(6, 26, 4, 2, shoes.darkened(0.15))
		else:
			rect(7, 20, 6, 1, lower)
			rect(6, 21, 8, 2, lower)
			if legs == "stand":
				rect(9, 23, 2, 3, skin)
				rect(9, 26, 4, 2, shoes)
			else:
				rect(11, 23, 2, 3, skin)
				rect(7, 23, 2, 3, skin.darkened(0.15))
				rect(11, 26, 4, 2, shoes)
				rect(6, 26, 4, 2, shoes.darkened(0.15))
		# torso
		var y := dy
		rect(7, 14 + y, 6, 6, top)
		if look.has("vest"):
			rect(7, 15 + y, 3, 5, Color(look["vest"]))
		# head
		_head_blob(skin)
		_hair_side()
		if state.get("blink", false):
			rect(12, 9 + y, 2, 1, PixelPerson.EYE)
		else:
			rect(13, 8 + y, 1, 2, PixelPerson.EYE)
			if fem:
				px(14, 8 + y, PixelPerson.EYE)
		px(16, 10 + y, skin)  # nose
		if fem:
			px(12, 10 + y, PixelPerson.BLUSH)
		if state.get("mouth", "closed") == "open":
			rect(13, 11 + y, 2, 2, PixelPerson.MOUTH_OPEN)
		else:
			px(14, 11 + y, skin.darkened(0.25))
		# near arm
		var sleeve := top.darkened(0.08)
		match arm:
			"forward", "out":
				rect(10, 15 + y, 4, 2, sleeve)
				rect(14, 15 + y, 2, 2, skin)
			"up":
				rect(10, 9 + y, 2, 6, sleeve)
				rect(10, 7 + y, 2, 2, skin)
			_:
				var swing := 1 if legs == "step_l" else (-1 if legs == "step_r" else 0)
				rect(9 + swing, 15 + y, 2, 4, sleeve)
				rect(9 + swing, 19 + y, 2, 1, skin)

	func _hair_side() -> void:
		var y := dy
		var style: String = look.get("hair_style", "short")
		var hl := hair.lightened(0.25)
		match style:
			"bald":
				rect(4, 7 + y, 2, 5, hair)
				rect(6, 10 + y, 2, 2, hair)
				px(8, 9 + y, skin.darkened(0.15))  # ear
				px(9, 4 + y, skin.lightened(0.3))
				return
			"perm":
				rect(6, 1 + y, 7, 1, hair)
				rect(4, 2 + y, 11, 1, hair)
				rect(3, 3 + y, 13, 4, hair)
				rect(3, 7 + y, 7, 5, hair)
				for x in [5, 8, 11]:
					px(x, 2 + y, hair.lightened(0.18))
				return
		rect(6, 3 + y, 8, 1, hair)
		rect(5, 4 + y, 10, 1, hair)
		rect(4, 5 + y, 12, 2, hair)
		rect(4, 7 + y, 6, 5, hair)
		rect(5, 12 + y, 4, 1, hair)
		rect(8, 4 + y, 4, 1, hl)
		if style != "buzz":
			rect(13, 7 + y, 3, 1, hair)   # fringe over the brow
		match style:
			"long":
				rect(4, 12 + y, 5, 8, hair)
			"bob":
				rect(4, 12 + y, 6, 2, hair)
			"ponytail":
				rect(1, 5 + y, 3, 8, hair)
				px(3, 5 + y, Color("#d84a4a"))
			"bun":
				rect(2, 3 + y, 3, 1, hair)
				rect(1, 4 + y, 4, 3, hair)
				rect(4, 4 + y, 1, 3, hair.darkened(0.35))
			"spiky":
				for x in [6, 9, 12]:
					px(x, 2 + y, hair)
