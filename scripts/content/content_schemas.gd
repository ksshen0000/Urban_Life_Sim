class_name ContentSchemas
extends RefCounted
## Declarative schemas for content packs (see SchemaValidator for the spec format).
##
## Table definition keys:
##   schema_versions  supported file `schema_version` values (bump + migrate on breaking changes)
##   record           SchemaValidator spec for one record (must have an "id" field)
##   required_scope   pack.json scope keys that must be declared for packs filling this table
##   scope_fields     {record_field: scope_key}; when both exist they must be equal
## Structural rules a schema cannot express live in `custom_checks()`.
## Adding a region or city never requires editing this file; adding a new *kind* of data does.

const GEO_ID := "^[A-Z][A-Z0-9_]*$"
const CURRENCY_CODE := "^[A-Z]{3}$"
const LANGUAGE := "^[a-z]{2}(_[A-Z]{2})?$"
const SEMVER := "^[0-9]+\\.[0-9]+\\.[0-9]+$"
const TEXT_KEY_PATTERN := "^[a-z0-9_]+(\\.[a-z0-9_]+)+$"
const TEXT_TABLE := "text"

## Every player-facing string is a key into the `text` table; missing keys fail validation.
const TEXT := {"type": "text_key", "required": true, "table": TEXT_TABLE}
const OPTIONAL_TEXT := {"type": "text_key", "table": TEXT_TABLE}
const TILE := {"type": "array", "required": true, "min_items": 2, "max_items": 2,
	"items": {"type": "int", "min": 0, "max": 4096}}

## Time modes drive need rates (NeedsSystem). "working" uses the job's own rates (T010) and
## falls back to "awake" for needs the job does not list.
const TIME_MODES := ["awake", "resting", "sleeping", "working"]

## Map tile kinds (3/4 view, D-019). The ASCII rows describe the ground plane only:
##   ground / road / grass / water / wall  terrain drawn on the ground layer
##   building                              footprint cell of a declared structure (solid)
##   tree                                  a tree prop stands here (solid trunk, grass beneath)
## Presentation (colours, facades, canopies) lives in the world builders; walkability is a rule.
const TILE_KINDS := {
	"ground": {"walkable": true},
	"road": {"walkable": true},
	"grass": {"walkable": true},
	"wall": {"walkable": false},
	"building": {"walkable": false},
	"tree": {"walkable": false},
	"water": {"walkable": false},
	# interiors (D-034): floors, the wall faces seen in 3/4 view, and the dark outside
	"floor_tile": {"walkable": true},
	"floor_wood": {"walkable": true},
	"wall_in": {"walkable": false},
	"void": {"walkable": false},
	# districts beyond the old town (D-035): building-site earth, hoarding, polished plaza stone
	"dirt": {"walkable": true},
	"fence": {"walkable": false},
	"plaza": {"walkable": true},
}
const TILE_KIND_NAMES := ["ground", "road", "grass", "wall", "building", "tree", "water",
	"floor_tile", "floor_wood", "wall_in", "void", "dirt", "fence", "plaza"]
const STRUCTURE_STYLES := ["apartment", "shop", "restaurant", "block", "warehouse", "arcade", "billiards",
	"barber", "noodle", "construction", "tower", "luxury", "cafe", "mall"]
const INTERACTABLE_KINDS := ["sign", "shop", "activity", "home", "job_board", "transit", "workplace", "door", "barber"]
## Interactables created at runtime (never in map files): "npc", "pedestrian".
## Indoor furniture (D-034): kind -> blocking footprint in tiles [w, h] ([0, 0] = walk-through).
## Work stations (cash register, order counter) are where shift minigames will live later.
const FURNITURE := {
	"fridge": [1, 1], "shelf": [3, 1], "cashier_counter": [3, 1], "snack_rack": [1, 1],
	"order_counter": [3, 1], "kitchen": [3, 1], "table": [1, 1], "chair_left": [0, 0],
	"chair_right": [0, 0], "plant": [1, 1], "drink_machine": [1, 1], "trash_bin": [1, 1],
	"door_mat": [0, 0],
}
const FURNITURE_KINDS := ["fridge", "shelf", "cashier_counter", "snack_rack", "order_counter", "kitchen",
	"table", "chair_left", "chair_right", "plant", "drink_machine", "trash_bin", "door_mat"]
const WALL_DECOR := ["menu_board", "poster", "clock", "window_in", "wall_shelf", "price_banner"]
## Interactables generated at runtime (not allowed in map files): "npc".
const INTERACTABLE_PROPS := ["none", "signpost", "bus_sign", "board", "bench", "chess_table", "speaker"]
## Walk-through scenery placed by maps (`decor`).
const DECOR_KINDS := ["pavilion", "lamp", "flowers", "crane", "bricks", "laundry", "barber_pole", "fountain"]
## Flat road markings drawn under everything (`decals`).
const DECAL_KINDS := ["crosswalk_v", "crosswalk_h"]
## What park regulars and passers-by are doing (`ambient`, presentation only).
const AMBIENT_POSES := ["chess", "watch", "sing", "erhu", "dance", "taichi", "fish", "stand", "eat", "browse", "work"]
const FACINGS := ["down", "up", "left", "right"]
const HOURS := {"type": "array", "min_items": 1, "items": {"type": "object", "fields": {
	"start_minute_of_day": {"type": "int", "required": true, "min": 0, "max": 1439},
	"end_minute_of_day": {"type": "int", "required": true, "min": 1, "max": 1440},
}}}
const COLOR := {"type": "string", "required": true, "pattern": "^#[0-9a-fA-F]{6}$"}
const OPTIONAL_COLOR := {"type": "string", "pattern": "^#[0-9a-fA-F]{6}$"}
## How a person looks (PixelPerson). `figure` "f" = narrower shoulders, lashes, blush.
const HAIR_STYLES := ["short", "spiky", "buzz", "bald", "long", "bob", "ponytail", "bun", "perm"]
const LOOK_EXTRA := {
	"hair_style": {"type": "string", "values": HAIR_STYLES},
	"outfit": {"type": "string", "values": ["pants", "skirt", "dress"]},
	"figure": {"type": "string", "values": ["m", "f"]},
	"skin": OPTIONAL_COLOR, "bottom": OPTIONAL_COLOR, "shoes": OPTIONAL_COLOR, "vest": OPTIONAL_COLOR,
}
const LOOK_FIELDS := {
	"shirt": COLOR, "hair": COLOR,
	"hair_style": LOOK_EXTRA["hair_style"], "outfit": LOOK_EXTRA["outfit"], "figure": LOOK_EXTRA["figure"],
	"skin": OPTIONAL_COLOR, "bottom": OPTIONAL_COLOR, "shoes": OPTIONAL_COLOR, "vest": OPTIONAL_COLOR,
}

