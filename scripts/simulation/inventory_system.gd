class_name InventorySystem
extends RefCounted
## Item counts per owner. A WorldState component; writes only inside commands.
## Item existence is checked by the command handlers against content; this class only counts.

const SCHEMA_VERSION := 1
const STATE_SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"owners": {"type": "map", "required": true,
		"values_spec": {"type": "map", "values_spec": {"type": "int", "min": 1}}},
}}

var _stack_limit: int
var _owners: Dictionary = {}  # owner_id -> {item_id: count > 0}


func _init(stack_limit: int = 99) -> void:
	_stack_limit = maxi(stack_limit, 1)


## World setup only.
func open_owner(owner_id: String) -> bool:
	if owner_id.is_empty() or _owners.has(owner_id):
		return false
	_owners[owner_id] = {}
	return true


func has_owner(owner_id: String) -> bool:
	return _owners.has(owner_id)


func count(owner_id: String, item_id: String) -> int:
	return (_owners.get(owner_id, {}) as Dictionary).get(item_id, 0)


## {item_id: count}, only items with count > 0.
func get_items(owner_id: String) -> Dictionary:
	return (_owners.get(owner_id, {}) as Dictionary).duplicate()


func get_stack_limit() -> int:
	return _stack_limit


func can_add(owner_id: String, item_id: String, quantity: int) -> bool:
	return has_owner(owner_id) and quantity > 0 and count(owner_id, item_id) + quantity <= _stack_limit


func add(ctx: CommandContext, owner_id: String, item_id: String, quantity: int) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	if not has_owner(owner_id) or quantity <= 0:
		return "E_INVALID_ARGUMENTS"
	if not can_add(owner_id, item_id, quantity):
		return "E_INVENTORY_FULL"
	_set_count(ctx, owner_id, item_id, count(owner_id, item_id) + quantity, quantity)
	return ""


func remove(ctx: CommandContext, owner_id: String, item_id: String, quantity: int) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	if not has_owner(owner_id) or quantity <= 0:
		return "E_INVALID_ARGUMENTS"
	if count(owner_id, item_id) < quantity:
		return "E_NOT_ENOUGH_ITEMS"
	_set_count(ctx, owner_id, item_id, count(owner_id, item_id) - quantity, -quantity)
	return ""


func _set_count(ctx: CommandContext, owner_id: String, item_id: String, value: int, delta: int) -> void:
	if value > 0:
		_owners[owner_id][item_id] = value
	else:
		(_owners[owner_id] as Dictionary).erase(item_id)
	ctx.emit("inventory_changed", {"owner_id": owner_id, "item_id": item_id, "count": value, "delta": delta})


func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "owners": _owners.duplicate(true)}


func from_dict(data: Dictionary) -> String:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, STATE_SCHEMA)
	if not v.is_ok():
		return "E_INVALID_INVENTORY_STATE"
	for owner: String in d["owners"]:
		for item: String in d["owners"][owner]:
			if int(d["owners"][owner][item]) > _stack_limit:
				return "E_INVALID_INVENTORY_STATE"
	_owners = d["owners"]
	return ""
