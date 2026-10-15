class_name RigSkeleton
extends RefCounted
## Bone table + procedural pose of a CreatureRig.
##
## Every bone has an identity rest basis, so its axes are the creature axes
## (+X right, +Y up, -Z forward) and rotations read naturally ("pitch the neck
## about X"). A bone's local pose is `Transform3D(Basis(rot), rest_off + off)`
## relative to its parent. Globals (skeleton space == rig space) are computed here
## by `fk()` and pushed to a *flat* Skeleton3D in which every bone is a root, so the
## engine does no hierarchy work and skinning uses exactly the transforms we solved.

var names: PackedStringArray = PackedStringArray()
var parent: PackedInt32Array = PackedInt32Array()
## Rest position in skeleton space.
var rest_pos: PackedVector3Array = PackedVector3Array()
## Rest offset from the parent's rest position.
var rest_off: PackedVector3Array = PackedVector3Array()
## Local rotation (relative to the parent's frame).
var rot: Array[Quaternion] = []
## Extra local translation on top of rest_off.
var off: PackedVector3Array = PackedVector3Array()
## Non-inherited scale (applied only to the bone's own skin, never to children).
var scl: PackedVector3Array = PackedVector3Array()
## Solved skeleton-space transforms (unscaled).
var glob: Array[Transform3D] = []

var _index: Dictionary = {}
var _scaled: PackedByteArray = PackedByteArray()


## Adds a bone at skeleton-space rest position `pos`. Parents must be added first.
func add(bone_name: StringName, parent_name: StringName, pos: Vector3) -> int:
	var p := -1
	if parent_name != &"":
		p = int(_index.get(parent_name, -1))
		assert(p >= 0, "RigSkeleton: unknown parent %s" % parent_name)
	var i := names.size()
	names.append(bone_name)
	parent.append(p)
	rest_pos.append(pos)
	rest_off.append(pos - (rest_pos[p] if p >= 0 else Vector3.ZERO))
	rot.append(Quaternion.IDENTITY)
	off.append(Vector3.ZERO)
	scl.append(Vector3.ONE)
	glob.append(Transform3D(Basis.IDENTITY, pos))
	_scaled.append(0)
	_index[bone_name] = i
	return i


## Bone index or -1.
func idx(bone_name: StringName) -> int:
	return int(_index.get(bone_name, -1))


func has(bone_name: StringName) -> bool:
	return _index.has(bone_name)


func count() -> int:
	return names.size()


## Resets every bone to its rest pose (rotation, offset, scale).
func reset_pose() -> void:
	for i in names.size():
		rot[i] = Quaternion.IDENTITY
		off[i] = Vector3.ZERO
		if _scaled[i]:
			scl[i] = Vector3.ONE
			_scaled[i] = 0


func set_scale(i: int, s: Vector3) -> void:
	scl[i] = s
	_scaled[i] = 1


## Forward kinematics for all bones (parents always precede children).
func fk() -> void:
	for i in names.size():
		var p := parent[i]
		var local := Transform3D(Basis(rot[i]), rest_off[i] + off[i])
		glob[i] = glob[p] * local if p >= 0 else local


## FK for a pre-computed list of bone indices (in parent-first order).
func fk_list(list: PackedInt32Array) -> void:
	for i in list:
		var p := parent[i]
		var local := Transform3D(Basis(rot[i]), rest_off[i] + off[i])
		glob[i] = glob[p] * local if p >= 0 else local


## All descendants of `root_bone` including itself, parent-first.
func subtree(root_bone: int) -> PackedInt32Array:
	var out := PackedInt32Array([root_bone])
	for i in range(root_bone + 1, names.size()):
		if out.has(parent[i]):
			out.append(i)
	return out


## Sets the bone's local rotation so that its skeleton-space basis becomes `b`
## (call after the parent's global is up to date).
func set_global_basis(i: int, b: Basis) -> void:
	var p := parent[i]
	if p >= 0:
		rot[i] = (glob[p].basis.transposed() * b).get_rotation_quaternion()
	else:
		rot[i] = b.get_rotation_quaternion()


## Rest direction from bone `i` to the rest position of bone `j` (normalized).
func rest_dir(i: int, j: int) -> Vector3:
	return (rest_pos[j] - rest_pos[i]).normalized()


## Builds a flat Skeleton3D (every bone a root) and the matching Skin.
func build_skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = &"Skeleton3D"
	for i in names.size():
		sk.add_bone(names[i])
		var t := Transform3D(Basis.IDENTITY, rest_pos[i])
		sk.set_bone_rest(i, t)
		sk.set_bone_pose(i, t)
	return sk


