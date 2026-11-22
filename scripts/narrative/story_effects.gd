class_name StoryEffects
extends RefCounted
## The only way story content changes the world (spec §4.3 effect whitelist, D-004c): each effect
## maps to a domain-system call inside the current command, so a failing effect rolls back the
## whole event / dialogue choice. Money and relationship changes go through EconomyService and
## RelationshipSystem like any other command; nothing here can run code or touch other state.


## Read-only pre-check used by validate(): "" or the error the effects would hit.
static func precheck(effects: Array, world: WorldState, actor_id: String) -> String:
	var spend := 0
	for e: Dictionary in effects:
		if e["type"] == "debit_money":
			spend += int(e["amount"])
	if spend > 0 and not (world.get_component("economy") as EconomyService).can_afford(actor_id, spend):
		return "E_INSUFFICIENT_FUNDS"
	return ""


## source: "event:<id>" or "dialogue:<tree>:<choice>"; rate_limited: repeatable small talk.
static func apply(ctx: CommandContext, effects: Array, actor_id: String, source: String, rate_limited: bool = false) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	for e: Dictionary in effects:
		var err := ""
		match str(e["type"]):
			"set_flag":
				err = (ctx.world.get_component("flags") as FlagsSystem).set_flag(ctx, e["key"], e["value"])
			"credit_money":
				err = (ctx.world.get_component("economy") as EconomyService).credit(ctx, actor_id, e["amount"], source)
			"debit_money":
				err = (ctx.world.get_component("economy") as EconomyService).try_debit(ctx, actor_id, e["amount"], source)
			"change_need":
				err = (ctx.world.get_component("needs") as NeedsSystem).change(ctx, actor_id, e["need_id"], e["delta"], source)
			"change_relationship":
				err = (ctx.world.get_component("relationships") as RelationshipSystem).change(ctx, e["npc_id"], e["delta"], rate_limited, source)
			"show_summary":
				err = (ctx.world.get_component("dialogue") as DialogueSystem).enqueue_summary(ctx,
					SummaryBuilder.build(ctx.world, ctx.get_service("content"), actor_id), source)
			_:
				err = "E_UNKNOWN_EFFECT"
		if not err.is_empty():
			return err
	return ""
