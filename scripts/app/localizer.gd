class_name Localizer
extends RefCounted
## Builds Godot Translations from the validated `text` table of loaded content packs and installs
## them in TranslationServer, so UI code uses plain `tr(key)`. zh_CN is the source/fallback
## language; an empty `en` entry falls back to it (spec §6: simplified Chinese first, English ready).

const SOURCE_LOCALE := "zh_CN"
const LOCALES := ["zh_CN", "en"]

static var _installed: Array[Translation] = []


static func build(content: ContentRegistry) -> Array[Translation]:
	var out: Array[Translation] = []
	for locale: String in LOCALES:
		var t := Translation.new()
		t.locale = locale
		for record in content.get_records(ContentSchemas.TEXT_TABLE):
			var text: String = record.get(locale, "")
			if text.is_empty():
				text = record[SOURCE_LOCALE]
			t.add_message(record["id"], text)
		out.append(t)
	return out


## Replaces previously installed content translations and selects `locale`.
static func install(content: ContentRegistry, locale: String = SOURCE_LOCALE) -> void:
	for t in _installed:
		TranslationServer.remove_translation(t)
	_installed = build(content)
	for t in _installed:
		TranslationServer.add_translation(t)
	TranslationServer.set_locale(locale)


static func uninstall() -> void:
	for t in _installed:
		TranslationServer.remove_translation(t)
	_installed.clear()


## tr() + {placeholder} substitution.
static func text(key: String, values: Dictionary = {}) -> String:
	return String(TranslationServer.translate(key)).format(values)
