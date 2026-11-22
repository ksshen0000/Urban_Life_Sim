class_name JobsSystem
extends RefCounted
## Job shifts (T009/T010). A shift is one concrete slot of a job's shift template on one day:
## shift_id = "<job_id>.d<day>.<template_id>". Lifecycle: booked -> in_progress -> completed,
## or booked -> missed when its end passes unworked. A shift is paid at most once: payment
## happens only in the booked -> completed transition (spec §3.6 / T010 PayIdempotency).

const SCHEMA_VERSION := 1
## May arrive up to this early (then wait); must start at least this long before the end.
const ARRIVE_EARLY_MAX_MINUTES := 120
const LATEST_START_BEFORE_END_MINUTES := 30
const BOOKING_DAYS_AHEAD := 1
const STATUSES := ["booked", "in_progress", "completed", "missed"]
const STATE_SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"shifts": {"type": "map", "required": true, "values_spec": {"type": "object", "fields": {
		"actor_id": {"type": "string", "required": true, "min_length": 1},
		"job_id": {"type": "id", "required": true},
		"template_id": {"type": "id", "required": true},
		"day": {"type": "int", "required": true, "min": 1},
		"start_minute": {"type": "int", "required": true, "min": 0},
		"end_minute": {"type": "int", "required": true, "min": 0},
		"status": {"type": "string", "required": true, "values": STATUSES},
		"worked_minutes": {"type": "int", "required": true, "min": 0},
		"late_minutes": {"type": "int", "required": true, "min": 0},
		"gross_minor": {"type": "int", "required": true, "min": 0},
		"net_minor": {"type": "int", "required": true, "min": 0},
	}}},
}}

var _content: ContentRegistry
var _shifts: Dictionary = {}


func _init(content: ContentRegistry = null) -> void:
	_content = content


static func shift_id_for(job_id: String, day: int, template_id: String) -> String:
	return "%s.d%d.%s" % [job_id, day, template_id]


func get_shift(shift_id: String) -> Dictionary:
	var s: Dictionary = (_shifts.get(shift_id, {}) as Dictionary).duplicate()
	if not s.is_empty():
		s["shift_id"] = shift_id
	return s


## Actor's shifts ordered by start time.
func get_shifts(actor_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in _shifts:
		if _shifts[id]["actor_id"] == actor_id:
			out.append(get_shift(id))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["start_minute"] < b["start_minute"])
	return out


func count_with_status(actor_id: String, status: String) -> int:
	var n := 0
	for id: String in _shifts:
		if _shifts[id]["actor_id"] == actor_id and _shifts[id]["status"] == status:
			n += 1
	return n


## Booked shift the actor can start at `location_id` right now ({} if none).
func startable_shift_at(actor_id: String, location_id: String, now: int) -> Dictionary:
	for s in get_shifts(actor_id):
		if s["status"] != "booked":
			continue
		if _content.get_record("jobs", s["job_id"])["workplace_location_id"] != location_id:
			continue
		if check_start(actor_id, s["shift_id"], now).is_empty():
			return s
	return {}


func window(job: Dictionary, day: int, template_id: String) -> Dictionary:
	for t: Dictionary in job["shifts"]:
		if t["id"] == template_id:
			var start := GameClock.minute_from_day_time(day, 0) + int(t["start_minute_of_day"])
			return {"start": start, "end": start + int(t["duration_minutes"]), "minutes": int(t["duration_minutes"])}
	return {}