func build_skin() -> Skin:
	var skin := Skin.new()
	for i in names.size():
		skin.add_bind(i, Transform3D(Basis.IDENTITY, -rest_pos[i]))
	return skin


## Pushes the solved pose to a flat skeleton built by build_skeleton().
func push(sk: Skeleton3D) -> void:
	for i in names.size():
		if _scaled[i]:
			var g := glob[i]
			sk.set_bone_pose(i, Transform3D(g.basis * Basis.from_scale(scl[i]), g.origin))
		else:
			sk.set_bone_pose(i, glob[i])


# --- Skin weights ---------------------------------------------------------------------

## Weights for a point lying along a bone chain: finds the closest chain segment and
## blends smoothly into the neighbouring bone near joints. `tip` is where the last bone
## ends. Returns [bone0, w0, bone1, w1].
func chain_weights(p: Vector3, chain: PackedInt32Array, tip: Vector3, blend: float = 0.3) -> PackedFloat32Array:
	var n := chain.size()
	if n == 1:
		return PackedFloat32Array([chain[0], 1.0, chain[0], 0.0])
	var best_k := 0
	var best_t := 0.0
	var best_d := INF
	for k in n:
		var a := rest_pos[chain[k]]
		var b := rest_pos[chain[k + 1]] if k + 1 < n else tip
		var ab := b - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 1e-8 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var d := p.distance_squared_to(a + ab * t)
		if d < best_d - 1e-9:
			best_d = d
			best_k = k
			best_t = t
	var h := blend * 0.5
	if best_t < h and best_k > 0:
		var w := 0.5 + 0.5 * smoothstep(0.0, 1.0, best_t / h)
		return PackedFloat32Array([chain[best_k], w, chain[best_k - 1], 1.0 - w])
	if best_t > 1.0 - h and best_k + 1 < n:
		var w := 0.5 + 0.5 * smoothstep(0.0, 1.0, (1.0 - best_t) / h)
		return PackedFloat32Array([chain[best_k], w, chain[best_k + 1], 1.0 - w])
	return PackedFloat32Array([chain[best_k], 1.0, chain[best_k], 0.0])


## Returns a weighting Callable(p: Vector3) -> PackedFloat32Array for MeshKit.
func chain_weighter(chain_names: Array, tip: Vector3, blend: float = 0.3) -> Callable:
	var chain := PackedInt32Array()
	for n: StringName in chain_names:
		var i := idx(n)
		assert(i >= 0, "chain_weighter: unknown bone %s" % n)
		chain.append(i)
	return func(p: Vector3) -> PackedFloat32Array: return chain_weights(p, chain, tip, blend)


## Weighting Callable that binds everything rigidly to one bone.
func rigid_weighter(bone_name: StringName) -> Callable:
	var i := idx(bone_name)
	assert(i >= 0, "rigid_weighter: unknown bone %s" % bone_name)
	var w := PackedFloat32Array([i, 1.0, i, 0.0])
	return func(_p: Vector3) -> PackedFloat32Array: return w


## Weighting Callable over arbitrary bone segments: `segments` = [[bone_name, a, b], ...]
## (skeleton-space endpoints). Inverse-distance weights (power `pw`), best `count` bones.
## Used for membranes and other surfaces spanning several chains.
func segment_weighter(segments: Array, pw: float = 4.0, count: int = 3) -> Callable:
	var bones := PackedInt32Array()
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	for sg: Array in segments:
		var i := idx(sg[0])
		assert(i >= 0, "segment_weighter: unknown bone %s" % sg[0])
		bones.append(i)
		a.append(sg[1])
		b.append(sg[2])
	return func(p: Vector3) -> PackedFloat32Array:
		var ws := PackedFloat32Array()
		ws.resize(bones.size())
		for k in bones.size():
			var ab := b[k] - a[k]
			var l2 := ab.length_squared()
			var t := 0.0 if l2 < 1e-8 else clampf((p - a[k]).dot(ab) / l2, 0.0, 1.0)
			var d := p.distance_to(a[k] + ab * t)
			ws[k] = 1.0 / pow(d + 0.05, pw)
		var out := PackedFloat32Array()
		var used := PackedByteArray()
		used.resize(bones.size())
		for n in mini(count, bones.size()):
			var best := -1
			for k in bones.size():
				if used[k] == 0 and (best < 0 or ws[k] > ws[best]):
					best = k
			used[best] = 1
			out.append(bones[best])
			out.append(ws[best])
		return out
