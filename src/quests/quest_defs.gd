class_name QuestDefs
extends RefCounted
## Loads and normalizes quest definitions from the data files (data/quests/*.gd, each a script
## with `const QUESTS := [...]`) and validates them (tests). Format: docs/modules/quests_npcs.md.
##
##   {"id": &"wt_born_of_the_tide", "title": "Born of the Tide", "kind": &"main", "nation": &"water",
##    "giver": &"wt_anaaya", "summary": "...", "description": "...",
##    "requires": {cond}, "auto_start": {cond},
##    "stages": [{"id": &"arrive", "text": "journal line", "objectives": [{...}], "on_complete": [actions]}],
##    "on_start": [actions], "rewards": {"xp": 120, "currency": 25, "items": {&"arctic_moss": 2},
##    "techniques": [&"water_surge", &"ice_wall"], "skill_points": 0}, "next": &"wt_first_form"}

const FILES: Array[String] = [
	"res://data/quests/quests_water.gd",
	"res://data/quests/quests_earth.gd",
	"res://data/quests/quests_fire.gd",
	"res://data/quests/quests_air.gd",
	"res://data/quests/quests_travel.gd",
]

const KINDS: Array[StringName] = [&"main", &"side", &"travel", &"training"]
const OBJECTIVE_TYPES: Array[StringName] = [&"go_to", &"talk_to", &"defeat", &"collect", &"use_ability",
	&"discover", &"interact", &"escort", &"challenge"]


## Every quest of the data files, normalized, in file order.
static func load_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path in FILES:
		if not ResourceLoader.exists(path):
			continue
		var s := load(path) as GDScript
		if s == null:
			push_error("QuestDefs: cannot load %s" % path)
			continue
		var list: Variant = s.get_script_constant_map().get("QUESTS", [])
		for q: Variant in list:
			if q is Dictionary:
				out.append(normalize(q))
	return out


static func normalize(src: Dictionary) -> Dictionary:
	var q := src.duplicate(true)
	q["id"] = StringName(str(q.get("id", "")))
	q["title"] = String(q.get("title", String(q["id"]).capitalize()))
	q["kind"] = StringName(str(q.get("kind", "side")))
	q["nation"] = StringName(str(q.get("nation", "")))
	q["giver"] = StringName(str(q.get("giver", "")))
	q["summary"] = String(q.get("summary", ""))
	q["description"] = String(q.get("description", q["summary"]))
	q["location"] = String(q.get("location", ""))
	q["next"] = StringName(str(q.get("next", "")))
	q["rewards"] = q.get("rewards", {})
	q["on_start"] = q.get("on_start", [])
	var stages: Array = []
	var si := 0
	for st: Variant in q.get("stages", []):
		var sd: Dictionary = (st as Dictionary).duplicate(true)
		sd["id"] = StringName(str(sd.get("id", "stage_%d" % si)))
		sd["text"] = String(sd.get("text", ""))
		sd["on_complete"] = sd.get("on_complete", [])
		var objs: Array = []
		var oi := 0
		for o: Variant in sd.get("objectives", []):
			objs.append(normalize_objective(o, oi))
			oi += 1
		sd["objectives"] = objs
		stages.append(sd)
		si += 1
	q["stages"] = stages
	return q


