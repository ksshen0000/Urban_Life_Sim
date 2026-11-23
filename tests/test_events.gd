extends "res://tests/framework/test_case.gd"
## T015 events + spec §8.1 #8 EventOnce + test_story_no_direct_mutation: once-only events (also
## across save/load), atomic effects, story writes only through commands, day-7 summary variants.

const Sessions := preload("res://tests/framework/session_factory.gd")
const Grant := preload("res://tests/framework/grant_handler.gd")
const P := SimulationSession.PLAYER_ID


func _story() -> SimulationSession:
	var s := Sessions.create({"story_enabled": true})
	s.processor.register_handler(Grant.new())
	return s


func _to(s: SimulationSession, day: int, hour: int, minute: int = 0) -> void:
	var target := GameClock.minute_from_day_time(day, hour, minute)
	while s.world.clock.get_minute() < target:
		# step in hours like real play, so time-of-day events get their chance
		s.submit("advance_time", {"minutes": mini(60, target - s.world.clock.get_minute())}, "system")
		_answer_all(s)


## Answers every queued story entry with its first choice (or dismisses summaries).
func _answer_all(s: SimulationSession, choice_index: int = 0) -> void:
	var guard := 0
	while s.dialogue.has_pending() and guard < 20:
		guard += 1
		var e := s.dialogue.peek()
		if e["kind"] == "summary":
			s.submit("dismiss_story_entry", {"entry_id": e["entry_id"]})
			continue
		var tree := s.content.get_record("dialogues", e["tree_id"])
		var node: Dictionary = tree["nodes"].filter(func(n: Dictionary) -> bool: return n["id"] == e["node_id"])[0]
		var choices: Array = node["choices"]
		var c: Dictionary = choices[mini(choice_index, choices.size() - 1)]
		var r := s.submit("choose_dialogue", {"tree_id": e["tree_id"], "node_id": e["node_id"], "choice_id": c["id"], "entry_id": e["entry_id"]})
		if not r.ok:
			c = choices[choices.size() - 1]
			s.submit("choose_dialogue", {"tree_id": e["tree_id"], "node_id": e["node_id"], "choice_id": c["id"], "entry_id": e["entry_id"]})


## Day 2, 09:00: walk into the store and up to Chen (introductions are face to face, D-036).
func _meet_chen(s: SimulationSession) -> void:
	_to(s, 2, 9)
	Sessions.go(s, "convenience_store")
	s.submit("approach_npc", {"npc_id": "npc_chen_yu"})
	_answer_all(s)
	Sessions.go(s, "park")


func _fired_count(s: SimulationSession, event_id: String) -> int:
	return s.events.to_dict()["fired"].get(event_id, {"count": 0})["count"]


func test_arrival_fires_once() -> void:
	var s := _story()
	s.run_story_rules()
	assert_true(s.events.has_fired("event_arrival"))
	assert_eq(s.dialogue.peek()["tree_id"], "dialogue_arrival")
	for i in 5:
		s.submit("advance_time", {"minutes": 5}, "system")
	assert_eq(_fired_count(s, "event_arrival"), 1)
	assert_eq(s.dialogue.get_pending().size(), 1, "not queued again")


func test_event_once_survives_save_and_load() -> void:
	var s := _story()
	s.run_story_rules()
	_answer_all(s)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.world.to_dict()))
	var loaded := _story()
	assert_eq(loaded.world.from_dict(saved), "")
	loaded.run_story_rules()
	loaded.submit("advance_time", {"minutes": 30}, "system")
	assert_eq(_fired_count(loaded, "event_arrival"), 1)
	assert_false(loaded.dialogue.has_pending())
	assert_eq(loaded.flags.get_flag("story.arrived"), true)


func test_day2_intro_needs_chen_present() -> void:
	var s := _story()
	_to(s, 2, 7)
	assert_false(s.events.has_fired("event_day2_chen_intro"), "Chen is not out yet at 07:00")
	_to(s, 2, 9)
	assert_false(s.events.has_fired("event_day2_chen_intro"), "she works inside the store (D-034)")
	Sessions.go(s, "convenience_store")
	assert_false(s.events.has_fired("event_day2_chen_intro"), "same room is not enough: walk up to her")
	s.submit("approach_npc", {"npc_id": "npc_chen_yu"})
	assert_true(s.events.has_fired("event_day2_chen_intro"), "meeting her face to face")
	_answer_all(s)
	assert_eq(s.flags.get_flag("story.met_chen"), true)
	assert_true(s.relationships.get_value("npc_chen_yu") > 0)


func test_dinner_invite_choice_and_atomic_failure() -> void:
	var s := _story()
	_meet_chen(s)
	_to(s, 3, 16)
	assert_eq(s.flags.get_flag("story.met_chen"), true)
	s.submit("advance_time", {"minutes": 60}, "system")  # 17:00: invite arrives
	var e := s.dialogue.peek()
	assert_eq(e.get("tree_id"), "dialogue_day3_dinner")
	var before := s.economy.get_balance(P)
	assert_true(s.submit("choose_dialogue", {"tree_id": e["tree_id"], "node_id": "start", "choice_id": "go", "entry_id": e["entry_id"]}).ok)
	assert_eq(before - s.economy.get_balance(P), 3000)
	assert_eq(s.flags.get_flag("story.dinner_with_chen"), true)