## Story DSL (T015, spec §4.3 whitelist + documented extensions, D-022). Only these types exist;
## per-type required fields, value types, references and authority limits are enforced by
## StoryValidator after loading. Content can never contain code.
const CONDITION_TYPES := [
	"day_at_least", "minute_of_day_at_least", "minute_of_day_before",
	"wallet_at_least", "wallet_below", "need_above", "need_below",
	"relationship_at_least", "any_relationship_at_least", "flag_equals",
	"lease_active", "rent_overdue", "rent_periods_paid_at_least",
	"shifts_booked_at_least", "shifts_completed_at_least", "shifts_completed_below",
	"stat_at_least", "on_map", "npc_present", "npc_nearby", "event_fired",
]
const EFFECT_TYPES := ["set_flag", "credit_money", "debit_money", "change_need", "change_relationship", "show_summary", "give_item"]
const FLAG_KEY_PATTERN := "^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)*$"
const CONDITION := {"type": "object", "fields": {
	"type": {"type": "string", "required": true, "values": CONDITION_TYPES},
	"value": {"type": "any"},
	"key": {"type": "string", "pattern": FLAG_KEY_PATTERN},
	"npc_id": {"type": "ref", "table": "npcs"},
	"need_id": {"type": "ref", "table": "needs"},
	"map_id": {"type": "ref", "table": "maps"},
	"event_id": {"type": "ref", "table": "events"},
}}
const EFFECT := {"type": "object", "fields": {
	"type": {"type": "string", "required": true, "values": EFFECT_TYPES},
	"key": {"type": "string", "pattern": FLAG_KEY_PATTERN},
	"value": {"type": "any"},
	"npc_id": {"type": "ref", "table": "npcs"},
	"need_id": {"type": "ref", "table": "needs"},
	"delta": {"type": "int", "min": -100, "max": 100},
	"amount": {"type": "int", "min": 1},
	"item_id": {"type": "ref", "table": "items"},
	"count": {"type": "int", "min": 1},
}}
const CONDITIONS := {"type": "array", "required": true, "items": CONDITION}
const EFFECTS := {"type": "array", "required": true, "items": EFFECT}
const HEX_COLOR := "^#[0-9a-fA-F]{6}$"

const PACK_MANIFEST := {
	"type": "object",
	"fields": {
		"schema_version": {"type": "int", "required": true, "min": 1},
		"pack_id": {"type": "id", "required": true},
		"pack_version": {"type": "string", "required": true, "pattern": SEMVER},
		"description": {"type": "string"},
		"scope": {"type": "object", "required": true, "fields": {
			"region_id": {"type": "string", "pattern": GEO_ID},
			"country_id": {"type": "string", "pattern": GEO_ID},
			"city_id": {"type": "string", "pattern": GEO_ID},
		}},
		"dependencies": {"type": "array", "required": true, "unique": true, "items": {"type": "id"}},
		"files": {"type": "array", "required": true, "items": {"type": "object", "fields": {
			"path": {"type": "string", "required": true, "min_length": 1},
			"table": {"type": "id", "required": true},
		}}},
		"story_providers": {"type": "array", "items": {"type": "object", "fields": {
			"provider_id": {"type": "id", "required": true},
			"schema_version": {"type": "int", "required": true, "min": 1},
			"provider_version": {"type": "string", "pattern": SEMVER},
		}}},
	},
}

