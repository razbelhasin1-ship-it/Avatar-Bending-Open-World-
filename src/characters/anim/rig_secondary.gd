class_name RigSecondary
extends RefCounted
## Cheap secondary motion run after the main solve:
## * Spring chains (hair tails, long hair, capes): verlet tip particles in
##   WORLD space so they trail behind motion, pulled toward the animated pose,
##   length-constrained, kept out of the back, then turned into bone rotations.
## * Skirt bones: front/back panels follow the forward/backward thigh swing
##   (so long robes never get pierced by a stepping leg) plus a damped sway
##   from body acceleration.

const SK = preload("res://src/characters/rig/rig_skeleton_def.gd")

var chains: Array = []
var skirt_bones := PackedInt32Array()
var _p: Array = []        # per chain: Array[Vector3] current tip particles (world)
var _pp: Array = []       # per chain: previous particles
var _len: Array = []      # per chain: PackedFloat32Array bone lengths
var _dir: Array = []      # per chain: Array[Vector3] rest bone directions
var _initialized := false
var _skirt_sway := Vector2.ZERO
var _skirt_vel := Vector2.ZERO
var _last_root := Vector3.ZERO
var _last_vel := Vector3.ZERO
var enabled := true


func setup(d: RigSkeletonDef, chain_descs: Array) -> void:
	chains.clear()
	for c: Dictionary in chain_descs:
		if c.get("skirt", false):
			skirt_bones = PackedInt32Array(c["bones"])
			continue
		var bones: Array = c["bones"]
		var lens := PackedFloat32Array()
		var dirs: Array[Vector3] = []
		for k in bones.size():
			var b: int = bones[k]
			var nxt: Vector3 = d.rest_pos[bones[k + 1]] if k + 1 < bones.size() else (c["tip"] as Vector3)
			var off := nxt - d.rest_pos[b]
			lens.append(off.length())
			dirs.append(off.normalized())
		chains.append(c)
		_len.append(lens)
		_dir.append(dirs)
		_p.append([])
		_pp.append([])
	_initialized = false


func reset() -> void:
	_initialized = false


## Runs after RigSolver.solve(); `model_to_world` is the skeleton's global transform.
func process(s: RigSolver, model_to_world: Transform3D, dt: float) -> void:
	if skirt_bones.size() == 4:
		_skirt(s, model_to_world, dt)
	if not enabled or chains.is_empty():
		_initialized = false
		return
	var inv := model_to_world.affine_inverse()
	var g := Vector3(0, -9.8, 0)
	var dts := clampf(dt, 0.0, 1.0 / 20.0)
	for ci in chains.size():
		var c: Dictionary = chains[ci]
		var bones: Array = c["bones"]
		var lens: PackedFloat32Array = _len[ci]
		var dirs: Array[Vector3] = _dir[ci]
		var ps: Array = _p[ci]
		var pps: Array = _pp[ci]
		var stiff: float = c.get("stiffness", 0.5)
		var damp: float = c.get("damping", 0.4)
		var grav: float = c.get("gravity", 0.6)
		var collide: bool = c.get("collide_back", false)
		if not _initialized or ps.size() != bones.size():
			ps.clear()
			pps.clear()
			for k in bones.size():
				var b: int = bones[k]
				var par := s.parents[b]
				var tip := s.g_pos[b] + s.g_basis[par] * (dirs[k] * lens[k])
				ps.append(model_to_world * tip)
				pps.append(model_to_world * tip)
		for k in bones.size():
			var b: int = bones[k]
			var par := s.parents[b]
			s.local_rot[b] = Basis.IDENTITY
			s._fk(b)
			var head_m := s.g_pos[b]
			var target_m := head_m + s.g_basis[par] * (dirs[k] * lens[k])
			var head_w := model_to_world * head_m
			var target_w := model_to_world * target_m
			var p: Vector3 = ps[k]
			var pp: Vector3 = pps[k]
			var vel := (p - pp) * (1.0 - damp)
			pps[k] = p
			p += vel + g * grav * dts * dts
			p = p.lerp(target_w, 1.0 - pow(1.0 - stiff, dts * 60.0))
			var off := p - head_w
			var wl := lens[k] * model_to_world.basis.get_scale().x
			p = head_w + (off.normalized() * wl if off.length_squared() > 1e-10 else target_w - head_w)
			var pm := inv * p
			if collide:
				var uc := s.g_basis[SK.UPPER_CHEST]
				var q := uc.transposed() * (pm - s.g_pos[SK.UPPER_CHEST])
				var min_back: float = float(s.def.p["chest_d"]) * float(s.def.p["height"]) * 1.15
				if q.z < min_back:
					q.z = min_back
					pm = s.g_pos[SK.UPPER_CHEST] + uc * q
					p = model_to_world * pm
			ps[k] = p
			var cur := (target_m - head_m).normalized()
			var want := (pm - head_m).normalized()
			if cur.dot(want) < 0.99999:
				var rot := Basis(Quaternion(cur, want))
				s.local_rot[b] = s.g_basis[par].transposed() * rot * s.g_basis[par]
			s._fk(b)
	_initialized = true


func _skirt(s: RigSolver, model_to_world: Transform3D, dt: float) -> void:
	# Body acceleration in model space drives a small damped sway.
	var root := model_to_world.origin
	if dt > 0.0:
		var vel := (root - _last_root) / dt
		var acc := (vel - _last_vel) / maxf(dt, 0.001)
		_last_vel = vel
		var acc_m := model_to_world.basis.transposed() * acc
		var target := Vector2(clampf(acc_m.z * 0.02, -0.35, 0.35), clampf(-acc_m.x * 0.015, -0.25, 0.25))
		_skirt_vel += ((target - _skirt_sway) * 90.0 - _skirt_vel * 10.0) * minf(dt, 0.05)
		_skirt_sway += _skirt_vel * minf(dt, 0.05)
		if not enabled:
			_skirt_sway = Vector2.ZERO
			_skirt_vel = Vector2.ZERO
	_last_root = root
	var fwd := maxf(maxf(s.thigh_swing[0], s.thigh_swing[1]), 0.0)
	var back := minf(minf(s.thigh_swing[0], s.thigh_swing[1]), 0.0)
	var f := skirt_bones[0]
	var b := skirt_bones[1]
	var l := skirt_bones[2]
	var r := skirt_bones[3]
	s.local_rot[f] = Basis(Vector3.RIGHT, fwd * 0.9 + _skirt_sway.x)
	s.local_rot[b] = Basis(Vector3.RIGHT, back * 0.9 + _skirt_sway.x)
	s.local_rot[l] = Basis(Vector3.BACK, -maxf(s.thigh_abduct[0], 0.0) * 0.8 + _skirt_sway.y)
	s.local_rot[r] = Basis(Vector3.BACK, maxf(s.thigh_abduct[1], 0.0) * 0.8 + _skirt_sway.y)
	for i in [f, b, l, r]:
		s._fk(i)
