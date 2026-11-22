class_name GameUi
extends CanvasLayer
## In-world UI layer: HUD plus one modal panel at a time (sign message, confirmation, shop,
## inventory, pause menu). While a panel is open, game time and the scene tree are paused
## (spec §3.5: dialogue / menus pause time). Every action a panel offers is submitted as a
## command through SimulationSession; the panel only renders the result.
## Keys: Esc opens the pause menu or closes the open panel, I toggles the inventory.

signal modal_changed(is_open: bool)
## Emitted after a successful trip so the world can load the destination map.
signal travelled

const PAUSE_REASON := "ui"

var _session: SimulationSession
var _modal := false
var _panel_kind := ""
var _overlay: Control
var _content: VBoxContainer
var _scroll: ScrollContainer
## Tallest a panel may get (base 1080p canvas) before it scrolls.
const MAX_PANEL_HEIGHT := 880.0
var _paused_tree := false
## True while the open panel is a queued story entry: those must be answered, so Esc opens the
## pause menu instead of dismissing them (otherwise they would reopen every frame).
var _story_open := false
## Returns the player's standing tile for saves (set by CityWorld; presentation only).
var player_tile_provider: Callable
## Where "Back" in the save/load list leads (pause menu, or closing when opened at home).
var _slots_back: Callable

var sound: UiSound
var _bus: GameEventBus
var _last_balance := 0

@onready var hud: Hud = $Hud


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10  # above the day/night tint and glow layers (DayNight uses 1 and 2)
	sound = UiSound.new()
	sound.name = "UiSound"
	add_child(sound)
	_build_overlay()


func bind(session: SimulationSession, bus: GameEventBus) -> void:
	_session = session
	hud.bind(session, bus)
	_last_balance = session.economy.get_balance(SimulationSession.PLAYER_ID)
	_disconnect_bus()
	_bus = bus
	if _bus != null:
		_bus.wallet_changed.connect(_on_wallet_changed)
		_bus.day_changed.connect(_on_day_changed)


func _exit_tree() -> void:
	_disconnect_bus()


func _disconnect_bus() -> void:
	if _bus == null:
		return
	if _bus.wallet_changed.is_connected(_on_wallet_changed):
		_bus.wallet_changed.disconnect(_on_wallet_changed)
	if _bus.day_changed.is_connected(_on_day_changed):
		_bus.day_changed.disconnect(_on_day_changed)


func _on_day_changed(_day: int) -> void:
	sound.play("chime")


func _on_wallet_changed(owner_id: String, balance_minor: int) -> void:
	if owner_id != SimulationSession.PLAYER_ID:
		return
	if balance_minor > _last_balance:
		sound.play("coin")
	_last_balance = balance_minor


func is_modal() -> bool:
	return _modal


func get_panel_kind() -> String:
	return _panel_kind


## The open panel's content (tests and accessibility tooling look up named buttons here).
func get_panel_content() -> VBoxContainer:
	return _content


func set_prompt(target: Interactable) -> void:
	hud.set_prompt(target.get_display_name() if target != null else "")


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause_menu"):
		if _modal and _story_open:
			open_pause()
		elif _modal:
			close()
		else:
			open_pause()
	elif Input.is_action_just_pressed("open_inventory") and _session != null:
		if _panel_kind == "inventory":
			close()
		elif not _modal:
			open_inventory()
	elif Input.is_action_just_pressed("open_journal") and _session != null:
		if _panel_kind == "journal":
			close()
		elif not _modal:
			open_journal()


# --- panels -------------------------------------------------------------------------------

func open_message(title: String, body: String) -> void:
	_begin("message", title)
	_add_body(body)
	_add_buttons([["Ok", tr("ui.common.ok"), close]])
	_show()


func open_confirm(title: String, body: String, on_confirm: Callable) -> void:
	_begin("confirm", title)
	_add_body(body)
	_add_buttons([["Confirm", tr("ui.common.ok"), on_confirm], ["Cancel", tr("ui.common.cancel"), close]])
	_show()


## Choose how long to sleep / rest (activity with a duration range). Buttons: "Until" (e.g. sleep
## until 07:00) and Minutes_<n> for each preset. `back` = where "Back" leads (default: close).
func open_activity(activity_id: String, back: Callable = Callable(), feedback: String = "") -> void:
	var activity := _session.content.get_record("activities", activity_id)
	_begin("activity", tr(activity["name_key"]))
	_add_body(tr(activity["description_key"]))
	var per_hour := Localizer.text("ui.duration.per_hour", {"effects": effects_per_hour(activity)})
	if activity["time_mode"] == "sleeping":
		per_hour += " " + tr("ui.duration.sleep_cap")
	_add_body(per_hour)
	var facts: PackedStringArray = []
	if int(activity.get("price_per_hour_minor", 0)) > 0:
		facts.append(Localizer.text("ui.activity.price", {"price": _money(activity["price_per_hour_minor"])}))
	if not ActivityRules.hours_text(activity).is_empty():
		facts.append(Localizer.text("ui.activity.hours", {"hours": ActivityRules.hours_text(activity)}))
	if not facts.is_empty():
		_add_body(" · ".join(facts))
	var shift := _next_booked_shift()
	if not shift.is_empty():
		var job := _session.content.get_record("jobs", shift["job_id"])
		_add_body(Localizer.text("ui.duration.shift_warning", {"job": tr(job["name_key"]),
			"day": shift["day"], "start": _hhmm(shift["start_minute"])}))
	_add_feedback(feedback)
	var buttons: Array = []
	for o: Dictionary in duration_options(activity):
		buttons.append([o["name"], o["label"], _perform_activity.bind(activity_id, o["minutes"])])
	var mod := _session.world.clock.get_minute_of_day()
	if not ActivityRules.is_open(activity, mod):
		_add_feedback(Localizer.text("ui.activity.closed", {"hours": ActivityRules.hours_text(activity)}))
	elif buttons.is_empty():
		_add_feedback(tr("ui.activity.closes_soon"))
	_add_buttons(buttons, true)
	_add_buttons([["Back", tr("ui.boot.back") if back.is_valid() else tr("ui.common.close"),
		back if back.is_valid() else close]])
	_show()


