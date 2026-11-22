extends "res://tests/framework/test_case.gd"
## T003 / spec §8.1 #1 ClockRollOver.


func _types(events: Array) -> Array:
	return events.map(func(e: Dictionary) -> String: return e["type"])


func _days(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == "day_changed") \
		.map(func(e: Dictionary) -> int: return e["payload"]["day_index"])


func test_start_minute_from_city_config() -> void:
	assert_eq(GameClock.minute_from_day_time(1, 8), 480)
	var clock := GameClock.new(GameClock.minute_from_day_time(1, 8))
	assert_eq(clock.get_day_index(), 1)
	assert_eq(clock.get_hour(), 8)
	assert_eq(GameClock.format_debug(clock.get_minute()), "D1 08:00")


func test_2350_plus_30_is_next_day_0020() -> void:
	var clock := GameClock.new(GameClock.minute_from_day_time(1, 23, 50))
	var r := clock.advance_minutes(30)
	assert_true(r["ok"])
	assert_eq(GameClock.format_debug(clock.get_minute()), "D2 00:20")
	assert_eq(_types(r["events"]), ["time_advanced", "day_changed", "time_advanced"])
	assert_eq(r["events"][0]["payload"], {"old_minute": 1430, "new_minute": 1440})
	assert_eq(r["events"][1]["payload"], {"day_index": 2})
	assert_eq(r["events"][1]["game_minute"], 1440)
	assert_eq(r["events"][2]["payload"], {"old_minute": 1440, "new_minute": 1460})


func test_multi_day_advance_emits_every_day_in_order() -> void:
	var clock := GameClock.new(GameClock.minute_from_day_time(1, 8))
	var r := clock.advance_minutes(2 * GameClock.MINUTES_PER_DAY + 60)
	assert_eq(_days(r["events"]), [2, 3], "no day skipped")
	assert_eq(GameClock.format_debug(clock.get_minute()), "D3 09:00")
	var r2 := clock.advance_minutes(5 * GameClock.MINUTES_PER_DAY)
	assert_eq(_days(r2["events"]), [4, 5, 6, 7, 8])


func test_time_segments_are_contiguous() -> void:
	var clock := GameClock.new(100)
	var r := clock.advance_minutes(4000)
	var cursor := 100
	for e: Dictionary in r["events"]:
		if e["type"] == "time_advanced":
			assert_eq(e["payload"]["old_minute"], cursor, "segment starts where previous ended")
			cursor = e["payload"]["new_minute"]
	assert_eq(cursor, 4100)


func test_landing_exactly_on_midnight() -> void:
	var clock := GameClock.new(GameClock.minute_from_day_time(1, 22))
	var r := clock.advance_minutes(120)
	assert_eq(_types(r["events"]), ["time_advanced", "day_changed"])
	assert_eq(clock.get_day_index(), 2)
	assert_eq(clock.get_minute_of_day(), 0)
	var r2 := clock.advance_minutes(10)
	assert_eq(_types(r2["events"]), ["time_advanced"], "starting at midnight does not re-fire day_changed")


func test_zero_minutes_is_a_no_op() -> void:
	var clock := GameClock.new(500)
	var r := clock.advance_minutes(0)
	assert_true(r["ok"])
	assert_eq(r["events"].size(), 0)
	assert_eq(clock.get_minute(), 500)


func test_invalid_advances_change_nothing() -> void:
	var clock := GameClock.new(500)
	assert_eq(clock.advance_minutes(-1)["error_code"], "E_NEGATIVE_MINUTES")
	assert_eq(clock.advance_minutes(GameClock.MAX_ADVANCE_MINUTES + 1)["error_code"], "E_ADVANCE_TOO_LARGE")
	assert_eq(clock.get_minute(), 500)


func test_pause_reasons_stack() -> void:
	var clock := GameClock.new()
	assert_false(clock.is_paused())
	clock.push_pause("dialogue")
	clock.push_pause("menu")
	clock.pop_pause("dialogue")
	assert_true(clock.is_paused(), "menu still holds the pause")
	assert_eq(clock.get_pause_reasons(), PackedStringArray(["menu"]))
	assert_eq(clock.accumulate_real_time(10.0), 0, "no time accrues while paused")
	clock.pop_pause("menu")
	assert_false(clock.is_paused())


func test_real_time_accumulates_whole_minutes() -> void:
	var clock := GameClock.new()
	assert_true(clock.set_minutes_per_real_second(1.0))
	assert_eq(clock.accumulate_real_time(0.4), 0)
	assert_eq(clock.accumulate_real_time(0.4), 0)
	assert_eq(clock.accumulate_real_time(0.4), 1, "fractions carry over")
	assert_eq(clock.get_minute(), 0, "accumulating never advances the clock itself")
	assert_false(clock.set_minutes_per_real_second(0.0))
	assert_false(clock.set_minutes_per_real_second(-2.0))
	assert_eq(clock.get_minutes_per_real_second(), 1.0)


func test_round_trip_and_rejects_bad_state() -> void:
	var clock := GameClock.new(12345)
	var restored := GameClock.new()
	assert_eq(restored.from_dict(clock.to_dict()), "")
	assert_eq(restored.get_minute(), 12345)
	assert_eq(restored.from_dict({"schema_version": 1, "minute": 777.0}), "", "JSON floats accepted")
	assert_eq(restored.get_minute(), 777)
	assert_eq(restored.from_dict({"schema_version": 1, "minute": -5}), "E_INVALID_CLOCK_STATE")
	assert_eq(restored.from_dict({"minute": 5}), "E_INVALID_CLOCK_STATE")
	assert_eq(restored.get_minute(), 777, "failed restore leaves state untouched")


func test_date_key() -> void:
	assert_eq(GameClock.date_key_of(7), "day_7")
