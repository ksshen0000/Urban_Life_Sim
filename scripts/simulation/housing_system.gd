class_name HousingSystem
extends RefCounted
## Leases and rent (T011). Signing pays the deposit; rent is collected automatically at the start
## of each due day (via the TimeFlow day hook, so multi-day fast-forwards settle every day in
## order). If the wallet cannot cover it, the lease becomes overdue — never a negative balance
## (spec §3.6) — and collection is retried every following day start, or paid manually.
## A period is charged at most once: `next_due_day` only moves forward after a successful payment.

const SCHEMA_VERSION := 1
const STATE_SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"leases": {"type": "map", "required": true, "values_spec": {"type": "object", "fields": {
		"housing_id": {"type": "id", "required": true},
		"start_day": {"type": "int", "required": true, "min": 1},
		"next_due_day": {"type": "int", "required": true, "min": 1},
		"overdue_since_day": {"type": "int", "required": true, "min": -1},
		"periods_paid": {"type": "int", "required": true, "min": 0},
		"deposit_minor": {"type": "int", "required": true, "min": 0},
	}}},
}}

var _content: ContentRegistry
var _leases: Dictionary = {}  # actor_id -> lease


func _init(content: ContentRegistry = null) -> void:
	_content = content


func has_lease(actor_id: String) -> bool:
	return _leases.has(actor_id)


func get_lease(actor_id: String) -> Dictionary:
	return (_leases.get(actor_id, {}) as Dictionary).duplicate()


func home_location_id(actor_id: String) -> String:
	if not has_lease(actor_id):
		return ""
	return _content.get_record("housing", _leases[actor_id]["housing_id"])["location_id"]


func is_overdue(actor_id: String) -> bool:
	return has_lease(actor_id) and int(_leases[actor_id]["overdue_since_day"]) >= 0


static func rent_due(policy: RegionPolicy, housing: Dictionary, actor_id: String) -> int:
	return policy.calculate_recurring_cost("rent", housing["rent_minor"], {"housing_id": housing["id"], "actor_id": actor_id})


func sign(ctx: CommandContext, actor_id: String, housing_id: String, day: int) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	var housing := _content.get_record("housing", housing_id)
	_leases[actor_id] = {"housing_id": housing_id, "start_day": day,
		"next_due_day": day + int(housing["first_due_after_days"]), "overdue_since_day": -1,
		"periods_paid": 0, "deposit_minor": housing["deposit_minor"]}
	ctx.emit("lease_signed", {"actor_id": actor_id, "housing_id": housing_id,
		"next_due_day": _leases[actor_id]["next_due_day"], "deposit_minor": housing["deposit_minor"]})
	return ""


## Manual payment of an overdue (or due-today) rent. "" or error code.
func pay_now(ctx: CommandContext, actor_id: String) -> String:
	if not has_lease(actor_id):
		return "E_NO_HOME"
	if ctx.world.clock.get_day_index() < int(_leases[actor_id]["next_due_day"]):
		return "E_NOTHING_DUE"
	return _collect(ctx, actor_id, ctx.world.clock.get_day_index())


## TimeFlow hook.
func on_day_started(ctx: CommandContext, day: int) -> void:
	var actors := PackedStringArray(_leases.keys())
	actors.sort()
	for actor in actors:
		var lease: Dictionary = _leases[actor]
		if day == int(lease["next_due_day"]) - 1:
			var housing := _content.get_record("housing", lease["housing_id"])
			ctx.emit("rent_reminder", {"actor_id": actor, "housing_id": lease["housing_id"],
				"due_day": lease["next_due_day"], "amount_minor": rent_due(_policy(ctx), housing, actor)})
		var guard := 0
		while day >= int(_leases[actor]["next_due_day"]) and guard < 8:
			guard += 1
			if not _collect(ctx, actor, day).is_empty():
				break


func _collect(ctx: CommandContext, actor_id: String, day: int) -> String:
	var lease: Dictionary = _leases[actor_id]
	var housing := _content.get_record("housing", lease["housing_id"])
	var amount := rent_due(_policy(ctx), housing, actor_id)
	var period := int(lease["periods_paid"]) + 1
	var economy := ctx.world.get_component("economy") as EconomyService
	var err := economy.try_debit(ctx, actor_id, amount, "rent:%s:p%d" % [lease["housing_id"], period])
	if err.is_empty():
		lease["periods_paid"] = period
		lease["next_due_day"] = int(lease["next_due_day"]) + int(housing["period_days"])
		lease["overdue_since_day"] = -1
		ctx.emit("rent_paid", {"actor_id": actor_id, "housing_id": lease["housing_id"], "period": period,
			"amount_minor": amount, "next_due_day": lease["next_due_day"]})
		return ""
	if err == "E_INSUFFICIENT_FUNDS":
		if int(lease["overdue_since_day"]) < 0:
			lease["overdue_since_day"] = day
		ctx.emit("rent_overdue", {"actor_id": actor_id, "housing_id": lease["housing_id"], "period": period,
			"amount_minor": amount, "overdue_since_day": lease["overdue_since_day"]})
	return err


static func _policy(ctx: CommandContext) -> RegionPolicy:
	return ctx.get_service("region_policy") as RegionPolicy


func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "leases": _leases.duplicate(true)}


func from_dict(data: Dictionary) -> String:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, STATE_SCHEMA)
	if not v.is_ok():
		return "E_INVALID_HOUSING_STATE"
	for actor: String in d["leases"]:
		if not _content.has_record("housing", d["leases"][actor]["housing_id"]):
			return "E_INVALID_HOUSING_STATE"
	_leases = d["leases"]
	return ""
