class_name ChinaRegionPolicy
extends RegionPolicy
## China rules for the first slice. Every number is a GAMIFIED balance parameter read from
## content/regions/cn/policy_config.json; nothing here models real tax, social insurance or
## labour law (spec §2.3, §3.4).

const SETTINGS_SCHEMA := {"type": "object", "fields": {
	## Flat payroll deduction in basis points (500 = 5%). Deduction rounds down (player-favourable).
	"payroll_deduction_bp": {"type": "int", "required": true, "min": 0, "max": 10000},
	"max_work_minutes_per_day": {"type": "int", "required": true, "min": 1, "max": 1440},
	## Per cost kind multiplier in basis points; missing kind = 10000 (unchanged).
	"recurring_cost_multiplier_bp": {"type": "map", "required": true, "key_pattern": "^[a-z][a-z0-9_]*$",
		"values_spec": {"type": "int", "min": 0, "max": 1000000}},
	## date_key ("day_7") -> modifier object, interpreted by the systems that consume it.
	"calendar_modifiers": {"type": "map", "required": true, "key_pattern": "^[a-z0-9_]+$",
		"values_spec": {"type": "map", "values_spec": {"type": "any"}}},
}}

const BP_SCALE := 10000

var _settings: Dictionary = {}


func configure(config_record: Dictionary) -> PackedStringArray:
	var errors := super(config_record)
	var v := SchemaValidator.new()
	var settings: Variant = v.validate(config_record.get("settings", {}), SETTINGS_SCHEMA, "/settings")
	for e in v.errors:
		errors.append("%s [%s] %s" % [e["path"], e["code"], e["message"]])
	if errors.is_empty():
		_settings = settings
	return errors


@warning_ignore("integer_division")
func calculate_take_home_pay(gross_minor: int, _context: Dictionary) -> int:
	if gross_minor <= 0:
		return 0
	var deduction: int = gross_minor * int(_settings["payroll_deduction_bp"]) / BP_SCALE
	return gross_minor - deduction


@warning_ignore("integer_division")
func calculate_recurring_cost(kind: String, base_minor: int, _context: Dictionary) -> int:
	if base_minor <= 0:
		return 0
	var multiplier: int = (_settings["recurring_cost_multiplier_bp"] as Dictionary).get(kind, BP_SCALE)
	return base_minor * multiplier / BP_SCALE


func validate_work_shift(_job: Dictionary, shift_minutes: int, context: Dictionary) -> bool:
	if shift_minutes <= 0:
		return false
	var already: int = int(context.get("worked_minutes_today", 0))
	return already >= 0 and already + shift_minutes <= int(_settings["max_work_minutes_per_day"])


func get_calendar_modifiers(date_key: String) -> Dictionary:
	return ((_settings["calendar_modifiers"] as Dictionary).get(date_key, {}) as Dictionary).duplicate(true)
