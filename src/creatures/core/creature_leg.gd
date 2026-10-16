class_name CreatureLeg
extends RefCounted
## One leg of a creature: bone chain, rest geometry, stepping state (owned by
## GaitEngine) and an analytic two-bone IK with an optional third "metacarpal /
## metatarsal" segment for digitigrade legs (dogs, birds).
##
## Chain: upper (shoulder/hip) -> lower (elbow/knee) -> [meta (wrist/hock)] -> foot.
## The foot bone's origin is the IK target; it sits `ankle_h` above the ground contact.

enum Group { FRONT, MIDDLE, HIND }

var id: StringName
var index := 0
var upper := -1
var lower := -1
var meta := -1
var foot := -1
var toe := -1
var l1 := 1.0
var l2 := 1.0
var l3 := 0.0
## +1 right, -1 left.
var side := 1.0
var group: int = Group.FRONT
## Body-space direction the knee/elbow points to (IK pole).
var knee_dir := Vector3.BACK
## Body-space direction from the foot up to the wrist/hock (digitigrade only).
var meta_dir := Vector3.UP
## Rest ground contact in rig space (y = 0).
var neutral := Vector3.ZERO
## Height of the foot bone origin above the ground contact.
var ankle_h := 0.1
var paw_size := 0.2
var weight := 0.5
## Swing arc height multiplier.
var lift_scale := 1.0
## Free (flight/dangle) paw position relative to the hip, body space.
var tuck := Vector3(0, -0.5, 0)
## Paw curl during swing (radians the foot pitches toes-down at mid swing).
var curl := 0.6

# Stepping state (world space).
var planted := true
var foot_world := Vector3.ZERO
var ground_normal := Vector3.UP
var swing_from := Vector3.ZERO
var swing_to := Vector3.ZERO
var swing_t := 1.0
var swing_dur := 0.3
var in_window := false
## 0..1 progress through the current swing arc (0 when planted).
var lift := 0.0
## 0..1 blend toward the free (tucked / action-driven) pose.
var free := 0.0
var was_free := false
## Where the paw contact actually is after blending (world), set by the motor.
var paw_world := Vector3.ZERO
var surface: StringName = &"grass"

var _rest_d1 := Vector3.DOWN
var _rest_d2 := Vector3.DOWN
var _rest_d3 := Vector3.DOWN


## Reads bone indices and lengths. `bones` = [upper, lower, foot] or
## [upper, lower, meta, foot]; `contact` = rest ground contact (rig space).
func setup(skel: RigSkeleton, leg_id: StringName, bones: Array, contact: Vector3) -> void:
	id = leg_id
	upper = skel.idx(bones[0])
	lower = skel.idx(bones[1])
	if bones.size() >= 4:
		meta = skel.idx(bones[2])
		foot = skel.idx(bones[3])
	else:
		foot = skel.idx(bones[2])
	assert(upper >= 0 and lower >= 0 and foot >= 0, "CreatureLeg %s: missing bones" % leg_id)
	var p1 := skel.rest_pos[upper]
	var p2 := skel.rest_pos[lower]
	var p3 := skel.rest_pos[meta] if meta >= 0 else skel.rest_pos[foot]
	l1 = p1.distance_to(p2)
	l2 = p2.distance_to(p3)
	_rest_d1 = (p2 - p1).normalized()
	_rest_d2 = (p3 - p2).normalized()
	if meta >= 0:
		l3 = p3.distance_to(skel.rest_pos[foot])
		_rest_d3 = (skel.rest_pos[foot] - p3).normalized()
		meta_dir = (p3 - skel.rest_pos[foot]).normalized()
	neutral = Vector3(contact.x, 0.0, contact.z)
	ankle_h = skel.rest_pos[foot].y - contact.y
	side = signf(contact.x) if absf(contact.x) > 1e-3 else 1.0


## Total reach from hip to foot origin.
func reach() -> float:
	return l1 + l2 + l3


