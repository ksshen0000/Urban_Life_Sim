extends Control
## Title screen. Applies the stored settings, validates the shipped content packs and the default
## city's region policy (any failure is also reported via push_error so headless boot checks in
## tools/check.sh fail loudly), then offers New game / Load / Settings / Quit.

const SETTING_CONTENT_ROOT := "everyday_city/content/root"
const SETTING_DEFAULT_CITY := "everyday_city/content/default_city_id"

const WORLD_SCENE := "res://scenes/world/city_world.tscn"

@onready var _version_label: Label = %VersionLabel
@onready var _status_label: Label = %StatusLabel
@onready var _new_game_button: Button = %NewGameButton
@onready var _quit_button: Button = %QuitButton
@onready var _load_button: Button = %LoadButton
@onready var _settings_button: Button = %SettingsButton
@onready var _buttons: Control = $Center/Panel/VBox/Buttons
@onready var _sub_panel: VBoxContainer = %SubPanel

var _sound: UiSound

var _city_id := ""


func _ready() -> void:
	GameSettings.load_and_apply()
	_sound = UiSound.new()
	add_child(_sound)
	var version := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	_version_label.text = "v%s · Godot %s" % [version, Engine.get_version_info().string]
	var check := self_check(
		ProjectSettings.get_setting(SETTING_CONTENT_ROOT, "res://content"),
		ProjectSettings.get_setting(SETTING_DEFAULT_CITY, ""))
	for line: String in check["errors"]:
		push_error(line)
	# Players only need to see the self-check when something is wrong; the details stay in the
	# version line for bug reports.
	_status_label.text = "" if check["ok"] else check["text"]
	_status_label.visible = not check["ok"]
	if check["ok"]:
		_version_label.text += " · " + check["text"]
	_city_id = ProjectSettings.get_setting(SETTING_DEFAULT_CITY, "")
	var gs := get_node_or_null("/root/GameSession")
	if check["ok"] and gs != null:
		gs.adopt_content(check["content"])
	_new_game_button.disabled = not check["ok"] or gs == null
	_load_button.disabled = _new_game_button.disabled or not gs.saves.has_any_save()
	_settings_button.disabled = not check["ok"]
	_refresh_texts(check["ok"])
	_new_game_button.pressed.connect(_on_new_game)
	_load_button.pressed.connect(show_load_list)
	_settings_button.pressed.connect(show_settings)
	_quit_button.pressed.connect(func() -> void: get_tree().quit())
	_sound.attach_buttons(self)
	if check["ok"] and SmokeTest.requested():
		get_tree().root.add_child.call_deferred(SmokeTest.new())
		return
	if not _load_button.disabled:
		_load_button.grab_focus()
	elif not _new_game_button.disabled:
		_new_game_button.grab_focus()


func _refresh_texts(ok: bool = true) -> void:
	_new_game_button.text = tr("ui.boot.new_game") if ok else "—"
	_load_button.text = tr("ui.boot.continue") if ok else "—"
	_settings_button.text = tr("ui.boot.settings") if ok else "—"
	_quit_button.text = tr("ui.boot.quit") if ok else "Quit"


## Replaces the main buttons with a list of save slots (one button per slot: Slot_slot_01 ...).
func show_load_list() -> void:
	_open_sub_panel(tr("ui.load.title"))
	var gs := get_node("/root/GameSession")
	var slots: Array = gs.saves.list_slots()
	for i in slots.size():
		var info: Dictionary = slots[i]
		var b := Button.new()
		b.name = "Slot_" + info["slot_id"]
		var label := Localizer.text("ui.save.slot_name", {"n": i + 1}) + " · "
		match info["state"]:
			"ok":
				var sm: Dictionary = info["summary"]
				@warning_ignore("integer_division")
				label += Localizer.text("ui.save.slot_info", {"day": sm["day_index"],
					"time": "%02d:%02d" % [int(sm["minute_of_day"]) / 60, int(sm["minute_of_day"]) % 60],
					"cash": MoneyFormat.format_minor(sm["balance_minor"], _currency_of(info["city_id"]), _digits_of(info["city_id"])),
					"saved_at": GameUi.local_datetime(info["saved_at_unix"])}).replace("\n", " · ")
			"corrupt":
				label += tr("ui.save.slot_corrupt")
			_:
				label += tr("ui.save.slot_empty")
		b.text = label
		b.disabled = info["state"] != "ok"
		b.pressed.connect(_on_load.bind(info["slot_id"]))
		_sub_panel.add_child(b)
	_close_sub_panel_button()