const TABLES := {
	# --- localization ---------------------------------------------------------------------
	"text": {
		"schema_versions": [1],
		"record": {"type": "object", "fields": {
			"id": {"type": "string", "required": true, "pattern": TEXT_KEY_PATTERN},
			"zh_CN": {"type": "string", "required": true, "min_length": 1},
			# Empty / missing = not translated yet; the fallback locale (zh_CN) is shown.
			"en": {"type": "string"},
		}},
	},
	# --- common rules -----------------------------------------------------------------------
	"game_rules": {
		"schema_versions": [1],
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true},
			## Real milliseconds per game minute while exploring (1000 = 1 game min / real s).
			"exploration_real_ms_per_game_minute": {"type": "int", "required": true, "min": 10, "max": 60000},
			## Exploration time is committed in steps of this many game minutes.
			"exploration_step_minutes": {"type": "int", "required": true, "min": 1, "max": 60},
			"ledger_keep_entries": {"type": "int", "required": true, "min": 10, "max": 10000},
			"inventory_stack_limit": {"type": "int", "required": true, "min": 1, "max": 999},
		}},
	},
	"needs": {
		"schema_versions": [1],
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true},
			"name_key": TEXT,
			"initial_value": {"type": "int", "required": true, "min": 0, "max": 100},
			"high_is_bad": {"type": "bool", "required": true},
			## Points per game hour by time mode (fractions carry over between ticks).
			"rates_per_hour": {"type": "object", "required": true, "fields": {
				"awake": {"type": "int", "required": true, "min": -100, "max": 100},
				"resting": {"type": "int", "required": true, "min": -100, "max": 100},
				"sleeping": {"type": "int", "required": true, "min": -100, "max": 100},
			}},
			## Increases during a mode never push the value above this cap (e.g. sleep -> 90 energy).
			"mode_caps": {"type": "map", "key_pattern": "^(awake|resting|sleeping|working)$",
				"values_spec": {"type": "int", "min": 0, "max": 100}},
			## What a need does to you beyond the number (D-037): past a threshold you walk slower,
			## work less efficiently (pay x efficiency), or cannot start a shift at all.
			"states": {"type": "array", "unique_by": "id", "items": {"type": "object", "fields": {
				"id": {"type": "id", "required": true},
				"name_key": TEXT,
				"op": {"type": "string", "required": true, "values": ["at_least", "at_most"]},
				"value": {"type": "int", "required": true, "min": 0, "max": 100},
				"walk_speed_pct": {"type": "int", "min": 10, "max": 100},
				"work_efficiency_pct": {"type": "int", "min": 10, "max": 100},
				## Set = cannot start a shift in this state; the value is the refusal code.
				"blocks_work": {"type": "string", "pattern": "^E_[A-Z_]+$"},
			}}},
			"pressure_rules": {"type": "array", "items": {"type": "object", "fields": {
				"when_need": {"type": "ref", "required": true, "table": "needs"},
				"op": {"type": "string", "required": true, "values": ["at_least", "at_most"]},
				"value": {"type": "int", "required": true, "min": 0, "max": 100},
				"add_per_hour": {"type": "int", "required": true, "min": -100, "max": 100},
			}}},
		}},
	},
	"items": {
		"schema_versions": [1],
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true},
			"name_key": TEXT,
			"description_key": TEXT,
			## "keepsake": owned, never used up (a luxury bag); needs no use_effects.
			"category": {"type": "string", "required": true, "values": ["food", "drink", "keepsake"]},
			"use_minutes": {"type": "int", "required": true, "min": 0, "max": 120},
			"use_effects": {"type": "array", "required": true, "unique_by": "need_id",
				"items": {"type": "object", "fields": {
					"need_id": {"type": "ref", "required": true, "table": "needs"},
					"delta": {"type": "int", "required": true, "min": -100, "max": 100},
				}}},
		}},
	},
	"activities": {
		"schema_versions": [1],
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true},
			"name_key": TEXT,
			"description_key": TEXT,
			## Default length; the player may pick any length in min_minutes..max_minutes
			## (both default to duration_minutes, i.e. a fixed length).
			"duration_minutes": {"type": "int", "required": true, "min": 1, "max": 1440},
			"min_minutes": {"type": "int", "min": 1, "max": 1440},
			"max_minutes": {"type": "int", "min": 1, "max": 1440},
			## Lengths offered as buttons (UI). Each must lie in min..max.
			"duration_presets_minutes": {"type": "array", "unique": true, "max_items": 8,
				"items": {"type": "int", "min": 1, "max": 1440}},
			## Also offer "until HH:00" (e.g. sleep until 07:00 next morning) when that fits min..max.
			"until_hour": {"type": "int", "min": 0, "max": 23},
			"time_mode": {"type": "string", "required": true, "values": ["awake", "resting", "sleeping"]},
			## Per-hour need changes replacing the time mode's base rate for the listed needs
			## (scrolling short videos relaxes but tires you out).
			"rates_per_hour": {"type": "array", "unique_by": "need_id",
				"items": {"type": "object", "fields": {
					"need_id": {"type": "ref", "required": true, "table": "needs"},
					"per_hour": {"type": "int", "required": true, "min": -100, "max": 100},
				}}},
			## Opening windows (minute of day, end exclusive, no wrap past midnight). The activity must
			## start and finish inside one window. Absent = always available.
			"hours": HOURS,
			## Paid by the hour, rounded up to the minor unit (arcade, billiards). Absent = free.
			"price_per_hour_minor": {"type": "int", "min": 0, "max": 1000000},
			## Grouping for menus: "sleep" (the bed) or "rest" (pastimes at home / on a bench).
			"category": {"type": "string", "required": true, "values": ["sleep", "rest"]},
			## Optional minigame played while doing it (registry id, D-038); presentation only.
			"minigame": {"type": "id"},
			## Only at the actor's leased home (bed).
			"requires_home": {"type": "bool"},
			## Otherwise: only on the map of one of these locations (bench in the park). Empty = anywhere.
			"location_ids": {"type": "array", "unique": true, "items": {"type": "id"}},
		}},
	},
	# --- region -----------------------------------------------------------------------------
	"regions": {
		"schema_versions": [1],
		"required_scope": ["region_id"],
		"scope_fields": {"id": "region_id", "country_id": "country_id"},
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true, "pattern": GEO_ID},
			"display_name_key": TEXT,
			# Optional: a region *group* such as EU has no single country or currency.
			"country_id": {"type": "string", "pattern": GEO_ID},
			"currency_code": {"type": "string", "pattern": CURRENCY_CODE},
			"currency_minor_digits": {"type": "int", "min": 0, "max": 4},
			"default_language": {"type": "string", "required": true, "pattern": LANGUAGE},
			"policy_config_id": {"type": "ref", "required": true, "table": "region_policy_configs",
				"match": {"region_id": "id"}},
		}},
	},
	"region_policy_configs": {
		"schema_versions": [1],
		"required_scope": ["region_id"],
		"scope_fields": {"region_id": "region_id"},
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true},
			"region_id": {"type": "ref", "required": true, "table": "regions", "pattern": GEO_ID,
				"match": {"currency_code": "currency_code"}},
			"implementation": {"type": "id", "required": true},
			"currency_code": {"type": "string", "required": true, "pattern": CURRENCY_CODE},
			"gamified": {"type": "bool", "required": true},
			"notes": {"type": "string"},
			# Validated by the RegionPolicy implementation named in `implementation`.
			"settings": {"type": "map", "required": true, "values_spec": {"type": "any"}},
		}},
	},
	# --- city -------------------------------------------------------------------------------
	"cities": {
		"schema_versions": [1],
		"required_scope": ["region_id", "city_id"],
		"scope_fields": {"id": "city_id", "region_id": "region_id", "country_id": "country_id"},
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true, "pattern": GEO_ID},
			"region_id": {"type": "ref", "required": true, "table": "regions", "pattern": GEO_ID,
				"match": {"currency_code": "currency_code"}},
			"country_id": {"type": "string", "required": true, "pattern": GEO_ID},
			"display_name_key": TEXT,
			"currency_code": {"type": "string", "required": true, "pattern": CURRENCY_CODE},
			"language": {"type": "string", "required": true, "pattern": LANGUAGE},
			"starting_money_minor": {"type": "int", "required": true, "min": 0},
			"starting_day": {"type": "int", "required": true, "min": 1},
			"starting_hour": {"type": "int", "required": true, "min": 0, "max": 23},
			"default_spawn": {"type": "ref", "required": true, "table": "locations",
				"match": {"city_id": "id"}},
			"district_ids": {"type": "array", "required": true, "min_items": 1, "unique": true,
				"items": {"type": "ref", "table": "districts", "pattern": GEO_ID, "match": {"city_id": "id"}}},
			"start_map_id": {"type": "ref", "required": true, "table": "maps", "match": {"city_id": "id"}},
			"game_rules_id": {"type": "ref", "required": true, "table": "game_rules"},
		}},
	},
	"districts": {
		"schema_versions": [1],
		"required_scope": ["city_id"],
		"scope_fields": {"city_id": "city_id"},
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true, "pattern": GEO_ID},
			"city_id": {"type": "ref", "required": true, "table": "cities", "pattern": GEO_ID},
			"name_key": TEXT,
		}},
	},
	"locations": {
		"schema_versions": [1],
		"required_scope": ["city_id"],
		"scope_fields": {"city_id": "city_id"},
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true},
			"city_id": {"type": "ref", "required": true, "table": "cities", "pattern": GEO_ID},
			"district_id": {"type": "ref", "required": true, "table": "districts", "pattern": GEO_ID,
				"match": {"city_id": "city_id"}},
			"kind": {"type": "string", "required": true, "values": [
				"bus_stop", "home", "shop", "restaurant", "job_board", "park", "workplace", "leisure", "entrance"]},
			"name_key": TEXT,
			## The walkable map this place is on; presence checks compare maps (D-020).
			"map_id": {"type": "ref", "required": true, "table": "maps", "match": {"city_id": "city_id"}},
		}},
	},
	"jobs": {
		"schema_versions": [1],
		"required_scope": ["city_id"],
		"scope_fields": {"city_id": "city_id"},
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true},
			"city_id": {"type": "ref", "required": true, "table": "cities", "pattern": GEO_ID},
			"name_key": TEXT,
			"description_key": TEXT,
			"workplace_location_id": {"type": "ref", "required": true, "table": "locations", "match": {"city_id": "city_id"}},
			"hourly_wage_minor": {"type": "int", "required": true, "min": 1},
			"available_from_day": {"type": "int", "required": true, "min": 1},
			"shifts": {"type": "array", "required": true, "min_items": 1, "unique_by": "id",
				"items": {"type": "object", "fields": {
					"id": {"type": "id", "required": true},
					"start_minute_of_day": {"type": "int", "required": true, "min": 0, "max": 1439},
					"duration_minutes": {"type": "int", "required": true, "min": 30, "max": 720},
				}}},
			"minigame": {"type": "id"},  # the shift's minigame (registry id, D-038)
			"work_rates_per_hour": {"type": "array", "required": true, "unique_by": "need_id",
				"items": {"type": "object", "fields": {
					"need_id": {"type": "ref", "required": true, "table": "needs"},
					"per_hour": {"type": "int", "required": true, "min": -100, "max": 100},
				}}},
		}},
	},
	"housing": {
		"schema_versions": [1],
		"required_scope": ["city_id"],
		"scope_fields": {"city_id": "city_id"},
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true},
			"city_id": {"type": "ref", "required": true, "table": "cities", "pattern": GEO_ID},
			"location_id": {"type": "ref", "required": true, "table": "locations", "match": {"city_id": "city_id"}},
			"name_key": TEXT,
			"description_key": TEXT,
			"rent_minor": {"type": "int", "required": true, "min": 1},
			"deposit_minor": {"type": "int", "required": true, "min": 0},
			"period_days": {"type": "int", "required": true, "min": 1, "max": 31},
			## First rent is due at the start of day (signing day + this).
			"first_due_after_days": {"type": "int", "required": true, "min": 1, "max": 31},
		}},
	},
	"transit_routes": {
		"schema_versions": [1],
		"required_scope": ["city_id"],
		"scope_fields": {"city_id": "city_id"},
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true},
			"city_id": {"type": "ref", "required": true, "table": "cities", "pattern": GEO_ID},
			"name_key": TEXT,
			"from_location_id": {"type": "ref", "required": true, "table": "locations", "match": {"city_id": "city_id"}},
			"to_location_id": {"type": "ref", "required": true, "table": "locations", "match": {"city_id": "city_id"}},
			"fare_minor": {"type": "int", "required": true, "min": 0},
			"travel_minutes": {"type": "int", "required": true, "min": 1, "max": 600},
			"first_departure_minute_of_day": {"type": "int", "required": true, "min": 0, "max": 1439},
			"last_departure_minute_of_day": {"type": "int", "required": true, "min": 0, "max": 1439},
		}},
	},
	"shops": {
		"schema_versions": [1],
		"required_scope": ["city_id"],
		"scope_fields": {"city_id": "city_id"},
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true},
			"city_id": {"type": "ref", "required": true, "table": "cities", "pattern": GEO_ID},
			"location_id": {"type": "ref", "required": true, "table": "locations", "match": {"city_id": "city_id"}},
			"name_key": TEXT,
			"stock": {"type": "array", "required": true, "min_items": 1, "unique_by": "item_id",
				"items": {"type": "object", "fields": {
					"item_id": {"type": "ref", "required": true, "table": "items"},
					"price_minor": {"type": "int", "required": true, "min": 1},
				}}},
		}},
	},
	"npcs": {
		"schema_versions": [1],
		"required_scope": ["city_id"],
		"scope_fields": {"city_id": "city_id"},
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true},
			"city_id": {"type": "ref", "required": true, "table": "cities", "pattern": GEO_ID},
			"name_key": TEXT,
			"role_key": TEXT,
			"home_location_id": {"type": "ref", "required": true, "table": "locations", "match": {"city_id": "city_id"}},
			## Public whereabouts by time of day; gaps = at home, indoors (not visible).
			"schedule": {"type": "array", "required": true, "items": {"type": "object", "fields": {
				"start_minute_of_day": {"type": "int", "required": true, "min": 0, "max": 1439},
				"end_minute_of_day": {"type": "int", "required": true, "min": 1, "max": 1440},
				"location_id": {"type": "ref", "required": true, "table": "locations"},
				## Only on these game days (strangers you meet once, D-039). Absent = every day.
				"day_from": {"type": "int", "min": 1, "max": 9999},
				"day_to": {"type": "int", "min": 1, "max": 9999},
			}}},
			"initial_relationship": {"type": "int", "required": true, "min": -100, "max": 100},
			"dialogue_tree_id": {"type": "ref", "required": true, "table": "dialogues"},
			"chat_tree_id": {"type": "ref", "required": true, "table": "dialogues"},
			"appearance": {"type": "object", "required": true, "fields": LOOK_FIELDS},
		}},
	},
	"dialogues": {
		"schema_versions": [1],
		"required_scope": ["city_id"],
		"scope_fields": {"city_id": "city_id"},
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true},
			"city_id": {"type": "ref", "required": true, "table": "cities", "pattern": GEO_ID},
			## in_person: the speaker must be on the player's map; phone / narration: anywhere.
			"channel": {"type": "string", "required": true, "values": ["in_person", "phone", "narration"]},
			"speaker_id": {"type": "ref", "table": "npcs"},
			## Repeatable trees can be revisited; positive relationship changes from them apply
			## at most once per NPC per game day. Others can be completed only once.
			"repeatable": {"type": "bool", "required": true},
			"nodes": {"type": "array", "required": true, "min_items": 1, "unique_by": "id", "items": {"type": "object", "fields": {
				"id": {"type": "id", "required": true},
				"text_key": TEXT,
				"choices": {"type": "array", "required": true, "min_items": 1, "max_items": 3, "unique_by": "id",
					"items": {"type": "object", "fields": {
						"id": {"type": "id", "required": true},
						"text_key": TEXT,
						"effects": EFFECTS,
						"next": {"type": "id"},
					}}},
			}}},
		}},
	},
	"events": {
		"schema_versions": [1],
		"required_scope": ["city_id"],
		"scope_fields": {"city_id": "city_id"},
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true},
			"city_id": {"type": "ref", "required": true, "table": "cities", "pattern": GEO_ID},
			"priority": {"type": "int", "required": true, "min": 0, "max": 1000},
			"once": {"type": "bool", "required": true},
			"conditions": CONDITIONS,
			"effects": EFFECTS,
			"dialogue_tree_id": {"type": "ref", "table": "dialogues"},
		}},
	},
	"quests": {
		"schema_versions": [1],
		"required_scope": ["city_id"],
		"scope_fields": {"city_id": "city_id"},
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true},
			"city_id": {"type": "ref", "required": true, "table": "cities", "pattern": GEO_ID},
			"name_key": TEXT,
			"steps": {"type": "array", "required": true, "min_items": 1, "unique_by": "id", "items": {"type": "object", "fields": {
				"id": {"type": "id", "required": true},
				"text_key": TEXT,
				"hint_key": TEXT,
				"conditions": CONDITIONS,
			}}},
		}},
	},
	"summary_lines": {
		"schema_versions": [1],
		"required_scope": ["city_id"],
		"scope_fields": {"city_id": "city_id"},
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true},
			"city_id": {"type": "ref", "required": true, "table": "cities", "pattern": GEO_ID},
			## One line per group: the first matching line by `order` wins; groups print by `group_rank`.
			"group": {"type": "id", "required": true},
			"group_rank": {"type": "int", "required": true, "min": 0},
			"order": {"type": "int", "required": true, "min": 0},
			"conditions": CONDITIONS,
			"text_key": TEXT,
		}},
	},
	"maps": {
		"schema_versions": [1],
		"required_scope": ["city_id"],
		"scope_fields": {"city_id": "city_id"},
		"record": {"type": "object", "fields": {
			"id": {"type": "id", "required": true},
			"city_id": {"type": "ref", "required": true, "table": "cities", "pattern": GEO_ID},
			"name_key": TEXT,
			"tile_size": {"type": "int", "required": true, "min": 8, "max": 128},
			"rows": {"type": "array", "required": true, "min_items": 1, "items": {"type": "string", "min_length": 1}},
			"legend": {"type": "map", "required": true, "key_pattern": "^.$",
				"values_spec": {"type": "string", "values": TILE_KIND_NAMES}},
			"spawns": {"type": "array", "required": true, "min_items": 1, "unique_by": "location_id",
				"items": {"type": "object", "fields": {
					"location_id": {"type": "ref", "required": true, "table": "locations", "match": {"city_id": "city_id"}},
					"tile": TILE,
				}}},
			## Buildings drawn in 3/4 view. `tiles` = footprint [x, y, w, h] (all "building" cells);
			## the bottom `wall_rows` rows show the facade, the rest plus `roof_overhang_rows` rows
			## above the footprint show the roof (the player can walk behind it).
			"structures": {"type": "array", "required": true, "unique_by": "id",
				"items": {"type": "object", "fields": {
					"id": {"type": "id", "required": true},
					"tiles": {"type": "array", "required": true, "min_items": 4, "max_items": 4,
						"items": {"type": "int", "min": 0, "max": 4096}},
					"wall_rows": {"type": "int", "required": true, "min": 1, "max": 8},
					"roof_overhang_rows": {"type": "int", "required": true, "min": 0, "max": 10},
					"style": {"type": "string", "required": true, "values": STRUCTURE_STYLES},
					"door": {"type": "array", "min_items": 2, "max_items": 2, "items": {"type": "int", "min": 0, "max": 4096}},
					"sign_key": OPTIONAL_TEXT,
				}}},
			"interactables": {"type": "array", "required": true, "unique_by": "id",
				"items": {"type": "object", "fields": {
					"id": {"type": "id", "required": true},
					"kind": {"type": "string", "required": true, "values": INTERACTABLE_KINDS},
					"location_id": {"type": "ref", "required": true, "table": "locations", "match": {"city_id": "city_id"}},
					"tile": TILE,
					"name_key": TEXT,
					"text_key": OPTIONAL_TEXT,
					"shop_id": {"type": "ref", "table": "shops"},
					"activity_id": {"type": "ref", "table": "activities"},
					## Doors (kind "door"): where walking through leads. `walk_in` doors (street ends)
					## trigger by stepping onto them instead of pressing the interact key.
					"target_location_id": {"type": "ref", "table": "locations", "match": {"city_id": "city_id"}},
					"walk_in": {"type": "bool"},
					## Barber (kind "barber"): price and minutes of a haircut.
					"price_minor": {"type": "int", "min": 0, "max": 10000000},
					"service_minutes": {"type": "int", "min": 1, "max": 240},
					## Several activities at one spot (the arcade's machines, the plaza's morning
					## tai chi and evening dancing): interacting lists them.
					"activity_ids": {"type": "array", "unique": true, "min_items": 1,
						"items": {"type": "ref", "table": "activities"}},
					## Visual only. Default: none (e.g. a door drawn by its structure).
					"prop": {"type": "string", "values": INTERACTABLE_PROPS},
				}}},
			## Indoors: lit by lamps, so the day/night tint does not darken it (D-035).
			"indoor": {"type": "bool"},
			"decals": {"type": "array", "items": {"type": "object", "fields": {
				"kind": {"type": "string", "required": true, "values": DECAL_KINDS},
				"tile": TILE,
			}}},
			## Indoor furniture; blocks its FURNITURE footprint (tile = footprint's bottom-left).
			"furniture": {"type": "array", "items": {"type": "object", "fields": {
				"kind": {"type": "string", "required": true, "values": FURNITURE_KINDS},
				"tile": TILE,
			}}},
			## Pictures on the back wall (drawn on "wall_in" tiles, not y-sorted).
			"wall_decor": {"type": "array", "items": {"type": "object", "fields": {
				"kind": {"type": "string", "required": true, "values": WALL_DECOR},
				"tile": TILE,
			}}},
			## Where NPCs scheduled at a location stand on this map (behind the counter, at a
			## table) instead of next to the location's spawn; optional pose.
			"anchors": {"type": "array", "unique_by": "location_id", "items": {"type": "object", "fields": {
				"location_id": {"type": "ref", "required": true, "table": "locations", "match": {"city_id": "city_id"}},
				"tile": TILE,
				"pose": {"type": "string", "values": ["stand", "sit"]},
				"facing": {"type": "string", "values": FACINGS},
			}}},
			## Scenery the player walks through (pavilion, street lamps, flower beds).
			"decor": {"type": "array", "items": {"type": "object", "fields": {
				"kind": {"type": "string", "required": true, "values": DECOR_KINDS},
				"tile": TILE,
			}}},
			## Passers-by walking a route back and forth (D-039). Presentation only; press E next to
			## one for a line of chat (one of `lines`, picked by the day). Segments of `path` must be
			## straight (same row or column) and every tile on them walkable.
			"pedestrians": {"type": "array", "unique_by": "id", "items": {"type": "object", "fields": {
				"id": {"type": "id", "required": true},
				"name_key": TEXT,
				"lines": {"type": "array", "required": true, "min_items": 1, "items": TEXT},
				"path": {"type": "array", "required": true, "min_items": 2, "items": TILE},
				"speed": {"type": "int", "min": 20, "max": 140},
				"hours": HOURS,
				"shirt": COLOR,
				"hair": COLOR,
				"hair_style": LOOK_EXTRA["hair_style"], "outfit": LOOK_EXTRA["outfit"], "figure": LOOK_EXTRA["figure"],
				"skin": OPTIONAL_COLOR, "bottom": OPTIONAL_COLOR, "shoes": OPTIONAL_COLOR, "vest": OPTIONAL_COLOR,
			}}},
			## Background people (chess players, singers, dancers...). Presentation only, never
			## part of the world state: they show while their `activity_id` is open, or during
			## their own `hours`, or always.
			"ambient": {"type": "array", "unique_by": "id", "items": {"type": "object", "fields": {
				"id": {"type": "id", "required": true},
				"tile": TILE,
				"pose": {"type": "string", "required": true, "values": AMBIENT_POSES},
				"facing": {"type": "string", "values": FACINGS},
				"shirt": COLOR,
				"hair": COLOR,
				"hair_style": LOOK_EXTRA["hair_style"], "outfit": LOOK_EXTRA["outfit"], "figure": LOOK_EXTRA["figure"],
				"skin": OPTIONAL_COLOR, "bottom": OPTIONAL_COLOR, "shoes": OPTIONAL_COLOR, "vest": OPTIONAL_COLOR,
				"activity_id": {"type": "ref", "table": "activities"},
				"hours": HOURS,
			}}},
		}},
	},
}

