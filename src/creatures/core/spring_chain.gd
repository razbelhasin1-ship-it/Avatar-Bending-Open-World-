class_name SpringChain
extends RefCounted
## Secondary motion ("jiggle bones") for a bone chain: tails, ears, whiskers, manes.
## The animated pose of the chain is the spring target; each bone's tip is simulated as
## a damped particle in WORLD space (so the chain lags behind body motion and swings
## when the creature turns), constrained to the bone length, and the bone is rotated
## to point at it. Bones further down the chain can be made looser with `falloff`.

var bones: PackedInt32Array = PackedInt32Array()
var stiffness := 60.0
var damping := 9.0
## World-space acceleration (e.g. Vector3(0, -2, 0) for droopy ears).
var gravity := Vector3.ZERO
## Stiffness multiplier per successive bone (< 1 = tip looser).
var falloff := 0.8
## 0..1 how much of the simulated motion is applied.
var weight := 1.0

var _tip_dir: PackedVector3Array = PackedVector3Array()
var _len: PackedFloat32Array = PackedFloat32Array()
var _x: PackedVector3Array = PackedVector3Array()
var _v: PackedVector3Array = PackedVector3Array()
var _ready := false


## `tip` = rest position of the end of the last bone (skeleton space).
func setup(skel: RigSkeleton, chain: PackedInt32Array, tip: Vector3) -> SpringChain:
	bones = chain
	_tip_dir.resize(chain.size())
	_len.resize(chain.size())
	_x.resize(chain.size())
	_v.resize(chain.size())
	for k in chain.size():
		var a := skel.rest_pos[chain[k]]
		var b := skel.rest_pos[chain[k + 1]] if k + 1 < chain.size() else tip
		_len[k] = maxf(a.distance_to(b), 1e-3)
		_tip_dir[k] = (b - a) / _len[k]
	return self


func reset() -> void:
	_ready = false


## Runs after the chain's animated pose is solved (globals up to date).
func update(skel: RigSkeleton, xf: Transform3D, delta: float) -> void:
	if bones.is_empty():
		return
	var n := bones.size()
	if not _ready or delta <= 0.0:
		for k in n:
			var g := skel.glob[bones[k]]
			_x[k] = xf * (g.origin + g.basis * _tip_dir[k] * _len[k])
			_v[k] = Vector3.ZERO
		_ready = true
		return
	var dt := minf(delta, 1.0 / 20.0)
	var inv := xf.affine_inverse()
	var k_stiff := stiffness
	for k in n:
		var bi := bones[k]
		# Re-derive this bone's global from its (possibly already sprung) parent.
		var p := skel.parent[bi]
		if k > 0 and p >= 0:
			skel.glob[bi] = skel.glob[p] * Transform3D(Basis(skel.rot[bi]), skel.rest_off[bi] + skel.off[bi])
		var g := skel.glob[bi]
		var origin_w := xf * g.origin
		var target_w := xf * (g.origin + g.basis * _tip_dir[k] * _len[k])
		var acc := (target_w - _x[k]) * k_stiff - _v[k] * damping + gravity
		_v[k] += acc * dt
		_x[k] += _v[k] * dt
		# Constrain to the bone length.
		var d := _x[k] - origin_w
		var dl := d.length()
		if dl < 1e-5:
			d = target_w - origin_w
			dl = d.length()
		_x[k] = origin_w + d * (_len[k] / dl)
		# Rotate the bone toward the simulated tip.
		var cur_dir := (g.basis * _tip_dir[k]).normalized()
		var want := (inv.basis * (_x[k] - origin_w)).normalized()
		want = cur_dir.slerp(want, weight) if weight < 1.0 else want
		if cur_dir.dot(want) < 0.99999:
			var q := Quaternion(cur_dir, want)
			var nb := Basis(q) * g.basis
			if p >= 0:
				skel.rot[bi] = (skel.glob[p].basis.transposed() * nb).get_rotation_quaternion()
			skel.glob[bi] = Transform3D(nb.orthonormalized(), g.origin)
		k_stiff *= falloff
