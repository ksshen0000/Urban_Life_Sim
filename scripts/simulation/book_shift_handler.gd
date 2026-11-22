class_name BookShiftHandler
extends CommandHandler
## `book_shift` {job_id, day, template_id}: sign up for one shift of a job (T009), today or
## tomorrow, if the job is hiring that day, the slot has not started, it does not overlap the
## actor's other shifts, and the region's daily work-time rule allows it.

const ACTION := "book_shift"
const ARGUMENTS_SCHEMA := {"type": "object", "fields": {
	"job_id": {"type": "id", "required": true},
	"day": {"type": "int", "required": true, "min": 1},
	"template_id": {"type": "id", "required": true},
}}


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	return "" if ctx.proposal.actor_id == "player" else "E_FORBIDDEN_ACTOR"


func validate(ctx: CommandContext) -> String:
	var args: Variant = parse_args(ctx, ARGUMENTS_SCHEMA)
	if args == null:
		return "E_INVALID_ARGUMENTS"
	var jobs := ctx.world.get_component("jobs") as JobsSystem
	return jobs.check_booking(ctx.proposal.actor_id, args["job_id"], args["day"], args["template_id"],
		ctx.world.clock.get_minute(), ctx.get_service("region_policy"))


func apply(ctx: CommandContext) -> String:
	var args: Dictionary = parse_args(ctx, ARGUMENTS_SCHEMA)
	return (ctx.world.get_component("jobs") as JobsSystem).book(ctx, ctx.proposal.actor_id,
		args["job_id"], args["day"], args["template_id"])
