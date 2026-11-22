class_name WorkShiftHandler
extends CommandHandler
## `work_shift` {shift_id} (T010): at the workplace, work a booked shift. Arriving early waits
## until the start; arriving late shortens the paid time. Time passes in "working" mode with the
## job's need rates; pay = hourly × worked minutes / 60 (rounded down to the fen), take-home is
## computed by the RegionPolicy, then credited once. The shift's status guards against double pay.

const ACTION := "work_shift"
const ARGUMENTS_SCHEMA := {"type": "object", "fields": {"shift_id": {"type": "string", "required": true, "min_length": 1}}}


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	return "" if ctx.proposal.actor_id == "player" else "E_FORBIDDEN_ACTOR"


func validate(ctx: CommandContext) -> String:
	var args: Variant = parse_args(ctx, ARGUMENTS_SCHEMA)
	if args == null:
		return "E_INVALID_ARGUMENTS"
	var actor := ctx.proposal.actor_id
	var jobs := ctx.world.get_component("jobs") as JobsSystem
	var err := jobs.check_start(actor, args["shift_id"], ctx.world.clock.get_minute())
	if not err.is_empty():
		return err
	var job := (ctx.get_service("content") as ContentRegistry).get_record("jobs", jobs.get_shift(args["shift_id"])["job_id"])
	if not (ctx.world.get_component("locations") as LocationSystem).is_on_map_of(actor, job["workplace_location_id"]):
		return "E_NOT_HERE"
	return ""


@warning_ignore("integer_division")
func apply(ctx: CommandContext) -> String:
	var actor := ctx.proposal.actor_id
	var shift_id: String = ctx.proposal.arguments["shift_id"]
	var jobs := ctx.world.get_component("jobs") as JobsSystem
	var shift := jobs.get_shift(shift_id)
	var job := (ctx.get_service("content") as ContentRegistry).get_record("jobs", shift["job_id"])
	var start: int = shift["start_minute"]
	var end: int = shift["end_minute"]
	var err := jobs.begin(ctx, shift_id)
	if not err.is_empty():
		return err
	var now := ctx.world.clock.get_minute()
	if now < start:
		err = TimeFlow.advance(ctx, start - now, TimeFlow.MODE_AWAKE)
		if not err.is_empty():
			return err
		now = start
	var late := now - start
	var worked := end - now
	var rates := {}
	for r: Dictionary in job["work_rates_per_hour"]:
		rates[r["need_id"]] = r["per_hour"]
	err = TimeFlow.advance(ctx, worked, TimeFlow.MODE_WORKING, {"rates": rates, "job_id": job["id"]})
	if not err.is_empty():
		return err
	var gross: int = int(job["hourly_wage_minor"]) * worked / 60
	var policy := ctx.get_service("region_policy") as RegionPolicy
	var net := policy.calculate_take_home_pay(gross, {"job_id": job["id"], "shift_id": shift_id, "actor_id": actor})
	if net > 0:
		err = (ctx.world.get_component("economy") as EconomyService).credit(ctx, actor, net, "wage:" + shift_id)
		if not err.is_empty():
			return err
	return jobs.complete(ctx, shift_id, worked, late, gross, net)
