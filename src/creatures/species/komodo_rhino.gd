extends CreatureSpecies
## Komodo rhino (Fire Nation): a ~4 m armored monitor lizard with a rhino horn,
## bony back plates, sprawled legs and a heavy whipping tail. Lizard walk with lateral
## spine undulation and a scrambling run. Fire Nation cavalry mount (saddle sockets).

const HIDE := Color(0.47, 0.44, 0.4)
const PLATES := Color(0.3, 0.28, 0.27)
const BELLY := Color(0.72, 0.64, 0.52)
const HORN := Color(0.9, 0.85, 0.72)


func id() -> StringName:
	return &"komodo_rhino"


func draw_distance() -> float:
	return 300.0


func _init() -> void:
	tune["neck_down"] = -0.4
	tune["head_up"] = 0.4
	tune["rear_pitch"] = 0.4
	tune["bite_reach"] = 0.6
	tune["shake_roll"] = 0.1


func build(rig: CreatureRig) -> void:
	var s := rig.skel
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z) * k
	s.add(&"root", &"", Vector3.ZERO)
	s.add(&"pelvis", &"root", v.call(0, 0.95, 0.9))
	s.add(&"spine1", &"pelvis", v.call(0, 1.02, 0.3))
	s.add(&"spine2", &"spine1", v.call(0, 1.05, -0.3))
	s.add(&"chest", &"spine2", v.call(0, 1.0, -0.8))
	s.add(&"neck", &"chest", v.call(0, 0.98, -1.25))
	s.add(&"head", &"neck", v.call(0, 0.98, -1.55))
	s.add(&"jaw", &"head", v.call(0, 0.86, -1.68))
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		s.add(StringName("eye_" + sx), &"head", v.call(0.2 * side, 1.08, -1.76))
		s.add(StringName("lid_" + sx), &"head", v.call(0.2 * side, 1.08, -1.76))
	var tail_pts := [v.call(0, 0.92, 1.4), v.call(0, 0.82, 1.9), v.call(0, 0.7, 2.35), v.call(0, 0.58, 2.75), v.call(0, 0.47, 3.1)]
	var prev := &"pelvis"
	for i in tail_pts.size():
		var n := StringName("tail%d" % (i + 1))
		s.add(n, prev, tail_pts[i])
		prev = n
	for row in [["fl", -0.8, &"chest", CreatureLeg.Group.FRONT], ["hl", 0.9, &"pelvis", CreatureLeg.Group.HIND]]:
		for side in [-1.0, 1.0]:
			var sx := "l" if side < 0.0 else "r"
			var pre: String = row[0]
			var z: float = row[1]
			var front: bool = row[3] == CreatureLeg.Group.FRONT
			s.add(StringName(pre + "_upper_" + sx), row[2], v.call(0.42 * side, 0.85, z))
			s.add(StringName(pre + "_lower_" + sx), StringName(pre + "_upper_" + sx), v.call(0.8 * side, 0.55, z + (0.12 if front else -0.12)))
			s.add(StringName(pre + "_foot_" + sx), StringName(pre + "_lower_" + sx), v.call(0.86 * side, 0.15, z - 0.08))
	for row in [["fl", CreatureLeg.Group.FRONT], ["hl", CreatureLeg.Group.HIND]]:
		for side in [-1.0, 1.0]:
			var sx := "l" if side < 0.0 else "r"
			var pre: String = row[0]
			var l := CreatureLeg.new()
			var fp := s.rest_pos[s.idx(StringName(pre + "_foot_" + sx))]
			l.setup(s, StringName(pre + "_" + sx), [StringName(pre + "_upper_" + sx), StringName(pre + "_lower_" + sx),
					StringName(pre + "_foot_" + sx)], Vector3(fp.x, 0.0, fp.z - 0.1 * k))
			l.group = row[1]
			var front: bool = l.group == CreatureLeg.Group.FRONT
			l.knee_dir = Vector3(0.7 * side, 0.3, 0.6 if front else -0.6).normalized()
			l.paw_size = 0.4 * k
			l.weight = 0.8
			l.curl = 0.4
			l.tuck = Vector3(0.3 * side, -0.5, 0.0) * k
			rig.legs.append(l)
	var m := rig.motor
	m.root = s.idx(&"root")
	m.pelvis = s.idx(&"pelvis")
	m.spine = PackedInt32Array([s.idx(&"spine1"), s.idx(&"spine2"), s.idx(&"chest")])
	m.neck = PackedInt32Array([s.idx(&"neck")])
	m.neck_weights = PackedFloat32Array([0.7])
	m.head = s.idx(&"head")
	m.jaw = s.idx(&"jaw")
	m.tail = PackedInt32Array()
	for i in 5:
		m.tail.append(s.idx(StringName("tail%d" % (i + 1))))
	m.eye_l = s.idx(&"eye_l")
	m.eye_r = s.idx(&"eye_r")
	m.lid_l = s.idx(&"lid_l")
	m.lid_r = s.idx(&"lid_r")
	m.hind_z = 0.9 * k
	m.front_z = -0.8 * k
	m.head_stab = 0.5
	m.lid_open = 0.75
	m.jaw_open = 0.6
	var ts := SpringChain.new().setup(s, m.tail, v.call(0, 0.4, 3.45))
	ts.stiffness = 30.0
	ts.damping = 6.0
	ts.falloff = 0.9
	m.springs.append(ts)
	rig.gaits.append(GaitEngine.make_gait({"name": &"walk", "max_speed": 2.5 * sqrt(k), "duty": 0.68,
			"offsets": [0.0, 0.5, 0.5, 0.0], "freq": 0.95, "ref_speed": 1.5 * sqrt(k), "lift": 0.18 * k, "bob": 0.015,
			"bob_mult": 2.0, "roll": 0.05, "roll_phase": 0.25, "spine_yaw": 0.2, "spine_yaw_phase": 0.25, "head_bob": 0.0}))
	rig.gaits.append(GaitEngine.make_gait({"name": &"run", "duty": 0.45, "offsets": [0.0, 0.5, 0.5, 0.0], "freq": 1.8,
			"ref_speed": 7.0 * sqrt(k), "lift": 0.3 * k, "bob": 0.04, "bob_mult": 2.0, "roll": 0.06, "spine_yaw": 0.28,
			"spine_yaw_phase": 0.25}))
	rig.gait.tempo = sqrt(k)
	rig.breath_period = 3.5
	rig.add_socket(&"saddle", &"spine2", Transform3D(Basis.IDENTITY, v.call(0, 0.55, 0.1)))
	rig.add_socket(&"back", &"spine1", Transform3D(Basis.IDENTITY, v.call(0, 0.55, 0.0)))
	rig.add_socket(&"rider_left", &"spine2", Transform3D(Basis.IDENTITY, v.call(-0.6, 0.15, 0.1)))
	rig.add_socket(&"rider_right", &"spine2", Transform3D(Basis.IDENTITY, v.call(0.6, 0.15, 0.1)))
	rig.add_socket(&"head", &"head", Transform3D(Basis.IDENTITY, v.call(0, 0.15, -0.3)))
	rig.add_socket(&"mouth", &"jaw", Transform3D(Basis.IDENTITY, v.call(0, 0, -0.5)))
	rig.add_socket(&"chest", &"chest", Transform3D(Basis.IDENTITY, v.call(0, -0.3, -0.2)))
	rig.add_socket(&"tail", &"tail5", Transform3D.IDENTITY)
	rig.set_dimensions({
		"length": 4.4 * k, "height": 1.7 * k, "width": 1.9 * k, "saddle_height": 1.6 * k, "paw_size": 0.4 * k,
		"weight": 0.8, "can_fly": false, "walk_speed": 1.5 * sqrt(k), "run_speed": 7.0 * sqrt(k),
		"sprint_speed": 9.0 * sqrt(k), "fly_speed": 0.0, "collision_radius": 0.8 * k, "collision_height": 1.5 * k,
		"mass": 1800.0 * k * k * k,
	})


