extends "res://tests/framework/test_case.gd"
## D-033 character creator: the profile component (validation, saves, v1 -> v2 migration), the
## creator UI, the title-screen flow and the mirror at home.

const Sessions := preload("res://tests/framework/session_factory.gd")
const WORLD_SCENE := preload("res://scenes/world/city_world.tscn")
const BOOT_SCENE := preload("res://scenes/boot/boot.tscn")
const P := SimulationSession.PLAYER_ID

var nodes: Array[Node] = []


func after_each() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()
	await wait_process_frames(2)
	(Engine.get_main_loop() as SceneTree).paused = false


func _look(overrides: Dictionary = {}) -> Dictionary:
	var l := ProfileSystem.DEFAULT_LOOK.duplicate()
	l.merge(overrides, true)
	return l


func test_new_game_profile() -> void:
	var s := Sessions.create()
	assert_eq(s.profile.get_look(P), ProfileSystem.DEFAULT_LOOK, "default look without the creator")
	var mine := {"name": "小林", "look": _look({"figure": "f", "hair_style": "bob", "outfit": "dress", "top": "#e07aa0"})}
	var s2 := Sessions.create({"player_profile": mine})
	assert_eq(s2.profile.get_profile(P), mine)
	var bad := SimulationSession.create_new(Sessions.content(), RegionPolicyRegistry.with_builtin_implementations(),
		"CN_LINCHUAN", {"player_profile": {"name": "x", "look": _look({"hair_style": "mohawk"})}})
	assert_false(bad["ok"])
	assert_eq(bad["error_code"], "E_INVALID_PROFILE")


func test_profile_validation() -> void:
	assert_eq(ProfileSystem.validate_profile({"name": "", "look": _look()}), "")
	for broken: Dictionary in [
			{"name": "名字实在是太长了超过十二个字了啊", "look": _look()},
			{"name": "a\u0007b", "look": _look()},
			{"name": "a", "look": _look({"top": "blue"})},
			{"name": "a", "look": _look({"outfit": "armor"})},
			{"name": "a", "look": _look({"figure": "x"})},
			{"name": "a"}]:
		assert_eq(ProfileSystem.validate_profile(broken), "E_INVALID_PROFILE", str(broken))


func test_mirror_command_needs_home() -> void:
	var s := Sessions.create()
	var p := {"name": "阿明", "look": _look({"hair_style": "buzz"})}
	assert_eq(s.submit("set_profile", p).error_code, "E_NO_HOME")
	s.submit("sign_lease", {"housing_id": "home_shared_room_01"})
	assert_true(s.submit("set_profile", p).ok)
	assert_eq(s.profile.get_display_name(P), "阿明")
	assert_eq(s.submit("set_profile", {"name": "x", "look": _look({"skin": "#zzzzzz"})}).error_code, "E_INVALID_PROFILE")
	assert_eq(s.profile.get_look(P)["hair_style"], "buzz", "unchanged by the rejected command")


func test_profile_saved_and_v1_saves_migrate() -> void:
	var s := Sessions.create({"player_profile": {"name": "小林", "look": _look({"hair_style": "long", "figure": "f"})}})
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveManager.build(s)))
	var r := SaveManager.restore(s.content, RegionPolicyRegistry.with_builtin_implementations(), data)
	assert_true(r["ok"])
	assert_eq((r["session"] as SimulationSession).profile.get_profile(P), s.profile.get_profile(P))
	# The same save as the v1 format had it: no profile component.
	var v1: Dictionary = JSON.parse_string(JSON.stringify(SaveManager.build(s)))
	v1["save_schema_version"] = 1
	(v1["world"]["components"] as Dictionary).erase("profile")
	(v1["summary"] as Dictionary).erase("player_name")
	var old := SaveManager.restore(s.content, RegionPolicyRegistry.with_builtin_implementations(), v1)
	assert_true(old["ok"], "v1 save loads: %s" % old["message"])
	assert_eq((old["session"] as SimulationSession).profile.get_look(P), ProfileSystem.DEFAULT_LOOK)
	assert_eq((old["session"] as SimulationSession).economy.get_balance(P), s.economy.get_balance(P))


func _creator() -> CharacterCreator:
	var c := CharacterCreator.make({}, "ui.creator.title", "ui.creator.start")
	(Engine.get_main_loop() as SceneTree).root.add_child(c)
	nodes.append(c)
	return c


