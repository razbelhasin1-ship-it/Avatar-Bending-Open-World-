class_name BirdFlock
extends Node3D
## Cheap sky life: a flock of birds drawn with ONE MultiMesh draw call. Wings flap in
## the vertex shader (assets/shaders/creatures/bird.gdshader) from per-instance data;
## steering is a light boids variant (circle a center at an altitude band, cohesion,
## separation, wander), updated at a reduced rate when far from the camera.
##
##   var gulls := BirdFlock.create(&"gull", 14, harbor_pos, 40.0, 25.0)
##   add_child(gulls)
##   gulls.startle(player.global_position)   # scatter for a few seconds
##
## Kinds: &"gull" (white/grey, black tips, flappy), &"hawk" (brown, soaring),
## &"crow" (black, fast flaps). Count is scaled by Settings.vegetation_density()-like
## budgets by the caller; `max_distance` hides the flock beyond it.

const SHADER := preload("res://assets/shaders/creatures/bird.gdshader")

const KINDS := {
	&"gull": {"body": Color(0.96, 0.96, 0.97), "wing": Color(0.72, 0.75, 0.8), "tip": Color(0.1, 0.1, 0.12),
			"beak": Color(0.98, 0.76, 0.2), "belly": Color(1, 1, 1), "span": 1.3, "speed": 9.0, "flap_speed": 3.2, "soar": 0.35},
	&"hawk": {"body": Color(0.45, 0.3, 0.18), "wing": Color(0.5, 0.35, 0.2), "tip": Color(0.18, 0.12, 0.08),
			"beak": Color(0.95, 0.8, 0.3), "belly": Color(0.9, 0.82, 0.68), "span": 1.6, "speed": 11.0, "flap_speed": 2.2, "soar": 0.85},
	&"crow": {"body": Color(0.1, 0.1, 0.12), "wing": Color(0.12, 0.12, 0.15), "tip": Color(0.06, 0.06, 0.08),
			"beak": Color(0.15, 0.15, 0.15), "belly": Color(0.14, 0.14, 0.16), "span": 0.9, "speed": 8.0, "flap_speed": 4.5, "soar": 0.15},
}

var kind: StringName = &"gull"
var count := 12
## Circling center (world) and radius; altitude above center.y.
var center := Vector3.ZERO
var radius := 30.0
var altitude := 20.0
## Vertical spread of the altitude band (m).
var altitude_band := 8.0
var max_distance := 450.0

var _mmi: MultiMeshInstance3D
var _mm: MultiMesh
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _phase := PackedFloat32Array()
var _flap := PackedFloat32Array()
var _flap_target := PackedFloat32Array()
var _bank := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _accum := 0.0
var _scare := 0.0
var _scare_from := Vector3.ZERO
var _spec: Dictionary = {}
var _dir := 1.0
var _t := 0.0


## Creates a ready-to-add flock.
static func create(bird_kind: StringName, n: int, c: Vector3, r: float, alt: float, seed_value: int = 0) -> BirdFlock:
	var f := BirdFlock.new()
	f.kind = bird_kind if KINDS.has(bird_kind) else &"gull"
	f.count = maxi(1, n)
	f.center = c
	f.radius = r
	f.altitude = alt
	f._rng.seed = seed_value if seed_value != 0 else hash(c)
	f.name = "BirdFlock_%s" % f.kind
	return f


func _ready() -> void:
	_spec = KINDS[kind]
	_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = _bird_mesh(float(_spec["span"]))
	_mm.instance_count = count
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"body_color", _spec["body"])
	mat.set_shader_parameter(&"wing_color", _spec["wing"])
	mat.set_shader_parameter(&"tip_color", _spec["tip"])
	mat.set_shader_parameter(&"beak_color", _spec["beak"])
	mat.set_shader_parameter(&"belly_color", _spec["belly"])
	mat.set_shader_parameter(&"rim_strength", 0.2)
	_mmi.material_override = mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.visibility_range_end = max_distance
	_mmi.custom_aabb = AABB(Vector3(-radius - 60.0, -altitude - 40.0, -radius - 60.0), Vector3(radius * 2.0 + 120.0, altitude + 120.0, radius * 2.0 + 120.0))
	add_child(_mmi)
	_mmi.top_level = true
	_mmi.global_transform = Transform3D.IDENTITY
	_pos.resize(count)
	_vel.resize(count)
	_phase.resize(count)
	_flap.resize(count)
	_flap_target.resize(count)
	_bank.resize(count)
	var spd := float(_spec["speed"])
	for i in count:
		var a := _rng.randf() * TAU
		var r := radius * _rng.randf_range(0.6, 1.2)
		_pos[i] = center + Vector3(cos(a) * r, altitude + _rng.randf_range(-altitude_band, altitude_band) * 0.5, sin(a) * r)
		_vel[i] = Vector3(-sin(a), 0.0, cos(a)) * spd * _dir
		_phase[i] = _rng.randf()
		_flap[i] = _rng.randf()
		_flap_target[i] = _flap[i]
		_bank[i] = 0.0
	_write()


