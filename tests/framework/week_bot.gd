extends RefCounted
## Scripted player for balance runs (T018): plays a week (or longer) only through commands, like
## the UI would, following a strategy, and records what happened. Used by tests/test_balance.gd
## (acceptance) and tools/balance_report.gd (the printed table).
##
## Strategy keys (all optional):
##   name: String
##   shifts: {day: [[job_id, template_id], ...]}   booked the day before (or same morning)
##   eat_at: int        hunger at or above which the bot eats (default 50)
##   food: String       item to buy for meals (default item_simple_meal)
##   extras: [[item_id, count_per_day], ...]        bought and used every day (overspending)
##   talk: bool         chat with whoever is around once per day (default true)
##   lease: bool        sign the lease on day 1 (default true)
##   start_money_minor: int                         override the city's starting cash

const P := SimulationSession.PLAYER_ID
const OLD_TOWN := "map_old_town"
const INDUSTRIAL := "map_industrial"
const Sessions := preload("res://tests/framework/session_factory.gd")
const BUS_OUT := "route_12_to_industrial"
const BUS_BACK := "route_12_to_old_town"
const WAKE_HOUR := 6
const BED_HOUR := 22

var s: SimulationSession
var strategy: Dictionary
var stats := {
	"max_hunger": 0, "min_energy": 100, "max_stress": 0, "hungry_hours": 0, "min_balance": 0,
	"shifts_worked": 0, "net_wages": 0, "food_spent": 0, "extras_spent": 0, "fares": 0, "rent_paid": 0,
	"talks": 0, "errors": PackedStringArray(),
}


func _init(p_session: SimulationSession, p_strategy: Dictionary) -> void:
	s = p_session
	strategy = p_strategy
	stats["min_balance"] = s.economy.get_balance(P)


## Builds a session for `strategy` on `content` (story on, like the real game).
static func make_session(content: ContentRegistry, p_strategy: Dictionary) -> SimulationSession:
	var o := {"story_enabled": true}
	if p_strategy.has("start_money_minor"):
		o["starting_money_minor"] = p_strategy["start_money_minor"]
	var r := SimulationSession.create_new(content, RegionPolicyRegistry.with_builtin_implementations(), "CN_LINCHUAN", o)
	return r["session"]


## Plays from the start of the game until the start of `end_day` (06:00); returns the report.
func run(end_day: int = 8) -> Dictionary:
	s.run_story_rules()
	_answer()
	if strategy.get("lease", true):
		_must(s.submit("sign_lease", {"housing_id": "home_shared_room_01"}), "lease")
	_book_for(1)
	_book_for(2)
	return continue_to(end_day)


## Keeps playing (possibly after changing `strategy`) until the start of `end_day`.
func continue_to(end_day: int) -> Dictionary:
	var day := s.world.clock.get_day_index()
	_book_for(day + 1)
	var guard := 0
	while day < end_day and guard < end_day * 2:
		guard += 1
		_play_day(day)
		if s.world.clock.get_day_index() <= day:
			stats["errors"].append("day %d did not end" % day)
			break
		day = s.world.clock.get_day_index()
		_book_for(day + 1)
	return report()


