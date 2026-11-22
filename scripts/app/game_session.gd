extends Node
## Autoload `GameSession`: holds the validated content and the running SimulationSession across
## scene changes, installs localization and connects the `EventBus` autoload to the session's
## command processor. One of the few allowed singletons (spec §0: session / event bus / save).

const SETTING_CONTENT_ROOT := "everyday_city/content/root"
const SETTING_DEFAULT_CITY := "everyday_city/content/default_city_id"

var content: ContentRegistry
var session: SimulationSession
var saves := SaveManager.new()
## Where the player should stand when the world scene next builds the map after a load
## (presentation only; Vector2i(-1, -1) = the spawn of the arrival location).
var pending_player_tile := Vector2i(-1, -1)


## Accepts content already validated elsewhere (the boot self-check).
func adopt_content(p_content: ContentRegistry) -> void:
	content = p_content
	Localizer.install(content, GameSettings.current["locale"])


func default_city_id() -> String:
	return ProjectSettings.get_setting(SETTING_DEFAULT_CITY, "")


## Returns {ok, error_code, message}.
## `player_profile` = {name, look} from the character creator (default look when empty).
func start_new_game(city_id: String = "", player_profile: Dictionary = {}) -> Dictionary:
	var loaded := _ensure_content()
	if not loaded["ok"]:
		return loaded
	if city_id.is_empty():
		city_id = default_city_id()
	var overrides := {}
	if not player_profile.is_empty():
		overrides["player_profile"] = player_profile
	var r := SimulationSession.create_new(content, RegionPolicyRegistry.with_builtin_implementations(), city_id, overrides)
	if not r["ok"]:
		return {"ok": false, "error_code": r["error_code"], "message": r["message"]}
	_install(r["session"], Vector2i(-1, -1))
	session.run_story_rules()  # e.g. the arrival scene on day 1
	return {"ok": true, "error_code": null, "message": ""}


## Writes the running game to `slot_id` (T017). Returns {ok, error_code, message}.
func save_game(slot_id: String, player_tile: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	if session == null:
		return {"ok": false, "error_code": "E_NO_GAME", "message": "no game running"}
	var r := saves.save_session(slot_id, session, player_tile)
	if r["ok"]:
		var bus := get_node_or_null("/root/EventBus") as GameEventBus
		if bus != null:
			bus.save_completed.emit(slot_id)
	return r


## Replaces the running game with the one in `slot_id`. On any error the running game (if any)
## stays exactly as it was. Returns {ok, error_code, message, warnings}.
func load_game(slot_id: String) -> Dictionary:
	var loaded := _ensure_content()
	if not loaded["ok"]:
		return loaded
	var r := saves.load_slot(slot_id, content, RegionPolicyRegistry.with_builtin_implementations())
	if not r["ok"]:
		push_warning("load %s failed: [%s] %s" % [slot_id, r["error_code"], r["message"]])
		return {"ok": false, "error_code": r["error_code"], "message": r["message"], "warnings": PackedStringArray()}
	for w: String in r["warnings"]:
		push_warning("load %s: %s" % [slot_id, w])
	_install(r["session"], r["player"]["tile"])
	return {"ok": true, "error_code": null, "message": "", "warnings": r["warnings"]}


## Consumed by the world scene once it has placed the player.
func take_pending_player_tile() -> Vector2i:
	var t := pending_player_tile
	pending_player_tile = Vector2i(-1, -1)
	return t


func _install(new_session: SimulationSession, player_tile: Vector2i) -> void:
	end_game()
	session = new_session
	pending_player_tile = player_tile
	# The interface language is a player setting; the city's `language` is its content source language.
	Localizer.install(content, GameSettings.current["locale"])
	var bus := get_node_or_null("/root/EventBus") as GameEventBus
	if bus != null:
		bus.attach(session.processor)


func _ensure_content() -> Dictionary:
	if content == null:
		var c := ContentRegistry.new()
		if not c.load_root(ProjectSettings.get_setting(SETTING_CONTENT_ROOT, "res://content")):
			return {"ok": false, "error_code": "E_CONTENT_INVALID", "message": "\n".join(c.get_error_strings())}
		adopt_content(c)
	return {"ok": true, "error_code": null, "message": ""}


## Shutdown: release every static cache (textures, tile atlases, sounds, translations) while the
## engine is still running, so nothing is reported as leaked at exit.
func _exit_tree() -> void:
	end_game()
	content = null
	release_static_caches()


static func release_static_caches() -> void:
	PixelArt.clear_cache()
	CityMapBuilder.clear_cache()
	UiSound.clear_cache()
	DayNight.release_static()
	Localizer.uninstall()
	SchemaValidator.clear_cache()


func end_game() -> void:
	if session == null:
		return
	var bus := get_node_or_null("/root/EventBus") as GameEventBus
	if bus != null:
		bus.detach(session.processor)
	session = null
