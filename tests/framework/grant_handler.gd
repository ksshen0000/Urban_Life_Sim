extends CommandHandler
## Test-only command: `test_grant` {amount}: credits the actor. Lets tests set up money states
## through the real command path instead of poking component internals.


func get_action() -> String:
	return "test_grant"


func apply(ctx: CommandContext) -> String:
	return (ctx.world.get_component("economy") as EconomyService).credit(ctx, ctx.proposal.actor_id,
		int(ctx.proposal.arguments["amount"]), "test_grant")
