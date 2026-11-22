class_name SetProfileHandler
extends CommandHandler
## `set_profile` {name, look}: change the player's name and look at the mirror at home.
## Presentation only, but still a command: the profile is part of the saved world.

const ACTION := "set_profile"
const ARGUMENTS_SCHEMA := {"type": "object", "fields": {
	"name": {"type": "string", "required": true},
	"look": {"type": "object", "required": true, "allow_extra": true, "fields": {}},
}}


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	return "" if ctx.proposal.actor_id == "player" else "E_FORBIDDEN_ACTOR"


func validate(ctx: CommandContext) -> String:
	var v := SchemaValidator.new()
	v.validate(ctx.proposal.arguments, ARGUMENTS_SCHEMA, "/arguments")
	if not v.is_ok():
		return "E_INVALID_ARGUMENTS"
	var err := ProfileSystem.validate_profile(ctx.proposal.arguments)
	if not err.is_empty():
		return err
	var actor := ctx.proposal.actor_id
	var home := (ctx.world.get_component("housing") as HousingSystem).home_location_id(actor)
	if home.is_empty():
		return "E_NO_HOME"
	if not (ctx.world.get_component("locations") as LocationSystem).is_on_map_of(actor, home):
		return "E_NOT_HERE"
	return ""


func apply(ctx: CommandContext) -> String:
	return (ctx.world.get_component("profile") as ProfileSystem).set_profile(ctx, ctx.proposal.actor_id,
		{"name": ctx.proposal.arguments["name"], "look": ctx.proposal.arguments["look"]})
