class_name StoryValidator
extends RefCounted
## Semantic checks for story content (T015, spec §14.3) — beyond the JSON schema:
##   * every condition / effect type is whitelisted and carries exactly the fields it needs,
##     with the right value types (no code, no free-form strings interpreted as logic);
##   * referenced NPCs, needs, maps, events, dialogue trees and text keys exist;
##   * authority limits: story flags live under "story.", money effects are capped, relationship
##     and need deltas are bounded, summaries only come from events, dialogue effects only sit on
##     terminal choices (so restarting a conversation cannot re-apply them).
## Runs on every loaded event / dialogue / quest / summary line (ContentRegistry), and on records
## arriving from elsewhere (test fixtures now, future model proposals later, T027/T032).

const MAX_MONEY_MINOR := 20000
const MAX_RELATIONSHIP_DELTA := 20
const MAX_NEED_DELTA := 50
const STORY_FLAG_PREFIX := "story."

## field -> kind: int, nat (int >= 0), bool, scalar (bool|int|string), npc, need, map, event, flag, stat
const CONDITION_FIELDS := {
	"day_at_least": {"value": "nat"},
	"minute_of_day_at_least": {"value": "nat"},
	"minute_of_day_before": {"value": "nat"},
	"wallet_at_least": {"value": "nat"},
	"wallet_below": {"value": "nat"},
	"need_above": {"need_id": "need", "value": "nat"},
	"need_below": {"need_id": "need", "value": "nat"},
	"relationship_at_least": {"npc_id": "npc", "value": "int"},
	"any_relationship_at_least": {"value": "int"},
	"flag_equals": {"key": "flag", "value": "scalar"},
	"lease_active": {"value": "bool"},
	"rent_overdue": {"value": "bool"},
	"rent_periods_paid_at_least": {"value": "nat"},
	"shifts_booked_at_least": {"value": "nat"},
	"shifts_completed_at_least": {"value": "nat"},
	"shifts_completed_below": {"value": "nat"},
	"stat_at_least": {"key": "stat", "value": "nat"},
	"on_map": {"map_id": "map"},
	"npc_present": {"npc_id": "npc"},
	"npc_nearby": {"npc_id": "npc"},
	"event_fired": {"event_id": "event"},
}
const EFFECT_FIELDS := {
	"set_flag": {"key": "flag", "value": "scalar"},
	"credit_money": {"amount": "money"},
	"debit_money": {"amount": "money"},
	"change_need": {"need_id": "need", "delta": "need_delta"},
	"change_relationship": {"npc_id": "npc", "delta": "relationship_delta"},
	"show_summary": {},
	"give_item": {"item_id": "item", "count": "item_count"},
}
const MAX_ITEM_GIFT := 3


static func validate_conditions(conditions: Array, path: String, content: ContentRegistry) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	for i in conditions.size():
		_check_item(conditions[i], CONDITION_FIELDS, "%s/%d" % [path, i], content, errors, "E_STORY_UNKNOWN_CONDITION")
	return errors


static func validate_effects(effects: Array, path: String, content: ContentRegistry, allow_summary: bool) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	for i in effects.size():
		var p := "%s/%d" % [path, i]
		_check_item(effects[i], EFFECT_FIELDS, p, content, errors, "E_STORY_UNKNOWN_EFFECT")
		if typeof(effects[i]) == TYPE_DICTIONARY and effects[i].get("type") == "show_summary" and not allow_summary:
			errors.append(_err("E_STORY_FORBIDDEN_EFFECT", p, "show_summary is only allowed in events"))
	return errors


static func validate_event(record: Dictionary, content: ContentRegistry) -> Array[Dictionary]:
	var errors := validate_conditions(record.get("conditions", []), "/conditions", content)
	errors.append_array(validate_effects(record.get("effects", []), "/effects", content, true))
	if not record.get("once", false):
		errors.append(_err("E_STORY_REPEATING_EVENT", "/once", "repeating events need cooldown rules (T028); use once=true"))
	if record.has("dialogue_tree_id") and not content.has_record("dialogues", record["dialogue_tree_id"]):
		errors.append(_err("E_STORY_UNKNOWN_REF", "/dialogue_tree_id", "dialogue '%s' does not exist" % record["dialogue_tree_id"]))
	return errors


static func validate_dialogue(record: Dictionary, content: ContentRegistry) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var channel: String = record.get("channel", "")
	if channel != "narration" and not record.has("speaker_id"):
		errors.append(_err("E_STORY_MISSING_FIELD", "/speaker_id", "%s dialogue needs a speaker" % channel))
	if record.has("speaker_id") and not content.has_record("npcs", record["speaker_id"]):
		errors.append(_err("E_STORY_UNKNOWN_REF", "/speaker_id", "npc '%s' does not exist" % record["speaker_id"]))
	var node_ids := {}
	for n: Dictionary in record.get("nodes", []):
		node_ids[n["id"]] = true
	var nodes: Array = record.get("nodes", [])
	for i in nodes.size():
		var choices: Array = nodes[i].get("choices", [])
		for j in choices.size():
			var c: Dictionary = choices[j]
			var p := "/nodes/%d/choices/%d" % [i, j]
			if c.has("next") and not node_ids.has(c["next"]):
				errors.append(_err("E_STORY_UNKNOWN_REF", p + "/next", "node '%s' does not exist" % c["next"]))
			if c.has("next") and not (c.get("effects", []) as Array).is_empty():
				errors.append(_err("E_STORY_EFFECT_ON_BRANCH", p + "/effects", "effects are only allowed on terminal choices"))
			errors.append_array(validate_effects(c.get("effects", []), p + "/effects", content, false))
	return errors