## Per-kind required interactable fields.
## home / job_board / transit / workplace act on whatever their location offers (housing, jobs,
## routes, shifts), so they need no extra field.
const INTERACTABLE_REQUIRES := {"sign": "text_key", "shop": "shop_id", "activity": "activity_id",
	"door": "target_location_id", "barber": "price_minor"}


static func has_table(table: String) -> bool:
	return TABLES.has(table)


static func get_table(table: String) -> Dictionary:
	return TABLES.get(table, {})


static func is_walkable_kind(kind: String) -> bool:
	return TILE_KINDS.get(kind, {}).get("walkable", false)


## Rules beyond the declarative schema. Runs only on records that passed schema validation.
## Returns [{code, path, message}].
static func custom_checks(table: String, record: Dictionary, path: String) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if table == "maps":
		_check_map(record, path, errors)
	elif table == "activities":
		_check_activity(record, path, errors)
	elif table == "items" and record["category"] != "keepsake" and (record["use_effects"] as Array).is_empty():
		errors.append({"code": "E_REQUIRED", "path": path + "/use_effects", "message": "food and drink need at least one effect"})
	return errors


## duration range must contain the default and every preset; opening windows must be non-empty.
static func _check_activity(record: Dictionary, path: String, errors: Array[Dictionary]) -> void:
	var hours: Array = record.get("hours", [])
	for i in hours.size():
		if int(hours[i]["start_minute_of_day"]) >= int(hours[i]["end_minute_of_day"]):
			errors.append({"code": "E_RANGE", "path": "%s/hours/%d" % [path, i],
				"message": "opening window must end after it starts"})
	var d: int = record["duration_minutes"]
	var lo: int = record.get("min_minutes", d)
	var hi: int = record.get("max_minutes", d)
	if lo > d or d > hi:
		errors.append({"code": "E_ACTIVITY_RANGE", "path": path + "/duration_minutes",
			"message": "duration %d is outside %d..%d" % [d, lo, hi]})
	var presets: Array = record.get("duration_presets_minutes", [])
	for i in presets.size():
		if int(presets[i]) < lo or int(presets[i]) > hi:
			errors.append({"code": "E_ACTIVITY_RANGE", "path": "%s/duration_presets_minutes/%d" % [path, i],
				"message": "preset %d is outside %d..%d" % [presets[i], lo, hi]})


