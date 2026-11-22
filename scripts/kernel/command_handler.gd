class_name CommandHandler
extends RefCounted
## One action type (e.g. "advance_time", later "work_shift", "pay_rent"). Contract:
##   authorize(ctx) – may this actor do this at all?            read-only, "" or error code
##   validate(ctx)  – preconditions: entities, time, resources.  read-only, "" or error code
##   apply(ctx)     – mutate the world, emit events.             "" or error code
## Returning an error from apply rolls the whole command back, including emitted events.
## CommandProcessor verifies that authorize/validate leave the world untouched.


func get_action() -> String:
	return ""


func authorize(_ctx: CommandContext) -> String:
	return ""


func validate(_ctx: CommandContext) -> String:
	return ""


func apply(_ctx: CommandContext) -> String:
	return "E_NOT_IMPLEMENTED"


## Validates and normalizes ctx.proposal.arguments; returns null (and sets ctx.message) if invalid.
static func parse_args(ctx: CommandContext, schema: Dictionary) -> Variant:
	var v := SchemaValidator.new()
	var args: Variant = v.validate(ctx.proposal.arguments, schema, "/arguments")
	if not v.is_ok():
		ctx.message = "%s %s" % [v.errors[0]["path"], v.errors[0]["message"]]
		return null
	return args
