class_name DomainEvent
extends RefCounted
## A committed fact (spec §4.2, §13.1). Produced only by CommandProcessor inside a command;
## signals on GameEventBus are notifications derived from these, never the other way round.
##
## event_id      stable id from the world's CommandJournal ("evt_00000042")
## cause_id      proposal_id of the causing command, or the event_id of an earlier event
## world_revision revision the world reached when the command committed

const SCHEMA_VERSION := 1
const SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"event_id": {"type": "string", "required": true, "min_length": 1},
	"type": {"type": "id", "required": true},
	"game_minute": {"type": "int", "required": true, "min": 0},
	"actor_id": {"type": "string", "required": true, "min_length": 1},
	"cause_id": {"type": "string", "required": true, "min_length": 1},
	"world_revision": {"type": "int", "required": true, "min": 0},
	"payload": {"type": "map", "required": true, "values_spec": {"type": "any"}},
}}

var event_id := ""
var type := ""
var game_minute := 0
var actor_id := ""
var cause_id := ""
var world_revision := 0
var payload: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"event_id": event_id,
		"type": type,
		"game_minute": game_minute,
		"actor_id": actor_id,
		"cause_id": cause_id,
		"world_revision": world_revision,
		"payload": payload.duplicate(true),
	}


## Returns null if `data` is not a valid event.
static func from_dict(data: Dictionary) -> DomainEvent:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, SCHEMA)
	if not v.is_ok():
		return null
	var e := DomainEvent.new()
	e.event_id = d["event_id"]
	e.type = d["type"]
	e.game_minute = d["game_minute"]
	e.actor_id = d["actor_id"]
	e.cause_id = d["cause_id"]
	e.world_revision = d["world_revision"]
	e.payload = d["payload"]
	return e
