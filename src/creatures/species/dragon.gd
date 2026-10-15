extends CreatureSpecies
## Dragon (Fire companion): a ~20 m serpentine dragon with red scales and gold belly
## plates, horns, whiskers, beard and flowing mane, glowing slit eyes, four clawed legs
## and huge membrane wings.
##
## The rig origin sits under the SHOULDERS; neck and head reach ahead of it and the
## 26-segment body/tail follows the path the shoulders travelled (a recorded trail), so
## the body snakes through turns on the ground and in the air. Lateral undulation is
## synced to the leg gait when crawling; flight adds vertical undulation, banking per
## segment (stored in the trail), flapping/gliding wings, takeoff and landing.

const DragonMesh := preload("res://src/creatures/species/dragon_mesh.gd")

const SEG := 0.6
const SPINE := 26
## Rest height of each spine joint above the ground (k = 1) and body radii.
const HEIGHTS := [2.2, 2.24, 2.27, 2.27, 2.25, 2.21, 2.16, 2.1, 2.04, 1.98, 1.92, 1.84, 1.75, 1.64, 1.52,
		1.4, 1.28, 1.16, 1.05, 0.95, 0.86, 0.78, 0.71, 0.65, 0.6, 0.56, 0.53]
const HIND := 10
const TRAIL_STEP := 0.2

const SCALE := Color(0.70, 0.10, 0.07)
const BELLY := Color(0.96, 0.74, 0.28)
const MANE := Color(0.99, 0.80, 0.38)
const HORN := Color(0.95, 0.86, 0.62)
const MEMBRANE := Color(0.78, 0.22, 0.10)

var rig_ref: WeakRef
var wings: Array[DragonWings] = []
var spine_bones := PackedInt32Array()

var _trail := PackedVector3Array()
var _trail_bank := PackedFloat32Array()
var _trail_ready := false
var _flap := 0.0
var _glide := 0.0
var _glide_timer := 0.0
var _gliding := false
var _flap_count := 0
var _prev_flap := 0.0
var _wing_fold := 1.0
var _bank_now := 0.0


func id() -> StringName:
	return &"dragon"


func can_fly() -> bool:
	return true


func draw_distance() -> float:
	return 900.0


func _init() -> void:
	tune["neck_down"] = -0.6
	tune["head_up"] = 0.5
	tune["rear_pitch"] = 0.55
	tune["bite_reach"] = 0.9
	tune["flight_blend"] = 1.4
	tune["takeoff_leap"] = 0.75
	tune["shake_roll"] = 0.1