func test_creator_edits_a_valid_profile() -> void:
	Localizer.install(Sessions.content())
	var c := _creator()
	await wait_process_frames(2)
	var result := []
	c.confirmed.connect(func(p: Dictionary) -> void: result.append(p))
	(c.find_child("Gender_f", true, false) as Button).pressed.emit()
	assert_eq(c.profile["look"]["figure"], "f")
	assert_eq(c.profile["look"]["hair_style"], "ponytail", "suggested hair")
	assert_eq(c.profile["look"]["outfit"], "skirt", "suggested outfit")
	(c.find_child("HairNext", true, false) as Button).pressed.emit()
	assert_eq(c.profile["look"]["hair_style"], "bun")
	(c.find_child("Swatch_top_2", true, false) as Button).pressed.emit()
	assert_eq(c.profile["look"]["top"], CharacterCreator.TOP[2])
	(c.find_child("Outfit_dress", true, false) as Button).pressed.emit()
	assert_true((c.find_child("Outfit_dress", true, false) as Button).button_pressed, "selection shown")
	assert_false((c.find_child("Outfit_skirt", true, false) as Button).button_pressed)
	(c.find_child("NameEdit", true, false) as LineEdit).text = "  小雪 "
	(c.find_child("Confirm", true, false) as Button).pressed.emit()
	assert_eq(result.size(), 1)
	assert_eq(result[0]["name"], "小雪")
	assert_eq(ProfileSystem.validate_profile(result[0]), "")
	for i in 20:
		c.randomize_look()
		assert_eq(ProfileSystem.validate_profile(c.profile), "", "random look %d valid" % i)
	assert_not_null((c.find_child("Preview", true, false) as TextureRect).texture, "live preview")


func test_title_screen_new_game_opens_creator() -> void:
	var boot: Control = BOOT_SCENE.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(boot)
	nodes.append(boot)
	await wait_process_frames(2)
	(boot.find_child("NewGameButton", true, false) as Button).pressed.emit()
	var c := boot.find_child("CharacterCreator", true, false) as CharacterCreator
	assert_not_null(c, "character creator shown before the game starts")
	(c.find_child("Cancel", true, false) as Button).pressed.emit()
	await wait_process_frames(2)
	assert_true(boot.find_child("CharacterCreator", true, false) == null, "back to the title")


func test_mirror_at_home_changes_the_sprite() -> void:
	Localizer.install(Sessions.content())
	var s := Sessions.create()
	s.submit("sign_lease", {"housing_id": "home_shared_room_01"})
	var bus := GameEventBus.new()
	var world: CityWorld = WORLD_SCENE.instantiate()
	world.setup(s, bus)
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	nodes.append(world)
	nodes.append(bus)
	await wait_physics_frames(2)
	world.ui.open_home("old_town_apartment")
	(world.ui.get_panel_content().find_child("Mirror", true, false) as Button).pressed.emit()
	var m := world.ui.get_mirror()
	assert_not_null(m)
	await wait_process_frames(1)
	assert_true((Engine.get_main_loop() as SceneTree).paused, "time stops at the mirror")
	(m.find_child("Swatch_hair_4", true, false) as Button).pressed.emit()
	(m.find_child("Confirm", true, false) as Button).pressed.emit()
	await wait_process_frames(2)
	assert_eq(s.profile.get_look(P)["hair"], CharacterCreator.HAIR[4], "saved through set_profile")
	assert_eq(world.player.look["hair"], CharacterCreator.HAIR[4], "sprite updated")
	assert_false((Engine.get_main_loop() as SceneTree).paused)


## A control created but never added to the tree is an orphan that leaks at exit (and pins the
## theme font with its glyph textures): the barber's hair-only creator used to do this.
func test_creator_modes_leave_no_orphan_nodes() -> void:
	Localizer.install(Sessions.content())
	for fields: Array in [[], ["hair_style", "hair"], ["hair"]]:
		await wait_process_frames(2)  # let nodes queued for deletion by earlier tests go first
		var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		var c := CharacterCreator.make({}, "ui.creator.title", "ui.creator.start", fields)
		(Engine.get_main_loop() as SceneTree).root.add_child(c)
		await wait_process_frames(2)
		var during := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		c.free()
		assert_eq(during, before, "no orphan controls with fields %s" % str(fields))
