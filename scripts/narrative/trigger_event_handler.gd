class_name TriggerEventHandler
extends CommandHandler
## `trigger_event` {event_id} by actor "system:event/<event_id>" (T015). Re-checks eligibility on
## the authoritative world, applies the event's effects atomically (any failure rolls the whole
## event back and it stays unfired, D-004c), marks it fired and queues its dialogue.

const ACTION := "trigger_event"
const ACTOR_PREFIX := "system:event/"
const ARGUMENTS_SCHEMA := {"type": "object", "fields": {"event_id": {"type": "id", "required": true}}}


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	var event_id: String = str(ctx.proposal.arguments.get("event_id", ""))
	return "" if ctx.proposal.actor_id == ACTOR_PREFIX + event_id else "E_FORBIDDEN_ACTOR"


func validate(ctx: CommandContext) -> String:
	var args: Variant = parse_args(ctx, ARGUMENTS_SCHEMA)
	if args == null:
		return "E_INVALID_ARGUMENTS"
	var content := ctx.get_service("content") as ContentRegistry
	if not content.has_record("events", args["event_id"]):
		return "E_UNKNOWN_EVENT"
	var events := ctx.world.get_component("events") as EventSystem
	if not events.is_eligible(args["event_id"], ctx.world):
		return "E_EVENT_NOT_ELIGIBLE"
	var ev := content.get_record("events", args["event_id"])
	if ev.has("dialogue_tree_id") and not (ctx.world.get_component("dialogue") as DialogueSystem).can_enqueue():
		return "E_STORY_QUEUE_FULL"
	return StoryEffects.precheck(ev["effects"], ctx.world, "player")


func apply(ctx: CommandContext) -> String:
	var event_id: String = ctx.proposal.arguments["event_id"]
	var content := ctx.get_service("content") as ContentRegistry
	var ev := content.get_record("events", event_id)
	var started := ctx.emit("event_started", {"event_id": event_id})
	var err := StoryEffects.apply(ctx, ev["effects"], "player", "event:" + event_id)
	if err.is_empty():
		err = (ctx.world.get_component("events") as EventSystem).mark_fired(ctx, event_id)
	if err.is_empty() and ev.has("dialogue_tree_id"):
		var tree := content.get_record("dialogues", ev["dialogue_tree_id"])
		err = (ctx.world.get_component("dialogue") as DialogueSystem).enqueue_tree(ctx, tree["id"],
			tree["nodes"][0]["id"], "event:" + event_id)
	if err.is_empty():
		ctx.emit("event_completed", {"event_id": event_id}, started)
	return err
