class_name WorldState
extends RefCounted
## Authoritative persistent facts (spec §13.1): a revision counter, the command journal and a set
## of named components (clock now; wallet, needs, jobs... in later tasks). Each component exposes
## `to_dict() -> Dictionary` and `from_dict(data) -> String` (error code or ""), so the whole world
## can be captured for rollback and serialized for saves. No Godot nodes, no rendered text.
##
## Only CommandProcessor (via command handlers) may mutate it.

const SCHEMA_VERSION := 1
const SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"revision": {"type": "int", "required": true, "min": 0},
	"journal": {"type": "map", "required": true, "values_spec": {"type": "any"}},
	"components": {"type": "map", "required": true, "values_spec": {"type": "map", "values_spec": {"type": "any"}}},
}}

var revision := 0
var clock: GameClock
var journal: CommandJournal
var _components: Dictionary = {}
var _component_order: Array[String] = []


func _init(start_minute: int = 0, journal_capacity: int = CommandJournal.DEFAULT_CAPACITY) -> void:
	clock = GameClock.new(start_minute)
	journal = CommandJournal.new(journal_capacity)
	register_component("clock", clock)


func register_component(component_name: String, component: RefCounted) -> bool:
	if component_name.is_empty() or _components.has(component_name) or component == null:
		return false
	if not (component.has_method("to_dict") and component.has_method("from_dict")):
		return false
	_components[component_name] = component
	_component_order.append(component_name)
	return true


func get_component(component_name: String) -> RefCounted:
	return _components.get(component_name)


func get_component_names() -> PackedStringArray:
	return PackedStringArray(_component_order)


## Everything a failed command could have touched. The idempotency memory is excluded on purpose:
## it only changes after a successful commit.
func capture() -> Dictionary:
	return {"revision": revision, "next_event_seq": journal.next_event_seq, "components": _components_to_dict()}


func rollback(state: Dictionary) -> void:
	revision = state["revision"]
	journal.next_event_seq = state["next_event_seq"]
	for component_name in _component_order:
		var err: String = _components[component_name].from_dict(state["components"][component_name])
		assert(err.is_empty(), "rollback of component '%s' failed: %s" % [component_name, err])


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"revision": revision,
		"journal": journal.to_dict(),
		"components": _components_to_dict(),
	}


## All-or-nothing restore. Returns "" or an error code; on error the world is unchanged.
func from_dict(data: Dictionary) -> String:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, SCHEMA)
	if not v.is_ok():
		return "E_INVALID_WORLD_STATE"
	var components: Dictionary = d["components"]
	for component_name: String in components:
		if not _components.has(component_name):
			return "E_UNKNOWN_COMPONENT"
	for component_name in _component_order:
		if not components.has(component_name):
			return "E_MISSING_COMPONENT"
	var before := capture()
	var journal_before := journal.to_dict()
	var err := journal.from_dict(d["journal"])
	if err.is_empty():
		for component_name in _component_order:
			err = _components[component_name].from_dict(components[component_name])
			if not err.is_empty():
				break
	if not err.is_empty():
		journal.from_dict(journal_before)
		rollback(before)
		return err
	revision = d["revision"]
	return ""


func _components_to_dict() -> Dictionary:
	var out := {}
	for component_name in _component_order:
		out[component_name] = _components[component_name].to_dict()
	return out
