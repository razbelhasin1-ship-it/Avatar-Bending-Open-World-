class_name IceFloe
extends AnimatableBody3D
## A disc of ice frozen out of a water surface (Ice Trap / Ice Wall / Water
## Wave over water): a temporary walkable platform on Layers.CONSTRUCT (the
## player and enemies stand on it, swimmers are lifted out as it rises). It
## melts after `lifetime` (sinks and breaks up). Capped: at most MAX_LIVE floes,
## the oldest melts early. Not damageable, never a lock-on target.
##
##   var f := IceFloe.create(from, Vector3(x, water_level, z), 2.6, 14.0)

const MAX_LIVE := 6
const THICK := 0.5
## Top of the ice above the water line.
const FREEBOARD := 0.14

static var live: Array[IceFloe] = []

var radius := 2.6
var lifetime := 14.0
var level := 0.0
var mesh_i: MeshInstance3D
var _t := 0.0
var _state := 0  # 0 rising, 1 floating, 2 melting
var _melt_t := 0.0
var _rise := 0.22


static func create(from: Node, water_point: Vector3, p_radius: float = 2.6, p_lifetime: float = 14.0) -> IceFloe:
	_prune()
	while live.size() >= MAX_LIVE:
		var old: IceFloe = live.pop_front()
		if is_instance_valid(old):
			old.melt()
	var f := IceFloe.new()
	f.name = "IceFloe"
	f.radius = clampf(p_radius, 0.8, 6.0)
	f.lifetime = p_lifetime
	f.level = water_point.y
	FxLib.root(from).add_child(f)
	f._build(water_point)
	live.append(f)
	return f


static func _prune() -> void:
	for i in range(live.size() - 1, -1, -1):
		if not is_instance_valid(live[i]) or live[i]._state >= 2:
			live.remove_at(i)


## True if `p` (feet) stands on a live floe.
static func supports(p: Vector3) -> bool:
	_prune()
	for f in live:
		var d := Vector2(p.x - f.global_position.x, p.z - f.global_position.z).length()
		if d <= f.radius and absf(p.y - f.top_y()) < 0.6:
			return true
	return false


func top_y() -> float:
	return level + FREEBOARD


func _build(water_point: Vector3) -> void:
	collision_layer = Layers.CONSTRUCT
	collision_mask = 0
	sync_to_physics = false
	set_meta(&"no_lock", true)
	add_to_group(&"ice_floe")
	mesh_i = MeshInstance3D.new()
	mesh_i.mesh = mesh(radius, randi() % 4)
	mesh_i.material_override = material()
	mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_i)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius * 0.94
	cyl.height = THICK
	cs.shape = cyl
	cs.position = Vector3(0, FREEBOARD - THICK * 0.5, 0)
	add_child(cs)
	global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU), water_point + Vector3.DOWN * (THICK + 0.1))
	# The surface cracks white as it freezes.
	IceFx.shatter(self, water_point + Vector3.UP * 0.2, Vector3.UP, 0.6 + radius * 0.15, water_point.y)
	FxRing.spawn(self, water_point, radius * 1.15, Color(0.86, 0.96, 1.0), 0.45, {"opacity": 0.7, "fill": 0.3, "width": 0.14})
	FxBurst.spawn(self, &"snow", water_point + Vector3.UP * 0.2, {"count": 0.8, "radius": radius * 0.6, "color": Color(0.9, 0.97, 1.0)})
	Audio.play_bending(ElementDefs.Element.WATER, &"freeze", water_point, -2.0)


func _physics_process(delta: float) -> void:
	_t += delta
	var base := Vector3(global_position.x, level, global_position.z)
	match _state:
		0:
			var u := clampf(_t / _rise, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - u, 3.0)
			global_position = base + Vector3.DOWN * (THICK + 0.1) * (1.0 - e)
			if u >= 1.0:
				_state = 1
				_t = 0.0
		1:
			# Gentle bob on the water.
			global_position = base + Vector3.UP * sin(_t * 1.7) * 0.015
			if _t >= lifetime:
				melt()
		2:
			_melt_t += delta
			var k := clampf(_melt_t / 0.7, 0.0, 1.0)
			global_position = base + Vector3.DOWN * (THICK + 0.25) * k * k
			mesh_i.scale = Vector3(1.0 - 0.25 * k, 1.0, 1.0 - 0.25 * k)
			if k >= 1.0:
				live.erase(self)
				queue_free()


## Breaks up and sinks (lifetime over, or recycled).
func melt() -> void:
	if _state >= 2:
		return
	_state = 2
	_melt_t = 0.0
	collision_layer = 0
	var c := Vector3(global_position.x, level, global_position.z)
	IceFx.shatter(self, c + Vector3.UP * 0.2, Vector3.UP, 0.8, level)
	IceFx.splash(self, c, 0.7 + radius * 0.15)
	Audio.play_bending(ElementDefs.Element.WATER, &"shatter", c, -6.0)


func _exit_tree() -> void:
	live.erase(self)


static var _mesh_cache: Dictionary = {}
static var _mat: Material = null


static func material() -> Material:
	if _mat == null:
		var m := ShaderMaterial.new()
		m.shader = preload("res://src/fx/shaders/fx_ice.gdshader")
		m.set_shader_parameter(&"base_color", Color(0.42, 0.7, 0.9))
		m.set_shader_parameter(&"core_color", Color(0.78, 0.92, 0.99))
		m.set_shader_parameter(&"glow", 0.02)
		m.next_pass = ToonMaterials.outline(0.8, Color(0.16, 0.3, 0.42))
		_mat = m
	return _mat


## Irregular faceted ice disc: frosted top at y = FREEBOARD, flared sides down to -THICK.
static func mesh(r: float, variant: int = 0) -> ArrayMesh:
	var key := "%.1f_%d" % [r, variant]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4100 + variant
	var n := 11
	var top := PackedVector3Array()
	var bot := PackedVector3Array()
	for i in n:
		var a := TAU * float(i) / n + rng.randf_range(-0.12, 0.12)
		var rr := r * rng.randf_range(0.82, 1.06)
		top.append(Vector3(cos(a) * rr, FREEBOARD + rng.randf_range(-0.03, 0.04), sin(a) * rr))
		bot.append(Vector3(cos(a) * rr * 0.86, FREEBOARD - THICK, sin(a) * rr * 0.86))
	var tris := PackedVector3Array()
	var c := Vector3(0, FREEBOARD + 0.05, 0)
	for i in n:
		var j := (i + 1) % n
		WaterMeshes.add_tri(tris, c, top[i], top[j], Vector3.UP)
		var out := (top[i] + top[j]) * 0.5
		out.y = 0.0
		WaterMeshes.add_tri(tris, top[i], top[j], bot[j], out)
		WaterMeshes.add_tri(tris, top[i], bot[j], bot[i], out)
	var m := WaterMeshes.flat(tris, func(p: Vector3, nrm: Vector3) -> Color:
		# Frosted white top, clearer blue flanks.
		return Color(1, 1, 1) if nrm.y > 0.7 else Color(0.8, 0.9, 1.0))
	_mesh_cache[key] = m
	return m
