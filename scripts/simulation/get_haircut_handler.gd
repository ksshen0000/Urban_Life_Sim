class_name GetHaircutHandler
extends CommandHandler
## `get_haircut` {barber_id, hair_style, hair}: a paid haircut at a barber (map interactable of
## kind "barber" with price_minor / service_minutes). Needs presence on the barber's map and the
## money; takes the service time and changes the player's hair in their profile (D-035).

const ACTION := "get_haircut"
const ARGUMENTS_SCHEMA := {"type": "object", "fields": {
	"barber_id": {"type": "id", "required": true},
	"hair_style": {"type": "string", "required": true, "values": ProfileSystem.HAIR_STYLES},
	"hair": {"type": "string", "required": true, "pattern": "^#[0-9a-fA-F]{6}$"},
}}


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	return "" if ctx.proposal.actor_id == "player" else "E_FORBIDDEN_ACTOR"


## {barber, map_id} or {}.
static func find_barber(content: ContentRegistry, barber_id: String) -> Dictionary:
	for map in content.get_records("maps"):
		for it: Dictionary in map["interactables"]:
			if it["id"] == barber_id and it["kind"] == "barber":
				return {"barber": it, "map_id": map["id"]}
	return {}


func validate(ctx: CommandContext) -> String:
	var v := SchemaValidator.new()
	var args: Variant = v.validate(ctx.proposal.arguments, ARGUMENTS_SCHEMA, "/arguments")
	if not v.is_ok():
		return "E_INVALID_ARGUMENTS"
	var found := find_barber(ctx.get_service("content") as ContentRegistry, args["barber_id"])
	if found.is_empty():
		return "E_INVALID_ARGUMENTS"
	var actor := ctx.proposal.actor_id
	if (ctx.world.get_component("locations") as LocationSystem).get_map_id(actor) != found["map_id"]:
		return "E_NOT_HERE"
	if not (ctx.world.get_component("economy") as EconomyService).can_afford(actor, int(found["barber"]["price_minor"])):
		return "E_INSUFFICIENT_FUNDS"
	return ""


func apply(ctx: CommandContext) -> String:
	var args := ctx.proposal.arguments
	var actor := ctx.proposal.actor_id
	var barber: Dictionary = find_barber(ctx.get_service("content") as ContentRegistry, args["barber_id"])["barber"]
	var err := (ctx.world.get_component("economy") as EconomyService).try_debit(ctx, actor,
		int(barber["price_minor"]), "haircut:" + str(args["barber_id"]))
	if not err.is_empty():
		return err
	err = TimeFlow.advance(ctx, int(barber.get("service_minutes", 30)), TimeFlow.MODE_RESTING)
	if not err.is_empty():
		return err
	var profiles := ctx.world.get_component("profile") as ProfileSystem
	var profile := profiles.get_profile(actor)
	profile["look"]["hair_style"] = args["hair_style"]
	profile["look"]["hair"] = args["hair"]
	return profiles.set_profile(ctx, actor, profile)
