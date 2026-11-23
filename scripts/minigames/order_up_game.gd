extends Minigame
## Fast-food orders: read the ticket, put exactly those dishes on the tray (buttons or keys 1-6),
## Enter to serve, Backspace to clear. 75 seconds; a correct order +17, a wrong one -8.

const MENU := ["burger", "chicken_rice", "beef_noodles", "fries", "cola", "soy_milk"]

var rng := RandomNumberGenerator.new()
var ticket: Dictionary = {}  # dish -> count
var tray: Dictionary = {}
var served := 0
var mistakes := 0
var note := ""
var _buttons: HBoxContainer


func _on_start() -> void:
	time_limit = 75.0
	rng.seed = int(context.get("seed", 23))
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	_buttons.position = Vector2(size.x / 2.0 - 640, size.y - 140)
	add_child(_buttons)
	for i in MENU.size():
		_add("Dish_" + MENU[i], "%d · %s" % [i + 1, tr("mg.order_up.dish." + MENU[i])], add_dish.bind(MENU[i]))
	_add("Clear", tr("mg.order_up.clear"), clear_tray)
	_add("Serve", tr("mg.order_up.serve"), serve)
	next_ticket()


func _add(n: String, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.name = n
	b.text = text
	b.custom_minimum_size = Vector2(150, 64)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	_buttons.add_child(b)


func next_ticket() -> void:
	ticket.clear()
	tray.clear()
	for i in rng.randi_range(2, 3):
		var dish: String = MENU[rng.randi() % MENU.size()]
		ticket[dish] = int(ticket.get(dish, 0)) + 1


func add_dish(dish: String) -> void:
	tray[dish] = int(tray.get(dish, 0)) + 1


func clear_tray() -> void:
	tray.clear()


func serve() -> void:
	if tray.is_empty():
		return
	if tray == ticket:
		served += 1
		note = tr("mg.order_up.correct")
	else:
		mistakes += 1
		note = tr("mg.order_up.wrong")
	next_ticket()


func current_score() -> int:
	return clampi(served * 17 - mistakes * 8, 0, 100)


func _input(event: InputEvent) -> void:
	if not running or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	if k >= KEY_1 and k <= KEY_6:
		add_dish(MENU[k - KEY_1])
	elif k == KEY_ENTER or k == KEY_KP_ENTER:
		serve()
	elif k == KEY_BACKSPACE:
		clear_tray()


func _lines(d: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for dish in MENU:
		if d.has(dish):
			out.append("%s × %d" % [tr("mg.order_up.dish." + dish), d[dish]])
	return out


func _draw() -> void:
	var t := Rect2(size.x / 2.0 - 440, 160, 380, 360)
	panel(t, Color("#f4f1e8"))
	text_at(t.position + Vector2(24, 50), tr("mg.order_up.ticket"), 30, Color("#d84a4a"))
	var tl := _lines(ticket)
	for i in tl.size():
		text_at(t.position + Vector2(24, 110 + i * 48), tl[i], 30, Color("#2a2420"))
	var tr_rect := Rect2(size.x / 2.0 + 60, 160, 380, 360)
	panel(tr_rect, Color("#e07a2e"))
	text_at(tr_rect.position + Vector2(24, 50), tr("mg.order_up.tray"), 30, Color("#fbf3dc"))
	var trl := _lines(tray)
	for i in trl.size():
		text_at(tr_rect.position + Vector2(24, 110 + i * 48), trl[i], 30, Color("#fbf3dc"))
	text_at(Vector2(40, 60), tr("mg.order_up.status") % [served, mistakes], 26)
	if not note.is_empty():
		text_at(Vector2(40, 100), note, 24, Color("#f2d27a"))
