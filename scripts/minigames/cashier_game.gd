extends Minigame
## Corner-store checkout: click each item (or press Space) to scan it, then hand back the right
## change for the note the customer pays with (coin buttons, or keys 1-6; Enter = give change,
## Backspace = start over). 75 seconds; every correct customer is +20, a wrong change -10.

const ITEMS := [["water", 200], ["noodles", 450], ["bread", 600], ["milk", 550], ["gum", 300],
	["crisps", 750], ["yogurt", 650], ["onigiri", 800], ["coffee", 900], ["tissues", 250]]
const COINS := [2000, 1000, 500, 100, 50, 10]

var rng := RandomNumberGenerator.new()
var basket: Array[Dictionary] = []  # {id, price, scanned}
var paid := 0
var given := 0
var served := 0
var mistakes := 0
var note := ""
var _buttons: HBoxContainer


func _on_start() -> void:
	time_limit = 75.0
	rng.seed = int(context.get("seed", 11))
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 14)
	_buttons.position = Vector2(size.x / 2.0 - 520, size.y - 130)
	add_child(_buttons)
	for i in COINS.size():
		_add_button("Coin_%d" % COINS[i], "%d · %s" % [i + 1, _money(COINS[i])], give.bind(COINS[i]))
	_add_button("Undo", tr("mg.cashier.undo"), undo)
	_add_button("Give", tr("mg.cashier.give"), submit)
	next_customer()


func _add_button(n: String, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.name = n
	b.text = text
	b.custom_minimum_size = Vector2(120, 64)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	_buttons.add_child(b)


func next_customer() -> void:
	basket.clear()
	var n := rng.randi_range(2, 5)
	for i in n:
		var it: Array = ITEMS[rng.randi() % ITEMS.size()]
		basket.append({"id": it[0], "price": it[1], "scanned": false})
	paid = 0
	given = 0


func total() -> int:
	var t := 0
	for it in basket:
		t += int(it["price"])
	return t


func all_scanned() -> bool:
	return basket.all(func(it: Dictionary) -> bool: return it["scanned"])


func scan_next() -> void:
	for i in basket.size():
		if not basket[i]["scanned"]:
			scan(i)
			return


## Scan item `i`; once the whole basket is scanned the customer hands over a note.
func scan(i: int) -> void:
	basket[i]["scanned"] = true
	if all_scanned() and paid == 0:
		var t := total()
		for note_value in [1000, 2000, 5000, 10000]:
			if note_value >= t:
				paid = note_value
				break


func change_due() -> int:
	return paid - total()


func give(amount: int) -> void:
	if paid > 0:
		given += amount


func undo() -> void:
	given = 0


func submit() -> void:
	if paid == 0:
		return
	if given == change_due():
		served += 1
		note = tr("mg.cashier.correct")
	else:
		mistakes += 1
		note = tr("mg.cashier.wrong") % _money(change_due())
	next_customer()


func current_score() -> int:
	return clampi(served * 20 - mistakes * 10, 0, 100)


func _input(event: InputEvent) -> void:
	if not running or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	if k == KEY_SPACE:
		scan_next()
	elif k >= KEY_1 and k <= KEY_6:
		give(COINS[k - KEY_1])
	elif k == KEY_ENTER or k == KEY_KP_ENTER:
		submit()
	elif k == KEY_BACKSPACE:
		undo()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in basket.size():
			if _item_rect(i).has_point((event as InputEventMouseButton).position) and not basket[i]["scanned"]:
				scan(i)
				break


func _item_rect(i: int) -> Rect2:
	return Rect2(size.x / 2.0 - 420 + i * 170, 220, 150, 150)


@warning_ignore("integer_division")
func _money(minor: int) -> String:
	return "¥%d.%02d" % [minor / 100, minor % 100] if minor % 100 != 0 else "¥%d" % (minor / 100)


func _draw() -> void:
	draw_rect(Rect2(size.x / 2.0 - 460, 200, 920, 190), Color("#3a3f46"))   # belt
	for i in basket.size():
		var r := _item_rect(i)
		var it: Dictionary = basket[i]
		panel(r, Color("#f4f1e8") if not it["scanned"] else Color("#9fd8a8"))
		text_at(r.position + Vector2(0, 66), tr("mg.cashier.item." + str(it["id"])), 26, Color("#2a2420"), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		text_at(r.position + Vector2(0, 112), _money(it["price"]), 24, Color("#6b4a2f"), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var screen := Rect2(size.x / 2.0 - 300, 420, 600, 170)
	panel(screen, Color("#10201a"), Color("#3fa06a"))
	var lines := [tr("mg.cashier.total") % _money(total() if all_scanned() else 0)]
	if paid > 0:
		lines.append(tr("mg.cashier.paid") % _money(paid))
		lines.append(tr("mg.cashier.given") % _money(given))
	else:
		lines.append(tr("mg.cashier.scan_hint"))
	for i in lines.size():
		text_at(screen.position + Vector2(24, 48 + i * 44), lines[i], 30, Color("#9fffb0"))
	text_at(Vector2(40, 60), tr("mg.cashier.status") % [served, mistakes], 26)
	if not note.is_empty():
		text_at(Vector2(40, 100), note, 24, Color("#f2d27a"))
