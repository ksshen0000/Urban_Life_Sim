class_name SignLeaseHandler
extends CommandHandler
## `sign_lease` {housing_id} (T011): at the housing's location, with no current lease, pay the
## deposit and start the lease. First rent falls due `first_due_after_days` later.

const ACTION := "sign_lease"
const ARGUMENTS_SCHEMA := {"type": "object", "fields": {"housing_id": {"type": "id", "required": true}}}


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	return "" if ctx.proposal.actor_id == "player" else "E_FORBIDDEN_ACTOR"


func validate(ctx: CommandContext) -> String:
	var args: Variant = parse_args(ctx, ARGUMENTS_SCHEMA)
	if args == null:
		return "E_INVALID_ARGUMENTS"
	var content := ctx.get_service("content") as ContentRegistry
	if not content.has_record("housing", args["housing_id"]):
		return "E_UNKNOWN_HOUSING"
	var housing := content.get_record("housing", args["housing_id"])
	var actor := ctx.proposal.actor_id
	if (ctx.world.get_component("housing") as HousingSystem).has_lease(actor):
		return "E_ALREADY_LEASED"
	if not (ctx.world.get_component("locations") as LocationSystem).is_on_map_of(actor, housing["location_id"]):
		return "E_NOT_HERE"
	if not (ctx.world.get_component("economy") as EconomyService).can_afford(actor, housing["deposit_minor"]):
		return "E_INSUFFICIENT_FUNDS"
	return ""


func apply(ctx: CommandContext) -> String:
	var housing_id: String = ctx.proposal.arguments["housing_id"]
	var housing := (ctx.get_service("content") as ContentRegistry).get_record("housing", housing_id)
	var actor := ctx.proposal.actor_id
	if int(housing["deposit_minor"]) > 0:
		var err := (ctx.world.get_component("economy") as EconomyService).try_debit(ctx, actor,
			housing["deposit_minor"], "deposit:" + housing_id)
		if not err.is_empty():
			return err
	return (ctx.world.get_component("housing") as HousingSystem).sign(ctx, actor, housing_id, ctx.world.clock.get_day_index())
