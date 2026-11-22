class_name RegionPolicy
extends RefCounted
## Region rule interface (spec §2.3). Answers "how is this settled here?"; content packs answer
## "what exists here?". Gameplay systems call only these methods, so a new country is a new
## implementation + config, never an `if country == ...` branch in WorkSystem & co.
##
## All money is integer minor units. Implementations must be deterministic and side-effect free:
## they compute results, the CommandProcessor applies them.

var _config: Dictionary = {}


## Receives the `region_policy_configs` record. Returns validation errors (empty = ok).
## Subclasses validate their own `settings` and should call super first.
func configure(config_record: Dictionary) -> PackedStringArray:
	_config = config_record.duplicate(true)
	return PackedStringArray()


func get_policy_config_id() -> String:
	return _config.get("id", "")


func get_region_id() -> String:
	return _config.get("region_id", "")


func get_implementation_id() -> String:
	return _config.get("implementation", "")


func get_currency_code() -> String:
	return _config.get("currency_code", "")


func calculate_take_home_pay(gross_minor: int, _context: Dictionary) -> int:
	return maxi(gross_minor, 0)


func calculate_recurring_cost(_kind: String, base_minor: int, _context: Dictionary) -> int:
	return maxi(base_minor, 0)


## context may contain "worked_minutes_today" (int).
func validate_work_shift(_job: Dictionary, shift_minutes: int, _context: Dictionary) -> bool:
	return shift_minutes > 0


## date_key comes from GameClock.date_key_of(day_index).
func get_calendar_modifiers(_date_key: String) -> Dictionary:
	return {}
