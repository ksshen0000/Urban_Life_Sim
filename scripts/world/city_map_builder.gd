class_name CityMapBuilder
extends RefCounted
## Builds the ground plane of a city map (T005, 3/4 view per D-019): textured placeholder tiles
## generated at runtime (no art assets yet, spec §6) with full-tile collision on non-walkable
## kinds. Buildings, trees and signs are drawn separately as y-sorted visuals (StructureVisual,
## PropVisual) so the player can stand in front of or behind them.

const WORLD_COLLISION_LAYER := 1
const TILE_COLORS := {
	"ground": Color("#d9c9a6"), "road": Color("#575b63"), "grass": Color("#6fae55"),
	"wall": Color("#8a8f99"), "building": Color("#cdbb95"), "tree": Color("#6fae55"),
	"water": Color("#3f86b8"),
}

## Each kind has VARIANTS hand-off-free variations (stone colour, grass tufts, flowers), picked
## per cell by a stable hash so the ground never looks tiled. Art is 16 x 16 per tile, drawn
## 2 x 2 per art pixel to match the sprites (PixelArt.SCALE).
const VARIANTS := 4
const ART := 16

static var _tileset_cache: Dictionary = {}


static func build_tileset(tile_size: int) -> TileSet:
	if _tileset_cache.has(tile_size):
		return _tileset_cache[tile_size]
	var kinds: Array = ContentSchemas.TILE_KIND_NAMES
	var img := Image.create_empty(tile_size * kinds.size(), tile_size * VARIANTS, false, Image.FORMAT_RGBA8)
	for i in kinds.size():
		for v in VARIANTS:
			_paint_tile(img, i * tile_size, v * tile_size, tile_size, kinds[i], v)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, WORLD_COLLISION_LAYER)
	ts.set_physics_layer_collision_mask(0, 0)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(tile_size, tile_size)
	ts.add_source(src, 0)
	var h := tile_size / 2.0
	var square := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	for i in kinds.size():
		for v in VARIANTS:
			src.create_tile(Vector2i(i, v))
			if not ContentSchemas.is_walkable_kind(kinds[i]):
				var td := src.get_tile_data(Vector2i(i, v), 0)
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, 0, square)
	_tileset_cache[tile_size] = ts
	return ts


## Deterministic pseudo-random 0..1 (stable textures, no RNG state involved).
static func _hash01(x: int, y: int, salt: int) -> float:
	var n := (x * 374761393 + y * 668265263 + salt * 2147483647) & 0x7fffffff
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0


## Paints one tile: an ART x ART pattern scaled up to tile_size.
static func _paint_tile(img: Image, x0: int, y0: int, ts: int, kind: String, variant: int) -> void:
	var k := float(ts) / ART
	for ay in ART:
		for ax in ART:
			var c := art_pixel(kind, variant, ax, ay)
			for yy in range(int(ay * k), int((ay + 1) * k)):
				for xx in range(int(ax * k), int((ax + 1) * k)):
					img.set_pixel(x0 + xx, y0 + yy, c)


