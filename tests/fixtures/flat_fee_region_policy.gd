extends RegionPolicy
## Test-only "fake region": take-home = gross - flat fee. Used to prove gameplay code works
## unchanged when a city's policy config points at a different implementation (spec §8.1 #5).

var _fee := 0


func configure(config_record: Dictionary) -> PackedStringArray:
	var errors := super(config_record)
	var v := SchemaValidator.new()
	var settings: Variant = v.validate(config_record.get("settings", {}), {"type": "object", "fields": {
		"flat_fee_minor": {"type": "int", "required": true, "min": 0}}}, "/settings")
	for e in v.errors:
		errors.append("%s [%s]" % [e["path"], e["code"]])
	if errors.is_empty():
		_fee = settings["flat_fee_minor"]
	return errors


func calculate_take_home_pay(gross_minor: int, _context: Dictionary) -> int:
	return maxi(gross_minor - _fee, 0)
