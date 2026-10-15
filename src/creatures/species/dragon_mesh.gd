extends RefCounted
## Geometry and materials of the dragon (see dragon.gd for the rig and animation).

const D := preload("res://src/creatures/species/dragon.gd")

## Body radii (half width, half height) at spine joints (k = 1), interpolated.
const BODY_R := [[0, 0.85, 0.8], [2, 0.93, 0.86], [4, 0.96, 0.88], [6, 0.9, 0.84], [8, 0.84, 0.78],
		[10, 0.76, 0.71], [12, 0.62, 0.58], [14, 0.5, 0.47], [17, 0.38, 0.36], [20, 0.27, 0.26],
		[23, 0.17, 0.16], [26, 0.07, 0.07]]


static func _body_r(i: float) -> Vector2:
	for n in range(1, BODY_R.size()):
		if i <= float(BODY_R[n][0]):
			var a: Array = BODY_R[n - 1]
			var b: Array = BODY_R[n]
			var t := (i - float(a[0])) / (float(b[0]) - float(a[0]))
			return Vector2(lerpf(a[1], b[1], t), lerpf(a[2], b[2], t))
	return Vector2(0.07, 0.07)


static func build(sp: CreatureSpecies, rig: CreatureRig, kit: MeshKit) -> void:
	var k := sp.k
	var s := rig.skel
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z) * k
	var scale_c := sp.color("scales", D.SCALE)
	# --- Neck + body + tail: one continuous loft, head base -> tail tip.
	kit.surface(&"scales")
	var secs: Array = []
	var neck_r := [0.5, 0.55, 0.61, 0.68, 0.76]
	for i in range(4, -1, -1):
		var p := s.rest_pos[s.idx(StringName("neck_%d" % i))]
		secs.append({"p": p, "w": neck_r[i] * k, "h": neck_r[i] * 0.95 * k, "hb": neck_r[i] * k})
	for i in D.SPINE + 1:
		var r := _body_r(i)
		var p := Vector3(0, float(D.HEIGHTS[i]), i * D.SEG) * k
		secs.append({"p": p, "w": r.x * k, "h": r.y * k, "hb": r.y * 1.05 * k})
	var head_p := s.rest_pos[s.idx(&"head")]
	secs.push_front({"p": head_p + v.call(0, 0.02, 0.1), "w": 0.47 * k, "h": 0.45 * k})
	var neck_chain := PackedInt32Array()
	for i in 5:
		neck_chain.append(s.idx(StringName("neck_%d" % i)))
	var spine_chain := PackedInt32Array()
	for i in D.SPINE:
		spine_chain.append(s.idx(StringName("spine_%d" % i)))
	var tail_tip := Vector3(0, float(D.HEIGHTS[D.SPINE]), D.SPINE * D.SEG) * k
	var weigh := func(p: Vector3) -> PackedFloat32Array:
		if p.z < -0.35 * k:
			return s.chain_weights(p, neck_chain, head_p, 0.45)
		if p.z > 0.35 * k:
			return s.chain_weights(p, spine_chain, tail_tip, 0.45)
		var t := (p.z + 0.35 * k) / (0.7 * k)
		return PackedFloat32Array([neck_chain[0], 1.0 - t, spine_chain[0], t])
	kit.loft(secs, {"segs": 26, "sub": 2, "color": scale_c, "cap0": "round", "cap_len": 0.5, "cap1": "point", "weights": weigh,
			"mark_row": 1, "fur": 0.0})
	# --- Head.
	var hw := s.rigid_weighter(&"head")
	var head := [
		{"p": v.call(0, 3.72, -3.92), "w": 0.5 * k, "h": 0.46 * k},
		{"p": v.call(0, 3.76, -4.26), "w": 0.6 * k, "h": 0.5 * k, "hb": 0.42 * k},
		{"p": v.call(0, 3.69, -4.7), "w": 0.47 * k, "h": 0.36 * k, "hb": 0.33 * k},
		{"p": v.call(0, 3.62, -5.15), "w": 0.36 * k, "h": 0.27 * k, "hb": 0.25 * k},
		{"p": v.call(0, 3.6, -5.55), "w": 0.33 * k, "h": 0.25 * k, "hb": 0.22 * k},
		{"p": v.call(0, 3.59, -5.8), "w": 0.27 * k, "h": 0.21 * k, "hb": 0.18 * k},
	]
	kit.loft(head, {"segs": 26, "sub": 3, "color": scale_c, "cap0": "round", "cap1": "round", "cap_len": 0.6,
			"weights": hw, "mark_row": 2, "fur": 0.0})
	var jaw := [
		{"p": v.call(0, 3.44, -4.25), "w": 0.44 * k, "h": 0.1 * k, "hb": 0.2 * k},
		{"p": v.call(0, 3.39, -4.95), "w": 0.33 * k, "h": 0.08 * k, "hb": 0.15 * k},
		{"p": v.call(0, 3.38, -5.62), "w": 0.23 * k, "h": 0.06 * k, "hb": 0.1 * k},
	]
	kit.loft(jaw, {"segs": 18, "sub": 2, "color": scale_c, "weights": s.rigid_weighter(&"jaw"), "mark_row": 3, "fur": 0.0, "cap_len": 0.7})
	# Brow ridges and nostril bumps.
	for side in [-1.0, 1.0]:
		kit.ellipsoid(v.call(0.37 * side, 3.97, -4.64), Vector3(0.15, 0.07, 0.3) * k, {"color": scale_c, "weights": hw,
				"rings": 8, "segs": 12, "fur": 0.0}, Basis.from_euler(Vector3(-0.2, 0.3 * side, -0.45 * side)))
		kit.ellipsoid(v.call(0.14 * side, 3.78, -5.6), Vector3(0.1, 0.07, 0.13) * k, {"color": scale_c, "weights": hw,
				"rings": 7, "segs": 10, "fur": 0.0})
	kit.surface(&"mouth")
	for side in [-1.0, 1.0]:
		kit.ellipsoid(v.call(0.15 * side, 3.84, -5.66), Vector3(0.05, 0.03, 0.06) * k, {"weights": hw, "rings": 6, "segs": 8, "fur": 0.0})
	kit.ellipsoid(v.call(0, 3.47, -4.9), Vector3(0.3, 0.07, 0.75) * k, {"weights": hw, "rings": 8, "segs": 12, "fur": 0.0})
	# Teeth.
	kit.surface(&"claw")
	var up_t := PackedVector3Array()
	var lo_t := PackedVector3Array()
	for i in 6:
		var t := float(i) / 5.0
		for side in [-1.0, 1.0]:
			up_t.append(v.call(side * lerpf(0.3, 0.16, t), 3.42, lerpf(-4.6, -5.6, t)))
			lo_t.append(v.call(side * lerpf(0.26, 0.14, t), 3.46, lerpf(-4.7, -5.5, t)))
	CreatureParts.teeth(kit, rig, &"head", up_t, Vector3.DOWN, 0.12 * k, 0.03 * k)
	CreatureParts.teeth(kit, rig, &"jaw", lo_t, Vector3.UP, 0.09 * k, 0.025 * k)
	# Horns sweeping back from the skull.
	kit.surface(&"horn")
	for side in [-1.0, 1.0]:
		CreatureParts.horn(kit, rig, &"head", PackedVector3Array([v.call(0.27 * side, 4.02, -4.18), v.call(0.37 * side, 4.3, -3.8),
				v.call(0.45 * side, 4.47, -3.25), v.call(0.5 * side, 4.52, -2.6)]), 0.12 * k, {"sub": 4})
		CreatureParts.horn(kit, rig, &"head", PackedVector3Array([v.call(0.42 * side, 3.82, -4.2), v.call(0.62 * side, 3.85, -3.95),
				v.call(0.74 * side, 3.82, -3.65)]), 0.06 * k, {"sub": 3})
	# Whiskers (spring chains) and beard: gold hair, flowing.
	kit.surface(&"mane")
	var mane_c := sp.color("mane", D.MANE)
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		var names: Array = []
		var wsecs: Array = []
		var radii := [0.032, 0.026, 0.02, 0.014, 0.004]
		for i in 5:
			var p: Vector3
			if i < 4:
				var n := StringName("whisker%d_%s" % [i, sx])
				names.append(n)
				p = s.rest_pos[s.idx(n)]
			else:
				p = v.call(1.6 * side, 2.7, -3.3)
			wsecs.append({"p": p, "w": radii[i] * k, "h": radii[i] * k, "c": Color(mane_c.r, mane_c.g, mane_c.b, float(i) / 4.0 * 0.4)})
		kit.loft(wsecs, {"segs": 6, "sub": 3, "cap0": "round", "cap1": "point",
				"weights": s.chain_weighter(names, v.call(1.6 * side, 2.7, -3.3), 0.5)})
	for i in 3:
		var f := float(i) - 1.0
		var base: Vector3 = v.call(f * 0.12, 3.28, -5.1 + absf(f) * 0.25)
		_lock(kit, s, &"jaw", base, (Vector3(f * 0.25, -0.75, 0.65)).normalized(), (0.75 - absf(f) * 0.2) * k, 0.11 * k, mane_c, 0.5)
	# --- Mane: flame-like locks down the neck and around the head (they flutter).
	var n_locks := 22
	for i in n_locks:
		var t := float(i) / (n_locks - 1)
		var z := lerpf(-4.1, 1.1, t) * k
		var base := _top_line(s, z, k) + Vector3(0, -0.07 * k, 0)
		var bone := _nearest_bone(s, base, ["head", "neck_4", "neck_3", "neck_2", "neck_1", "neck_0", "spine_0", "spine_1"])
		var wob := sin(i * 2.7) * 0.5 + 0.5
		var ln := lerpf(1.55, 0.75, t) * (0.8 + 0.3 * wob) * k
		for side in [-1.0, 1.0]:
			var d := Vector3(side * (0.28 + 0.18 * wob), 0.42 + 0.2 * (1.0 - t), 1.0).normalized()
			_lock(kit, s, bone, base + Vector3(side * 0.08 * k, 0, 0.05 * k * side), d, ln, (0.1 + 0.03 * wob) * k, mane_c,
					0.5 + 0.3 * wob)
		if i % 2 == 0:
			_lock(kit, s, bone, base + Vector3(0, 0.04 * k, 0), Vector3(0, 0.55, 1.0).normalized(), ln * 0.9, 0.1 * k, mane_c, 0.45)
	# Cheek tufts and tail-tip tuft.
	for side in [-1.0, 1.0]:
		for i in 3:
			var base: Vector3 = v.call(0.42 * side, 3.55 - i * 0.1, -4.25 + i * 0.12)
			_lock(kit, s, &"head", base, Vector3(0.5 * side, -0.25 - i * 0.15, 1.0).normalized(), (0.75 - i * 0.12) * k, 0.1 * k, mane_c)
	var tb := StringName("spine_%d" % (D.SPINE - 1))
	for i in 4:
		var a := float(i) / 4.0 * TAU + 0.6
		var base := tail_tip + Vector3(cos(a) * 0.04, sin(a) * 0.04, -0.25) * k
		_lock(kit, s, tb, base, Vector3(cos(a) * 0.22, sin(a) * 0.22 + 0.1, 1.0).normalized(), (1.1 - 0.15 * (i % 2)) * k, 0.13 * k, mane_c, 0.3)
	# Dorsal spikes along the back and tail.
	kit.surface(&"horn")
	for i in range(1, D.SPINE - 1):
		var r := _body_r(i)
		var base := Vector3(0, float(D.HEIGHTS[i]) * k + r.y * k * 0.92, (i * D.SEG + 0.1) * k)
		var hgt := r.y * 0.42 * k + 0.05 * k
		var bn := StringName("spine_%d" % i)
		kit.tube(PackedVector3Array([base, base + Vector3(0, hgt * 0.6, 0.12 * k), base + Vector3(0, hgt, 0.3 * k)]),
				PackedFloat32Array([0.11 * k * (0.5 + r.x), 0.06 * k * (0.5 + r.x), 0.0]),
				{"weights": s.rigid_weighter(bn), "segs": 6, "sub": 2, "fur": 0.0, "flatten": 0.65, "up": Vector3.RIGHT})
	# --- Legs with scaly sleeves, elbow tufts and big claws.
	kit.surface(&"scales")
	for l in rig.legs:
		var front := l.group == CreatureLeg.Group.FRONT
		CreatureParts.limb(kit, rig, l, [Vector2(0.4, 0.44) * k, Vector2(0.44, 0.46) * k, Vector2(0.3, 0.31) * k,
				Vector2(0.21, 0.21) * k, Vector2(0.19, 0.15) * k], v.call(0, 0.1, 0.0),
				{"segs": 16, "sub": 3, "color": scale_c, "cap0": "none", "inset": 0.4, "mark_row": 4, "fur": 0.0})
		CreatureParts.paw(kit, rig, l, Vector3(0.24, 0.12, 0.3) * k, 4, 0.26 * k, {"color": scale_c, "segs": 14, "rings": 8, "fur": 0.0},
				&"claw", &"scales")
		kit.surface(&"mane")
		var elbow := s.rest_pos[l.lower]
		var back := Vector3(l.side * 0.3, -0.2, 1.0 if front else -0.2).normalized()
		for i in 3:
			_lock(kit, s, s.names[l.lower], elbow + Vector3(0, -0.05 * i, 0.05 * i) * k, (back + Vector3(0, -0.15 * i, 0)).normalized(),
					(0.55 - 0.1 * i) * k, 0.09 * k, mane_c)
		kit.surface(&"scales")
	# --- Eyes.
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		CreatureParts.eye(kit, rig, StringName("eye_" + sx), StringName("lid_" + sx), 0.1 * k,
				Vector3(0.7 * side, 0.1, -1.0).normalized(), &"scales", &"eye", Vector3(1.2, 0.85, 1.0), {"color": scale_c})
	# --- Wings.
	for w: DragonWings in sp.wings:
		_wing(kit, rig, w, k, sp)


