extends "res://tests/framework/test_case.gd"
## T002 / spec §8.1 #10 ContentValidation: the registry loads real packs and rejects broken
## content with locatable errors (file + JSON pointer + stable code).

const ContentFixture := preload("res://tests/framework/content_fixture.gd")
const CITY := "regions/cn/cities/linchuan/"
const REGION := "regions/cn/"

var fx: ContentFixture


func before_each() -> void:
	fx = ContentFixture.new()
	fx.load_real()


func after_each() -> void:
	fx.cleanup()


func _load_fixture() -> ContentRegistry:
	var reg := ContentRegistry.new()
	reg.load_root(fx.write())
	return reg


func _expect_error(reg: ContentRegistry, code: String, file_suffix: String, path := "", contains := "") -> void:
	assert_false(reg.is_loaded(), "load should fail")
	for e in reg.get_errors():
		if e["code"] == code and str(e["file"]).ends_with(file_suffix) \
				and (path.is_empty() or e["path"] == path) \
				and (contains.is_empty() or str(e["message"]).contains(contains)):
			return
	fail("expected %s at %s:%s (%s); got:\n          %s" % [code, file_suffix, path, contains,
		"\n          ".join(reg.get_error_strings())])


# --- happy path ---------------------------------------------------------------------------

func test_real_content_loads() -> void:
	var reg := ContentRegistry.new()
	assert_true(reg.load_root("res://content"), "\n".join(reg.get_error_strings()))
	assert_eq(reg.get_pack_ids(), PackedStringArray(["common", "region_cn", "city_cn_linchuan"]))
	var city := reg.get_record("cities", "CN_LINCHUAN")
	assert_eq(typeof(city.get("starting_money_minor")), TYPE_INT, "money normalized to int")
	assert_eq(city.get("starting_money_minor"), 140000)
	assert_eq(city.get("district_ids"), ["OLD_TOWN", "INDUSTRIAL"])
	assert_eq(reg.get_ids("needs"), PackedStringArray(["energy", "hunger", "stress"]))
	assert_true(str(reg.get_record_source("cities", "CN_LINCHUAN").get("file")).ends_with(CITY + "city.json"))
	assert_true(reg.has_record("locations", "old_town_bus_stop"))
	assert_false(reg.has_record("locations", "nowhere"))


func test_story_provider_metadata_kept() -> void:
	var reg := ContentRegistry.new()
	reg.load_root("res://content")
	var providers := reg.get_story_providers()
	assert_eq(providers.size(), 1)
	if providers.size() == 1:
		assert_eq(providers[0]["provider_id"], "template_story_provider")
		assert_eq(providers[0]["schema_version"], 1)
		assert_eq(providers[0]["pack_id"], "city_cn_linchuan")


func test_pack_metadata_and_content_hash() -> void:
	var reg := _load_fixture()
	var pack := reg.get_pack("city_cn_linchuan")
	assert_true(str(pack.get("pack_version")).count(".") == 2, "semver kept")
	assert_eq(pack.get("scope", {}).get("city_id"), "CN_LINCHUAN")
	var hash_a: String = pack.get("content_hash", "")
	assert_eq(hash_a.length(), 64, "sha256 hex")
	var reg_again := _load_fixture()
	assert_eq(reg_again.get_pack("city_cn_linchuan").get("content_hash"), hash_a, "hash is stable")
	fx.data(CITY + "city.json")["starting_money_minor"] = 1
	assert_ne(_load_fixture().get_pack("city_cn_linchuan").get("content_hash"), hash_a, "hash tracks content")


func test_returned_records_are_copies() -> void:
	var reg := _load_fixture()
	var city := reg.get_record("cities", "CN_LINCHUAN")
	city["starting_money_minor"] = 999
	(city["district_ids"] as Array).clear()
	assert_eq(reg.get_record("cities", "CN_LINCHUAN")["starting_money_minor"], 140000)
	assert_eq((reg.get_record("cities", "CN_LINCHUAN")["district_ids"] as Array).size(), 2)


# --- field validation ---------------------------------------------------------------------

func test_missing_required_field() -> void:
	(fx.data(CITY + "city.json") as Dictionary).erase("currency_code")
	_expect_error(_load_fixture(), "E_REQUIRED", CITY + "city.json", "/currency_code")


func test_wrong_types_and_ranges() -> void:
	var city: Dictionary = fx.data(CITY + "city.json")
	city["starting_money_minor"] = 1500.5
	city["starting_hour"] = 24
	city["starting_day"] = "1"
	var reg := _load_fixture()
	_expect_error(reg, "E_TYPE", "city.json", "/starting_money_minor")
	_expect_error(reg, "E_RANGE", "city.json", "/starting_hour")
	_expect_error(reg, "E_TYPE", "city.json", "/starting_day")


