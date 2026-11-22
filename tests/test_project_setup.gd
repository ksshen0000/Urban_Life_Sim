extends "res://tests/framework/test_case.gd"
## T001: project boots into a valid entry scene with the agreed input map and theme.

const REQUIRED_ACTIONS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E],
	"pause_menu": [KEY_ESCAPE],
	"open_inventory": [KEY_I],
	"open_journal": [KEY_J],
}


func test_main_scene_is_boot() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://scenes/boot/boot.tscn")


func test_boot_scene_instantiates() -> void:
	var packed: PackedScene = load("res://scenes/boot/boot.tscn")
	assert_not_null(packed, "boot.tscn must load")
	if packed == null:
		return
	var node := packed.instantiate()
	assert_true(node is Control, "boot root should be a Control")
	assert_not_null(node.get_node_or_null("%VersionLabel"), "VersionLabel unique node")
	node.free()


func test_input_actions_mapped() -> void:
	for action: String in REQUIRED_ACTIONS:
		assert_true(InputMap.has_action(action), "missing action %s" % action)
		if not InputMap.has_action(action):
			continue
		var keys: Array[int] = []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				keys.append(ev.physical_keycode)
		for expected: int in REQUIRED_ACTIONS[action]:
			assert_has(keys, expected, "%s should map %s" % [action, OS.get_keycode_string(expected)])


func test_theme_has_cjk_capable_font() -> void:
	var theme: Theme = load(ProjectSettings.get_setting("gui/theme/custom"))
	assert_not_null(theme, "custom theme must load")
	if theme == null:
		return
	assert_true(theme.default_font is SystemFont, "default font should be a SystemFont fallback chain")
	if theme.default_font is SystemFont:
		assert_has(theme.default_font.font_names, "Noto Sans CJK SC")


func test_display_targets() -> void:
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 1920)
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 1080)
	assert_eq(ProjectSettings.get_setting("display/window/stretch/mode"), "canvas_items")


func test_future_region_dirs_hold_no_content() -> void:
	# Spec 2.4: us/ and eu/ keep only a README until their packs are designed.
	for region in ["us", "eu"]:
		var dir := DirAccess.open("res://content/regions/%s" % region)
		assert_not_null(dir, "content/regions/%s exists" % region)
		if dir == null:
			continue
		var files := Array(dir.get_files()).filter(func(f: String) -> bool: return not f.ends_with(".import"))
		assert_eq(files, ["README.md"], "region %s should contain only README.md" % region)
		assert_eq(dir.get_directories().size(), 0, "region %s should have no subdirs" % region)



func test_boot_self_check() -> void:
	var boot := load("res://scripts/boot/boot.gd")
	var ok: Dictionary = boot.self_check(
		ProjectSettings.get_setting("everyday_city/content/root"),
		ProjectSettings.get_setting("everyday_city/content/default_city_id"))
	assert_true(ok["ok"], str(ok["errors"]))
	assert_true(str(ok["text"]).contains("CN_LINCHUAN"), ok["text"])
	assert_true(str(ok["text"]).contains("CNY"), ok["text"])
	var bad_city: Dictionary = boot.self_check("res://content", "US_NOWHERE")
	assert_false(bad_city["ok"])
	assert_true(str(bad_city["errors"][0]).contains("E_UNKNOWN_CITY"))
	var bad_root: Dictionary = boot.self_check("res://does_not_exist", "CN_LINCHUAN")
	assert_false(bad_root["ok"])
	assert_true(str(bad_root["errors"][0]).contains("E_FILE_MISSING"))