## Point on the dorsal line of the neck/body at rest (for mane placement).
static func _top_line(s: RigSkeleton, z: float, k: float) -> Vector3:
	var pts: Array[Vector3] = []
	pts.append(s.rest_pos[s.idx(&"head")] + Vector3(0, 0.45 * k, 0.1 * k))
	var neck_r := [0.5, 0.55, 0.61, 0.68, 0.76]
	for i in range(4, -1, -1):
		pts.append(s.rest_pos[s.idx(StringName("neck_%d" % i))] + Vector3(0, neck_r[i] * 0.95 * k, 0))
	for i in 3:
		var r := _body_r(i)
		pts.append(Vector3(0, (float(D.HEIGHTS[i]) + r.y) * k, i * D.SEG * k))
	for i in range(1, pts.size()):
		if z <= pts[i].z:
			var t := (z - pts[i - 1].z) / maxf(pts[i].z - pts[i - 1].z, 1e-4)
			return pts[i - 1].lerp(pts[i], clampf(t, 0.0, 1.0))
	return pts[pts.size() - 1]


static func _nearest_bone(s: RigSkeleton, p: Vector3, names: Array) -> StringName:
	var best: StringName = names[0]
	var bd := INF
	for n: String in names:
		var d := s.rest_pos[s.idx(StringName(n))].distance_to(p)
		if d < bd:
			bd = d
			best = StringName(n)
	return best


