class_name CityWorld
extends Node2D
## The walkable city (T005). Builds the start map of the session's city from content, places the
## interactables and the player at the city's default spawn, runs exploration time while no panel
## is open, and routes interactions to the UI. All world changes go through commands.
##
## Tests call `setup(session, bus)` before adding the scene to the tree. When run on its own
## (F6 in the editor, or `godot res://scenes/world/city_world.tscn`) it starts a new game through
## the GameSession autoload.

signal interacted(interactable_id: String)
signal map_changed(map_id: String)

var session: SimulationSession
var bus: GameEventBus
var map: Dictionary = {}

var structures: Array[StructureVisual] = []
var npcs: Dictionary = {}  # npc_id -> NpcActor on the current map
var day_night: DayNight
var _last_tile := Vector2i(-1, -1)
var ambient: Dictionary = {}  # ambient id -> AmbientActor currently shown
var _npc_presence: Dictionary = {}
## Saved standing tile to use instead of the arrival spawn on the next map build (after a load).
var _start_tile := Vector2i(-1, -1)

@onready var ground: TileMapLayer = $Ground
@onready var markings: RoadMarkings = $RoadMarkings
@onready var entities: Node2D = $Entities
@onready var player: PlayerController = $Entities/Player
@onready var ui: GameUi = $GameUi


func setup(p_session: SimulationSession, p_bus: GameEventBus, start_tile: Vector2i = Vector2i(-1, -1)) -> void:
	session = p_session
	bus = p_bus
	_start_tile = start_tile


func _ready() -> void:
	day_night = DayNight.new()
	day_night.name = "DayNight"
	add_child(day_night)
	day_night.setup(ground, markings, entities)
	if session == null:
		_adopt_global_session()
	if session == null:
		push_error("CityWorld: no game session available")
		return
	sync_map()
	ui.bind(session, bus)
	ui.player_tile_provider = player_tile
	ui.travelled.connect(sync_map)
	ui.modal_changed.connect(func(open: bool) -> void:
		if not open:
			sync_player_look())
	sync_player_look()
	player.focus_changed.connect(ui.set_prompt)
	player.interact_requested.connect(_on_interact_requested)


func _process(delta: float) -> void:
	if session == null:
		return
	if session.locations.get_map_id(SimulationSession.PLAYER_ID) != map.get("id", ""):
		sync_map()
	_refresh_npcs()
	_refresh_ambient()
	day_night.update(session.world.clock.get_minute_of_day())
	if not ui.is_modal():
		_check_walk_in_doors()
		if session.dialogue.has_pending():
			ui.open_story_entry(session.dialogue.peek())
		else:
			session.advance_exploration(delta)
	for st in structures:
		st.update_fade(player.position)


## The player's sprite follows their saved profile (character creator, mirror at home).
func sync_player_look() -> void:
	var look := PixelPerson.normalize_look(session.profile.get_look(SimulationSession.PLAYER_ID))
	if look != player.look:
		player.look = look
		player.queue_redraw()


## Loads the map the player is on (start of game, after a bus trip, after loading a save) and
## places the player at the spawn of their last arrival location.
func sync_map() -> void:
	var map_id := session.locations.get_map_id(SimulationSession.PLAYER_ID)
	if map_id == map.get("id", ""):
		return
	map = session.content.get_record("maps", map_id)
	_build_map()
	var location_id := session.locations.get_location_id(SimulationSession.PLAYER_ID)
	var spawn := CityMapBuilder.spawn_tile(map, location_id)
	if spawn.x < 0:
		push_error("CityWorld: map '%s' has no spawn for '%s'" % [map["id"], location_id])
		spawn = Vector2i(1, 1)
	if can_stand_on(_start_tile):
		spawn = _start_tile
	_start_tile = Vector2i(-1, -1)
	player.position = CityMapBuilder.tile_center(map, spawn)
	player.set_camera_limits(camera_bounds())
	map_changed.emit(map_id)


