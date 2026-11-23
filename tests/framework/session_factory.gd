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


## Mechanics tests run without story events and without need effects (D-037: they fast-forward
## days without sleeping) unless they ask for them (story_enabled / need_effects: true).
## (old note) Mechanics tests run without story events unless they ask for them (story_enabled: true).
static func create(overrides: Dictionary = {}) -> SimulationSession:
	var o := {"story_enabled": false, "need_effects": false}
	o.merge(overrides, true)
	var r := SimulationSession.create_new(content(), RegionPolicyRegistry.with_builtin_implementations(),
		CITY_ID, o)
	assert(r["ok"], str(r["message"]))
	return r["session"]


## Walks the player to `location_id` through doors (D-034): out of the current interior if
## needed, then in through the door that leads there. Bus rides are not taken. Returns true if
## the player ends up on that location's map.
static func go(s: SimulationSession, location_id: String) -> bool:
	var target_map := s.locations.map_of_location(location_id)
	for i in 3:
		var here := s.locations.get_map_id(SimulationSession.PLAYER_ID)
		if here == target_map:
			return true
		var door := _door_towards(s, here, target_map)
		if door.is_empty() or not s.submit("use_door", {"door_id": door}).ok:
			return false
	return s.locations.get_map_id(SimulationSession.PLAYER_ID) == target_map


## A door on map `here` leading to `target_map`, else a door leading back out to the street.
static func _door_towards(s: SimulationSession, here: String, target_map: String) -> String:
	var fallback := ""
	for it: Dictionary in s.content.get_record("maps", here)["interactables"]:
		if it["kind"] != "door":
			continue
		if s.locations.map_of_location(it["target_location_id"]) == target_map:
			return it["id"]
		if s.content.get_record("maps", here).get("indoor", false):
			fallback = it["id"]  # out of a shop; never wander off down a street
	return fallback
