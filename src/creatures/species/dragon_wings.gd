class_name DragonWings
extends RefCounted
## Membrane wing rig + poser for one side of the dragon.
##
## Bones (per side): wing_arm (shoulder) -> wing_fore (elbow) -> wing_hand (wrist) ->
## three fingers f1 (leading), f2, f3 with two segments each. The wing is built
## spread (its rest pose). Each frame `pose()` blends joint directions between the
## spread pose (rotated by the flap angle about the body axis, swept, with upstroke
## flex) and a designed folded pose, then aims every bone so the skinned membrane
## follows. All directions are in the parent spine bone's frame.

const FINGERS := 3

var side := 1.0
var parent := -1
var arm := -1
var fore := -1
var hand := -1
var fa := PackedInt32Array()   # finger first segments
var fb := PackedInt32Array()   # finger second segments
## Rest joint positions (skeleton space).
var p_shoulder := Vector3.ZERO
var p_elbow := Vector3.ZERO
var p_wrist := Vector3.ZERO
var p_knuckle: PackedVector3Array = PackedVector3Array()
var p_tip: PackedVector3Array = PackedVector3Array()

var _len := {}
var _rest_dir := {}
var _fold_dir := {}


## Rest layout for the RIGHT wing at scale 1 (x is mirrored for the left wing).
static func layout(k: float, sd: float) -> Dictionary:
	var m := func(x: float, y: float, z: float) -> Vector3: return Vector3(x * sd, y, z) * k
	return {
		"shoulder": m.call(0.55, 2.85, 1.0), "elbow": m.call(2.6, 3.28, 1.25), "wrist": m.call(5.4, 3.5, 0.75),
		"knuckles": [m.call(7.4, 3.5, 1.05), m.call(6.95, 3.38, 2.25), m.call(5.95, 3.3, 2.6)],
		"tips": [m.call(8.9, 3.32, 1.7), m.call(7.85, 3.15, 3.8), m.call(6.05, 3.08, 4.55)],
	}


func add_bones(s: RigSkeleton, parent_name: StringName, k: float, sd: float) -> void:
	side = sd
	var L := layout(k, sd)
	var sx := "l" if sd < 0.0 else "r"
	s.add(StringName("wing_arm_" + sx), parent_name, L["shoulder"])
	s.add(StringName("wing_fore_" + sx), StringName("wing_arm_" + sx), L["elbow"])
	s.add(StringName("wing_hand_" + sx), StringName("wing_fore_" + sx), L["wrist"])
	for f in FINGERS:
		var a := StringName("wing_f%da_%s" % [f + 1, sx])
		var b := StringName("wing_f%db_%s" % [f + 1, sx])
		s.add(a, StringName("wing_hand_" + sx), L["wrist"])
		s.add(b, a, L["knuckles"][f])
	parent = s.idx(parent_name)
	arm = s.idx(StringName("wing_arm_" + sx))
	fore = s.idx(StringName("wing_fore_" + sx))
	hand = s.idx(StringName("wing_hand_" + sx))
	for f in FINGERS:
		fa.append(s.idx(StringName("wing_f%da_%s" % [f + 1, sx])))
		fb.append(s.idx(StringName("wing_f%db_%s" % [f + 1, sx])))
	p_shoulder = L["shoulder"]
	p_elbow = L["elbow"]
	p_wrist = L["wrist"]
	for f in FINGERS:
		p_knuckle.append(L["knuckles"][f])
		p_tip.append(L["tips"][f])
	_len["arm"] = p_shoulder.distance_to(p_elbow)
	_len["fore"] = p_elbow.distance_to(p_wrist)
	_rest_dir["arm"] = (p_elbow - p_shoulder).normalized()
	_rest_dir["fore"] = (p_wrist - p_elbow).normalized()
	for f in FINGERS:
		_len["fa%d" % f] = p_wrist.distance_to(p_knuckle[f])
		_len["fb%d" % f] = p_knuckle[f].distance_to(p_tip[f])
		_rest_dir["fa%d" % f] = (p_knuckle[f] - p_wrist).normalized()
		_rest_dir["fb%d" % f] = (p_tip[f] - p_knuckle[f]).normalized()
	# Folded along the flank: humerus up/back, forearm forward, fingers back and down.
	var m := func(x: float, y: float, z: float) -> Vector3: return Vector3(x * sd, y, z).normalized()
	_fold_dir["arm"] = m.call(0.3, 0.5, 0.82)
	_fold_dir["fore"] = m.call(0.16, -0.12, -1.0)
	_fold_dir["fa0"] = m.call(0.2, -0.22, 1.0)
	_fold_dir["fb0"] = m.call(0.1, -0.3, 1.0)
	_fold_dir["fa1"] = m.call(0.24, -0.45, 1.0)
	_fold_dir["fb1"] = m.call(0.08, -0.55, 1.0)
	_fold_dir["fa2"] = m.call(0.26, -0.7, 1.0)
	_fold_dir["fb2"] = m.call(0.06, -0.8, 1.0)


