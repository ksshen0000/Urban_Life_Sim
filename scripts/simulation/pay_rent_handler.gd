class_name PayRentHandler
extends CommandHandler
## `pay_rent` {}: pay a rent that is due or overdue (normally collected automatically at day start).

const ACTION := "pay_rent"


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	return "" if ctx.proposal.actor_id == "player" else "E_FORBIDDEN_ACTOR"


func validate(ctx: CommandContext) -> String:
	var actor := ctx.proposal.actor_id
	var housing_sys := ctx.world.get_component("housing") as HousingSystem
	if not housing_sys.has_lease(actor):
		return "E_NO_HOME"
	var lease := housing_sys.get_lease(actor)
	if ctx.world.clock.get_day_index() < int(lease["next_due_day"]):
		return "E_NOTHING_DUE"
	var housing := (ctx.get_service("content") as ContentRegistry).get_record("housing", lease["housing_id"])
	var amount := HousingSystem.rent_due(ctx.get_service("region_policy"), housing, actor)
	if not (ctx.world.get_component("economy") as EconomyService).can_afford(actor, amount):
		return "E_INSUFFICIENT_FUNDS"
	return ""


func apply(ctx: CommandContext) -> String:
	return (ctx.world.get_component("housing") as HousingSystem).pay_now(ctx, ctx.proposal.actor_id)
