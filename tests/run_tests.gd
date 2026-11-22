extends SceneTree
## Headless test runner. Usage:
##   godot --headless --path . -s res://tests/run_tests.gd [-- --filter=<substring>]
## Discovers res://tests/test_*.gd, runs every `test_*` method, exits 1 on any failure.
## Test methods (and before_each/after_each) may be coroutines: they are awaited, so scene tests
## can wait for physics frames.

const TEST_DIR := "res://tests"


func _initialize() -> void:
	_run()


func _run() -> void:
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")

	var files := _discover()
	var passed := 0
	var failed := 0
	var broken := 0

	for path in files:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			printerr("BROKEN  %s (failed to load/compile)" % path)
			broken += 1
			continue
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if mname.begins_with("test_") and not methods.has(mname):
				if filter.is_empty() or (path + ":" + mname).contains(filter):
					methods.append(mname)
		methods.sort()
		for mname in methods:
			var instance: RefCounted = script.new()
			instance._begin(mname)
			await instance.before_each()
			await instance.call(mname)
			await instance.after_each()
			var failures: PackedStringArray = instance.get_failures()
			if failures.is_empty():
				passed += 1
				print("PASS    %s:%s" % [path.get_file(), mname])
			else:
				failed += 1
				printerr("FAIL    %s:%s" % [path.get_file(), mname])
				for f in failures:
					printerr("        - %s" % f)

	print("\n%d passed, %d failed, %d broken files (%d files)" % [passed, failed, broken, files.size()])
	quit(1 if failed > 0 or broken > 0 or passed == 0 else 0)


func _discover() -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		printerr("cannot open %s" % TEST_DIR)
		return out
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(TEST_DIR.path_join(f))
	out.sort()
	return out
