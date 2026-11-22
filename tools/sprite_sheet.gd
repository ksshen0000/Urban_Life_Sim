extends SceneTree
## Dev tool: renders the procedural pixel people (and other pixel sprites) to one PNG without a
## window or GPU, for reviewing the art. Usage:
##   godot --headless --path . -s res://tools/sprite_sheet.gd -- --out=<file.png> [--zoom=4]

func _initialize() -> void:
	var out := "user://sprite_sheet.png"
	var zoom := 4
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--zoom="):
			zoom = int(arg.trim_prefix("--zoom="))
	var content := ContentRegistry.new()
	content.load_root("res://content")
	var looks: Array = []
	var player := PlayerController.new()
	looks.append(player.look)
	player.free()
	for n in content.get_records("npcs"):
		looks.append(PixelPerson.normalize_look(n["appearance"]))
	var map := content.get_record("maps", "map_old_town")
	var poses: Array = []
	for a: Dictionary in map.get("ambient", []):
		var actor := AmbientActor.new()
		actor.setup(a, map)
		poses.append([actor.look, actor.pose_state(0.0), actor.pose_state(0.5)])
		actor.free()
	var rows: Array = []
	# row per main character: 4 facings x (stand, step) + blink
	for look: Dictionary in looks:
		var row: Array = []
		for f in ["down", "up", "left", "right"]:
			for legs in ["stand", "step_l", "step_r"]:
				row.append(PixelPerson.texture(look, {"facing": f, "legs": legs}).get_image())
		rows.append(row)
	var row2: Array = []
	for p: Array in poses:
		row2.append(PixelPerson.texture(p[0], p[1]).get_image())
	rows.append(row2)
	var row3: Array = []
	for p: Array in poses:
		row3.append(PixelPerson.texture(p[0], p[2]).get_image())
	rows.append(row3)
	var cell := Vector2i(PixelPerson.W + 2 * PixelPerson.M + 2, PixelPerson.H + 2 * PixelPerson.M + 2)
	var cols := 0
	for r: Array in rows:
		cols = maxi(cols, r.size())
	var sheet := Image.create_empty(cols * cell.x, rows.size() * cell.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#79a85c"))
	for y in rows.size():
		for x in (rows[y] as Array).size():
			var im: Image = rows[y][x]
			sheet.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(x * cell.x + 1, y * cell.y + 1))
	sheet.resize(sheet.get_width() * zoom, sheet.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out)
	print("sprite sheet: ", ProjectSettings.globalize_path(out))
	quit()
