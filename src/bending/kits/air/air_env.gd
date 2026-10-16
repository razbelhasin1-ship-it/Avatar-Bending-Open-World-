class_name AirEnv
extends RefCounted
## Air <-> world (docs/modules/bending_air.md "Environment"). Every Air technique
## calls AirEnv.blow() where its wind reaches the world, and the world answers by
## what is there:
##
## * VEGETATION / CLOTH: a short-lived wind impulse (AirWindField -> shader globals):
##   grass flattens, shrubs and trees bend away and spring back, banners / awnings /
##   tent cloth snap out (vegetation, grass and cloth shaders read air_wind.gdshaderinc).
## * GROUND by surface: dust (dirt / stone / sand / ash in their colours), leaves on
##   grass, snow kicked up (strong blasts scour a hollow in the snow trails), spray
##   rings on water.
## * PHYSICS PROPS: every RigidBody3D in reach is shoved (AirProp pots / crates /
##   baskets / barrels, anything else), and nodes in group &"wind_reactive" get
##   `wind(impulse: Vector3, at: Vector3, by: Node)`.
## * FIRES: the EXTINGUISH hook shared with bending_water / bending_fire: nodes in group
##   &"extinguishable" with `func extinguish(by: Node, at: Vector3) -> bool` (optional
##   `var extinguish_radius`) are blown out (torches, braziers, lanterns, burning grass).
##
##   AirEnv.blow(ctx, center, 4.0, 1.0, {"mode": &"radial"})
##   AirEnv.blow(ctx, head, 2.0, 0.6, {"dir": d, "ground": false})        # a passing gust
##   AirEnv.extinguish(self, p, 2.0)                                      # any module

const EXTINGUISHABLE := &"extinguishable"
const WIND_REACTIVE := &"wind_reactive"

## Counters (tests / stats).
static var extinguished := 0
static var bodies_pushed := 0
static var blows := 0

static var _renderer_ref: WeakRef = null
static var _last_snow_frame := -100


## Wind reaching the world at `center` within `radius` with `power` (0.3 light gust ..
## 1 strong blast .. 2 tornado). opts: mode (&"radial" default, &"directional" with
## dir, &"vortex"), dir (Vector3), ground (true: surface reaction), props (true),
## fires (true), plants (true: shader impulse), hold (impulse hold s), by (Node).
## Returns {"extinguished": n, "pushed": n, "surface": &"..."}.
static func blow(ctx_or_from: Variant, center: Vector3, radius: float, power: float, opts: Dictionary = {}) -> Dictionary:
	var from: Node = _node_of(ctx_or_from)
	var out := {"extinguished": 0, "pushed": 0, "surface": &""}
	if from == null or not from.is_inside_tree():
		return out
	blows += 1
	var dir: Vector3 = opts.get("dir", Vector3.ZERO)
	var mode: StringName = opts.get("mode", &"directional" if dir != Vector3.ZERO else &"radial")
	var by: Node = opts.get("by", from)
	if bool(opts.get("plants", true)):
		var m := AirWindField.RADIAL
		match mode:
			&"directional": m = AirWindField.DIRECTIONAL
			&"vortex": m = AirWindField.VORTEX
		AirWindField.add(from, center, radius * 1.35 + 1.0, 14.0 + 12.0 * power, m, dir, float(opts.get("hold", 0.1)))
	if bool(opts.get("fires", true)):
		out["extinguished"] = extinguish(from, center, radius, by)
	if bool(opts.get("props", true)):
		out["pushed"] = push_bodies(from, center, radius, power, mode, dir, by)
	if bool(opts.get("ground", true)):
		out["surface"] = ground(from, center, radius, power, mode, dir)
	return out


## Blows out fires within `radius` (EXTINGUISH hook). Returns how many went out.
static func extinguish(from: Node, center: Vector3, radius: float, by: Node = null) -> int:
	if from == null or not from.is_inside_tree():
		return 0
	var n := 0
	for node in from.get_tree().get_nodes_in_group(EXTINGUISHABLE):
		if not (node is Node3D) or not is_instance_valid(node) or not node.has_method("extinguish"):
			continue
		var extra := float(node.get("extinguish_radius")) if "extinguish_radius" in node else 0.0
		if (node as Node3D).global_position.distance_to(center) > radius + extra:
			continue
		if bool(node.call("extinguish", by if by != null else from, center)):
			n += 1
	extinguished += n
	return n


## Shoves rigid bodies and wind_reactive nodes. Returns how many were pushed.
static func push_bodies(from: Node, center: Vector3, radius: float, power: float, mode: StringName = &"radial", dir: Vector3 = Vector3.ZERO,
		by: Node = null) -> int:
	if from == null or not from.is_inside_tree() or not (from is Node3D or from.get_viewport() != null):
		return 0
	var n := 0
	var seen := {}
	# Rigid bodies (props on the loose-prop layer, anything else on WORLD).
	var space := (from as Node3D).get_world_3d().direct_space_state if from is Node3D else null
	if space != null:
		var shape := SphereShape3D.new()
		shape.radius = radius
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis.IDENTITY, center)
		q.collision_mask = Layers.PROJECTILE | Layers.WORLD
		for r: Dictionary in space.intersect_shape(q, 32):
			var rb := r.get("collider") as RigidBody3D
			if rb == null or seen.has(rb.get_instance_id()) or rb.freeze:
				continue
			seen[rb.get_instance_id()] = true
			var at := rb.global_position + Vector3.UP * 0.25
			var imp := _impulse(center, at, radius, power, mode, dir)
			if rb.has_method("wind"):
				rb.call("wind", imp / sqrt(maxf(rb.mass, 0.5)), at, by)
			else:
				rb.sleeping = false
				rb.apply_impulse(imp * sqrt(maxf(rb.mass, 0.5)), Vector3.UP * 0.2)
			n += 1
	for node in from.get_tree().get_nodes_in_group(WIND_REACTIVE):
		if not (node is Node3D) or not is_instance_valid(node) or seen.has(node.get_instance_id()) or not node.has_method("wind"):
			continue
		var p := (node as Node3D).global_position
		if p.distance_to(center) > radius:
			continue
		node.call("wind", _impulse(center, p, radius, power, mode, dir), p, by)
		n += 1
	bodies_pushed += n
	return n


