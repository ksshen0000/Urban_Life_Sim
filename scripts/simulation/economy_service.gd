class_name EconomyService
extends RefCounted
## Wallets and the transaction ledger (spec §3.6). A WorldState component.
##
## Money is integer minor units (CNY fen). Writes (`credit`, `try_debit`) only succeed while a
## command is applying (ctx.can_write()); UI and story code cannot change balances directly.
## Balances never go negative: a debit that does not fit fails with E_INSUFFICIENT_FUNDS and
## changes nothing. Every posting gets a transaction_id, game-minute timestamp, reason, signed
## amount and currency code, and emits a `wallet_changed` event.

const SCHEMA_VERSION := 1
const MAX_AMOUNT_MINOR := 1_000_000_000_000
const STATE_SCHEMA := {"type": "object", "fields": {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": SCHEMA_VERSION},
	"currency_code": {"type": "string", "required": true, "pattern": "^[A-Z]{3}$"},
	"next_transaction_seq": {"type": "int", "required": true, "min": 1},
	"balances": {"type": "map", "required": true, "values_spec": {"type": "int", "min": 0}},
	"ledger": {"type": "array", "required": true, "items": {"type": "object", "fields": {
		"transaction_id": {"type": "string", "required": true, "min_length": 1},
		"timestamp_game_minute": {"type": "int", "required": true, "min": 0},
		"owner_id": {"type": "string", "required": true, "min_length": 1},
		"amount_minor": {"type": "int", "required": true},
		"balance_after_minor": {"type": "int", "required": true, "min": 0},
		"currency_code": {"type": "string", "required": true},
		"reason": {"type": "string", "required": true},
		"event_id": {"type": "string", "required": true},
	}}},
}}

var _currency_code: String
var _ledger_keep: int
var _balances: Dictionary = {}
var _ledger: Array[Dictionary] = []
var _next_transaction_seq := 1


func _init(currency_code: String = "", ledger_keep: int = 200) -> void:
	_currency_code = currency_code
	_ledger_keep = maxi(ledger_keep, 1)


## World setup only (new game), before any command runs.
func open_account(owner_id: String, initial_minor: int = 0) -> bool:
	if owner_id.is_empty() or _balances.has(owner_id) or initial_minor < 0:
		return false
	_balances[owner_id] = initial_minor
	return true


func get_currency_code() -> String:
	return _currency_code


func has_account(owner_id: String) -> bool:
	return _balances.has(owner_id)


func get_balance(owner_id: String) -> int:
	return _balances.get(owner_id, 0)


func can_afford(owner_id: String, amount_minor: int) -> bool:
	return has_account(owner_id) and amount_minor >= 0 and get_balance(owner_id) >= amount_minor


## Most recent last. Empty owner_id = all owners.
func get_ledger(owner_id: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in _ledger:
		if owner_id.is_empty() or t["owner_id"] == owner_id:
			out.append(t.duplicate())
	return out


func credit(ctx: CommandContext, owner_id: String, amount_minor: int, reason: String) -> String:
	var err := _check(ctx, owner_id, amount_minor)
	if not err.is_empty():
		return err
	_post(ctx, owner_id, amount_minor, reason)
	return ""


func try_debit(ctx: CommandContext, owner_id: String, amount_minor: int, reason: String) -> String:
	var err := _check(ctx, owner_id, amount_minor)
	if not err.is_empty():
		return err
	if get_balance(owner_id) < amount_minor:
		return "E_INSUFFICIENT_FUNDS"
	_post(ctx, owner_id, -amount_minor, reason)
	return ""


func _check(ctx: CommandContext, owner_id: String, amount_minor: int) -> String:
	if ctx == null or not ctx.can_write():
		return "E_NOT_IN_COMMAND"
	if not has_account(owner_id):
		return "E_UNKNOWN_ACCOUNT"
	if amount_minor <= 0 or amount_minor > MAX_AMOUNT_MINOR:
		return "E_INVALID_AMOUNT"
	return ""


func _post(ctx: CommandContext, owner_id: String, signed_minor: int, reason: String) -> void:
	var balance: int = _balances[owner_id] + signed_minor
	_balances[owner_id] = balance
	var txn_id := "txn_%08d" % _next_transaction_seq
	_next_transaction_seq += 1
	var event_id := ctx.emit("wallet_changed", {"owner_id": owner_id, "balance_minor": balance,
		"delta_minor": signed_minor, "transaction_id": txn_id, "reason": reason, "currency_code": _currency_code})
	_ledger.append({"transaction_id": txn_id, "timestamp_game_minute": ctx.current_minute(),
		"owner_id": owner_id, "amount_minor": signed_minor, "balance_after_minor": balance,
		"currency_code": _currency_code, "reason": reason, "event_id": event_id})
	if _ledger.size() > _ledger_keep:
		_ledger = _ledger.slice(_ledger.size() - _ledger_keep)


func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "currency_code": _currency_code,
		"next_transaction_seq": _next_transaction_seq, "balances": _balances.duplicate(),
		"ledger": _ledger.duplicate(true)}


func from_dict(data: Dictionary) -> String:
	var v := SchemaValidator.new()
	var d: Variant = v.validate(data, STATE_SCHEMA)
	if not v.is_ok():
		return "E_INVALID_ECONOMY_STATE"
	if not _currency_code.is_empty() and d["currency_code"] != _currency_code:
		return "E_CURRENCY_MISMATCH"
	_currency_code = d["currency_code"]
	_next_transaction_seq = d["next_transaction_seq"]
	_balances = d["balances"]
	_ledger.assign(d["ledger"])
	return ""