## Birds flee from `from` (upward and away) for a few seconds.
func startle(from: Vector3, duration: float = 4.0) -> void:
	_scare = duration
	_scare_from = from


## Moves the circling center (e.g. follow a harbor or the player region).
func set_center(c: Vector3, r: float = -1.0, alt: float = -1.0) -> void:
	center = c
	if r > 0.0:
		radius = r
	if alt > 0.0:
		altitude = alt


## Copy of the current bird positions (world).
func bird_positions() -> PackedVector3Array:
	return _pos.duplicate()


func _process(delta: float) -> void:
	_t += delta
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	var dist := cam.global_position.distance_to(center) if cam else 0.0
	if dist > max_distance + radius:
		return
	var interval := 0.0 if dist < 120.0 else (1.0 / 20.0 if dist < 260.0 else 1.0 / 8.0)
	_accum += delta
	if _accum < interval:
		return
	var dt := minf(_accum, 0.25)
	_accum = 0.0
	_steer(dt)
	_write()


func _steer(dt: float) -> void:
	var spd := float(_spec["speed"])
	var soar := float(_spec["soar"])
	_scare = maxf(0.0, _scare - dt)
	var avg := Vector3.ZERO
	for p in _pos:
		avg += p
	avg /= float(count)
	for i in count:
		var p := _pos[i]
		var v := _vel[i]
		var to_c := Vector3(center.x - p.x, 0.0, center.z - p.z)
		var d := to_c.length()
		var radial := to_c / maxf(d, 0.01)
		var tangent := Vector3(-radial.z, 0.0, radial.x) * -_dir
		var want := tangent * spd + radial * (d - radius) * 0.35
		var alt_target := center.y + altitude + sin(_t * 0.3 + float(i) * 1.7) * altitude_band * 0.5
		want.y = clampf((alt_target - p.y) * 0.6, -3.0, 3.0)
		want += (avg - p) * 0.05
		for j in count:
			if j == i:
				continue
			var o := p - _pos[j]
			var l2 := o.length_squared()
			if l2 < 9.0 and l2 > 1e-4:
				want += o / l2 * 6.0
		want += Vector3(sin(_t * 0.7 + i * 3.1), 0.0, cos(_t * 0.6 + i * 2.3)) * spd * 0.25
		if _scare > 0.0:
			var away := (p - _scare_from)
			away.y = maxf(away.y, 0.0) + 10.0
			want += away.normalized() * spd * 2.0
		var nv := v.lerp(want, 1.0 - exp(-dt * 1.4))
		var hs := Vector2(nv.x, nv.z).length()
		if hs < spd * 0.5:
			var hn := Vector2(nv.x, nv.z).normalized() * spd * 0.5 if hs > 0.01 else Vector2(tangent.x, tangent.z) * spd * 0.5
			nv.x = hn.x
			nv.z = hn.y
		# Turn rate -> bank.
		var turn := Vector2(v.x, v.z).angle_to(Vector2(nv.x, nv.z)) / maxf(dt, 1e-3)
		_bank[i] = lerpf(_bank[i], clampf(-turn * 0.6, -0.8, 0.8), 1.0 - exp(-dt * 3.0))
		_vel[i] = nv
		_pos[i] = p + nv * dt
		# Flap when climbing, scared or slow; otherwise glide (soarers glide more).
		var want_flap := 1.0 if (nv.y > 0.6 or _scare > 0.0) else (0.0 if _rng.randf() < soar else 0.6)
		if fmod(_t + float(i) * 0.37, 3.0) < dt or _scare > 0.0:
			_flap_target[i] = want_flap
		_flap[i] = move_toward(_flap[i], _flap_target[i], dt * 1.5)


