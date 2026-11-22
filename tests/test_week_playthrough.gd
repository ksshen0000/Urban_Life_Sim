extends "res://tests/framework/test_case.gd"
## End-to-end (headless) first week, played only through commands like the UI would, with story on.
## Checks the spec §3.3 stage goal is reachable (pay first rent, 2+ shifts, a first relationship),
## that an overspending route ends in rent trouble without negative money, and that the DoD loop
## (jobs, wages, shopping, rent, needs, NPCs, summary) closes. Not a balance pass (that is T018).

const Sessions := preload("res://tests/framework/session_factory.gd")
const P := SimulationSession.PLAYER_ID

var s: SimulationSession


func _until(day: int, hour: int, minute: int = 0) -> void:
	var target := GameClock.minute_from_day_time(day, hour, minute)
	while s.world.clock.get_minute() < target:
		s.submit("advance_time", {"minutes": mini(30, target - s.world.clock.get_minute())}, "system")
		_answer()


func _answer() -> void:
	var guard := 0
	while s.dialogue.has_pending() and guard < 20:
		guard += 1
		var e := s.dialogue.peek()
		if e["kind"] == "summary":
			s.submit("dismiss_story_entry", {"entry_id": e["entry_id"]})
			continue
		var tree := s.content.get_record("dialogues", e["tree_id"])
		var node: Dictionary = tree["nodes"].filter(func(n: Dictionary) -> bool: return n["id"] == e["node_id"])[0]
		for c: Dictionary in node["choices"]:
			if s.submit("choose_dialogue", {"tree_id": e["tree_id"], "node_id": e["node_id"], "choice_id": c["id"], "entry_id": e["entry_id"]}).ok:
				break


func _eat_if_hungry() -> void:
	if s.needs.get_value(P, "hunger") >= 50:
		if s.inventory.count(P, "item_simple_meal") == 0:
			s.submit("buy_item", {"shop_id": "shop_fast_food", "item_id": "item_simple_meal"})
		s.submit("use_item", {"item_id": "item_simple_meal"})
		_answer()


func _sleep() -> void:
	assert_true(s.submit("perform_activity", {"activity_id": "activity_sleep"}).ok, "sleep")
	_answer()


func _work(job: String, day: int, tpl: String) -> void:
	var id := JobsSystem.shift_id_for(job, day, tpl)
	var r := s.submit("work_shift", {"shift_id": id})
	assert_true(r.ok, "%s: %s" % [id, r.error_code])
	_answer()


func test_reasonable_week_meets_stage_goals() -> void:
	s = Sessions.create({"story_enabled": true})
	s.run_story_rules()
	_answer()
	assert_true(s.submit("sign_lease", {"housing_id": "home_shared_room_01"}).ok)
	assert_true(s.submit("book_shift", {"job_id": "job_convenience_clerk", "day": 2, "template_id": "morning"}).ok)
	_eat_if_hungry()
	_until(1, 22)
	_eat_if_hungry()
	_sleep()                                              # wake day 2 06:00
	for day in range(2, 8):
		_eat_if_hungry()
		if day < 7:
			var job := "job_warehouse_sorter" if day + 1 >= 4 else "job_convenience_clerk"
			var tpl := "day" if job == "job_warehouse_sorter" else "morning"
			s.submit("book_shift", {"job_id": job, "day": day + 1, "template_id": tpl})
		var today := s.jobs.get_shifts(P).filter(func(sh: Dictionary) -> bool: return sh["day"] == day and sh["status"] == "booked")
		for sh: Dictionary in today:
			var job_rec := s.content.get_record("jobs", sh["job_id"])
			var on_industrial: bool = s.locations.map_of_location(job_rec["workplace_location_id"]) == "map_industrial"
			_until(day, maxi(6, GameClock.minute_of_day_of(sh["start_minute"]) / 60 - (1 if on_industrial else 0)))
			if on_industrial:
				assert_true(s.submit("take_route", {"route_id": "route_12_to_industrial"}).ok, "commute out")
			_work(sh["job_id"], day, sh["template_id"])
			if on_industrial:
				assert_true(s.submit("take_route", {"route_id": "route_12_to_old_town"}).ok, "commute back")
			_eat_if_hungry()
		_until(day, 17)
		if not s.npc_schedule.location_of("npc_chen_yu", s.world.clock.get_minute()).is_empty():
			s.submit("choose_dialogue", {"tree_id": ChooseDialogueHandler.talk_tree_for(s.content.get_record("npcs", "npc_chen_yu"), s.dialogue),
				"node_id": "start", "choice_id": "thanks" if not s.dialogue.is_completed("dialogue_chen_yu_intro") else "talk"})
		_answer()
		_eat_if_hungry()
		_until(day, 22)
		_eat_if_hungry()
		if day < 7:
			_sleep()
	_until(7, 21)
	assert_true(s.housing.get_lease(P)["periods_paid"] >= 1, "first rent paid")
	assert_true(s.jobs.count_with_status(P, "completed") >= 2, "2+ shifts")
	assert_true(s.relationships.max_value() >= 10, "a first relationship")
	assert_true(s.events.has_fired("event_week1_summary"))
	assert_true(s.quests.is_complete("quest_settle_in"), "tutorial completed: %s" % str(s.quests.current_step("quest_settle_in").get("id")))
	assert_true(s.economy.get_balance(P) > 0)
	for need: String in s.needs.get_need_ids():
		var v := s.needs.get_value(P, need)
		assert_true(v >= 0 and v <= 100)


func test_overspending_week_ends_in_rent_trouble_not_negative_money() -> void:
	s = Sessions.create({"story_enabled": true})
	s.run_story_rules()
	_answer()
	s.submit("sign_lease", {"housing_id": "home_shared_room_01"})
	for i in 4:  # treats every day, no work at all
		s.submit("buy_item", {"shop_id": "shop_convenience_store", "item_id": "item_simple_meal", "quantity": 5})
	_until(1, 22)
	_sleep()
	_until(7, 21)
	assert_true(s.housing.is_overdue(P), "rent could not be paid")
	assert_true(s.economy.get_balance(P) >= 0)
	assert_true(s.events.has_fired("event_rent_overdue"), "the landlord follows up")
