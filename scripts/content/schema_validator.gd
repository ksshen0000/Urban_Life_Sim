class_name SchemaValidator
extends RefCounted
## Validates parsed JSON against a small declarative schema (a JSON-Schema-equivalent subset).
## Used for content packs now; reused later for proposals, story fixtures and save files.
##
## Never prints. Problems are collected in `errors` as {code, path, message}; `path` is a
## JSON-pointer-like string ("/records/2/region_id"). `validate()` returns a normalized copy:
## integral JSON numbers become `int` (Godot's JSON parser yields floats for every number).
##
## Spec keys:
##   type        "any" | "string" | "id" | "text_key" | "ref" | "int" | "bool" | "array" | "object" | "map"
##   required    (object fields) field must be present
##   nullable    null is accepted
##   pattern     regex for string-like types ("id", "ref" and "text_key" have defaults)
##   min_length  string-like types ("id"/"ref" default to 1)
##   max_length  string-like types (no limit by default)
##   values      allowed values (enum) for string-like types
##   min / max   int range
##   items       element spec (array); min_items / max_items / unique / unique_by (object field)
##   fields      field specs (object); allow_extra permits unknown fields
##   values_spec value spec (map); key_pattern regex for keys
##   table       (ref, text_key) referenced table; match = {target_field: source_field} cross-checks
##               resolved by the caller once every record is known.

const MAX_SAFE_INT := 9007199254740991
const DEFAULT_ID_PATTERN := "^[a-z][a-z0-9_]*$"
const TEXT_KEY_PATTERN := "^[a-z0-9_]+(\\.[a-z0-9_]+)+$"

var errors: Array[Dictionary] = []
## References found while validating: {table, id, path, match}.
var refs: Array[Dictionary] = []

static var _regex_cache: Dictionary = {}


static func clear_cache() -> void:
	_regex_cache.clear()


func reset() -> void:
	errors.clear()
	refs.clear()


func is_ok() -> bool:
	return errors.is_empty()


func validate(value: Variant, spec: Dictionary, path: String = "") -> Variant:
	if value == null:
		if spec.get("nullable", false) or spec.get("type", "any") == "any":
			return null
		_error("E_TYPE", path, "expected %s, got null" % spec.get("type", "any"))
		return null
	var type: String = spec.get("type", "any")
	match type:
		"any":
			return _normalize_any(value)
		"string", "id", "text_key", "ref":
			return _validate_string(value, spec, path, type)
		"int":
			return _validate_int(value, spec, path)
		"bool":
			if typeof(value) != TYPE_BOOL:
				_error("E_TYPE", path, "expected bool, got %s" % type_string(typeof(value)))
				return null
			return value
		"array":
			return _validate_array(value, spec, path)
		"object":
			return _validate_object(value, spec, path)
		"map":
			return _validate_map(value, spec, path)
	_error("E_SCHEMA", path, "unknown schema type '%s'" % type)
	return null


static func join_path(path: String, key: Variant) -> String:
	return "%s/%s" % [path, str(key)]


func _error(code: String, path: String, message: String) -> void:
	errors.append({"code": code, "path": path, "message": message})


func _validate_string(value: Variant, spec: Dictionary, path: String, type: String) -> Variant:
	if typeof(value) != TYPE_STRING:
		_error("E_TYPE", path, "expected string, got %s" % type_string(typeof(value)))
		return null
	var s: String = value
	var before := errors.size()
	var min_length: int = spec.get("min_length", 1 if type in ["id", "ref", "text_key"] else 0)
	if s.length() < min_length:
		_error("E_LENGTH", path, "string shorter than %d" % min_length)
	if spec.has("max_length") and s.length() > int(spec["max_length"]):
		_error("E_LENGTH", path, "string longer than %d" % int(spec["max_length"]))
	var pattern: String = spec.get("pattern", "")
	if pattern.is_empty():
		if type == "id" or type == "ref":
			pattern = DEFAULT_ID_PATTERN
		elif type == "text_key":
			pattern = TEXT_KEY_PATTERN
	if not pattern.is_empty() and not _regex(pattern).search(s):
		_error("E_PATTERN", path, "'%s' does not match %s" % [s, pattern])
	if spec.has("values") and not (spec["values"] as Array).has(s):
		_error("E_ENUM", path, "'%s' is not one of %s" % [s, str(spec["values"])])
	# "ref" always records a reference; "text_key" does when the spec names its text table.
	if (type == "ref" or (type == "text_key" and spec.has("table"))) and errors.size() == before:
		refs.append({"table": spec.get("table", ""), "id": s, "path": path, "match": spec.get("match", {})})
	return s


