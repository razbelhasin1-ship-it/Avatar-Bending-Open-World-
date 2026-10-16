class_name DialogueTree
extends RefCounted
## Data-driven dialogue trees (data/dialogue/*.gd `TREES`), see docs/modules/quests_npcs.md.
##
##   &"siku_greeting": {
##       "start": "hello",                                   # default "start"
##       "nodes": {
##           "hello": {"text": "Breathe in. Feel the tide in you.", "next": "ask"},
##           "ask":   {"text": ["Variant A", "Variant B"],     # a random line each time
##                     "choices": [
##                         {"text": "Teach me.", "next": "teach", "if": {"level": 2}, "do": [["flag", "asked"]]},
##                         {"text": "Farewell.", "end": true}]},
##           "teach": {"lines": ["First line.", "Second line."], "do": [["start_quest", &"wt_first_form"]], "end": true},
##           "route": {"branch": [{"if": {"quest": [&"wt_x", "active"]}, "next": "busy"}, {"next": "hello"}]},
##       }}
##
## Node keys: text (String or Array) | lines (Array, shown one after another), speaker (String,
## default the NPC's name; "" = narrator), do (actions run when the node is shown), next / end,
## choices [{text, next | end, if, do}], branch [{if, next}] (silent routing), emote (rig clip),
## camera (&"close" | &"wide").

const START := "start"


static func normalize(id: StringName, src: Dictionary) -> Dictionary:
	var t := src.duplicate(true)
	t["id"] = id
	t["start"] = String(t.get("start", START))
	var nodes: Dictionary = t.get("nodes", {})
	var out := {}
	for k: Variant in nodes:
		out[String(k)] = nodes[k]
	t["nodes"] = out
	return t


static func get_node_data(tree: Dictionary, key: String) -> Dictionary:
	var nodes: Dictionary = tree.get("nodes", {})
	var n: Variant = nodes.get(key)
	return n if n is Dictionary else {}


## Lines of a node to show in order (one random variant for `text` arrays).
static func lines_of(node: Dictionary, rng: RandomNumberGenerator = null) -> Array[String]:
	var out: Array[String] = []
	if node.has("lines"):
		for l: Variant in node["lines"]:
			out.append(String(l))
	if node.has("text"):
		var t: Variant = node["text"]
		if t is Array and not (t as Array).is_empty():
			var arr: Array = t
			var i := rng.randi_range(0, arr.size() - 1) if rng != null else randi() % arr.size()
			out.append(String(arr[i]))
		elif t is String or t is StringName:
			out.append(String(t))
	return out


## The choices of a node whose `if` holds.
static func visible_choices(node: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Variant in node.get("choices", []):
		if c is Dictionary and QuestConditions.check((c as Dictionary).get("if")):
			out.append(c)
	return out


## Follows `branch` routing: the first entry whose `if` holds gives the next node key.
static func route(node: Dictionary) -> String:
	for b: Variant in node.get("branch", []):
		if b is Dictionary and QuestConditions.check((b as Dictionary).get("if")):
			return String((b as Dictionary).get("next", ""))
	return ""


## Replaces {player}, {element}, {nation}, {bender} in a line.
static func format_line(text: String) -> String:
	var e := GameState.element
	var data := ElementDefs.get_data(e)
	return text.replace("{player}", GameState.player_name) \
		.replace("{element}", String(data.get("element_name", "bending")).to_lower()) \
		.replace("{bender}", String(data.get("name", "bender")).to_lower()) \
		.replace("{nation}", String(data.get("nation", "the world")))


## Problems in one tree (dangling next keys, empty choices, unknown action verbs).
static func validate(tree: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var tid := String(tree.get("id", "?"))
	var nodes: Dictionary = tree.get("nodes", {})
	if not nodes.has(String(tree.get("start", START))):
		errs.append("tree %s: start node '%s' missing" % [tid, tree.get("start", START)])
	for k: Variant in nodes:
		var n: Dictionary = nodes[k]
		var nxt := String(n.get("next", ""))
		if nxt != "" and not nodes.has(nxt):
			errs.append("tree %s/%s: next '%s' missing" % [tid, k, nxt])
		if not n.has("text") and not n.has("lines") and not n.has("branch") and not n.has("choices"):
			errs.append("tree %s/%s: empty node" % [tid, k])
		for c: Variant in n.get("choices", []):
			var cd: Dictionary = c
			if String(cd.get("text", "")).is_empty():
				errs.append("tree %s/%s: choice without text" % [tid, k])
			var cn := String(cd.get("next", ""))
			if cn != "" and not nodes.has(cn):
				errs.append("tree %s/%s: choice next '%s' missing" % [tid, k, cn])
			errs.append_array(_check_actions(cd.get("do", []), "%s/%s" % [tid, k]))
		for b: Variant in n.get("branch", []):
			var bn := String((b as Dictionary).get("next", ""))
			if not nodes.has(bn):
				errs.append("tree %s/%s: branch next '%s' missing" % [tid, k, bn])
		errs.append_array(_check_actions(n.get("do", []), "%s/%s" % [tid, k]))
	return errs


const VERBS: Array[StringName] = [&"start_quest", &"complete_objective", &"give_item", &"take_item", &"currency",
	&"xp", &"flag", &"unlock", &"heal", &"notify", &"track", &"skill_point", &"shop", &"train", &"travel", &"challenge"]


static func _check_actions(actions: Variant, where: String) -> Array[String]:
	var errs: Array[String] = []
	for a: Variant in actions:
		if not (a is Array) or (a as Array).is_empty():
			errs.append("%s: malformed action %s" % [where, a])
			continue
		var verb := StringName(str((a as Array)[0]))
		if not VERBS.has(verb):
			errs.append("%s: unknown action %s" % [where, verb])
		if verb == &"start_quest" and not Quests.has_quest(StringName(str((a as Array)[1]))):
			errs.append("%s: start_quest of unknown quest %s" % [where, (a as Array)[1]])
	return errs
