class_name UseDoorHandler
extends CommandHandler
## `use_door` {door_id}: walk through a door (into a shop, back out to the street). The door is a
## map interactable of kind "door"; the actor must be on that door's map. Moves the actor to the
## door's target location (and so onto its map); takes no game time.

const ACTION := "use_door"
const ARGUMENTS_SCHEMA := {"type": "object", "fields": {"door_id": {"type": "id", "required": true}}}


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	return "" if ctx.proposal.actor_id == "player" else "E_FORBIDDEN_ACTOR"


## The door record and the map it is on: {door, map_id} or {}.
static func find_door(content: ContentRegistry, door_id: String) -> Dictionary:
	for map in content.get_records("maps"):
		for it: Dictionary in map["interactables"]:
			if it["id"] == door_id and it["kind"] == "door":
				return {"door": it, "map_id": map["id"]}
	return {}


func validate(ctx: CommandContext) -> String:
	var v := SchemaValidator.new()
	var args: Variant = v.validate(ctx.proposal.arguments, ARGUMENTS_SCHEMA, "/arguments")
	if not v.is_ok():
		return "E_INVALID_ARGUMENTS"
	var found := find_door(ctx.get_service("content") as ContentRegistry, args["door_id"])
	if found.is_empty():
		return "E_UNKNOWN_DOOR"
	if (ctx.world.get_component("locations") as LocationSystem).get_map_id(ctx.proposal.actor_id) != found["map_id"]:
		return "E_NOT_HERE"
	return ""


func apply(ctx: CommandContext) -> String:
	var found := find_door(ctx.get_service("content") as ContentRegistry, ctx.proposal.arguments["door_id"])
	return (ctx.world.get_component("locations") as LocationSystem).move_to(ctx, ctx.proposal.actor_id,
		found["door"]["target_location_id"])
