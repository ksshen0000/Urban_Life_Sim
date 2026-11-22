class_name Hud
extends Control
## T006 HUD: day + time (top left), cash (top right), hunger / energy / stress (bottom left) and
## the interaction prompt. Values always appear as text, never colour alone (spec §6).
## Reads the world only through SimulationSession.view_player(); refreshes on every committed
## DomainEvent re-broadcast by the GameEventBus.

var _session: SimulationSession
var _bus: GameEventBus
var _day_label: Label
var _cash_label: Label
var _needs_box: VBoxContainer
var _need_rows: Dictionary = {}  # need_id -> {bar: ProgressBar, value: Label}

## Bar colours are a reading aid only; the numeric value is always shown next to the bar.
const BAR_COLORS := [Color("#6cc46c"), Color("#e0a64a"), Color("#b88be0"), Color("#5fb3d9")]  # by need id order: energy, hunger, stress
var _objective_panel: PanelContainer
var _objective_label: Label
var _hint_label: Label
var _prompt_panel: PanelContainer
var _prompt_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func bind(session: SimulationSession, bus: GameEventBus) -> void:
	_session = session
	if _bus != null and _bus.domain_event_published.is_connected(_on_event):
		_bus.domain_event_published.disconnect(_on_event)
	_bus = bus
	if _bus != null:
		_bus.domain_event_published.connect(_on_event)
	_build_needs()
	refresh()


## Language switched in the settings: rebuild every text (need names are built once).
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _session != null and is_node_ready():
		_build_needs.call_deferred()


func refresh() -> void:
	if _session == null:
		return
	var v := _session.view_player()
	var mod: int = v["minute_of_day"]
	@warning_ignore("integer_division")
	var hh := mod / 60
	_day_label.text = "%s  %02d:%02d" % [Localizer.text("ui.hud.day", {"day": v["day_index"]}), hh, mod % 60]
	_cash_label.text = Localizer.text("ui.hud.cash", {"cash": MoneyFormat.format_minor(
		v["balance_minor"], v["currency_code"], v["currency_minor_digits"])})
	_refresh_objective()
	for need_id: String in _need_rows:
		var value: int = v["needs"].get(need_id, 0)
		(_need_rows[need_id]["bar"] as ProgressBar).value = value
		(_need_rows[need_id]["value"] as Label).text = Localizer.text("ui.hud.need_value", {"value": value})


## Current tutorial / quest step and its hint (T016), hidden when every quest is done.
func _refresh_objective() -> void:
	var shown := false
	for q in _session.content.get_records("quests"):
		var step := _session.quests.current_step(q["id"])
		if step.is_empty():
			continue
		_objective_label.text = Localizer.text("ui.hud.objective", {"text": tr(step["text_key"])})
		_hint_label.text = tr(step["hint_key"])
		shown = true
		break
	_objective_panel.visible = shown


func get_objective_text() -> String:
	return _objective_label.text if _objective_panel.visible else ""


func set_prompt(display_name: String) -> void:
	_prompt_panel.visible = not display_name.is_empty()
	_prompt_label.text = Localizer.text("ui.prompt.interact", {"name": display_name})


# Read-back helpers for tests and accessibility tooling.
func get_day_text() -> String:
	return _day_label.text


func get_cash_text() -> String:
	return _cash_label.text


func get_need_text(need_id: String) -> String:
	return (_need_rows[need_id]["value"] as Label).text if _need_rows.has(need_id) else ""


func get_prompt_text() -> String:
	return _prompt_label.text if _prompt_panel.visible else ""


func _on_event(_e: DomainEvent) -> void:
	refresh()


func _exit_tree() -> void:
	if _bus != null and _bus.domain_event_published.is_connected(_on_event):
		_bus.domain_event_published.disconnect(_on_event)


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)

	var top := HBoxContainer.new()
	column.add_child(top)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	top.add_child(left)
	_day_label = _panel_label(left, 28)
	_objective_panel = PanelContainer.new()
	left.add_child(_objective_panel)
	var obj_box := VBoxContainer.new()
	_objective_panel.add_child(obj_box)
	_objective_label = Label.new()
	_objective_label.add_theme_color_override("font_color", Color("#f2d27a"))
	obj_box.add_child(_objective_label)
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 21)
	_hint_label.add_theme_color_override("font_color", Color("#c9c4b8"))
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size.x = 620
	obj_box.add_child(_hint_label)
	top.add_child(_spacer(true, false))
	_cash_label = _panel_label(top, 28)
	_cash_label.get_parent().size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	column.add_child(_spacer(false, true))

	var prompt_row := CenterContainer.new()
	column.add_child(prompt_row)
	_prompt_panel = PanelContainer.new()
	_prompt_panel.visible = false
	prompt_row.add_child(_prompt_panel)
	_prompt_label = Label.new()
	_prompt_panel.add_child(_prompt_label)

	var bottom := HBoxContainer.new()
	column.add_child(bottom)
	var needs_panel := PanelContainer.new()
	bottom.add_child(needs_panel)
	_needs_box = VBoxContainer.new()
	needs_panel.add_child(_needs_box)
	bottom.add_child(_spacer(true, false))
	_ignore_mouse(margin)


func _build_needs() -> void:
	for c in _needs_box.get_children():
		c.free()
	_need_rows.clear()
	var defs := _session.content.get_records("needs")
	for d in defs:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_needs_box.add_child(row)
		var name_label := Label.new()
		name_label.text = Localizer.text("ui.hud.need_name", {"name": tr(d["name_key"]), "hint": tr("need.%s.hint" % d["id"])})
		name_label.custom_minimum_size.x = 220
		row.add_child(name_label)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(220, 22)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = BAR_COLORS[_need_rows.size() % BAR_COLORS.size()]
		fill.set_corner_radius_all(3)
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0, 0, 0, 0.45)
		back.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", back)
		row.add_child(bar)
		var value_label := Label.new()
		value_label.custom_minimum_size.x = 90
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
		_need_rows[d["id"]] = {"bar": bar, "value": value_label}
	_ignore_mouse(_needs_box)
	if is_node_ready():
		refresh()  # rebuilt rows (language switch) must show values right away


static func _panel_label(parent: Control, font_size: int) -> Label:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	panel.add_child(label)
	return label


static func _spacer(horizontal: bool, vertical: bool) -> Control:
	var c := Control.new()
	if horizontal:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_ignore_mouse(c)