func show_settings() -> void:
	_open_sub_panel(tr("ui.settings.title"))
	SettingsForm.build(_sub_panel, func(key: String) -> void:
		if key == "locale":
			var gs := get_node_or_null("/root/GameSession")
			if gs != null and gs.content != null:
				Localizer.install(gs.content, GameSettings.current["locale"])
			_refresh_texts()
			show_settings.call_deferred())
	_close_sub_panel_button()


func _open_sub_panel(title: String) -> void:
	for c in _sub_panel.get_children():
		_sub_panel.remove_child(c)
		c.queue_free()
	_buttons.visible = false
	_sub_panel.visible = true
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 30)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_panel.add_child(t)


func _close_sub_panel_button() -> void:
	var back := Button.new()
	back.name = "Back"
	back.text = tr("ui.boot.back")
	back.pressed.connect(close_sub_panel)
	_sub_panel.add_child(back)
	_sound.attach_buttons(_sub_panel)
	for c in _sub_panel.get_children():
		if c is Button and not (c as Button).disabled:
			(c as Button).grab_focus()
			break


func close_sub_panel() -> void:
	_sub_panel.visible = false
	_buttons.visible = true
	var gs := get_node_or_null("/root/GameSession")
	_load_button.disabled = _new_game_button.disabled or gs == null or not gs.saves.has_any_save()
	(_load_button if not _load_button.disabled else _new_game_button).grab_focus()


func _on_load(slot_id: String) -> void:
	var r: Dictionary = get_node("/root/GameSession").load_game(slot_id)
	if not r["ok"]:
		_status_label.text = Localizer.text("ui.save.load_failed", {"reason": _error_text(r["error_code"])})
		_status_label.visible = true
		return
	get_tree().change_scene_to_file(WORLD_SCENE)


func _error_text(code: Variant) -> String:
	var c := str(code)
	if c.begins_with("E_INVALID_") or c.begins_with("E_MISSING_") or c.begins_with("E_UNKNOWN_COMPONENT"):
		c = "E_SAVE_CORRUPT"
	var key := "ui.error." + c.to_lower()
	var t := tr(key)
	return t if t != key else c


func _currency_of(city_id: String) -> String:
	var gs := get_node_or_null("/root/GameSession")
	if gs == null or gs.content == null or not gs.content.has_record("cities", city_id):
		return ""
	return gs.content.get_record("cities", city_id)["currency_code"]


func _digits_of(city_id: String) -> int:
	var gs := get_node_or_null("/root/GameSession")
	if gs == null or gs.content == null or not gs.content.has_record("cities", city_id):
		return 2
	var region: Dictionary = gs.content.get_record("regions", gs.content.get_record("cities", city_id)["region_id"])
	return int(region.get("currency_minor_digits", 2))


## New game: create the character first (D-033), then start.
func _on_new_game() -> void:
	var creator := CharacterCreator.make({}, "ui.creator.title", "ui.creator.start")
	creator.name = "CharacterCreator"
	creator.confirmed.connect(start_with_profile)
	creator.cancelled.connect(func() -> void:
		creator.queue_free()
		_new_game_button.grab_focus())
	add_child(creator)


func start_with_profile(profile: Dictionary) -> void:
	var r: Dictionary = get_node("/root/GameSession").start_new_game(_city_id, profile)
	if not r["ok"]:
		push_error("new game failed: [%s] %s" % [r["error_code"], r["message"]])
		_status_label.text = str(r["error_code"])
		_status_label.visible = true
		return
	get_tree().change_scene_to_file(WORLD_SCENE)


## Returns {ok, text, errors}. Pure: no printing, so tests can call it with broken fixtures.
static func self_check(content_root: String, city_id: String) -> Dictionary:
	var content := ContentRegistry.new()
	if not content.load_root(content_root):
		var errors: PackedStringArray = []
		for line in content.get_error_strings():
			errors.append("content: " + line)
		return {"ok": false, "errors": errors,
			"text": "内容包校验失败（%d 个错误，详见日志）" % errors.size()}
	var policy := RegionPolicyRegistry.with_builtin_implementations().create_for_city(content, city_id)
	if not policy["ok"]:
		return {"ok": false, "errors": PackedStringArray(["region policy: [%s] %s" % [policy["error_code"], policy["message"]]]),
			"text": "地区规则加载失败：%s" % policy["error_code"]}
	var rp: RegionPolicy = policy["policy"]
	return {"ok": true, "errors": PackedStringArray(), "content": content, "text": "内容包 %d 个 · 城市 %s · 地区规则 %s（%s）" % [
		content.get_pack_ids().size(), city_id, rp.get_implementation_id(), rp.get_currency_code()]}