static func _impulse(center: Vector3, at: Vector3, radius: float, power: float, mode: StringName, dir: Vector3) -> Vector3:
	var to := at - center
	to.y = 0.0
	var dist := to.length()
	var fall := clampf(1.0 - dist / maxf(radius, 0.1), 0.25, 1.0)
	var radial := to / dist if dist > 0.05 else Vector3(randf() - 0.5, 0.0, randf() - 0.5).normalized()
	var d := radial
	var up := 0.35
	match mode:
		&"directional":
			d = Vector3(dir.x, 0.0, dir.z).normalized() if dir != Vector3.ZERO else radial
			d = (d + radial * 0.25).normalized()
		&"vortex":
			d = (Vector3(-radial.z, 0.0, radial.x) * 0.9 - radial * 0.5).normalized()
			up = 1.1
	return (d + Vector3.UP * up) * 7.5 * power * fall


## Surface reaction under the wind (dust / leaves / snow / spray). Returns the surface.
static func ground(from: Node, center: Vector3, radius: float, power: float, mode: StringName = &"radial", dir: Vector3 = Vector3.ZERO) -> StringName:
	var gy := _ground_y(from, center)
	if center.y - gy > 3.5 + radius * 0.3:
		return &""
	var g := Vector3(center.x, gy, center.z)
	var surf := GroundSampler.surface(g)
	var water := GroundSampler.water_height(g)
	if water > gy + 0.05 and water > center.y - 3.0:
		surf = &"water"
		g.y = water
	var col := FxLib.surface_color(surf)
	var push := (Vector3(dir.x, 0.0, dir.z).normalized() if dir != Vector3.ZERO else Vector3.ZERO) + Vector3.UP
	var strength := clampf(power, 0.3, 2.0)
	match mode:
		&"radial", &"vortex":
			match surf:
				&"snow", &"ice":
					FxBurst.spawn(from, &"snow", g, {"count": 1.2 * strength, "radius": radius * 0.5, "size": 1.0 + power * 0.3})
					_scour_snow(from, g, power, radius)
				&"water":
					FxBurst.spawn(from, &"spray", g, {"count": 1.5 * strength, "radius": radius * 0.4})
					FxRing.spawn(from, g + Vector3.UP * 0.03, radius * 0.8, Color(0.85, 0.94, 1.0), 0.6, {"opacity": 0.55, "width": 0.18, "fill": 0.1})
				_:
					FxBurst.spawn(from, &"dust_ring", g, {"color": col, "radius": radius * 0.4, "count": strength})
					if surf == &"grass":
						FxBurst.spawn(from, &"leaves", g, {"count": 1.2 * strength, "radius": radius * 0.45})
		_:
			AirFx.ground_puff(from, g, surf, clampf(power, 0.3, 1.2), push.normalized())
			if surf == &"snow" and power >= 0.8:
				_scour_snow(from, g, power * 0.6, radius)
	return surf


static func _scour_snow(from: Node, g: Vector3, power: float, radius: float) -> void:
	# Strong blasts blow a hollow into fresh snow (snow trails crater), at most one per frame.
	var f := Engine.get_physics_frames()
	if f - _last_snow_frame < 2 or power < 0.6:
		return
	_last_snow_frame = f
	var r := renderer(from)
	if r == null or r.get("snow") == null:
		return
	var snow: Object = r.get("snow")
	if snow.has_method("add_crater"):
		snow.call("add_crater", g, 5.0 + 7.0 * power * clampf(radius / 3.0, 0.5, 1.6), &"snow")


static func _ground_y(from: Node, p: Vector3) -> float:
	if from is Node3D and (from as Node3D).is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * 8.0, Layers.WORLD | Layers.CONSTRUCT)
		var r := (from as Node3D).get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty():
			return (r["position"] as Vector3).y
	return WorldData.get_height(p.x, p.z)


static func _node_of(v: Variant) -> Node:
	if v is BendingContext:
		var c := v as BendingContext
		return c.caster if c.is_valid() else null
	return v as Node


## The scene's WorldRenderer (snow trails) or null (arenas).
static func renderer(from: Node) -> Node:
	var r: Node = _renderer_ref.get_ref() as Node if _renderer_ref != null else null
	if r != null and is_instance_valid(r) and r.is_inside_tree():
		return r
	_renderer_ref = null
	if from == null or not from.is_inside_tree():
		return null
	# The playable scene the caster lives in (it may not be the current scene: tools, tests).
	var n: Node = from
	while n != null:
		var rr: Variant = n.get("renderer") if "renderer" in n else null
		if rr is WorldRenderer:
			_renderer_ref = weakref(rr)
			return rr
		n = n.get_parent()
	var cs := from.get_tree().current_scene
	if cs == null:
		return null
	var cand: Variant = cs.get("renderer") if "renderer" in cs else null
	if cand is WorldRenderer:
		_renderer_ref = weakref(cand)
		return cand
	for c in cs.get_children():
		if c is WorldRenderer:
			_renderer_ref = weakref(c)
			return c
	return null


## The player performed technique `id` (practice toward the next tier); enemy casts never count.
static func practiced(ctx: BendingContext, id: StringName) -> void:
	if ctx != null and ctx.is_player():
		GameState.add_practice(id)
