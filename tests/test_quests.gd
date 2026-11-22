extends "res://tests/framework/test_case.gd"
## T016: the settle-in tutorial tracks real progress, in order, catching up on steps already done.

const Sessions := preload("res://tests/framework/session_factory.gd")
const Q := "quest_settle_in"


func test_steps_advance_with_play() -> void:
	var s := Sessions.create({"story_enabled": true})
	assert_eq(s.quests.current_step(Q)["id"], "rent_room")
	s.submit("sign_lease", {"housing_id": "home_shared_room_01"})
	assert_eq(s.quests.current_step(Q)["id"], "find_job")
	s.submit("book_shift", {"job_id": "job_convenience_clerk", "day": 2, "template_id": "morning"})
	assert_eq(s.quests.current_step(Q)["id"], "eat")
	s.submit("buy_item", {"shop_id": "shop_fast_food", "item_id": "item_simple_meal"})
	s.submit("use_item", {"item_id": "item_simple_meal"})
	assert_eq(s.quests.current_step(Q)["id"], "first_shift")
	s.submit("advance_time", {"minutes": GameClock.minute_from_day_time(2, 9) - s.world.clock.get_minute()}, "system")
	s.submit("work_shift", {"shift_id": "job_convenience_clerk.d2.morning"})
	assert_eq(s.quests.current_step(Q)["id"], "second_shift")
	s.submit("book_shift", {"job_id": "job_restaurant_server", "day": 2, "template_id": "dinner"})
	s.submit("advance_time", {"minutes": GameClock.minute_from_day_time(2, 17) - s.world.clock.get_minute()}, "system")
	s.submit("work_shift", {"shift_id": "job_restaurant_server.d2.dinner"})
	assert_eq(s.quests.current_step(Q)["id"], "acquaintance")
	for day in [3, 4]:
		s.submit("advance_time", {"minutes": GameClock.minute_from_day_time(day, 9) - s.world.clock.get_minute()}, "system")
		s.submit("choose_dialogue", {"tree_id": "dialogue_chen_yu_intro" if day == 3 else "dialogue_chen_yu_chat",
			"node_id": "start", "choice_id": "thanks" if day == 3 else "talk"})
		_answer(s)
	s.submit("choose_dialogue", {"tree_id": "dialogue_chen_yu_chat", "node_id": "start", "choice_id": "talk"})
	assert_true(s.relationships.get_value("npc_chen_yu") >= 8)
	s.submit("advance_time", {"minutes": GameClock.minute_from_day_time(5, 9) - s.world.clock.get_minute()}, "system")
	_answer(s)
	s.submit("choose_dialogue", {"tree_id": "dialogue_chen_yu_chat", "node_id": "start", "choice_id": "talk"})
	assert_eq(s.quests.current_step(Q)["id"], "first_rent")
	s.submit("advance_time", {"minutes": GameClock.minute_from_day_time(7, 1) - s.world.clock.get_minute()}, "system")
	assert_true(s.quests.is_complete(Q))


func _answer(s: SimulationSession) -> void:
	while s.dialogue.has_pending():
		var e := s.dialogue.peek()
		if e["kind"] == "summary":
			s.submit("dismiss_story_entry", {"entry_id": e["entry_id"]})
			continue
		var tree := s.content.get_record("dialogues", e["tree_id"])
		var choices: Array = tree["nodes"].filter(func(n: Dictionary) -> bool: return n["id"] == e["node_id"])[0]["choices"]
		s.submit("choose_dialogue", {"tree_id": e["tree_id"], "node_id": e["node_id"], "choice_id": choices[-1]["id"], "entry_id": e["entry_id"]})


func test_catches_up_on_steps_done_out_of_order() -> void:
	var s := Sessions.create({"story_enabled": true})
	s.submit("buy_item", {"shop_id": "shop_fast_food", "item_id": "item_simple_meal"})
	s.submit("use_item", {"item_id": "item_simple_meal"})
	s.submit("book_shift", {"job_id": "job_convenience_clerk", "day": 2, "template_id": "morning"})
	assert_eq(s.quests.current_step(Q)["id"], "rent_room", "steps stay in order")
	s.submit("sign_lease", {"housing_id": "home_shared_room_01"})
	assert_eq(s.quests.current_step(Q)["id"], "first_shift", "then catch up in one pass")
