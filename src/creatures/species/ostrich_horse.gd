extends CreatureSpecies
## Ostrich horse (Earth Kingdom roads): a ~2.7 m tall riding bird with a horse's head
## and ears, a dark feathered crest down its neck, a round feathered body with folded
## wing stubs, a plume tail and two powerful digitigrade bird legs. Walk and a fast
## run with a flight phase. Ridable: saddle / rider sockets.

const BODY := Color(0.84, 0.68, 0.46)
const MANE := Color(0.34, 0.23, 0.15)
const LEGS := Color(0.56, 0.56, 0.6)
const MUZZLE := Color(0.42, 0.32, 0.26)


func id() -> StringName:
	return &"ostrich_horse"


func draw_distance() -> float:
	return 260.0


func _init() -> void:
	tune["neck_down"] = -1.0
	tune["head_up"] = 0.5
	tune["shake_roll"] = 0.12
	tune["bite_reach"] = 0.5


func build(rig: CreatureRig) -> void:
	var s := rig.skel
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z) * k
	s.add(&"root", &"", Vector3.ZERO)
	s.add(&"pelvis", &"root", v.call(0, 1.5, 0.35))
	s.add(&"spine", &"pelvis", v.call(0, 1.56, -0.1))
	s.add(&"chest", &"spine", v.call(0, 1.5, -0.5))
	s.add(&"neck1", &"chest", v.call(0, 1.68, -0.74))
	s.add(&"neck2", &"neck1", v.call(0, 2.02, -0.92))
	s.add(&"neck3", &"neck2", v.call(0, 2.36, -1.02))
	s.add(&"head", &"neck3", v.call(0, 2.6, -1.06))
	s.add(&"jaw", &"head", v.call(0, 2.5, -1.22))
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		s.add(StringName("ear_" + sx), &"head", v.call(0.075 * side, 2.76, -1.08))
		s.add(StringName("eye_" + sx), &"head", v.call(0.1 * side, 2.68, -1.27))
		s.add(StringName("lid_" + sx), &"head", v.call(0.1 * side, 2.68, -1.27))
	s.add(&"tail1", &"pelvis", v.call(0, 1.62, 0.82))
	s.add(&"tail2", &"tail1", v.call(0, 1.55, 1.15))
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		s.add(StringName("leg_upper_" + sx), &"pelvis", v.call(0.27 * side, 1.38, 0.22))
		s.add(StringName("leg_lower_" + sx), StringName("leg_upper_" + sx), v.call(0.29 * side, 1.02, -0.08))
		s.add(StringName("leg_meta_" + sx), StringName("leg_lower_" + sx), v.call(0.29 * side, 0.55, 0.16))
		s.add(StringName("leg_foot_" + sx), StringName("leg_meta_" + sx), v.call(0.29 * side, 0.08, 0.02))
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		var l := CreatureLeg.new()
		var fp := s.rest_pos[s.idx(StringName("leg_foot_" + sx))]
		l.setup(s, StringName("leg_" + sx), [StringName("leg_upper_" + sx), StringName("leg_lower_" + sx), StringName("leg_meta_" + sx),
				StringName("leg_foot_" + sx)], Vector3(fp.x, 0.0, fp.z - 0.08 * k))
		l.group = CreatureLeg.Group.HIND
		l.knee_dir = Vector3.FORWARD
		l.paw_size = 0.32 * k
		l.weight = 0.45
		l.curl = 1.0
		l.tuck = Vector3(0, -0.6, 0.35) * k
		rig.legs.append(l)
	var m := rig.motor
	m.root = s.idx(&"root")
	m.pelvis = s.idx(&"pelvis")
	m.spine = PackedInt32Array([s.idx(&"spine"), s.idx(&"chest")])
	m.neck = PackedInt32Array([s.idx(&"neck1"), s.idx(&"neck2"), s.idx(&"neck3")])
	m.neck_weights = PackedFloat32Array([0.3, 0.35, 0.35])
	m.head = s.idx(&"head")
	m.jaw = s.idx(&"jaw")
	m.tail = PackedInt32Array([s.idx(&"tail1"), s.idx(&"tail2")])
	m.ear_l = s.idx(&"ear_l")
	m.ear_r = s.idx(&"ear_r")
	m.eye_l = s.idx(&"eye_l")
	m.eye_r = s.idx(&"eye_r")
	m.lid_l = s.idx(&"lid_l")
	m.lid_r = s.idx(&"lid_r")
	m.hind_z = 0.3 * k
	m.front_z = -0.45 * k
	m.head_stab = 0.85
	m.lid_open = 1.0
	m.jaw_open = 0.35
	m.ear_back_angle = 0.7
	var ts := SpringChain.new().setup(s, m.tail, v.call(0, 1.42, 1.5))
	ts.stiffness = 50.0
	ts.damping = 6.0
	m.springs.append(ts)
	rig.gaits.append(GaitEngine.make_gait({"name": &"walk", "max_speed": 2.6 * sqrt(k), "duty": 0.62, "offsets": [0.0, 0.5],
			"freq": 1.0, "ref_speed": 1.6 * sqrt(k), "lift": 0.28 * k, "bob": 0.03, "bob_mult": 2.0, "roll": 0.03,
			"head_bob": 0.0, "spine_yaw": 0.04}))
	rig.gaits.append(GaitEngine.make_gait({"name": &"run", "duty": 0.36, "offsets": [0.0, 0.5], "freq": 1.75,
			"ref_speed": 11.0 * sqrt(k), "lift": 0.5 * k, "bob": 0.08, "bob_mult": 2.0, "bob_phase": 0.15, "pitch": 0.03,
			"roll": 0.02}))
	rig.gait.tempo = sqrt(k)
	rig.breath_period = 3.0
	rig.add_socket(&"saddle", &"spine", Transform3D(Basis.IDENTITY, v.call(0, 0.4, 0.05)))
	rig.add_socket(&"back", &"spine", Transform3D(Basis.IDENTITY, v.call(0, 0.4, 0.35)))
	rig.add_socket(&"rider_left", &"spine", Transform3D(Basis.IDENTITY, v.call(-0.42, -0.1, 0.05)))
	rig.add_socket(&"rider_right", &"spine", Transform3D(Basis.IDENTITY, v.call(0.42, -0.1, 0.05)))
	rig.add_socket(&"reins", &"head", Transform3D(Basis.IDENTITY, v.call(0, -0.08, -0.3)))
	rig.add_socket(&"head", &"head", Transform3D(Basis.IDENTITY, v.call(0, 0.05, -0.15)))
	rig.add_socket(&"mouth", &"jaw", Transform3D(Basis.IDENTITY, v.call(0, 0, -0.3)))
	rig.add_socket(&"chest", &"chest", Transform3D(Basis.IDENTITY, v.call(0, -0.1, -0.3)))
	rig.add_socket(&"tail", &"tail2", Transform3D.IDENTITY)
	rig.set_dimensions({
		"length": 2.6 * k, "height": 2.85 * k, "width": 0.95 * k, "saddle_height": 1.96 * k, "paw_size": 0.32 * k,
		"weight": 0.45, "can_fly": false, "walk_speed": 1.6 * sqrt(k), "run_speed": 11.0 * sqrt(k),
		"sprint_speed": 14.0 * sqrt(k), "fly_speed": 0.0, "collision_radius": 0.5 * k, "collision_height": 2.4 * k,
		"mass": 250.0 * k * k * k,
	})