func _validate_int(value: Variant, spec: Dictionary, path: String) -> Variant:
	var n := 0
	match typeof(value):
		TYPE_INT:
			n = value
		TYPE_FLOAT:
			var f: float = value
			if is_nan(f) or is_inf(f) or f != floorf(f) or absf(f) > MAX_SAFE_INT:
				_error("E_TYPE", path, "expected integer, got %s" % str(f))
				return null
			n = int(f)
		_:
			_error("E_TYPE", path, "expected integer, got %s" % type_string(typeof(value)))
			return null
	if spec.has("min") and n < int(spec["min"]):
		_error("E_RANGE", path, "%d is below minimum %d" % [n, int(spec["min"])])
	if spec.has("max") and n > int(spec["max"]):
		_error("E_RANGE", path, "%d is above maximum %d" % [n, int(spec["max"])])
	return n


func _validate_array(value: Variant, spec: Dictionary, path: String) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		_error("E_TYPE", path, "expected array, got %s" % type_string(typeof(value)))
		return null
	var arr: Array = value
	if spec.has("min_items") and arr.size() < int(spec["min_items"]):
		_error("E_LENGTH", path, "needs at least %d items" % int(spec["min_items"]))
	if spec.has("max_items") and arr.size() > int(spec["max_items"]):
		_error("E_LENGTH", path, "allows at most %d items" % int(spec["max_items"]))
	var item_spec: Dictionary = spec.get("items", {"type": "any"})
	var out: Array = []
	var seen := {}
	for i in arr.size():
		var item_path := join_path(path, i)
		var item: Variant = validate(arr[i], item_spec, item_path)
		if (spec.get("unique", false) or spec.has("unique_by")) and item != null:
			var key := var_to_str(item)
			if spec.has("unique_by") and typeof(item) == TYPE_DICTIONARY:
				key = var_to_str((item as Dictionary).get(spec["unique_by"]))
			if seen.has(key):
				_error("E_DUPLICATE_ITEM", item_path, "duplicate item %s (first at index %d)" % [str(item), seen[key]])
			else:
				seen[key] = i
		out.append(item)
	return out


func _validate_object(value: Variant, spec: Dictionary, path: String) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		_error("E_TYPE", path, "expected object, got %s" % type_string(typeof(value)))
		return null
	var obj: Dictionary = value
	var fields: Dictionary = spec.get("fields", {})
	var out := {}
	for field: String in fields:
		var field_spec: Dictionary = fields[field]
		if not obj.has(field):
			if field_spec.get("required", false):
				_error("E_REQUIRED", join_path(path, field), "missing required field '%s'" % field)
			continue
		out[field] = validate(obj[field], field_spec, join_path(path, field))
	if not spec.get("allow_extra", false):
		for key: Variant in obj:
			if not fields.has(key):
				_error("E_UNKNOWN_FIELD", join_path(path, key), "unknown field '%s'" % str(key))
	else:
		for key: Variant in obj:
			if not fields.has(key):
				out[key] = _normalize_any(obj[key])
	return out


func _validate_map(value: Variant, spec: Dictionary, path: String) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		_error("E_TYPE", path, "expected object, got %s" % type_string(typeof(value)))
		return null
	var obj: Dictionary = value
	var key_pattern: String = spec.get("key_pattern", "")
	var value_spec: Dictionary = spec.get("values_spec", {"type": "any"})
	var out := {}
	for key: Variant in obj:
		var key_path := join_path(path, key)
		if typeof(key) != TYPE_STRING:
			_error("E_TYPE", key_path, "map keys must be strings")
			continue
		if not key_pattern.is_empty() and not _regex(key_pattern).search(key):
			_error("E_PATTERN", key_path, "key '%s' does not match %s" % [key, key_pattern])
		out[key] = validate(obj[key], value_spec, key_path)
	return out


## Deep copy that turns integral floats into ints (the project stores no fractional numbers).
func _normalize_any(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			if not is_nan(f) and not is_inf(f) and f == floorf(f) and absf(f) <= MAX_SAFE_INT:
				return int(f)
			return f
		TYPE_ARRAY:
			var out: Array = []
			for v: Variant in value:
				out.append(_normalize_any(v))
			return out
		TYPE_DICTIONARY:
			var out := {}
			for k: Variant in value:
				out[k] = _normalize_any(value[k])
			return out
	return value


static func _regex(pattern: String) -> RegEx:
	if not _regex_cache.has(pattern):
		var re := RegEx.new()
		re.compile(pattern)
		_regex_cache[pattern] = re
	return _regex_cache[pattern]
