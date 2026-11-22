class_name RoadMarkings
extends Node2D
## Ground decals derived from the terrain, drawn at the art scale (2 world px per art pixel):
## kerbs and a dashed centre line on roads, ragged grass lips where lawns meet paving, and a
## stone bank with foam where land meets water. Purely visual.

const PX := PixelArt.SCALE

var _map: Dictionary = {}


func setup(map: Dictionary) -> void:
	_map = map
	queue_redraw()


func _kind(cell: Vector2i) -> String:
	return CityMapBuilder.tile_kind_at(_map, cell)


func _draw() -> void:
	if _map.is_empty():
		return
	var ts: float = _map["tile_size"]
	var rows: Array = _map["rows"]
	for y in rows.size():
		for x in (rows[y] as String).length():
			var cell := Vector2i(x, y)
			var o := Vector2(cell) * ts
			match _kind(cell):
				"road":
					_road(cell, o, ts)
				"tree":
					if _is_street_tree(cell):
						_tree_pit(cell, o, ts)
					else:
						_grass_edges(cell, o, ts)
				"grass":
					_grass_edges(cell, o, ts)
				"water":
					_bank(cell, o, ts)
				"wall_in":
					_wall_trim(cell, o, ts)
				"void":
					if _kind(cell + Vector2i.UP) in ["floor_tile", "floor_wood"]:
						# the cut-away front wall: its top edge
						draw_rect(Rect2(o.x, o.y, ts, 3 * PX), Color("#d9cdb2"))
						draw_rect(Rect2(o.x, o.y + 3 * PX, ts, PX), Color("#8a7e66"))
	for d: Dictionary in _map.get("decals", []):
		var o := Vector2(d["tile"][0], d["tile"][1]) * ts
		for i in 4:
			if d["kind"] == "crosswalk_v":
				draw_rect(Rect2(o.x + 2 * PX, o.y + (i * 4 + 1) * PX, 12 * PX, 2 * PX), Color("#eeeae0"))
			else:
				draw_rect(Rect2(o.x + (i * 4 + 1) * PX, o.y + 2 * PX, 2 * PX, 12 * PX), Color("#eeeae0"))
	for d: Dictionary in _map.get("wall_decor", []):
		var tex := PixelProps.texture(d["kind"])
		draw_texture_rect(tex, Rect2(Vector2(d["tile"][0], d["tile"][1]) * ts,
			Vector2(tex.get_width(), tex.get_height()) * PX), false)


func _road(cell: Vector2i, o: Vector2, ts: float) -> void:
	var up := _kind(cell + Vector2i.UP)
	var down := _kind(cell + Vector2i.DOWN)
	if up != "road":
		draw_rect(Rect2(o.x, o.y, ts, 3 * PX), Color("#b9b5aa"))
		draw_rect(Rect2(o.x, o.y, ts, PX), Color("#d6d2c6"))
		draw_rect(Rect2(o.x, o.y + 3 * PX, ts, PX), Color(0, 0, 0, 0.28))
		for i in 2:
			draw_rect(Rect2(o.x + i * ts / 2.0, o.y, PX, 3 * PX), Color("#8f8b80"))
	if down != "road":
		draw_rect(Rect2(o.x, o.y + ts - 3 * PX, ts, 3 * PX), Color("#a9a59a"))
		draw_rect(Rect2(o.x, o.y + ts - 3 * PX, ts, PX), Color("#c9c5b9"))
	if up == "road":
		draw_rect(Rect2(o.x + 3 * PX, o.y - PX, 7 * PX, 2 * PX), Color("#e6cf5a"))


## Interior wall face: crown moulding at the top, skirting board where it meets the floor.
func _wall_trim(cell: Vector2i, o: Vector2, ts: float) -> void:
	if _kind(cell + Vector2i.UP) != "wall_in":
		draw_rect(Rect2(o.x, o.y, ts, 3 * PX), Color("#a08a6a"))
		draw_rect(Rect2(o.x, o.y + 3 * PX, ts, PX), Color("#d8c8a8"))
	if _kind(cell + Vector2i.DOWN) in ["floor_tile", "floor_wood"]:
		draw_rect(Rect2(o.x, o.y + ts - 4 * PX, ts, 4 * PX), Color("#7a5a3a"))
		draw_rect(Rect2(o.x, o.y + ts - 4 * PX, ts, PX), Color("#9a7a52"))
		draw_rect(Rect2(o.x, o.y + ts, ts, 2 * PX), Color(0, 0, 0, 0.18))