func build_mesh(rig: CreatureRig, kit: MeshKit) -> void:
	var s := rig.skel
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z) * k
	var hide := color("hide", HIDE)
	var hw := s.rigid_weighter(&"head")
	kit.surface(&"hide")
	# Neck -> body -> tail tip in one loft.
	var secs := [
		{"p": v.call(0, 1.0, -1.45), "w": 0.3 * k, "h": 0.24 * k},
		{"p": v.call(0, 1.0, -1.15), "w": 0.38 * k, "h": 0.3 * k, "hb": 0.32 * k},
		{"p": v.call(0, 1.02, -0.75), "w": 0.58 * k, "h": 0.38 * k, "hb": 0.42 * k},
		{"p": v.call(0, 1.05, -0.2), "w": 0.66 * k, "h": 0.4 * k, "hb": 0.45 * k},
		{"p": v.call(0, 1.02, 0.4), "w": 0.62 * k, "h": 0.38 * k, "hb": 0.42 * k},
		{"p": v.call(0, 0.96, 0.95), "w": 0.48 * k, "h": 0.32 * k, "hb": 0.34 * k},
		{"p": v.call(0, 0.9, 1.45), "w": 0.32 * k, "h": 0.25 * k},
		{"p": v.call(0, 0.8, 1.95), "w": 0.22 * k, "h": 0.18 * k},
		{"p": v.call(0, 0.68, 2.4), "w": 0.15 * k, "h": 0.13 * k},
		{"p": v.call(0, 0.56, 2.8), "w": 0.1 * k, "h": 0.09 * k},
		{"p": v.call(0, 0.45, 3.15), "w": 0.06 * k, "h": 0.055 * k},
		{"p": v.call(0, 0.4, 3.45), "w": 0.025 * k, "h": 0.025 * k},
	]
	var front := PackedInt32Array([s.idx(&"pelvis"), s.idx(&"spine1"), s.idx(&"spine2"), s.idx(&"chest"), s.idx(&"neck")])
	var tail := PackedInt32Array()
	for i in 5:
		tail.append(s.idx(StringName("tail%d" % (i + 1))))
	var head_p := s.rest_pos[s.idx(&"head")]
	var tip: Vector3 = v.call(0, 0.4, 3.45)
	var z0 := s.rest_pos[s.idx(&"pelvis")].z
	var z1 := s.rest_pos[tail[0]].z
	var body_w := func(p: Vector3) -> PackedFloat32Array:
		if p.z <= z0:
			return s.chain_weights(p, front, head_p, 0.4)
		if p.z >= z1:
			return s.chain_weights(p, tail, tip, 0.5)
		var t := smoothstep(z0, z1, p.z)
		return PackedFloat32Array([front[0], 1.0 - t, tail[0], t])
	kit.loft(secs, {"segs": 22, "sub": 2, "color": hide, "cap0": "round", "cap1": "point", "weights": body_w, "mark_row": 1})
	# Head: heavy wedge with a rhino horn.
	kit.loft([{"p": v.call(0, 1.0, -1.4), "w": 0.3 * k, "h": 0.25 * k},
			{"p": v.call(0, 1.04, -1.6), "w": 0.32 * k, "h": 0.24 * k, "hb": 0.2 * k},
			{"p": v.call(0, 1.0, -1.85), "w": 0.24 * k, "h": 0.17 * k, "hb": 0.15 * k},
			{"p": v.call(0, 0.95, -2.08), "w": 0.17 * k, "h": 0.12 * k, "hb": 0.1 * k}],
			{"segs": 18, "sub": 2, "color": hide, "cap0": "round", "cap1": "round", "cap_len": 0.6, "weights": hw, "mark_row": 2})
	kit.loft([{"p": v.call(0, 0.86, -1.62), "w": 0.26 * k, "h": 0.05 * k, "hb": 0.1 * k},
			{"p": v.call(0, 0.85, -2.0), "w": 0.14 * k, "h": 0.04 * k, "hb": 0.07 * k}],
			{"segs": 14, "sub": 1, "color": hide, "weights": s.rigid_weighter(&"jaw"), "mark_row": 3})
	for side in [-1.0, 1.0]:
		kit.ellipsoid(v.call(0.19 * side, 1.16, -1.74), Vector3(0.09, 0.05, 0.14) * k, {"color": hide, "weights": hw, "rings": 7, "segs": 10},
				Basis.from_euler(Vector3(0, 0.3 * side, -0.3 * side)))
	# Armor plates down the back and tail.
	kit.surface(&"plates")
	var plate_bones := [&"neck", &"chest", &"chest", &"spine2", &"spine2", &"spine1", &"spine1", &"pelvis", &"pelvis",
			&"tail1", &"tail1", &"tail2", &"tail2", &"tail3"]
	for i in 14:
		var t := float(i) / 13.0
		var z := lerpf(-1.1, 2.6, t)
		var y := 1.38 if z < 0.4 else lerpf(1.38, 0.78, (z - 0.4) / 2.2)
		var base: Vector3 = v.call(0, y, z)
		var sz := lerpf(0.2, 0.07, t) * k
		kit.tube(PackedVector3Array([base, base + Vector3(0, sz * 0.7, sz * 0.4), base + Vector3(0, sz, sz * 1.1)]),
				PackedFloat32Array([sz * 0.7, sz * 0.45, 0.0]), {"weights": s.rigid_weighter(plate_bones[i]), "segs": 6, "sub": 1,
				"flatten": 0.6, "up": Vector3.RIGHT})
	kit.surface(&"horn")
	CreatureParts.horn(kit, rig, &"head", PackedVector3Array([v.call(0, 1.06, -1.98), v.call(0, 1.24, -2.08), v.call(0, 1.42, -2.06),
			v.call(0, 1.55, -1.96)]), 0.11 * k, {"sub": 3})
	CreatureParts.horn(kit, rig, &"head", PackedVector3Array([v.call(0, 1.18, -1.72), v.call(0, 1.3, -1.74), v.call(0, 1.38, -1.68)]),
			0.06 * k, {"sub": 2})
	kit.surface(&"hide")
	for l in rig.legs:
		CreatureParts.limb(kit, rig, l, [Vector2(0.24, 0.24) * k, Vector2(0.24, 0.22) * k, Vector2(0.16, 0.15) * k, Vector2(0.12, 0.1) * k],
				v.call(0, 0.05, 0), {"segs": 12, "sub": 2, "color": hide, "cap0": "none", "inset": 0.4, "mark_row": 4})
		CreatureParts.paw(kit, rig, l, Vector3(0.16, 0.07, 0.2) * k, 4, 0.12 * k, {"color": hide, "segs": 12, "rings": 7}, &"horn", &"hide")
	kit.surface(&"mouth")
	kit.ellipsoid(v.call(0, 0.9, -1.8), Vector3(0.18, 0.05, 0.3) * k, {"weights": hw, "rings": 6, "segs": 10})
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		CreatureParts.eye(kit, rig, StringName("eye_" + sx), StringName("lid_" + sx), 0.045 * k, Vector3(0.8 * side, 0.1, -0.7).normalized(),
				&"hide", &"eye", Vector3(1.1, 0.9, 1.0), {"color": hide})
	kit.surface(&"hide")