func _play_day(day: int) -> void:
	_book_for(day)
	if strategy.get("talk", true):
		_talk_around()
	_buy_extras()
	var todays: Array = s.jobs.get_shifts(P).filter(func(sh: Dictionary) -> bool:
		return int(sh["day"]) == day and sh["status"] == "booked")
	todays.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["start_minute"]) < int(b["start_minute"]))
	for sh: Dictionary in todays:
		var job := s.content.get_record("jobs", sh["job_id"])
		var far: bool = s.locations.map_of_location(job["workplace_location_id"]) == INDUSTRIAL
		var leave: int = int(sh["start_minute"]) - (45 if far else 15)
		_wait_until(leave)
		if far:
			_eat_before_trip()
			_ride(BUS_OUT)
		Sessions.go(s, job["workplace_location_id"])  # walk in if it is indoors (D-034)
		if strategy.get("talk", true):
			_talk_around()
		_must(s.submit("work_shift", {"shift_id": sh["shift_id"]}), "work " + str(sh["shift_id"]))
		if s.jobs.get_shifts(P).any(func(x: Dictionary) -> bool: return x["shift_id"] == sh["shift_id"] and x["status"] == "completed"):
			stats["shifts_worked"] += 1
		_answer()
		_track()
		if far:
			_ride(BUS_BACK)
		if strategy.get("talk", true):
			_talk_around()
	_wait_until(GameClock.minute_from_day_time(day, BED_HOUR))
	if s.locations.get_map_id(P) == INDUSTRIAL:
		_ride(BUS_BACK)
	_eat_if_hungry()
	if s.housing.has_lease(P):
		Sessions.go(s, "old_town_apartment")
		_must(s.submit("perform_activity", {"activity_id": "activity_sleep"}), "sleep")
		_answer()
		_track()
	_wait_until(GameClock.minute_from_day_time(day + 1, WAKE_HOUR))


func report() -> Dictionary:
	var lease := s.housing.get_lease(P)
	var out := stats.duplicate(true)
	out["name"] = strategy.get("name", "?")
	out["day"] = s.world.clock.get_day_index()
	out["balance"] = s.economy.get_balance(P)
	out["has_lease"] = not lease.is_empty()
	out["periods_paid"] = int(lease.get("periods_paid", 0))
	out["overdue"] = not lease.is_empty() and int(lease["overdue_since_day"]) >= 0
	out["relationship_max"] = 0
	for npc_id: String in s.relationships.get_all():
		out["relationship_max"] = maxi(out["relationship_max"], s.relationships.get_value(npc_id))
	out["events"] = s.events.fired_ids()
	out["quests_done"] = s.content.get_records("quests").filter(func(q: Dictionary) -> bool: return s.quests.is_complete(q["id"])).size()
	return out


# --- steps ------------------------------------------------------------------------------------

func _book_for(day: int) -> void:
	var plan: Dictionary = strategy.get("shifts", {})
	for pair: Array in plan.get(day, []):
		var id := JobsSystem.shift_id_for(pair[0], day, pair[1])
		if s.jobs.get_shifts(P).any(func(x: Dictionary) -> bool: return x["shift_id"] == id):
			continue
		s.submit("book_shift", {"job_id": pair[0], "day": day, "template_id": pair[1]})
		_answer()


func _wait_until(minute: int) -> void:
	while s.world.clock.get_minute() < minute:
		var r := s.submit("advance_time", {"minutes": mini(30, minute - s.world.clock.get_minute())}, "system")
		if not r.ok:
			stats["errors"].append("advance: " + str(r.error_code))
			return
		_answer()
		_eat_if_hungry()
		_track()


func _eat_if_hungry() -> void:
	var guard := 0
	while s.needs.get_value(P, "hunger") >= int(strategy.get("eat_at", 50)) and guard < 4:
		guard += 1
		var food: String = strategy.get("food", "item_simple_meal")
		if s.inventory.count(P, food) == 0:
			if s.locations.get_map_id(P) == INDUSTRIAL:
				return  # nothing to buy out here; eat back in town
			_enter_shop(_shop_for(food))
			var before := s.economy.get_balance(P)
			if not s.submit("buy_item", {"shop_id": _shop_for(food), "item_id": food, "quantity": 1}).ok:
				return  # broke: go hungry
			stats["food_spent"] += before - s.economy.get_balance(P)
		s.submit("use_item", {"item_id": food})
		_answer()


## Warehouse days: eat first if over half hungry (nothing to buy in the industrial area).
func _eat_before_trip() -> void:
	if s.needs.get_value(P, "hunger") >= 35:
		var at: int = strategy.get("eat_at", 50)
		strategy["eat_at"] = 35
		_eat_if_hungry()
		strategy["eat_at"] = at


