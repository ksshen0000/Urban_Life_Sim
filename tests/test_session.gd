extends "res://tests/framework/test_case.gd"
## SimulationSession wiring: new game, exploration time steps, full world round trip, localization.

const Sessions := preload("res://tests/framework/session_factory.gd")


func test_new_game_starts_at_city_time() -> void:
	var s := Sessions.create()
	assert_eq(GameClock.format_debug(s.world.clock.get_minute()), "D1 08:00")
	var v := s.view_player()
	assert_eq(v["day_index"], 1)
	assert_eq(v["balance_minor"], Sessions.start_money())
	assert_eq(v["currency_minor_digits"], 2)


func test_unknown_city() -> void:
	var r := SimulationSession.create_new(Sessions.content(), RegionPolicyRegistry.with_builtin_implementations(), "XX_NOWHERE")
	assert_eq(r["error_code"], "E_UNKNOWN_CITY")


func test_exploration_commits_in_steps() -> void:
	var s := Sessions.create()
	var start := s.world.clock.get_minute()
	for i in 4:
		assert_eq(s.advance_exploration(1.0), null, "below the 5-minute step")
	assert_eq(s.world.clock.get_minute(), start)
	var r := s.advance_exploration(1.0)
	assert_not_null(r)
	assert_true(r.ok)
	assert_eq(s.world.clock.get_minute(), start + 5)
	s.world.clock.push_pause("menu")
	assert_eq(s.advance_exploration(100.0), null, "paused clock accrues nothing")
	assert_eq(s.world.clock.get_minute(), start + 5)


func test_ids_are_unique_and_actor_tagged() -> void:
	var s := Sessions.create()
	var a := s.submit("advance_time", {"minutes": 1}, "system:clock")
	var b := s.submit("advance_time", {"minutes": 1}, "system:clock")
	assert_ne(a.proposal_id, b.proposal_id)
	assert_true(a.proposal_id.begins_with("system:clock.r0."))


func test_whole_world_round_trip() -> void:
	var s := Sessions.create()
	s.submit("buy_item", {"shop_id": "shop_fast_food", "item_id": "item_simple_meal", "quantity": 2})
	s.submit("use_item", {"item_id": "item_simple_meal"})
	s.submit("sign_lease", {"housing_id": "home_shared_room_01"})
	assert_true(s.submit("perform_activity", {"activity_id": "activity_sleep"}).ok)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.world.to_dict()))
	var fresh := Sessions.create()
	assert_eq(fresh.world.from_dict(saved), "")
	assert_eq(fresh.world.to_dict(), s.world.to_dict())
	assert_eq(fresh.economy.get_balance("player"), Sessions.start_money() - 3600 - 60000)
	assert_eq(fresh.inventory.count("player", "item_simple_meal"), 1)


func test_localizer_uses_content_text() -> void:
	Localizer.install(Sessions.content())
	assert_eq(tr("need.hunger.name"), "饥饿")
	assert_eq(Localizer.text("ui.hud.day", {"day": 3}), "第 3 天")
	TranslationServer.set_locale("en")
	assert_eq(tr("need.hunger.name"), "Hunger")
	assert_eq(tr("npc.chen_yu.name"), "陈雨", "missing English falls back to zh_CN")
	TranslationServer.set_locale("zh_CN")
