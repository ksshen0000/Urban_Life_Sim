class_name CharacterCreator
extends Control
## Character creator (D-033): name, gender presentation, hair style and colour, skin, top,
## bottoms (trousers / skirt / dress) and colour, shoes, with a live, turnable, walking preview.
## Used full screen before a new game (title screen) and from the mirror at home. It only edits a
## profile dictionary {name, look}; the caller decides what to do with it (new game / command).
## Button names (tests): Gender_m/f, HairPrev/HairNext, Outfit_<o>, Swatch_<field>_<i>,
## Random, Cancel, Confirm; the name field is NameEdit.

signal confirmed(profile: Dictionary)
signal cancelled

const HAIR := ["#1e1a1a", "#3a2a22", "#6b4430", "#a0683a", "#d9b25a", "#b8b8b8", "#a83a3a", "#3a5aa8"]
const SKIN := ["#f6d5b5", "#f2c9a0", "#e2b48c", "#c98f62", "#9a6a46"]
const TOP := ["#3a6fd8", "#d84a4a", "#3fa06a", "#f2c94c", "#f4f1e8", "#2e2a28", "#e07aa0", "#8a5ad0", "#e07a2e", "#7d8a96"]
const BOTTOM := ["#3d4656", "#2e2a28", "#8a7a5a", "#f4f1e8", "#b03a2e", "#3a3550", "#e07aa0"]
const SHOES := ["#e8e4da", "#2e2a28", "#4a3328", "#d84a4a", "#3a6fd8"]
const FACINGS := ["down", "left", "up", "right"]
const PREVIEW_SCALE := 8

var profile: Dictionary = ProfileSystem.default_profile()
## Rows to show; empty = all (the barber shows only "hair_style" and "hair").
var fields: Array = []
var confirm_text := ""
var subtitle := ""
var _confirm_text := ""
var _title_text := ""
var _preview: TextureRect
var _hair_label: Label
var _name_edit: LineEdit
var _rows: Dictionary = {}  # field -> HBoxContainer of swatches / buttons
var _facing := 0
var _t := 0.0


## `confirm_key`: "ui.creator.start" (new game) or "ui.creator.save" (mirror).
static func make(initial: Dictionary, title_key: String, confirm_key: String, p_fields: Array = []) -> CharacterCreator:
	var c := CharacterCreator.new()
	if not initial.is_empty():
		c.profile = initial.duplicate(true)
	c._title_text = TranslationServer.translate(title_key)
	c._confirm_text = TranslationServer.translate(confirm_key) if not confirm_key.is_empty() else ""
	c.fields = p_fields
	return c


func _shows(field: String) -> bool:
	return fields.is_empty() or fields.has(field)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.1, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 18)
	panel.add_child(outer)
	var title := Label.new()
	title.text = _title_text
	title.add_theme_font_size_override("font_size", 36)
	outer.add_child(title)
	if not subtitle.is_empty():
		var sub := Label.new()
		sub.text = subtitle
		outer.add_child(sub)
	if not confirm_text.is_empty():
		_confirm_text = confirm_text
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 40)
	outer.add_child(body)
	body.add_child(_build_preview())
	body.add_child(_build_options())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 16)
	outer.add_child(buttons)
	if fields.is_empty():
		_button(buttons, "Random", tr("ui.creator.random"), randomize_look)
	_button(buttons, "Cancel", tr("ui.creator.cancel"), func() -> void: cancelled.emit())
	var ok := _button(buttons, "Confirm", _confirm_text, _confirm)
	_refresh()
	ok.grab_focus()


func _build_preview() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var frame := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#6fae55")
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(16)
	frame.add_theme_stylebox_override("panel", bg)
	box.add_child(frame)
	_preview = TextureRect.new()
	_preview.name = "Preview"
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.custom_minimum_size = Vector2(PixelPerson.W + 2, PixelPerson.H + 2) * PREVIEW_SCALE
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(_preview)
	var turn := HBoxContainer.new()
	turn.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(turn)
	_button(turn, "TurnLeft", "◀", func() -> void: _turn(1))
	var l := Label.new()
	l.text = tr("ui.creator.turn")
	turn.add_child(l)
	_button(turn, "TurnRight", "▶", func() -> void: _turn(-1))
	return box