func build_mesh(rig: CreatureRig, kit: MeshKit) -> void:
	var s := rig.skel
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z) * k
	var body_c := color("body", BODY)
	var mane_c := color("mane", MANE)
	var hw := s.rigid_weighter(&"head")
	kit.surface(&"body")
	kit.loft([{"p": v.call(0, 1.6, 0.9), "w": 0.18 * k, "h": 0.16 * k},
			{"p": v.call(0, 1.56, 0.6), "w": 0.38 * k, "h": 0.36 * k, "hb": 0.38 * k},
			{"p": v.call(0, 1.53, 0.15), "w": 0.44 * k, "h": 0.4 * k, "hb": 0.43 * k},
			{"p": v.call(0, 1.5, -0.3), "w": 0.4 * k, "h": 0.36 * k, "hb": 0.4 * k},
			{"p": v.call(0, 1.52, -0.62), "w": 0.26 * k, "h": 0.25 * k, "hb": 0.28 * k}],
			{"segs": 22, "sub": 2, "color": body_c, "cap0": "round", "cap1": "none", "fluff": 0.06, "lobes": 17.0, "fluff_lo": 1.8,
			"weights": s.chain_weighter([&"pelvis", &"spine", &"chest"], v.call(0, 1.55, -0.7)), "mark_row": 1, "seed": 61})
	kit.loft([{"p": v.call(0, 1.56, -0.55), "w": 0.2 * k, "h": 0.2 * k}, {"p": v.call(0, 1.72, -0.78), "w": 0.15 * k, "h": 0.16 * k},
			{"p": v.call(0, 2.04, -0.94), "w": 0.12 * k, "h": 0.13 * k}, {"p": v.call(0, 2.38, -1.03), "w": 0.11 * k, "h": 0.12 * k},
			{"p": v.call(0, 2.6, -1.05), "w": 0.1 * k, "h": 0.11 * k}],
			{"segs": 14, "sub": 2, "color": body_c, "cap0": "none", "cap1": "none", "mark_row": 2,
			"weights": s.chain_weighter([&"chest", &"neck1", &"neck2", &"neck3", &"head"], v.call(0, 2.65, -1.15))})
	# Horse head.
	kit.loft([{"p": v.call(0, 2.66, -0.98), "w": 0.1 * k, "h": 0.11 * k},
			{"p": v.call(0, 2.66, -1.12), "w": 0.12 * k, "h": 0.12 * k, "hb": 0.13 * k},
			{"p": v.call(0, 2.6, -1.3), "w": 0.1 * k, "h": 0.09 * k, "hb": 0.1 * k},
			{"p": v.call(0, 2.52, -1.48), "w": 0.075 * k, "h": 0.07 * k, "hb": 0.07 * k},
			{"p": v.call(0, 2.49, -1.56), "w": 0.07 * k, "h": 0.06 * k}],
			{"segs": 16, "sub": 2, "color": body_c, "cap0": "round", "cap1": "round", "cap_len": 0.6, "weights": hw, "mark_row": 3})
	kit.loft([{"p": v.call(0, 2.47, -1.2), "w": 0.07 * k, "h": 0.02 * k, "hb": 0.04 * k}, {"p": v.call(0, 2.45, -1.5), "w": 0.05 * k, "h": 0.015 * k, "hb": 0.03 * k}],
			{"segs": 10, "sub": 1, "color": MUZZLE, "weights": s.rigid_weighter(&"jaw")})
	for side in [-1.0, 1.0]:
		var en := StringName("ear_" + ("l" if side < 0.0 else "r"))
		var b := s.rest_pos[s.idx(en)]
		CreatureParts.ear(kit, rig, en, b, b + v.call(0.02 * side, 0.08, 0.02), b + v.call(0.03 * side, 0.16, 0.04),
				Vector3(0.035, 0.032, 0.008) * k, 0.012 * k, {"color": body_c, "segs": 8, "sub": 1, "face": Vector3(0.3 * side, 0, -1).normalized()})
	# Folded wing stubs.
	for side in [-1.0, 1.0]:
		kit.ellipsoid(v.call(0.4 * side, 1.58, 0.05), Vector3(0.07, 0.2, 0.36) * k, {"color": mane_c.lightened(0.15), "fluff": 0.0,
				"weights": s.rigid_weighter(&"spine"), "rings": 9, "segs": 12}, Basis.from_euler(Vector3(0.25, 0.1 * side, 0.15 * side)))
	# Crest down the neck and plume tail.
	kit.surface(&"mane")
	var crest_bones := [&"head", &"neck3", &"neck3", &"neck2", &"neck2", &"neck2", &"neck1", &"neck1", &"chest"]
	for i in 17:
		var t := float(i) / 16.0
		var p: Vector3 = v.call(0, lerpf(2.72, 1.72, t), lerpf(-1.03, -0.62, t)) + v.call(0, 0.04, 0.09)
		var bone: StringName = crest_bones[int(round(t * 8.0))]
		var wob := 0.5 + 0.5 * sin(i * 2.3)
		_plume(kit, s, bone, p, Vector3(0.12 * sin(i * 1.7), 0.3 + 0.2 * wob, 1.0).normalized(), lerpf(0.26, 0.34, t) * (0.85 + 0.3 * wob) * k,
				0.085 * k, mane_c)
	for i in 5:
		var a := (float(i) - 2.0) * 0.35
		_plume(kit, s, &"tail2", v.call(0, 1.58, 1.0), Vector3(sin(a) * 0.6, 0.45 - absf(a) * 0.3, 1.0).normalized(), 0.65 * k, 0.1 * k, mane_c)
	# Bird legs and feet.
	kit.surface(&"legs")
	for l in rig.legs:
		CreatureParts.limb(kit, rig, l, [Vector2(0.17, 0.2) * k, Vector2(0.17, 0.2) * k, Vector2(0.075, 0.085) * k, Vector2(0.05, 0.05) * k,
				Vector2(0.045, 0.04) * k], v.call(0, 0.08, 0), {"segs": 10, "sub": 2, "color": LEGS, "cap0": "none"})
		CreatureParts.paw(kit, rig, l, Vector3(0.085, 0.04, 0.12) * k, 2, 0.06 * k, {"color": LEGS, "segs": 10, "rings": 6}, &"claw", &"legs")
	kit.surface(&"claw")
	kit.ellipsoid(v.call(0, 2.52, -1.56), Vector3(0.05, 0.04, 0.03) * k, {"weights": hw, "rings": 6, "segs": 8})
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		CreatureParts.eye(kit, rig, StringName("eye_" + sx), StringName("lid_" + sx), 0.03 * k, Vector3(0.85 * side, 0.1, -0.5).normalized(),
				&"body", &"eye", Vector3.ONE, {"color": body_c})
	kit.surface(&"body")