## The 16 x 16 pattern of each ground kind.
@warning_ignore("integer_division")
static func art_pixel(kind: String, variant: int, x: int, y: int) -> Color:
	var base: Color = TILE_COLORS[kind]
	var n := _hash01(x + variant * 31, y + variant * 17, kind.hash())
	match kind:
		"ground", "building":
			# 8 x 8 paving slabs: mortar on the top/left, bevel light/dark, per-slab tint
			var slab := _hash01(x / 8 + variant * 2, y / 8 + variant * 3, 7)
			var c := base.darkened(0.05) if slab < 0.3 else (base.lightened(0.04) if slab > 0.75 else base)
			var lx := x % 8
			var ly := y % 8
			if lx == 0 or ly == 0:
				return base.darkened(0.22)
			if lx == 1 or ly == 1:
				c = c.lightened(0.07)
			elif lx == 7 or ly == 7:
				c = c.darkened(0.08)
			if n > 0.96:
				c = c.darkened(0.12)  # a worn speck
			return c
		"grass", "tree":
			var c := base
			# blades: short vertical strokes, darker root, lighter tip
			var col := (x * 7 + variant * 5) % 5
			var row := (y + (x * 3 + variant) % 4) % 5
			if col == 0 and row == 2:
				c = base.lightened(0.18)
			elif col == 0 and row == 3:
				c = base.darkened(0.16)
			elif n < 0.1:
				c = base.darkened(0.08)
			elif n > 0.93:
				c = base.lightened(0.08)
			if variant == 3 and kind == "grass":
				if (x == 4 and y == 5) or (x == 11 and y == 11):
					c = Color("#f4f1e8")
				elif (x == 5 and y == 5) or (x == 12 and y == 11):
					c = Color("#f2c94c")
			return c
		"road":
			var c := base
			if n > 0.86:
				c = base.lightened(0.07)
			elif n < 0.1:
				c = base.darkened(0.12)
			if variant == 2 and y == 9 and x > 3 and x < 9:
				c = base.darkened(0.2)  # a patched crack
			return c
		"wall":
			# low stone wall: lit coping on top, bricks on the face
			if y < 5:
				return base.lightened(0.18) if y == 0 else (base.lightened(0.08) if n > 0.2 else base)
			if y == 5:
				return Color("#4a403a")
			var brick := Color("#7a6a60") if n > 0.5 else Color("#6b5d55")
			var off := 4 if (y / 4) % 2 == 1 else 0
			if y % 4 == 1 or (x + off) % 8 == 0:
				return Color("#51463f")
			return brick
		"water":
			var c := base
			var wave := (x + y * 2 + variant * 3) % 11
			if y % 4 == 1 and wave < 3:
				c = base.lightened(0.28)
			elif y % 4 == 2 and wave < 4:
				c = base.lightened(0.12)
			elif n < 0.12:
				c = base.darkened(0.1)
			return c
	return base


static func populate(layer: TileMapLayer, map: Dictionary) -> void:
	layer.tile_set = build_tileset(map["tile_size"])
	layer.clear()
	var kinds: Array = ContentSchemas.TILE_KIND_NAMES
	var legend: Dictionary = map["legend"]
	var rows: Array = map["rows"]
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var variant := int(_hash01(x, y, 99) * VARIANTS) % VARIANTS
			layer.set_cell(Vector2i(x, y), 0, Vector2i(kinds.find(legend[row[x]]), variant))


## Cells of a given kind, in row-major order.
static func cells_of_kind(map: Dictionary, kind: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rows: Array = map["rows"]
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if map["legend"][row[x]] == kind:
				out.append(Vector2i(x, y))
	return out


static func tile_center(map: Dictionary, tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * float(map["tile_size"])


## Bottom-centre of a tile: the y-sort anchor ("feet") of anything standing on it.
static func tile_foot(map: Dictionary, tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 1.0)) * float(map["tile_size"])


static func pixel_size(map: Dictionary) -> Vector2i:
	return Vector2i((map["rows"][0] as String).length(), (map["rows"] as Array).size()) * int(map["tile_size"])


static func tile_kind_at(map: Dictionary, tile: Vector2i) -> String:
	var rows: Array = map["rows"]
	if tile.y < 0 or tile.y >= rows.size() or tile.x < 0 or tile.x >= (rows[0] as String).length():
		return ""
	return map["legend"][(rows[tile.y] as String)[tile.x]]


## Spawn tile for a location, or (-1, -1) if the map has none.
static func spawn_tile(map: Dictionary, location_id: String) -> Vector2i:
	for s: Dictionary in map["spawns"]:
		if s["location_id"] == location_id:
			return Vector2i(s["tile"][0], s["tile"][1])
	return Vector2i(-1, -1)


## True if the tile lies inside any structure footprint.
static func in_structure(map: Dictionary, tile: Vector2i) -> bool:
	for st: Dictionary in map["structures"]:
		var t: Array = st["tiles"]
		if tile.x >= t[0] and tile.x < t[0] + t[2] and tile.y >= t[1] and tile.y < t[1] + t[3]:
			return true
	return false
