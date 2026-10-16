class_name FireStatus
extends RefCounted
## BURNING (docs/modules/bending_fire.md "Burn"): fire hits whose hit data carries
## `status.burn >= MIN_BURN` seconds set their target alight - flames lick the body
## and it takes small damage ticks (fire's pressure: a firebender's hits keep
## hurting). Lighter fire hits (jabs) only scorch-tint the target.
##
## * Ticks: every TICK s (player: PLAYER_TICK), DAMAGE x level-free, reaction NONE,
##   no poise, unblockable, element FIRE, credited to whoever set the fire (XP / kills).
##   They are delivered with receive_hit (not Combat.deal: no hit sounds / no quest or
##   tutorial "hit" counters), with the same accounting as BendingHits: an applied tick
##   counts in BendingHits.applied_hits and shows a (small) hit flare (ImpactFx.hits_shown).
## * Duration: max(remaining, new), capped at MAX_BURN; firebenders burn half as long.
## * Put out by: any water hit or a soak, standing in water, a dodge roll (stop, drop and
##   roll), death. Flames visuals are capped (CAP per tier); burning continues without
##   flames beyond the cap.
##
##   FireStatus.ensure()                         # starts listening (first fire ability)
##   FireStatus.ignite(target, 3.0, source)      # set alight directly (grass fire, hazards)
##   FireStatus.is_burning(target); FireStatus.time_left(target); FireStatus.douse(target)

const MIN_BURN := 2.0
const MAX_BURN := 5.0
const TICK := 0.6
const PLAYER_TICK := 1.0
const DAMAGE := 2.0
const CAPS: Array[int] = [3, 5, 8, 10]

static var _mgr: WeakRef = null
## Ticks applied (tests).
static var ticks_applied := 0


static func ensure() -> Manager:
	var m: Manager = _mgr.get_ref() as Manager if _mgr != null else null
	if m != null and is_instance_valid(m) and not m.is_queued_for_deletion():
		return m
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	m = Manager.new()
	m.name = "FireStatus"
	# Listening starts now (hits this frame count); the node joins the tree deferred
	# (ensure() may run while the tree is busy) and ticks from then on.
	Events.hit_landed.connect(m._on_hit)
	tree.root.add_child.call_deferred(m)
	_mgr = weakref(m)
	return m


## The burn manager (null until the first fire ability ran / ensure()).
static func manager() -> Manager:
	return _manager()


static func _manager() -> Manager:
	var m: Manager = _mgr.get_ref() as Manager if _mgr != null else null
	return m if m != null and is_instance_valid(m) else null


## Sets `target` alight for `seconds` (refreshes; never shortens). `source` gets the credit.
static func ignite(target: Node, seconds: float, source: Node = null, team: int = Combat.Team.NEUTRAL) -> bool:
	var m := ensure()
	if m == null or target == null or not is_instance_valid(target) or not (target is Node3D):
		return false
	if not Combat.is_alive(target) or target is BendingConstruct or target.has_meta(&"no_burn"):
		return false
	return m.add(target as Node3D, seconds, source, team)


static func is_burning(target: Node) -> bool:
	var m := _manager()
	return m != null and target != null and m.entries.has(target.get_instance_id())


static func time_left(target: Node) -> float:
	var m := _manager()
	if m == null or target == null or not m.entries.has(target.get_instance_id()):
		return 0.0
	return maxf(0.0, float((m.entries[target.get_instance_id()] as Dictionary)["until"]) - m.clock)


## Puts the flames out (water, rolling, death). Returns true if it was burning.
static func douse(target: Node, steam: bool = true) -> bool:
	var m := _manager()
	if m == null or target == null:
		return false
	return m.remove(target.get_instance_id(), steam)


static func burning_count() -> int:
	var m := _manager()
	return m.entries.size() if m != null else 0