## A tree with no lawn around it stands in a paved tree pit.
func _is_street_tree(cell: Vector2i) -> bool:
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if _kind(cell + d) in ["grass", "tree"]:
			return false
	return true


func _tree_pit(cell: Vector2i, o: Vector2, ts: float) -> void:
	# repaint the cell as paving (same art as the ground tiles), then the pit
	for ay in CityMapBuilder.ART:
		for ax in CityMapBuilder.ART:
			draw_rect(Rect2(o.x + ax * PX, o.y + ay * PX, PX, PX), CityMapBuilder.art_pixel("ground", 0, ax, ay))
	draw_rect(Rect2(o.x + 2 * PX, o.y + 2 * PX, 12 * PX, 12 * PX), Color("#9a958a"))
	draw_rect(Rect2(o.x + 2 * PX, o.y + 2 * PX, 12 * PX, PX), Color("#b9b4a8"))
	draw_rect(Rect2(o.x + 3 * PX, o.y + 3 * PX, 10 * PX, 10 * PX), Color("#5a4230"))
	for i in 10:
		if CityMapBuilder._hash01(cell.x * 10 + i, cell.y, 3) > 0.6:
			draw_rect(Rect2(o.x + (3 + i) * PX, o.y + (4 + i % 7) * PX, PX, PX), Color("#6fae55"))


## Ragged lip on the grass side of each edge that borders paving or road.
func _grass_edges(cell: Vector2i, o: Vector2, ts: float) -> void:
	var dark := Color("#4f8a3e")
	var tuft := Color("#8cc46a")
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var k := _kind(cell + d)
		if k == "grass" or k == "tree" or k == "" or k == "building" or k == "wall":
			continue
		for i in 16:
			var depth := 1 + int(CityMapBuilder._hash01(cell.x * 16 + i, cell.y * 16 + d.x * 3 + d.y * 5, 11) * 2.0)
			var stick_out := CityMapBuilder._hash01(cell.x * 16 + i, cell.y * 16, d.x * 7 + d.y * 13) > 0.78
			var along := o + (Vector2(i * PX, 0) if d.y != 0 else Vector2(0, i * PX))
			match d:
				Vector2i.UP:
					draw_rect(Rect2(along.x, o.y, PX, depth * PX), dark)
					if stick_out:
						draw_rect(Rect2(along.x, o.y - PX, PX, PX), tuft)
				Vector2i.DOWN:
					draw_rect(Rect2(along.x, o.y + ts - depth * PX, PX, depth * PX), dark)
					draw_rect(Rect2(along.x, o.y + ts, PX, PX), Color(0, 0, 0, 0.12))
				Vector2i.LEFT:
					draw_rect(Rect2(o.x, along.y, depth * PX, PX), dark)
					if stick_out:
						draw_rect(Rect2(o.x - PX, along.y, PX, PX), tuft)
				Vector2i.RIGHT:
					draw_rect(Rect2(o.x + ts - depth * PX, along.y, depth * PX, PX), dark)
					if stick_out:
						draw_rect(Rect2(o.x + ts, along.y, PX, PX), tuft)


## Stone bank and foam along the top of a river.
func _bank(cell: Vector2i, o: Vector2, ts: float) -> void:
	if _kind(cell + Vector2i.UP) == "water":
		return
	draw_rect(Rect2(o.x, o.y, ts, 4 * PX), Color("#a9a294"))
	draw_rect(Rect2(o.x, o.y, ts, PX), Color("#c9c2b2"))
	for i in 4:
		draw_rect(Rect2(o.x + i * 4 * PX, o.y + PX, PX, 3 * PX), Color("#8a8476"))
	draw_rect(Rect2(o.x, o.y + 4 * PX, ts, 2 * PX), Color("#2f6890"))
	for i in 16:
		if CityMapBuilder._hash01(cell.x * 16 + i, cell.y, 5) > 0.45:
			draw_rect(Rect2(o.x + i * PX, o.y + 6 * PX, PX, PX), Color(1, 1, 1, 0.55))
