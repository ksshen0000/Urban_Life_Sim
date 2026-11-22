class_name SummaryBuilder
extends RefCounted
## Stage summary from real state (spec §5.2 Day 7, §14.5 MemorySummary): for each group of
## `summary_lines` (money, work, people, body...), the first line by `order` whose conditions hold.
## Text is chosen from facts, never invented; the chosen keys are frozen into the dialogue queue
## when the summary event fires, so reloading shows the same summary.


static func build(world: WorldState, content: ContentRegistry, actor_id: String = "player") -> PackedStringArray:
	var groups := {}
	for line in content.get_records("summary_lines"):
		var g: String = line["group"]
		if not groups.has(g):
			groups[g] = []
		(groups[g] as Array).append(line)
	var names := groups.keys()
	names.sort_custom(func(a: String, b: String) -> bool:
		return int(groups[a][0]["group_rank"]) < int(groups[b][0]["group_rank"]) or \
			(int(groups[a][0]["group_rank"]) == int(groups[b][0]["group_rank"]) and a < b))
	var out: PackedStringArray = []
	for g: String in names:
		var lines: Array = groups[g]
		lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
		for line: Dictionary in lines:
			if StoryConditions.all_true(line["conditions"], world, content, actor_id):
				out.append(line["text_key"])
				break
	return out
