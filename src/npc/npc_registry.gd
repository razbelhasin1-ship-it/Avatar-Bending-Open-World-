class_name NpcRegistry
extends RefCounted
## Named characters (quest givers, trainers, merchants, story NPCs) and their dialogue trees,
## loaded from data/dialogue/*.gd (each a script with `const NPCS := {...}` and
## `const TREES := {...}`), placements resolved against the settlement anchors / POIs, and the
## live NPC nodes currently spawned. Format: docs/modules/quests_npcs.md "Named NPCs".
##
##   NpcRegistry.get_npc(&"wt_siku")            # normalized definition ({} if unknown)
##   NpcRegistry.placement(&"wt_siku")          # Transform3D where the NPC stands (origin INF if unresolved)
##   NpcRegistry.position_of(&"wt_siku")        # live node position, else the placement
##   NpcRegistry.dialogue_tree(&"siku_greeting")
##   NpcRegistry.live_npc(&"wt_siku")           # the spawned NpcCharacter or null

const FILES: Array[String] = [
	"res://data/dialogue/npcs_water.gd",
	"res://data/dialogue/npcs_earth.gd",
	"res://data/dialogue/npcs_fire.gd",
	"res://data/dialogue/npcs_air.gd",
	"res://data/dialogue/npcs_travel.gd",
]

static var _npcs: Dictionary = {}
static var _trees: Dictionary = {}
static var _order: Array[StringName] = []
static var _loaded := false
static var _placements: Dictionary = {}
static var _live: Dictionary = {}


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	for path in FILES:
		if not ResourceLoader.exists(path):
			continue
		var s := load(path) as GDScript
		if s == null:
			push_error("NpcRegistry: cannot load %s" % path)
			continue
		var consts := s.get_script_constant_map()
		var npcs: Dictionary = consts.get("NPCS", {})
		for id: Variant in npcs:
			register_npc(StringName(str(id)), npcs[id])
		var trees: Dictionary = consts.get("TREES", {})
		for tid: Variant in trees:
			register_tree(StringName(str(tid)), trees[tid])


## Adds or replaces a named NPC (data loading, tests).
static func register_npc(id: StringName, src: Dictionary) -> void:
	var d := src.duplicate(true)
	d["id"] = id
	d["name"] = String(d.get("name", String(id).capitalize()))
	d["title"] = String(d.get("title", ""))
	d["nation"] = StringName(str(d.get("nation", "")))
	d["role"] = StringName(str(d.get("role", "quest_giver")))
	d["look"] = d.get("look", {})
	d["place"] = d.get("place", {})
	d["barks"] = d.get("barks", [])
	d["idle"] = StringName(str(d.get("idle", "stand")))
	d["wander"] = float(d.get("wander", 0.0))
	if not d.has("talk"):
		d["talk"] = [{"tree": d.get("tree", "")}] if d.has("tree") else []
	if not _npcs.has(id):
		_order.append(id)
	_npcs[id] = d
	_placements.erase(id)


static func register_tree(id: StringName, tree: Dictionary) -> void:
	_trees[id] = DialogueTree.normalize(id, tree)


static func get_npc(id: StringName) -> Dictionary:
	ensure()
	return _npcs.get(id, {})


static func has_npc(id: StringName) -> bool:
	ensure()
	return _npcs.has(id)


static func ids() -> Array[StringName]:
	ensure()
	return _order.duplicate()


static func dialogue_tree(id: StringName) -> Dictionary:
	ensure()
	return _trees.get(id, {})


static func tree_ids() -> Array:
	ensure()
	return _trees.keys()


static func display_name(id: StringName) -> String:
	var d := get_npc(id)
	return String(d.get("name", String(id).capitalize())) if not d.is_empty() else String(id).capitalize()


## The NPC's nation as an ElementDefs.Element (dialogue colours, markers).
static func element_of(id: StringName) -> int:
	return ElementDefs.from_id(StringName(str(get_npc(id).get("nation", ""))))


