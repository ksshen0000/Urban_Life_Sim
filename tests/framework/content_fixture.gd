extends RefCounted
## Builds content-pack trees for tests. Starts from a copy of the real res://content packs so
## fixtures never drift from shipped data; a test mutates the parsed JSON (or injects raw text),
## then `write()` materializes it in a throwaway user:// directory. Call `cleanup()` afterwards.

const REAL_ROOT := "res://content"
const TMP_ROOT := "user://test_tmp"

## relative path -> parsed JSON value, or a String written verbatim (see set_raw).
var files: Dictionary = {}
var _raw: Dictionary = {}
var _written_root := ""


func load_real() -> void:
	_copy_tree(REAL_ROOT, "")


func data(rel_path: String) -> Variant:
	assert(files.has(rel_path), "fixture has no file %s" % rel_path)
	return files[rel_path]


func set_json(rel_path: String, value: Variant) -> void:
	files[rel_path] = value
	_raw.erase(rel_path)


func set_raw(rel_path: String, text: String) -> void:
	files[rel_path] = text
	_raw[rel_path] = true


func remove(rel_path: String) -> void:
	files.erase(rel_path)
	_raw.erase(rel_path)


func write() -> String:
	cleanup()
	_written_root = "%s/content_%d_%d" % [TMP_ROOT, Time.get_ticks_usec(), randi()]
	for rel: String in files:
		var path := _written_root + "/" + rel
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(files[rel] if _raw.has(rel) else JSON.stringify(files[rel], "  "))
		f.close()
	return _written_root


func path_of(rel_path: String) -> String:
	return _written_root + "/" + rel_path


func cleanup() -> void:
	if not _written_root.is_empty():
		_remove_tree(_written_root)
		_written_root = ""


func _copy_tree(abs_dir: String, rel_dir: String) -> void:
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".json"):
			var rel := f if rel_dir.is_empty() else rel_dir + "/" + f
			files[rel] = JSON.parse_string(FileAccess.get_file_as_string(abs_dir.path_join(f)))
	for d in dir.get_directories():
		_copy_tree(abs_dir.path_join(d), d if rel_dir.is_empty() else rel_dir + "/" + d)


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	for d in dir.get_directories():
		_remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)
