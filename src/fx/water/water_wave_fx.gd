class_name WaterWaveFx
extends Node3D
## A bent wave of water (Water Surge, Water Wave, Tidal Torrent): a crescent
## crest mesh (WaterMeshes.crest) with the bent-water shader, spray flying off
## the lip and a foam skirt at its foot. The owner moves it every tick
## (place()); it rises when spawned and collapses into spray on crash().
## Pooled through FxLib.
##
##   var w := WaterWaveFx.spawn(self, deg_to_rad(80), 3.0, 1.8, 1.4)
##   w.place(Transform3D(basis_facing_travel, ground_point))   # every tick
##   w.crash()                                               # collapse + return to the pool

const SHADER := preload("res://src/fx/water/fx_water_wave.gdshader")

var mesh_i: MeshInstance3D
var mat: ShaderMaterial
var spray: GPUParticles3D
var foam: GPUParticles3D
var span := 1.4
var radius := 3.0
var height := 1.8
var depth := 1.4
## 0..1 visible height (rise / collapse).
var rise := 0.0
var _rise_time := 0.16
var _t := 0.0
var _crash := -1.0
var _crash_time := 0.45
var _height_scale := 1.0


static func spawn(from: Node, p_span: float, p_radius: float, p_height: float, p_depth: float, opts: Dictionary = {}) -> WaterWaveFx:
	var w := FxLib.take(from, &"water_wave", WaterWaveFx._make) as WaterWaveFx
	w._setup(p_span, p_radius, p_height, p_depth, opts)
	return w


static func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"noise_tex", FxLib.noise_texture(&"smooth"))
	return m


static func _make() -> WaterWaveFx:
	var w := WaterWaveFx.new()
	w.name = "WaterWave"
	w.mesh_i = MeshInstance3D.new()
	w.mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.mat = material()
	w.mesh_i.material_override = w.mat
	w.add_child(w.mesh_i)
	w.spray = _emitter(26, 0.7, Vector3(0, 1, -0.6), 0.16, 0.3, Color(0.88, 0.96, 1.0, 0.9))
	w.add_child(w.spray)
	w.foam = _emitter(18, 0.9, Vector3(0, 0.6, 0.4), 0.3, 0.55, Color(0.92, 0.97, 1.0, 0.7))
	w.add_child(w.foam)
	return w


static func _emitter(count: int, life: float, dir: Vector3, s0: float, s1: float, col: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = FxLib.amount(count)
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-10, -3, -10), Vector3(20, 10, 20))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.0, 0.1, 0.2)
	pm.direction = dir.normalized()
	pm.spread = 35.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -9.0, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	pm.scale_min = s0
	pm.scale_max = s1
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.6))
	sc.add_point(Vector2(0.4, 1.0))
	sc.add_point(Vector2(1.0, 1.5))
	var ct := CurveTexture.new()
	ct.curve = sc
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, col.a))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	pm.color = Color(col.r, col.g, col.b)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	p.draw_pass_1 = q
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.billboard_keep_scale = true
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = FxLib.soft_dot()
	p.material_override = sm
	return p


func _setup(p_span: float, p_radius: float, p_height: float, p_depth: float, opts: Dictionary) -> void:
	span = p_span
	radius = snappedf(p_radius, 0.5)
	height = snappedf(p_height, 0.1)
	depth = snappedf(p_depth, 0.1)
	mesh_i.mesh = WaterMeshes.crest(span, radius, height, depth)
	mesh_i.scale = Vector3.ONE
	_rise_time = float(opts.get("rise_time", 0.16))
	_crash_time = float(opts.get("crash_time", 0.45))
	rise = 0.0 if _rise_time > 0.0 else 1.0
	_t = 0.0
	_crash = -1.0
	_height_scale = 1.0
	mat.set_shader_parameter(&"fade", 1.0)
	mat.set_shader_parameter(&"freeze", float(opts.get("freeze", 0.0)))
	mat.set_shader_parameter(&"glow", 0.0)
	mat.set_shader_parameter(&"streak_scale", Vector2(maxf(2.0, span * radius * 0.8), 1.2))
	# Spray off the lip along the whole crest.
	var width := 2.0 * radius * sin(minf(span * 0.5, PI * 0.5)) if span < TAU else radius * 2.0
	for e: GPUParticles3D in [spray, foam]:
		var pm := e.process_material as ParticleProcessMaterial
		pm.emission_box_extents = Vector3(width * 0.42, 0.1, 0.25)
		e.position = Vector3(0, height * (0.9 if e == spray else 0.1), -radius + depth * (0.2 if e == spray else -0.6))
		e.amount = FxLib.amount(int(clampf(width * (6.0 if e == spray else 4.0), 8.0, 48.0)))
		e.restart()
		e.emitting = FxLib.scale() > 0.3 and span < TAU
	_apply()


## Places the wave (origin = centre of the crest arc, -Z = travel direction).
func place(xform: Transform3D) -> void:
	global_transform = xform
	_apply()


## Height multiplier (riding waves swell / shrink).
func set_height_scale(k: float) -> void:
	_height_scale = maxf(0.05, k)
	_apply()


func set_freeze(f: float) -> void:
	mat.set_shader_parameter(&"freeze", clampf(f, 0.0, 1.0))


## Collapses into spray and returns to the pool.
func crash(duration: float = -1.0) -> void:
	if _crash >= 0.0:
		return
	if duration > 0.0:
		_crash_time = duration
	_crash = 0.0
	spray.emitting = false
	foam.emitting = false
	var c := global_transform * Vector3(0, height * 0.5, -radius)
	FxBurst.spawn(self, &"spray", c, {"count": 1.6, "size": 1.0 + height * 0.4, "radius": clampf(radius * 0.4, 0.6, 3.0), "dir": (-global_basis.z + Vector3.UP).normalized()})
	FxBurst.spawn(self, &"droplets", c, {"count": 1.5, "speed": 1.4, "radius": clampf(radius * 0.3, 0.5, 2.5)})


## Returns to the pool at once (no spray; scene teardown).
func drop() -> void:
	_crash = 99.0
	spray.emitting = false
	foam.emitting = false
	FxLib.release(self)


func is_crashing() -> bool:
	return _crash >= 0.0


func fx_reset() -> void:
	_crash = 99.0
	spray.emitting = false
	foam.emitting = false


func _apply() -> void:
	var h := rise * _height_scale
	if _crash >= 0.0:
		var k := clampf(_crash / _crash_time, 0.0, 1.0)
		h *= 1.0 - k * k
	mesh_i.scale = Vector3(1.0, maxf(h, 0.02), 1.0)


func _process(delta: float) -> void:
	_t += delta
	if _crash < 0.0 and rise < 1.0:
		rise = minf(1.0, _t / maxf(_rise_time, 0.01))
		rise = 1.0 - pow(1.0 - rise, 2.0)
		_apply()
	if _crash >= 0.0:
		_crash += delta
		var k := clampf(_crash / _crash_time, 0.0, 1.0)
		mat.set_shader_parameter(&"fade", 1.0 - k)
		_apply()
		if k >= 1.0:
			FxLib.release(self)
