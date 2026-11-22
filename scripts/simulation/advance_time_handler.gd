class_name AdvanceTimeHandler
extends CommandHandler
## `advance_time` {minutes}: awake time passing (exploration ticks, waiting). Goes through
## TimeFlow, so needs and day-start rules react exactly as for sleep or work.
## NPCs may not move world time.

const ACTION := "advance_time"
const ARGUMENTS_SCHEMA := {"type": "object", "fields": {
	"minutes": {"type": "int", "required": true, "min": 1, "max": GameClock.MAX_ADVANCE_MINUTES},
}}


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	var actor := ctx.proposal.actor_id
	if actor == "player" or actor == "system" or actor.begins_with("system:"):
		return ""
	return "E_FORBIDDEN_ACTOR"


func validate(ctx: CommandContext) -> String:
	var v := SchemaValidator.new()
	v.validate(ctx.proposal.arguments, ARGUMENTS_SCHEMA, "/arguments")
	if not v.is_ok():
		ctx.message = "%s %s" % [v.errors[0]["path"], v.errors[0]["message"]]
		return "E_INVALID_ARGUMENTS"
	return ""


func apply(ctx: CommandContext) -> String:
	var v := SchemaValidator.new()
	var args: Dictionary = v.validate(ctx.proposal.arguments, ARGUMENTS_SCHEMA)
	return TimeFlow.advance(ctx, args["minutes"], TimeFlow.MODE_AWAKE)
