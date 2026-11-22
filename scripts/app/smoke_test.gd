class_name SmokeTest
extends Node
## Release smoke test (T020): `EverydayCity --headless -- --smoke-test` (or with the editor binary:
## `godot --headless --main-pack EverydayCity.pck -- --smoke-test`). Starts a new game through the
## real title screen path, loads the city scene, plays a few commands, saves to a private folder,
## loads it back, compares, cleans up and exits 0 ("SMOKE OK") or 1 ("SMOKE FAIL ...").
## Never touches the player's saves or settings.

const ARG := "--smoke-test"
const DIR := "user://smoke_test"
const WORLD_SCENE := "res://scenes/world/city_world.tscn"


static func requested() -> bool:
	return OS.get_cmdline_user_args().has(ARG)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	var gs := tree.root.get_node_or_null("GameSession")
	if gs == null:
		return _finish(false, "GameSession autoload missing")
	gs.saves = SaveManager.new(DIR)
	var r: Dictionary = gs.start_new_game()
	if not r["ok"]:
		return _finish(false, "new game: %s %s" % [r["error_code"], r["message"]])
	tree.change_scene_to_file(WORLD_SCENE)
	for i in 30:
		await tree.process_frame
	if not (tree.current_scene is CityWorld):
		return _finish(false, "city scene did not load")
	var s: SimulationSession = gs.session
	for step: Array in [["sign_lease", {"housing_id": "home_shared_room_01"}],
			["buy_item", {"shop_id": "shop_fast_food", "item_id": "item_simple_meal", "quantity": 1}],
			["use_item", {"item_id": "item_simple_meal"}]]:
		var c := s.submit(step[0], step[1])
		if not c.ok:
			return _finish(false, "%s: %s" % [step[0], c.error_code])
	var w: Dictionary = gs.save_game("slot_01")
	if not w["ok"]:
		return _finish(false, "save: %s %s" % [w["error_code"], w["message"]])
	var before := JSON.stringify(s.world.to_dict(), "", true)
	var l: Dictionary = gs.load_game("slot_01")
	if not l["ok"]:
		return _finish(false, "load: %s %s" % [l["error_code"], l["message"]])
	if JSON.stringify(gs.session.world.to_dict(), "", true) != before:
		return _finish(false, "loaded world differs from saved world")
	_finish(true, "content packs %d, day %d, cash %d" % [gs.content.get_pack_ids().size(),
		gs.session.world.clock.get_day_index(), gs.session.economy.get_balance(SimulationSession.PLAYER_ID)])


func _finish(ok: bool, detail: String) -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))
		DirAccess.remove_absolute(DIR)
	if ok:
		print("SMOKE OK: ", detail)
	else:
		printerr("SMOKE FAIL: ", detail)
	get_tree().quit(0 if ok else 1)
