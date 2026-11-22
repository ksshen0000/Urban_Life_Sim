extends RefCounted
## Builds a SimulationSession on the real shipped content for simulation tests.

const CITY_ID := "CN_LINCHUAN"

static var _content: ContentRegistry


static func content() -> ContentRegistry:
	if _content == null:
		_content = ContentRegistry.new()
		_content.load_root("res://content")
	return _content


## The shipped city's starting cash (tuned in T018; tests derive from it instead of hardcoding).
static func start_money() -> int:
	return content().get_record("cities", CITY_ID)["starting_money_minor"]


## Mechanics tests run without story events unless they ask for them (story_enabled: true).
static func create(overrides: Dictionary = {}) -> SimulationSession:
	var o := {"story_enabled": false}
	o.merge(overrides, true)
	var r := SimulationSession.create_new(content(), RegionPolicyRegistry.with_builtin_implementations(),
		CITY_ID, o)
	assert(r["ok"], str(r["message"]))
	return r["session"]
