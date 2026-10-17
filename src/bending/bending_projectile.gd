class_name BendingProjectile
extends Node3D
## Pooled bending projectile with continuous collision: every tick the sphere
## is shape-cast along its motion (PhysicsDirectSpaceState3D.cast_motion), so
## even 100 m/s bolts never tunnel through thin targets or walls.
##
##   var p := BendingProjectile.launch(ctx, from, dir, 30.0, hit_dict, {
##       "radius": 0.3, "range": 30.0, "visual": node, "pierce": false,
##       "on_impact": func(proj, pos, normal, target): ..., "lead": 0.6})
##
## * Hits damageables of the opposing team via BendingHits.deliver (once per
##   attack_id; pierce keeps flying through targets).
## * Stops on terrain and constructs (WORLD | CONSTRUCT) -> on_impact + world VFX
##   ("world_radius": a smaller core sphere for that test, e.g. wide air gusts).
## * Deflectable: defenders call redirect(dir, team, source) (air / water
##   parries send it back). The HitInfo carries meta &"projectile" = this node.
## * Aim assist: launch() leads a locked/soft target (lead 0..1) and may home
##   slightly (homing deg/s for homing_time s).
## * The visual node is any Node3D placed at the projectile each frame; it is
##   handed back through `on_finish(visual)` (or freed / FxLib.release'd).

signal finished(proj: BendingProjectile)

var ctx: BendingContext
var team: int = Combat.Team.PLAYER
var element: int = ElementDefs.Element.NONE
var source: Node3D = null
var velocity := Vector3.ZERO
var radius := 0.25
## Radius growth per second (expanding gusts).
var radius_growth := 0.0
var max_radius := 4.0
## Radius of the sphere that meets terrain and constructs (SOLID); < 0: `radius`. A wide,
## growing gust hits bodies with its full radius but only stops where its core meets the
## ground or a wall (a 0.75 m kick gust 0.5 m above the floor otherwise died after 0.5 m).
var world_radius := -1.0
var max_distance := 30.0
var traveled := 0.0
var gravity := 0.0
var pierce := false
var hit_template: Dictionary = {}
var attack_id := 0
var ability_id: StringName = &""
var deflectable := true
var homing_target: Node3D = null
var homing_rate := 0.0
var homing_time := 0.0
var visual: Node3D = null
## Orient the visual along the velocity (shards, rocks).
var align_visual := true
var spin_visual := Vector3.ZERO
var on_impact: Callable = Callable()
var on_finish: Callable = Callable()
var on_step: Callable = Callable()
var age := 0.0
var max_age := 5.0
var alive := false
var redirected := false
## World impact VFX size (BendingFeedback.world_impact).
var impact_size := 1.0

var _exclude: Array[RID] = []
var _shape := SphereShape3D.new()
var _params := PhysicsShapeQueryParameters3D.new()

static var _free: Array[BendingProjectile] = []
## Live projectiles (tests, defenses scanning for incoming projectiles).
static var live: Array[BendingProjectile] = []


static func launch(p_ctx: BendingContext, from: Vector3, dir: Vector3, speed: float, h: Dictionary, opts: Dictionary = {}) -> BendingProjectile:
	var p: BendingProjectile = null
	while not _free.is_empty() and p == null:
		# Untyped: pooled projectiles are freed with their scene's FxRoot (scene changes), and
		# assigning a freed instance to a typed variable is a script error.
		var c: Variant = _free.pop_back()
		if is_instance_valid(c):
			p = c as BendingProjectile
	if p == null:
		p = BendingProjectile.new()
		p.name = "Projectile"
	var root := FxLib.root(p_ctx.caster)
	if p.get_parent() != root:
		if p.get_parent():
			p.get_parent().remove_child(p)
		root.add_child(p)
	p._setup(p_ctx, from, dir, speed, h, opts)
	return p