static func normalize_objective(src: Variant, index: int) -> Dictionary:
	var o: Dictionary = (src as Dictionary).duplicate(true) if src is Dictionary else {}
	o["type"] = StringName(str(o.get("type", "go_to")))
	o["id"] = StringName(str(o.get("id", "%s_%d" % [o["type"], index])))
	o["text"] = String(o.get("text", ""))
	o["optional"] = bool(o.get("optional", false))
	var count := int(o.get("count", 1))
	o["count"] = maxi(1, count)
	match o["type"]:
		&"go_to":
			o["radius"] = float(o.get("radius", 10.0))
		&"talk_to", &"escort":
			o["npc"] = StringName(str(o.get("npc", "")))
			if o["type"] == &"escort":
				o["radius"] = float(o.get("radius", 8.0))
		&"collect", &"interact":
			o["item"] = StringName(str(o.get("item", "")))
			o["key"] = StringName(str(o.get("key", o.get("item", ""))))
		&"defeat":
			o["site"] = StringName(str(o.get("site", "")))
			o["archetype"] = StringName(str(o.get("archetype", "")))
			o["faction"] = StringName(str(o.get("faction", "")))
		&"use_ability":
			o["ability"] = StringName(str(o.get("ability", "")))
			o["slot"] = StringName(str(o.get("slot", "any")))
			o["mode"] = StringName(str(o.get("mode", "use")))
			o["on"] = StringName(str(o.get("on", "any")))
		&"discover":
			o["poi"] = StringName(str(o.get("poi", "")))
		&"challenge":
			o["challenge"] = o.get("challenge", {})
	return o


## Problems with a quest table (unknown ids, broken chains...). Empty = valid. `npc_ids` and
## `item_ids` are the known NPC / item ids (skipped when empty).
static func validate(quests: Array[Dictionary], npc_ids: Array = [], item_ids: Array = []) -> Array[String]:
	var errs: Array[String] = []
	var ids := {}
	for q in quests:
		if q["id"] == &"":
			errs.append("quest without id")
		if ids.has(q["id"]):
			errs.append("duplicate quest id %s" % q["id"])
		ids[q["id"]] = true
	for q in quests:
		var qid := String(q["id"])
		if not KINDS.has(q["kind"]):
			errs.append("%s: unknown kind %s" % [qid, q["kind"]])
		if (q["stages"] as Array).is_empty():
			errs.append("%s: no stages" % qid)
		if q["next"] != &"" and not ids.has(q["next"]):
			errs.append("%s: next quest %s does not exist" % [qid, q["next"]])
		if q["giver"] != &"" and not npc_ids.is_empty() and not npc_ids.has(q["giver"]):
			errs.append("%s: giver %s is not a known NPC" % [qid, q["giver"]])
		var obj_ids := {}
		for st: Dictionary in q["stages"]:
			if (st["objectives"] as Array).is_empty():
				errs.append("%s/%s: stage without objectives" % [qid, st["id"]])
			for o: Dictionary in st["objectives"]:
				if obj_ids.has(o["id"]):
					errs.append("%s: duplicate objective id %s" % [qid, o["id"]])
				obj_ids[o["id"]] = true
				if not OBJECTIVE_TYPES.has(o["type"]):
					errs.append("%s/%s: unknown objective type %s" % [qid, o["id"], o["type"]])
				if String(o["text"]).is_empty():
					errs.append("%s/%s: objective without text" % [qid, o["id"]])
				if (o["type"] == &"talk_to" or o["type"] == &"escort") and not npc_ids.is_empty() and not npc_ids.has(o["npc"]):
					errs.append("%s/%s: unknown npc %s" % [qid, o["id"], o["npc"]])
				if o["type"] == &"collect" and not item_ids.is_empty() and not item_ids.has(o["item"]):
					errs.append("%s/%s: unknown item %s" % [qid, o["id"], o["item"]])
				if o["type"] == &"go_to" and not o.has("target"):
					errs.append("%s/%s: go_to without target" % [qid, o["id"]])
				if o["type"] == &"escort" and not o.has("to"):
					errs.append("%s/%s: escort without destination" % [qid, o["id"]])
				if o["type"] == &"discover" and o["poi"] == &"":
					errs.append("%s/%s: discover without poi" % [qid, o["id"]])
		var r: Dictionary = q["rewards"]
		if not item_ids.is_empty():
			for it: Variant in (r.get("items", {}) as Dictionary):
				if not item_ids.has(StringName(str(it))):
					errs.append("%s: reward item %s unknown" % [qid, it])
	return errs
