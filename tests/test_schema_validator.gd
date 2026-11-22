extends "res://tests/framework/test_case.gd"
## SchemaValidator primitives shared by content, proposals and (later) saves.


func test_integral_floats_become_ints() -> void:
	var v := SchemaValidator.new()
	assert_eq(v.validate(150000.0, {"type": "int"}), 150000)
	assert_eq(typeof(v.validate(3.0, {"type": "int"})), TYPE_INT)
	assert_eq(v.validate({"a": [1.0, 2.5]}, {"type": "any"}), {"a": [1, 2.5]})
	assert_true(v.is_ok())


func test_rejects_unsafe_numbers() -> void:
	var v := SchemaValidator.new()
	v.validate(1.0e300, {"type": "int"}, "/big")
	v.validate(true, {"type": "int"}, "/bool")
	assert_eq(v.errors.size(), 2)
	assert_eq(v.errors[0]["path"], "/big")


func test_unique_and_length() -> void:
	var v := SchemaValidator.new()
	v.validate(["a", "b", "a"], {"type": "array", "unique": true, "max_items": 2, "items": {"type": "id"}}, "/x")
	var codes := v.errors.map(func(e: Dictionary) -> String: return e["code"])
	assert_has(codes, "E_LENGTH")
	assert_has(codes, "E_DUPLICATE_ITEM")


func test_map_key_pattern_and_values() -> void:
	var v := SchemaValidator.new()
	var out: Variant = v.validate({"ok_key": 1.0, "Bad Key": 2}, {"type": "map", "key_pattern": "^[a-z_]+$",
		"values_spec": {"type": "int", "min": 0}}, "/m")
	assert_eq(v.errors.size(), 1)
	assert_eq(v.errors[0]["path"], "/m/Bad Key")
	assert_eq(out["ok_key"], 1)


func test_refs_collected_only_when_valid() -> void:
	var v := SchemaValidator.new()
	v.validate({"r": "good_id", "s": "Bad Id"}, {"type": "object", "fields": {
		"r": {"type": "ref", "table": "t", "match": {"a": "b"}},
		"s": {"type": "ref", "table": "t"}}})
	assert_eq(v.refs.size(), 1)
	assert_eq(v.refs[0], {"table": "t", "id": "good_id", "path": "/r", "match": {"a": "b"}})


func test_nullable() -> void:
	var v := SchemaValidator.new()
	assert_eq(v.validate(null, {"type": "string", "nullable": true}), null)
	assert_true(v.is_ok())
	v.validate(null, {"type": "string"}, "/n")
	assert_eq(v.errors.size(), 1)
	assert_eq(v.validate({"error_code": null}, {"type": "map", "values_spec": {"type": "any"}}), {"error_code": null},
		"'any' accepts JSON null (saved CommandResults contain it)")
	assert_eq(v.errors.size(), 1)
