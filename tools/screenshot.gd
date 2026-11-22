extends SceneTree
## Dev tool: renders key screens to PNG for manual UI review at a given window size.
##   godot --path . -s res://tools/screenshot.gd -- --out=<dir> --size=1280x720
## Captures the title screen (+ load list, settings), the world and every panel (story, shop,
## inventory, jobs, home, transit, journal, summary, pause, save slots, settings), the industrial
## map and a few screens in English. Needs a display (not --headless). Uses its own save folder and
## settings file, so the player's saves and settings are never touched.
## Output files: <dir>/<WxH>_<screen>.png

func _initialize() -> void:
	# Watchdog: never leave a hung window on the user's desktop.
	create_timer(60.0, true, false, true).timeout.connect(func() -> void:
		printerr("screenshot: timed out")
		quit(1))
	_run()


func _run() -> void:
	var out := "user://screenshots"
	var size := Vector2i(1280, 720)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--size="):
			var p := arg.trim_prefix("--size=").split("x")
			size = Vector2i(int(p[0]), int(p[1]))
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame  # let autoloads enter the tree before using absolute node paths
	GameSettings.storage_path = "user://screenshot_settings.cfg"
	var gs := root.get_node("GameSession")
	gs.saves = SaveManager.new("user://screenshot_saves")
	var prefix := "%s/%dx%d_" % [out, size.x, size.y]
	# Title screen (it applies the stored settings, including the window size, so size it after).
	var boot: Control = load("res://scenes/boot/boot.tscn").instantiate()
	root.add_child(boot)
	await _frames(2)
	root.size = size  # the root viewport *is* the main window
	await _shot(prefix + "boot.png")
	boot.show_settings()
	await _shot(prefix + "boot_settings.png")
	boot.close_sub_panel()
	boot.queue_free()
	await _frames(2)
	var r: Dictionary = gs.start_new_game()
	if not r["ok"]:
		printerr("screenshot: cannot start game: ", r["message"])
		quit(1)
		return
	var session: SimulationSession = gs.session
	var world: CityWorld = load("res://scenes/world/city_world.tscn").instantiate()
	root.add_child(world)
	await _frames(10)
	world._process(0.0)
	await _shot(prefix + "story.png")                     # arrival narration
	_answer(session)
	world.ui.close()
	session.submit("sign_lease", {"housing_id": "home_shared_room_01"})
	session.submit("buy_item", {"shop_id": "shop_convenience_store", "item_id": "item_drink", "quantity": 2})
	session.submit("buy_item", {"shop_id": "shop_convenience_store", "item_id": "item_instant_food"})
	session.submit("advance_time", {"minutes": 60}, "system")  # 09:00: NPCs out
	_answer(session)
	world.player.position = world.tile_center(Vector2i(22, 7))
	await _frames(20)
	await _shot(prefix + "world.png")
	world.player.position = world.tile_center(Vector2i(46, 7))
	await _frames(20)
	await _shot(prefix + "street_arcade.png")
	world.ui.open_activity_menu(tr("location.arcade.name"), ["activity_arcade_games", "activity_dance_machine"])
	await _shot(prefix + "arcade_menu.png")
	world.ui.close()
	world.player.position = world.tile_center(Vector2i(12, 23))
	await _frames(20)
	await _shot(prefix + "park_morning.png")
	world.player.position = world.tile_center(Vector2i(30, 23))
	await _frames(20)
	await _shot(prefix + "plaza_morning.png")
	world.player.position = world.tile_center(Vector2i(22, 7))
	await _frames(10)
	world.ui.open_shop("shop_convenience_store", "示例反馈：买了饮料，花了 ¥5.00。")
	await _shot(prefix + "shop.png")
	world.ui.open_inventory()
	await _shot(prefix + "inventory.png")
	world.ui.open_job_board()
	await _shot(prefix + "jobs.png")
	world.ui.open_home("old_town_apartment")
	await _shot(prefix + "home.png")
	world.ui.open_activity("activity_sleep")
	await _shot(prefix + "sleep_duration.png")
	world.ui.open_home_rest("old_town_apartment")
	await _shot(prefix + "home_rest.png")
	world.ui.open_transit("old_town_bus_stop", tr("interactable.bus_stop.text"))
	await _shot(prefix + "transit.png")
	world.ui.open_npc("npc_chen_yu")
	await _shot(prefix + "dialogue.png")
	world.ui.open_journal()
	await _shot(prefix + "journal.png")
	world.ui.open_story_entry({"kind": "summary", "entry_id": "preview", "lines": ["summary.money_tight",
		"summary.work_started", "summary.people_friend", "summary.body_ok"]})
	await _shot(prefix + "summary.png")
	world.ui.open_pause()
	await _shot(prefix + "pause.png")
	world.ui.save_to("slot_01", "存档 1")
	await _shot(prefix + "save_slots.png")
	world.ui.open_settings()
	await _shot(prefix + "settings.png")
	GameSettings.set_value("locale", "en")
	world.ui.open_pause()
	await _shot(prefix + "en_pause.png")
	world.ui.open_job_board()
	await _shot(prefix + "en_jobs.png")
	GameSettings.set_value("locale", "zh_CN")
	world.ui.close()
	session.submit("take_route", {"route_id": "route_12_to_industrial"})
	_answer(session)
	await _frames(20)
	world._process(0.0)
	world.ui.close()
	await _frames(10)
	await _shot(prefix + "industrial.png")
	# Back in town in the evening: square dancing and singing.
	session.submit("take_route", {"route_id": "route_12_to_old_town"})
	session.submit("advance_time", {"minutes": GameClock.minute_from_day_time(1, 19, 30) - session.world.clock.get_minute()}, "system")
	_answer(session)
	await _frames(10)
	world._process(0.0)
	world.ui.close()
	world.player.position = world.tile_center(Vector2i(30, 23))
	await _frames(25)
	await _shot(prefix + "plaza_evening.png")
	world.player.position = world.tile_center(Vector2i(14, 23))
	await _frames(20)
	await _shot(prefix + "park_evening.png")
	# Title screen load list, now that a save exists.
	world.queue_free()
	boot = load("res://scenes/boot/boot.tscn").instantiate()
	root.add_child(boot)
	await _frames(2)
	root.size = size
	boot.show_load_list()
	await _shot(prefix + "boot_load.png")
	for f in DirAccess.get_files_at("user://screenshot_saves"):
		DirAccess.remove_absolute("user://screenshot_saves".path_join(f))
	print("screenshots written to ", ProjectSettings.globalize_path(out))
	quit()


func _answer(session: SimulationSession) -> void:
	while session.dialogue.has_pending():
		var e := session.dialogue.peek()
		if e["kind"] == "summary":
			session.submit("dismiss_story_entry", {"entry_id": e["entry_id"]})
			continue
		var tree := session.content.get_record("dialogues", e["tree_id"])
		var c: Dictionary = tree["nodes"][0]["choices"][0]
		session.submit("choose_dialogue", {"tree_id": e["tree_id"], "node_id": e["node_id"], "choice_id": c["id"], "entry_id": e["entry_id"]})


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(path: String) -> void:
	await _frames(6)
	root.get_viewport().get_texture().get_image().save_png(path)
