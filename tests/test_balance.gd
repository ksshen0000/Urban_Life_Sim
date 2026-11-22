extends "res://tests/framework/test_case.gd"
## T018 acceptance on the shipped numbers, played by the scripted bot (tests/framework/week_bot.gd,
## strategies in balance_strategies.gd; the full table: tools/balance_report.gd):
## a reasonable route pays the first rent, overspending runs into rent trouble, doing nothing is not
## enough, and no route is a dead end (broke or late players can still recover). Money never < 0.

const Sessions := preload("res://tests/framework/session_factory.gd")
const WeekBot := preload("res://tests/framework/week_bot.gd")
const Strategies := preload("res://tests/framework/balance_strategies.gd")


func _play(strategy: Dictionary, end_day: int = 8) -> Dictionary:
	var bot := WeekBot.new(WeekBot.make_session(Sessions.content(), strategy), strategy)
	var r := bot.run(end_day)
	assert_eq(r["errors"], PackedStringArray(), "%s: bot commands all accepted" % strategy["name"])
	assert_true(r["min_balance"] >= 0, "%s: never negative" % strategy["name"])
	return r


func test_reasonable_route_pays_rent_and_meets_stage_goals() -> void:
	var r := _play(Strategies.reasonable())
	assert_eq(r["periods_paid"], 1, "first rent paid")
	assert_false(r["overdue"])
	assert_true(r["shifts_worked"] >= 2)
	assert_true(r["relationship_max"] >= 10, "a first relationship")
	assert_true(r["balance"] >= 30000, "comfortable margin (¥%.2f)" % (r["balance"] / 100.0))


func test_minimum_route_pays_rent_tightly() -> void:
	var r := _play(Strategies.two_shifts())
	assert_eq(r["periods_paid"], 1)
	assert_true(r["balance"] < 20000, "two short shifts leave little slack (¥%.2f)" % (r["balance"] / 100.0))


func test_overspending_creates_economic_pressure() -> void:
	var r := _play(Strategies.overspender())
	assert_true(r["overdue"], "rent overdue")
	assert_true(r["events"].has("event_rent_overdue"), "landlord follows up")


func test_doing_nothing_is_not_enough() -> void:
	var r := _play(Strategies.idle())
	assert_true(r["overdue"], "the first rent needs at least one shift")


func test_no_dead_ends() -> void:
	# Overdue after an idle week: one warehouse shift on day 8 settles the rent at the next day start.
	var idle := Strategies.idle()
	var bot := WeekBot.new(WeekBot.make_session(Sessions.content(), idle), idle)
	bot.run(8)
	idle["shifts"] = {8: [[Strategies.SORTER, "day"]]}
	var r := bot.continue_to(9)
	assert_false(r["overdue"], "recovered from overdue rent by working")
	assert_eq(r["periods_paid"], 1)
	# Starting late or with no spare cash still makes the first rent.
	for strategy: Dictionary in [Strategies.late_starter(), Strategies.broke_start()]:
		var rr := _play(strategy)
		assert_eq(rr["periods_paid"], 1, strategy["name"])


func test_hard_work_shows_in_needs() -> void:
	# Not a fail state (the game has none), but the trade-off must be visible.
	var r := _play(Strategies.hustler())
	assert_true(r["max_stress"] >= 60, "double shifts build stress (%d)" % r["max_stress"])
	assert_true(r["min_energy"] <= 20, "and drain energy (%d)" % r["min_energy"])
	assert_true(r["balance"] > _play(Strategies.reasonable())["balance"], "but pay more")
