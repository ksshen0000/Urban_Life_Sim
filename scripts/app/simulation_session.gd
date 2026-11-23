class_name SimulationSession
extends RefCounted
## One running game world, headless and testable: content + region policy + WorldState with its
## components + CommandProcessor with the registered handlers. Scenes and UI talk to the world
## only through `submit()` (writes) and the `view_*` / getter methods (read-only copies).

const PLAYER_ID := "player"
const CLOCK_ACTOR := "system:clock"

var content: ContentRegistry
var policy: RegionPolicy
var city: Dictionary
var region: Dictionary
var rules: Dictionary
var world: WorldState
var processor: CommandProcessor
var economy: EconomyService
var inventory: InventorySystem
var needs: NeedsSystem
var locations: LocationSystem
var jobs: JobsSystem
var housing: HousingSystem
var flags: FlagsSystem
var stats: StatsSystem
var relationships: RelationshipSystem
var events: EventSystem
var dialogue: DialogueSystem
var quests: QuestSystem
var npc_schedule: NpcScheduleSystem
var profile: ProfileSystem

## Max story commands (events + quest steps) run after one command: event-storm guard (§13.4).
const STORY_STEP_BUDGET := 8
var _in_story_pass := false
## False isolates game mechanics from story events (system-level tests); the game always runs with true.
var story_enabled := true

var _proposal_seq := 0
var _pending_exploration_minutes := 0


## Returns {ok, error_code, message, session}. `overrides` may set player_profile ({name, look}
## from the character creator) and, for tests / debug, starting_money_minor and story_enabled.
static func create_new(p_content: ContentRegistry, policies: RegionPolicyRegistry, city_id: String,
		overrides: Dictionary = {}) -> Dictionary:
	if p_content == null or not p_content.is_loaded():
		return _fail("E_CONTENT_NOT_LOADED", "content registry is not loaded")
	if not p_content.has_record("cities", city_id):
		return _fail("E_UNKNOWN_CITY", "city '%s' is not defined" % city_id)
	var built := policies.create_for_city(p_content, city_id)
	if not built["ok"]:
		return _fail(built["error_code"], built["message"])

	var s := SimulationSession.new()
	s.story_enabled = bool(overrides.get("story_enabled", true))
	s.content = p_content
	s.policy = built["policy"]
	s.city = p_content.get_record("cities", city_id)
	s.region = p_content.get_record("regions", s.city["region_id"])
	s.rules = p_content.get_record("game_rules", s.city["game_rules_id"])

	s.world = WorldState.new(GameClock.minute_from_day_time(s.city["starting_day"], s.city["starting_hour"]))
	s.world.clock.set_minutes_per_real_second(1000.0 / float(s.rules["exploration_real_ms_per_game_minute"]))
	s.economy = EconomyService.new(s.city["currency_code"], s.rules["ledger_keep_entries"])
	s.economy.open_account(PLAYER_ID, int(overrides.get("starting_money_minor", s.city["starting_money_minor"])))
	s.inventory = InventorySystem.new(s.rules["inventory_stack_limit"])
	s.inventory.open_owner(PLAYER_ID)
	s.needs = NeedsSystem.new(p_content.get_records("needs"))
	s.needs.add_owner(PLAYER_ID)
	s.locations = LocationSystem.new(p_content)
	s.locations.place(PLAYER_ID, s.city["default_spawn"])
	s.jobs = JobsSystem.new(p_content)
	s.housing = HousingSystem.new(p_content)
	# Registration order = TimeFlow hook order: needs react first, then missed shifts, then rent.
	s.world.register_component("needs", s.needs)
	s.world.register_component("economy", s.economy)
	s.world.register_component("inventory", s.inventory)
	s.world.register_component("locations", s.locations)
	s.world.register_component("jobs", s.jobs)
	s.world.register_component("housing", s.housing)
	s.flags = FlagsSystem.new()
	s.stats = StatsSystem.new()
	s.relationships = RelationshipSystem.new(p_content)
	s.events = EventSystem.new(p_content)
	s.dialogue = DialogueSystem.new()
	s.quests = QuestSystem.new(p_content)
	s.npc_schedule = NpcScheduleSystem.new(p_content)
	s.profile = ProfileSystem.new()
	if not s.profile.set_initial(PLAYER_ID, overrides.get("player_profile", ProfileSystem.default_profile())):
		return _fail("E_INVALID_PROFILE", "player profile is not valid")
	for pair: Array in [["flags", s.flags], ["stats", s.stats], ["relationships", s.relationships],
			["events", s.events], ["dialogue", s.dialogue], ["quests", s.quests], ["profile", s.profile]]:
		s.world.register_component(pair[0], pair[1])

	# need_effects (D-037): off only for mechanics tests that fast-forward without sleeping
	s.rules["need_effects"] = bool(overrides.get("need_effects", true))
	s.processor = CommandProcessor.new(s.world, {"content": p_content, "region_policy": s.policy, "rules": s.rules})
	for handler: CommandHandler in [AdvanceTimeHandler.new(), BuyItemHandler.new(), UseItemHandler.new(),
			PerformActivityHandler.new(), BookShiftHandler.new(), WorkShiftHandler.new(), SignLeaseHandler.new(),
			PayRentHandler.new(), TakeRouteHandler.new(), TriggerEventHandler.new(), ChooseDialogueHandler.new(),
			DismissStoryHandler.new(), AdvanceQuestHandler.new(), SetProfileHandler.new(), UseDoorHandler.new(), GetHaircutHandler.new(), ApproachNpcHandler.new()]:
		s.processor.register_handler(handler)
	return {"ok": true, "error_code": null, "message": "", "session": s}


