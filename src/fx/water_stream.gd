class_name WaterStream
extends Node3D
## A bendable water tube along a curve (whips, streams drawn from sources,
## torrents, orbiting shields). Rebuilt every frame from control points with a
## Catmull-Rom spline into a cheap ImmediateMesh tube; the water shader flows
## along it, and `freeze` turns it to ice. Droplets spray from the head.
##
##   var s := WaterStream.spawn(self)
##   s.set_points(PackedVector3Array([hand, mid, tip]), 0.09, 0.05)   # world space
##   s.freeze = 0.6
##   s.finish(0.25)     # retract/fade, then returns to the pool

const RINGS_MAX := 40
const SIDES := 7

var mesh_instance: MeshInstance3D
var imesh: ImmediateMesh
var mat: ShaderMaterial
var points := PackedVector3Array()
var radius_head := 0.08
var radius_tail := 0.05
## 0..1 visible fraction from the head (tail retracts toward the head when < 1).
var reveal := 1.0
var freeze := 0.0:
	set(v):
		freeze = clampf(v, 0.0, 1.0)
		if mat:
			mat.set_shader_parameter(&"freeze", freeze)
var droplets: GPUParticles3D
var _fade := -1.0
var _fade_t := 0.0
var _alpha := 1.0
var _dirty := true


static func spawn(from: Node) -> WaterStream:
	var s := FxLib.take(from, &"water_stream", WaterStream._make) as WaterStream
	s.global_transform = Transform3D.IDENTITY
	s._fade = -1.0
	s._alpha = 1.0
	s.reveal = 1.0
	s.freeze = 0.0
	s.points = PackedVector3Array()
	s.imesh.clear_surfaces()
	s.droplets.emitting = false
	# Drop drivers left by a previous user of this pooled stream.
	for c in s.get_children():
		if c.has_meta(&"stream_driver"):
			c.queue_free()
	return s


static func _make() -> WaterStream:
	var s := WaterStream.new()
	s.name = "WaterStream"
	s.imesh = ImmediateMesh.new()
	s.mesh_instance = MeshInstance3D.new()
	s.mesh_instance.mesh = s.imesh
	s.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.mat = material()
	s.mesh_instance.material_override = s.mat
	s.add_child(s.mesh_instance)
	s.droplets = _make_droplets()
	s.add_child(s.droplets)
	return s


## A fresh water material instance (each stream animates its own freeze).
static func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://src/fx/shaders/fx_water.gdshader")
	m.set_shader_parameter(&"noise_tex", FxLib.noise_texture(&"smooth"))
	return m


static func _make_droplets() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = FxLib.amount(18)
	p.lifetime = 0.5
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.direction = Vector3.UP
	pm.spread = 75.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3(0, -9.0, 0)
	pm.scale_min = 0.04
	pm.scale_max = 0.08
	pm.color = Color(0.85, 0.95, 1.0, 0.9)
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
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## World-space control points (tail first, head last) and radii.
func set_points(p_points: PackedVector3Array, head_radius: float = 0.08, tail_radius: float = 0.05) -> void:
	points = p_points
	radius_head = head_radius
	radius_tail = tail_radius
	_dirty = true


## Head position (last control point).
func head() -> Vector3:
	return points[points.size() - 1] if points.size() > 0 else global_position


func set_spray(on: bool) -> void:
	droplets.emitting = on and FxLib.scale() > 0.3


## Starts retracting/fading; returns to the pool when done.
func finish(duration: float = 0.25) -> void:
	if _fade >= 0.0:
		return
	_fade = maxf(duration, 0.02)
	_fade_t = 0.0
	droplets.emitting = false


func fx_reset() -> void:
	_fade = 0.001
	_fade_t = 1.0