func _setup(p_ctx: BendingContext, from: Vector3, dir: Vector3, speed: float, h: Dictionary, opts: Dictionary) -> void:
	ctx = p_ctx
	team = ctx.team
	element = int(opts.get("element", ctx.element))
	source = ctx.caster
	global_position = from
	var d := dir.normalized() if dir.length_squared() > 1e-6 else ctx.forward()
	velocity = d * speed
	radius = float(opts.get("radius", 0.25))
	radius_growth = float(opts.get("radius_growth", 0.0))
	max_radius = float(opts.get("max_radius", 4.0))
	world_radius = float(opts.get("world_radius", -1.0))
	max_distance = float(opts.get("range", 30.0))
	gravity = float(opts.get("gravity", 0.0))
	pierce = bool(opts.get("pierce", false))
	hit_template = h.duplicate()
	hit_template["projectile"] = true
	if not hit_template.has("deflectable"):
		hit_template["deflectable"] = bool(opts.get("deflectable", true))
	deflectable = bool(hit_template["deflectable"])
	attack_id = int(opts.get("attack_id", HitInfo.new_attack_id()))
	ability_id = opts.get("ability_id", &"")
	homing_target = opts.get("homing_target", ctx.aim_target())
	homing_rate = float(opts.get("homing", 0.0))
	homing_time = float(opts.get("homing_time", 0.35))
	visual = opts.get("visual", null)
	align_visual = bool(opts.get("align", true))
	spin_visual = opts.get("spin", Vector3.ZERO)
	on_impact = opts.get("on_impact", Callable())
	on_finish = opts.get("on_finish", Callable())
	on_step = opts.get("on_step", Callable())
	impact_size = float(opts.get("impact_size", 1.0))
	max_age = float(opts.get("max_age", maxf(1.0, max_distance / maxf(speed, 1.0) + 1.0)))
	traveled = 0.0
	age = 0.0
	redirected = false
	alive = true
	visible = true
	_exclude = ctx.exclude()
	for n: Variant in opts.get("exclude", []):
		if n is CollisionObject3D:
			_exclude.append((n as CollisionObject3D).get_rid())
	set_physics_process(true)
	if not live.has(self):
		live.append(self)
	_place_visual(0.0)
	# Point-blank: anything already overlapping the spawn point is hit now.
	_check_overlap()


func _mask() -> int:
	return (Layers.PLAYER_ATTACK_TARGETS if team == Combat.Team.PLAYER else Layers.ENEMY_ATTACK_TARGETS) | Layers.SOLID


func _physics_process(delta: float) -> void:
	if alive:
		step(delta)


## Advances the projectile by `delta` (public for tests).
func step(delta: float) -> void:
	if not alive:
		return
	# The caster was freed mid-flight (a despawned enemy, a torn-down scene): every hit is
	# built from it, so the projectile ends quietly instead of raising script errors.
	if ctx == null or not is_instance_valid(ctx.caster):
		_finish()
		return
	age += delta
	if age > max_age or traveled > max_distance:
		_expire()
		return
	if homing_rate > 0.0 and age < homing_time and homing_target != null and is_instance_valid(homing_target) and Combat.is_alive(homing_target):
		var want := (BendingContext.target_point(homing_target) - global_position).normalized()
		var cur := velocity.normalized()
		var ang := cur.angle_to(want)
		if ang > 0.001:
			var axis := cur.cross(want)
			if axis.length_squared() > 1e-8:
				velocity = velocity.rotated(axis.normalized(), minf(ang, deg_to_rad(homing_rate) * delta))
	velocity.y -= gravity * delta
	if radius_growth != 0.0:
		radius = clampf(radius + radius_growth * delta, 0.05, max_radius)
	var motion := velocity * delta
	var guard := 0
	while alive and guard < 4:
		guard += 1
		var res := _cast(motion)
		if res.is_empty():
			global_position += motion
			traveled += motion.length()
			break
		var frac: float = res["fraction"]
		var contact: Vector3 = global_position + motion * frac
		var collider: Object = res["collider"]
		var node := collider as Node
		var dmg := Combat.find_damageable(node) if node != null else null
		var is_world := node is CollisionObject3D and ((node as CollisionObject3D).collision_layer & Layers.SOLID) != 0 and dmg == null
		if dmg != null and not (dmg is BendingConstruct):
			var r := _hit_target(dmg, contact)
			if not alive:
				return
			if redirected:
				redirected = false
				motion = velocity * delta * (1.0 - frac)
				global_position = contact
				continue
			# Pierce (or the hit was ignored): keep going, never re-hit this collider.
			if collider is CollisionObject3D:
				_exclude.append((collider as CollisionObject3D).get_rid())
			if not pierce and (r == Combat.Result.HIT or r == Combat.Result.KILLED or r == Combat.Result.BLOCKED):
				_impact(contact, -velocity.normalized(), dmg)
				return
			continue
		if dmg is BendingConstruct:
			_hit_target(dmg, contact)
			if not alive:
				return
			_impact(contact, res.get("normal", -velocity.normalized()), dmg)
			return
		if is_world or node == null:
			_impact(contact, res.get("normal", Vector3.UP), null)
			return
		# Something else (non-solid area): ignore it from now on.
		if collider is CollisionObject3D:
			_exclude.append((collider as CollisionObject3D).get_rid())
	_place_visual(delta)
	if on_step.is_valid():
		on_step.call(self, delta)