static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error_code": code, "message": message, "session": null}


## Submits a proposal with a fresh id. Ids embed the world revision, so ids issued after loading
## a save never collide with commands committed before it.
func submit(action: String, arguments: Dictionary = {}, actor_id: String = PLAYER_ID,
		target_id: String = "") -> CommandResult:
	var r := _submit_raw(action, arguments, actor_id, target_id)
	if r.ok and not _in_story_pass:
		run_story_rules()
	return r


## After a world change: fire eligible story events (priority order) and complete quest steps
## whose conditions now hold, each as its own system command. Bounded by STORY_STEP_BUDGET.
func run_story_rules() -> void:
	if not story_enabled:
		return
	_in_story_pass = true
	var failed := {}
	for i in STORY_STEP_BUDGET:
		var progressed := false
		for event_id in events.eligible_events(world):
			if failed.has(event_id):
				continue
			var r := _submit_raw(TriggerEventHandler.ACTION, {"event_id": event_id}, TriggerEventHandler.ACTOR_PREFIX + event_id)
			if r.ok:
				progressed = true
				break
			failed[event_id] = true
		if not progressed:
			for quest_id in quests.advanceable_quests(world):
				if _submit_raw(AdvanceQuestHandler.ACTION, {"quest_id": quest_id}, AdvanceQuestHandler.ACTOR).ok:
					progressed = true
					break
		if not progressed:
			break
	_in_story_pass = false


func _submit_raw(action: String, arguments: Dictionary, actor_id: String, target_id: String = "") -> CommandResult:
	_proposal_seq += 1
	var pid := "%s.r%d.%d" % [actor_id.replace("/", "."), world.revision, _proposal_seq]
	var p := ActionProposal.create(pid, actor_id, action, arguments, target_id)
	p.issued_at_game_minute = world.clock.get_minute()
	return processor.apply(p)


## Exploration time: converts real seconds into game minutes and commits them in
## `exploration_step_minutes` steps. Returns the CommandResult of a commit, or null.
func advance_exploration(real_delta_seconds: float) -> CommandResult:
	_pending_exploration_minutes += world.clock.accumulate_real_time(real_delta_seconds)
	var step: int = rules["exploration_step_minutes"]
	if _pending_exploration_minutes < step:
		return null
	@warning_ignore("integer_division")
	var minutes: int = (_pending_exploration_minutes / step) * step
	_pending_exploration_minutes -= minutes
	return submit(AdvanceTimeHandler.ACTION, {"minutes": minutes}, CLOCK_ACTOR)


## Saved with the game so proposal ids after a load continue the same sequence (replays of a
## loaded game then produce the same journal as the uninterrupted game).
func get_proposal_seq() -> int:
	return _proposal_seq


func set_proposal_seq(value: int) -> void:
	_proposal_seq = maxi(value, 0)


func get_currency_minor_digits() -> int:
	return int(region.get("currency_minor_digits", 2))


## Read-only snapshot for the HUD and menus.
func view_player() -> Dictionary:
	return {
		"minute": world.clock.get_minute(),
		"day_index": world.clock.get_day_index(),
		"minute_of_day": world.clock.get_minute_of_day(),
		"balance_minor": economy.get_balance(PLAYER_ID),
		"currency_code": economy.get_currency_code(),
		"currency_minor_digits": get_currency_minor_digits(),
		"needs": needs.get_values(PLAYER_ID),
		"inventory": inventory.get_items(PLAYER_ID),
		"map_id": locations.get_map_id(PLAYER_ID),
		"location_id": locations.get_location_id(PLAYER_ID),
		"lease": housing.get_lease(PLAYER_ID),
		"shifts": jobs.get_shifts(PLAYER_ID),
		"relationships": relationships.get_all(),
	}


## The player's active need states (D-037), or none when need effects are switched off.
func need_states() -> Array[Dictionary]:
	if not rules.get("need_effects", true):
		return [] as Array[Dictionary]
	return NeedStates.active(content, needs.get_values(PLAYER_ID))


## NPCs visible on the player's current map right now: {npc_id: location_id}.
func present_npcs() -> Dictionary:
	return npc_schedule.present_on_map(locations.get_map_id(PLAYER_ID), world.clock.get_minute())