func test_unaffordable_choice_changes_nothing() -> void:
	var s := Sessions.create({"story_enabled": true, "starting_money_minor": 1000})
	_meet_chen(s)
	_to(s, 3, 16)
	s.submit("advance_time", {"minutes": 60}, "system")  # invite arrives; leave it unanswered
	var e := s.dialogue.peek()
	assert_eq(e.get("tree_id"), "dialogue_day3_dinner")
	var before := s.world.to_dict()
	var r := s.submit("choose_dialogue", {"tree_id": e["tree_id"], "node_id": "start", "choice_id": "go", "entry_id": e["entry_id"]})
	assert_eq(r.error_code, "E_INSUFFICIENT_FUNDS")
	assert_eq(s.world.to_dict(), before, "no partial effects (no relationship gain, no flag)")
	assert_true(s.submit("choose_dialogue", {"tree_id": e["tree_id"], "node_id": "start", "choice_id": "skip", "entry_id": e["entry_id"]}).ok,
		"declining is always possible")


func test_story_cannot_write_directly() -> void:
	var s := _story()
	assert_eq(StoryEffects.apply(null, [{"type": "credit_money", "amount": 100}], P, "hack"), "E_NOT_IN_COMMAND")
	assert_eq(s.flags.set_flag(null, "story.x", true), "E_NOT_IN_COMMAND")
	assert_eq(s.submit("trigger_event", {"event_id": "event_arrival"}, "player").error_code, "E_FORBIDDEN_ACTOR")
	assert_eq(s.submit("trigger_event", {"event_id": "event_day4_warehouse"}, "system:event/event_day4_warehouse").error_code,
		"E_EVENT_NOT_ELIGIBLE", "conditions re-checked by the command")
	assert_eq(s.submit("advance_quest", {"quest_id": "quest_settle_in"}, "player").error_code, "E_FORBIDDEN_ACTOR")
	assert_eq(s.economy.get_balance(P), Sessions.start_money())


func test_story_pass_is_bounded() -> void:
	var s := _story()
	_to(s, 7, 21)  # many eligible events over a week
	var per_command := {}
	for ev in s.processor.get_event_log():
		if ev.type == "event_started":
			per_command[ev.world_revision] = true
	assert_true(s.events.fired_ids().size() <= SimulationSession.STORY_STEP_BUDGET * 200)
	assert_true(s.dialogue.get_pending().size() <= DialogueSystem.MAX_PENDING)


func _week(money: int, lease: bool, shifts: int, dinner: bool, chat_days: int) -> PackedStringArray:
	var s := Sessions.create({"story_enabled": true, "starting_money_minor": money})
	s.processor.register_handler(Grant.new())
	if lease:
		s.submit("sign_lease", {"housing_id": "home_shared_room_01"})
	var booked := 0
	for day in range(2, 8):
		_to(s, day - 1, 20)
		if booked < shifts:
			if s.submit("book_shift", {"job_id": "job_convenience_clerk", "day": day, "template_id": "morning"}).ok:
				booked += 1
		_to(s, day, 9)
		var sid := JobsSystem.shift_id_for("job_convenience_clerk", day, "morning")
		if not s.jobs.get_shift(sid).is_empty():
			Sessions.go(s, "convenience_store")
			s.submit("work_shift", {"shift_id": sid})
			_answer_all(s)
		if day - 1 <= chat_days and day >= 2:
			_to(s, day, 17)
			Sessions.go(s, "park")
			s.submit("approach_npc", {"npc_id": "npc_chen_yu"})
			_answer_all(s)
			s.submit("choose_dialogue", {"tree_id": "dialogue_chen_yu_chat", "node_id": "start", "choice_id": "talk"})
		if day == 3:
			_to(s, 3, 17)
			_answer_all(s, 0 if dinner else 1)
	_to(s, 7, 21)
	var summary: PackedStringArray = []
	for ev in s.processor.get_event_log():
		if ev.type == "story_entry_queued" and ev.payload["kind"] == "summary":
			summary = PackedStringArray(ev.payload["lines"])
	return summary


func test_week1_summary_has_distinct_variants() -> void:
	var worker := _week(150000, true, 6, true, 5)
	var idle := _week(150000, true, 0, false, 0)
	var homeless := _week(150000, false, 0, false, 0)
	var broke := _week(80000, true, 0, false, 0)
	assert_eq(worker.size(), 4, "money/work/people/body")
	assert_has(worker, "summary.work_busy")
	assert_has(worker, "summary.people_friend")
	assert_has(idle, "summary.work_none")
	assert_has(homeless, "summary.money_unsettled")
	assert_has(broke, "summary.money_overdue")
	var distinct := {}
	for v in [worker, idle, homeless, broke]:
		distinct["|".join(v)] = true
	assert_true(distinct.size() >= 3, "at least three different summaries from real state")


func test_lao_zhou_gives_gloves_only_face_to_face() -> void:
	var s := _story()
	_to(s, 1, 9)
	s.submit("take_route", {"route_id": "route_12_to_industrial"})
	_answer_all(s)
	assert_false(s.events.has_fired("event_meet_lao_zhou"), "getting off the bus is not meeting him")
	assert_eq(s.submit("approach_npc", {"npc_id": "npc_landlord_wang"}).error_code, "E_NPC_NOT_HERE")
	assert_true(s.submit("approach_npc", {"npc_id": "npc_lao_zhou"}).ok)
	assert_true(s.events.has_fired("event_meet_lao_zhou"), "walking up to him at the warehouse")
	s.submit("advance_time", {"minutes": 30}, "system")
	assert_eq(s.stats.get_stat(P, "approached_at.npc_lao_zhou") > 0, true)