## Where the NPC stands: anchor / POI / spawn / pos spec (+ offset) with a facing (`yaw`, `face`
## spec, or the anchor's own yaw). Origin Vector3.INF when the world has no such place.
static func placement(id: StringName) -> Transform3D:
	if _placements.has(id):
		return _placements[id]
	var d := get_npc(id)
	var out := Transform3D(Basis(), Vector3.INF)
	if not d.is_empty():
		out = resolve_place(d.get("place", {}))
	_placements[id] = out
	return out


static func resolve_place(place: Dictionary) -> Transform3D:
	var pos := Vector3.INF
	var yaw := float(place.get("yaw", 0.0))
	if place.has("anchor"):
		var a := QuestTargets.find_anchor(place["anchor"])
		if not a.is_empty():
			pos = a["position"]
			if not place.has("yaw"):
				yaw = float(a.get("yaw", 0.0))
			if place.has("offset"):
				pos += Basis(Vector3.UP, float(a.get("yaw", 0.0))) * (place["offset"] as Vector3)
	elif place.has("spawn") and place.has("local"):
		# in the frame of an element's new-game spawn (-Z = the way the player looks on arrival)
		var sp := WorldData.get_spawn(ElementDefs.from_id(StringName(str(place["spawn"]))))
		pos = sp * (place["local"] as Vector3)
		var to := sp.origin - pos
		if not place.has("yaw") and Vector2(to.x, to.z).length() > 0.01:
			yaw = atan2(-to.x, -to.z)
	else:
		pos = QuestTargets.resolve(place)
	if not pos.is_finite():
		return Transform3D(Basis(), Vector3.INF)
	if place.has("face"):
		var f := QuestTargets.resolve(place["face"])
		if f.is_finite():
			var dv := f - pos
			if Vector2(dv.x, dv.z).length() > 0.01:
				yaw = atan2(-dv.x, -dv.z)
	return Transform3D(Basis(Vector3.UP, yaw), pos)


static func clear_placements() -> void:
	_placements.clear()


# --- live nodes -------------------------------------------------------------------------------

static func register_live(id: StringName, node: Node3D) -> void:
	if id != &"":
		_live[id] = node


static func unregister_live(id: StringName, node: Node3D) -> void:
	if _live.get(id) == node:
		_live.erase(id)


static func live_npc(id: StringName) -> Node3D:
	var n: Variant = _live.get(id)
	if n is Node3D and is_instance_valid(n) and (n as Node3D).is_inside_tree():
		return n
	_live.erase(id)
	return null


static func position_of(id: StringName) -> Vector3:
	var n := live_npc(id)
	if n != null:
		return n.global_position
	return placement(id).origin


## Picks the dialogue tree for a named NPC: the first `talk` entry whose `if` holds.
static func pick_tree(id: StringName) -> StringName:
	for e: Variant in get_npc(id).get("talk", []):
		if e is Dictionary and QuestConditions.check((e as Dictionary).get("if")):
			return StringName(str((e as Dictionary).get("tree", "")))
	return &""


## Problems in the NPC / dialogue data (tests). Empty = valid.
static func validate() -> Array[String]:
	ensure()
	var errs: Array[String] = []
	for id in _order:
		var d: Dictionary = _npcs[id]
		if (d["place"] as Dictionary).is_empty():
			errs.append("npc %s has no place" % id)
		for e: Variant in d["talk"]:
			var tid := StringName(str((e as Dictionary).get("tree", "")))
			if tid != &"" and not _trees.has(tid):
				errs.append("npc %s talks with unknown tree %s" % [id, tid])
		if (d["talk"] as Array).is_empty() and d["role"] != &"escort":
			errs.append("npc %s has no dialogue" % id)
	for tid: Variant in _trees:
		errs.append_array(DialogueTree.validate(_trees[tid]))
	return errs
