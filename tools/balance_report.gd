extends SceneTree
## T018 balance report: plays the first week under several strategies (tests/framework/week_bot.gd)
## and prints one row per strategy. Usage:
##   godot --headless --path . -s res://tools/balance_report.gd [-- --days=8]
## Money in yuan. "rent" = periods paid by the start of the last day; "overdue" = rent unpaid now.

const WeekBot := preload("res://tests/framework/week_bot.gd")
const Strategies := preload("res://tests/framework/balance_strategies.gd")


func _initialize() -> void:
	var end_day := 8
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			end_day = int(arg.trim_prefix("--days=")) + 1
	var content := ContentRegistry.new()
	if not content.load_root("res://content"):
		printerr("\n".join(content.get_error_strings()))
		quit(1)
		return
	print("strategy            | end day | cash ¥  | min ¥  | rent paid | overdue | shifts | wages ¥ | food ¥ | extras ¥ | fares ¥ | max hunger | min energy | max stress | hungry steps | best rel | quests")
	for strategy: Dictionary in Strategies.all():
		var s: SimulationSession = WeekBot.make_session(content, strategy)
		var bot := WeekBot.new(s, strategy)
		var r: Dictionary = bot.run(end_day)
		print("%-19s | %7d | %7.2f | %6.2f | %9d | %7s | %6d | %7.2f | %6.2f | %8.2f | %7.2f | %10d | %10d | %10d | %12d | %8d | %d" % [
			r["name"], r["day"], r["balance"] / 100.0, r["min_balance"] / 100.0, r["periods_paid"], str(r["overdue"]),
			r["shifts_worked"], r["net_wages"] / 100.0, r["food_spent"] / 100.0, r["extras_spent"] / 100.0, r["fares"] / 100.0,
			r["max_hunger"], r["min_energy"], r["max_stress"], r["hungry_hours"], r["relationship_max"], r["quests_done"]])
		if not (r["errors"] as PackedStringArray).is_empty():
			print("    errors: ", ", ".join(r["errors"]))
	quit(0)