func test_unknown_field_is_rejected() -> void:
	fx.data(CITY + "city.json")["starting_mony_minor"] = 1
	_expect_error(_load_fixture(), "E_UNKNOWN_FIELD", "city.json", "/starting_mony_minor")


func test_enum_and_id_pattern() -> void:
	var locs: Array = fx.data(CITY + "locations.json")["records"]
	locs[2]["kind"] = "casino"
	locs[3]["id"] = "Fast Food"
	var reg := _load_fixture()
	_expect_error(reg, "E_ENUM", "locations.json", "/records/2/kind")
	_expect_error(reg, "E_PATTERN", "locations.json", "/records/3/id")


func test_unsupported_schema_version() -> void:
	fx.data(CITY + "city.json")["schema_version"] = 2
	_expect_error(_load_fixture(), "E_SCHEMA_VERSION", "city.json", "/schema_version")


func test_missing_schema_version() -> void:
	(fx.data(CITY + "districts.json") as Dictionary).erase("schema_version")
	_expect_error(_load_fixture(), "E_REQUIRED", "districts.json", "/schema_version")


func test_json_syntax_error_reports_line() -> void:
	fx.set_raw(CITY + "districts.json", "{\n  \"schema_version\": 1,\n  \"records\": [\n}\n")
	_expect_error(_load_fixture(), "E_JSON_PARSE", "districts.json", "", "line")


func test_missing_data_file() -> void:
	fx.remove(CITY + "locations.json")
	_expect_error(_load_fixture(), "E_FILE_MISSING", CITY + "locations.json")


# --- ids and references -------------------------------------------------------------------

func test_duplicate_id_in_same_file() -> void:
	var locs: Array = fx.data(CITY + "locations.json")["records"]
	locs.append((locs[0] as Dictionary).duplicate())
	_expect_error(_load_fixture(), "E_DUPLICATE_ID", "locations.json", "/records/%d/id" % (locs.size() - 1),
		"locations.json:/records/0")


func test_duplicate_id_across_files() -> void:
	fx.set_json(CITY + "more_locations.json", {"schema_version": 1, "records": [
		{"id": "park", "city_id": "CN_LINCHUAN", "district_id": "OLD_TOWN", "kind": "park",
			"name_key": "location.park.name", "map_id": "map_old_town"}]})
	(fx.data(CITY + "pack.json")["files"] as Array).append({"path": "more_locations.json", "table": "locations"})
	_expect_error(_load_fixture(), "E_DUPLICATE_ID", "more_locations.json", "/records/0/id", "locations.json")


func test_unknown_reference() -> void:
	(fx.data(CITY + "city.json")["district_ids"] as Array).append("HARBOR")
	fx.data(CITY + "city.json")["default_spawn"] = "airport"
	var reg := _load_fixture()
	_expect_error(reg, "E_UNKNOWN_REF", "city.json", "/district_ids/2", "HARBOR")
	_expect_error(reg, "E_UNKNOWN_REF", "city.json", "/default_spawn", "airport")


func test_reference_must_be_visible_through_dependencies() -> void:
	fx.data(CITY + "pack.json")["dependencies"] = ["common"]
	_expect_error(_load_fixture(), "E_REF_NOT_VISIBLE", "city.json", "/region_id", "region_cn")


func test_currency_must_match_region() -> void:
	fx.data(CITY + "city.json")["currency_code"] = "USD"
	_expect_error(_load_fixture(), "E_REF_MISMATCH", "city.json", "/region_id", "currency_code")


func test_scope_mismatch() -> void:
	var locs: Array = fx.data(CITY + "locations.json")["records"]
	locs[1]["city_id"] = "CN_OTHER"
	_expect_error(_load_fixture(), "E_SCOPE_MISMATCH", "locations.json", "/records/1/city_id")


func test_city_scoped_table_needs_city_scope() -> void:
	fx.set_json(REGION + "stray_locations.json", {"schema_version": 1, "records": [
		{"id": "stray", "city_id": "CN_LINCHUAN", "district_id": "OLD_TOWN", "kind": "park",
			"name_key": "location.park.name", "map_id": "map_old_town"}]})
	(fx.data(REGION + "pack.json")["files"] as Array).append({"path": "stray_locations.json", "table": "locations"})
	_expect_error(_load_fixture(), "E_SCOPE_MISSING", "stray_locations.json", "/records/0")


# --- pack manifests -----------------------------------------------------------------------

func test_missing_pack_dependency() -> void:
	fx.data(CITY + "pack.json")["dependencies"] = ["region_xx"]
	_expect_error(_load_fixture(), "E_PACK_DEPENDENCY", CITY + "pack.json", "/dependencies/0", "region_xx")


