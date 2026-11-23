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
## NPCs the player is currently standing near (approach_npc already sent for this visit).
var _near: Dictionary = {}
const APPROACH_TILES := 2.5
const LEAVE_TILES := 4.0
## Greeting cutscene (D-036): an NPC with a face-to-face story beat notices the player within
## SIGHT_TILES, a "!" pops up, the player is held in place and the NPC walks over.
const SIGHT_TILES := 16.0
const ALERT_SECONDS := 0.7
var greeting: NpcActor = null
var _greet_phase := ""          # "alert" | "walk" | "talk" | "return"
var _greet_timer := 0.0
var _greet_home := Vector2.ZERO
var _greeted: Dictionary = {}   # npc_id -> true (once per map visit)
var _blocked: Dictionary = {}   # Vector2i -> true: furniture footprints
var ambient: Dictionary = {}  # ambient id -> AmbientActor currently shown
var pedestrians: Dictionary = {}  # pedestrian id -> Pedestrian currently walking
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
	player.speed_factor = NeedStates.walk_factor(session.need_states())
	_update_greeting(delta)
	if not ui.is_modal():
		if session.dialogue.has_pending():
			ui.open_story_entry(session.dialogue.peek())
		elif greeting == null or _greet_phase == "return":
			# free roaming (a greeting NPC walking back home does not hold the player)
			_check_walk_in_doors()
			_check_npc_approach()
			if greeting == null:
				_check_greetings()
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
	_near.clear()
	_greeted.clear()
	_blocked.clear()
	_end_greeting()
	ambient.clear()
	pedestrians.clear()
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
	for fr: Dictionary in map.get("furniture", []):
		var size: Array = ContentSchemas.FURNITURE[fr["kind"]]
		for dx in int(size[0]):
			_blocked[Vector2i(int(fr["tile"][0]) + dx, int(fr["tile"][1]))] = true
	for i in (map.get("furniture", []) as Array).size():
		var f := FurnitureVisual.new()
		f.setup(map["furniture"][i], ts, i)
		entities.add_child(f)
	# One label per street end ("往新河里 →"), above the first of its walk-in tiles.
	var labelled := {}
	for record: Dictionary in map["interactables"]:
		if record.get("walk_in", false) and not labelled.has(record["target_location_id"]):
			labelled[record["target_location_id"]] = true
			var text := tr(record["name_key"])
			var w := WorldText.measure(text, 12) + 14.0
			var foot := CityMapBuilder.tile_foot(map, Vector2i(record["tile"][0], record["tile"][1]))
			var x := foot.x - w if int(record["tile"][0]) > 0 else foot.x - 16.0
			var label := WorldText.make(text, Rect2(x, foot.y - ts - 26, w, 18), 12, Color("#fbf7ec"), Color(0.08, 0.07, 0.1, 0.6))
			label.name = "ExitLabel_" + str(record["id"])
			entities.add_child(label)
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


func _check_greetings() -> void:
	if not session.story_enabled or Engine.get_process_frames() % 6 != 0:
		return
	var ts: float = map["tile_size"]
	var best: NpcActor = null
	var best_d := INF
	for npc_id in session.events.greeting_npcs(session.world):
		if _greeted.has(npc_id) or not npcs.has(npc_id):
			continue
		var d: float = (npcs[npc_id] as Node2D).position.distance_to(player.position) / ts
		if d <= SIGHT_TILES and d < best_d:
			best = npcs[npc_id]
			best_d = d
	if best != null:
		_start_greeting(best)


func _start_greeting(npc: NpcActor) -> void:
	greeting = npc
	_greeted[npc.npc_id] = true
	_greet_home = npc.position
	_greet_phase = "alert"
	_greet_timer = ALERT_SECONDS
	npc.alert = true
	npc.face_towards(player.position)
	player.locked = true
	session.world.clock.push_pause("greeting")


