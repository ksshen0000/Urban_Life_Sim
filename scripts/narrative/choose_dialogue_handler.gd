class_name ChooseDialogueHandler
extends CommandHandler
## `choose_dialogue` {tree_id, node_id, choice_id, entry_id?} (T014). Either answers a queued story
## entry (entry_id) or talks to an NPC in person (no entry_id: the speaker must be on the player's
## map and the tree must be that NPC's intro — not yet completed — or their repeatable chat).
## Terminal choices apply their whitelisted effects; repeatable trees rate-limit affection gains.

const ACTION := "choose_dialogue"
const ARGUMENTS_SCHEMA := {"type": "object", "fields": {
	"tree_id": {"type": "id", "required": true},
	"node_id": {"type": "id", "required": true},
	"choice_id": {"type": "id", "required": true},
	"entry_id": {"type": "string"},
}}


func get_action() -> String:
	return ACTION


func authorize(ctx: CommandContext) -> String:
	return "" if ctx.proposal.actor_id == "player" else "E_FORBIDDEN_ACTOR"


func validate(ctx: CommandContext) -> String:
	var args: Variant = parse_args(ctx, ARGUMENTS_SCHEMA)
	if args == null:
		return "E_INVALID_ARGUMENTS"
	var content := ctx.get_service("content") as ContentRegistry
	if not content.has_record("dialogues", args["tree_id"]):
		return "E_UNKNOWN_DIALOGUE"
	var tree := content.get_record("dialogues", args["tree_id"])
	var choice := find_choice(tree, args["node_id"], args["choice_id"])
	if choice.is_empty():
		return "E_INVALID_ARGUMENTS"
	var dialogue := ctx.world.get_component("dialogue") as DialogueSystem
	if args.has("entry_id"):
		var entry := dialogue.find_entry(args["entry_id"])
		if entry.is_empty() or entry.get("tree_id", "") != args["tree_id"] or entry.get("node_id", "") != args["node_id"]:
			return "E_DIALOGUE_DONE"
	else:
		var err := _check_in_person(ctx, tree, content, dialogue)
		if not err.is_empty():
			return err
	if not choice.has("next"):
		return StoryEffects.precheck(choice["effects"], ctx.world, "player")
	return ""


func apply(ctx: CommandContext) -> String:
	var args: Dictionary = parse_args(ctx, ARGUMENTS_SCHEMA)
	var content := ctx.get_service("content") as ContentRegistry
	var tree := content.get_record("dialogues", args["tree_id"])
	var choice := find_choice(tree, args["node_id"], args["choice_id"])
	var dialogue := ctx.world.get_component("dialogue") as DialogueSystem
	var entry_id: String = args.get("entry_id", "")
	if choice.has("next"):
		ctx.emit("dialogue_advanced", {"tree_id": tree["id"], "choice_id": choice["id"], "next": choice["next"]})
		return dialogue.set_entry_node(ctx, entry_id, choice["next"]) if not entry_id.is_empty() else ""
	var source := "dialogue:%s:%s" % [tree["id"], choice["id"]]
	var err := StoryEffects.apply(ctx, choice["effects"], "player", source, tree["repeatable"])
	if err.is_empty() and not tree["repeatable"]:
		err = dialogue.mark_completed(ctx, tree["id"])
	if err.is_empty() and not entry_id.is_empty():
		err = dialogue.finish_entry(ctx, entry_id)
	if err.is_empty():
		ctx.emit("dialogue_completed", {"tree_id": tree["id"], "choice_id": choice["id"]})
	return err


## The tree an in-person talk with `npc_id` opens right now ("" if none).
static func talk_tree_for(npc: Dictionary, dialogue: DialogueSystem) -> String:
	return npc["dialogue_tree_id"] if not dialogue.is_completed(npc["dialogue_tree_id"]) else npc["chat_tree_id"]


static func find_choice(tree: Dictionary, node_id: String, choice_id: String) -> Dictionary:
	for n: Dictionary in tree["nodes"]:
		if n["id"] == node_id:
			for c: Dictionary in n["choices"]:
				if c["id"] == choice_id:
					return c
	return {}


func _check_in_person(ctx: CommandContext, tree: Dictionary, content: ContentRegistry, dialogue: DialogueSystem) -> String:
	if tree["channel"] != "in_person" or not tree.has("speaker_id"):
		return "E_DIALOGUE_DONE"
	var npc := content.get_record("npcs", tree["speaker_id"])
	if talk_tree_for(npc, dialogue) != tree["id"]:
		return "E_DIALOGUE_DONE"
	if not StoryConditions.evaluate({"type": "npc_present", "npc_id": npc["id"]}, ctx.world, content):
		return "E_NPC_NOT_HERE"
	return ""