func test_dependency_cycle() -> void:
	fx.data("common/pack.json")["dependencies"] = ["city_cn_linchuan"]
	_expect_error(_load_fixture(), "E_PACK_CYCLE", "common/pack.json")


func test_path_traversal_rejected() -> void:
	var files: Array = fx.data(CITY + "pack.json")["files"]
	var first := files.size()
	files.append({"path": "../region.json", "table": "regions"})
	files.append({"path": "res://project.godot", "table": "regions"})
	var reg := _load_fixture()
	_expect_error(reg, "E_PATH", CITY + "pack.json", "/files/%d/path" % first)
	_expect_error(reg, "E_PATH", CITY + "pack.json", "/files/%d/path" % (first + 1))


func test_unknown_table_rejected() -> void:
	(fx.data(CITY + "pack.json")["files"] as Array)[0]["table"] = "citys"
	_expect_error(_load_fixture(), "E_UNKNOWN_TABLE", CITY + "pack.json", "/files/0/table")


func test_invalid_story_provider_metadata() -> void:
	(fx.data(CITY + "pack.json")["story_providers"] as Array)[0]["schema_version"] = 0
	_expect_error(_load_fixture(), "E_RANGE", CITY + "pack.json", "/story_providers/0/schema_version")


func test_duplicate_pack_id() -> void:
	fx.set_json("regions/cn/cities/copy/pack.json", fx.data(CITY + "pack.json").duplicate(true))
	_expect_error(_load_fixture(), "E_DUPLICATE_PACK", "pack.json", "/pack_id")


# --- failure semantics --------------------------------------------------------------------

func test_failed_load_leaves_registry_empty() -> void:
	fx.data(CITY + "city.json")["default_spawn"] = "airport"
	var reg := _load_fixture()
	assert_false(reg.is_loaded())
	assert_false(reg.has_record("cities", "CN_LINCHUAN"), "no partial data after failure")
	assert_false(reg.has_record("needs", "hunger"), "even valid packs are dropped")
	assert_eq(reg.get_pack_ids().size(), 0)
	assert_eq(reg.get_story_providers().size(), 0)


func test_reports_all_errors_in_one_pass() -> void:
	(fx.data(CITY + "city.json") as Dictionary).erase("language")
	fx.data("common/needs.json")["records"][0]["initial_value"] = 101
	var reg := _load_fixture()
	_expect_error(reg, "E_REQUIRED", "city.json", "/language")
	_expect_error(reg, "E_RANGE", "needs.json", "/records/0/initial_value")


func test_reload_resets_previous_state() -> void:
	var reg := ContentRegistry.new()
	assert_true(reg.load_root("res://content"))
	fx.data(CITY + "city.json")["default_spawn"] = "airport"
	assert_false(reg.load_root(fx.write()))
	assert_false(reg.has_record("cities", "CN_LINCHUAN"))
	assert_true(reg.load_root("res://content"), "registry is reusable after a failed load")
	assert_eq(reg.get_errors().size(), 0)


# --- M1 tables: text, shops, maps ---------------------------------------------------------

const MAP := CITY + "maps/old_town.json"


func test_missing_text_key_is_an_error() -> void:
	fx.data("common/items.json")["records"][0]["name_key"] = "item.does_not.exist"
	_expect_error(_load_fixture(), "E_UNKNOWN_REF", "common/items.json", "/records/0/name_key", "text")


func test_text_must_be_visible_to_the_referencing_pack() -> void:
	# A common item cannot use a city-only string: common does not depend on the city pack.
	fx.data("common/items.json")["records"][0]["name_key"] = "city.cn_linchuan.name"
	_expect_error(_load_fixture(), "E_REF_NOT_VISIBLE", "common/items.json", "/records/0/name_key")


func test_duplicate_text_key_across_packs() -> void:
	(fx.data(CITY + "text.json")["records"] as Array).append({"id": "need.hunger.name", "zh_CN": "饿"})
	_expect_error(_load_fixture(), "E_DUPLICATE_ID", CITY + "text.json", "", "common/text.json")


func test_shop_stock_item_listed_once() -> void:
	var stock: Array = fx.data(CITY + "shops.json")["records"][0]["stock"]
	stock.append({"item_id": stock[0]["item_id"], "price_minor": 1})
	_expect_error(_load_fixture(), "E_DUPLICATE_ITEM", "shops.json", "/records/0/stock/%d" % (stock.size() - 1))


func test_shop_stock_unknown_item() -> void:
	var stock: Array = fx.data(CITY + "shops.json")["records"][0]["stock"]
	stock.append({"item_id": "item_caviar", "price_minor": 100000})
	_expect_error(_load_fixture(), "E_UNKNOWN_REF", "shops.json", "/records/0/stock/%d/item_id" % (stock.size() - 1))


