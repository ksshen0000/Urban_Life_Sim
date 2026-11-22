extends RefCounted
## Named player strategies for the T018 balance runs (see week_bot.gd for the keys).

const CLERK := "job_convenience_clerk"
const SERVER := "job_restaurant_server"
const SORTER := "job_warehouse_sorter"


static func all() -> Array[Dictionary]:
	return [idle(), two_shifts(), reasonable(), hustler(), overspender(), late_starter(), broke_start()]


## Never works: signs the lease, eats when hungry, sleeps.
static func idle() -> Dictionary:
	return {"name": "idle"}


## The stage goal's minimum: two short shifts.
static func two_shifts() -> Dictionary:
	return {"name": "two_shifts", "shifts": {2: [[CLERK, "morning"]], 3: [[CLERK, "morning"]]}}


## One shift a day from day 2: clerk until the warehouse opens on day 4, then warehouse.
static func reasonable() -> Dictionary:
	return {"name": "reasonable", "shifts": {
		2: [[CLERK, "morning"]], 3: [[SERVER, "lunch"]], 4: [[SORTER, "day"]], 5: [[SORTER, "day"]],
		6: [[CLERK, "morning"]], 7: [[SORTER, "day"]]}}


## Two shifts most days.
static func hustler() -> Dictionary:
	return {"name": "hustler", "shifts": {
		2: [[CLERK, "morning"], [SERVER, "dinner"]], 3: [[CLERK, "morning"], [SERVER, "dinner"]],
		4: [[SORTER, "day"], [SERVER, "dinner"]], 5: [[SORTER, "day"], [SERVER, "dinner"]],
		6: [[SORTER, "day"], [SERVER, "dinner"]], 7: [[SORTER, "day"]]}}


## Two shifts, but buys snacks and drinks all day and eats full meals early.
static func overspender() -> Dictionary:
	return {"name": "overspender", "eat_at": 30,
		"extras": [["item_drink", 6], ["item_simple_meal", 1]],
		"shifts": {2: [[CLERK, "morning"]], 3: [[CLERK, "morning"]]}}


## Does nothing until day 5, then works the warehouse every day.
static func late_starter() -> Dictionary:
	return {"name": "late_starter", "extras": [["item_drink", 2]],
		"shifts": {5: [[SORTER, "day"]], 6: [[SORTER, "day"]], 7: [[SORTER, "day"]], 8: [[SORTER, "day"]]}}


## Arrives with just the deposit: zero cash after signing, must work from day 2 to eat.
static func broke_start() -> Dictionary:
	return {"name": "broke_start", "start_money_minor": 60000,
		"shifts": {2: [[CLERK, "morning"], [SERVER, "dinner"]], 3: [[CLERK, "morning"], [SERVER, "dinner"]],
			4: [[SORTER, "day"]], 5: [[SORTER, "day"]], 6: [[SORTER, "day"]], 7: [[SORTER, "day"]]}}