func build(rig: CreatureRig) -> void:
	rig_ref = weakref(rig)
	var s := rig.skel
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z) * k
	s.add(&"root", &"", Vector3.ZERO)
	var prev := &"root"
	for i in SPINE:
		var n := StringName("spine_%d" % i)
		s.add(n, prev, v.call(0, HEIGHTS[i], i * SEG))
		spine_bones.append(s.idx(n))
		prev = n
	var neck_pts := [v.call(0, 2.36, -0.42), v.call(0, 2.76, -1.12), v.call(0, 3.14, -1.84), v.call(0, 3.44, -2.6), v.call(0, 3.6, -3.36)]
	prev = &"spine_0"
	for i in neck_pts.size():
		var n := StringName("neck_%d" % i)
		s.add(n, prev, neck_pts[i])
		prev = n
	s.add(&"head", &"neck_4", v.call(0, 3.66, -4.05))
	s.add(&"jaw", &"head", v.call(0, 3.47, -4.22))
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		s.add(StringName("eye_" + sx), &"head", v.call(0.4 * side, 3.82, -4.74))
		s.add(StringName("lid_" + sx), &"head", v.call(0.4 * side, 3.82, -4.74))
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		var wp := [v.call(0.3 * side, 3.55, -5.38), v.call(0.72 * side, 3.46, -5.08), v.call(1.12 * side, 3.25, -4.6), v.call(1.42 * side, 3.0, -4.0)]
		var p2 := &"head"
		for i in wp.size():
			var n := StringName("whisker%d_%s" % [i, sx])
			s.add(n, p2, wp[i])
			p2 = n
	# Legs: front on the shoulders, hind on spine HIND. Sprawled, lizard-like.
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		s.add(StringName("fl_upper_" + sx), &"spine_0", v.call(0.62 * side, 2.0, 0.08))
		s.add(StringName("fl_lower_" + sx), StringName("fl_upper_" + sx), v.call(1.12 * side, 1.3, 0.42))
		s.add(StringName("fl_meta_" + sx), StringName("fl_lower_" + sx), v.call(1.26 * side, 0.46, 0.02))
		s.add(StringName("fl_foot_" + sx), StringName("fl_meta_" + sx), v.call(1.3 * side, 0.2, -0.14))
	var hz := HIND * SEG
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		s.add(StringName("hl_upper_" + sx), StringName("spine_%d" % HIND), v.call(0.6 * side, 1.78, hz))
		s.add(StringName("hl_lower_" + sx), StringName("hl_upper_" + sx), v.call(1.12 * side, 1.18, hz - 0.42))
		s.add(StringName("hl_meta_" + sx), StringName("hl_lower_" + sx), v.call(1.22 * side, 0.52, hz + 0.26))
		s.add(StringName("hl_foot_" + sx), StringName("hl_meta_" + sx), v.call(1.26 * side, 0.2, hz + 0.06))
	for side in [-1.0, 1.0]:
		var w := DragonWings.new()
		w.add_bones(s, &"spine_1", k, side)
		wings.append(w)
	var order := [["fl", -1.0, CreatureLeg.Group.FRONT], ["fl", 1.0, CreatureLeg.Group.FRONT],
			["hl", -1.0, CreatureLeg.Group.HIND], ["hl", 1.0, CreatureLeg.Group.HIND]]
	for o: Array in order:
		var sx: String = "l" if float(o[1]) < 0.0 else "r"
		var pre: String = o[0]
		var l := CreatureLeg.new()
		var fp := s.rest_pos[s.idx(StringName(pre + "_foot_" + sx))]
		l.setup(s, StringName(pre + "_" + sx), [StringName(pre + "_upper_" + sx), StringName(pre + "_lower_" + sx),
				StringName(pre + "_meta_" + sx), StringName(pre + "_foot_" + sx)], Vector3(fp.x, 0.0, fp.z - 0.1 * k))
		l.group = o[2]
		var sd: float = o[1]
		l.knee_dir = Vector3(0.6 * sd, 0.0, 1.0).normalized() if l.group == CreatureLeg.Group.FRONT else Vector3(0.6 * sd, 0.0, -1.0).normalized()
		l.paw_size = 0.75 * k
		l.weight = 0.9
		l.curl = 0.7
		l.lift_scale = 1.0
		l.tuck = Vector3(0.35 * sd, -0.55, 0.7) * k if l.group == CreatureLeg.Group.FRONT else Vector3(0.3 * sd, -0.35, 1.3) * k
		rig.legs.append(l)
	var m := rig.motor
	m.root = s.idx(&"root")
	m.pelvis = -1
	m.body_override = _solve_spine
	m.neck = PackedInt32Array()
	for i in 5:
		m.neck.append(s.idx(StringName("neck_%d" % i)))
	m.neck_weights = PackedFloat32Array([0.14, 0.2, 0.22, 0.22, 0.22])
	m.head = s.idx(&"head")
	m.jaw = s.idx(&"jaw")
	m.eye_l = s.idx(&"eye_l")
	m.eye_r = s.idx(&"eye_r")
	m.lid_l = s.idx(&"lid_l")
	m.lid_r = s.idx(&"lid_r")
	m.lid_open = 0.75
	m.lid_closed = -0.25
	m.head_stab = 0.5
	m.jaw_open = 0.7
	m.look_yaw_limit = 1.3
	m.look_pitch_limit = 0.7
	m.look_neck_share = 0.7
	m.hind_z = HIND * SEG * k
	m.front_z = 0.0
	m.breath_bones = PackedInt32Array([s.idx(&"spine_2"), s.idx(&"spine_3"), s.idx(&"spine_4")])
	m.breath_scale = Vector3(0.03, 0.035, 0.0)
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		var chain := PackedInt32Array()
		for i in 4:
			chain.append(s.idx(StringName("whisker%d_%s" % [i, sx])))
		var sp := SpringChain.new().setup(s, chain, v.call(1.6 * side, 2.7, -3.3))
		sp.stiffness = 26.0
		sp.damping = 4.0
		sp.falloff = 0.85
		sp.gravity = Vector3(0, -2.0, 0)
		m.springs.append(sp)
	var tail_tip := PackedInt32Array()
	for i in range(SPINE - 5, SPINE):
		tail_tip.append(s.idx(StringName("spine_%d" % i)))
	var ts := SpringChain.new().setup(s, tail_tip, v.call(0, HEIGHTS[SPINE], SPINE * SEG))
	ts.stiffness = 55.0
	ts.damping = 8.0
	ts.falloff = 0.85
	m.springs.append(ts)
	rig.gaits.append(GaitEngine.make_gait({"name": &"walk", "max_speed": 3.2 * sqrt(k), "duty": 0.66,
			"offsets": [0.25, 0.75, 0.0, 0.5], "freq": 0.62, "ref_speed": 2.2 * sqrt(k), "lift": 0.38 * k,
			"bob": 0.03, "bob_mult": 2.0, "head_bob": 0.02}))
	rig.gaits.append(GaitEngine.make_gait({"name": &"run", "duty": 0.46,
			"offsets": [0.0, 0.5, 0.5, 0.0], "freq": 1.05, "ref_speed": 7.5 * sqrt(k), "lift": 0.6 * k,
			"bob": 0.06, "bob_mult": 2.0, "head_bob": 0.03}))
	rig.gait.tempo = sqrt(k)
	rig.breath_period = 4.5
	rig.add_socket(&"saddle", &"spine_0", Transform3D(Basis.IDENTITY, v.call(0, 0.98, -0.15)))
	rig.add_socket(&"back", &"spine_3", Transform3D(Basis.IDENTITY, v.call(0, 0.95, 0.0)))
	rig.add_socket(&"rider_left", &"spine_2", Transform3D(Basis.IDENTITY, v.call(-0.8, 0.55, 0.0)))
	rig.add_socket(&"rider_right", &"spine_2", Transform3D(Basis.IDENTITY, v.call(0.8, 0.55, 0.0)))
	rig.add_socket(&"head", &"head", Transform3D(Basis.IDENTITY, v.call(0, 0.2, -0.6)))
	rig.add_socket(&"mouth", &"head", Transform3D(Basis.IDENTITY, v.call(0, -0.26, -1.65)))
	rig.add_socket(&"chest", &"spine_2", Transform3D(Basis.IDENTITY, v.call(0, -0.6, 0.0)))
	rig.add_socket(&"tail", &"spine_%d" % (SPINE - 1), Transform3D(Basis.IDENTITY, v.call(0, 0, 0.6)))
	rig.add_socket(&"wing_left", &"wing_hand_l", Transform3D.IDENTITY)
	rig.add_socket(&"wing_right", &"wing_hand_r", Transform3D.IDENTITY)
	rig.set_dimensions({
		"length": 21.5 * k, "height": 4.4 * k, "width": 3.0 * k, "wingspan": 17.8 * k, "saddle_height": 3.2 * k,
		"paw_size": 0.75 * k, "weight": 0.9, "can_fly": true, "walk_speed": 2.2 * sqrt(k),
		"run_speed": 7.5 * sqrt(k), "sprint_speed": 10.0 * sqrt(k), "fly_speed": 30.0,
		"collision_radius": 1.3 * k, "collision_height": 3.0 * k, "mass": 6000.0 * k * k * k,
	})


