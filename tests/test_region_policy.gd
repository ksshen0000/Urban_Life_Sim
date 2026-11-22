extends "res://tests/framework/test_case.gd"
## T004: region policy interface, China implementation, data-driven selection and swapping.
## The full RegionPolicySwap test against the real WorkSystem lands with T010.

const ContentFixture := preload("res://tests/framework/content_fixture.gd")
const FlatFeePolicy := preload("res://tests/fixtures/flat_fee_region_policy.gd")
const POLICY_FILE := "regions/cn/policy_config.json"

var fx: ContentFixture


func before_each() -> void:
	fx = ContentFixture.new()
	fx.load_real()


func after_each() -> void:
	fx.cleanup()


func _real_content() -> ContentRegistry:
	var reg := ContentRegistry.new()
	reg.load_root("res://content")
	return reg


func _china() -> ChinaRegionPolicy:
	var r := RegionPolicyRegistry.with_builtin_implementations().create_for_city(_real_content(), "CN_LINCHUAN")
	return r["policy"]


## Stand-in for the WorkSystem call pattern (T010): it only talks to the RegionPolicy interface.
@warning_ignore("integer_division")
static func _settle_shift(policy: RegionPolicy, hourly_minor: int, minutes: int, worked_today: int) -> Dictionary:
	if not policy.validate_work_shift({}, minutes, {"worked_minutes_today": worked_today}):
		return {"ok": false}
	var gross := hourly_minor * minutes / 60
	return {"ok": true, "gross": gross, "net": policy.calculate_take_home_pay(gross, {}),
		"currency": policy.get_currency_code()}


func test_city_selects_china_policy_from_content() -> void:
	var r := RegionPolicyRegistry.with_builtin_implementations().create_for_city(_real_content(), "CN_LINCHUAN")
	assert_true(r["ok"], str(r["message"]))
	var policy: RegionPolicy = r["policy"]
	assert_true(policy is ChinaRegionPolicy)
	assert_eq(policy.get_currency_code(), "CNY")
	assert_eq(policy.get_region_id(), "CN")
	assert_eq(policy.get_implementation_id(), "china")
	assert_eq(policy.get_policy_config_id(), "cn_default_policy")


func test_china_take_home_is_integer_and_rounds_deduction_down() -> void:
	var policy := _china()
	assert_eq(policy.calculate_take_home_pay(8800, {}), 8360, "¥88.00 - 5% = ¥83.60")
	assert_eq(policy.calculate_take_home_pay(1, {}), 1, "deduction of 0.05 fen rounds to 0")
	assert_eq(policy.calculate_take_home_pay(123456789, {}), 117283950)
	assert_eq(policy.calculate_take_home_pay(0, {}), 0)
	assert_eq(policy.calculate_take_home_pay(-500, {}), 0, "never negative")


func test_china_recurring_cost_multiplier() -> void:
	assert_eq(_china().calculate_recurring_cost("rent", 60000, {}), 60000, "default unchanged")
	fx.data(POLICY_FILE)["settings"]["recurring_cost_multiplier_bp"] = {"rent": 12000}
	var reg := ContentRegistry.new()
	reg.load_root(fx.write())
	var policy: RegionPolicy = RegionPolicyRegistry.with_builtin_implementations().create_for_city(reg, "CN_LINCHUAN")["policy"]
	assert_eq(policy.calculate_recurring_cost("rent", 60000, {}), 72000)
	assert_eq(policy.calculate_recurring_cost("transit", 300, {}), 300)


func test_china_work_shift_limit() -> void:
	var policy := _china()
	assert_true(policy.validate_work_shift({}, 240, {}))
	assert_true(policy.validate_work_shift({}, 300, {"worked_minutes_today": 420}), "exactly 720 allowed")
	assert_false(policy.validate_work_shift({}, 240, {"worked_minutes_today": 600}))
	assert_false(policy.validate_work_shift({}, 0, {}))


