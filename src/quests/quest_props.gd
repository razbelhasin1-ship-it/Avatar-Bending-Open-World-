class_name QuestProps
extends Node3D
## Physical quest props: the things a `collect` / `interact` objective points at (moss to
## gather, nets to untangle, an offering bowl, a letter on a crate). Declared on the objective:
##
##   {"id": &"moss", "type": &"collect", "item": &"arctic_moss", "count": 3, "text": "Gather healing moss",
##    "props": [{"at": {"poi": &"wt_ice_flats", "offset": Vector3(12, 0, -4), "ground": true},
##               "kind": &"herb", "prompt": "Gather the moss"}, ...]}
##
## Props of the active objectives are spawned within `spawn_range` of the player (2 Hz check),
## each an Interactable with a small toon mesh and a pulsing glint; interacting gives the item
## (collect) or reports `Quests.report(&"interact", key)` (interact). Taken props are remembered
## in GameState.quests[q]["taken"][objective] so they stay gone after a reload.

const SPAWN_RANGE := 140.0
const DESPAWN_RANGE := 170.0

var player: Node3D = null
var _live: Dictionary = {}       # "q|o|i" -> Node3D
var _t := 0.0


static func is_taken(q: StringName, o: StringName, i: int) -> bool:
	var r: Variant = GameState.quests.get(String(q))
	if not (r is Dictionary):
		return false
	var taken: Dictionary = (r as Dictionary).get("taken", {})
	return (taken.get(String(o), []) as Array).has(i)


static func mark_taken(q: StringName, o: StringName, i: int) -> void:
	var r: Variant = GameState.quests.get(String(q))
	if not (r is Dictionary):
		return
	var rd: Dictionary = r
	var taken: Dictionary = rd.get("taken", {})
	var list: Array = taken.get(String(o), [])
	if not list.has(i):
		list.append(i)
	taken[String(o)] = list
	rd["taken"] = taken
	GameState.quests[String(q)] = rd


func _ready() -> void:
	name = "QuestProps"
	Quests.quest_changed.connect(func(_q: StringName) -> void: _t = 0.0)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	refresh()


## Spawns / frees props for the active objectives around the player.
func refresh() -> void:
	var pl := player if player != null and is_instance_valid(player) else Quests.get_player()
	var wanted := {}
	for e in Quests.active_objectives():
		var q: StringName = e["quest"]
		var od: Dictionary = e["objective"]
		var props: Array = od.get("props", [])
		for i in props.size():
			if is_taken(q, od["id"], i):
				continue
			var spec: Dictionary = props[i]
			var at := QuestTargets.resolve(spec.get("at"))
			if not at.is_finite():
				continue
			var key := "%s|%s|%d" % [q, od["id"], i]
			var d := pl.global_position.distance_to(at) if pl != null else 0.0
			if _live.has(key):
				if d < DESPAWN_RANGE:
					wanted[key] = true
			elif d < SPAWN_RANGE:
				_spawn(key, q, od, i, spec, at)
				wanted[key] = true
	for key: String in _live.keys():
		if not wanted.has(key):
			var n: Node3D = _live[key]
			if is_instance_valid(n):
				n.queue_free()
			_live.erase(key)


func _spawn(key: String, q: StringName, od: Dictionary, i: int, spec: Dictionary, at: Vector3) -> void:
	var it := QuestPropNode.new()
	it.quest_id = q
	it.objective = od
	it.index = i
	it.kind = StringName(str(spec.get("kind", "bundle")))
	it.prompt = String(spec.get("prompt", "Inspect"))
	add_child(it)
	it.global_position = _ground(at)
	it.rotation.y = float(spec.get("yaw", float(i) * 1.7))
	_live[key] = it
	it.taken.connect(func() -> void:
		_live.erase(key))


func _ground(p: Vector3) -> Vector3:
	if not is_inside_tree():
		return p
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 6.0, Layers.WORLD | Layers.CONSTRUCT)
	var r := space.intersect_ray(q)
	if not r.is_empty():
		return r["position"]
	return p


## Live prop nodes (tests / playtests).
func live_props() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for k: String in _live:
		if is_instance_valid(_live[k]):
			out.append(_live[k])
	return out


class QuestPropNode extends Interactable:
	## One quest prop: mesh + glint + interaction. Emits `taken` once used up.
	signal taken

	var quest_id: StringName
	var objective: Dictionary = {}
	var index := 0
	var kind: StringName = &"bundle"
	var _used := false

	func _ready() -> void:
		radius = 2.2
		interact_priority = 2
		animation = &"interact_r"
		lock_time = 0.5
		focus_offset = Vector3(0, 0.4, 0)
		add_to_group(&"quest_prop")
		var tint := Color(-1, 0, 0)
		if objective.get("item", &"") != &"":
			tint = TradeGoods.color(objective["item"])
		add_child(QuestPropMeshes.build(kind, tint))
		var g := QuestPropMeshes.glint(Color(1.0, 0.86, 0.5), 0.8)
		g.position = Vector3(0, 0.75, 0)
		add_child(g)
		super._ready()

	func get_interaction_text(_player: Node3D) -> String:
		return prompt

	func can_interact(p: Node3D) -> bool:
		return not _used and super.can_interact(p) and Quests.is_objective_active(quest_id, objective["id"])

	func interact(p: Node3D) -> void:
		if _used:
			return
		_used = true
		super.interact(p)
		QuestProps.mark_taken(quest_id, objective["id"], index)
		Audio.play_sfx(&"pickup", global_position, -4.0)
		FxBurst.spawn(self, &"sparkle", global_position + Vector3.UP * 0.4, {"count": 0.7, "color": Color(1.0, 0.86, 0.5)})
		if objective["type"] == &"collect":
			var n := int(objective.get("give", 1))
			GameState.add_item(objective["item"], n)
			Events.notify.emit("+%d %s" % [n, TradeGoods.display_name(objective["item"])], &"info")
		else:
			Quests.report(&"interact", objective["key"], 1, {"quest": quest_id})
		taken.emit()
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3.ONE * 0.05, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
		tw.tween_callback(queue_free)
