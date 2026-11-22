extends "res://tests/framework/test_case.gd"
## T007 + spec §8.1 #2 MoneyInteger, #3 InsufficientFunds.

const Sessions := preload("res://tests/framework/session_factory.gd")
const P := SimulationSession.PLAYER_ID


class DirectWrite extends CommandHandler:
	## Proves systems refuse writes outside a command's apply phase.
	var results: Dictionary = {}

	func get_action() -> String:
		return "direct_write"

	func validate(ctx: CommandContext) -> String:
		results["debit_in_validate"] = (ctx.world.get_component("economy") as EconomyService).try_debit(ctx, "player", 1, "x")
		return ""

	func apply(_ctx: CommandContext) -> String:
		return ""


func _buy(s: SimulationSession, shop: String, item: String, qty := 1) -> CommandResult:
	return s.submit("buy_item", {"shop_id": shop, "item_id": item, "quantity": qty})


func test_new_game_wallet_from_city_config() -> void:
	var s := Sessions.create()
	assert_eq(s.economy.get_balance(P), Sessions.start_money(), "from city.json")
	assert_eq(s.economy.get_currency_code(), "CNY")
	assert_eq(s.view_player()["inventory"], {})


func test_acceptance_20_yuan_buys_18_yuan_meal_then_fails() -> void:
	var s := Sessions.create({"starting_money_minor": 2000})
	var first := _buy(s, "shop_fast_food", "item_simple_meal")
	assert_true(first.ok, str(first.error_code))
	assert_eq(s.economy.get_balance(P), 200, "¥20 - ¥18 = ¥2")
	assert_eq(s.inventory.count(P, "item_simple_meal"), 1)
	var second := _buy(s, "shop_fast_food", "item_simple_meal")
	assert_eq(second.error_code, "E_INSUFFICIENT_FUNDS")
	assert_eq(s.economy.get_balance(P), 200, "no negative balance, nothing charged")
	assert_eq(s.inventory.count(P, "item_simple_meal"), 1, "inventory unchanged on failure")
	assert_eq(s.economy.get_ledger(P).size(), 1, "failed purchase leaves no ledger entry")


func test_ledger_entry_fields() -> void:
	var s := Sessions.create()
	_buy(s, "shop_convenience_store", "item_drink", 2)
	var ledger := s.economy.get_ledger(P)
	assert_eq(ledger.size(), 1)
	var t: Dictionary = ledger[0]
	assert_eq(t["transaction_id"], "txn_00000001")
	assert_eq(t["amount_minor"], -1000)
	assert_eq(t["balance_after_minor"], Sessions.start_money() - 1000)
	assert_eq(t["currency_code"], "CNY")
	assert_eq(t["timestamp_game_minute"], s.world.clock.get_minute())
	assert_eq(t["reason"], "purchase:shop_convenience_store:item_drink")
	assert_true(str(t["event_id"]).begins_with("evt_"))


func test_money_stays_integer_over_many_small_purchases() -> void:
	var s := Sessions.create()
	for i in 30:
		_buy(s, "shop_convenience_store", "item_drink")  # ¥5.00 each, stack limit 99
	var balance := s.economy.get_balance(P)
	assert_eq(typeof(balance), TYPE_INT)
	assert_eq(balance, Sessions.start_money() - 30 * 500)
	var sum := 0
	for t in s.economy.get_ledger(P):
		sum += int(t["amount_minor"])
	assert_eq(Sessions.start_money() + sum, balance, "ledger reconciles exactly")


