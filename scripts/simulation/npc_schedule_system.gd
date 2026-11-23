class_name NpcScheduleSystem
extends RefCounted
## Where named NPCs are (T013): a pure function of content schedules and game time, so it is
## always consistent after time skips, map changes and save/load, and needs no saved state.
## Outside scheduled slots an NPC is at home, indoors, and not visible. Pathfinding is not needed:
## NPCs switch between location anchors (spec T013). Richer off-screen life is T026.

var _content: ContentRegistry


func _init(content: ContentRegistry) -> void:
	_content = content


## location_id, or "" when at home/indoors.
func location_of(npc_id: String, game_minute: int) -> String:
	if not _content.has_record("npcs", npc_id):
		return ""
	var mod := GameClock.minute_of_day_of(game_minute)
	var day := GameClock.day_index_of(game_minute)
	for slot: Dictionary in _content.get_record("npcs", npc_id)["schedule"]:
		if day < int(slot.get("day_from", 1)) or day > int(slot.get("day_to", 999999)):
			continue
		if mod >= int(slot["start_minute_of_day"]) and mod < int(slot["end_minute_of_day"]):
			return slot["location_id"]
	return ""


## NPC ids visible on `map_id` at `game_minute`, sorted, with their location ids.
func present_on_map(map_id: String, game_minute: int) -> Dictionary:
	var out := {}
	for npc_id in _content.get_ids("npcs"):
		var loc := location_of(npc_id, game_minute)
		if not loc.is_empty() and _content.get_record("locations", loc)["map_id"] == map_id:
			out[npc_id] = loc
	return out