## Total span of this wing from the shoulder to the farthest tip.
func reach() -> float:
	var r := 0.0
	for t in p_tip:
		r = maxf(r, Vector2(t.x - p_shoulder.x, t.z - p_shoulder.z).length())
	return r


## fold 0..1 (1 = folded on the flank), flap (rad, + = wing up), flex 0..1 (elbow/wrist
## bend for the upstroke), sweep (rad, + = wing forward), spread 0..1 finger fan.
func pose(s: RigSkeleton, fold: float, flap: float, flex: float, sweep: float, spread: float) -> void:
	var pb := s.glob[parent].basis
	var R := Basis(Vector3.UP, sweep * side) * Basis(Vector3.BACK, flap * side)
	# Pole = membrane normal: up when spread, facing outward when folded on the flank.
	var pole_spread := R * Vector3.UP
	var pole_fold := Vector3(side, 0.15, 0.0).normalized()
	var pole := pole_spread.lerp(pole_fold, fold).normalized()
	var flex_q := clampf(flex, 0.0, 1.0)
	var d_arm := _blend(R * _rest_dir["arm"], _fold_dir["arm"], fold)
	var d_fore := _blend(R * _rest_dir["fore"], _fold_dir["fore"], clampf(fold + flex_q * 0.35, 0.0, 1.0))
	_aim(s, arm, pb, _rest_dir["arm"], d_arm, pole)
	_aim(s, fore, pb, _rest_dir["fore"], d_fore, pole)
	# The hand bone carries no geometry of its own: keep it aligned with the forearm.
	_aim(s, hand, pb, _rest_dir["fore"], d_fore, pole)
	for f in FINGERS:
		var fan := (1.0 - spread) * (float(f) - 1.0) * 0.25
		var Rf := R * Basis(Vector3.UP, fan * side)
		var ff := clampf(fold + flex_q * (0.45 + 0.1 * f), 0.0, 1.0)
		var da := _blend(Rf * _rest_dir["fa%d" % f], _fold_dir["fa%d" % f], ff)
		var db := _blend(Rf * _rest_dir["fb%d" % f], _fold_dir["fb%d" % f], ff)
		_aim(s, fa[f], pb, _rest_dir["fa%d" % f], da, pole)
		_aim(s, fb[f], pb, _rest_dir["fb%d" % f], db, pole)


static func _blend(a: Vector3, b: Vector3, t: float) -> Vector3:
	var v := a.lerp(b, t)
	if v.length_squared() < 1e-6:
		v = b
	return v.normalized()


## Sets bone `i` so its rest direction maps to `dir` (parent-frame directions converted
## to skeleton space through the parent spine basis `pb`), updating rot and glob.
static func _aim(s: RigSkeleton, i: int, pb: Basis, rest_d: Vector3, dir: Vector3, pole: Vector3) -> void:
	var g := CreatureLeg.aim(rest_d, pb * dir, Vector3.UP, pb * pole)
	var p := s.parent[i]
	var origin := s.glob[p] * (s.rest_off[i] + s.off[i])
	s.rot[i] = (s.glob[p].basis.transposed() * g).get_rotation_quaternion()
	s.glob[i] = Transform3D(g.orthonormalized(), origin)
