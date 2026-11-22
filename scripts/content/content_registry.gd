class_name ContentRegistry
extends RefCounted
## Loads and validates data-driven content packs (spec §2.4, §2.6, §16.3).
##
## A pack is a directory containing `pack.json`, which declares its id, version, scope
## (region/country/city), dependencies, story-provider metadata and the data files it ships,
## each bound to a table defined in ContentSchemas.
##
## Loading is all-or-nothing. Every problem found (bad JSON, missing/extra/mistyped fields,
## duplicate ids, unknown or invisible references, scope mismatches, dependency cycles) is
## reported with file path + JSON pointer, and a failed load leaves the registry empty so the
## game can never run on half-valid data. Nothing here prints: callers decide how to surface it.
##
## Records returned by queries are deep copies; content is immutable at runtime.

const PACK_MANIFEST := "pack.json"
const SUPPORTED_MANIFEST_VERSIONS := [1]

var _packs: Dictionary = {}                  # pack_id -> normalized manifest (+ _dir, _file, content_hash)
var _pack_order: PackedStringArray = []      # dependency order
var _tables: Dictionary = {}                 # table -> {id -> record}
var _sources: Dictionary = {}                # table -> {id -> {pack_id, file, path}}
var _errors: Array[Dictionary] = []
var _loaded := false


## Discovers every pack.json under `root_dir` (recursively) and loads them.
func load_root(root_dir: String) -> bool:
	_reset()
	var dirs: PackedStringArray = []
	if DirAccess.open(root_dir) == null:
		_error("E_FILE_MISSING", root_dir, "", "content root cannot be opened")
		return false
	_discover(root_dir, dirs)
	if dirs.is_empty():
		_error("E_NO_PACKS", root_dir, "", "no %s found" % PACK_MANIFEST)
		return false
	return _load(dirs)


## Loads exactly the given pack directories.
func load_pack_dirs(pack_dirs: PackedStringArray) -> bool:
	_reset()
	return _load(pack_dirs)


func is_loaded() -> bool:
	return _loaded


func get_errors() -> Array[Dictionary]:
	return _errors.duplicate(true)


func get_error_strings() -> PackedStringArray:
	var out: PackedStringArray = []
	for e in _errors:
		out.append(format_error(e))
	return out


static func format_error(e: Dictionary) -> String:
	var location: String = e.get("file", "")
	if not str(e.get("path", "")).is_empty():
		location += ":" + str(e["path"])
	return "%s [%s] %s" % [location, e.get("code", "?"), e.get("message", "")]


func get_pack_ids() -> PackedStringArray:
	return _pack_order.duplicate()


func get_pack(pack_id: String) -> Dictionary:
	if not _packs.has(pack_id):
		return {}
	var m: Dictionary = _packs[pack_id].duplicate(true)
	m.erase("_dir")
	m.erase("_file")
	return m


func has_record(table: String, id: String) -> bool:
	return _tables.has(table) and (_tables[table] as Dictionary).has(id)


func get_record(table: String, id: String) -> Dictionary:
	if not has_record(table, id):
		return {}
	return (_tables[table][id] as Dictionary).duplicate(true)


func get_ids(table: String) -> PackedStringArray:
	var ids: PackedStringArray = []
	if _tables.has(table):
		ids = PackedStringArray((_tables[table] as Dictionary).keys())
		ids.sort()
	return ids