func _cast(motion: Vector3) -> Dictionary:
	if world_radius < 0.0 or world_radius >= radius:
		return _cast_sphere(motion, radius, _mask())
	# Bodies with the full radius, terrain / constructs with the core: the nearer contact wins.
	var bodies := _cast_sphere(motion, radius, _mask() & ~Layers.SOLID)
	if not bodies.is_empty() and bodies.get("collider") == null:
		bodies = {}
	var world := _cast_sphere(motion, world_radius, _mask() & Layers.SOLID)
	if bodies.is_empty() or (not world.is_empty() and float(world["fraction"]) < float(bodies["fraction"])):
		return world
	return bodies


func _cast_sphere(motion: Vector3, r: float, mask: int) -> Dictionary:
	var space := get_world_3d().direct_space_state
	_shape.radius = r
	_params.shape = _shape
	_params.transform = Transform3D(Basis.IDENTITY, global_position)
	_params.motion = motion
	_params.collision_mask = mask
	_params.collide_with_areas = true
	_params.collide_with_bodies = true
	_params.exclude = _exclude
	var fr := space.cast_motion(_params)
	if fr.size() < 2 or fr[1] >= 1.0:
		return {}
	var unsafe: float = fr[1]
	# Find what we touch at the unsafe point.
	_params.transform = Transform3D(Basis.IDENTITY, global_position + motion * unsafe)
	_params.motion = Vector3.ZERO
	var hits := space.intersect_shape(_params, 8)
	if hits.is_empty():
		var info := space.get_rest_info(_params)
		if info.is_empty():
			return {"fraction": fr[0], "collider": null, "normal": -motion.normalized()}
		return {"fraction": fr[0], "collider": instance_from_id(int(info["collider_id"])), "normal": info.get("normal", Vector3.UP)}
	# Prefer damageables over terrain at the same contact.
	var best: Dictionary = hits[0]
	for h: Dictionary in hits:
		if h.get("collider") is Node and Combat.find_damageable(h["collider"] as Node) != null:
			best = h
			break
	var nrm := -motion.normalized()
	var rest := space.get_rest_info(_params)
	if not rest.is_empty():
		nrm = rest.get("normal", nrm)
	return {"fraction": fr[0], "collider": best.get("collider"), "normal": nrm}


func _check_overlap() -> void:
	var space := get_world_3d().direct_space_state
	_shape.radius = radius
	_params.shape = _shape
	_params.transform = Transform3D(Basis.IDENTITY, global_position)
	_params.motion = Vector3.ZERO
	_params.collision_mask = _mask() & ~Layers.SOLID
	_params.collide_with_areas = true
	_params.exclude = _exclude
	for h: Dictionary in space.intersect_shape(_params, 8):
		var c: Object = h.get("collider")
		if c is Node:
			var d := Combat.find_damageable(c as Node)
			if d != null and d != source:
				var r := _hit_target(d, global_position)
				if not alive:
					return
				if c is CollisionObject3D:
					_exclude.append((c as CollisionObject3D).get_rid())
				if not pierce and r != Combat.Result.IGNORED and not redirected:
					_impact(global_position, -velocity.normalized(), d)
					return