func _process(delta: float) -> void:
	if _fade >= 0.0:
		_fade_t += delta
		_alpha = clampf(1.0 - _fade_t / _fade, 0.0, 1.0)
		_dirty = true
		if _fade_t >= _fade:
			imesh.clear_surfaces()
			FxLib.release(self)
			return
	if points.size() >= 2:
		droplets.global_position = head()
	if _dirty:
		_rebuild()


func _rebuild() -> void:
	_dirty = false
	imesh.clear_surfaces()
	var n := points.size()
	if n < 2 or _alpha <= 0.0:
		return
	# Sample the Catmull-Rom spline.
	var seg := clampi(n * 5, 6, RINGS_MAX)
	var samples := PackedVector3Array()
	samples.resize(seg + 1)
	for i in seg + 1:
		samples[i] = _spline(float(i) / seg * (n - 1))
	var start := clampi(int(floor((1.0 - reveal) * seg)), 0, seg - 1)
	imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_ring: Array[Vector3] = []
	var prev_norm: Array[Vector3] = []
	var prev_u := 0.0
	var up_ref := Vector3.UP
	var total_len := 0.0
	for i in range(start + 1, seg + 1):
		total_len += samples[i].distance_to(samples[i - 1])
	var acc := 0.0
	for i in range(start, seg + 1):
		var p := samples[i]
		var t := (samples[mini(i + 1, seg)] - samples[maxi(i - 1, start)])
		if t.length_squared() < 1e-8:
			t = Vector3.FORWARD
		t = t.normalized()
		if absf(t.dot(up_ref)) > 0.95:
			up_ref = Vector3.RIGHT
		var bx := t.cross(up_ref).normalized()
		var by := bx.cross(t).normalized()
		up_ref = by
		if i > start:
			acc += p.distance_to(samples[i - 1])
		var u := acc / maxf(total_len, 0.001)
		var r := lerpf(radius_tail, radius_head, u)
		# Rounded caps at both ends.
		r *= sqrt(clampf(u * 6.0, 0.15, 1.0)) * sqrt(clampf((1.0 - u) * 10.0 + 0.35, 0.35, 1.0))
		var ring: Array[Vector3] = []
		var norms: Array[Vector3] = []
		for k in SIDES:
			var a := TAU * float(k) / SIDES
			var nn := bx * cos(a) + by * sin(a)
			ring.append(p + nn * r)
			norms.append(nn)
		if not prev_ring.is_empty():
			var ca := Color(1, 1, 1, _alpha * clampf(prev_u * 4.0, 0.25, 1.0))
			var cb := Color(1, 1, 1, _alpha * clampf(u * 4.0, 0.25, 1.0))
			for k in SIDES:
				var k2 := (k + 1) % SIDES
				var v0 := float(k) / SIDES
				var v1 := float(k + 1) / SIDES
				# Clockwise seen from outside (Godot front faces).
				_vtx(prev_ring[k], prev_norm[k], Vector2(prev_u, v0), ca)
				_vtx(ring[k2], norms[k2], Vector2(u, v1), cb)
				_vtx(ring[k], norms[k], Vector2(u, v0), cb)
				_vtx(prev_ring[k], prev_norm[k], Vector2(prev_u, v0), ca)
				_vtx(prev_ring[k2], prev_norm[k2], Vector2(prev_u, v1), ca)
				_vtx(ring[k2], norms[k2], Vector2(u, v1), cb)
		prev_ring = ring
		prev_norm = norms
		prev_u = u
	imesh.surface_end()


func _vtx(p: Vector3, n: Vector3, uv: Vector2, c: Color) -> void:
	imesh.surface_set_normal(n)
	imesh.surface_set_uv(uv)
	imesh.surface_set_color(c)
	imesh.surface_add_vertex(to_local(p))


func _spline(f: float) -> Vector3:
	var n := points.size()
	var i := clampi(int(floor(f)), 0, n - 2)
	var u := f - i
	var p0 := points[maxi(i - 1, 0)]
	var p1 := points[i]
	var p2 := points[i + 1]
	var p3 := points[mini(i + 2, n - 1)]
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)