func build_mesh(rig: CreatureRig, kit: MeshKit) -> void:
	DragonMesh.build(self, rig, kit)


func material_for(surface: StringName, detail: int, _lod: int) -> Material:
	return DragonMesh.material(self, surface, detail)


# --- Trail-following spine ------------------------------------------------------------------

func _rig() -> CreatureRig:
	return rig_ref.get_ref() as CreatureRig if rig_ref else null


func _reset_trail(rig: CreatureRig) -> void:
	_trail.clear()
	_trail_bank.clear()
	var p := rig.global_position
	var back := rig.global_basis.z
	back.y = 0.0
	back = back.normalized() if back.length_squared() > 1e-6 else Vector3.BACK
	var n := int(ceil((SPINE + 2) * SEG * k / TRAIL_STEP)) + 4
	for i in n:
		_trail.append(p + back * TRAIL_STEP * (i + 1))
		_trail_bank.append(0.0)
	_trail_ready = true


func _record_trail(rig: CreatureRig) -> void:
	var p := rig.global_position
	if not _trail_ready or p.distance_to(_trail[0]) > 25.0 * k:
		_reset_trail(rig)
	if p.distance_to(_trail[0]) >= TRAIL_STEP:
		_trail.insert(0, p)
		_trail_bank.insert(0, _bank_now)
		var max_n := int(ceil((SPINE + 4) * SEG * k / TRAIL_STEP)) + 12
		if _trail.size() > max_n:
			_trail.resize(max_n)
			_trail_bank.resize(max_n)


