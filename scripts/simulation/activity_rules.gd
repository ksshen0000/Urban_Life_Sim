class_name ActivityRules
extends RefCounted
## Pure rules for activities (sleep, pastimes, arcade, billiards, park): opening hours, the
## longest stay before closing, and the price. Shared by the command handler (authority) and the
## UI / world (which only display them). An activity without `hours` is always available.


## True if the activity can be started at `minute_of_day`.
static func is_open(activity: Dictionary, minute_of_day: int) -> bool:
	return window_end(activity, minute_of_day) >= 0


## Minute of day the current opening window ends (1440 = midnight); -1 if closed now.
## Without `hours`: one day from now (no closing time).
static func window_end(activity: Dictionary, minute_of_day: int) -> int:
	var hours: Array = activity.get("hours", [])
	if hours.is_empty():
		return minute_of_day + GameClock.MINUTES_PER_DAY
	for w: Dictionary in hours:
		if minute_of_day >= int(w["start_minute_of_day"]) and minute_of_day < int(w["end_minute_of_day"]):
			return int(w["end_minute_of_day"])
	return -1


## Longest length that ends before closing (0 if closed).
static func minutes_left(activity: Dictionary, minute_of_day: int) -> int:
	var end := window_end(activity, minute_of_day)
	return maxi(end - minute_of_day, 0) if end >= 0 else 0


## Price for `minutes`, rounded up to the minor unit. 0 for free activities.
static func cost_minor(activity: Dictionary, minutes: int) -> int:
	var per_hour: int = activity.get("price_per_hour_minor", 0)
	@warning_ignore("integer_division")
	return (per_hour * minutes + 59) / 60


## "10:00–24:00" / "07:00–10:00, 18:00–21:00"; "" when always open.
static func hours_text(activity: Dictionary) -> String:
	var parts: PackedStringArray = []
	for w: Dictionary in activity.get("hours", []):
		parts.append("%s–%s" % [_hhmm(int(w["start_minute_of_day"])), _hhmm(int(w["end_minute_of_day"]))])
	return ", ".join(parts)


@warning_ignore("integer_division")
static func _hhmm(m: int) -> String:
	return "%02d:%02d" % [m / 60, m % 60]
