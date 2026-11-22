extends RefCounted
## Minimal assertion base for the headless test runner (see docs/decisions.md D-002).
## Test scripts extend this file by path and define methods named `test_*`.
## Assertions record failures instead of aborting so one run reports everything.

var _failures: PackedStringArray = []
var _current_test := ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


## Waits for `count` physics frames (for scene tests).
func wait_physics_frames(count: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for i in count:
		await tree.physics_frame


func wait_process_frames(count: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for i in count:
		await tree.process_frame


func _begin(test_name: String) -> void:
	_current_test = test_name
	_failures.clear()


func get_failures() -> PackedStringArray:
	return _failures


func fail(message: String) -> void:
	_failures.append(message)


func assert_true(value: bool, message := "") -> void:
	if not value:
		fail("expected true. %s" % message)


func assert_false(value: bool, message := "") -> void:
	if value:
		fail("expected false. %s" % message)


func assert_eq(actual: Variant, expected: Variant, message := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		fail("expected <%s> (%s), got <%s> (%s). %s" % [
			str(expected), type_string(typeof(expected)),
			str(actual), type_string(typeof(actual)), message])


func assert_ne(actual: Variant, unexpected: Variant, message := "") -> void:
	if typeof(actual) == typeof(unexpected) and actual == unexpected:
		fail("did not expect <%s>. %s" % [str(actual), message])


func assert_not_null(value: Variant, message := "") -> void:
	if value == null:
		fail("expected non-null. %s" % message)


func assert_has(container: Variant, item: Variant, message := "") -> void:
	if not container.has(item):
		fail("expected container to have <%s>. %s" % [str(item), message])
