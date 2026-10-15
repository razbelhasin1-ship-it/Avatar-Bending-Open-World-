extends CreatureSpecies
## Turtle duck (lake wildlife): a ~0.55 m duck carrying a green turtle shell, tan
## body, yellow head, orange bill and webbed feet. Waddles on land and paddles on
## water (set_swimming). Actions: quack, preen, dive (tips up to feed), shake.

const BODY := Color(0.8, 0.68, 0.45)
const HEAD := Color(0.86, 0.72, 0.32)
const SHELL := Color(0.33, 0.46, 0.25)
const BILL := Color(0.96, 0.6, 0.16)


func id() -> StringName:
	return &"turtle_duck"


func draw_distance() -> float:
	return 90.0


func _init() -> void:
	tune["neck_down"] = -0.9
	tune["head_up"] = 0.5
	tune["swim_float"] = 0.0
	tune["shake_roll"] = 0.35


func build(rig: CreatureRig) -> void:
	var s := rig.skel
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z) * k
	s.add(&"root", &"", Vector3.ZERO)
	s.add(&"pelvis", &"root", v.call(0, 0.17, 0.1))
	s.add(&"chest", &"pelvis", v.call(0, 0.19, -0.08))
	s.add(&"neck1", &"chest", v.call(0, 0.23, -0.15))
	s.add(&"neck2", &"neck1", v.call(0, 0.3, -0.17))
	s.add(&"head", &"neck2", v.call(0, 0.355, -0.18))
	s.add(&"jaw", &"head", v.call(0, 0.35, -0.225))
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		s.add(StringName("eye_" + sx), &"head", v.call(0.036 * side, 0.375, -0.205))
		s.add(StringName("lid_" + sx), &"head", v.call(0.036 * side, 0.375, -0.205))
	s.add(&"tail1", &"pelvis", v.call(0, 0.21, 0.22))
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		s.add(StringName("leg_upper_" + sx), &"pelvis", v.call(0.06 * side, 0.13, 0.07))
		s.add(StringName("leg_lower_" + sx), StringName("leg_upper_" + sx), v.call(0.065 * side, 0.075, 0.055))
		s.add(StringName("leg_foot_" + sx), StringName("leg_lower_" + sx), v.call(0.066 * side, 0.018, 0.065))
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		var l := CreatureLeg.new()
		var fp := s.rest_pos[s.idx(StringName("leg_foot_" + sx))]
		l.setup(s, StringName("leg_" + sx), [StringName("leg_upper_" + sx), StringName("leg_lower_" + sx), StringName("leg_foot_" + sx)],
				Vector3(fp.x, 0.0, fp.z - 0.015 * k))
		l.group = CreatureLeg.Group.HIND
		l.knee_dir = Vector3.FORWARD
		l.paw_size = 0.07 * k
		l.weight = 0.05
		l.curl = 0.4
		l.tuck = Vector3(0, -0.06, 0.06) * k
		rig.legs.append(l)
	var m := rig.motor
	m.root = s.idx(&"root")
	m.pelvis = s.idx(&"pelvis")
	m.spine = PackedInt32Array([s.idx(&"chest")])
	m.neck = PackedInt32Array([s.idx(&"neck1"), s.idx(&"neck2")])
	m.neck_weights = PackedFloat32Array([0.5, 0.5])
	m.head = s.idx(&"head")
	m.jaw = s.idx(&"jaw")
	m.tail = PackedInt32Array([s.idx(&"tail1")])
	m.eye_l = s.idx(&"eye_l")
	m.eye_r = s.idx(&"eye_r")
	m.lid_l = s.idx(&"lid_l")
	m.lid_r = s.idx(&"lid_r")
	m.hind_z = 0.1 * k
	m.front_z = -0.08 * k
	m.head_stab = 0.75
	m.lid_open = 1.1
	m.jaw_open = 0.4
	rig.gaits.append(GaitEngine.make_gait({"name": &"waddle", "max_speed": 0.6 * sqrt(k), "duty": 0.6, "offsets": [0.0, 0.5],
			"freq": 3.0, "ref_speed": 0.35 * sqrt(k), "lift": 0.025 * k, "bob": 0.006, "bob_mult": 2.0, "roll": 0.14,
			"spine_yaw": 0.1, "head_bob": 0.05}))
	rig.gaits.append(GaitEngine.make_gait({"name": &"hurry", "duty": 0.5, "offsets": [0.0, 0.5], "freq": 4.5,
			"ref_speed": 1.0 * sqrt(k), "lift": 0.035 * k, "bob": 0.008, "bob_mult": 2.0, "roll": 0.16, "head_bob": 0.07}))
	rig.gait.tempo = sqrt(k)
	rig.breath_period = 1.6
	rig.add_socket(&"head", &"head", Transform3D(Basis.IDENTITY, v.call(0, 0.02, -0.02)))
	rig.add_socket(&"mouth", &"jaw", Transform3D(Basis.IDENTITY, v.call(0, 0, -0.07)))
	rig.add_socket(&"saddle", &"pelvis", Transform3D(Basis.IDENTITY, v.call(0, 0.15, -0.05)))
	rig.add_socket(&"back", &"pelvis", Transform3D(Basis.IDENTITY, v.call(0, 0.15, -0.05)))
	rig.add_socket(&"rider_left", &"pelvis", Transform3D(Basis.IDENTITY, v.call(-0.15, 0.05, -0.05)))
	rig.add_socket(&"rider_right", &"pelvis", Transform3D(Basis.IDENTITY, v.call(0.15, 0.05, -0.05)))
	rig.add_socket(&"chest", &"chest", Transform3D(Basis.IDENTITY, v.call(0, -0.04, -0.06)))
	rig.add_socket(&"tail", &"tail1", Transform3D.IDENTITY)
	rig.set_dimensions({
		"length": 0.56 * k, "height": 0.42 * k, "width": 0.32 * k, "saddle_height": 0.33 * k, "paw_size": 0.07 * k,
		"weight": 0.05, "can_fly": false, "walk_speed": 0.35 * sqrt(k), "run_speed": 1.0 * sqrt(k),
		"sprint_speed": 1.2 * sqrt(k), "swim_speed": 0.8 * sqrt(k), "fly_speed": 0.0,
		"collision_radius": 0.15 * k, "collision_height": 0.4 * k, "mass": 3.0 * k * k * k,
	})


