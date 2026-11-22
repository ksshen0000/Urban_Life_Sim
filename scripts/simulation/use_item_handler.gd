class_name UseItemHandler
extends CommandHandler
## `use_item` {item_id}: consume one item, apply its need effects, then let its use time pass
## (eating a meal takes 20 minutes, during which needs keep changing).

const ACTION := "use_item"
const ARGUMENTS_SCHEMA := {"type": "object", "fields": {"item_id": {"type": "id", "required": true}}}


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	var needs := ctx.world.get_component("needs") as NeedsSystem
	var inventory := ctx.world.get_component("inventory") as InventorySystem
	var actor := ctx.proposal.actor_id
	return "" if needs.has_owner(actor) and inventory.has_owner(actor) else "E_FORBIDDEN_ACTOR"


func validate(ctx: CommandContext) -> String:
	var v := SchemaValidator.new()
	var args: Variant = v.validate(ctx.proposal.arguments, ARGUMENTS_SCHEMA, "/arguments")
	if not v.is_ok():
		return "E_INVALID_ARGUMENTS"
	if not (ctx.get_service("content") as ContentRegistry).has_record("items", args["item_id"]):
		return "E_UNKNOWN_ITEM"
	var inventory := ctx.world.get_component("inventory") as InventorySystem
	if inventory.count(ctx.proposal.actor_id, args["item_id"]) < 1:
		return "E_NOT_ENOUGH_ITEMS"
	return ""


func apply(ctx: CommandContext) -> String:
	var actor := ctx.proposal.actor_id
	var item_id: String = ctx.proposal.arguments["item_id"]
	var item := (ctx.get_service("content") as ContentRegistry).get_record("items", item_id)
	var inventory := ctx.world.get_component("inventory") as InventorySystem
	var needs := ctx.world.get_component("needs") as NeedsSystem
	var err := inventory.remove(ctx, actor, item_id, 1)
	if not err.is_empty():
		return err
	ctx.emit("item_used", {"owner_id": actor, "item_id": item_id})
	var stats := ctx.world.get_component("stats") as StatsSystem
	if stats != null:
		stats.increment(ctx, actor, "food_eaten" if item["category"] == "food" else "drinks")
	for effect: Dictionary in item["use_effects"]:
		err = needs.change(ctx, actor, effect["need_id"], effect["delta"], "item:" + item_id)
		if not err.is_empty():
			return err
	if int(item["use_minutes"]) > 0:
		return TimeFlow.advance(ctx, item["use_minutes"], TimeFlow.MODE_AWAKE)
	return ""