## Listens to hits (sets targets alight / water puts them out) and ticks the burns.
class Manager extends Node:
	## instance id -> {target: WeakRef, until, next, source: WeakRef, team, fx: BodyFlames}
	var entries: Dictionary = {}
	var clock := 0.0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_PAUSABLE
		if not Events.hit_landed.is_connected(_on_hit):
			Events.hit_landed.connect(_on_hit)

	func _exit_tree() -> void:
		for id: int in entries.keys():
			remove(id, false)
		if Events.hit_landed.is_connected(_on_hit):
			Events.hit_landed.disconnect(_on_hit)

	func _on_hit(hit: HitInfo, target: Node, result: int) -> void:
		if target == null or not is_instance_valid(target):
			return
		if result != Combat.Result.HIT and result != Combat.Result.KILLED:
			return
		if hit.element == ElementDefs.Element.WATER or hit.status.has("soaked"):
			remove(target.get_instance_id(), true)
			return
		var burn := float(hit.status.get("burn", 0.0))
		if burn >= FireStatus.MIN_BURN and result == Combat.Result.HIT:
			add(target as Node3D, burn, hit.source, hit.team)

	func add(target: Node3D, seconds: float, source: Node, team: int) -> bool:
		if target == null:
			return false
		var secs := seconds
		if "element" in target and int(target.get("element")) == ElementDefs.Element.FIRE:
			secs *= 0.5
		secs = minf(secs, FireStatus.MAX_BURN)
		var id := target.get_instance_id()
		var tick := FireStatus.PLAYER_TICK if target.is_in_group(&"player") else FireStatus.TICK
		if entries.has(id):
			var e: Dictionary = entries[id]
			e["until"] = maxf(float(e["until"]), clock + secs)
			if source != null and is_instance_valid(source):
				e["source"] = weakref(source)
				e["team"] = team
			return true
		var fx: BodyFlames = null
		if entries.size() < FireStatus.CAPS[FxLib.tier()]:
			fx = BodyFlames.spawn(target)
		entries[id] = {"target": weakref(target), "until": clock + secs, "next": clock + tick * 0.5,
			"source": weakref(source) if source != null and is_instance_valid(source) else null, "team": team, "fx": fx, "tick": tick}
		return true

	func remove(id: int, steam: bool) -> bool:
		if not entries.has(id):
			return false
		var e: Dictionary = entries[id]
		entries.erase(id)
		var fx: BodyFlames = e.get("fx")
		if fx != null and is_instance_valid(fx):
			fx.stop()
		var t := (e["target"] as WeakRef).get_ref() as Node3D
		if steam and t != null and is_instance_valid(t) and t.is_inside_tree():
			FxBurst.spawn(t, &"steam", t.global_position + Vector3.UP * 1.1, {"count": 0.6, "size": 0.7})
			Audio.play_bending(ElementDefs.Element.FIRE, &"extinguish", t.global_position, -8.0)
		return true

	func _physics_process(delta: float) -> void:
		clock += delta
		if entries.is_empty():
			return
		for id: int in entries.keys():
			if not entries.has(id):
				continue
			var e: Dictionary = entries[id]
			var t := (e["target"] as WeakRef).get_ref() as Node3D
			if t == null or not is_instance_valid(t) or not t.is_inside_tree() or not Combat.is_alive(t):
				remove(id, false)
				continue
			if clock >= float(e["until"]) or _put_out(t):
				remove(id, clock < float(e["until"]))
				continue
			if clock >= float(e["next"]):
				e["next"] = clock + float(e["tick"])
				_tick(t, e)

	## Water underfoot or a dodge roll puts the fire out.
	func _put_out(t: Node3D) -> bool:
		var w := GroundSampler.water_height(t.global_position)
		if w > -INF and w > t.global_position.y + 0.3:
			return true
		var c: Variant = t.get("controller") if "controller" in t else null
		if c is BendingController and (c as BendingController).current is DodgeAbility:
			return true
		return false

	func _tick(t: Node3D, e: Dictionary) -> void:
		var src_ref: Variant = e.get("source")
		var src: Node = (src_ref as WeakRef).get_ref() as Node if src_ref is WeakRef else null
		var hit := HitInfo.make(FireStatus.DAMAGE, src if src != null and is_instance_valid(src) else null, ElementDefs.Element.FIRE,
				HitInfo.Reaction.NONE, Vector3.FORWARD, 0.0)
		hit.team = int(e.get("team", Combat.Team.NEUTRAL))
		hit.poise_damage = 0.0
		hit.unblockable = true
		hit.ability_id = &"burn"
		hit.position = BendingContext.target_point(t)
		hit.origin = hit.position
		hit.set_meta(&"no_focus", true)
		hit.set_meta(&"dot", true)
		if not Combat.can_hit(t, hit) or not t.has_method("receive_hit"):
			return
		var r: int = t.call("receive_hit", hit)
		if r == Combat.Result.HIT or r == Combat.Result.KILLED:
			# Same accounting as BendingHits.deliver: applied damage <=> a visible hit.
			BendingHits.applied_hits += 1
			ImpactFx.hits_shown += 1
			FireStatus.ticks_applied += 1
			FxBurst.spawn(t, &"flame", hit.position, {"size": 0.45, "count": 0.35, "speed": 0.6})
			Audio.play_bending(ElementDefs.Element.FIRE, &"ignite", hit.position, -12.0)