func _build_options() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 14)
	# Controls are only created when shown: a control never added to the tree is an orphan that
	# leaks at exit (and keeps the theme font with all its glyph textures alive).
	if _shows("name"):
		_name_edit = LineEdit.new()
		_name_edit.name = "NameEdit"
		_name_edit.max_length = ProfileSystem.MAX_NAME_LENGTH
		_name_edit.placeholder_text = tr("ui.creator.name_hint")
		_name_edit.custom_minimum_size.x = 320
		_name_edit.text = profile["name"]
		_name_edit.text_changed.connect(func(t: String) -> void: profile["name"] = t)
		_label(grid, "ui.creator.name")
		grid.add_child(_name_edit)
	if _shows("figure"):
		_label(grid, "ui.creator.gender")
		var g := _row(grid, "figure")
		_button(g, "Gender_m", tr("ui.creator.male"), _set_gender.bind("m"))
		_button(g, "Gender_f", tr("ui.creator.female"), _set_gender.bind("f"))
	if _shows("hair_style"):
		_hair_label = Label.new()
		_label(grid, "ui.creator.hair_style")
		var h := _row(grid, "hair_style")
		_button(h, "HairPrev", "◀", _cycle_hair.bind(-1))
		_hair_label.custom_minimum_size.x = 120
		_hair_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(_hair_label)
		_button(h, "HairNext", "▶", _cycle_hair.bind(1))
	if _shows("hair"):
		_swatches(grid, "ui.creator.hair_color", "hair", HAIR)
	if _shows("skin"):
		_swatches(grid, "ui.creator.skin", "skin", SKIN)
	if _shows("top"):
		_swatches(grid, "ui.creator.top", "top", TOP)
	if _shows("outfit"):
		_label(grid, "ui.creator.bottom")
		var o := _row(grid, "outfit")
		for outfit in ProfileSystem.OUTFITS:
			_button(o, "Outfit_" + outfit, tr("ui.creator." + outfit), _set_look.bind("outfit", outfit))
	if _shows("bottom"):
		_swatches(grid, "ui.creator.bottom_color", "bottom", BOTTOM)
	if _shows("shoes"):
		_swatches(grid, "ui.creator.shoes", "shoes", SHOES)
	return grid


func _process(delta: float) -> void:
	_t += delta
	var legs: String = ["stand", "step_l", "stand", "step_r"][int(_t / 0.22) % 4]
	_preview.texture = PixelPerson.texture(PixelPerson.normalize_look(profile["look"]),
		{"facing": FACINGS[_facing], "legs": legs, "blink": fmod(_t, 3.0) < 0.12})


func _turn(step: int) -> void:
	_facing = (_facing + step + FACINGS.size()) % FACINGS.size()


func _set_look(field: String, value: String) -> void:
	profile["look"][field] = value
	_refresh()


## Switching gender also suggests a matching hair style and outfit (both stay changeable).
func _set_gender(figure: String) -> void:
	profile["look"]["figure"] = figure
	profile["look"]["hair_style"] = "short" if figure == "m" else "ponytail"
	profile["look"]["outfit"] = "pants" if figure == "m" else "skirt"
	_refresh()


func _cycle_hair(step: int) -> void:
	var styles := ProfileSystem.HAIR_STYLES
	var i := styles.find(profile["look"]["hair_style"])
	profile["look"]["hair_style"] = styles[(i + step + styles.size()) % styles.size()]
	_refresh()


## Presentation-only randomness (no game rule uses it).
func randomize_look() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fem := rng.randf() < 0.5
	var look: Dictionary = profile["look"]
	look["figure"] = "f" if fem else "m"
	var styles: Array = ["long", "bob", "ponytail", "bun", "perm", "short"] if fem else ["short", "spiky", "buzz", "bald", "short"]
	look["hair_style"] = styles[rng.randi() % styles.size()]
	look["outfit"] = ["pants", "skirt", "dress"][rng.randi() % 3] if fem else "pants"
	look["hair"] = HAIR[rng.randi() % HAIR.size()]
	look["skin"] = SKIN[rng.randi() % SKIN.size()]
	look["top"] = TOP[rng.randi() % TOP.size()]
	look["bottom"] = BOTTOM[rng.randi() % BOTTOM.size()]
	look["shoes"] = SHOES[rng.randi() % SHOES.size()]
	_refresh()


func _confirm() -> void:
	if _name_edit != null:
		profile["name"] = _name_edit.text.strip_edges()
	if ProfileSystem.validate_profile(profile).is_empty():
		confirmed.emit(profile.duplicate(true))


## Highlights the selected option in every row.
func _refresh() -> void:
	var look: Dictionary = profile["look"]
	if _hair_label != null:
		_hair_label.text = tr("ui.creator.hair." + str(look["hair_style"]))
	for field: String in _rows:
		for b in (_rows[field] as HBoxContainer).get_children():
			if b is Button and b.has_meta("value"):
				(b as Button).button_pressed = b.get_meta("value") == look.get(field)


func _label(grid: GridContainer, key: String) -> void:
	var l := Label.new()
	l.text = tr(key)
	grid.add_child(l)


func _row(grid: GridContainer, field: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	grid.add_child(row)
	_rows[field] = row
	return row


func _swatches(grid: GridContainer, key: String, field: String, colors: Array) -> void:
	_label(grid, key)
	var row := _row(grid, field)
	for i in colors.size():
		var b := Button.new()
		b.name = "Swatch_%s_%d" % [field, i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(40, 40)
		b.set_meta("value", colors[i])
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(colors[i])
			sb.set_corner_radius_all(6)
			var selected: bool = state.contains("pressed")
			sb.set_border_width_all(4 if selected else (2 if state == "hover" or state == "focus" else 1))
			sb.border_color = Color("#fff4c2") if selected else Color(0, 0, 0, 0.5)
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(_set_look.bind(field, colors[i]))
		row.add_child(b)


func _button(parent: Control, node_name: String, text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.pressed.connect(on_pressed)
	if node_name.begins_with("Gender_") or node_name.begins_with("Outfit_"):
		b.toggle_mode = true
		b.set_meta("value", node_name.get_slice("_", 1))
	parent.add_child(b)
	return b
