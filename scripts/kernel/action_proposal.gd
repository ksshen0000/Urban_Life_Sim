class_name ActionProposal
extends RefCounted
## An intent to change the world (spec §13.1), submitted by the player UI, NPC policies, the
## story runtime, or — in the future — a model. Proposals are never guaranteed to succeed:
## CommandProcessor authorizes, validates and applies them atomically.
##
## proposal_id doubles as the idempotency key: re-submitting an already committed id returns
## the original result without applying anything again.

const SCHEMA_VERSION := 1
## "player", "npc_chen_yu", "system", "system:event/event_first_rent"
const ACTOR_PATTERN := "^[a-z][a-z0-9_]*(:[a-z0-9_./-]+)?$"
const PROPOSAL_ID_PATTERN := "^[A-Za-z0-9_.:-]{1,128}$"
const SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"proposal_id": {"type": "string", "required": true, "pattern": PROPOSAL_ID_PATTERN},
	"actor_id": {"type": "string", "required": true, "pattern": ACTOR_PATTERN},
	"action": {"type": "id", "required": true},
	"target_id": {"type": "string"},
	"arguments": {"type": "map", "values_spec": {"type": "any"}},
	## -1 = do not check; otherwise must equal the current world revision (optimistic concurrency).
	"expected_world_revision": {"type": "int", "min": -1},
	"issued_at_game_minute": {"type": "int", "min": -1},
}}

var proposal_id := ""
var actor_id := ""
var action := ""
var target_id := ""
var arguments: Dictionary = {}
var expected_world_revision := -1
var issued_at_game_minute := -1


static func create(p_proposal_id: String, p_actor_id: String, p_action: String,
		p_arguments: Dictionary = {}, p_target_id: String = "") -> ActionProposal:
	var p := ActionProposal.new()
	p.proposal_id = p_proposal_id
	p.actor_id = p_actor_id
	p.action = p_action
	p.arguments = p_arguments.duplicate(true)
	p.target_id = p_target_id
	return p


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"proposal_id": proposal_id,
		"actor_id": actor_id,
		"action": action,
		"target_id": target_id,
		"arguments": arguments.duplicate(true),
		"expected_world_revision": expected_world_revision,
		"issued_at_game_minute": issued_at_game_minute,
	}


## Returns {ok, error_code, errors: Array[Dictionary], proposal}. Used for untrusted input
## (story files, future model output); integral JSON floats are normalized to ints.
static func from_dict(data: Variant) -> Dictionary:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, SCHEMA)
	if not v.is_ok():
		return {"ok": false, "error_code": "E_MALFORMED_PROPOSAL", "errors": v.errors, "proposal": null}
	var p := ActionProposal.create(d["proposal_id"], d["actor_id"], d["action"],
		d.get("arguments", {}), d.get("target_id", ""))
	p.expected_world_revision = d.get("expected_world_revision", -1)
	p.issued_at_game_minute = d.get("issued_at_game_minute", -1)
	return {"ok": true, "error_code": null, "errors": [], "proposal": p}


## Structural check of an in-memory proposal; "" or E_MALFORMED_PROPOSAL.
func validate_structure() -> String:
	var v := SchemaValidator.new()
	v.validate(to_dict(), SCHEMA)
	return "" if v.is_ok() else "E_MALFORMED_PROPOSAL"


## Identity of the request, excluding transport metadata. Re-using a proposal_id with a
## different fingerprint is rejected instead of silently returning the old result.
func fingerprint() -> String:
	var v := SchemaValidator.new()
	return JSON.stringify([actor_id, action, target_id, v.validate(arguments, {"type": "any"})], "", true)