## One flame-shaped lock of hair (flattened tapered tube, flutter weight in alpha).
static func _lock(kit: MeshKit, s: RigSkeleton, bone: StringName, base: Vector3, dir: Vector3, length: float, width: float,
		c: Color, curl: float = 0.25) -> void:
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 1e-4:
		side = Vector3.RIGHT
	var bend := (Vector3(0, -1.0, 0) * 0.7 + Vector3(0, 0, 1.0) * 0.3) * curl * length
	var root := c.darkened(0.22)
	var tip := c.lightened(0.25)
	var secs := [
		{"p": base, "w": width * 0.75, "h": width * 0.3, "c": Color(root.r, root.g, root.b, 0.0)},
		{"p": base + dir * length * 0.3 + bend * 0.08, "w": width, "h": width * 0.32, "c": Color(c.r, c.g, c.b, 0.3)},
		{"p": base + dir * length * 0.65 + bend * 0.4, "w": width * 0.62, "h": width * 0.24, "c": Color(c.r, c.g, c.b, 0.7)},
		{"p": base + dir * length + bend, "w": width * 0.06, "h": width * 0.04, "c": Color(tip.r, tip.g, tip.b, 1.0)},
	]
	for sec: Dictionary in secs:
		sec["up"] = side.cross(dir).normalized()
	kit.loft(secs, {"segs": 8, "sub": 2, "weights": s.rigid_weighter(bone), "cap0": "round", "cap1": "point"})


