class_name GameClock
extends RefCounted
## Authoritative game time (spec §3.5): integer minutes since Day 1 00:00.
##
## The clock never emits signals. `advance_minutes()` returns ordered event drafts
## ({type, game_minute, payload}); the CommandProcessor turns them into DomainEvents and the
## GameEventBus re-broadcasts `time_advanced` / `day_changed` only after the command commits
## (docs/decisions.md D-007). A multi-day advance is split at every midnight, so listeners see
## each intermediate day in order and per-day settlement can never be skipped.
##
## Pause reasons and the real-time carry are session state (not saved); only `minute` is world state.

const MINUTES_PER_HOUR := 60
const HOURS_PER_DAY := 24
const MINUTES_PER_DAY := MINUTES_PER_HOUR * HOURS_PER_DAY
## Upper bound for one advance; protects against event storms from bad input (spec §13.4).
const MAX_ADVANCE_MINUTES := 30 * MINUTES_PER_DAY
const SCHEMA_VERSION := 1
const STATE_SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"minute": {"type": "int", "required": true, "min": 0},
}}

var _minute: int = 0
var _pause_reasons: Dictionary = {}
var _minutes_per_real_second: float = 1.0
var _real_time_carry: float = 0.0


func _init(start_minute: int = 0) -> void:
	_minute = maxi(start_minute, 0)


# --- pure time math -----------------------------------------------------------------------

static func minute_from_day_time(day_index: int, hour: int, minute: int = 0) -> int:
	return (day_index - 1) * MINUTES_PER_DAY + hour * MINUTES_PER_HOUR + minute


@warning_ignore("integer_division")
static func day_index_of(game_minute: int) -> int:
	return game_minute / MINUTES_PER_DAY + 1


static func minute_of_day_of(game_minute: int) -> int:
	return game_minute % MINUTES_PER_DAY


## Calendar key used by RegionPolicy.get_calendar_modifiers ("day_7"). A real-date calendar
## (holidays, weekdays) can replace this later without touching callers.
static func date_key_of(day_index: int) -> String:
	return "day_%d" % day_index


## Debug/log label such as "D2 00:20". Player-facing formatting belongs to the UI layer.
@warning_ignore("integer_division")
static func format_debug(game_minute: int) -> String:
	var mod := minute_of_day_of(game_minute)
	return "D%d %02d:%02d" % [day_index_of(game_minute), mod / MINUTES_PER_HOUR, mod % MINUTES_PER_HOUR]


# --- queries ------------------------------------------------------------------------------

func get_minute() -> int:
	return _minute


func get_day_index() -> int:
	return day_index_of(_minute)


func get_minute_of_day() -> int:
	return minute_of_day_of(_minute)


@warning_ignore("integer_division")
func get_hour() -> int:
	return get_minute_of_day() / MINUTES_PER_HOUR


# --- mutation (call only from command handlers) -------------------------------------------

## Returns {ok, error_code, events}. On error nothing changes.
func advance_minutes(minutes: int) -> Dictionary:
	if minutes < 0:
		return {"ok": false, "error_code": "E_NEGATIVE_MINUTES", "events": []}
	if minutes > MAX_ADVANCE_MINUTES:
		return {"ok": false, "error_code": "E_ADVANCE_TOO_LARGE", "events": []}
	var events: Array[Dictionary] = []
	var target := _minute + minutes
	while _minute < target:
		var next_midnight := day_index_of(_minute) * MINUTES_PER_DAY
		var segment_end := mini(target, next_midnight)
		var old := _minute
		_minute = segment_end
		events.append({"type": "time_advanced", "game_minute": segment_end,
			"payload": {"old_minute": old, "new_minute": segment_end}})
		if segment_end == next_midnight:
			events.append({"type": "day_changed", "game_minute": segment_end,
				"payload": {"day_index": day_index_of(segment_end)}})
	return {"ok": true, "error_code": null, "events": events}


# --- real-time flow (session state) -------------------------------------------------------

## Reasons are a set: pushing the same reason twice needs one pop.
func push_pause(reason: String) -> void:
	_pause_reasons[reason] = true


func pop_pause(reason: String) -> void:
	_pause_reasons.erase(reason)


func is_paused() -> bool:
	return not _pause_reasons.is_empty()


func get_pause_reasons() -> PackedStringArray:
	var out := PackedStringArray(_pause_reasons.keys())
	out.sort()
	return out


func set_minutes_per_real_second(rate: float) -> bool:
	if is_nan(rate) or is_inf(rate) or rate <= 0.0:
		return false
	_minutes_per_real_second = rate
	return true


func get_minutes_per_real_second() -> float:
	return _minutes_per_real_second


## Converts real seconds of exploration into whole game minutes that are now due.
## Does NOT advance the clock: the session submits an `advance_time` command with the result.
func accumulate_real_time(delta_seconds: float) -> int:
	if is_paused() or is_nan(delta_seconds) or delta_seconds <= 0.0:
		return 0
	_real_time_carry += delta_seconds * _minutes_per_real_second
	var whole := floori(_real_time_carry)
	_real_time_carry -= whole
	return mini(whole, MAX_ADVANCE_MINUTES)


# --- persistence --------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "minute": _minute}


## Returns "" on success or an error code; on error the clock is unchanged.
func from_dict(data: Dictionary) -> String:
	var v := SchemaValidator.new()
	var state: Variant = v.validate(data, STATE_SCHEMA)
	if not v.is_ok():
		return "E_INVALID_CLOCK_STATE"
	_minute = state["minute"]
	return ""
