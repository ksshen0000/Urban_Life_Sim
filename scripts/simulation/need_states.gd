class_name NeedStates
extends RefCounted
## What hunger, energy and stress do to you (D-037), from the `states` of each need record:
## slower walking, lower work efficiency (pay x efficiency, judged when a shift starts) and, for
## exhaustion / breaking point, no starting a shift at all. Pure functions of content + values.
## Hunger never blocks work: someone broke and hungry must always be able to earn (no dead ends).


## Active states for `values` ({need_id: int}): [{need_id, id, name_key, walk, work, blocks}].
static func active(content: ContentRegistry, values: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for need in content.get_records("needs"):
		if not values.has(need["id"]):
			continue
		var v: int = values[need["id"]]
		for st: Dictionary in need.get("states", []):
			var hit: bool = v >= int(st["value"]) if st["op"] == "at_least" else v <= int(st["value"])
			if hit:
				out.append({"need_id": need["id"], "id": st["id"], "name_key": st["name_key"],
					"walk": int(st.get("walk_speed_pct", 100)), "work": int(st.get("work_efficiency_pct", 100)),
					"blocks": str(st.get("blocks_work", ""))})
	return out


## Product of walking-speed factors (1.0 = normal).
static func walk_factor(states: Array[Dictionary]) -> float:
	var f := 1.0
	for st in states:
		f *= st["walk"] / 100.0
	return f


## Work efficiency in basis points (10000 = 100 %), product of all active states.
static func work_efficiency_bp(states: Array[Dictionary]) -> int:
	var bp := 10000
	for st in states:
		bp = bp * int(st["work"]) / 100
	return bp


## The refusal code of the first state that blocks work, or "".
static func work_block(states: Array[Dictionary]) -> String:
	for st in states:
		if not str(st["blocks"]).is_empty():
			return st["blocks"]
	return ""
