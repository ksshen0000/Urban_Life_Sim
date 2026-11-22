class_name TimeFlow
extends RefCounted
## The one way game time passes inside a command (exploration ticks, sleep, eating, later work and
## travel). Advances the authoritative clock, emits its time_advanced/day_changed events, and lets
## every world component that implements the hooks react, in registration order:
##   on_time_passed(ctx, minutes: int, mode: String, context: Dictionary)
##                                                      once per segment (segments split at midnight);
##                                                      context carries e.g. a job's work rates
##   on_day_started(ctx, day_index: int)                at each midnight crossed (rent etc., T011)
## Because this runs inside the command transaction, a later failure rolls all of it back.

const MODE_AWAKE := "awake"
const MODE_RESTING := "resting"
const MODE_SLEEPING := "sleeping"
const MODE_WORKING := "working"


static func advance(ctx: CommandContext, minutes: int, mode: String, context: Dictionary = {}) -> String:
	if not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	if not ContentSchemas.TIME_MODES.has(mode):
		return "E_UNKNOWN_TIME_MODE"
	var r := ctx.world.clock.advance_minutes(minutes)
	if not r["ok"]:
		return r["error_code"]
	var listeners: Array[RefCounted] = []
	for component_name in ctx.world.get_component_names():
		var c := ctx.world.get_component(component_name)
		if c.has_method("on_time_passed") or c.has_method("on_day_started"):
			listeners.append(c)
	for draft: Dictionary in r["events"]:
		ctx.time_cursor = draft["game_minute"]
		ctx.emit(draft["type"], draft["payload"])
		if draft["type"] == "time_advanced":
			var span: int = draft["payload"]["new_minute"] - draft["payload"]["old_minute"]
			for c in listeners:
				if c.has_method("on_time_passed"):
					c.on_time_passed(ctx, span, mode, context)
		elif draft["type"] == "day_changed":
			for c in listeners:
				if c.has_method("on_day_started"):
					c.on_day_started(ctx, draft["payload"]["day_index"])
	ctx.time_cursor = -1
	return ""