## World points (and banks) at arc distances `ds` (ascending) behind the shoulders.
func _sample(from: Vector3, ds: PackedFloat32Array, out_p: PackedVector3Array, out_b: PackedFloat32Array) -> void:
	var prev := from
	var prev_b := _bank_now
	var acc := 0.0
	var i := 0
	var k_i := 0
	while k_i < ds.size():
		var target := ds[k_i]
		if i >= _trail.size():
			var dir := (prev - _trail[_trail.size() - 2]).normalized() if _trail.size() > 1 else Vector3.BACK
			out_p[k_i] = prev + dir * (target - acc)
			out_b[k_i] = prev_b
			k_i += 1
			continue
		var nxt := _trail[i]
		var d := prev.distance_to(nxt)
		if acc + d >= target and d > 1e-5:
			var t := (target - acc) / d
			out_p[k_i] = prev.lerp(nxt, t)
			out_b[k_i] = lerpf(prev_b, _trail_bank[i], t)
			k_i += 1
		else:
			acc += d
			prev = nxt
			prev_b = _trail_bank[i]
			i += 1


func _solve_spine(pose: CreaturePose) -> void:
	var rig := _rig()
	if rig == null or not rig.is_inside_tree():
		return
	var s := rig.skel
	var xf := rig.global_transform
	var inv := xf.affine_inverse()
	_record_trail(rig)
	var n := SPINE + 1
	var ds := PackedFloat32Array()
	for i in n:
		ds.append(i * SEG * k)
	var pts := PackedVector3Array()
	pts.resize(n)
	var banks := PackedFloat32Array()
	banks.resize(n)
	_sample(rig.global_position, ds, pts, banks)
	var fw := rig.flight_w
	var front_lift := sin(clampf(pose.body_pitch - rig.flight_pitch * fw, -0.6, 1.2)) * 4.0 * k * (1.0 - fw * 0.7)
	var fwd_root := -xf.basis.z
	# Heights above the trail (ground profile -> level in flight) + undulation.
	var ge := rig.gait
	var lat_amp := (0.3 + 0.15 * clampf(ge.speed / maxf(rig.run_speed, 0.1), 0.0, 1.0)) * k * ge.motion_w * (1.0 - fw)
	var vert_amp := 0.45 * k * fw * (1.0 - _glide * 0.7)
	for i in n:
		var u := float(i) / (n - 1)
		var h := lerpf(float(HEIGHTS[i]) * k, float(HEIGHTS[0]) * k, fw)
		var lift_w := maxf(0.0, 1.0 - ds[i] / (5.5 * k))
		h += front_lift * lift_w * lift_w + pose.body_y * (1.0 - 0.6 * u)
		pts[i] += Vector3.UP * h
	var right := PackedVector3Array()
	right.resize(n)
	for i in n:
		var f := _fwd(pts, i, fwd_root)
		right[i] = f.cross(Vector3.UP).normalized() if absf(f.y) < 0.98 else Vector3.RIGHT
	for i in n:
		var u := float(i) / (n - 1)
		var env := smoothstep(0.0, 0.25, u) * (1.0 - 0.35 * u)
		var wave := sin(TAU * (ds[i] / (7.0 * k) - ge.phase))
		pts[i] += right[i] * lat_amp * wave * env
		var vwave := sin(TAU * (ds[i] / (9.0 * k) - _flap))
		pts[i] += Vector3.UP * vert_amp * vwave * smoothstep(0.0, 0.3, u)
	# Frames -> rig-space transforms -> local rotations/offsets.
	var prev_g := Transform3D.IDENTITY
	var prev_up := xf.basis.y.normalized()
	for i in SPINE:
		var f := _fwd(pts, i, fwd_root)
		var roll := banks[i] * fw + pose.body_roll * (1.0 - fw) * (1.0 - float(i) / n)
		# Near-vertical path segments (climbing/diving straight) use the previous
		# segment's up vector so the frame never degenerates.
		var up_ref := Vector3.UP if absf(f.y) < 0.9 else prev_up
		var up := Basis(f, roll) * up_ref
		var z := -f
		var xv := up.cross(z)
		if xv.length_squared() < 1e-6:
			xv = prev_up.cross(z)
			if xv.length_squared() < 1e-6:
				xv = Vector3.RIGHT
		var x := xv.normalized()
		var y := z.cross(x).normalized()
		prev_up = y
		var g := inv * Transform3D(Basis(x, y, z), pts[i])
		var bi := spine_bones[i]
		var local := g if i == 0 else prev_g.affine_inverse() * g
		s.rot[bi] = local.basis.get_rotation_quaternion()
		s.off[bi] = local.origin - s.rest_off[bi]
		s.glob[bi] = Transform3D(g.basis.orthonormalized(), g.origin)
		prev_g = s.glob[bi]