func material_for(surface: StringName, _detail: int, _lod: int) -> Material:
	match surface:
		&"hide":
			return CreatureMaterials.skin("komodo_rhino/hide", Color.WHITE, {"shade_tint": Color(0.58, 0.5, 0.62), "rim": 0.35,
				"pattern": CreatureMaterials.Pattern.SCALES, "pattern_scale": 9.0, "pattern_strength": 0.3, "specular": 0.12,
				"marks": _marks(), "mark_rows": 5, "mark_colors": [PLATES, BELLY, PLATES], "plate_spacing": 0.16 * k,
				"plate_line": Color(0.5, 0.42, 0.32), "outline_width": 1.1})
		&"plates":
			return CreatureMaterials.hard("komodo_rhino/plates", PLATES, {"pattern": CreatureMaterials.Pattern.SMOOTH, "pattern_scale": 10.0,
				"pattern_strength": 0.2, "outline_width": 0.9})
		&"horn":
			return CreatureMaterials.hard("komodo_rhino/horn", HORN, {"outline_width": 1.0})
		&"mouth":
			return CreatureMaterials.hard("komodo_rhino/mouth", Color(0.45, 0.12, 0.12), {"outline": false})
		&"eye":
			return CreatureMaterials.eye("komodo_rhino/eye", {"iris": Color(0.85, 0.55, 0.1), "iris_inner": Color(1.0, 0.8, 0.3),
				"sclera": Color(0.7, 0.5, 0.2), "iris_size": 0.95, "pupil_size": 0.55, "pupil_slit": 0.3})
	return CreatureMaterials.skin("komodo_rhino/default", HIDE)


static var _mark_tex: ImageTexture = null


static func _marks() -> ImageTexture:
	if _mark_tex == null:
		_mark_tex = CreatureMaterials.mark_texture([
			{},
			{"dorsal": [[0.0, 0.08], [0.5, 0.12], [1.0, 0.1]], "ventral": [[0.0, 0.12], [0.3, 0.2], [0.6, 0.15], [1.0, 0.08]]},
			{"dorsal": [[0.0, 0.1], [1.0, 0.05]], "ventral": [[0.0, 0.15], [1.0, 0.1]]},
			{"ventral": [[0.0, 0.25], [1.0, 0.25]]},
			{"ventral": [[0.0, 0.08], [1.0, 0.12]]},
		])
	return _mark_tex


func idle_actions() -> Array[StringName]:
	return [&"look_around", &"sniff", &"yawn", &"growl", &"look_around"]


func sound_for(action: StringName, event: StringName) -> StringName:
	if event == &"vocal_start" and (action == &"growl" or action == &"roar"):
		return &"dog_growl"
	return &""
