class_name MinigameRegistry
extends RefCounted
## Minigame plugins by id (D-038). Content (jobs / activities) names a minigame by id; adding a
## game = one script extending Minigame + one line here + the id in content.

const GAMES := {
	"cashier": "res://scripts/minigames/cashier_game.gd",
	"order_up": "res://scripts/minigames/order_up_game.gd",
	"sorting": "res://scripts/minigames/sorting_game.gd",
	"bricks": "res://scripts/minigames/bricks_game.gd",
	"xiangqi": "res://scripts/minigames/xiangqi_game.gd",
	"billiards": "res://scripts/minigames/billiards_game.gd",
	"breakout": "res://scripts/minigames/breakout_game.gd",
	"dance": "res://scripts/minigames/rhythm_game.gd",
	"square_dance": "res://scripts/minigames/rhythm_game.gd",
}


static func has(id: String) -> bool:
	return GAMES.has(id)


static func create(id: String) -> Minigame:
	if not GAMES.has(id):
		return null
	var game: Minigame = (load(GAMES[id]) as GDScript).new()
	game.set_meta("game_id", id)
	return game
