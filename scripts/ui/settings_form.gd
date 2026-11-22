class_name SettingsForm
extends RefCounted
## Builds the settings controls (T019) into a container; shared by the title screen and the pause
## menu. Every change is applied and saved immediately through GameSettings. `on_changed(key)` lets
## the owner rebuild its texts after a language switch.
## Node names (tests): MasterVolume, SfxVolume (HSlider), WindowMode, Locale (OptionButton).


static func build(parent: Container, on_changed: Callable = Callable()) -> void:
	var s := GameSettings.current
	_slider_row(parent, "MasterVolume", tr_key("ui.settings.master_volume"), "master_volume", s["master_volume"], on_changed)
	_slider_row(parent, "SfxVolume", tr_key("ui.settings.sfx_volume"), "sfx_volume", s["sfx_volume"], on_changed)
	var modes: Array = []
	for m in GameSettings.WINDOW_MODES:
		modes.append([m, tr_key("ui.settings." + m)])
	_option_row(parent, "WindowMode", tr_key("ui.settings.window"), "window_mode", modes, s["window_mode"], on_changed)
	var locales: Array = []
	for l in GameSettings.LOCALES:
		locales.append([l, tr_key("ui.settings.locale_" + l.to_lower())])
	_option_row(parent, "Locale", tr_key("ui.settings.language"), "locale", locales, s["locale"], on_changed)
	var note := Label.new()
	note.name = "Note"
	note.text = tr_key("ui.settings.note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 600
	note.add_theme_font_size_override("font_size", 20)
	note.modulate = Color(1, 1, 1, 0.75)
	parent.add_child(note)


static func tr_key(key: String) -> String:
	return TranslationServer.translate(key)


static func _row(parent: Container, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size.x = 200
	row.add_child(l)
	return row


static func _slider_row(parent: Container, node_name: String, label_text: String, key: String, value: int,
		on_changed: Callable) -> void:
	var row := _row(parent, label_text)
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 10
	slider.value = value
	slider.custom_minimum_size = Vector2(300, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var shown := Label.new()
	shown.name = node_name + "Value"
	shown.text = "%d%%" % value
	shown.custom_minimum_size.x = 80
	row.add_child(shown)
	slider.value_changed.connect(func(v: float) -> void:
		shown.text = "%d%%" % roundi(v)
		GameSettings.set_value(key, roundi(v))
		if on_changed.is_valid():
			on_changed.call(key))


static func _option_row(parent: Container, node_name: String, label_text: String, key: String, options: Array,
		selected: String, on_changed: Callable) -> void:
	var row := _row(parent, label_text)
	var ob := OptionButton.new()
	ob.name = node_name
	ob.custom_minimum_size.x = 380
	for i in options.size():
		ob.add_item(options[i][1], i)
		ob.set_item_metadata(i, options[i][0])
		if options[i][0] == selected:
			ob.select(i)
	row.add_child(ob)
	ob.item_selected.connect(func(index: int) -> void:
		GameSettings.set_value(key, ob.get_item_metadata(index))
		if on_changed.is_valid():
			on_changed.call(key))