func build_mesh(rig: CreatureRig, kit: MeshKit) -> void:
	var s := rig.skel
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z) * k
	var hw := s.rigid_weighter(&"head")
	kit.surface(&"body")
	kit.loft([{"p": v.call(0, 0.22, 0.27), "w": 0.04 * k, "h": 0.03 * k},
			{"p": v.call(0, 0.19, 0.16), "w": 0.12 * k, "h": 0.09 * k},
			{"p": v.call(0, 0.18, 0.02), "w": 0.135 * k, "h": 0.1 * k, "hb": 0.105 * k},
			{"p": v.call(0, 0.19, -0.1), "w": 0.11 * k, "h": 0.09 * k, "hb": 0.1 * k},
			{"p": v.call(0, 0.215, -0.17), "w": 0.06 * k, "h": 0.06 * k}],
			{"segs": 16, "sub": 2, "color": color("body", BODY), "cap0": "point", "cap1": "round",
			"weights": s.chain_weighter([&"tail1", &"pelvis", &"chest"], v.call(0, 0.21, -0.18)), "mark_row": 1})
	kit.loft([{"p": v.call(0, 0.2, -0.13), "w": 0.042 * k, "h": 0.042 * k}, {"p": v.call(0, 0.27, -0.165), "w": 0.034 * k, "h": 0.034 * k},
			{"p": v.call(0, 0.34, -0.18), "w": 0.034 * k, "h": 0.034 * k}],
			{"segs": 10, "sub": 2, "color": color("head", HEAD), "cap0": "none", "cap1": "none",
			"weights": s.chain_weighter([&"neck1", &"neck2", &"head"], v.call(0, 0.37, -0.19))})
	kit.loft([{"p": v.call(0, 0.37, -0.145), "w": 0.04 * k, "h": 0.04 * k},
			{"p": v.call(0, 0.375, -0.19), "w": 0.047 * k, "h": 0.046 * k},
			{"p": v.call(0, 0.365, -0.225), "w": 0.035 * k, "h": 0.03 * k}],
			{"segs": 14, "sub": 2, "color": color("head", HEAD), "cap0": "round", "cap1": "round", "weights": hw, "mark_row": 2})
	kit.surface(&"shell")
	kit.loft([{"p": v.call(0, 0.215, 0.21), "w": 0.08 * k, "h": 0.035 * k, "hb": 0.012 * k},
			{"p": v.call(0, 0.225, 0.12), "w": 0.145 * k, "h": 0.085 * k, "hb": 0.014 * k},
			{"p": v.call(0, 0.23, 0.0), "w": 0.155 * k, "h": 0.095 * k, "hb": 0.014 * k},
			{"p": v.call(0, 0.225, -0.1), "w": 0.12 * k, "h": 0.065 * k, "hb": 0.013 * k}],
			{"segs": 18, "sub": 2, "color": color("shell", SHELL), "cap0": "round", "cap1": "round", "cap_len": 0.5,
			"weights": s.chain_weighter([&"pelvis", &"chest"], v.call(0, 0.22, -0.12)), "mark_row": 3})
	kit.surface(&"bill")
	kit.loft([{"p": v.call(0, 0.37, -0.215), "w": 0.03 * k, "h": 0.012 * k}, {"p": v.call(0, 0.364, -0.27), "w": 0.027 * k, "h": 0.009 * k},
			{"p": v.call(0, 0.36, -0.295), "w": 0.022 * k, "h": 0.007 * k}],
			{"segs": 10, "sub": 1, "weights": hw, "cap1": "round"})
	kit.loft([{"p": v.call(0, 0.355, -0.22), "w": 0.026 * k, "h": 0.006 * k}, {"p": v.call(0, 0.352, -0.285), "w": 0.02 * k, "h": 0.005 * k}],
			{"segs": 8, "sub": 1, "weights": s.rigid_weighter(&"jaw"), "cap1": "round"})
	for l in rig.legs:
		CreatureParts.limb(kit, rig, l, [Vector2(0.02, 0.02) * k, Vector2(0.016, 0.016) * k, Vector2(0.012, 0.012) * k, Vector2(0.01, 0.01) * k],
				v.call(0, 0.03, 0), {"segs": 6, "sub": 1, "cap0": "none"})
		CreatureParts.paw(kit, rig, l, Vector3(0.03, 0.006, 0.035) * k, 3, 0.0, {"segs": 8, "rings": 5}, &"bill", &"bill")
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		CreatureParts.eye(kit, rig, StringName("eye_" + sx), StringName("lid_" + sx), 0.011 * k, Vector3(0.8 * side, 0.1, -0.6).normalized(),
				&"body", &"eye", Vector3.ONE, {"color": HEAD})
	kit.surface(&"body")


