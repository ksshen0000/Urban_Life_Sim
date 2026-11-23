class_name ApproachNpcHandler
extends CommandHandler
## `approach_npc` {npc_id}: the player walked up to an NPC (the world submits it when the player
## comes within a couple of tiles). Records the minute in the player's stats so in-person story
## beats (`npc_nearby` condition: Chen's introduction, Lao Zhou's gloves) happen face to face
## instead of anywhere on the same map. Takes no time.

const ACTION := "approach_npc"
const ARGUMENTS_SCHEMA := {"type": "object", "fields": {"npc_id": {"type": "id", "required": true}}}
## How long after walking up the NPC still counts as "nearby" for story conditions.
const NEARBY_MINUTES := 10


static func stat_key(npc_id: String) -> String:
	return "approached_at." + npc_id


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	return "" if ctx.proposal.actor_id == "player" else "E_FORBIDDEN_ACTOR"


func validate(ctx: CommandContext) -> String:
	var v := SchemaValidator.new()
	var args: Variant = v.validate(ctx.proposal.arguments, ARGUMENTS_SCHEMA, "/arguments")
	if not v.is_ok():
		return "E_INVALID_ARGUMENTS"
	var content := ctx.get_service("content") as ContentRegistry
	if not content.has_record("npcs", args["npc_id"]):
		return "E_INVALID_ARGUMENTS"
	var loc := NpcScheduleSystem.new(content).location_of(args["npc_id"], ctx.world.clock.get_minute())
	if loc.is_empty() or not (ctx.world.get_component("locations") as LocationSystem).is_on_map_of(ctx.proposal.actor_id, loc):
		return "E_NPC_NOT_HERE"
	return ""


func apply(ctx: CommandContext) -> String:
	var npc_id: String = ctx.proposal.arguments["npc_id"]
	ctx.emit("npc_approached", {"npc_id": npc_id})
	return (ctx.world.get_component("stats") as StatsSystem).set_stat(ctx, ctx.proposal.actor_id,
		stat_key(npc_id), ctx.world.clock.get_minute())
