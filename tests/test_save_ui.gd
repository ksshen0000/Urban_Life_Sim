extends "res://tests/framework/test_case.gd"
## T017 / T019 in the real scenes: saving from the pause menu through the GameSession autoload,
## loading replaces the game and puts the player back on the saved tile, a failed load keeps the
## running game, the settings panel applies and persists changes.

const WORLD_SCENE := preload("res://scenes/world/city_world.tscn")
const DIR := "user://test_saves_ui"
const SETTINGS := "user://test_settings.cfg"

var gs: Node
var world: CityWorld
var _settings_before: Dictionary


func before_each() -> void:
	await wait_process_frames(1)  # autoloads enter the tree after the runner's _initialize
	_clear_dir()
	gs = (Engine.get_main_loop() as SceneTree).root.get_node("GameSession")
	gs.saves = SaveManager.new(DIR)
	_settings_before = GameSettings.current.duplicate()
	GameSettings.storage_path = SETTINGS


func after_each() -> void:
	if world != null:
		world.ui.close()
		world.queue_free()
		await wait_process_frames(2)
	world = null
	(Engine.get_main_loop() as SceneTree).paused = false
	gs.end_game()
	gs.saves = SaveManager.new()
	GameSettings.current = _settings_before
	GameSettings.apply(_settings_before)
	GameSettings.storage_path = GameSettings.PATH
	_clear_dir()
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(SETTINGS)


func _clear_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)


func _open_world() -> void:
	world = WORLD_SCENE.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	await wait_physics_frames(3)
	# Close the arrival story so the world is free to use.
	world.ui.close()


func _button(node_name: String) -> Button:
	return world.ui.get_panel_content().find_child(GameUi.button_name(node_name), true, false) as Button


func test_save_from_pause_menu_then_load_restores_game_and_position() -> void:
	assert_true(gs.start_new_game()["ok"])
	await _open_world()
	world.player.position = world.tile_center(Vector2i(25, 13))
	await wait_physics_frames(2)
	var saved_tile := world.player_tile()
	var saved_minute: int = gs.session.world.clock.get_minute()
	world.ui.open_pause()
	assert_false(_button("Save").disabled, "save available in a real game")
	_button("Save").pressed.emit()
	assert_eq(world.ui.get_panel_kind(), "save_save")
	_button("Slot_slot_01").pressed.emit()
	assert_true(FileAccess.file_exists(DIR.path_join("slot_01.json")), "file written")
	assert_not_null(world.ui.get_panel_content().find_child("Feedback", true, false), "saved message shown")
	# Overwriting asks first.
	_button("Slot_slot_01").pressed.emit()
	assert_eq(world.ui.get_panel_kind(), "confirm")
	world.ui.close()

	gs.session.submit("advance_time", {"minutes": 180}, "system")
	var played: SimulationSession = gs.session
	var r: Dictionary = gs.load_game("slot_01")
	assert_true(r["ok"], str(r))
	assert_ne(gs.session, played, "a new session replaces the old one")
	assert_eq(gs.session.world.clock.get_minute(), saved_minute)
	world.queue_free()
	await wait_process_frames(2)
	await _open_world()
	assert_eq(world.player_tile(), saved_tile, "player stands where they saved")


func test_failed_load_keeps_running_game() -> void:
	assert_true(gs.start_new_game()["ok"])
	var running: SimulationSession = gs.session
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(DIR.path_join("slot_02.json"), FileAccess.WRITE)
	f.store_string("{\"save_schema_version\": 1, \"world\": 3}")
	f.close()
	var r: Dictionary = gs.load_game("slot_02")
	assert_false(r["ok"])
	assert_eq(r["error_code"], "E_SAVE_CORRUPT")
	assert_eq(gs.session, running, "running game untouched")
	await _open_world()
	world.ui.open_pause()
	_button("Load").pressed.emit()
	assert_eq(world.ui.get_panel_kind(), "save_load")
	assert_true(_button("Slot_slot_02").disabled, "damaged slot cannot be chosen")
	assert_true(_button("Slot_slot_01").disabled, "empty slot cannot be chosen")


func test_unsaved_scene_session_cannot_save_through_autoload() -> void:
	# A world driven by its own session (tests, tools) must not save the autoload's game.
	var content := ContentRegistry.new()
	content.load_root("res://content")
	var s: SimulationSession = SimulationSession.create_new(content, RegionPolicyRegistry.with_builtin_implementations(),
		"CN_LINCHUAN", {"story_enabled": false})["session"]
	world = WORLD_SCENE.instantiate()
	world.setup(s, null)
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	await wait_physics_frames(2)
	world.ui.open_pause()
	assert_true(_button("Save").disabled)
	assert_true(_button("Load").disabled)