## Ground, decals and every y-sorted visual (structures, trees, interactables) of `map`.
func _build_map() -> void:
	CityMapBuilder.populate(ground, map)
	markings.setup(map)
	for c in entities.get_children():
		if c != player:
			entities.remove_child(c)
			c.queue_free()
	structures.clear()
	npcs.clear()
	ambient.clear()
	_npc_presence = {}
	var ts: int = map["tile_size"]
	for record: Dictionary in map["structures"]:
		var sv := StructureVisual.new()
		sv.setup(record, ts)
		entities.add_child(sv)
		structures.append(sv)
	for cell in CityMapBuilder.cells_of_kind(map, "tree"):
		var tree := PropVisual.new()
		tree.setup("tree", CityMapBuilder.tile_foot(map, cell), "tree_%d_%d" % [cell.x, cell.y])
		entities.add_child(tree)
	for record: Dictionary in map["interactables"]:
		var it := Interactable.new()
		it.setup(record, ts)
		entities.add_child(it)
	var lamps: Array[Vector2] = []
	for d: Dictionary in map.get("decor", []):
		if d["kind"] == "lamp":
			lamps.append(CityMapBuilder.tile_foot(map, Vector2i(d["tile"][0], d["tile"][1])))
	day_night.set_sources(lamps, map.get("indoor", false))
	day_night.update(session.world.clock.get_minute_of_day())
	for i in (map.get("furniture", []) as Array).size():
		var f := FurnitureVisual.new()
		f.setup(map["furniture"][i], ts, i)
		entities.add_child(f)
	for i in (map.get("decor", []) as Array).size():
		var d: Dictionary = map["decor"][i]
		var prop := PropVisual.new()
		prop.setup(d["kind"], CityMapBuilder.tile_foot(map, Vector2i(d["tile"][0], d["tile"][1])), "%s_%d" % [d["kind"], i])
		entities.add_child(prop)
	_refresh_ambient()


## Shows the NPCs whose schedule puts them on this map now (T013), next to their location's
## anchor (the location's spawn tile), using the first free walkable neighbouring tile.
func _refresh_npcs() -> void:
	var present := session.present_npcs()
	if present == _npc_presence:
		return
	_npc_presence = present
	for id: String in npcs.keys():
		entities.remove_child(npcs[id])
		npcs[id].queue_free()
	npcs.clear()
	var used := {}
	var ids := present.keys()
	ids.sort()
	for npc_id: String in ids:
		# A map anchor (behind the counter, at a table) wins over standing next to the spawn.
		var placed := map_anchor(present[npc_id])
		if not placed.is_empty() and not used.has(placed["tile"]):
			used[placed["tile"]] = true
			var at := NpcActor.new()
			at.setup_npc(session.content.get_record("npcs", npc_id), present[npc_id], placed["tile"], map["tile_size"],
				placed["pose"], placed["facing"])
			entities.add_child(at)
			npcs[npc_id] = at
			continue
		var anchor := CityMapBuilder.spawn_tile(map, present[npc_id])
		if anchor.x < 0:
			continue
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var tile: Vector2i = anchor + offset
			if used.has(tile) or not ContentSchemas.is_walkable_kind(CityMapBuilder.tile_kind_at(map, tile)):
				continue
			used[tile] = true
			var actor := NpcActor.new()
			actor.setup_npc(session.content.get_record("npcs", npc_id), present[npc_id], tile, map["tile_size"])
			entities.add_child(actor)
			npcs[npc_id] = actor
			break


## Street ends (`walk_in` doors): stepping onto one walks on into the next district.
func _check_walk_in_doors() -> void:
	var tile := player_tile()
	if tile == _last_tile:
		return
	_last_tile = tile
	for it: Dictionary in map["interactables"]:
		if it.get("walk_in", false) and Vector2i(it["tile"][0], it["tile"][1]) == tile:
			session.submit(UseDoorHandler.ACTION, {"door_id": it["id"]})
			return


## Camera limits: the map, grown symmetrically when it is smaller than the view (shop
## interiors), so small rooms sit centred on screen instead of in a corner.
func camera_bounds() -> Rect2i:
	var size := CityMapBuilder.pixel_size(map)
	var view := Vector2i(get_viewport_rect().size / player.get_camera_zoom())
	var grow := Vector2i(maxi(view.x - size.x, 0), maxi(view.y - size.y, 0))
	return Rect2i(-grow / 2, size + grow)