func _write() -> void:
	var fs := float(_spec["flap_speed"])
	for i in count:
		var v := _vel[i]
		var fwd := v.normalized() if v.length_squared() > 1e-4 else Vector3.FORWARD
		if absf(fwd.y) > 0.97:
			fwd = Vector3(fwd.x, signf(fwd.y) * 0.97, fwd.z).normalized()
		var b := Basis.looking_at(fwd, Vector3.UP)
		b = b * Basis(Vector3.BACK, _bank[i])
		_mm.set_instance_transform(i, Transform3D(b, _pos[i]))
		_mm.set_instance_custom_data(i, Color(_phase[i], _flap[i], fs * (1.4 if _scare > 0.0 else 1.0), 0.0))


## Low-poly bird: body, head, beak, tail fan and two-segment wings along +-X.
## Vertex color: r = wing factor, g = side, b = part (see bird.gdshader).
static func _bird_mesh(span: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := span * 0.38
	var W := span * 0.09
	# Body: elongated octahedron-like spindle (8 sides) from tail (+Z) to head (-Z).
	var rings := [[L * 0.55, 0.0], [L * 0.25, W * 0.8], [-L * 0.1, W], [-L * 0.35, W * 0.75], [-L * 0.5, W * 0.55], [-L * 0.62, W * 0.3]]
	var seg := 8
	var pts: Array = []
	for r: Array in rings:
		var ring := []
		for j in seg:
			var a := float(j) / seg * TAU
			ring.append(Vector3(cos(a) * float(r[1]), sin(a) * float(r[1]) * 0.85, float(r[0])))
		pts.append(ring)
	for i in pts.size() - 1:
		for j in seg:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i][(j + 1) % seg]
			var c: Vector3 = pts[i + 1][(j + 1) % seg]
			var d: Vector3 = pts[i + 1][j]
			_tri(st, a, c, b, Color(0, 0.5, 0))
			_tri(st, a, d, c, Color(0, 0.5, 0))
	# Head cap and beak.
	var tip := Vector3(0, 0, -L * 0.75)
	for j in seg:
		_tri(st, pts[pts.size() - 1][j], pts[pts.size() - 1][(j + 1) % seg], tip, Color(0, 0.5, 0.5))
	# Tail fan.
	var t0 := Vector3(0, 0, L * 0.45)
	_tri(st, t0 + Vector3(-W * 0.4, 0, 0), t0 + Vector3(W * 0.4, 0, 0), t0 + Vector3(W * 1.4, 0, L * 0.45), Color(0, 0.5, 0))
	_tri(st, t0 + Vector3(-W * 0.4, 0, 0), t0 + Vector3(W * 1.4, 0, L * 0.45), t0 + Vector3(-W * 1.4, 0, L * 0.45), Color(0, 0.5, 0))
	# Wings: inner + outer panel per side (swept, tapered).
	for side in [-1.0, 1.0]:
		var g := 1.0 if side > 0.0 else 0.0
		var root_f := Vector3(side * W * 0.6, W * 0.2, -L * 0.18)
		var root_b := Vector3(side * W * 0.6, W * 0.2, L * 0.12)
		var mid_f := Vector3(side * span * 0.25, W * 0.25, -L * 0.12)
		var mid_b := Vector3(side * span * 0.25, W * 0.2, L * 0.2)
		var tip_f := Vector3(side * span * 0.5, W * 0.1, L * 0.02)
		var tip_b := Vector3(side * span * 0.47, W * 0.1, L * 0.16)
		var c0 := Color(0.05, g, 0.0)
		var c1 := Color(0.5, g, 0.0)
		var c2 := Color(1.0, g, 1.0)
		_quad(st, root_f, mid_f, mid_b, root_b, [c0, c1, c1, c0])
		_quad(st, mid_f, tip_f, tip_b, mid_b, [c1, c2, c2, c1])
	st.generate_normals()
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for p in [a, b, c]:
		st.set_color(col)
		st.add_vertex(p)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, cols: Array) -> void:
	var pts := [a, b, c, a, c, d]
	var cs := [cols[0], cols[1], cols[2], cols[0], cols[2], cols[3]]
	for i in 6:
		st.set_color(cs[i])
		st.add_vertex(pts[i])