func material_for(surface: StringName, _detail: int, _lod: int) -> Material:
	match surface:
		&"body":
			return CreatureMaterials.skin("turtle_duck/body", Color.WHITE, {"shade_tint": Color(0.62, 0.6, 0.78), "rim": 0.35,
				"pattern": CreatureMaterials.Pattern.FEATHERS, "pattern_scale": 60.0, "pattern_strength": 0.12,
				"marks": _marks(), "mark_rows": 4, "mark_colors": [Color(0.5, 0.38, 0.18), Color(0.95, 0.9, 0.75), Color(0.25, 0.4, 0.22)],
				"outline_width": 0.8})
		&"shell":
			return CreatureMaterials.skin("turtle_duck/shell", Color.WHITE, {"shade_tint": Color(0.55, 0.6, 0.7), "rim": 0.3,
				"pattern": CreatureMaterials.Pattern.SHELL, "pattern_scale": 22.0, "pattern_strength": 0.35, "specular": 0.25,
				"marks": _marks(), "mark_rows": 4, "mark_colors": [Color(0.78, 0.72, 0.35), Color(0.9, 0.85, 0.6), Color(0.78, 0.72, 0.35)],
				"outline_width": 0.8})
		&"bill":
			return CreatureMaterials.hard("turtle_duck/bill", BILL, {"outline_width": 0.7})
		&"eye":
			return CreatureMaterials.eye("turtle_duck/eye", {"iris": Color(0.05, 0.04, 0.03), "iris_size": 1.0, "pupil_size": 0.6})
	return CreatureMaterials.skin("turtle_duck/default", BODY)


