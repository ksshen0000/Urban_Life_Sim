class_name TakeRouteHandler
extends CommandHandler
## `take_route` {route_id} (T012): from the route's origin map, during service hours, pay the
## fare, ride (awake time passes) and arrive at the destination location (and its map).
## Insufficient funds or no departure: nothing changes.

const ACTION := "take_route"
const ARGUMENTS_SCHEMA := {"type": "object", "fields": {"route_id": {"type": "id", "required": true}}}


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	var locations := ctx.world.get_component("locations") as LocationSystem
	return "" if locations.has_actor(ctx.proposal.actor_id) else "E_FORBIDDEN_ACTOR"


func validate(ctx: CommandContext) -> String:
	var args: Variant = parse_args(ctx, ARGUMENTS_SCHEMA)
	if args == null:
		return "E_INVALID_ARGUMENTS"
	var content := ctx.get_service("content") as ContentRegistry
	if not content.has_record("transit_routes", args["route_id"]):
		return "E_UNKNOWN_ROUTE"
	var route := content.get_record("transit_routes", args["route_id"])
	var actor := ctx.proposal.actor_id
	if not (ctx.world.get_component("locations") as LocationSystem).is_on_map_of(actor, route["from_location_id"]):
		return "E_NOT_HERE"
	var mod := ctx.world.clock.get_minute_of_day()
	if mod < int(route["first_departure_minute_of_day"]) or mod > int(route["last_departure_minute_of_day"]):
		return "E_NO_DEPARTURE"
	if not (ctx.world.get_component("economy") as EconomyService).can_afford(actor, route["fare_minor"]):
		return "E_INSUFFICIENT_FUNDS"
	return ""


func apply(ctx: CommandContext) -> String:
	var route := (ctx.get_service("content") as ContentRegistry).get_record("transit_routes", ctx.proposal.arguments["route_id"])
	var actor := ctx.proposal.actor_id
	if int(route["fare_minor"]) > 0:
		var err := (ctx.world.get_component("economy") as EconomyService).try_debit(ctx, actor,
			route["fare_minor"], "transit:" + route["id"])
		if not err.is_empty():
			return err
	var err2 := TimeFlow.advance(ctx, route["travel_minutes"], TimeFlow.MODE_AWAKE)
	if not err2.is_empty():
		return err2
	err2 = (ctx.world.get_component("locations") as LocationSystem).move_to(ctx, actor, route["to_location_id"])
	if not err2.is_empty():
		return err2
	var stats := ctx.world.get_component("stats") as StatsSystem
	if stats != null:
		stats.increment(ctx, actor, "trips")
	ctx.emit("trip_completed", {"actor_id": actor, "route_id": route["id"], "to_location_id": route["to_location_id"]})
	return ""