## Solves the chain so the foot bone origin reaches `target` (rig space).
## `body` is the parent body basis (rig space) used for the pole and foot yaw;
## `normal` the ground normal (rig space) the paw aligns to when planted.
func solve(skel: RigSkeleton, target: Vector3, body: Basis, normal: Vector3) -> void:
	var a := skel.glob[upper].origin
	var w := target
	var md := Vector3.ZERO
	if meta >= 0:
		# Digitigrade: the wrist/hock sits above the paw; curl it back during swing.
		md = (body * meta_dir.rotated(Vector3.RIGHT, -curl * sin(lift * PI) * 0.9 - free * 0.4)).normalized()
		w = target + md * l3
	var pole := body * knee_dir
	var knee := two_bone(a, w, l1, l2, pole)
	var b1 := aim(_rest_d1, knee - a, knee_dir, pole)
	_put(skel, upper, b1)
	var b2 := aim(_rest_d2, w - knee, knee_dir, pole)
	_put(skel, lower, b2)
	if meta >= 0:
		var b3 := aim(_rest_d3, target - w, knee_dir, pole)
		_put(skel, meta, b3)
	# Foot: body yaw, tilted to the ground when planted, toes curled in swing.
	var fwd := -body.z
	# nlerp (Vector3.slerp is unstable for nearly parallel vectors).
	var up := normal.normalized().lerp(body.y, clampf(free + lift * 0.5, 0.0, 1.0)).normalized()
	fwd = (fwd - up * fwd.dot(up)).normalized()
	if fwd.length_squared() < 1e-6:
		fwd = Vector3.FORWARD
	var right := fwd.cross(up).normalized()
	var fb := Basis(right, up, -fwd).orthonormalized()
	fb = fb * Basis(Vector3.RIGHT, -curl * sin(lift * PI) - free * 0.5)
	_put(skel, foot, fb)
	if toe >= 0:
		skel.glob[toe] = skel.glob[foot] * Transform3D(Basis(skel.rot[toe]), skel.rest_off[toe] + skel.off[toe])


## Analytic two-bone IK: returns the joint position bending toward `pole`.
static func two_bone(a: Vector3, t: Vector3, la: float, lb: float, pole: Vector3) -> Vector3:
	var d := t - a
	var dist := d.length()
	var x := d / dist if dist > 1e-5 else Vector3.DOWN
	dist = clampf(dist, absf(la - lb) + 1e-3, (la + lb) * 0.9995)
	var y := pole - x * pole.dot(x)
	if y.length_squared() < 1e-8:
		y = Vector3.FORWARD - x * x.z
	y = y.normalized()
	var cos_a := clampf((la * la + dist * dist - lb * lb) / (2.0 * la * dist), -1.0, 1.0)
	var ang := acos(cos_a)
	return a + x * (cos(ang) * la) + y * (sin(ang) * la)


## Rotation that takes a rest bone direction (with its rest pole) to a new direction
## (with a new pole), as a skeleton-space basis (rest bases are identity).
static func aim(rest_d: Vector3, new_d: Vector3, rest_pole: Vector3, new_pole: Vector3) -> Basis:
	var f0 := _frame(rest_d, rest_pole)
	var f1 := _frame(new_d, new_pole)
	return f1 * f0.transposed()


static func _frame(d: Vector3, pole: Vector3) -> Basis:
	var a := d.normalized()
	var b := pole - a * pole.dot(a)
	if b.length_squared() < 1e-8:
		b = Vector3.FORWARD - a * a.z
		if b.length_squared() < 1e-8:
			b = Vector3.UP - a * a.y
	b = b.normalized()
	return Basis(a, b, a.cross(b))


static func _put(skel: RigSkeleton, i: int, b: Basis) -> void:
	var p := skel.parent[i]
	var origin := skel.glob[p] * (skel.rest_off[i] + skel.off[i]) if p >= 0 else skel.rest_off[i]
	# Pre-orthonormalized: near-degenerate IK frames (legs swinging free while a flyer lands)
	# otherwise fail the engine's float32 rotation check inside get_rotation_quaternion().
	skel.rot[i] = (skel.glob[p].basis.transposed() * b).orthonormalized().get_rotation_quaternion() if p >= 0 else b.orthonormalized().get_rotation_quaternion()
	skel.glob[i] = Transform3D(b.orthonormalized(), origin)
