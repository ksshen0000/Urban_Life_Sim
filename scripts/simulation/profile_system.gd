class_name ProfileSystem
extends RefCounted
## Who the player is: a display name and how they look (character creator). A WorldState
## component so the look survives saves; it never affects game rules. Written at world setup
## (new game) and by the `set_profile` command (the mirror at home).

const SCHEMA_VERSION := 1
const MAX_NAME_LENGTH := 12
const HAIR_STYLES := ["short", "spiky", "buzz", "bald", "long", "bob", "ponytail", "bun", "perm"]
const OUTFITS := ["pants", "skirt", "dress"]
const COLOR := {"type": "string", "required": true, "pattern": "^#[0-9a-fA-F]{6}$"}
const LOOK_SCHEMA := {"type": "object", "required": true, "fields": {
	"skin": COLOR, "hair": COLOR, "top": COLOR, "bottom": COLOR, "shoes": COLOR,
	"hair_style": {"type": "string", "required": true, "values": HAIR_STYLES},
	"outfit": {"type": "string", "required": true, "values": OUTFITS},
	"figure": {"type": "string", "required": true, "values": ["m", "f"]},
}}
const PROFILE_SCHEMA := {"type": "object", "fields": {
	"name": {"type": "string", "required": true, "max_length": MAX_NAME_LENGTH},
	"look": LOOK_SCHEMA,
}}
const STATE_SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"actors": {"type": "map", "required": true, "values_spec": PROFILE_SCHEMA},
}}

## A young newcomer in a blue jacket (used when nobody went through the creator).
const DEFAULT_LOOK := {"skin": "#f2c9a0", "hair": "#2b2b33", "hair_style": "spiky", "top": "#3a6fd8",
	"bottom": "#3d4656", "shoes": "#e8e4da", "outfit": "pants", "figure": "m"}

var _actors: Dictionary = {}  # actor_id -> {name, look}


## Returns "" or an error code. Names are trimmed; control characters are not allowed.
static func validate_profile(profile: Variant) -> String:
	if typeof(profile) != TYPE_DICTIONARY:
		return "E_INVALID_PROFILE"
	var v := SchemaValidator.new()
	v.validate(profile, PROFILE_SCHEMA)
	if not v.is_ok():
		return "E_INVALID_PROFILE"
	var name: String = profile["name"]
	for i in name.length():
		if name.unicode_at(i) < 32:
			return "E_INVALID_PROFILE"
	return ""


static func default_profile() -> Dictionary:
	return {"name": "", "look": DEFAULT_LOOK.duplicate()}


## World setup only (new game).
func set_initial(actor_id: String, profile: Dictionary) -> bool:
	if not validate_profile(profile).is_empty():
		return false
	_actors[actor_id] = _clean(profile)
	return true


func get_profile(actor_id: String) -> Dictionary:
	return (_actors.get(actor_id, default_profile()) as Dictionary).duplicate(true)


func get_look(actor_id: String) -> Dictionary:
	return get_profile(actor_id)["look"]


func get_display_name(actor_id: String) -> String:
	return get_profile(actor_id)["name"]


func set_profile(ctx: CommandContext, actor_id: String, profile: Dictionary) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	var err := validate_profile(profile)
	if not err.is_empty():
		return err
	_actors[actor_id] = _clean(profile)
	ctx.emit("profile_changed", {"actor_id": actor_id})
	return ""


static func _clean(profile: Dictionary) -> Dictionary:
	var look := {}
	for k: String in LOOK_SCHEMA["fields"]:
		look[k] = profile["look"][k]
	return {"name": str(profile["name"]).strip_edges(), "look": look}


func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "actors": _actors.duplicate(true)}


func from_dict(data: Dictionary) -> String:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, STATE_SCHEMA)
	if not v.is_ok():
		return "E_INVALID_PROFILE_STATE"
	for id: String in d["actors"]:
		if not validate_profile(d["actors"][id]).is_empty():
			return "E_INVALID_PROFILE_STATE"
	_actors = d["actors"]
	return ""