static func _wing(kit: MeshKit, rig: CreatureRig, w: DragonWings, k: float, sp: CreatureSpecies) -> void:
	var s := rig.skel
	var sx := "l" if w.side < 0.0 else "r"
	var nm := func(n: String) -> StringName: return StringName(n + "_" + sx)
	# Bone struts (arm, forearm, fingers) and the thumb claw.
	kit.surface(&"wingbone")
	var wc := sp.color("scales", D.SCALE).darkened(0.12)
	kit.tube(PackedVector3Array([w.p_shoulder, w.p_shoulder.lerp(w.p_elbow, 0.5), w.p_elbow]),
			PackedFloat32Array([0.2 * k, 0.15 * k, 0.15 * k]),
			{"weights": s.chain_weighter([nm.call("wing_arm"), nm.call("wing_fore")], w.p_wrist, 0.25), "segs": 10, "sub": 2,
			"color": wc, "cap0": "round", "fur": 0.0})
	kit.tube(PackedVector3Array([w.p_elbow, w.p_elbow.lerp(w.p_wrist, 0.5), w.p_wrist]),
			PackedFloat32Array([0.15 * k, 0.11 * k, 0.1 * k]),
			{"weights": s.chain_weighter([nm.call("wing_fore")], w.p_wrist, 0.25), "segs": 10, "sub": 2, "color": wc, "fur": 0.0})
	for f in DragonWings.FINGERS:
		var a: StringName = nm.call("wing_f%da" % (f + 1))
		var b: StringName = nm.call("wing_f%db" % (f + 1))
		kit.tube(PackedVector3Array([w.p_wrist, w.p_knuckle[f], w.p_tip[f]]),
				PackedFloat32Array([0.085 * k, 0.06 * k, 0.012 * k]),
				{"weights": s.chain_weighter([a, b], w.p_tip[f], 0.25), "segs": 8, "sub": 3, "color": wc, "fur": 0.0})
	kit.surface(&"claw")
	var thumb := w.p_wrist + Vector3(0, 0.05, -0.12) * k
	kit.tube(PackedVector3Array([thumb, thumb + Vector3(0.1 * w.side, 0.08, -0.25) * k, thumb + Vector3(0.12 * w.side, -0.05, -0.42) * k]),
			PackedFloat32Array([0.07 * k, 0.045 * k, 0.0]), {"weights": s.rigid_weighter(nm.call("wing_hand")), "segs": 6, "sub": 2, "fur": 0.0})
	# Membrane panels (Coons patches between the struts, scalloped trailing edges).
	kit.surface(&"membrane")
	var segs: Array = [
		[nm.call("wing_arm"), w.p_shoulder, w.p_elbow], [nm.call("wing_fore"), w.p_elbow, w.p_wrist],
	]
	for f in DragonWings.FINGERS:
		segs.append([nm.call("wing_f%da" % (f + 1)), w.p_wrist, w.p_knuckle[f]])
		segs.append([nm.call("wing_f%db" % (f + 1)), w.p_knuckle[f], w.p_tip[f]])
	for i in range(1, 10):
		var a := Vector3(0.6 * w.side, float(D.HEIGHTS[i]), i * D.SEG) * k
		var b := Vector3(0.6 * w.side, float(D.HEIGHTS[i + 1]), (i + 1) * D.SEG) * k
		segs.append([StringName("spine_%d" % i), a, b])
	var weigh := s.segment_weighter(segs, 4.0, 3)
	var drop := Vector3(0, -0.06, 0) * k
	var body_attach := Vector3(0.62 * w.side, float(D.HEIGHTS[9]) + 0.28, 9 * D.SEG) * k
	var mc := sp.color("membrane", D.MEMBRANE)
	var res := kit.res
	var cols := maxi(5, int(round(10 * res)))
	var rows := maxi(4, int(round(7 * res)))
	var lead := func(u: float) -> Vector3:
		var l1 := w.p_shoulder.distance_to(w.p_elbow)
		var l2 := w.p_elbow.distance_to(w.p_wrist)
		var d := u * (l1 + l2)
		return (w.p_shoulder.lerp(w.p_elbow, d / l1) if d <= l1 else w.p_elbow.lerp(w.p_wrist, (d - l1) / l2)) + drop
	var finger := func(f: int, t: float) -> Vector3:
		var a := w.p_wrist
		var b: Vector3 = w.p_knuckle[f]
		var c: Vector3 = w.p_tip[f]
		var l1 := a.distance_to(b)
		var l2 := b.distance_to(c)
		var d := t * (l1 + l2)
		return (a.lerp(b, d / l1) if d <= l1 else b.lerp(c, (d - l1) / l2)) + drop
	# Inner panel: body flank -> finger 3.
	var root_edge := func(t: float) -> Vector3: return (w.p_shoulder + drop).lerp(body_attach, t)
	var f3 := func(t: float) -> Vector3: return finger.call(2, t)
	var trail_in := func(u: float) -> Vector3:
		var a: Vector3 = body_attach
		var b: Vector3 = w.p_tip[2] + drop
		var mid := a.lerp(b, u)
		var inward := (w.p_wrist - mid).normalized()
		return mid + inward * a.distance_to(b) * 0.12 * sin(PI * u)
	kit.sheet(_coons(lead, trail_in, root_edge, f3, cols, rows), 0.035 * k, {"weights": weigh, "color": mc, "color_edge": mc.darkened(0.15)})
	# Between fingers 3 -> 2 and 2 -> 1.
	for pair in [[2, 1], [1, 0]]:
		var fa: int = pair[0]
		var fb: int = pair[1]
		var c0 := func(t: float) -> Vector3: return finger.call(fa, t)
		var c1 := func(t: float) -> Vector3: return finger.call(fb, t)
		var wrist := func(_u: float) -> Vector3: return w.p_wrist + drop
		var ta: Vector3 = w.p_tip[fa] + drop
		var tb: Vector3 = w.p_tip[fb] + drop
		var trail := func(u: float) -> Vector3:
			var mid := ta.lerp(tb, u)
			return mid + (w.p_wrist - mid).normalized() * ta.distance_to(tb) * 0.16 * sin(PI * u)
		kit.sheet(_coons(wrist, trail, c0, c1, maxi(4, int(round(6 * res))), rows), 0.03 * k,
				{"weights": weigh, "color": mc, "color_edge": mc.darkened(0.15)})