func check_booking(actor_id: String, job_id: String, day: int, template_id: String, now: int,
		policy: RegionPolicy) -> String:
	if not _content.has_record("jobs", job_id):
		return "E_UNKNOWN_JOB"
	var job := _content.get_record("jobs", job_id)
	var w := window(job, day, template_id)
	if w.is_empty():
		return "E_INVALID_ARGUMENTS"
	if day < int(job["available_from_day"]):
		return "E_JOB_NOT_OPEN"
	var today := GameClock.day_index_of(now)
	if w["start"] <= now or day > today + BOOKING_DAYS_AHEAD:
		return "E_SHIFT_UNAVAILABLE"
	if _shifts.has(shift_id_for(job_id, day, template_id)):
		return "E_SHIFT_UNAVAILABLE"
	var booked_that_day := 0
	for s in get_shifts(actor_id):
		if s["status"] == "missed":
			continue
		if w["start"] < s["end_minute"] and s["start_minute"] < w["end"]:
			return "E_SHIFT_CONFLICT"
		if s["day"] == day:
			booked_that_day += int(s["end_minute"]) - int(s["start_minute"])
	if not policy.validate_work_shift(job, w["minutes"], {"worked_minutes_today": booked_that_day}):
		return "E_SHIFT_LIMIT"
	return ""


func check_start(actor_id: String, shift_id: String, now: int) -> String:
	var s: Dictionary = _shifts.get(shift_id, {})
	if s.is_empty() or s["actor_id"] != actor_id or s["status"] != "booked":
		return "E_SHIFT_NOT_BOOKED"
	if now < int(s["start_minute"]) - ARRIVE_EARLY_MAX_MINUTES:
		return "E_SHIFT_NOT_STARTED"
	if now > int(s["end_minute"]) - LATEST_START_BEFORE_END_MINUTES:
		return "E_SHIFT_TOO_LATE"
	return ""


func book(ctx: CommandContext, actor_id: String, job_id: String, day: int, template_id: String) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	var w := window(_content.get_record("jobs", job_id), day, template_id)
	var id := shift_id_for(job_id, day, template_id)
	_shifts[id] = {"actor_id": actor_id, "job_id": job_id, "template_id": template_id, "day": day,
		"start_minute": w["start"], "end_minute": w["end"], "status": "booked",
		"worked_minutes": 0, "late_minutes": 0, "gross_minor": 0, "net_minor": 0}
	ctx.emit("shift_booked", {"shift_id": id, "actor_id": actor_id, "job_id": job_id, "day": day,
		"start_minute": w["start"], "end_minute": w["end"]})
	return ""


## booked -> in_progress (no event; the shift is in the middle of its own command).
func begin(ctx: CommandContext, shift_id: String) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	if not _shifts.has(shift_id) or _shifts[shift_id]["status"] != "booked":
		return "E_SHIFT_NOT_BOOKED"
	_shifts[shift_id]["status"] = "in_progress"
	return ""


func complete(ctx: CommandContext, shift_id: String, worked: int, late: int, gross: int, net: int) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	if not _shifts.has(shift_id) or _shifts[shift_id]["status"] != "in_progress":
		return "E_SHIFT_NOT_BOOKED"
	var s: Dictionary = _shifts[shift_id]
	s["status"] = "completed"
	s["worked_minutes"] = worked
	s["late_minutes"] = late
	s["gross_minor"] = gross
	s["net_minor"] = net
	ctx.emit("job_shift_completed", {"shift_id": shift_id, "actor_id": s["actor_id"], "job_id": s["job_id"],
		"gross_minor": gross, "net_minor": net, "worked_minutes": worked, "late_minutes": late})
	return ""


## TimeFlow hook: booked shifts whose end has passed are missed.
func on_time_passed(ctx: CommandContext, _minutes: int, _mode: String, _context: Dictionary = {}) -> void:
	var now := ctx.current_minute()
	var ids := PackedStringArray(_shifts.keys())
	ids.sort()
	for id in ids:
		var s: Dictionary = _shifts[id]
		if s["status"] == "booked" and int(s["end_minute"]) <= now:
			s["status"] = "missed"
			ctx.emit("shift_missed", {"shift_id": id, "actor_id": s["actor_id"], "job_id": s["job_id"]})


func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "shifts": _shifts.duplicate(true)}


func from_dict(data: Dictionary) -> String:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, STATE_SCHEMA)
	if not v.is_ok():
		return "E_INVALID_JOBS_STATE"
	for id: String in d["shifts"]:
		if not _content.has_record("jobs", d["shifts"][id]["job_id"]):
			return "E_INVALID_JOBS_STATE"
	_shifts = d["shifts"]
	return ""
