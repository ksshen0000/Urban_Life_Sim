extends SceneTree
## Dev tool: plays most of the game like a player in a real window (GPU resources only leak with
## a real renderer): title + settings, new game + character creator, lease + mirror, store
## interior + shop, walk to Xinhe + barber, bus downtown, settings + language switch, save, load,
## back to title, quit. Then lists anything leaked at exit:
##   godot --path . --verbose -s res://tools/leak_probe.gd 2>&1 | grep -E "leak|still in use|Leaked"
## Expected output: nothing.
func _initialize() -> void:
	_run()
func _f(n: int) -> void:
	for i in n: await process_frame
func _run() -> void:
	await process_frame
	GameSettings.storage_path = "user://leakwide_settings.cfg"
	var gs := root.get_node("GameSession")
	gs.saves = SaveManager.new("user://leakwide_saves")
	var boot: Node = load("res://scenes/boot/boot.tscn").instantiate()
	root.add_child(boot); current_scene = boot
	await _f(5)
	boot.show_settings(); await _f(3); boot.close_sub_panel()
	(boot.find_child("NewGameButton", true, false) as Button).pressed.emit()
	await _f(5)
	(boot.find_child("CharacterCreator", true, false).find_child("Confirm", true, false) as Button).pressed.emit()
	await _f(40)
	var w: CityWorld = current_scene
	var s: SimulationSession = gs.session
	w.ui.close()
	s.submit("sign_lease", {"housing_id": "home_shared_room_01"})
	w.ui.open_home("old_town_apartment"); await _f(3)
	w.ui.open_mirror(); await _f(5)
	(w.ui.get_mirror().find_child("Confirm", true, false) as Button).pressed.emit(); await _f(5)
	s.submit("use_door", {"door_id": "door_convenience_store"}); await _f(20)
	w.ui.open_shop("shop_convenience_store"); await _f(3); w.ui.close()
	s.submit("use_door", {"door_id": "door_convenience_exit"}); await _f(10)
	s.submit("use_door", {"door_id": "street_east_8"}); await _f(20)
	w.ui.close()
	w.ui.open_barber({"id": "door_barber", "price_minor": 3000, "service_minutes": 30}); await _f(5)
	(w.ui.get_mirror().find_child("Confirm", true, false) as Button).pressed.emit(); await _f(5)
	w.ui.close()
	s.submit("use_door", {"door_id": "street_west_8"}); await _f(10)
	s.submit("take_route", {"route_id": "route_1_to_downtown"}); await _f(20)
	w.ui.close()
	w.ui.open_settings(); await _f(3)
	GameSettings.set_value("locale", "en"); await _f(5)
	GameSettings.set_value("locale", "zh_CN"); await _f(5)
	w.ui.open_pause(); await _f(2)
	w.ui.save_to("slot_01", "存档 1"); await _f(5)
	w.ui.load_from("slot_01"); await _f(30)
	w = current_scene
	w.ui.open_pause(); await _f(3)
	w.ui._to_title(); await _f(20)
	print("final scene: ", current_scene.name)
	for f in DirAccess.get_files_at("user://leakwide_saves"):
		DirAccess.remove_absolute("user://leakwide_saves".path_join(f))
	quit()
