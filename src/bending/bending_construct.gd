class_name BendingConstruct
extends AnimatableBody3D
## Earth / ice walls and pillars that rise out of the ground: solid collision on
## Layers.CONSTRUCT (blocks movement, projectiles and line of sight), HP, a
## lifetime, and a crumble (earth) or shatter (ice) when broken or expired.
## Damageable (group &"damageable"): attacks of the other team wear it down.
##
##   var w := BendingConstruct.raise(ctx, ground_pos, facing_dir, {
##       "kind": &"earth", "size": Vector3(6, 3, 1), "hp": 160, "lifetime": 12.0,
##       "rise_time": 0.32, "launch": {"lift": 7.0, "damage": 8}})
##
## Anything standing where it erupts is launched (one hit per construct).

signal broken(construct: BendingConstruct)

var team: int = Combat.Team.PLAYER
var kind: StringName = &"earth"
var size := Vector3(6, 3, 1)
var max_hp := 160.0
var hp := 160.0
var lifetime := 12.0
var rise_time := 0.32
var element: int = ElementDefs.Element.EARTH
var ground_y := 0.0
var mesh_i: MeshInstance3D
var shape: CollisionShape3D
var _t := 0.0
var _state := 0  # 0 rising, 1 standing, 2 crumbling
var _crumble_t := 0.0
var _launch: Dictionary = {}
var _ctx: BendingContext = null
var _attack_id := 0
var _top := Transform3D.IDENTITY
var _flash := 0.0
var _mat_flash: ShaderMaterial = null
## Optional: the construct follows this node (Earth Shield slab) at `follow_offset`
## (x right, z forward of the node, ground level) and never expires on its own.
var follow: Node3D = null
var follow_offset := Vector3(0, 0, 0.9)
## Optional (hit: HitInfo) -> int: returns a Combat.Result to resolve a hit
## without damaging the construct (Earth Shield parries), or -1 to take it.
var hit_filter: Callable = Callable()

## Live constructs (tests / AI queries).
static var live: Array[BendingConstruct] = []


static func raise(ctx: BendingContext, ground_pos: Vector3, facing: Vector3, opts: Dictionary = {}) -> BendingConstruct:
	var c := BendingConstruct.new()
	c.name = "Construct"
	c._ctx = ctx
	c.team = ctx.team
	c.kind = opts.get("kind", &"earth")
	c.element = ElementDefs.Element.WATER if c.kind == &"ice" else ElementDefs.Element.EARTH
	c.size = opts.get("size", Vector3(6, 3, 1))
	c.max_hp = float(opts.get("hp", 160.0))
	c.hp = c.max_hp
	c.lifetime = float(opts.get("lifetime", 12.0))
	c.rise_time = float(opts.get("rise_time", 0.32))
	c._launch = opts.get("launch", {})
	c._attack_id = HitInfo.new_attack_id()
	c.follow = opts.get("follow", null)
	c.follow_offset = opts.get("follow_offset", Vector3(0, 0, 0.9))
	if c.follow != null:
		c.lifetime = INF
	var f := Vector3(facing.x, 0.0, facing.z)
	f = f.normalized() if f.length_squared() > 1e-4 else Vector3.FORWARD
	c.ground_y = ground_pos.y
	# Local -Z faces `facing` (the wall's broad side faces the caster's aim).
	c._top = Transform3D(Basis.looking_at(f, Vector3.UP), ground_pos)
	var root := FxLib.root(ctx.caster)
	root.add_child(c)
	c._build()
	return c


func _build() -> void:
	collision_layer = Layers.CONSTRUCT
	collision_mask = 0
	sync_to_physics = false
	add_to_group(&"damageable")
	add_to_group(&"construct")
	set_meta(&"no_lock", true)
	mesh_i = MeshInstance3D.new()
	if kind == &"ice":
		mesh_i.mesh = FxMeshes.ice_block(size, randi() % 3)
		mesh_i.material_override = FxDebris.ice_material()
	else:
		mesh_i.mesh = FxMeshes.slab(size, randi() % 4)
		_mat_flash = ToonMaterials.make(Color(0.6, 0.5, 0.39), {"vertex_color": true, "unique": true, "outline_width": 1.3,
				"outline_color": Color(0.09, 0.07, 0.05), "rim": 0.2})
		mesh_i.material_override = _mat_flash
	mesh_i.position = Vector3(0, -0.15, 0)
	add_child(mesh_i)
	shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0, size.y * 0.5, 0)
	add_child(shape)
	global_transform = _top.translated(Vector3.DOWN * (size.y + 0.3))
	if _ctx != null and _ctx.caster is PhysicsBody3D:
		add_collision_exception_with(_ctx.caster as PhysicsBody3D)
	live.append(self)
	# Eruption feedback.
	var surface := GroundSampler.surface(_top.origin)
	if kind == &"ice":
		IceFx.shatter(self, _top.origin + Vector3.UP * 0.3, Vector3.UP, 0.8, ground_y)
		BendingFeedback.sound(ElementDefs.Element.WATER, &"wall", _top.origin)
	else:
		var right := _top.basis.x
		for i in 3:
			var p := _top.origin + right * (float(i) - 1.0) * size.x * 0.38
			EarthFx.tear_out(self, p, 0.6, surface)
		EarthFx.quake(self, _top.origin, size.x * 0.55, surface)
		BendingFeedback.sound(ElementDefs.Element.EARTH, &"wall", _top.origin)
	if _ctx != null and _ctx.is_player():
		BendingFeedback.shake(0.35, 0.3)