func get_records(table: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in get_ids(table):
		out.append(get_record(table, id))
	return out


## {pack_id, file, path} of the record's definition, for error messages and tooling.
func get_record_source(table: String, id: String) -> Dictionary:
	if not has_record(table, id):
		return {}
	return (_sources[table][id] as Dictionary).duplicate()


## Story providers declared by loaded packs: {provider_id, schema_version, provider_version, pack_id}.
func get_story_providers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pack_id in _pack_order:
		for p: Dictionary in _packs[pack_id].get("story_providers", []):
			var entry := p.duplicate(true)
			entry["pack_id"] = pack_id
			out.append(entry)
	return out


# --- loading ------------------------------------------------------------------------------

func _reset() -> void:
	_packs.clear()
	_pack_order.clear()
	_tables.clear()
	_sources.clear()
	_errors.clear()
	_loaded = false


func _error(code: String, file: String, path: String, message: String) -> void:
	_errors.append({"code": code, "file": file, "path": path, "message": message})


func _discover(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	if dir.file_exists(PACK_MANIFEST):
		out.append(dir_path)
	var subdirs := dir.get_directories()
	subdirs.sort()
	for sub in subdirs:
		if not sub.begins_with("."):
			_discover(dir_path.path_join(sub), out)


func _load(pack_dirs: PackedStringArray) -> bool:
	var manifests := _read_manifests(pack_dirs)
	_pack_order = _dependency_order(manifests)
	var visible := {}  # pack_id -> {pack_id: true} (itself + transitive dependencies)
	for pack_id in _pack_order:
		var reachable := {pack_id: true}
		for dep: String in manifests[pack_id]["dependencies"]:
			reachable.merge(visible.get(dep, {}))
		visible[pack_id] = reachable
	for table: String in ContentSchemas.TABLES:
		_tables[table] = {}
		_sources[table] = {}

	var pending_refs: Array[Dictionary] = []
	for pack_id in _pack_order:
		var manifest: Dictionary = manifests[pack_id]
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(str(manifest["_raw_text"]).to_utf8_buffer())
		var files: Array = manifest["files"]
		for i in files.size():
			_load_data_file(manifest, files[i], i, pending_refs, hashing)
		manifest["content_hash"] = hashing.finish().hex_encode()
		manifest.erase("_raw_text")
		_packs[pack_id] = manifest

	_resolve_refs(pending_refs, visible)
	if _errors.is_empty():
		_semantic_checks()
	_loaded = _errors.is_empty()
	if not _loaded:
		var errors := _errors.duplicate()  # _reset() clears the array in place
		_reset()
		_errors = errors
	return _loaded


func _read_manifests(pack_dirs: PackedStringArray) -> Dictionary:
	var manifests := {}
	for dir in pack_dirs:
		var file := dir.path_join(PACK_MANIFEST)
		var parsed := _read_json(file)
		if not parsed["ok"]:
			continue
		var v := SchemaValidator.new()
		var m: Variant = v.validate(parsed["value"], ContentSchemas.PACK_MANIFEST)
		_take_validator_errors(v, file)
		if not v.is_ok():
			continue
		if not SUPPORTED_MANIFEST_VERSIONS.has(m["schema_version"]):
			_error("E_SCHEMA_VERSION", file, "/schema_version",
				"unsupported manifest schema_version %d" % m["schema_version"])
			continue
		var pack_id: String = m["pack_id"]
		if manifests.has(pack_id):
			_error("E_DUPLICATE_PACK", file, "/pack_id",
				"pack '%s' is already defined by %s" % [pack_id, manifests[pack_id]["_file"]])
			continue
		m["_dir"] = dir
		m["_file"] = file
		m["_raw_text"] = parsed["text"]
		manifests[pack_id] = m
	for pack_id: String in manifests:
		var deps: Array = manifests[pack_id]["dependencies"]
		for i in deps.size():
			if not manifests.has(deps[i]):
				_error("E_PACK_DEPENDENCY", manifests[pack_id]["_file"], "/dependencies/%d" % i,
					"pack '%s' depends on missing pack '%s'" % [pack_id, deps[i]])
	return manifests


## Kahn's algorithm with sorted ready-queue for a deterministic order. Packs with missing
## dependencies or in cycles are excluded (and reported).
func _dependency_order(manifests: Dictionary) -> PackedStringArray:
	var order: PackedStringArray = []
	var remaining := {}
	for pack_id: String in manifests:
		var deps: Array = manifests[pack_id]["dependencies"]
		if deps.all(func(d: String) -> bool: return manifests.has(d)):
			remaining[pack_id] = deps.duplicate()
	var progress := true
	while progress and not remaining.is_empty():
		progress = false
		var ready: PackedStringArray = []
		for pack_id: String in remaining:
			if (remaining[pack_id] as Array).all(func(d: String) -> bool: return order.has(d)):
				ready.append(pack_id)
		ready.sort()
		for pack_id in ready:
			order.append(pack_id)
			remaining.erase(pack_id)
			progress = true
	var stuck := PackedStringArray(remaining.keys())
	stuck.sort()
	for pack_id in stuck:
		var deps: Array = remaining[pack_id]
		if deps.all(func(d: String) -> bool: return manifests.has(d)):
			_error("E_PACK_CYCLE", manifests[pack_id]["_file"], "/dependencies",
				"pack '%s' is in a dependency cycle or depends on a pack that cannot load" % pack_id)
	return order


func _load_data_file(manifest: Dictionary, entry: Dictionary, index: int,
		pending_refs: Array[Dictionary], hashing: HashingContext) -> void:
	var manifest_file: String = manifest["_file"]
	var rel: String = entry["path"]
	var table: String = entry["table"]
	var entry_path := "/files/%d" % index
	if not _is_safe_relative_path(rel):
		_error("E_PATH", manifest_file, entry_path + "/path",
			"'%s' must be a relative .json path inside the pack (no '..', no scheme)" % rel)
		return
	if not ContentSchemas.has_table(table):
		_error("E_UNKNOWN_TABLE", manifest_file, entry_path + "/table", "unknown table '%s'" % table)
		return
	var file: String = str(manifest["_dir"]).path_join(rel)
	var parsed := _read_json(file)
	if not parsed["ok"]:
		return
	hashing.update(str(parsed["text"]).to_utf8_buffer())
	var raw: Variant = parsed["value"]
	if typeof(raw) != TYPE_DICTIONARY:
		_error("E_TYPE", file, "", "top level must be a JSON object")
		return
	var data: Dictionary = raw
	var tdef := ContentSchemas.get_table(table)

	var version_check := SchemaValidator.new()
	var version: Variant = version_check.validate(data.get("schema_version"), {"type": "int"}, "/schema_version")
	if not data.has("schema_version"):
		_error("E_REQUIRED", file, "/schema_version", "missing required field 'schema_version'")
		return
	if not version_check.is_ok() or not (tdef["schema_versions"] as Array).has(version):
		_error("E_SCHEMA_VERSION", file, "/schema_version", "table '%s' supports schema_version %s, got %s"
			% [table, str(tdef["schema_versions"]), str(data["schema_version"])])
		return

	var records: Array = []
	var paths: PackedStringArray = []
	if data.has("records"):
		for key: Variant in data:
			if key != "records" and key != "schema_version":
				_error("E_UNKNOWN_FIELD", file, "/%s" % str(key), "unknown top-level field '%s'" % str(key))
		if typeof(data["records"]) != TYPE_ARRAY:
			_error("E_TYPE", file, "/records", "expected array")
			return
		records = data["records"]
		for i in records.size():
			paths.append("/records/%d" % i)
	else:
		var single := data.duplicate()
		single.erase("schema_version")
		records = [single]
		paths.append("")

	for i in records.size():
		var v := SchemaValidator.new()
		var record: Variant = v.validate(records[i], tdef["record"], paths[i])
		_take_validator_errors(v, file)
		if not v.is_ok():
			continue
		var custom := ContentSchemas.custom_checks(table, record, paths[i])
		for e in custom:
			_error(e["code"], file, e["path"], e["message"])
		if not custom.is_empty():
			continue
		var id: String = record["id"]
		if not _check_scope(manifest, table, tdef, record, file, paths[i]):
			continue
		if (_tables[table] as Dictionary).has(id):
			var first: Dictionary = _sources[table][id]
			_error("E_DUPLICATE_ID", file, paths[i] + "/id", "%s id '%s' is already defined at %s:%s"
				% [table, id, first["file"], first["path"]])
			continue
		_tables[table][id] = record
		_sources[table][id] = {"pack_id": manifest["pack_id"], "file": file, "path": paths[i]}
		for ref in v.refs:
			ref["file"] = file
			ref["source_table"] = table
			ref["source_id"] = id
			ref["source_pack"] = manifest["pack_id"]
			pending_refs.append(ref)


func _check_scope(manifest: Dictionary, table: String, tdef: Dictionary, record: Dictionary,
		file: String, path: String) -> bool:
	var scope: Dictionary = manifest["scope"]
	var ok := true
	for key: String in tdef.get("required_scope", []):
		if not scope.has(key):
			_error("E_SCOPE_MISSING", file, path, "table '%s' requires pack '%s' to declare scope.%s"
				% [table, manifest["pack_id"], key])
			ok = false
	var scope_fields: Dictionary = tdef.get("scope_fields", {})
	for field: String in scope_fields:
		var key: String = scope_fields[field]
		if scope.has(key) and record.has(field) and record[field] != scope[key]:
			_error("E_SCOPE_MISMATCH", file, path + "/" + field, "'%s' does not match pack scope.%s '%s'"
				% [record[field], key, scope[key]])
			ok = false
	return ok


func _resolve_refs(pending_refs: Array[Dictionary], visible: Dictionary) -> void:
	for ref in pending_refs:
		var table: String = ref["table"]
		var id: String = ref["id"]
		if not has_record(table, id):
			_error("E_UNKNOWN_REF", ref["file"], ref["path"], "%s '%s' is not defined" % [table, id])
			continue
		var target_pack: String = _sources[table][id]["pack_id"]
		if not (visible.get(ref["source_pack"], {}) as Dictionary).has(target_pack):
			_error("E_REF_NOT_VISIBLE", ref["file"], ref["path"],
				"%s '%s' is defined in pack '%s', which is not a dependency of pack '%s'"
				% [table, id, target_pack, ref["source_pack"]])
			continue
		var target: Dictionary = _tables[table][id]
		var source: Dictionary = _tables[ref["source_table"]][ref["source_id"]]
		var match_rules: Dictionary = ref["match"]
		for target_field: String in match_rules:
			var source_field: String = match_rules[target_field]
			if target.get(target_field) != source.get(source_field):
				_error("E_REF_MISMATCH", ref["file"], ref["path"], "%s '%s'.%s is '%s' but this record's %s is '%s'"
					% [table, id, target_field, str(target.get(target_field)), source_field,
					str(source.get(source_field))])


## Cross-record rules that need the whole registry (story DSL semantics, StoryValidator).
func _semantic_checks() -> void:
	for e in StoryValidator.validate_content(self):
		var src: Dictionary = _sources[e["table"]][e["id"]]
		_error(e["code"], src["file"], str(src["path"]) + str(e["path"]), e["message"])


func _read_json(file: String) -> Dictionary:
	if not FileAccess.file_exists(file):
		_error("E_FILE_MISSING", file, "", "file not found")
		return {"ok": false}
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		_error("E_FILE_READ", file, "", "cannot open (%s)" % error_string(FileAccess.get_open_error()))
		return {"ok": false}
	var text := f.get_as_text()
	var json := JSON.new()
	if json.parse(text) != OK:
		_error("E_JSON_PARSE", file, "", "line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return {"ok": false}
	return {"ok": true, "value": json.data, "text": text}


func _take_validator_errors(v: SchemaValidator, file: String) -> void:
	for e in v.errors:
		_error(e["code"], file, e["path"], e["message"])


static func _is_safe_relative_path(rel: String) -> bool:
	if rel.is_empty() or rel.begins_with("/") or rel.contains("://") or rel.contains("\\") or rel.contains(":"):
		return false
	if not rel.ends_with(".json"):
		return false
	for part in rel.split("/"):
		if part == ".." or part == "." or part.is_empty():
			return false
	return true