static func _plume(kit: MeshKit, s: RigSkeleton, bone: StringName, base: Vector3, dir: Vector3, length: float, width: float, c: Color) -> void:
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 1e-4:
		side = Vector3.RIGHT
	var up := side.cross(dir).normalized()
	kit.loft([{"p": base, "w": width * 0.6, "h": width * 0.3, "up": up, "c": Color(c.r, c.g, c.b, 0.0)},
			{"p": base + dir * length * 0.45, "w": width, "h": width * 0.3, "up": up, "c": Color(c.r, c.g, c.b, 0.4)},
			{"p": base + dir * length + Vector3(0, -0.2, 0) * length, "w": width * 0.1, "h": width * 0.05, "up": up, "c": Color(c.r, c.g, c.b, 1.0)}],
			{"segs": 8, "sub": 2, "cap1": "point", "weights": s.rigid_weighter(bone)})


func material_for(surface: StringName, _detail: int, _lod: int) -> Material:
	match surface:
		&"body":
			return CreatureMaterials.skin("ostrich_horse/body", Color.WHITE, {"shade_tint": Color(0.62, 0.58, 0.78), "rim": 0.35,
				"pattern": CreatureMaterials.Pattern.FEATHERS, "pattern_scale": 9.0, "pattern_strength": 0.14,
				"marks": _marks(), "mark_rows": 4, "mark_colors": [MANE, Color(0.95, 0.88, 0.72), MUZZLE], "outline_width": 1.0})
		&"mane":
			return CreatureMaterials.skin("ostrich_horse/mane", Color.WHITE, {"rim": 0.4, "pattern": CreatureMaterials.Pattern.FUR,
				"pattern_scale": 25.0, "pattern_strength": 0.2, "flutter": 0.03 * k, "flutter_freq": 3.0, "outline_width": 0.8})
		&"legs":
			return CreatureMaterials.skin("ostrich_horse/legs", LEGS, {"pattern": CreatureMaterials.Pattern.SCALES, "pattern_scale": 22.0,
				"pattern_strength": 0.25, "outline_width": 0.9})
		&"claw":
			return CreatureMaterials.hard("ostrich_horse/claw", Color(0.2, 0.18, 0.18), {"outline_width": 0.7})
		&"eye":
			return CreatureMaterials.eye("ostrich_horse/eye", {"iris": Color(0.12, 0.07, 0.04), "iris_inner": Color(0.3, 0.18, 0.08),
				"iris_size": 0.95, "pupil_size": 0.55})
	return CreatureMaterials.skin("ostrich_horse/default", BODY)


static var _mark_tex: ImageTexture = null


static func _marks() -> ImageTexture:
	if _mark_tex == null:
		_mark_tex = CreatureMaterials.mark_texture([
			{},
			{"ventral": [[0.0, 0.1], [0.5, 0.16], [1.0, 0.12]], "dorsal": [[0.0, 0.0], [0.5, 0.05], [1.0, 0.02]]},
			{"ventral": [[0.0, 0.12], [1.0, 0.1]]},
			# Head: dark muzzle toward the nose.
			{"lateral": [[0.0, 0.0], [0.6, 0.0], [0.7, 0.18], [1.0, 0.3]], "lateral_center": [[0.0, 0.5], [1.0, 0.5]]},
		])
	return _mark_tex


func idle_actions() -> Array[StringName]:
	return [&"look_around", &"sniff", &"ear_twitch", &"eat", &"shake", &"look_around"]


func sound_for(_action: StringName, _event: StringName) -> StringName:
	return &""
