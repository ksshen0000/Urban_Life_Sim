class_name BuyItemHandler
extends CommandHandler
## `buy_item` {shop_id, item_id, quantity=1}: pay the shop's listed price, receive the items.
## Fails without side effects on unknown shop/item, insufficient funds or a full stack.
## The buyer must be on the shop's map (D-020).

const ACTION := "buy_item"
const ARGUMENTS_SCHEMA := {"type": "object", "fields": {
	"shop_id": {"type": "id", "required": true},
	"item_id": {"type": "id", "required": true},
	"quantity": {"type": "int", "min": 1, "max": 20},
}}


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	var economy := ctx.world.get_component("economy") as EconomyService
	var inventory := ctx.world.get_component("inventory") as InventorySystem
	var actor := ctx.proposal.actor_id
	return "" if economy.has_account(actor) and inventory.has_owner(actor) else "E_FORBIDDEN_ACTOR"


func validate(ctx: CommandContext) -> String:
	var order := _order(ctx)
	if order.has("error"):
		return order["error"]
	var economy := ctx.world.get_component("economy") as EconomyService
	var inventory := ctx.world.get_component("inventory") as InventorySystem
	var shop := (ctx.get_service("content") as ContentRegistry).get_record("shops", order["shop_id"])
	if not (ctx.world.get_component("locations") as LocationSystem).is_on_map_of(ctx.proposal.actor_id, shop["location_id"]):
		return "E_NOT_HERE"
	if not inventory.can_add(ctx.proposal.actor_id, order["item_id"], order["quantity"]):
		return "E_INVENTORY_FULL"
	if not economy.can_afford(ctx.proposal.actor_id, order["total_minor"]):
		return "E_INSUFFICIENT_FUNDS"
	return ""


func apply(ctx: CommandContext) -> String:
	var order := _order(ctx)
	var actor := ctx.proposal.actor_id
	var economy := ctx.world.get_component("economy") as EconomyService
	var inventory := ctx.world.get_component("inventory") as InventorySystem
	var err := economy.try_debit(ctx, actor, order["total_minor"],
		"purchase:%s:%s" % [order["shop_id"], order["item_id"]])
	if err.is_empty():
		err = inventory.add(ctx, actor, order["item_id"], order["quantity"])
	if err.is_empty():
		ctx.emit("item_purchased", {"shop_id": order["shop_id"], "item_id": order["item_id"],
			"quantity": order["quantity"], "unit_price_minor": order["unit_price_minor"],
			"total_minor": order["total_minor"]})
	return err


## Resolves the order against content: {shop_id, item_id, quantity, unit_price_minor, total_minor}
## or {error}.
static func _order(ctx: CommandContext) -> Dictionary:
	var v := SchemaValidator.new()
	var args: Variant = v.validate(ctx.proposal.arguments, ARGUMENTS_SCHEMA, "/arguments")
	if not v.is_ok():
		ctx.message = "%s %s" % [v.errors[0]["path"], v.errors[0]["message"]]
		return {"error": "E_INVALID_ARGUMENTS"}
	var content := ctx.get_service("content") as ContentRegistry
	if not content.has_record("shops", args["shop_id"]):
		return {"error": "E_UNKNOWN_SHOP"}
	var quantity: int = args.get("quantity", 1)
	for entry: Dictionary in content.get_record("shops", args["shop_id"])["stock"]:
		if entry["item_id"] == args["item_id"]:
			var unit: int = entry["price_minor"]
			return {"shop_id": args["shop_id"], "item_id": args["item_id"], "quantity": quantity,
				"unit_price_minor": unit, "total_minor": unit * quantity}
	return {"error": "E_ITEM_NOT_SOLD"}