func _fwd(pts: PackedVector3Array, i: int, fwd_root: Vector3) -> Vector3:
	var a := pts[i - 1] if i > 0 else pts[0] + fwd_root * SEG * k
	var b := pts[i + 1] if i + 1 < pts.size() else pts[i] - (pts[i - 1] - pts[i])
	var f := (a - b)
	if i == 0:
		f = f.normalized().lerp(fwd_root, 0.5)
	return f.normalized() if f.length_squared() > 1e-8 else fwd_root


# --- Locomotion / flight -----------------------------------------------------------------

func animate(rig: CreatureRig, pose: CreaturePose, delta: float) -> void:
	var ge := rig.gait
	var turn := clampf(rig.yaw_rate, -2.0, 2.0)
	pose.neck_yaw += turn * 0.3
	pose.head_yaw += turn * 0.15
	pose.head_pitch += ge.out_head
	pose.body_y += ge.out_bob * k
	pose.body_roll += -turn * clampf(ge.speed / maxf(rig.run_speed, 0.1), 0.0, 1.0) * 0.1
	pose.breath += sin(rig.time * TAU / rig.breath_period)
	_bank_now = rig.flight_bank * rig.flight_w + pose.body_roll * (1.0 - rig.flight_w)
	_update_flap(rig, delta)


func _update_flap(rig: CreatureRig, delta: float) -> void:
	var fw := rig.flight_w
	var spd := rig.flight_velocity.length() if rig.flying else rig.velocity.length()
	var climbing := rig.flight_pitch > 0.08 or spd < 12.0 * sqrt(k) or rig.is_action_playing(&"takeoff") \
			or rig.is_action_playing(&"land")
	var cruising := fw > 0.95 and not climbing
	# Cruise rhythm: a few strong beats, then a long glide.
	if not cruising:
		_gliding = false
		_flap_count = 0
	elif _gliding:
		_glide_timer -= delta
		if _glide_timer <= 0.0:
			_gliding = false
			_flap_count = 0
	elif _flap_count >= 3:
		_gliding = true
		_glide_timer = rng.randf_range(2.5, 4.5)
	_glide = move_toward(_glide, 1.0 if _gliding else 0.0, delta * 0.9)
	var freq := (0.85 if climbing else 0.55) / sqrt(k)
	# While gliding the cycle eases toward the wings-level phase and holds there.
	if _glide > 0.0:
		freq *= 1.0 - 0.85 * _glide
	_prev_flap = _flap
	_flap = fmod(_flap + delta * freq, 1.0)
	if _flap < _prev_flap:
		_flap_count += 1
		if rig.sounds and fw > 0.3 and _glide < 0.5 and rig.lod <= 1 and rig.is_inside_tree():
			Audio.play_sfx(&"wing_flap_large", rig.global_position + Vector3.UP * 3.0 * k, -2.0, 0.1, 220.0)