static func _check_map(record: Dictionary, path: String, errors: Array[Dictionary]) -> void:
	var rows: Array = record["rows"]
	var legend: Dictionary = record["legend"]
	var width: int = (rows[0] as String).length()
	for y in rows.size():
		var row: String = rows[y]
		if row.length() != width:
			errors.append({"code": "E_MAP_SHAPE", "path": "%s/rows/%d" % [path, y],
				"message": "row has %d columns, expected %d" % [row.length(), width]})
			continue
		for x in row.length():
			if not legend.has(row[x]):
				errors.append({"code": "E_MAP_LEGEND", "path": "%s/rows/%d" % [path, y],
					"message": "character '%s' at column %d is not in the legend" % [row[x], x]})
				break
	if not errors.is_empty():
		return
	var spawns: Array = record["spawns"]
	for i in spawns.size():
		var tile: Array = spawns[i]["tile"]
		var p := "%s/spawns/%d/tile" % [path, i]
		if not _tile_in_bounds(tile, width, rows.size()):
			errors.append({"code": "E_MAP_BOUNDS", "path": p, "message": "tile %s is outside the map" % str(tile)})
		elif not is_walkable_kind(legend[(rows[tile[1]] as String)[tile[0]]]):
			errors.append({"code": "E_MAP_BLOCKED", "path": p, "message": "spawn tile %s is not walkable" % str(tile)})
	_check_structures(record, path, rows, legend, width, errors)
	var furniture: Array = record.get("furniture", [])
	for i in furniture.size():
		var f: Dictionary = furniture[i]
		var size: Array = FURNITURE[f["kind"]]
		for dx in maxi(int(size[0]), 1):
			var tile := [int(f["tile"][0]) + dx, int(f["tile"][1])]
			var p := "%s/furniture/%d/tile" % [path, i]
			if not _tile_in_bounds(tile, width, rows.size()):
				errors.append({"code": "E_MAP_BOUNDS", "path": p, "message": "furniture %s leaves the map" % str(tile)})
				break
			if not is_walkable_kind(legend[(rows[tile[1]] as String)[tile[0]]]):
				errors.append({"code": "E_MAP_BLOCKED", "path": p, "message": "furniture must stand on floor, %s is not" % str(tile)})
				break
	var peds: Array = record.get("pedestrians", [])
	for i in peds.size():
		var route: Array = peds[i]["path"]
		for k in range(1, route.size()):
			var a := Vector2i(route[k - 1][0], route[k - 1][1])
			var b := Vector2i(route[k][0], route[k][1])
			var p := "%s/pedestrians/%d/path/%d" % [path, i, k]
			if a.x != b.x and a.y != b.y:
				errors.append({"code": "E_MAP_PATH", "path": p, "message": "path segments must be straight"})
				continue
			var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
			var t := a
			while true:
				if not _tile_in_bounds([t.x, t.y], width, rows.size()) or not is_walkable_kind(legend[(rows[t.y] as String)[t.x]]):
					errors.append({"code": "E_MAP_BLOCKED", "path": p, "message": "route crosses %s" % str(t)})
					break
				if t == b:
					break
				t += step
	var wall_decor: Array = record.get("wall_decor", [])
	for i in wall_decor.size():
		if not _tile_in_bounds(wall_decor[i]["tile"], width, rows.size()):
			errors.append({"code": "E_MAP_BOUNDS", "path": "%s/wall_decor/%d/tile" % [path, i], "message": "outside the map"})
	for list_name in ["decor", "ambient", "anchors"]:
		var items: Array = record.get(list_name, [])
		for i in items.size():
			var tile: Array = items[i]["tile"]
			var p := "%s/%s/%d/tile" % [path, list_name, i]
			if not _tile_in_bounds(tile, width, rows.size()):
				errors.append({"code": "E_MAP_BOUNDS", "path": p, "message": "tile %s is outside the map" % str(tile)})
			elif not is_walkable_kind(legend[(rows[tile[1]] as String)[tile[0]]]):
				errors.append({"code": "E_MAP_BLOCKED", "path": p, "message": "tile %s is not walkable" % str(tile)})
	var interactables: Array = record["interactables"]
	for i in interactables.size():
		var it: Dictionary = interactables[i]
		var p := "%s/interactables/%d" % [path, i]
		if not _tile_in_bounds(it["tile"], width, rows.size()):
			errors.append({"code": "E_MAP_BOUNDS", "path": p + "/tile", "message": "tile %s is outside the map" % str(it["tile"])})
		var required: String = INTERACTABLE_REQUIRES.get(it["kind"], "")
		if required == "activity_id" and it.has("activity_ids"):
			required = ""
		if not required.is_empty() and not it.has(required):
			errors.append({"code": "E_REQUIRED", "path": "%s/%s" % [p, required],
				"message": "interactable kind '%s' requires '%s'" % [it["kind"], required]})