static func validate_quest(record: Dictionary, content: ContentRegistry) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var steps: Array = record.get("steps", [])
	for i in steps.size():
		errors.append_array(validate_conditions(steps[i].get("conditions", []), "/steps/%d/conditions" % i, content))
	return errors


## All story records of a loaded registry: [{table, id, code, path, message}].
static func validate_content(content: ContentRegistry) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for table: String in ["events", "dialogues", "quests", "summary_lines"]:
		for record in content.get_records(table):
			var errors: Array[Dictionary] = []
			match table:
				"events":
					errors = validate_event(record, content)
				"dialogues":
					errors = validate_dialogue(record, content)
				"quests":
					errors = validate_quest(record, content)
				"summary_lines":
					errors = validate_conditions(record.get("conditions", []), "/conditions", content)
			for e in errors:
				e["table"] = table
				e["id"] = record["id"]
				out.append(e)
	return out


static func _check_item(item: Variant, table: Dictionary, path: String, content: ContentRegistry,
		errors: Array[Dictionary], unknown_code: String) -> void:
	if typeof(item) != TYPE_DICTIONARY or not item.has("type"):
		errors.append(_err("E_STORY_MALFORMED", path, "expected an object with a 'type'"))
		return
	var type := str(item["type"])
	if not table.has(type):
		errors.append(_err(unknown_code, path + "/type", "'%s' is not an allowed type" % type))
		return
	var fields: Dictionary = table[type]
	for f: String in fields:
		if not item.has(f):
			errors.append(_err("E_STORY_MISSING_FIELD", "%s/%s" % [path, f], "'%s' needs field '%s'" % [type, f]))
		else:
			_check_value(item[f], fields[f], "%s/%s" % [path, f], content, errors)
	for f: String in item:
		if f != "type" and not fields.has(f):
			errors.append(_err("E_STORY_UNEXPECTED_FIELD", "%s/%s" % [path, f], "'%s' does not take field '%s'" % [type, f]))


static func _check_value(v: Variant, kind: String, path: String, content: ContentRegistry, errors: Array[Dictionary]) -> void:
	var is_int := typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and float(v) == floorf(v))
	match kind:
		"int":
			if not is_int:
				errors.append(_err("E_STORY_TYPE", path, "expected integer"))
		"nat":
			if not is_int or int(v) < 0:
				errors.append(_err("E_STORY_TYPE", path, "expected integer >= 0"))
		"bool":
			if typeof(v) != TYPE_BOOL:
				errors.append(_err("E_STORY_TYPE", path, "expected bool"))
		"scalar":
			if not (typeof(v) in [TYPE_BOOL, TYPE_INT, TYPE_STRING]) and not is_int:
				errors.append(_err("E_STORY_TYPE", path, "expected bool, integer or string"))
		"money":
			if not is_int or int(v) < 1 or int(v) > MAX_MONEY_MINOR:
				errors.append(_err("E_STORY_AUTHORITY", path, "money effects must be 1..%d minor units" % MAX_MONEY_MINOR))
		"need_delta":
			if not is_int or absi(int(v)) > MAX_NEED_DELTA:
				errors.append(_err("E_STORY_AUTHORITY", path, "need changes are limited to ±%d" % MAX_NEED_DELTA))
		"relationship_delta":
			if not is_int or absi(int(v)) > MAX_RELATIONSHIP_DELTA:
				errors.append(_err("E_STORY_AUTHORITY", path, "relationship changes are limited to ±%d" % MAX_RELATIONSHIP_DELTA))
		"flag":
			if typeof(v) != TYPE_STRING or not str(v).begins_with(STORY_FLAG_PREFIX):
				errors.append(_err("E_STORY_AUTHORITY", path, "story flags must start with '%s'" % STORY_FLAG_PREFIX))
		"stat":
			if typeof(v) != TYPE_STRING or str(v).is_empty():
				errors.append(_err("E_STORY_TYPE", path, "expected a stat name"))
		"item_count":
			if not is_int or int(v) < 1 or int(v) > MAX_ITEM_GIFT:
				errors.append(_err("E_STORY_AUTHORITY", path, "item gifts are limited to 1..%d" % MAX_ITEM_GIFT))
		"npc", "need", "map", "event", "item":
			var table: String = {"npc": "npcs", "need": "needs", "map": "maps", "event": "events", "item": "items"}[kind]
			if typeof(v) != TYPE_STRING or not content.has_record(table, v):
				errors.append(_err("E_STORY_UNKNOWN_REF", path, "%s '%s' does not exist" % [kind, str(v)]))


static func _err(code: String, path: String, message: String) -> Dictionary:
	return {"code": code, "path": path, "message": message}
