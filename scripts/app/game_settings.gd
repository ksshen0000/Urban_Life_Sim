class_name GameSettings
extends RefCounted
## Player settings (T019): volumes, window size, interface language. Stored in
## `user://settings.cfg` (a ConfigFile of plain values, separate from saves: settings belong to
## the machine, not to a game). Unknown or out-of-range values fall back to defaults.
## Settings never affect game rules.

const PATH := "user://settings.cfg"
const SECTION := "settings"
const SFX_BUS := "SFX"

const WINDOW_MODES: PackedStringArray = ["window_1280", "window_1600", "window_1920", "fullscreen"]
const WINDOW_SIZES := {"window_1280": Vector2i(1280, 720), "window_1600": Vector2i(1600, 900),
	"window_1920": Vector2i(1920, 1080)}
const LOCALES: PackedStringArray = ["zh_CN", "en"]

const DEFAULTS := {
	"master_volume": 80,  # percent
	"sfx_volume": 80,
	"window_mode": "window_1280",
	"locale": "zh_CN",
}

## The settings currently applied (after load / set).
static var current: Dictionary = DEFAULTS.duplicate()
## Where set_value() writes (tests point this elsewhere so they never touch the player's file).
static var storage_path := PATH


## Every key present, every value valid.
static func sanitize(raw: Dictionary) -> Dictionary:
	var out := DEFAULTS.duplicate()
	for key in ["master_volume", "sfx_volume"]:
		var v: Variant = raw.get(key)
		if typeof(v) in [TYPE_INT, TYPE_FLOAT] and not is_nan(float(v)):
			out[key] = clampi(roundi(float(v)), 0, 100)
	if WINDOW_MODES.has(str(raw.get("window_mode", ""))):
		out["window_mode"] = str(raw["window_mode"])
	if LOCALES.has(str(raw.get("locale", ""))):
		out["locale"] = str(raw["locale"])
	return out


static func load_from(path: String = PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return DEFAULTS.duplicate()
	var raw := {}
	for key: String in DEFAULTS:
		raw[key] = cfg.get_value(SECTION, key, DEFAULTS[key])
	return sanitize(raw)


static func save_to(settings: Dictionary, path: String = PATH) -> Error:
	var cfg := ConfigFile.new()
	var s := sanitize(settings)
	for key: String in s:
		cfg.set_value(SECTION, key, s[key])
	return cfg.save(path)


## Loads, applies and remembers the stored settings (boot).
static func load_and_apply(path: String = "") -> Dictionary:
	current = load_from(path if not path.is_empty() else storage_path)
	apply(current)
	return current


## Changes one setting: applies it, remembers it and writes the file.
static func set_value(key: String, value: Variant) -> Dictionary:
	var next := current.duplicate()
	next[key] = value
	current = sanitize(next)
	apply(current)
	save_to(current, storage_path)
	return current


static func apply(settings: Dictionary) -> void:
	var s := sanitize(settings)
	ensure_buses()
	AudioServer.set_bus_volume_db(0, percent_to_db(s["master_volume"]))
	AudioServer.set_bus_mute(0, s["master_volume"] == 0)
	var sfx := AudioServer.get_bus_index(SFX_BUS)
	AudioServer.set_bus_volume_db(sfx, percent_to_db(s["sfx_volume"]))
	AudioServer.set_bus_mute(sfx, s["sfx_volume"] == 0)
	TranslationServer.set_locale(s["locale"])
	_apply_window(s["window_mode"])


static func ensure_buses() -> void:
	if AudioServer.get_bus_index(SFX_BUS) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, SFX_BUS)
	AudioServer.set_bus_send(i, "Master")


## 100% = 0 dB, 50% ≈ -6 dB (perceptual-ish linear amplitude), 0% = silent.
static func percent_to_db(percent: int) -> float:
	return linear_to_db(maxf(float(percent) / 100.0, 0.0001))


static func _apply_window(mode: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if mode == "fullscreen":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var size: Vector2i = WINDOW_SIZES[mode]
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	# Never open a window larger than the screen (a 1920×1080 window on a 1366×768 laptop).
	if screen.size.x > 0 and (size.x > screen.size.x or size.y > screen.size.y):
		var k := minf(float(screen.size.x) / size.x, float(screen.size.y) / size.y) * 0.95
		size = Vector2i(roundi(size.x * k), roundi(size.y * k))
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