## [{name, minutes, label}] for the duration buttons, shortest first after the "until" option.
## Only lengths that fit before closing time; none while closed. Paid ones show their price.
func duration_options(activity: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var span := PerformActivityHandler.minutes_range(activity)
	var now := _session.world.clock.get_minute()
	span.y = mini(span.y, ActivityRules.minutes_left(activity, GameClock.minute_of_day_of(now)))
	if activity.has("until_hour"):
		var target := GameClock.minute_from_day_time(_session.world.clock.get_day_index(), int(activity["until_hour"]))
		if target <= now:
			target += GameClock.MINUTES_PER_DAY
		var m := target - now
		if m >= span.x and m <= span.y:
			out.append({"name": "Until", "minutes": m, "label": Localizer.text("ui.duration.until", {
				"what": tr(activity["name_key"]), "end": _end_text(now, m), "length": duration_text(m)}) + _shift_note(now, m)})
	var presets: Array = activity.get("duration_presets_minutes", [])
	if presets.is_empty():
		presets = [activity["duration_minutes"]]
	for m: int in presets:
		if m < span.x or m > span.y:
			continue
		var label := Localizer.text("ui.duration.option", {"length": duration_text(m), "end": _end_text(now, m)})
		if ActivityRules.cost_minor(activity, m) > 0:
			label += " " + Localizer.text("ui.duration.cost", {"cost": _money(ActivityRules.cost_minor(activity, m))})
		out.append({"name": "Minutes_%d" % m, "minutes": m, "label": label + _shift_note(now, m)})
	return out


## Several activities at one spot (arcade machines; the plaza's tai chi and dancing): one row
## each with price and hours; closed ones are shown but disabled. Buttons: Act_<activity_id>.
func open_activity_menu(title: String, activity_ids: Array) -> void:
	_begin("activity_menu", title)
	var mod := _session.world.clock.get_minute_of_day()
	for id: String in activity_ids:
		var a := _session.content.get_record("activities", id)
		var info: PackedStringArray = []
		var price: int = a.get("price_per_hour_minor", 0)
		info.append(Localizer.text("ui.activity.per_hour", {"price": _money(price)}) if price > 0 else tr("ui.activity.free"))
		if not ActivityRules.hours_text(a).is_empty():
			info.append(ActivityRules.hours_text(a))
		var row := _row()
		var b := _button(row, "Act_" + id, tr(a["name_key"]), open_activity.bind(id, open_activity_menu.bind(title, activity_ids)))
		b.disabled = not ActivityRules.is_open(a, mod)
		var d := _cell(row, " · ".join(info) + "\n" + tr(a["description_key"]), 470)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_add_buttons([["Close", tr("ui.common.close"), close]])
	_show()


static func duration_text(minutes: int) -> String:
	@warning_ignore("integer_division")
	var h := minutes / 60
	var m := minutes % 60
	if h == 0:
		return Localizer.text("ui.duration.minutes", {"m": m})
	if m == 0:
		return Localizer.text("ui.duration.hours", {"h": h})
	return Localizer.text("ui.duration.hours_minutes", {"h": h, "m": m})


func _end_text(now: int, minutes: int) -> String:
	var end := now + minutes
	var t := _hhmm(end)
	return t if GameClock.day_index_of(end) == GameClock.day_index_of(now) else tr("ui.duration.next_day") + " " + t


func _next_booked_shift() -> Dictionary:
	var now := _session.world.clock.get_minute()
	for sh in _session.jobs.get_shifts(SimulationSession.PLAYER_ID):  # ordered by start
		if sh["status"] == "booked" and int(sh["start_minute"]) >= now:
			return sh
	return {}


## Waking up later than 30 minutes before a booked shift leaves no time to get there.
const SHIFT_MARGIN_MINUTES := 30


func _shift_note(now: int, minutes: int) -> String:
	var sh := _next_booked_shift()
	if not sh.is_empty() and now + minutes > int(sh["start_minute"]) - SHIFT_MARGIN_MINUTES:
		return " " + tr("ui.duration.misses_shift")
	return ""


## "精力 +10 · 饥饿 +2 · 压力 -2": the activity's per-hour rates (its own, else its time mode's).
func effects_per_hour(activity: Dictionary) -> String:
	var overrides := PerformActivityHandler.rate_overrides(activity)
	var parts: PackedStringArray = []
	for need_id in ["energy", "hunger", "stress"]:
		var need := _session.content.get_record("needs", need_id)
		if need.is_empty():
			continue
		var rates: Dictionary = need["rates_per_hour"]
		var rate: int = overrides.get(need_id, rates.get(activity["time_mode"], rates["awake"]))
		if rate != 0:
			parts.append(Localizer.text("ui.effect.need_delta", {"need": tr(need["name_key"]),
				"delta": ("+%d" % rate) if rate > 0 else str(rate)}))
	return " · ".join(parts)


## Pastimes at home (category "rest" + requires_home), each opening its duration panel.
func open_home_rest(location_id: String) -> void:
	_begin("home_rest", tr("ui.rest.title"))
	for a in _session.content.get_records("activities"):
		if a["category"] != "rest" or not a.get("requires_home", false):
			continue
		var row := _row()
		_button(row, "Rest_" + a["id"], tr(a["name_key"]), open_activity.bind(a["id"], open_home_rest.bind(location_id)))
		var d := _cell(row, tr(a["description_key"]), 460)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_add_buttons([["Back", tr("ui.boot.back"), open_home.bind(location_id)]])
	_show()


func open_shop(shop_id: String, feedback: String = "") -> void:
	var shop := _session.content.get_record("shops", shop_id)
	var v := _session.view_player()
	_begin("shop", tr(shop["name_key"]))
	_add_body(Localizer.text("ui.shop.cash", {"cash": _money(v["balance_minor"])}))
	for entry: Dictionary in shop["stock"]:
		var item := _session.content.get_record("items", entry["item_id"])
		var price: int = entry["price_minor"]
		var affordable: bool = v["balance_minor"] >= price
		var row := _row()
		_cell(row, tr(item["name_key"]), 140)
		_cell(row, describe_item(item), 340)
		_cell(row, _money(price), 130, HORIZONTAL_ALIGNMENT_RIGHT)
		_cell(row, Localizer.text("ui.shop.after", {"after": _money(v["balance_minor"] - price)})
			if affordable else tr("ui.shop.cannot_afford"), 220)
		var buy := _button(row, "Buy_" + entry["item_id"], tr("ui.shop.buy"), _buy.bind(shop_id, entry["item_id"]))
		buy.disabled = not affordable
	_add_feedback(feedback)
	_add_buttons([["Close", tr("ui.common.close"), close]])
	_show()


func open_inventory(feedback: String = "") -> void:
	var items: Dictionary = _session.view_player()["inventory"]
	_begin("inventory", tr("ui.inventory.title"))
	if items.is_empty():
		_add_body(tr("ui.inventory.empty"))
	var ids := PackedStringArray(items.keys())
	ids.sort()
	for item_id in ids:
		var item := _session.content.get_record("items", item_id)
		var row := _row()
		_cell(row, tr(item["name_key"]), 140)
		_cell(row, Localizer.text("ui.inventory.count", {"count": items[item_id]}), 80)
		if item["category"] == "keepsake":
			_cell(row, tr("ui.inventory.keepsake") + " · " + tr(item["description_key"]), 420)
		else:
			_cell(row, describe_item(item), 340)
			_button(row, "Use_" + item_id, tr("ui.inventory.use"), _use.bind(item_id))
	_add_feedback(feedback)
	_add_buttons([["Close", tr("ui.common.close"), close]])
	_show()


## Generic choice list: actions = [[node_name, label, callable], ...].
func open_menu(title: String, actions: Array) -> void:
	_begin("menu", title)
	_add_body(tr("ui.menu.title"))
	var specs := actions.duplicate()
	specs.append(["Cancel", tr("ui.common.cancel"), close])
	_add_buttons(specs, true)
	_show()


# --- jobs (T009/T010) ---------------------------------------------------------------------

func open_job_board(feedback: String = "") -> void:
	var v := _session.view_player()
	var now: int = v["minute"]
	var today: int = v["day_index"]
	_begin("job_board", tr("ui.jobs.title"))
	for job in _session.content.get_records("jobs"):
		var first: Dictionary = job["shifts"][0]
		var minutes: int = first["duration_minutes"]
		@warning_ignore("integer_division")
		var gross: int = int(job["hourly_wage_minor"]) * minutes / 60
		var net := _session.policy.calculate_take_home_pay(gross, {"job_id": job["id"]})
		var header := _add_body("%s — %s" % [tr(job["name_key"]), tr(job["description_key"])])
		header.add_theme_font_size_override("font_size", 24)
		var place := tr(_session.content.get_record("locations", job["workplace_location_id"])["name_key"])
		var lines: PackedStringArray = [
			Localizer.text("ui.jobs.wage", {"wage": _money(job["hourly_wage_minor"]), "net": _money(net)}),
			Localizer.text("ui.jobs.where", {"place": place}),
			Localizer.text("ui.jobs.cost", _shift_costs(job, minutes)),
		]
		var commute := _commute_route(job["workplace_location_id"])
		if not commute.is_empty():
			lines.append(Localizer.text("ui.jobs.commute", {"fare": _money(commute["fare_minor"]), "minutes": commute["travel_minutes"]}))
		var info := _add_body("\n".join(lines))
		info.add_theme_color_override("font_color", Color("#c9c4b8"))
		var slots := HFlowContainer.new()
		slots.add_theme_constant_override("h_separation", 10)
		slots.add_theme_constant_override("v_separation", 8)
		_content.add_child(slots)
		if today + JobsSystem.BOOKING_DAYS_AHEAD < int(job["available_from_day"]):
			var l := Label.new()
			l.text = Localizer.text("ui.jobs.not_yet", {"day": job["available_from_day"]})
			slots.add_child(l)
			continue
		for day in [today, today + 1]:
			for t: Dictionary in job["shifts"]:
				var id := JobsSystem.shift_id_for(job["id"], day, t["id"])
				var w := _session.jobs.window(job, day, t["id"])
				var when := Localizer.text("ui.jobs.slot", {"day": tr("ui.jobs.today") if day == today else tr("ui.jobs.tomorrow"),
					"start": _hhmm(w["start"]), "end": _hhmm(w["end"])})
				var existing := _session.jobs.get_shift(id)
				if not existing.is_empty():
					var b := _button(slots, "Book_" + id, "%s · %s" % [when, tr("ui.jobs.booked")], func() -> void: pass)
					b.disabled = true
					continue
				var err := _session.jobs.check_booking(SimulationSession.PLAYER_ID, job["id"], day, t["id"], now, _session.policy)
				if err == "E_SHIFT_UNAVAILABLE" or err == "E_JOB_NOT_OPEN":
					continue
				var bb := _button(slots, "Book_" + id, Localizer.text("ui.jobs.book", {"when": when}), _book.bind(job["id"], day, t["id"]))
				if not err.is_empty():
					bb.disabled = true
					bb.tooltip_text = error_text(err)
	_add_my_shifts()
	_add_feedback(feedback)
	_add_buttons([["Close", tr("ui.common.close"), close]])
	_show()


func _add_my_shifts() -> void:
	var t := _add_body(tr("ui.jobs.my_shifts"))
	t.add_theme_font_size_override("font_size", 24)
	var shifts: Array = _session.jobs.get_shifts(SimulationSession.PLAYER_ID)
	if shifts.is_empty():
		_add_body(tr("ui.jobs.no_shifts"))
		return
	for sh: Dictionary in shifts.slice(maxi(0, shifts.size() - 6)):
		var job := _session.content.get_record("jobs", sh["job_id"])
		var status := Localizer.text("ui.shift.status." + str(sh["status"]), {"net": _money(sh["net_minor"])})
		if sh["status"] == "in_progress":
			status = tr("ui.shift.status.booked")
		_add_body(Localizer.text("ui.jobs.shift_line", {"job": tr(job["name_key"]), "day": sh["day"],
			"start": _hhmm(sh["start_minute"]), "end": _hhmm(sh["end_minute"]), "status": status}))


func _book(job_id: String, day: int, template_id: String) -> void:
	var r := _session.submit("book_shift", {"job_id": job_id, "day": day, "template_id": template_id})
	var feedback := error_text(r.error_code)
	if r.ok:
		var w := _session.jobs.window(_session.content.get_record("jobs", job_id), day, template_id)
		feedback = Localizer.text("ui.jobs.booked_msg", {"job": tr(_session.content.get_record("jobs", job_id)["name_key"]),
			"day": day, "start": _hhmm(w["start"])})
	open_job_board(feedback)


## Shift startable here right now, or {}.
func startable_shift(location_id: String) -> Dictionary:
	return _session.jobs.startable_shift_at(SimulationSession.PLAYER_ID, location_id, _session.world.clock.get_minute())


func open_work(location_id: String) -> void:
	var sh := startable_shift(location_id)
	if sh.is_empty():
		open_message(tr(_session.content.get_record("locations", location_id)["name_key"]), tr("ui.work.none"))
		return
	var job := _session.content.get_record("jobs", sh["job_id"])
	open_confirm(tr(job["name_key"]), Localizer.text("ui.jobs.shift_line", {"job": tr(job["name_key"]), "day": sh["day"],
		"start": _hhmm(sh["start_minute"]), "end": _hhmm(sh["end_minute"]), "status": tr("ui.shift.status.booked")}),
		_work.bind(sh["shift_id"]))


func _work(shift_id: String) -> void:
	var before := _session.world.clock.get_minute()
	var r := _session.submit("work_shift", {"shift_id": shift_id})
	var job := _session.content.get_record("jobs", _session.jobs.get_shift(shift_id)["job_id"])
	if not r.ok:
		open_message(tr(job["name_key"]), error_text(r.error_code))
		return
	var sh := _session.jobs.get_shift(shift_id)
	var lines: PackedStringArray = []
	if before < int(sh["start_minute"]):
		lines.append(Localizer.text("ui.work.waited", {"start": _hhmm(sh["start_minute"])}))
	if int(sh["late_minutes"]) > 0:
		lines.append(Localizer.text("ui.work.late", {"late": sh["late_minutes"]}))
	lines.append(Localizer.text("ui.work.done", {"minutes": sh["worked_minutes"], "gross": _money(sh["gross_minor"]),
		"net": _money(sh["net_minor"])}))
	open_message(tr(job["name_key"]), "\n".join(lines))


func _shift_costs(job: Dictionary, minutes: int) -> Dictionary:
	var out := {"energy": "0", "stress": "0"}
	for r: Dictionary in job["work_rates_per_hour"]:
		@warning_ignore("integer_division")
		var total: int = int(r["per_hour"]) * minutes / 60
		if out.has(r["need_id"]):
			out[r["need_id"]] = ("+%d" % total) if total > 0 else str(total)
	return out


## A route that reaches the map of `location_id` from elsewhere, or {} if it is walkable.
func _commute_route(location_id: String) -> Dictionary:
	var target_map := _session.locations.map_of_location(location_id)
	if target_map == _session.city["start_map_id"]:
		return {}
	for route in _session.content.get_records("transit_routes"):
		if _session.locations.map_of_location(route["to_location_id"]) == target_map:
			return route
	return {}


# --- transit (T012) -----------------------------------------------------------------------

func open_transit(location_id: String, sign_text: String = "", feedback: String = "") -> void:
	var v := _session.view_player()
	_begin("transit", tr("ui.transit.title"))
	if not sign_text.is_empty():
		_add_body(sign_text)
	for route in _session.content.get_records("transit_routes"):
		if route["from_location_id"] != location_id:
			continue
		var row := _row()
		_cell(row, Localizer.text("ui.transit.route", {"route": tr(route["name_key"]), "fare": _money(route["fare_minor"]),
			"minutes": route["travel_minutes"]}), 520)
		var b := _button(row, "Ride_" + route["id"], tr("ui.transit.ride"), _ride.bind(route["id"], location_id, sign_text))
		var mod: int = v["minute_of_day"]
		if mod < int(route["first_departure_minute_of_day"]) or mod > int(route["last_departure_minute_of_day"]):
			b.disabled = true
			_cell(row, error_text("E_NO_DEPARTURE"), 180)
		elif v["balance_minor"] < int(route["fare_minor"]):
			b.disabled = true
			_cell(row, tr("ui.shop.cannot_afford"), 180)
	_add_feedback(feedback)
	_add_buttons([["Close", tr("ui.common.close"), close]])
	_show()


func _ride(route_id: String, from_location_id: String, sign_text: String) -> void:
	var r := _session.submit("take_route", {"route_id": route_id})
	if not r.ok:
		open_transit(from_location_id, sign_text, error_text(r.error_code))
		return
	travelled.emit()
	var route := _session.content.get_record("transit_routes", route_id)
	open_message(tr(route["name_key"]), Localizer.text("ui.transit.arrived", {"time": _hhmm(_session.world.clock.get_minute())}))


# --- home (T011) --------------------------------------------------------------------------

func open_home(location_id: String, feedback: String = "") -> void:
	var lease := _session.housing.get_lease(SimulationSession.PLAYER_ID)
	var housing := {}
	for h in _session.content.get_records("housing"):
		if h["location_id"] == location_id:
			housing = h
	_begin("home", tr("ui.home.title"))
	var actions: Array = []
	if lease.is_empty():
		if not housing.is_empty():
			var due := _session.world.clock.get_day_index() + int(housing["first_due_after_days"])
			_add_body(Localizer.text("ui.home.offer", {"name": tr(housing["name_key"]), "rent": _money(housing["rent_minor"]),
				"days": housing["period_days"], "deposit": _money(housing["deposit_minor"]), "due": due}))
			_add_body(tr(housing["description_key"]))
			actions.append(["Lease_" + housing["id"], tr("ui.menu.lease"), _sign_lease.bind(housing["id"], location_id)])
	else:
		var h := _session.content.get_record("housing", lease["housing_id"])
		_add_body(tr(h["name_key"]))
		_add_body(Localizer.text("ui.home.status", {"rent": _money(HousingSystem.rent_due(_session.policy, h, SimulationSession.PLAYER_ID)),
			"days": h["period_days"], "due": lease["next_due_day"]}))
		if int(lease["overdue_since_day"]) >= 0:
			_add_body(Localizer.text("ui.home.overdue", {"since": lease["overdue_since_day"]}))
		if h["location_id"] == location_id:
			actions.append(["Sleep", tr("ui.home.sleep"), open_activity.bind("activity_sleep", open_home.bind(location_id))])
			actions.append(["Rest", tr("ui.home.rest"), open_home_rest.bind(location_id)])
			actions.append(["Mirror", tr("ui.home.mirror"), open_mirror])
			if _game_session() != null:
				actions.append(["SaveGame", tr("ui.menu.save"), open_slots_from.bind("save", open_home.bind(location_id))])
		if _session.world.clock.get_day_index() >= int(lease["next_due_day"]):
			actions.append(["PayRent", tr("ui.menu.pay_rent"), _pay_rent.bind(location_id)])
	_add_feedback(feedback)
	actions.append(["Close", tr("ui.common.close"), close])
	_add_buttons(actions)
	_show()


## The barber (D-035): the creator limited to hair style and colour; a cut goes through
## `get_haircut` (pays, takes the service time, changes the hair).
func open_barber(barber: Dictionary) -> void:
	close()
	var price := _money(int(barber["price_minor"]))
	var creator := CharacterCreator.make(_session.profile.get_profile(SimulationSession.PLAYER_ID),
		"ui.barber.title", "", ["hair_style", "hair"])
	creator.confirm_text = Localizer.text("ui.creator.cut", {"price": price})
	creator.subtitle = Localizer.text("ui.barber.price", {"price": price, "minutes": barber.get("service_minutes", 30)})
	creator.name = "Mirror"
	add_child(creator)
	_session.world.clock.push_pause(PAUSE_REASON + "_mirror")
	get_tree().paused = true
	var done := func(profile: Dictionary) -> void:
		creator.queue_free()
		_session.world.clock.pop_pause(PAUSE_REASON + "_mirror")
		get_tree().paused = false
		modal_changed.emit(false)
		if profile.is_empty():
			return
		var r := _session.submit("get_haircut", {"barber_id": barber["id"], "hair_style": profile["look"]["hair_style"],
			"hair": profile["look"]["hair"]})
		open_message(tr("ui.barber.title"), Localizer.text("ui.activity.paid", {"cost": price}) if r.ok else error_text(r.error_code))
	creator.confirmed.connect(done)
	creator.cancelled.connect(done.bind({}))
	modal_changed.emit(true)


## The mirror at home: the character creator over the game; saving goes through `set_profile`.
func open_mirror() -> void:
	close()
	var creator := CharacterCreator.make(_session.profile.get_profile(SimulationSession.PLAYER_ID),
		"ui.creator.mirror_title", "ui.creator.save")
	creator.name = "Mirror"
	add_child(creator)
	_session.world.clock.push_pause(PAUSE_REASON + "_mirror")
	get_tree().paused = true
	var done := func(profile: Dictionary) -> void:
		if not profile.is_empty():
			_session.submit("set_profile", profile)
		creator.queue_free()
		_session.world.clock.pop_pause(PAUSE_REASON + "_mirror")
		get_tree().paused = false
		modal_changed.emit(false)
	creator.confirmed.connect(done)
	creator.cancelled.connect(done.bind({}))
	modal_changed.emit(true)


func get_mirror() -> CharacterCreator:
	return get_node_or_null("Mirror") as CharacterCreator


func _sign_lease(housing_id: String, location_id: String) -> void:
	var r := _session.submit("sign_lease", {"housing_id": housing_id})
	var feedback := error_text(r.error_code)
	if r.ok:
		var lease := _session.housing.get_lease(SimulationSession.PLAYER_ID)
		feedback = Localizer.text("ui.home.signed", {"deposit": _money(lease["deposit_minor"]), "due": lease["next_due_day"]})
	open_home(location_id, feedback)


func _pay_rent(location_id: String) -> void:
	var r := _session.submit("pay_rent")
	var feedback := error_text(r.error_code)
	if r.ok:
		feedback = Localizer.text("ui.home.paid", {"due": _session.housing.get_lease(SimulationSession.PLAYER_ID)["next_due_day"]})
	open_home(location_id, feedback)


func _hhmm(game_minute: int) -> String:
	var mod := GameClock.minute_of_day_of(game_minute)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [mod / 60, mod % 60]


# --- story: dialogue, summary (T014/T015) -------------------------------------------------

## Shows the head of the story queue (CityWorld calls this whenever no panel is open).
func open_story_entry(entry: Dictionary) -> void:
	_story_open = true
	if entry.get("kind", "") == "summary":
		_begin("summary", tr("ui.summary.title"))
		var lines: PackedStringArray = []
		for key: String in entry["lines"]:
			lines.append(tr(key))
		_add_body("\n\n".join(lines))
		_add_buttons([["Continue", tr("ui.summary.continue"), _dismiss_entry.bind(entry["entry_id"])]])
		_show()
	else:
		_render_dialogue(entry["tree_id"], entry["node_id"], entry["entry_id"])


## Talk to an NPC in person: their intro the first time, their small talk afterwards.
func open_npc(npc_id: String) -> void:
	_story_open = false
	var npc := _session.content.get_record("npcs", npc_id)
	var tree_id := ChooseDialogueHandler.talk_tree_for(npc, _session.dialogue)
	_render_dialogue(tree_id, _session.content.get_record("dialogues", tree_id)["nodes"][0]["id"], "")


func _render_dialogue(tree_id: String, node_id: String, entry_id: String, feedback: String = "") -> void:
	var tree := _session.content.get_record("dialogues", tree_id)
	var node := {}
	for n: Dictionary in tree["nodes"]:
		if n["id"] == node_id:
			node = n
	_begin("dialogue", _speaker_title(tree))
	_add_body(tr(node["text_key"]))
	var specs: Array = []
	for c: Dictionary in node["choices"]:
		specs.append(["Choice_" + c["id"], tr(c["text_key"]), _choose.bind(tree_id, node_id, c["id"], entry_id)])
	_add_feedback(feedback)
	_add_buttons(specs, true)
	_show()


func _speaker_title(tree: Dictionary) -> String:
	if not tree.has("speaker_id"):
		return tr("ui.dialogue.narrator")
	var name := tr(_session.content.get_record("npcs", tree["speaker_id"])["name_key"])
	return Localizer.text("ui.dialogue.phone", {"name": name}) if tree["channel"] == "phone" else name


func _choose(tree_id: String, node_id: String, choice_id: String, entry_id: String) -> void:
	var args := {"tree_id": tree_id, "node_id": node_id, "choice_id": choice_id}
	if not entry_id.is_empty():
		args["entry_id"] = entry_id
	var log_size := _session.processor.get_event_log().size()
	var r := _session.submit("choose_dialogue", args)
	if not r.ok:
		_render_dialogue(tree_id, node_id, entry_id, error_text(r.error_code))
		return
	var choice := ChooseDialogueHandler.find_choice(_session.content.get_record("dialogues", tree_id), node_id, choice_id)
	if choice.has("next"):
		_render_dialogue(tree_id, choice["next"], entry_id)
		return
	var cooled := _session.processor.get_event_log().slice(log_size).any(
		func(e: DomainEvent) -> bool: return e.type == "relationship_cooldown")
	if cooled:
		open_message(_speaker_title(_session.content.get_record("dialogues", tree_id)), tr("ui.dialogue.cooldown"))
	else:
		close()


func _dismiss_entry(entry_id: String) -> void:
	_session.submit("dismiss_story_entry", {"entry_id": entry_id})
	close()


# --- journal (T016) -----------------------------------------------------------------------

func open_journal() -> void:
	var player_name := _session.profile.get_display_name(SimulationSession.PLAYER_ID)
	_begin("journal", tr("ui.journal.title") if player_name.is_empty()
		else Localizer.text("ui.journal.title_named", {"name": player_name}))
	for q in _session.content.get_records("quests"):
		var head := _add_body(tr(q["name_key"]))
		head.add_theme_font_size_override("font_size", 26)
		var current := _session.quests.get_step_index(q["id"])
		var steps: Array = q["steps"]
		for i in steps.size():
			var key := "ui.journal.quest_done" if i < current else ("ui.journal.quest_now" if i == current else "ui.journal.quest_later")
			var line := _add_body(Localizer.text(key, {"text": tr(steps[i]["text_key"])}))
			if i == current:
				line.add_theme_color_override("font_color", Color("#f2d27a"))
				var hint := _add_body("    " + tr(steps[i]["hint_key"]))
				hint.add_theme_color_override("font_color", Color("#c9c4b8"))
		if current >= steps.size():
			_add_body(tr("ui.journal.quest_complete"))
	_add_my_shifts()
	var rent_head := _add_body(tr("ui.journal.rent"))
	rent_head.add_theme_font_size_override("font_size", 24)
	var lease := _session.housing.get_lease(SimulationSession.PLAYER_ID)
	if lease.is_empty():
		_add_body(tr("ui.journal.no_lease"))
	else:
		var h := _session.content.get_record("housing", lease["housing_id"])
		_add_body(Localizer.text("ui.home.status", {"rent": _money(HousingSystem.rent_due(_session.policy, h, SimulationSession.PLAYER_ID)),
			"days": h["period_days"], "due": lease["next_due_day"]}))
		if int(lease["overdue_since_day"]) >= 0:
			_add_body(Localizer.text("ui.home.overdue", {"since": lease["overdue_since_day"]}))
	var people_head := _add_body(tr("ui.journal.people"))
	people_head.add_theme_font_size_override("font_size", 24)
	var known := 0
	for npc in _session.content.get_records("npcs"):
		if _session.dialogue.is_completed(npc["dialogue_tree_id"]):
			known += 1
			_add_body(Localizer.text("ui.journal.person", {"name": tr(npc["name_key"]), "role": tr(npc["role_key"]),
				"value": _session.relationships.get_value(npc["id"])}))
	if known == 0:
		_add_body(tr("ui.journal.nobody"))
	_add_buttons([["Close", tr("ui.common.close"), close]])
	_show()


func open_pause() -> void:
	_begin("pause", tr("ui.pause.title"))
	_add_buttons([
		["Resume", tr("ui.pause.resume"), close],
		["Save", tr("ui.pause.save"), open_slots_from.bind("save", open_pause)],
		["Load", tr("ui.pause.load"), open_slots_from.bind("load", open_pause)],
		["Settings", tr("ui.pause.settings"), open_settings],
		["TitleScreen", tr("ui.pause.title_screen"), _to_title],
		["Quit", tr("ui.pause.quit"), _quit],
	], true)
	if _game_session() == null:
		for n in ["Save", "Load"]:
			(_content.get_node("Buttons/" + n) as Button).disabled = true
	_show()


func open_settings() -> void:
	_begin("settings", tr("ui.settings.title"))
	var form := VBoxContainer.new()
	form.name = "Form"
	form.add_theme_constant_override("separation", 14)
	_content.add_child(form)
	# A language switch rebuilds the panel so its own texts follow immediately.
	SettingsForm.build(form, func(key: String) -> void:
		if key == "locale":
			open_settings.call_deferred())
	_add_buttons([["Back", tr("ui.boot.back"), open_pause]])
	_show()


# --- save / load (T017) -------------------------------------------------------------------

func open_slots_from(mode: String, back: Callable) -> void:
	_slots_back = back
	open_save_slots(mode)


## mode "save" | "load". One row per slot: summary + action button (Slot_slot_01 ...).
func open_save_slots(mode: String, feedback: String = "") -> void:
	_begin("save_" + mode, tr("ui.save.title") if mode == "save" else tr("ui.load.title"))
	var gs := _game_session()
	var slots: Array = gs.saves.list_slots() if gs != null else []
	for i in slots.size():
		var info: Dictionary = slots[i]
		var row := _row()
		row.name = button_name("Row_" + info["slot_id"])
		var name_text := Localizer.text("ui.save.slot_name", {"n": i + 1})
		_cell(row, name_text, 120)
		var desc := tr("ui.save.slot_empty")
		if info["state"] == "corrupt":
			desc = tr("ui.save.slot_corrupt")
		elif info["state"] == "ok":
			desc = slot_description(info)
		var d := _cell(row, desc, 380)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var b := _button(row, "Slot_" + info["slot_id"], tr("ui.save.save_here") if mode == "save" else tr("ui.save.load_this"),
			_on_slot_pressed.bind(mode, info["slot_id"], name_text, info["state"]))
		b.disabled = mode == "load" and info["state"] != "ok"
	_add_body(tr("ui.save.hint"))
	_add_feedback(feedback)
	_add_buttons([["Back", tr("ui.boot.back"), _slots_back if _slots_back.is_valid() else open_pause]])
	_show()


func slot_description(info: Dictionary) -> String:
	var sm: Dictionary = info["summary"]
	@warning_ignore("integer_division")
	var time := "%02d:%02d" % [int(sm["minute_of_day"]) / 60, int(sm["minute_of_day"]) % 60]
	var cash := MoneyFormat.format_minor(sm["balance_minor"], _session.economy.get_currency_code(),
		_session.get_currency_minor_digits()) if _session != null else str(sm["balance_minor"])
	var text := Localizer.text("ui.save.slot_info", {"day": sm["day_index"], "time": time, "cash": cash,
		"saved_at": local_datetime(info["saved_at_unix"])})
	return (str(sm["player_name"]) + " · " + text) if not str(sm.get("player_name", "")).is_empty() else text


static func local_datetime(unix: int) -> String:
	var bias: int = Time.get_time_zone_from_system().get("bias", 0)
	return Time.get_datetime_string_from_unix_time(unix + bias * 60, true).substr(0, 16)


func _on_slot_pressed(mode: String, slot_id: String, slot_name: String, state: String) -> void:
	if mode == "save":
		if state == "empty":
			save_to(slot_id, slot_name)
		else:
			open_confirm(tr("ui.save.overwrite_title"), Localizer.text("ui.save.overwrite_body", {"slot": slot_name}),
				save_to.bind(slot_id, slot_name))
	else:
		open_confirm(tr("ui.save.load_confirm_title"), tr("ui.save.load_confirm_body"), load_from.bind(slot_id))


func save_to(slot_id: String, slot_name: String) -> void:
	var tile := Vector2i(-1, -1)
	if player_tile_provider.is_valid():
		tile = player_tile_provider.call()
	var r: Dictionary = _game_session().save_game(slot_id, tile)
	open_save_slots("save", Localizer.text("ui.save.saved", {"slot": slot_name}) if r["ok"] else save_error_text(r["error_code"]))


func load_from(slot_id: String) -> void:
	var r: Dictionary = _game_session().load_game(slot_id)
	if not r["ok"]:
		open_save_slots("load", Localizer.text("ui.save.load_failed", {"reason": save_error_text(r["error_code"])}))
		return
	close()
	get_tree().change_scene_to_file("res://scenes/world/city_world.tscn")


## Component restore codes (E_INVALID_NEEDS_STATE ...) all mean "this file is damaged".
func save_error_text(code: Variant) -> String:
	var c := str(code)
	if c.begins_with("E_INVALID_") or c.begins_with("E_MISSING_") or c.begins_with("E_UNKNOWN_COMPONENT"):
		c = "E_SAVE_CORRUPT"
	return error_text(c)


## The GameSession autoload, only if it runs the game this UI shows (tests drive their own sessions).
func _game_session() -> Node:
	var gs := get_node_or_null("/root/GameSession")
	return gs if gs != null and _session != null and gs.get("session") == _session else null


func close() -> void:
	_story_open = false
	_overlay.visible = false
	_panel_kind = ""
	if _modal:
		_modal = false
		if _session != null:
			_session.world.clock.pop_pause(PAUSE_REASON)
		if _paused_tree:
			get_tree().paused = false
			_paused_tree = false
		modal_changed.emit(false)


# --- actions (all go through commands) ----------------------------------------------------

func _buy(shop_id: String, item_id: String) -> void:
	var r := _session.submit("buy_item", {"shop_id": shop_id, "item_id": item_id, "quantity": 1})
	var feedback := error_text(r.error_code)
	if r.ok:
		var price := 0
		for entry: Dictionary in _session.content.get_record("shops", shop_id)["stock"]:
			if entry["item_id"] == item_id:
				price = entry["price_minor"]
		feedback = Localizer.text("ui.shop.bought", {
			"item": tr(_session.content.get_record("items", item_id)["name_key"]),
			"price": _money(price), "cash": _money(_session.view_player()["balance_minor"])})
	open_shop(shop_id, feedback)


func _use(item_id: String) -> void:
	var r := _session.submit("use_item", {"item_id": item_id})
	var feedback := error_text(r.error_code)
	if r.ok:
		feedback = Localizer.text("ui.inventory.used", {"item": tr(_session.content.get_record("items", item_id)["name_key"])})
	open_inventory(feedback)


func _perform_activity(activity_id: String, minutes: int) -> void:
	var activity := _session.content.get_record("activities", activity_id)
	var before: Dictionary = _session.view_player()["needs"]
	var r := _session.submit("perform_activity", {"activity_id": activity_id, "minutes": minutes})
	var body := error_text(r.error_code)
	if r.ok:
		var v := _session.view_player()
		var changes: PackedStringArray = []
		for need_id in ["energy", "hunger", "stress"]:
			if before.has(need_id) and before[need_id] != v["needs"][need_id]:
				changes.append(Localizer.text("ui.activity.change", {"need": tr(_session.content.get_record("needs", need_id)["name_key"]),
					"before": before[need_id], "after": v["needs"][need_id]}))
		body = Localizer.text("ui.activity.result", {"activity": tr(activity["name_key"]), "day": v["day_index"],
			"time": _hhmm(v["minute"]), "changes": " · ".join(changes)})
		var cost := ActivityRules.cost_minor(activity, minutes)
		if cost > 0:
			body += "\n" + Localizer.text("ui.activity.paid", {"cost": _money(cost)})
	open_message(tr(activity["name_key"]), body)


func _to_title() -> void:
	close()
	var gs := get_node_or_null("/root/GameSession")
	if gs != null:
		gs.end_game()
	get_tree().change_scene_to_file("res://scenes/boot/boot.tscn")


func _quit() -> void:
	get_tree().quit()


# --- text helpers -------------------------------------------------------------------------

## Stable error code -> player-facing sentence (falls back to a generic message with the code).
func error_text(code: Variant) -> String:
	if code == null:
		return ""
	var key := "ui.error." + str(code).to_lower()
	var t := tr(key)
	return t if t != key else Localizer.text("ui.error.generic", {"code": code})


## "饥饿 -35 · 耗时 20 分钟"
func describe_item(item: Dictionary) -> String:
	var parts: PackedStringArray = []
	for e: Dictionary in item["use_effects"]:
		var need := _session.content.get_record("needs", e["need_id"])
		var delta: int = e["delta"]
		parts.append(Localizer.text("ui.effect.need_delta", {"need": tr(need["name_key"]),
			"delta": ("+%d" % delta) if delta > 0 else str(delta)}))
	if int(item["use_minutes"]) > 0:
		parts.append(Localizer.text("ui.effect.minutes", {"minutes": item["use_minutes"]}))
	return " · ".join(parts)


func _money(amount_minor: int) -> String:
	return MoneyFormat.format_minor(amount_minor, _session.economy.get_currency_code(), _session.get_currency_minor_digits())


# --- layout -------------------------------------------------------------------------------

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	# Long panels (job board, journal) scroll instead of running off screen at 720p.
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.add_theme_constant_override("separation", 14)
	_scroll.add_child(_content)


func _begin(kind: String, title: String) -> void:
	if kind != "dialogue" and kind != "summary":
		_story_open = false
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_panel_kind = kind
	var t := Label.new()
	t.name = "Title"
	t.text = title
	t.add_theme_font_size_override("font_size", 34)
	_content.add_child(t)


func _show() -> void:
	_overlay.visible = true
	if not _modal:
		_modal = true
		if _session != null:
			_session.world.clock.push_pause(PAUSE_REASON)
		if not get_tree().paused:
			get_tree().paused = true
			_paused_tree = true
		modal_changed.emit(true)
	_fit_scroll()
	sound.attach_buttons(_content)
	var first := _first_enabled_button(_content)
	if first != null:
		first.grab_focus()


func _fit_scroll() -> void:
	var need := _content.get_combined_minimum_size()
	_scroll.custom_minimum_size = Vector2(need.x, minf(need.y, MAX_PANEL_HEIGHT))
	_scroll.scroll_vertical = 0
	_refit_after_layout()


## Word-wrapped labels only know their real height once the container has given them a width,
## which happens after this frame's layout pass; measure again then (rows of "button + wrapped
## description" were cut off and scrolled otherwise).
func _refit_after_layout() -> void:
	var content_before := _content.get_child_count()
	await get_tree().process_frame
	if not is_instance_valid(_content) or not _overlay.visible or _content.get_child_count() != content_before:
		return
	var need := _content.get_combined_minimum_size()
	_scroll.custom_minimum_size = Vector2(need.x, minf(need.y, MAX_PANEL_HEIGHT))


func _add_body(text: String) -> Label:
	var l := Label.new()
	l.name = "Body"
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 600
	_content.add_child(l)
	return l


func _add_feedback(text: String) -> void:
	if text.is_empty():
		return
	var l := _add_body(text)
	l.name = "Feedback"
	l.add_theme_color_override("font_color", Color("#f2d27a"))


func _add_buttons(specs: Array, vertical: bool = false) -> void:
	var box: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	box.name = "Buttons"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	_content.add_child(box)
	for s: Array in specs:
		_button(box, s[0], s[1], s[2])


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_content.add_child(row)
	return row


static func _cell(row: HBoxContainer, text: String, min_width: float,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = min_width
	l.horizontal_alignment = align
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	return l


## Node names cannot contain "." etc.; ids are sanitized the same way for lookups (button_name()).
static func button_name(raw: String) -> String:
	return raw.validate_node_name().replace(".", "_")


static func _button(parent: Control, node_name: String, text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.name = button_name(node_name)
	b.text = text
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


static func _first_enabled_button(node: Node) -> Button:
	for c in node.get_children():
		if c is Button and not (c as Button).disabled:
			return c
		var nested := _first_enabled_button(c)
		if nested != null:
			return nested
	return null