func test_calendar_modifiers_are_data_and_copied() -> void:
	assert_eq(_china().get_calendar_modifiers("day_7"), {})
	fx.data(POLICY_FILE)["settings"]["calendar_modifiers"] = {"day_7": {"shop_price_bp": 11000}}
	var reg := ContentRegistry.new()
	reg.load_root(fx.write())
	var policy: RegionPolicy = RegionPolicyRegistry.with_builtin_implementations().create_for_city(reg, "CN_LINCHUAN")["policy"]
	var mods := policy.get_calendar_modifiers(GameClock.date_key_of(7))
	assert_eq(mods, {"shop_price_bp": 11000})
	mods["shop_price_bp"] = 1
	assert_eq(policy.get_calendar_modifiers("day_7"), {"shop_price_bp": 11000}, "callers get a copy")


func test_invalid_policy_settings_fail_with_path() -> void:
	fx.data(POLICY_FILE)["settings"]["payroll_deduction_bp"] = 20000
	var reg := ContentRegistry.new()
	assert_true(reg.load_root(fx.write()), "settings are opaque to the registry")
	var r := RegionPolicyRegistry.with_builtin_implementations().create_for_city(reg, "CN_LINCHUAN")
	assert_false(r["ok"])
	assert_eq(r["error_code"], "E_POLICY_CONFIG")
	assert_true(str(r["message"]).contains("/settings/payroll_deduction_bp"), str(r["message"]))


func test_unknown_implementation_is_reported() -> void:
	fx.data(POLICY_FILE)["implementation"] = "atlantis"
	var reg := ContentRegistry.new()
	reg.load_root(fx.write())
	var r := RegionPolicyRegistry.with_builtin_implementations().create_for_city(reg, "CN_LINCHUAN")
	assert_eq(r["error_code"], "E_UNKNOWN_POLICY_IMPLEMENTATION")


func test_unknown_city_and_unloaded_content() -> void:
	var registry := RegionPolicyRegistry.with_builtin_implementations()
	assert_eq(registry.create_for_city(_real_content(), "US_NOWHERE")["error_code"], "E_UNKNOWN_CITY")
	assert_eq(registry.create_for_city(ContentRegistry.new(), "CN_LINCHUAN")["error_code"], "E_CONTENT_NOT_LOADED")


func test_register_rejects_duplicates_and_non_policies() -> void:
	var registry := RegionPolicyRegistry.with_builtin_implementations()
	assert_false(registry.register_implementation("china", FlatFeePolicy), "id already taken")
	assert_false(registry.register_implementation("not_policy", preload("res://tests/framework/test_case.gd")))
	assert_false(registry.register_implementation("", FlatFeePolicy))
	assert_true(registry.register_implementation("flat_fee", FlatFeePolicy))
	assert_true(registry.has_implementation("flat_fee"))


func test_swapping_policy_via_config_changes_pay_not_flow() -> void:
	var china_result := _settle_shift(_china(), 2200, 240, 0)
	assert_eq(china_result, {"ok": true, "gross": 8800, "net": 8360, "currency": "CNY"})

	# Same city, same calling code; only the policy config changes.
	fx.data(POLICY_FILE)["implementation"] = "flat_fee"
	fx.data(POLICY_FILE)["settings"] = {"flat_fee_minor": 1000}
	var reg := ContentRegistry.new()
	assert_true(reg.load_root(fx.write()), "\n".join(reg.get_error_strings()))
	var registry := RegionPolicyRegistry.with_builtin_implementations()
	registry.register_implementation("flat_fee", FlatFeePolicy)
	var r := registry.create_for_city(reg, "CN_LINCHUAN")
	assert_true(r["ok"], str(r["message"]))
	var fake_result := _settle_shift(r["policy"], 2200, 240, 0)
	assert_eq(fake_result, {"ok": true, "gross": 8800, "net": 7800, "currency": "CNY"})
	assert_eq(_settle_shift(r["policy"], 2200, 240, 900)["ok"], true, "fake has no daily cap: base rule used")
