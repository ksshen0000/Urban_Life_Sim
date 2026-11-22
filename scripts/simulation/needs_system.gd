class_name NeedsSystem
extends RefCounted
## Hunger / energy / stress per owner (spec §3.2, §3.4). A WorldState component.
##
## Values are integers clamped to 0..100. Time changes them through `on_time_passed` (called by
## TimeFlow) using per-hour rates from content/common/needs.json, by time mode (awake, resting,
## sleeping). Fractions are carried as integer "rate × minutes" remainders, so sixty 1-minute
## ticks give exactly the same result as one 60-minute step. Long spans are evaluated in chunks
## of at most 60 minutes so pressure rules (e.g. hungry → stress rises) react within the hour.
## `mode_caps` stop increases during a mode at a cap (sleep restores energy to at most 90).

const SCHEMA_VERSION := 1
const MIN_VALUE := 0
const MAX_VALUE := 100
const CHUNK_MINUTES := 60
const STATE_SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"values": {"type": "map", "required": true,
		"values_spec": {"type": "map", "values_spec": {"type": "int", "min": MIN_VALUE, "max": MAX_VALUE}}},
	"carry": {"type": "map", "required": true,
		"values_spec": {"type": "map", "values_spec": {"type": "int", "min": -59, "max": 59}}},
}}

var _defs: Array[Dictionary] = []  # sorted by id
var _need_ids: PackedStringArray = []
var _values: Dictionary = {}       # owner -> {need_id: int}
var _carry: Dictionary = {}        # owner -> {need_id: int}


func _init(need_records: Array[Dictionary] = []) -> void:
	for r in need_records:
		_defs.append(r.duplicate(true))
	_defs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	for d in _defs:
		_need_ids.append(d["id"])


## World setup only.
func add_owner(owner_id: String) -> bool:
	if owner_id.is_empty() or _values.has(owner_id):
		return false
	_values[owner_id] = {}
	_carry[owner_id] = {}
	for d in _defs:
		_values[owner_id][d["id"]] = clampi(int(d["initial_value"]), MIN_VALUE, MAX_VALUE)
		_carry[owner_id][d["id"]] = 0
	return true


func has_owner(owner_id: String) -> bool:
	return _values.has(owner_id)


func get_need_ids() -> PackedStringArray:
	return _need_ids.duplicate()


func get_value(owner_id: String, need_id: String) -> int:
	return (_values.get(owner_id, {}) as Dictionary).get(need_id, 0)


func get_values(owner_id: String) -> Dictionary:
	return (_values.get(owner_id, {}) as Dictionary).duplicate()


func change(ctx: CommandContext, owner_id: String, need_id: String, delta: int, reason: String) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	if not has_owner(owner_id) or not _need_ids.has(need_id):
		return "E_UNKNOWN_NEED"
	var old: int = _values[owner_id][need_id]
	var new_value := clampi(old + delta, MIN_VALUE, MAX_VALUE)
	_values[owner_id][need_id] = new_value
	if new_value != old:
		ctx.emit("need_changed", {"owner_id": owner_id, "need_id": need_id, "value": new_value,
			"delta": new_value - old, "reason": reason})
	return ""


## TimeFlow hook.
@warning_ignore("integer_division")
## context["rates"] = {need_id: per_hour} overrides the mode's base rate for those needs (a job's
## work rates, or an activity's own rates such as scrolling short videos).
func on_time_passed(ctx: CommandContext, minutes: int, mode: String, context: Dictionary = {}) -> void:
	if minutes <= 0 or not ctx.can_write():
		return
	var owners := PackedStringArray(_values.keys())
	owners.sort()
	for owner in owners:
		var before: Dictionary = (_values[owner] as Dictionary).duplicate()
		var remaining := minutes
		while remaining > 0:
			var chunk := mini(remaining, CHUNK_MINUTES)
			remaining -= chunk
			var start: Dictionary = (_values[owner] as Dictionary).duplicate()
			for d in _defs:
				var id: String = d["id"]
				var rate := _rate(d, mode, start, context.get("rates", {}))
				var carry: int = _carry[owner][id] + rate * chunk
				var whole := carry / 60  # truncates toward zero; remainder keeps its sign
				_carry[owner][id] = carry - whole * 60
				if whole == 0:
					continue
				var old: int = _values[owner][id]
				var target := old + whole
				var caps: Dictionary = d.get("mode_caps", {})
				if whole > 0 and caps.has(mode):
					target = mini(target, maxi(int(caps[mode]), old))
				_values[owner][id] = clampi(target, MIN_VALUE, MAX_VALUE)
		for d in _defs:
			var id: String = d["id"]
			if _values[owner][id] != before[id]:
				ctx.emit("need_changed", {"owner_id": owner, "need_id": id, "value": _values[owner][id],
					"delta": _values[owner][id] - before[id], "reason": "time:" + mode})


func _rate(def: Dictionary, mode: String, values: Dictionary, overrides: Dictionary) -> int:
	var rates: Dictionary = def["rates_per_hour"]
	var rate: int = rates.get(mode, rates["awake"])
	if overrides.has(def["id"]):
		rate = overrides[def["id"]]
	for rule: Dictionary in def.get("pressure_rules", []):
		var v: int = values.get(rule["when_need"], 0)
		var hit: bool = v >= int(rule["value"]) if rule["op"] == "at_least" else v <= int(rule["value"])
		if hit:
			rate += int(rule["add_per_hour"])
	return rate


func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "values": _values.duplicate(true), "carry": _carry.duplicate(true)}


func from_dict(data: Dictionary) -> String:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, STATE_SCHEMA)
	if not v.is_ok():
		return "E_INVALID_NEEDS_STATE"
	var values: Dictionary = d["values"]
	var carry: Dictionary = d["carry"]
	if values.keys().size() != carry.keys().size():
		return "E_INVALID_NEEDS_STATE"
	for owner: String in values:
		if not carry.has(owner):
			return "E_INVALID_NEEDS_STATE"
		for table: Dictionary in [values[owner], carry[owner]]:
			var keys := PackedStringArray(table.keys())
			keys.sort()
			if keys != _need_ids:
				return "E_INVALID_NEEDS_STATE"
	_values = values
	_carry = carry
	return ""