## Every structure footprint must be in bounds, made only of "building" cells, not overlap another
## structure, and every "building" cell must belong to exactly one structure. Doors sit on the
## footprint's bottom row; wall_rows cannot exceed the footprint height.
static func _check_structures(record: Dictionary, path: String, rows: Array, legend: Dictionary,
		width: int, errors: Array[Dictionary]) -> void:
	var owner := {}  # Vector2i -> structure index
	var structures: Array = record["structures"]
	for i in structures.size():
		var st: Dictionary = structures[i]
		var p := "%s/structures/%d" % [path, i]
		var t: Array = st["tiles"]
		var x0: int = t[0]
		var y0: int = t[1]
		var w: int = t[2]
		var h: int = t[3]
		if w < 1 or h < 1 or x0 + w > width or y0 + h > rows.size():
			errors.append({"code": "E_MAP_BOUNDS", "path": p + "/tiles", "message": "footprint %s is outside the map or empty" % str(t)})
			continue
		if int(st["wall_rows"]) > h:
			errors.append({"code": "E_RANGE", "path": p + "/wall_rows", "message": "wall_rows %d exceeds footprint height %d" % [st["wall_rows"], h]})
		for y in range(y0, y0 + h):
			for x in range(x0, x0 + w):
				var cell := Vector2i(x, y)
				if legend[(rows[y] as String)[x]] != "building":
					errors.append({"code": "E_MAP_STRUCTURE", "path": p + "/tiles", "message": "cell %s is not a building cell" % str(cell)})
					return
				if owner.has(cell):
					errors.append({"code": "E_MAP_STRUCTURE", "path": p + "/tiles", "message": "overlaps structure %d at %s" % [owner[cell], str(cell)]})
					return
				owner[cell] = i
		if st.has("door"):
			var d: Array = st["door"]
			if d[1] != y0 + h - 1 or d[0] < x0 or d[0] >= x0 + w:
				errors.append({"code": "E_MAP_STRUCTURE", "path": p + "/door", "message": "door %s must be on the footprint's bottom row" % str(d)})
	for y in rows.size():
		for x in width:
			if legend[(rows[y] as String)[x]] == "building" and not owner.has(Vector2i(x, y)):
				errors.append({"code": "E_MAP_STRUCTURE", "path": "%s/rows/%d" % [path, y],
					"message": "building cell at column %d belongs to no structure" % x})
				return


static func _tile_in_bounds(tile: Array, width: int, height: int) -> bool:
	return tile[0] < width and tile[1] < height