func test_map_rows_must_be_rectangular_and_in_legend() -> void:
	var rows: Array = fx.data(MAP)["rows"]
	rows[3] = (rows[3] as String) + "."
	rows[4] = (rows[4] as String).substr(0, 10) + "?" + (rows[4] as String).substr(11)
	var reg := _load_fixture()
	_expect_error(reg, "E_MAP_SHAPE", MAP, "/rows/3")
	_expect_error(reg, "E_MAP_LEGEND", MAP, "/rows/4", "'?'")


func test_map_spawn_must_be_walkable_and_in_bounds() -> void:
	fx.data(MAP)["spawns"][0]["tile"] = [0, 0]
	_expect_error(_load_fixture(), "E_MAP_BLOCKED", MAP, "/spawns/0/tile")
	fx.data(MAP)["spawns"][0]["tile"] = [400, 1]
	_expect_error(_load_fixture(), "E_MAP_BOUNDS", MAP, "/spawns/0/tile")


func test_interactable_kind_requires_its_target() -> void:
	var its: Array = fx.data(MAP)["interactables"]
	for i in its.size():
		if its[i]["kind"] == "shop":
			(its[i] as Dictionary).erase("shop_id")
			_expect_error(_load_fixture(), "E_REQUIRED", MAP, "/interactables/%d/shop_id" % i)
			return
	fail("fixture has no shop interactable")


func test_interactable_ids_unique() -> void:
	var its: Array = fx.data(MAP)["interactables"]
	its.append((its[0] as Dictionary).duplicate(true))
	_expect_error(_load_fixture(), "E_DUPLICATE_ITEM", MAP, "/interactables/%d" % (its.size() - 1))



func test_structure_footprint_rules() -> void:
	var sts: Array = fx.data(MAP)["structures"]
	sts[0]["tiles"] = [1, 1, 3, 3]  # covers non-building cells
	_expect_error(_load_fixture(), "E_MAP_STRUCTURE", MAP, "/structures/0/tiles", "not a building cell")


func test_every_building_cell_needs_a_structure() -> void:
	(fx.data(MAP)["structures"] as Array).remove_at(0)
	_expect_error(_load_fixture(), "E_MAP_STRUCTURE", MAP, "", "belongs to no structure")


func test_structure_door_on_bottom_row() -> void:
	fx.data(MAP)["structures"][0]["door"] = [5, 2]
	_expect_error(_load_fixture(), "E_MAP_STRUCTURE", MAP, "/structures/0/door")


func test_location_map_must_exist() -> void:
	fx.data(CITY + "locations.json")["records"][0]["map_id"] = "map_moon"
	_expect_error(_load_fixture(), "E_UNKNOWN_REF", "locations.json", "/records/0/map_id")


## T019: English is optional per text, but where it exists it must use the same placeholders as the
## Chinese source, and every interface text in the common pack has an English version.
func test_english_texts_match_placeholders() -> void:
	var reg := ContentRegistry.new()
	assert_true(reg.load_root("res://content"))
	var re := RegEx.create_from_string("\\{[a-z_]+\\}")
	for r in reg.get_records("text"):
		var en: String = r.get("en", "")
		if en.is_empty():
			assert_false(str(r["id"]).begins_with("ui."), "interface text %s has English" % r["id"])
			continue
		var a: Array = re.search_all(r["zh_CN"]).map(func(m: RegExMatch) -> String: return m.get_string())
		var b: Array = re.search_all(en).map(func(m: RegExMatch) -> String: return m.get_string())
		a.sort()
		b.sort()
		assert_eq(b, a, "placeholders of %s" % r["id"])


func test_activity_duration_range_rules() -> void:
	var sleep: Dictionary = fx.data("common/activities.json")["records"][0]
	sleep["duration_presets_minutes"] = [60, 900]
	_expect_error(_load_fixture(), "E_ACTIVITY_RANGE", "activities.json", "/records/0/duration_presets_minutes/1")
	sleep["duration_presets_minutes"] = [60]
	sleep["min_minutes"] = 600  # default 480 below the minimum
	_expect_error(_load_fixture(), "E_ACTIVITY_RANGE", "activities.json", "/records/0/duration_minutes")


func test_ambient_and_hours_rules() -> void:
	fx.data(MAP)["ambient"][0]["tile"] = [1, 8]  # road is fine
	fx.data(MAP)["ambient"][1]["tile"] = [0, 0]  # wall
	_expect_error(_load_fixture(), "E_MAP_BLOCKED", MAP, "/ambient/1/tile")


func test_activity_hours_must_be_a_window() -> void:
	fx.data(CITY + "activities.json")["records"][0]["hours"] = [{"start_minute_of_day": 600, "end_minute_of_day": 600}]
	_expect_error(_load_fixture(), "E_RANGE", "activities.json", "/records/0/hours/0")