func test_purchase_validation_errors_change_nothing() -> void:
	var s := Sessions.create()
	var before := s.world.to_dict()
	assert_eq(_buy(s, "shop_nowhere", "item_drink").error_code, "E_UNKNOWN_SHOP")
	assert_eq(_buy(s, "shop_fast_food", "item_instant_food").error_code, "E_ITEM_NOT_SOLD")
	assert_eq(_buy(s, "shop_fast_food", "item_drink", 0).error_code, "E_INVALID_ARGUMENTS")
	assert_eq(_buy(s, "shop_fast_food", "item_drink", 21).error_code, "E_INVALID_ARGUMENTS")
	assert_eq(s.submit("buy_item", {"shop_id": "shop_fast_food", "item_id": "item_drink"}, "npc_chen_yu").error_code,
		"E_FORBIDDEN_ACTOR", "actors without a wallet cannot buy")
	assert_eq(s.world.to_dict(), before)


func test_stack_limit() -> void:
	var s := Sessions.create()
	for i in 4:
		_buy(s, "shop_convenience_store", "item_drink", 20)
	assert_eq(s.inventory.count(P, "item_drink"), 80)
	assert_eq(_buy(s, "shop_convenience_store", "item_drink", 20).error_code, "E_INVENTORY_FULL")
	assert_true(_buy(s, "shop_convenience_store", "item_drink", 19).ok)
	assert_eq(s.inventory.count(P, "item_drink"), 99)


func test_systems_refuse_writes_outside_apply() -> void:
	var s := Sessions.create()
	var h := DirectWrite.new()
	s.processor.register_handler(h)
	s.submit("direct_write")
	assert_eq(h.results["debit_in_validate"], "E_NOT_IN_COMMAND")
	assert_eq(s.economy.try_debit(null, P, 100, "ui hack"), "E_NOT_IN_COMMAND")
	assert_eq(s.inventory.add(null, P, "item_drink", 1), "E_NOT_IN_COMMAND")
	assert_eq(s.needs.change(null, P, "hunger", -50, "ui hack"), "E_NOT_IN_COMMAND")
	assert_eq(s.economy.get_balance(P), Sessions.start_money())


func test_use_item_applies_effects_and_time() -> void:
	var s := Sessions.create()
	_buy(s, "shop_fast_food", "item_simple_meal")
	var hunger_before := s.needs.get_value(P, "hunger")
	var minute_before := s.world.clock.get_minute()
	var r := s.submit("use_item", {"item_id": "item_simple_meal"})
	assert_true(r.ok, str(r.error_code))
	assert_eq(s.inventory.count(P, "item_simple_meal"), 0)
	assert_eq(s.world.clock.get_minute(), minute_before + 20, "eating takes 20 minutes")
	# -35 immediately (25 -> 0, clamped), then +4/h awake for 20 min = +1 (carry 20)
	assert_eq(hunger_before, 25)
	assert_eq(s.needs.get_value(P, "hunger"), 1)
	assert_eq(s.submit("use_item", {"item_id": "item_simple_meal"}).error_code, "E_NOT_ENOUGH_ITEMS")
	assert_eq(s.submit("use_item", {"item_id": "item_caviar"}).error_code, "E_UNKNOWN_ITEM")


func test_drink_lowers_stress_without_time() -> void:
	var s := Sessions.create()
	_buy(s, "shop_convenience_store", "item_drink")
	var minute := s.world.clock.get_minute()
	s.submit("use_item", {"item_id": "item_drink"})
	assert_eq(s.needs.get_value(P, "stress"), 17)
	assert_eq(s.world.clock.get_minute(), minute)


func test_money_format() -> void:
	assert_eq(MoneyFormat.format_minor(150000, "CNY", 2), "¥1,500.00")
	assert_eq(MoneyFormat.format_minor(200, "CNY", 2), "¥2.00")
	assert_eq(MoneyFormat.format_minor(5, "CNY", 2), "¥0.05")
	assert_eq(MoneyFormat.format_minor(-123456789, "USD", 2), "-$1,234,567.89")
	assert_eq(MoneyFormat.format_minor(1500, "JPY", 0), "¥1,500")
	assert_eq(MoneyFormat.format_minor(99900, "PLN", 2), "999.00 PLN")
