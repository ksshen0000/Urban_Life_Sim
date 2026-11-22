class_name StoryConditions
extends RefCounted
## Read-only evaluation of the story condition DSL (ContentSchemas.CONDITION_TYPES) against the
## authoritative world. Used by events, quests, summaries and dialogue availability. Every type is
## explicit; an unknown type evaluates to false (and is rejected earlier by StoryValidator).


static func all_true(conditions: Array, world: WorldState, content: ContentRegistry, actor_id: String = "player") -> bool:
	for c: Dictionary in conditions:
		if not evaluate(c, world, content, actor_id):
			return false
	return true


static func evaluate(c: Dictionary, world: WorldState, content: ContentRegistry, actor_id: String = "player") -> bool:
	var value: Variant = c.get("value")
	match str(c.get("type", "")):
		"day_at_least":
			return world.clock.get_day_index() >= int(value)
		"minute_of_day_at_least":
			return world.clock.get_minute_of_day() >= int(value)
		"minute_of_day_before":
			return world.clock.get_minute_of_day() < int(value)
		"wallet_at_least":
			return (world.get_component("economy") as EconomyService).get_balance(actor_id) >= int(value)
		"wallet_below":
			return (world.get_component("economy") as EconomyService).get_balance(actor_id) < int(value)
		"need_above":
			return (world.get_component("needs") as NeedsSystem).get_value(actor_id, c["need_id"]) > int(value)
		"need_below":
			return (world.get_component("needs") as NeedsSystem).get_value(actor_id, c["need_id"]) < int(value)
		"relationship_at_least":
			return (world.get_component("relationships") as RelationshipSystem).get_value(c["npc_id"]) >= int(value)
		"any_relationship_at_least":
			return (world.get_component("relationships") as RelationshipSystem).max_value() >= int(value)
		"flag_equals":
			var f: Variant = (world.get_component("flags") as FlagsSystem).get_flag(c["key"])
			return typeof(f) == typeof(value) and f == value
		"lease_active":
			return (world.get_component("housing") as HousingSystem).has_lease(actor_id) == bool(value)
		"rent_overdue":
			return (world.get_component("housing") as HousingSystem).is_overdue(actor_id) == bool(value)
		"rent_periods_paid_at_least":
			var housing := world.get_component("housing") as HousingSystem
			return housing.has_lease(actor_id) and int(housing.get_lease(actor_id)["periods_paid"]) >= int(value)
		"shifts_booked_at_least":
			return (world.get_component("jobs") as JobsSystem).get_shifts(actor_id).size() >= int(value)
		"shifts_completed_at_least":
			return (world.get_component("jobs") as JobsSystem).count_with_status(actor_id, "completed") >= int(value)
		"shifts_completed_below":
			return (world.get_component("jobs") as JobsSystem).count_with_status(actor_id, "completed") < int(value)
		"stat_at_least":
			return (world.get_component("stats") as StatsSystem).get_stat(actor_id, c["key"]) >= int(value)
		"on_map":
			return (world.get_component("locations") as LocationSystem).get_map_id(actor_id) == c["map_id"]
		"npc_present":
			var loc := NpcScheduleSystem.new(content).location_of(c["npc_id"], world.clock.get_minute())
			return not loc.is_empty() and (world.get_component("locations") as LocationSystem).is_on_map_of(actor_id, loc)
		"event_fired":
			return (world.get_component("events") as EventSystem).has_fired(c["event_id"])
	return false