func is_alive() -> bool:
	return _state < 2


func get_display_name() -> String:
	return "Ice Wall" if kind == &"ice" else "Earth Wall"


func receive_hit(hit: HitInfo) -> int:
	if _state >= 2:
		return Combat.Result.IGNORED
	if hit_filter.is_valid():
		var r := int(hit_filter.call(hit))
		if r >= 0:
			if r == Combat.Result.DEFLECTED:
				hit.damage = 0.0
			return r
	var dmg := hit.damage * (1.6 if hit.is_heavy else 1.0)
	if kind == &"ice" and hit.element == ElementDefs.Element.FIRE:
		dmg *= 1.8
	hp -= dmg
	hit.damage = dmg
	_flash = 1.0
	if hp <= 0.0:
		crumble()
		return Combat.Result.KILLED
	return Combat.Result.BLOCKED


func _physics_process(delta: float) -> void:
	_t += delta
	if follow != null and is_instance_valid(follow) and _state < 2:
		var fb := Basis(Vector3.UP, follow.global_rotation.y)
		var fwd := -fb.z
		var o := follow.global_position + fb.x * follow_offset.x + fwd * follow_offset.z
		o.y = _ctx.ground_y(o, 1.5, 3.0) if _ctx != null and _ctx.is_valid() else follow.global_position.y
		_top = Transform3D(Basis.looking_at(-fwd, Vector3.UP), o)
		if _state == 1:
			global_transform = _top
	elif follow != null and _state < 2:
		crumble()
		return
	match _state:
		0:
			var u := clampf(_t / maxf(rise_time, 0.01), 0.0, 1.0)
			# Ease-out-back: overshoot a little, settle.
			var e := 1.0 + 2.2 * pow(u - 1.0, 3.0) + 1.2 * pow(u - 1.0, 2.0)
			global_transform = _top.translated(Vector3.DOWN * (size.y + 0.3) * (1.0 - e))
			_launch_overlapping()
			if u >= 1.0:
				global_transform = _top
				_state = 1
				_t = 0.0
		1:
			if _t >= lifetime:
				crumble()
		2:
			_crumble_t += delta
			var k := clampf(_crumble_t / 0.6, 0.0, 1.0)
			global_transform = _top.translated(Vector3.DOWN * size.y * k * k)
			if k >= 1.0:
				live.erase(self)
				queue_free()
	if _flash > 0.0 and _mat_flash:
		_flash = maxf(0.0, _flash - delta * 6.0)
		_mat_flash.set_shader_parameter(&"hit_flash", _flash * 0.35)


func _launch_overlapping() -> void:
	if _launch.is_empty() or _ctx == null or not _ctx.is_valid():
		return
	var center := global_position + Vector3.UP * size.y * 0.5
	var shape_q := BoxShape3D.new()
	shape_q.size = size + Vector3(0.3, 0.6, 0.3)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape_q
	params.transform = Transform3D(global_basis, center)
	params.collision_mask = _ctx.hit_mask() & ~Layers.CONSTRUCT
	params.exclude = _ctx.exclude()
	for r: Dictionary in get_world_3d().direct_space_state.intersect_shape(params, 16):
		var col: Object = r.get("collider")
		if not (col is Node):
			continue
		var t := Combat.find_damageable(col as Node)
		if t == null or t == self:
			continue
		var h := {"damage": float(_launch.get("damage", 8.0)), "reaction": HitInfo.Reaction.LAUNCH,
				"lift": float(_launch.get("lift", 7.0)), "force": 2.0, "poise": 30.0, "heavy": true}
		var dir := (t as Node3D).global_position - global_position if t is Node3D else Vector3.FORWARD
		var hit := _ctx.make_hit(h, dir, _attack_id, &"earth_wall")
		hit.position = BendingContext.target_point(t as Node3D) if t is Node3D else center
		BendingHits.deliver(_ctx, t, hit)


## Breaks the construct (crumble / shatter) and sinks it.
func crumble() -> void:
	if _state >= 2:
		return
	_state = 2
	_crumble_t = 0.0
	collision_layer = 0
	remove_from_group(&"damageable")
	var center := global_position + Vector3.UP * size.y * 0.5
	if kind == &"ice":
		IceFx.shatter(self, center, Vector3.ZERO, 1.6, ground_y)
		BendingFeedback.sound(ElementDefs.Element.WATER, &"wall_break", center)
	else:
		var right := global_basis.x
		for i in 3:
			var p := center + right * (float(i) - 1.0) * size.x * 0.33
			FxDebris.spawn(self, p, {"count": 7, "size": 0.22, "up": 4.0, "out": 3.0, "ground_y": ground_y})
		FxBurst.spawn(self, &"dust", Vector3(center.x, ground_y + 0.3, center.z), {"color": FxLib.surface_color(GroundSampler.surface(center)),
				"count": 2.0, "size": 1.4, "radius": size.x * 0.3})
		BendingFeedback.sound(ElementDefs.Element.EARTH, &"wall_break", center)
	broken.emit(self)


func _exit_tree() -> void:
	live.erase(self)