## {tile, pose, facing} of the map's anchor for a location, or {}.
func map_anchor(location_id: String) -> Dictionary:
	for a: Dictionary in map.get("anchors", []):
		if a["location_id"] == location_id:
			return {"tile": Vector2i(a["tile"][0], a["tile"][1]), "pose": a.get("pose", "stand"),
				"facing": a.get("facing", "down")}
	return {}


## Park regulars come and go with their activity's hours (presentation only).
func _refresh_ambient() -> void:
	var mod := session.world.clock.get_minute_of_day()
	for record: Dictionary in map.get("ambient", []):
		var id: String = record["id"]
		var visible_now := AmbientActor.is_visible_at(record, session.content, mod)
		if visible_now and not ambient.has(id):
			var actor := AmbientActor.new()
			actor.setup(record, map)
			entities.add_child(actor)
			ambient[id] = actor
		elif not visible_now and ambient.has(id):
			entities.remove_child(ambient[id])
			ambient[id].queue_free()
			ambient.erase(id)


func get_structure(structure_id: String) -> StructureVisual:
	for st in structures:
		if st.name == structure_id:
			return st
	return null


func tile_center(tile: Vector2i) -> Vector2:
	return CityMapBuilder.tile_center(map, tile)


## Tile under the player's feet (saved as presentation state).
func player_tile() -> Vector2i:
	var ts := float(map["tile_size"])
	return Vector2i(floori(player.position.x / ts), floori(player.position.y / ts))


## A saved tile is only reused if the player could actually stand there on the current map
## (maps may change between versions): walkable, outside buildings, not an interactable's tile.
func can_stand_on(tile: Vector2i) -> bool:
	if tile.x < 0 or map.is_empty():
		return false
	if not ContentSchemas.is_walkable_kind(CityMapBuilder.tile_kind_at(map, tile)) or CityMapBuilder.in_structure(map, tile):
		return false
	for record: Dictionary in map["interactables"]:
		if Vector2i(record["tile"][0], record["tile"][1]) == tile:
			return false
	return true


func _adopt_global_session() -> void:
	var gs := get_node_or_null("/root/GameSession")
	if gs == null:
		return
	if gs.session == null:
		var r: Dictionary = gs.start_new_game()
		if not r["ok"]:
			push_error("CityWorld: cannot start a game: [%s] %s" % [r["error_code"], r["message"]])
			return
	session = gs.session
	bus = get_node_or_null("/root/EventBus")
	_start_tile = gs.take_pending_player_tile()


func _on_interact_requested(target: Interactable) -> void:
	if ui.is_modal():
		return
	interacted.emit(target.get_interactable_id())
	var location_id: String = target.data["location_id"]
	match target.get_kind():
		"sign":
			ui.open_message(target.get_display_name(), tr(target.data["text_key"]))
		"shop":
			var shop_id: String = target.data["shop_id"]
			var shift := ui.startable_shift(location_id)
			if shift.is_empty():
				ui.open_shop(shop_id)
			else:
				var job := session.content.get_record("jobs", shift["job_id"])
				ui.open_menu(target.get_display_name(), [
					["Work", Localizer.text("ui.menu.work", {"job": tr(job["name_key"])}), ui.open_work.bind(location_id)],
					["Shop", tr("ui.menu.shop"), ui.open_shop.bind(shop_id)]])
		"activity":
			if target.data.has("activity_ids"):
				ui.open_activity_menu(target.get_display_name(), target.data["activity_ids"])
			else:
				ui.open_activity(target.data["activity_id"])
		"home":
			ui.open_home(location_id)
		"job_board":
			ui.open_job_board()
		"transit":
			ui.open_transit(location_id, tr(target.data["text_key"]) if target.data.has("text_key") else "")
		"workplace":
			ui.open_work(location_id)
		"barber":
			ui.open_barber(target.data)
		"door":
			var r := session.submit(UseDoorHandler.ACTION, {"door_id": target.get_interactable_id()})
			if not r.ok:
				ui.open_message(target.get_display_name(), ui.error_text(r.error_code))
		"npc":
			ui.open_npc(target.data["id"])