## Coons patch grid: rows along v (0 = `top(u)`, 1 = `bottom(u)`), columns along u
## (0 = `left(v)`, 1 = `right(v)`).
static func _coons(top: Callable, bottom: Callable, left: Callable, right: Callable, cols: int, rows: int) -> Array:
	var p00: Vector3 = top.call(0.0)
	var p10: Vector3 = top.call(1.0)
	var p01: Vector3 = bottom.call(0.0)
	var p11: Vector3 = bottom.call(1.0)
	var grid: Array = []
	for r in rows:
		var vv := float(r) / (rows - 1)
		var row := PackedVector3Array()
		for c in cols:
			var u := float(c) / (cols - 1)
			var p: Vector3 = (1.0 - vv) * top.call(u) + vv * bottom.call(u) + (1.0 - u) * left.call(vv) + u * right.call(vv) \
					- ((1.0 - u) * (1.0 - vv) * p00 + u * (1.0 - vv) * p10 + (1.0 - u) * vv * p01 + u * vv * p11)
			row.append(p)
		grid.append(row)
	return grid


static func material(sp: CreatureSpecies, surface: StringName, _detail: int) -> Material:
	var scale_c := sp.color("scales", D.SCALE)
	match surface:
		&"scales":
			return CreatureMaterials.skin("dragon/scales", scale_c, {
				"shade_tint": Color(0.55, 0.38, 0.62), "rim": 0.5, "rim_color": Color(1.0, 0.85, 0.6),
				"pattern": CreatureMaterials.Pattern.SCALES, "pattern_scale": 5.5, "pattern_strength": 0.28,
				"specular": 0.04, "specular_size": 0.08, "marks": _marks(), "mark_rows": 5,
				"mark_colors": [scale_c.darkened(0.35), sp.color("belly", D.BELLY), sp.color("belly", D.BELLY)],
				"plate_spacing": 0.3 * sp.k, "plate_line": Color(0.62, 0.36, 0.1), "outline_width": 1.3, "belly_shade": 0.05})
		&"wingbone":
			return CreatureMaterials.skin("dragon/wingbone", Color.WHITE, {"shade_tint": Color(0.55, 0.38, 0.62), "rim": 0.4,
				"pattern": CreatureMaterials.Pattern.SCALES, "pattern_scale": 7.0, "pattern_strength": 0.2, "outline_width": 1.1})
		&"membrane":
			return CreatureMaterials.membrane("dragon/membrane", Color.WHITE, {"translucency": 0.9,
				"translucency_color": Color(1.0, 0.45, 0.15), "vein_color": Color(0.42, 0.06, 0.04), "rim": 0.25,
				"shade_tint": Color(0.6, 0.4, 0.55)})
		&"mane":
			return CreatureMaterials.skin("dragon/mane", Color.WHITE, {"shade_tint": Color(0.75, 0.5, 0.5), "rim": 0.6,
				"pattern": CreatureMaterials.Pattern.FUR, "pattern_scale": 24.0, "pattern_strength": 0.25, "specular": 0.0,
				"flutter": 0.06 * sp.k, "flutter_freq": 2.4, "outline_width": 0.9, "belly_shade": 0.0})
		&"horn":
			return CreatureMaterials.hard("dragon/horn", sp.color("horn", D.HORN), {"pattern": CreatureMaterials.Pattern.SMOOTH,
				"pattern_scale": 8.0, "pattern_strength": 0.12, "outline_width": 1.0})
		&"claw":
			return CreatureMaterials.hard("dragon/claw", Color(0.93, 0.88, 0.76), {"outline_width": 0.8})
		&"mouth":
			return CreatureMaterials.hard("dragon/mouth", Color(0.35, 0.05, 0.06), {"outline": false})
		&"eye":
			return CreatureMaterials.eye("dragon/eye", {"iris": Color(1.0, 0.62, 0.08), "iris_inner": Color(1.0, 0.9, 0.35),
				"sclera": Color(0.98, 0.78, 0.3), "iris_size": 0.95, "pupil_size": 0.55, "pupil_slit": 0.2, "glow": 2.5})
	return CreatureMaterials.skin("dragon/default", scale_c)


static var _mark_tex: ImageTexture = null


static func _marks() -> ImageTexture:
	if _mark_tex == null:
		_mark_tex = CreatureMaterials.mark_texture([
			{},
			# Neck + body + tail (head base -> tail tip): gold belly plates, dark dorsal ridge.
			{"ventral": [[0.0, 0.1], [0.12, 0.16], [0.2, 0.19], [0.5, 0.18], [0.75, 0.15], [1.0, 0.1]],
			"dorsal": [[0.0, 0.03], [1.0, 0.04]]},
			# Head: pale throat.
			{"ventral": [[0.0, 0.14], [0.6, 0.12], [1.0, 0.0]]},
			# Jaw: gold underside.
			{"ventral": [[0.0, 0.2], [1.0, 0.16]]},
			# Legs: gold inner side.
			{"ventral": [[0.0, 0.0], [0.3, 0.1], [1.0, 0.08]]},
		])
	return _mark_tex