func _buy_extras() -> void:
	if s.locations.get_map_id(P) == INDUSTRIAL:
		return
	for pair: Array in strategy.get("extras", []):
		_enter_shop(_shop_for(pair[0]))
		for i in int(pair[1]):
			var before := s.economy.get_balance(P)
			if not s.submit("buy_item", {"shop_id": _shop_for(pair[0]), "item_id": pair[0], "quantity": 1}).ok:
				break
			stats["extras_spent"] += before - s.economy.get_balance(P)
			s.submit("use_item", {"item_id": pair[0]})
			_answer()


func _shop_for(item_id: String) -> String:
	for shop in s.content.get_records("shops"):
		for e: Dictionary in shop["stock"]:
			if e["item_id"] == item_id:
				return shop["id"]
	return ""


func _enter_shop(shop_id: String) -> void:
	Sessions.go(s, s.content.get_record("shops", shop_id)["location_id"])
	if strategy.get("talk", true):
		_talk_around()


func _ride(route_id: String) -> void:
	Sessions.go(s, s.content.get_record("transit_routes", route_id)["from_location_id"])
	var before := s.economy.get_balance(P)
	if s.submit("take_route", {"route_id": route_id}).ok:
		stats["fares"] += before - s.economy.get_balance(P)
	_answer()


func _talk_around() -> void:
	var present := s.present_npcs()
	var ids := present.keys()
	ids.sort()
	for npc_id: String in ids:
		var npc := s.content.get_record("npcs", npc_id)
		var tree_id := ChooseDialogueHandler.talk_tree_for(npc, s.dialogue)
		var node_id := "start"
		for step in 4:
			var tree := s.content.get_record("dialogues", tree_id)
			var node: Dictionary = (tree["nodes"] as Array).filter(func(n: Dictionary) -> bool: return n["id"] == node_id)[0]
			if (node["choices"] as Array).is_empty():
				break
			var choice: Dictionary = node["choices"][0]
			if not s.submit("choose_dialogue", {"tree_id": tree_id, "node_id": node_id, "choice_id": choice["id"]}).ok:
				break
			if not choice.has("next"):
				stats["talks"] += 1
				break
			node_id = choice["next"]
		_answer()


## Story entries: take the first acceptable choice (the "polite yes" path), dismiss summaries.
func _answer() -> void:
	var guard := 0
	while s.dialogue.has_pending() and guard < 20:
		guard += 1
		var e := s.dialogue.peek()
		if e["kind"] == "summary":
			s.submit("dismiss_story_entry", {"entry_id": e["entry_id"]})
			continue
		var node: Dictionary = (s.content.get_record("dialogues", e["tree_id"])["nodes"] as Array).filter(
			func(n: Dictionary) -> bool: return n["id"] == e["node_id"])[0]
		var answered := false
		for c: Dictionary in node["choices"]:
			if s.submit("choose_dialogue", {"tree_id": e["tree_id"], "node_id": e["node_id"], "choice_id": c["id"],
					"entry_id": e["entry_id"]}).ok:
				answered = true
				break
		if not answered:
			s.submit("dismiss_story_entry", {"entry_id": e["entry_id"]})


func _track() -> void:
	var n := s.needs.get_values(P)
	stats["max_hunger"] = maxi(stats["max_hunger"], n["hunger"])
	stats["min_energy"] = mini(stats["min_energy"], n["energy"])
	stats["max_stress"] = maxi(stats["max_stress"], n["stress"])
	if n["hunger"] >= 70:
		stats["hungry_hours"] += 1  # per tracked step (~30 min while awake); a rough "hungry for long" signal
	stats["min_balance"] = mini(stats["min_balance"], s.economy.get_balance(P))
	var wages := 0
	var rent := 0
	for e: Dictionary in s.economy.get_ledger(P):
		var reason := str(e["reason"])
		if reason.begins_with("wage") or reason.contains("shift"):
			wages += int(e["amount_minor"])
		elif reason.contains("rent"):
			rent += -int(e["amount_minor"])
	stats["net_wages"] = wages
	stats["rent_paid"] = rent


func _must(r: CommandResult, what: String) -> void:
	if not r.ok:
		stats["errors"].append("%s: %s" % [what, r.error_code])