func _update_greeting(delta: float) -> void:
	if greeting == null:
		return
	if not is_instance_valid(greeting):
		_end_greeting()
		return
	match _greet_phase:
		"alert":
			_greet_timer -= delta
			if _greet_timer <= 0.0:
				greeting.alert = false
				greeting.queue_redraw()
				_greet_phase = "walk"
				greeting.walk_path(path_points(_tile_of(greeting.position), player_tile(), true))
		"walk":
			if not greeting.is_walking():
				greeting.face_towards(player.position)
				_face_player_towards(greeting.position)
				_greet_phase = "talk"
				session.world.clock.pop_pause("greeting")
				session.submit(ApproachNpcHandler.ACTION, {"npc_id": greeting.npc_id})
				_near[greeting.npc_id] = true
				_greet_timer = 0.3
		"talk":
			# the story entry opens on its own (pending dialogue); wait until it is answered
			_greet_timer -= delta
			if _greet_timer <= 0.0 and not ui.is_modal() and not session.dialogue.has_pending():
				player.locked = false
				_greet_phase = "return"
				greeting.walk_path(path_points(_tile_of(greeting.position), _tile_of(_greet_home), false))
		"return":
			if not greeting.is_walking():
				greeting.position = _greet_home
				greeting = null
				_greet_phase = ""


func _end_greeting() -> void:
	if greeting != null and _greet_phase in ["alert", "walk"]:
		session.world.clock.pop_pause("greeting")
	greeting = null
	_greet_phase = ""
	player.locked = false


func _face_player_towards(target: Vector2) -> void:
	var d := target - player.position
	player.facing = (Vector2.RIGHT if d.x > 0 else Vector2.LEFT) if absf(d.x) > absf(d.y) else (Vector2.DOWN if d.y > 0 else Vector2.UP)
	player.queue_redraw()


func _tile_of(p: Vector2) -> Vector2i:
	var ts: float = map["tile_size"]
	return Vector2i(floori(p.x / ts), floori((p.y - 1.0) / ts))


func is_free_tile(tile: Vector2i) -> bool:
	return ContentSchemas.is_walkable_kind(CityMapBuilder.tile_kind_at(map, tile)) and not _blocked.has(tile)


## Tile-by-tile path (BFS over free tiles) as world foot positions. With `beside`, ends on the
## free tile next to `goal` that is closest to walk to; otherwise ends on `goal`.
func path_points(from: Vector2i, goal: Vector2i, beside: bool) -> Array[Vector2]:
	var targets := {}
	if beside:
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if is_free_tile(goal + d):
				targets[goal + d] = true
	else:
		targets[goal] = true
	var prev := {from: from}
	var queue: Array[Vector2i] = [from]
	var found := Vector2i(-9999, -9999)
	while not queue.is_empty() and prev.size() < 4000:
		var c: Vector2i = queue.pop_front()
		if targets.has(c):
			found = c
			break
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := c + d
			if not prev.has(n) and (is_free_tile(n) or targets.has(n)):
				prev[n] = c
				queue.append(n)
	var out: Array[Vector2] = []
	if found.x == -9999:
		return out
	var c := found
	while c != from:
		out.push_front(CityMapBuilder.tile_foot(map, c))
		c = prev[c]
	return out


## Walking up to an NPC is a fact the story can use (face-to-face introductions, D-036): sent
## once when the player comes within APPROACH_TILES, again only after walking away past LEAVE_TILES.
func _check_npc_approach() -> void:
	var ts: float = map["tile_size"]
	for npc_id: String in npcs:
		var d: float = (npcs[npc_id] as Node2D).position.distance_to(player.position) / ts
		if d <= APPROACH_TILES and not _near.has(npc_id):
			_near[npc_id] = true
			session.submit(ApproachNpcHandler.ACTION, {"npc_id": npc_id})
		elif d > LEAVE_TILES and _near.has(npc_id):
			_near.erase(npc_id)


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


## Park regulars come and go with their activity's hours (presentation only); so do passers-by.
func _refresh_ambient() -> void:
	var mod := session.world.clock.get_minute_of_day()
	for record: Dictionary in map.get("pedestrians", []):
		var pid: String = record["id"]
		var show_ped := Pedestrian.is_visible_at(record, mod)
		if show_ped and not pedestrians.has(pid):
			var p := Pedestrian.new()
			p.setup_pedestrian(record, map)
			entities.add_child(p)
			pedestrians[pid] = p
		elif not show_ped and pedestrians.has(pid):
			entities.remove_child(pedestrians[pid])
			pedestrians[pid].queue_free()
			pedestrians.erase(pid)
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
		"pedestrian":
			var ped := target as Pedestrian
			ui.open_message(ped.get_display_name(), tr(ped.line_for_day(session.world.clock.get_day_index())))
		"door":
			var r := session.submit(UseDoorHandler.ACTION, {"door_id": target.get_interactable_id()})
			if not r.ok:
				ui.open_message(target.get_display_name(), ui.error_text(r.error_code))
		"npc":
			ui.open_npc(target.data["id"])
