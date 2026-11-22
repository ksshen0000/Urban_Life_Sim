class_name PerformActivityHandler
extends CommandHandler
## `perform_activity` {activity_id, minutes?}: spend `minutes` (default: the activity's
## duration_minutes; must lie in its min..max) in its time mode, with its own need rates if any
## (sleep in "sleeping"; phone, short videos, lying down, the park bench in "resting").
## Day changes inside are settled day by day by TimeFlow. Activities with opening hours must start
## and finish inside one window; paid ones (arcade, billiards) charge by the hour, rounded up.
## Access: `requires_home` activities need an active lease and being on the home's map;
## `location_ids` activities need being on one of those locations' maps.

const ACTION := "perform_activity"
const ARGUMENTS_SCHEMA := {"type": "object", "fields": {
	"activity_id": {"type": "id", "required": true},
	"minutes": {"type": "int", "min": 1, "max": 1440},
}}


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	return "" if ctx.proposal.actor_id == "player" else "E_FORBIDDEN_ACTOR"


func validate(ctx: CommandContext) -> String:
	var v := SchemaValidator.new()
	var args: Variant = v.validate(ctx.proposal.arguments, ARGUMENTS_SCHEMA, "/arguments")
	if not v.is_ok():
		return "E_INVALID_ARGUMENTS"
	var content := ctx.get_service("content") as ContentRegistry
	if not content.has_record("activities", args["activity_id"]):
		return "E_UNKNOWN_ACTIVITY"
	var activity := content.get_record("activities", args["activity_id"])
	if args.has("minutes"):
		var span := minutes_range(activity)
		if int(args["minutes"]) < span.x or int(args["minutes"]) > span.y:
			return "E_INVALID_DURATION"
	var actor := ctx.proposal.actor_id
	var locations := ctx.world.get_component("locations") as LocationSystem
	if activity.get("requires_home", false):
		var home := (ctx.world.get_component("housing") as HousingSystem).home_location_id(actor)
		if home.is_empty():
			return "E_NO_HOME"
		if not locations.is_on_map_of(actor, home):
			return "E_NOT_HERE"
	var allowed: Array = activity.get("location_ids", [])
	if not allowed.is_empty() and not allowed.any(func(l: String) -> bool: return locations.is_on_map_of(actor, l)):
		return "E_NOT_HERE"
	var minutes := int(args.get("minutes", activity["duration_minutes"]))
	var mod := ctx.world.clock.get_minute_of_day()
	if not ActivityRules.is_open(activity, mod):
		return "E_ACTIVITY_CLOSED"
	if minutes > ActivityRules.minutes_left(activity, mod):
		return "E_CLOSES_BEFORE_END"
	var economy := ctx.world.get_component("economy") as EconomyService
	if not economy.can_afford(actor, ActivityRules.cost_minor(activity, minutes)):
		return "E_INSUFFICIENT_FUNDS"
	return ""


## Vector2i(min, max) minutes the player may choose.
static func minutes_range(activity: Dictionary) -> Vector2i:
	var d: int = activity["duration_minutes"]
	return Vector2i(int(activity.get("min_minutes", d)), int(activity.get("max_minutes", d)))


## {need_id: per_hour} overrides for TimeFlow.
static func rate_overrides(activity: Dictionary) -> Dictionary:
	var rates := {}
	for r: Dictionary in activity.get("rates_per_hour", []):
		rates[r["need_id"]] = r["per_hour"]
	return rates


func apply(ctx: CommandContext) -> String:
	var activity_id: String = ctx.proposal.arguments["activity_id"]
	var activity := (ctx.get_service("content") as ContentRegistry).get_record("activities", activity_id)
	var minutes := int(ctx.proposal.arguments.get("minutes", activity["duration_minutes"]))
	var started := ctx.world.clock.get_minute()
	ctx.emit("activity_started", {"activity_id": activity_id, "minutes": minutes})
	var cost := ActivityRules.cost_minor(activity, minutes)
	if cost > 0:
		var paid := (ctx.world.get_component("economy") as EconomyService).try_debit(ctx, ctx.proposal.actor_id,
			cost, "activity:" + activity_id)
		if not paid.is_empty():
			return paid
	var err := TimeFlow.advance(ctx, minutes, activity["time_mode"],
		{"rates": rate_overrides(activity), "activity_id": activity_id})
	if not err.is_empty():
		return err
	ctx.emit("activity_completed", {"activity_id": activity_id, "started_minute": started,
		"ended_minute": ctx.world.clock.get_minute()})
	return ""