func flight_pose(rig: CreatureRig, pose: CreaturePose, _delta: float) -> void:
	var fw := rig.flight_w
	# Exposed for consumers (cameras, riders); the spine applies the banks from the trail.
	pose.body_roll += fw * rig.flight_bank
	pose.body_pitch += fw * rig.flight_pitch
	pose.neck_pitch += fw * (-0.42 - rig.flight_pitch * 0.3)
	pose.head_pitch += fw * (0.3 + rig.flight_pitch * 0.2)
	pose.neck_yaw += fw * -rig.flight_bank * 0.25
	pose.head_roll += fw * -rig.flight_bank * 0.3
	pose.head_stab += fw * 0.3
	pose.jaw += fw * 0.06


## Wing flap angle at flap phase p: fast downstroke (0..0.42), slower upstroke.
func _flap_angle(p: float, amp: float) -> float:
	if p < 0.42:
		return lerpf(amp, -amp * 0.75, smoothstep(0.0, 1.0, p / 0.42))
	return lerpf(-amp * 0.75, amp, smoothstep(0.0, 1.0, (p - 0.42) / 0.58))


func post_pose(rig: CreatureRig, _delta: float) -> void:
	var fw := rig.flight_w
	var fold := 1.0 - fw
	var amp := lerpf(0.9, 0.6, _glide)
	var flap := _flap_angle(_flap, amp) * (1.0 - _glide) + _glide * (0.1 + 0.03 * sin(rig.time * 1.3))
	var upstroke := smoothstep(0.42, 0.6, _flap) * (1.0 - smoothstep(0.85, 1.0, _flap)) * (1.0 - _glide)
	var sweep := 0.0
	var spread := 1.0
	var extra_raise := 0.0
	for a in rig.actions.active():
		var w := a.weight
		match a.name:
			&"roar", &"rear_up":
				var e := a.envelope(0.25, 0.25)
				fold -= 0.55 * e * w * (1.0 - fw)
				extra_raise += 0.45 * e * w * (1.0 - fw)
			&"takeoff":
				var e := a.window(0.0, 1.0, 0.15)
				fold -= 0.9 * e * w
				if fw < 0.3:
					flap = lerpf(flap, _flap_angle(_flap, 1.0), e * w)
			&"land":
				var e := a.window(0.0, 0.85, 0.15)
				sweep += 0.35 * e * w
				fold -= 0.2 * e * w
			&"breathe_fire_start":
				fold -= 0.3 * a.envelope(0.2, 0.0) * w * (1.0 - fw)
			&"stretch_wings":
				var e := a.envelope(0.25, 0.3)
				fold -= 0.95 * e * w * (1.0 - fw)
				extra_raise += 0.35 * e * w * sin(a.t * 2.2) * (1.0 - fw)
	fold = clampf(fold, 0.0, 1.0)
	_wing_fold = fold
	# Near the ground (takeoff/landing) the downstroke is shortened so the tips clear it.
	if fw > 0.0 and fw < 1.0 or rig.is_landing():
		var alt := rig.altitude() if rig.is_inside_tree() else 10.0
		var floor_ang := -0.12 - 0.85 * clampf(alt / (6.0 * k), 0.0, 1.0)
		flap = maxf(flap, floor_ang)
	for w in wings:
		w.pose(rig.skel, fold, (flap + extra_raise) * (1.0 - fold * 0.9) + extra_raise * fold, upstroke * (1.0 - fold),
				sweep + 0.1 * (1.0 - fold) * sin(_flap * TAU), spread)
		rig.skel.fk_list(rig.motor.skel_subtree(w.arm))


# --- Actions --------------------------------------------------------------------------------

func idle_actions() -> Array[StringName]:
	return [&"look_around", &"sniff", &"snort", &"look_around", &"yawn", &"stretch_wings"]


