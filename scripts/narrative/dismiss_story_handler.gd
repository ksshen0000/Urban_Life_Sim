class_name DismissStoryHandler
extends CommandHandler
## `dismiss_story_entry` {entry_id}: acknowledge a queued summary (dialogue entries are answered
## with choose_dialogue instead).

const ACTION := "dismiss_story_entry"
const ARGUMENTS_SCHEMA := {"type": "object", "fields": {"entry_id": {"type": "string", "required": true, "min_length": 1}}}


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	return "" if ctx.proposal.actor_id == "player" else "E_FORBIDDEN_ACTOR"


func validate(ctx: CommandContext) -> String:
	var args: Variant = parse_args(ctx, ARGUMENTS_SCHEMA)
	if args == null:
		return "E_INVALID_ARGUMENTS"
	var entry := (ctx.world.get_component("dialogue") as DialogueSystem).find_entry(args["entry_id"])
	return "" if not entry.is_empty() and entry["kind"] == "summary" else "E_DIALOGUE_DONE"


func apply(ctx: CommandContext) -> String:
	return (ctx.world.get_component("dialogue") as DialogueSystem).finish_entry(ctx, ctx.proposal.arguments["entry_id"])