static var _mark_tex: ImageTexture = null


static func _marks() -> ImageTexture:
	if _mark_tex == null:
		_mark_tex = CreatureMaterials.mark_texture([
			{},
			{"ventral": [[0.0, 0.1], [0.5, 0.2], [1.0, 0.15]]},
			# Head: darker crown, pale cheeks.
			{"dorsal": [[0.0, 0.12], [0.6, 0.1], [1.0, 0.0]], "ventral": [[0.0, 0.1], [1.0, 0.18]]},
			# Shell: yellow rim stripe low on the sides.
			{"lateral": [[0.0, 0.02], [1.0, 0.02]], "lateral_center": [[0.0, 0.33], [1.0, 0.33]]},
		])
	return _mark_tex


func idle_actions() -> Array[StringName]:
	return [&"preen", &"look_around", &"quack", &"shake", &"dive"]


func make_action(action_name: StringName, opts: Dictionary) -> CreatureAction:
	match action_name:
		&"quack", &"call":
			var q := CreatureAction.new(action_name, 0.8)
			q.add_event(0.2, &"vocal_start")
			return q
		&"preen":
			return CreatureAction.new(action_name, 2.0)
		&"dive":
			var d := CreatureAction.new(action_name, 2.4)
			d.add_event(0.5, &"splash")
			return d
	return super.make_action(action_name, opts)


func action_pose(rig: CreatureRig, a: CreatureAction, pose: CreaturePose) -> void:
	var w := a.weight
	match a.name:
		&"quack", &"call":
			var e := a.window(0.1, 0.8, 0.15)
			pose.neck_pitch += 0.3 * e * w
			pose.head_pitch += 0.3 * e * w
			pose.jaw += (0.6 + 0.4 * sin(a.t * 40.0)) * e * w
			return
		&"preen":
			var e := a.envelope(0.2, 0.2)
			pose.neck_yaw += 1.3 * e * w
			pose.neck_pitch += -0.5 * e * w
			pose.head_pitch += -0.6 * e * w
			pose.head_roll += 0.25 * sin(a.t * 16.0) * e * w
			pose.eyes_narrow += e * w
			return
		&"dive":
			# Tips up, head under (works on land as a "feeding" nod too).
			var e := a.window(0.1, 0.9, 0.2)
			pose.pitch_pivot += 1.0 * w
			pose.body_pitch += -0.9 * e * w
			pose.neck_pitch += -0.8 * e * w
			pose.tail_pitch += 0.6 * e * w
			for l in rig.legs:
				pose.add_paw(l.index, Vector3(0, 0.04 * sin(a.t * 18.0 + l.side), 0.03) * k * e * w)
			pose.hind_free += e * w * rig.swim_w
			return
	super.action_pose(rig, a, pose)
