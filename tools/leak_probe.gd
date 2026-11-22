extends SceneTree
## Dev tool: plays title -> new game -> character creator -> city -> pause -> Quit like a player,
## in a real window (GPU resources only leak with a real renderer), so leaks at exit show up:
##   godot --path . --verbose -s res://tools/leak_probe.gd 2>&1 | grep -E "leak|still in use|Leaked"
## Expected output: nothing.
func _initialize() -> void:
	_run()
func _run() -> void:
	await process_frame
	var boot: Node = load("res://scenes/boot/boot.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	for i in 5: await process_frame
	(boot.find_child("NewGameButton", true, false) as Button).pressed.emit()
	for i in 5: await process_frame
	(boot.find_child("CharacterCreator", true, false).find_child("Confirm", true, false) as Button).pressed.emit()
	for i in 60: await process_frame
	var world := current_scene
	print("scene: ", world.name if world else "none")
	world.ui.open_pause()
	for i in 5: await process_frame
	(world.ui.get_panel_content().find_child("Quit", true, false) as Button).pressed.emit()
