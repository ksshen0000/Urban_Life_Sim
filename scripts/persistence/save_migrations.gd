class_name SaveMigrations
extends RefCounted
## Explicit, ordered save upgrades (spec §4.4, §16.3). Each step turns a save of version N into
## version N + 1 and is a plain function over dictionaries: no objects are deserialized and nothing
## from the save is executed. A save newer than the game, or with a gap in the chain, is rejected.
##
## Version history:
##   1 — first save format (T017).
##   2 — adds the `profile` world component (character creator, D-033). v1 saves get the default
##       look and an empty name.
## To change the format: bump SaveManager.SAVE_SCHEMA_VERSION, add `N: _from_N` to
## _builtin_steps(), and add a migration test.


## Returns {ok, error_code, data}. `steps` is injectable for tests.
static func migrate(data: Dictionary, target: int, steps: Dictionary = {}) -> Dictionary:
	var chain: Dictionary = steps if not steps.is_empty() else _builtin_steps()
	var version: Variant = data.get("save_schema_version")
	if typeof(version) == TYPE_FLOAT and is_equal_approx(version, roundf(version)):
		version = int(version)
	if typeof(version) != TYPE_INT or version < 1:
		return {"ok": false, "error_code": "E_SAVE_CORRUPT", "data": {}}
	if version > target:
		return {"ok": false, "error_code": "E_SAVE_TOO_NEW", "data": {}}
	var out := data.duplicate(true)
	while version < target:
		if not chain.has(version):
			return {"ok": false, "error_code": "E_SAVE_NO_MIGRATION", "data": {}}
		var step: Callable = chain[version]
		out = step.call(out)
		if out.is_empty():
			return {"ok": false, "error_code": "E_SAVE_MIGRATION_FAILED", "data": {}}
		version += 1
		out["save_schema_version"] = version
	return {"ok": true, "error_code": null, "data": out}


static func _builtin_steps() -> Dictionary:
	return {1: _from_1}


## v1 -> v2: add the player profile component with the default look.
static func _from_1(data: Dictionary) -> Dictionary:
	var world: Variant = data.get("world")
	if typeof(world) != TYPE_DICTIONARY or typeof(world.get("components")) != TYPE_DICTIONARY:
		return data  # malformed: left for envelope validation to report as E_SAVE_CORRUPT
	var components: Dictionary = world["components"]
	if not components.has("profile"):
		var player: String = str((data.get("player", {}) as Dictionary).get("actor_id", "player")) \
			if typeof(data.get("player")) == TYPE_DICTIONARY else "player"
		components["profile"] = {"schema_version": 1, "actors": {player: ProfileSystem.default_profile()}}
	return data
