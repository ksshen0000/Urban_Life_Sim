extends "res://tests/framework/test_case.gd"
## T015 StoryValidator: unknown effects/conditions, invalid entities and over-reaching changes are
## rejected — for loaded content and for story records coming from elsewhere (fixtures here,
## model output later).

const Sessions := preload("res://tests/framework/session_factory.gd")
const ContentFixture := preload("res://tests/framework/content_fixture.gd")


func _event(conditions: Array, effects: Array, extra: Dictionary = {}) -> Dictionary:
	var e := {"id": "event_fixture", "city_id": "CN_LINCHUAN", "priority": 1, "once": true,
		"conditions": conditions, "effects": effects}
	e.merge(extra, true)
	return e


func _codes(errors: Array) -> Array:
	return errors.map(func(e: Dictionary) -> String: return e["code"])


func test_shipped_story_content_is_valid() -> void:
	assert_eq(StoryValidator.validate_content(Sessions.content()), [])


func test_unknown_effect_and_condition() -> void:
	var errors := StoryValidator.validate_event(_event([{"type": "moon_is_full"}], [{"type": "run_script", "code": "OS.execute()"}]),
		Sessions.content())
	assert_has(_codes(errors), "E_STORY_UNKNOWN_CONDITION")
	assert_has(_codes(errors), "E_STORY_UNKNOWN_EFFECT")


func test_invalid_entities() -> void:
	var errors := StoryValidator.validate_event(_event(
		[{"type": "relationship_at_least", "npc_id": "npc_ghost", "value": 5}],
		[{"type": "change_need", "need_id": "thirst", "delta": 5}]), Sessions.content())
	assert_eq(_codes(errors), ["E_STORY_UNKNOWN_REF", "E_STORY_UNKNOWN_REF"])
	var d := StoryValidator.validate_event(_event([], [], {"dialogue_tree_id": "dialogue_ghost"}), Sessions.content())
	assert_has(_codes(d), "E_STORY_UNKNOWN_REF")


func test_overreaching_changes() -> void:
	var errors := StoryValidator.validate_event(_event([], [
		{"type": "credit_money", "amount": 1000000},
		{"type": "change_relationship", "npc_id": "npc_chen_yu", "delta": 80},
		{"type": "change_need", "need_id": "stress", "delta": -100},
		{"type": "set_flag", "key": "housing_contract_signed", "value": true}]), Sessions.content())
	assert_eq(_codes(errors), ["E_STORY_AUTHORITY", "E_STORY_AUTHORITY", "E_STORY_AUTHORITY", "E_STORY_AUTHORITY"])


func test_missing_and_unexpected_fields() -> void:
	var errors := StoryValidator.validate_event(_event(
		[{"type": "need_above", "value": 50}, {"type": "day_at_least", "value": 2, "npc_id": "npc_chen_yu"}],
		[{"type": "debit_money"}]), Sessions.content())
	assert_eq(_codes(errors), ["E_STORY_MISSING_FIELD", "E_STORY_UNEXPECTED_FIELD", "E_STORY_MISSING_FIELD"])


func test_dialogue_rules() -> void:
	var tree := {"id": "dialogue_fixture", "channel": "in_person", "repeatable": true, "nodes": [
		{"id": "start", "text_key": "dlg.chen_chat.start", "choices": [
			{"id": "a", "text_key": "dlg.chen_chat.talk", "effects": [{"type": "change_relationship", "npc_id": "npc_chen_yu", "delta": 3}], "next": "end"},
			{"id": "b", "text_key": "dlg.chen_chat.bye", "effects": [{"type": "show_summary"}]},
			{"id": "c", "text_key": "dlg.chen_chat.bye", "effects": [], "next": "nowhere"}]},
		{"id": "end", "text_key": "dlg.chen_chat.start", "choices": [{"id": "x", "text_key": "dlg.chen_chat.bye", "effects": []}]}]}
	var codes := _codes(StoryValidator.validate_dialogue(tree, Sessions.content()))
	assert_has(codes, "E_STORY_MISSING_FIELD", "in_person needs a speaker")
	assert_has(codes, "E_STORY_EFFECT_ON_BRANCH")
	assert_has(codes, "E_STORY_FORBIDDEN_EFFECT")
	assert_has(codes, "E_STORY_UNKNOWN_REF")


func test_repeating_events_not_allowed_yet() -> void:
	assert_has(_codes(StoryValidator.validate_event(_event([], [], {"once": false}), Sessions.content())), "E_STORY_REPEATING_EVENT")


func test_registry_rejects_invalid_story_content() -> void:
	var fx := ContentFixture.new()
	fx.load_real()
	var events: Array = fx.data("regions/cn/cities/linchuan/events.json")["records"]
	events[0]["effects"] = [{"type": "credit_money", "amount": 99999999}]
	var reg := ContentRegistry.new()
	assert_false(reg.load_root(fx.write()))
	var hit := reg.get_errors().any(func(e: Dictionary) -> bool:
		return e["code"] == "E_STORY_AUTHORITY" and str(e["file"]).ends_with("events.json") and str(e["path"]).ends_with("/effects/0/amount"))
	assert_true(hit, "\n".join(reg.get_error_strings()))
	fx.cleanup()
