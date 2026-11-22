extends "res://tests/framework/test_case.gd"
## T014: relationships, in-person dialogue, one-time intros, daily cooldown on small talk.

const Sessions := preload("res://tests/framework/session_factory.gd")
const CHEN := "npc_chen_yu"


func _session_at(day: int, hour: int) -> SimulationSession:
	var s := Sessions.create()
	s.submit("advance_time", {"minutes": GameClock.minute_from_day_time(day, hour) - s.world.clock.get_minute()}, "system")
	return s


func _choose(s: SimulationSession, tree: String, node: String, choice: String) -> CommandResult:
	return s.submit("choose_dialogue", {"tree_id": tree, "node_id": node, "choice_id": choice})


func test_intro_once_then_chat() -> void:
	var s := _session_at(1, 9)
	assert_eq(ChooseDialogueHandler.talk_tree_for(s.content.get_record("npcs", CHEN), s.dialogue), "dialogue_chen_yu_intro")
	assert_true(_choose(s, "dialogue_chen_yu_intro", "start", "thanks").ok)
	assert_eq(s.relationships.get_value(CHEN), 5)
	assert_eq(s.flags.get_flag("story.met_chen"), true)
	assert_eq(_choose(s, "dialogue_chen_yu_intro", "start", "thanks").error_code, "E_DIALOGUE_DONE", "intro only once")
	assert_eq(s.relationships.get_value(CHEN), 5)
	assert_eq(ChooseDialogueHandler.talk_tree_for(s.content.get_record("npcs", CHEN), s.dialogue), "dialogue_chen_yu_chat")


func test_small_talk_cannot_farm_affection() -> void:
	var s := _session_at(1, 9)
	_choose(s, "dialogue_chen_yu_intro", "start", "nod")  # +2
	for i in 5:
		assert_true(_choose(s, "dialogue_chen_yu_chat", "start", "talk").ok)
	assert_eq(s.relationships.get_value(CHEN), 5, "+3 once today, then cooldown")
	assert_true(s.processor.get_event_log().any(func(e: DomainEvent) -> bool: return e.type == "relationship_cooldown"))
	s.submit("advance_time", {"minutes": GameClock.MINUTES_PER_DAY}, "system")  # day 2 09:00
	_choose(s, "dialogue_chen_yu_chat", "start", "talk")
	assert_eq(s.relationships.get_value(CHEN), 8, "a new day allows another +3")


func test_npc_must_be_present() -> void:
	var s := _session_at(1, 20)  # Chen is home by now
	assert_eq(_choose(s, "dialogue_chen_yu_intro", "start", "thanks").error_code, "E_NPC_NOT_HERE")
	var s2 := _session_at(1, 9)
	s2.submit("take_route", {"route_id": "route_12_to_industrial"})
	assert_eq(_choose(s2, "dialogue_chen_yu_intro", "start", "thanks").error_code, "E_NPC_NOT_HERE")


func test_branching_node_then_terminal_effects() -> void:
	var s := _session_at(1, 11)  # landlord at the apartment from 10:00
	assert_true(_choose(s, "dialogue_landlord_intro", "start", "bargain").ok, "branch")
	assert_eq(s.relationships.get_value("npc_landlord_wang"), 0, "branch choices carry no effects")
	assert_true(_choose(s, "dialogue_landlord_intro", "bargain", "fine").ok)
	assert_eq(s.relationships.get_value("npc_landlord_wang"), 1)
	assert_true(s.dialogue.is_completed("dialogue_landlord_intro"))


func test_bad_choices_rejected() -> void:
	var s := _session_at(1, 9)
	assert_eq(_choose(s, "dialogue_chen_yu_intro", "start", "kiss").error_code, "E_INVALID_ARGUMENTS")
	assert_eq(_choose(s, "dialogue_nope", "start", "x").error_code, "E_UNKNOWN_DIALOGUE")
	assert_eq(_choose(s, "dialogue_day3_dinner", "start", "go").error_code, "E_DIALOGUE_DONE",
		"event-only trees need their queued entry")
	assert_eq(s.submit("choose_dialogue", {"tree_id": "dialogue_chen_yu_intro", "node_id": "start", "choice_id": "thanks"},
		"npc_chen_yu").error_code, "E_FORBIDDEN_ACTOR")


func test_relationship_bounds_and_round_trip() -> void:
	var s := _session_at(1, 9)
	_choose(s, "dialogue_chen_yu_intro", "start", "thanks")
	var copy := RelationshipSystem.new(Sessions.content())
	assert_eq(copy.from_dict(JSON.parse_string(JSON.stringify(s.relationships.to_dict()))), "")
	assert_eq(copy.get_value(CHEN), 5)
	var bad := s.relationships.to_dict()
	bad["npcs"][CHEN]["value"] = 150
	assert_eq(copy.from_dict(bad), "E_INVALID_RELATIONSHIP_STATE")