func _hit_target(target: Node, contact: Vector3) -> int:
	if BendingHits.already_hit(attack_id, target):
		return Combat.Result.IGNORED
	var dir := velocity
	dir.y = 0.0
	var hit := ctx.make_hit(hit_template, dir.normalized() if dir.length_squared() > 1e-4 else ctx.forward(), attack_id, ability_id)
	hit.team = team
	hit.source = source if is_instance_valid(source) else null
	hit.element = element
	hit.position = contact
	hit.origin = contact - velocity.normalized() * 2.0
	hit.set_meta(&"projectile", self)
	var r := BendingHits.deliver(ctx, target, hit)
	return r


func _impact(pos: Vector3, normal: Vector3, target: Node) -> void:
	if not alive:
		return
	global_position = pos
	if target == null:
		BendingFeedback.world_impact(self, element, pos, normal, impact_size)
	if on_impact.is_valid():
		on_impact.call(self, pos, normal, target)
	_finish()


func _expire() -> void:
	if on_impact.is_valid() and bool(hit_template.get("explode_on_expire", false)):
		on_impact.call(self, global_position, Vector3.UP, null)
	_finish()


## Sends the projectile back (parry / deflection). It now belongs to `new_team`.
func redirect(new_dir: Vector3, new_team: int, new_source: Node3D = null, speed_mult: float = 1.15) -> void:
	if not alive:
		return
	var speed := velocity.length() * speed_mult
	velocity = new_dir.normalized() * speed
	team = new_team
	if new_source != null:
		source = new_source
		var nctx := BendingContext.new(new_source, null, element, new_team)
		if new_source.has_method("get_bending_context"):
			nctx = new_source.call("get_bending_context")
		ctx = nctx
	attack_id = HitInfo.new_attack_id()
	_exclude = []
	if new_source is CollisionObject3D:
		_exclude.append((new_source as CollisionObject3D).get_rid())
	traveled = 0.0
	age = 0.0
	homing_target = null
	redirected = true
	hit_template["damage"] = float(hit_template.get("damage", 10.0)) * 1.25


## Destroys it in flight (flame guard burning projectiles away).
func destroy(show_impact: bool = true) -> void:
	if not alive:
		return
	if show_impact:
		BendingFeedback.world_impact(self, element, global_position, Vector3.UP, impact_size * 0.7)
	_finish()


func _place_visual(delta: float) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	visual.global_position = global_position
	if align_visual and velocity.length_squared() > 0.01:
		var f := velocity.normalized()
		var up := Vector3.UP if absf(f.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		var s := visual.scale
		visual.global_basis = Basis.looking_at(f, up).scaled(s)
	if spin_visual != Vector3.ZERO and delta > 0.0:
		visual.rotate_object_local(Vector3.FORWARD, spin_visual.z * delta)
		visual.rotate_object_local(Vector3.RIGHT, spin_visual.x * delta)


func _notification(what: int) -> void:
	# Freed with its scene (FxRoot) while flying or pooled: never leave a dead entry behind.
	if what == NOTIFICATION_PREDELETE:
		live.erase(self)
		_free.erase(self)


func _finish() -> void:
	alive = false
	set_physics_process(false)
	live.erase(self)
	var v := visual
	visual = null
	if on_finish.is_valid():
		on_finish.call(v)
	elif v != null and is_instance_valid(v):
		if v.has_method("finish"):
			v.call("finish")
		elif v.has_meta(&"fx_kind"):
			FxLib.release(v)
		else:
			v.queue_free()
	finished.emit(self)
	ctx = null
	source = null
	homing_target = null
	on_impact = Callable()
	on_finish = Callable()
	on_step = Callable()
	visible = false
	if not _free.has(self):
		_free.append(self)


## Live projectiles of the opposite team within `radius` of `pos` heading toward it.
static func incoming(pos: Vector3, radius: float, defender_team: int) -> Array[BendingProjectile]:
	var out: Array[BendingProjectile] = []
	for p in live:
		if not is_instance_valid(p) or not p.alive or p.team == defender_team:
			continue
		var to := pos - p.global_position
		if to.length() <= radius and p.velocity.dot(to) > 0.0:
			out.append(p)
	return out
