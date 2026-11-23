class_name XiangqiRules
extends RefCounted
## Chinese chess rules (pure logic, D-038). Board: 9 files (x 0..8) x 10 ranks (y 0..9); black
## at the top (y 0..4), red at the bottom (y 5..9), red moves first. A piece is "r"/"b" + one of
## K (general) A (advisor) B (elephant) N (horse) R (chariot) C (cannon) P (soldier).
## Legal moves respect palaces, the river, the horse's leg, the elephant's eye, cannon screens,
## not leaving your general in check, and the flying-general rule.

const VALUES := {"K": 10000, "R": 900, "N": 400, "C": 450, "B": 200, "A": 200, "P": 100}
const NAMES := {
	"rK": "帅", "rA": "仕", "rB": "相", "rN": "马", "rR": "车", "rC": "炮", "rP": "兵",
	"bK": "将", "bA": "士", "bB": "象", "bN": "马", "bR": "车", "bC": "炮", "bP": "卒",
}

var cells: Dictionary = {}  # Vector2i -> "rK" ...


static func start_position() -> XiangqiRules:
	var b := XiangqiRules.new()
	var back := ["R", "N", "B", "A", "K", "A", "B", "N", "R"]
	for x in 9:
		b.cells[Vector2i(x, 0)] = "b" + back[x]
		b.cells[Vector2i(x, 9)] = "r" + back[x]
	for x in [1, 7]:
		b.cells[Vector2i(x, 2)] = "bC"
		b.cells[Vector2i(x, 7)] = "rC"
	for x in [0, 2, 4, 6, 8]:
		b.cells[Vector2i(x, 3)] = "bP"
		b.cells[Vector2i(x, 6)] = "rP"
	return b


func copy() -> XiangqiRules:
	var b := XiangqiRules.new()
	b.cells = cells.duplicate()
	return b


static func on_board(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < 9 and p.y >= 0 and p.y < 10


static func in_palace(side: String, p: Vector2i) -> bool:
	return p.x >= 3 and p.x <= 5 and (p.y <= 2 if side == "b" else p.y >= 7)


static func own_half(side: String, p: Vector2i) -> bool:
	return p.y <= 4 if side == "b" else p.y >= 5


func side_of(p: Vector2i) -> String:
	return str(cells.get(p, " "))[0]


## Moves of the piece at `p` ignoring check (pseudo-legal), as target squares.
func piece_moves(p: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not cells.has(p):
		return out
	var side: String = cells[p][0]
	var kind: String = cells[p][1]
	var add := func(t: Vector2i) -> void:
		if on_board(t) and side_of(t) != side:
			out.append(t)
	match kind:
		"K":
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if in_palace(side, p + d):
					add.call(p + d)
		"A":
			for d: Vector2i in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				if in_palace(side, p + d):
					add.call(p + d)
		"B":
			for d: Vector2i in [Vector2i(2, 2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(-2, -2)]:
				var t := p + d
				if on_board(t) and own_half(side, t) and not cells.has(p + d / 2):
					add.call(t)
		"N":
			for leg: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if cells.has(p + leg):
					continue
				var side_dirs: Array = [Vector2i(0, 1), Vector2i(0, -1)] if leg.y == 0 else [Vector2i(1, 0), Vector2i(-1, 0)]
				for sd: Vector2i in side_dirs:
					add.call(p + leg * 2 + sd)
		"R", "C":
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var t := p + d
				var jumped := false
				while on_board(t):
					if not cells.has(t):
						if not jumped:
							out.append(t)
					elif kind == "R":
						if side_of(t) != side:
							out.append(t)
						break
					elif not jumped:
						jumped = true  # the cannon's screen
					else:
						if side_of(t) != side:
							out.append(t)
						break
					t += d
		"P":
			var fwd := Vector2i(0, 1) if side == "b" else Vector2i(0, -1)
			add.call(p + fwd)
			if not own_half(side, p):
				add.call(p + Vector2i.LEFT)
				add.call(p + Vector2i.RIGHT)
	return out


func general_of(side: String) -> Vector2i:
	for p: Vector2i in cells:
		if cells[p] == side + "K":
			return p
	return Vector2i(-1, -1)


func in_check(side: String) -> bool:
	var g := general_of(side)
	if g.x < 0:
		return true
	var enemy := "r" if side == "b" else "b"
	for p: Vector2i in cells:
		if cells[p][0] == enemy and piece_moves(p).has(g):
			return true
	return _generals_face()


func _generals_face() -> bool:
	var r := general_of("r")
	var b := general_of("b")
	if r.x < 0 or b.x < 0 or r.x != b.x:
		return false
	for y in range(b.y + 1, r.y):
		if cells.has(Vector2i(r.x, y)):
			return false
	return true


func apply(from: Vector2i, to: Vector2i) -> String:
	var captured := str(cells.get(to, ""))
	cells[to] = cells[from]
	cells.erase(from)
	return captured


## Legal moves for `side`: [[from, to], ...].
func legal_moves(side: String) -> Array:
	var out: Array = []
	for p: Vector2i in cells.keys():
		if cells[p][0] != side:
			continue
		for t in piece_moves(p):
			var b := copy()
			b.apply(p, t)
			if not b.in_check(side):
				out.append([p, t])
	return out


func is_checkmated(side: String) -> bool:
	return legal_moves(side).is_empty()


## Material balance from `side`'s point of view (+ a bonus for soldiers across the river).
func evaluate(side: String) -> int:
	var score := 0
	for p: Vector2i in cells:
		var piece: String = cells[p]
		var v: int = VALUES[piece[1]]
		if piece[1] == "P" and not own_half(piece[0], p):
			v += 60
		score += v if piece[0] == side else -v
	return score


## The old man's move: alpha-beta, `depth` plies, captures searched first; ties broken by a
## stable order so the same position always gets the same reply.
func best_move(side: String, depth: int = 2) -> Array:
	var moves := _ordered(legal_moves(side))
	var best: Array = []
	var best_score := -INF
	for m: Array in moves:
		var b := copy()
		b.apply(m[0], m[1])
		var s := -b._negamax(_other(side), depth - 1, -INF, INF)
		if s > best_score:
			best_score = s
			best = m
	return best


func _negamax(side: String, depth: int, alpha: float, beta: float) -> float:
	if depth <= 0:
		return evaluate(side)
	var moves := _ordered(legal_moves(side))
	if moves.is_empty():
		return -100000.0  # checkmated / stalemated: lost
	var a := alpha
	for m: Array in moves:
		var b := copy()
		b.apply(m[0], m[1])
		var s := -b._negamax(_other(side), depth - 1, -beta, -a)
		if s >= beta:
			return s
		a = maxf(a, s)
	return a


func _ordered(moves: Array) -> Array:
	var keyed := moves.duplicate()
	keyed.sort_custom(func(m1: Array, m2: Array) -> bool:
		var c1: int = VALUES.get(str(cells.get(m1[1], " ?"))[1], 0) if cells.has(m1[1]) else 0
		var c2: int = VALUES.get(str(cells.get(m2[1], " ?"))[1], 0) if cells.has(m2[1]) else 0
		if c1 != c2:
			return c1 > c2
		return str(m1) < str(m2))
	return keyed


static func _other(side: String) -> String:
	return "b" if side == "r" else "r"
