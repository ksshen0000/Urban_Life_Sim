class_name RegionPolicyRegistry
extends RefCounted
## Maps the `implementation` id named in a region policy config to a RegionPolicy script and
## builds the configured policy for a city:
##   city.region_id -> region.policy_config_id -> config.implementation -> script.new().configure(config)
## Selection is pure data lookup; no code branches on region or country ids.

## Implementations shipped with the game. A new country adds one line here plus its config.
const BUILTIN_IMPLEMENTATIONS := {
	"china": preload("res://scripts/regions/china_region_policy.gd"),
}

var _implementations: Dictionary = {}


static func with_builtin_implementations() -> RegionPolicyRegistry:
	var registry := RegionPolicyRegistry.new()
	for impl_id: String in BUILTIN_IMPLEMENTATIONS:
		registry.register_implementation(impl_id, BUILTIN_IMPLEMENTATIONS[impl_id])
	return registry


## Returns false if the id is taken or the script is not a RegionPolicy.
func register_implementation(impl_id: String, script: Script) -> bool:
	if impl_id.is_empty() or _implementations.has(impl_id) or script == null or not script.can_instantiate():
		return false
	var probe: Object = script.new()
	var ok := probe is RegionPolicy
	if not (probe is RefCounted):
		probe.free()
	if not ok:
		return false
	_implementations[impl_id] = script
	return true


func has_implementation(impl_id: String) -> bool:
	return _implementations.has(impl_id)


## Returns {ok, error_code, message, policy}.
func create_for_city(content: ContentRegistry, city_id: String) -> Dictionary:
	if content == null or not content.is_loaded():
		return _fail("E_CONTENT_NOT_LOADED", "content registry is not loaded")
	if not content.has_record("cities", city_id):
		return _fail("E_UNKNOWN_CITY", "city '%s' is not defined" % city_id)
	var region_id: String = content.get_record("cities", city_id)["region_id"]
	var config_id: String = content.get_record("regions", region_id)["policy_config_id"]
	return create_from_config(content.get_record("region_policy_configs", config_id))


func create_from_config(config: Dictionary) -> Dictionary:
	var impl_id: String = config.get("implementation", "")
	if not _implementations.has(impl_id):
		return _fail("E_UNKNOWN_POLICY_IMPLEMENTATION",
			"policy config '%s' names unregistered implementation '%s'" % [config.get("id", "?"), impl_id])
	var policy: RegionPolicy = (_implementations[impl_id] as Script).new()
	var errors := policy.configure(config)
	if not errors.is_empty():
		return _fail("E_POLICY_CONFIG", "policy config '%s': %s" % [config.get("id", "?"), "; ".join(errors)])
	return {"ok": true, "error_code": null, "message": "", "policy": policy}


static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error_code": code, "message": message, "policy": null}