func make_action(action_name: StringName, opts: Dictionary) -> CreatureAction:
	match action_name:
		&"takeoff":
			var t := CreatureAction.new(action_name, 2.4)
			t.roots = true
			t.blend_in = 0.25
			t.blend_out = 0.7
			t.add_event(0.75, &"leap")
			return t
		&"land":
			var l := CreatureAction.new(action_name, 2.2)
			l.blend_in = 0.4
			l.blend_out = 0.7
			l.add_event(1.45, &"touchdown")
			return l
		&"breathe_fire_start":
			var f := CreatureAction.new(action_name, 0.7)
			f.hold = true
			f.blend_in = 0.15
			f.blend_out = 0.4
			f.add_event(0.0, &"inhale")
			f.add_event(0.6, &"fire_start")
			return f
		&"breathe_fire_end":
			var e := CreatureAction.new(action_name, 0.6)
			e.blend_in = 0.05
			e.blend_out = 0.3
			e.add_event(0.0, &"fire_end")
			return e
		&"snort":
			var sn := CreatureAction.new(action_name, 1.4)
			sn.add_event(0.55, &"smoke")
			return sn
		&"stretch_wings":
			var sw := CreatureAction.new(action_name, 3.6)
			sw.roots = true
			return sw
		&"prowl":
			var p := CreatureAction.new(action_name, 0.8)
			p.hold = true
			p.blend_out = 0.6
			return p
		&"roar":
			var r := CreatureAction.new(action_name, 2.8)
			r.add_event(0.8, &"vocal_start")
			r.add_event(2.3, &"vocal_end")
			return r
	return super.make_action(action_name, opts)


func action_pose(rig: CreatureRig, a: CreatureAction, pose: CreaturePose) -> void:
	var w := a.weight
	match a.name:
		&"takeoff":
			var crouch := a.window(0.0, 0.4, 0.15)
			var leap := a.window(0.28, 0.75, 0.15)
			pose.body_y += -0.55 * crouch * k * w
			pose.body_pitch += 0.2 * leap * w
			pose.neck_pitch += (-0.2 * crouch + 0.15 * leap) * w
			pose.head_pitch += 0.15 * leap * w
			return
		&"land":
			var reach := a.window(0.1, 0.72, 0.2)
			var impact := a.window(0.62, 0.95, 0.12)
			pose.body_pitch += 0.18 * reach * w
			pose.body_y += -0.35 * impact * k * w
			pose.neck_pitch += 0.1 * reach * w
			for l in rig.legs:
				pose.add_paw(l.index, Vector3(0, -0.5, -0.3) * k * reach * w)
			return
		&"breathe_fire_start":
			var inhale := a.window(0.0, 0.6, 0.2) if not a.stopping else 0.0
			var hold := smoothstep(0.45, 0.7, a.t)
			pose.neck_pitch += (0.35 * inhale - 0.25 * hold) * w
			pose.head_pitch += (0.3 * inhale - 0.15 * hold) * w
			pose.jaw += (0.2 * inhale + 1.0 * hold) * w
			pose.eyes_narrow += 0.7 * hold * w
			pose.breath += 1.5 * inhale * w
			pose.head_stab += 0.3 * w
			pose.head_pitch += sin(a.t * 23.0) * 0.015 * hold * w
			return
		&"breathe_fire_end":
			var e := a.envelope(0.05, 0.6)
			pose.jaw += 0.4 * (1.0 - a.progress()) * e * w
			return
		&"snort":
			var e := a.window(0.2, 0.8, 0.2)
			pose.head_pitch += (0.2 * e - 0.25 * a.window(0.45, 0.65, 0.08)) * w
			pose.eyes_narrow += 0.5 * e * w
			return
		&"stretch_wings":
			# The wings open in post_pose; lift the head proudly.
			var e := a.envelope(0.25, 0.3)
			pose.neck_pitch += 0.25 * e * w
			pose.head_pitch += 0.2 * e * w
			return
		&"prowl":
			var e := smoothstep(0.0, 1.0, minf(1.0, a.t / a.duration))
			pose.body_y += -0.6 * k * e * w
			pose.neck_pitch += -0.35 * e * w
			pose.head_pitch += 0.25 * e * w
			pose.eyes_narrow += 0.5 * e * w
			return
	super.action_pose(rig, a, pose)


func sound_for(action: StringName, event: StringName) -> StringName:
	match event:
		&"vocal_start":
			return &"dragon_roar"
		&"leap", &"touchdown":
			return &"wing_flap_large" if event == &"leap" else &"land_heavy"
		&"fire_start":
			return &"fire_whoosh"
		&"smoke":
			return &"fire_extinguish"
	if action == &"growl" and event == &"vocal_start":
		return &"dragon_roar"
	return &""
