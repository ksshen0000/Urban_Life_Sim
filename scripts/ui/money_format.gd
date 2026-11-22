class_name MoneyFormat
extends RefCounted
## Presentation-only currency formatting (spec §2.3: the UI formats; the simulation stores
## integer minor units). Symbols are display choices, not region rules.

const PREFIX_SYMBOLS := {"CNY": "¥", "USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥"}


## format_minor(150000, "CNY", 2) -> "¥1,500.00"; unknown codes -> "1,500.00 PLN".
static func format_minor(amount_minor: int, currency_code: String, minor_digits: int = 2) -> String:
	var negative := amount_minor < 0
	var abs_amount := absi(amount_minor)
	var scale := int(pow(10, minor_digits))
	@warning_ignore("integer_division")
	var major := abs_amount / scale
	var minor := abs_amount % scale
	var body := _group_thousands(str(major))
	if minor_digits > 0:
		body += "." + str(minor).pad_zeros(minor_digits)
	var minus := "-" if negative else ""
	if PREFIX_SYMBOLS.has(currency_code):
		return minus + PREFIX_SYMBOLS[currency_code] + body
	return "%s%s %s" % [minus, body, currency_code]


static func _group_thousands(digits: String) -> String:
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
