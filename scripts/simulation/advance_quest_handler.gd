class_name AdvanceQuestHandler
extends CommandHandler
## `advance_quest` {quest_id} by "system:quests": completes the current step when its conditions hold.

const ACTION := "advance_quest"
const ACTOR := "system:quests"
const ARGUMENTS_SCHEMA := {"type": "object", "fields": {"quest_id": {"type": "id", "required": true}}}


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	return "" if ctx.proposal.actor_id == ACTOR else "E_FORBIDDEN_ACTOR"


func validate(ctx: CommandContext) -> String:
	var args: Variant = parse_args(ctx, ARGUMENTS_SCHEMA)
	if args == null:
		return "E_INVALID_ARGUMENTS"
	return "" if (ctx.world.get_component("quests") as QuestSystem).can_advance(args["quest_id"], ctx.world) else "E_QUEST_NOT_READY"


func apply(ctx: CommandContext) -> String:
	return (ctx.world.get_component("quests") as QuestSystem).advance(ctx, ctx.proposal.arguments["quest_id"])