func test_saved_tile_inside_wall_falls_back_to_spawn() -> void:
	var content := ContentRegistry.new()
	content.load_root("res://content")
	var s: SimulationSession = SimulationSession.create_new(content, RegionPolicyRegistry.with_builtin_implementations(),
		"CN_LINCHUAN", {"story_enabled": false})["session"]
	world = WORLD_SCENE.instantiate()
	world.setup(s, null, Vector2i(0, 0))  # border wall
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	await wait_physics_frames(2)
	assert_eq(world.player.position, world.tile_center(Vector2i(35, 11)), "spawn of the arrival location")


func test_settings_panel_applies_and_persists() -> void:
	assert_true(gs.start_new_game()["ok"])
	await _open_world()
	world.ui.open_pause()
	_button("Settings").pressed.emit()
	assert_eq(world.ui.get_panel_kind(), "settings")
	var slider := world.ui.get_panel_content().find_child("SfxVolume", true, false) as HSlider
	assert_not_null(slider)
	slider.value = 30
	assert_eq(GameSettings.current["sfx_volume"], 30)
	var bus := AudioServer.get_bus_index(GameSettings.SFX_BUS)
	assert_true(bus > 0, "SFX bus exists")
	assert_true(absf(AudioServer.get_bus_volume_db(bus) - GameSettings.percent_to_db(30)) < 0.01)
	slider.value = 0
	assert_true(AudioServer.is_bus_mute(bus), "0% mutes")
	var locale := world.ui.get_panel_content().find_child("Locale", true, false) as OptionButton
	locale.select(1)
	locale.item_selected.emit(1)
	assert_eq(TranslationServer.get_locale(), "en")
	assert_eq(tr("ui.pause.title_screen") != "ui.pause.title_screen", true)
	assert_eq(tr("ui.settings.title"), "Settings", "interface text follows the language")
	await wait_process_frames(2)
	assert_eq(world.ui.get_panel_kind(), "settings", "panel rebuilt in the new language")
	locale = world.ui.get_panel_content().find_child("Locale", true, false) as OptionButton
	locale.select(0)
	locale.item_selected.emit(0)
	assert_eq(TranslationServer.get_locale(), "zh_CN")
	assert_eq(GameSettings.load_from(SETTINGS)["sfx_volume"], 0, "written to the redirected file")


func test_settings_file_roundtrip_and_sanitize() -> void:
	var s := GameSettings.sanitize({"master_volume": 55.4, "sfx_volume": 400, "window_mode": "window_1920", "locale": "en"})
	assert_eq(s, {"master_volume": 55, "sfx_volume": 100, "window_mode": "window_1920", "locale": "en"})
	assert_eq(GameSettings.sanitize({"window_mode": "huge", "locale": "tlh", "master_volume": "loud"}), GameSettings.DEFAULTS)
	assert_eq(GameSettings.save_to(s, SETTINGS), OK)
	assert_eq(GameSettings.load_from(SETTINGS), s)
	assert_eq(GameSettings.load_from("user://no_such_settings.cfg"), GameSettings.DEFAULTS)


## A button whose action changes scene removes the UI (and its sound player) from the tree
## before the click sound plays; that must be silent, not an engine error (check.sh scans for it).
func test_click_after_leaving_tree_is_silent() -> void:
	var holder := Node.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var sound := UiSound.new()
	holder.add_child(sound)
	var b := Button.new()
	holder.add_child(b)
	b.pressed.connect(func() -> void: (Engine.get_main_loop() as SceneTree).root.remove_child(holder))
	sound.attach_buttons(holder)
	b.pressed.emit()
	assert_false(sound.is_inside_tree())
	sound.click()
	holder.free()


func test_hud_keeps_need_values_after_language_switch() -> void:
	assert_true(gs.start_new_game()["ok"])
	await _open_world()
	var before: String = world.ui.hud.get_need_text("energy")
	assert_false(before.is_empty())
	GameSettings.set_value("locale", "en")
	await wait_process_frames(3)
	GameSettings.set_value("locale", "zh_CN")
	await wait_process_frames(3)
	assert_eq(world.ui.hud.get_need_text("energy"), before, "values still shown after the rebuild")
