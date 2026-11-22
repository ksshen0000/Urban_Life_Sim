class_name FlagsSystem
extends RefCounted
## Story flags (spec §4.3 set_flag / flag_equals). Keys are namespaced ("story.met_chen"); values
## are bool, int or string. Unset flags read as false. Written only through story effects.

const SCHEMA_VERSION := 1
const STATE_SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"flags": {"type": "map", "required": true, "key_pattern": ContentSchemas.FLAG_KEY_PATTERN, "values_spec": {"type": "any"}},
}}

var _flags: Dictionary = {}


func get_flag(key: String) -> Variant:
	return _flags.get(key, false)


func get_all() -> Dictionary:
	return _flags.duplicate()


func set_flag(ctx: CommandContext, key: String, value: Variant) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	if not (typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_STRING]):
		return "E_INVALID_ARGUMENTS"
	if _flags.get(key) == value and _flags.has(key):
		return ""
	_flags[key] = value
	ctx.emit("flag_set", {"key": key, "value": value})
	return ""


func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "flags": _flags.duplicate()}


func from_dict(data: Dictionary) -> String:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, STATE_SCHEMA)
	if not v.is_ok():
		return "E_INVALID_FLAGS_STATE"
	for k: String in d["flags"]:
		if not (typeof(d["flags"][k]) in [TYPE_BOOL, TYPE_INT, TYPE_STRING]):
			return "E_INVALID_FLAGS_STATE"
	_flags = d["flags"]
	return ""
