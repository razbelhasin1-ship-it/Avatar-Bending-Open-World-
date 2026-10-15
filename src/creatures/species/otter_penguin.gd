extends CreatureSpecies
## Otter penguin (arctic wildlife): ~1 m tall upright penguin body with an otter's
## round face, whiskers and small ears; black back, white front, flippers and webbed
## feet. Waddles (big side-to-side roll), toboggans on its belly (belly_slide, hold) and
## swims (set_swimming) in the same flat pose. Small budget: no fur shells.

const BACK := Color(0.17, 0.16, 0.18)
const BELLY := Color(0.96, 0.95, 0.92)
const FEET := Color(0.32, 0.3, 0.3)

var flip_l := -1
var flip_r := -1


func id() -> StringName:
	return &"otter_penguin"


func draw_distance() -> float:
	return 160.0


func _init() -> void:
	tune["sit_pitch"] = 0.0
	tune["sit_drop"] = 0.12
	tune["neck_down"] = -0.5
	tune["head_up"] = 0.6
	tune["shake_roll"] = 0.3
	tune["swim_float"] = 0.0


func build(rig: CreatureRig) -> void:
	var s := rig.skel
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z) * k
	s.add(&"root", &"", Vector3.ZERO)
	s.add(&"pelvis", &"root", v.call(0, 0.32, 0.02))
	s.add(&"spine1", &"pelvis", v.call(0, 0.5, 0.0))
	s.add(&"chest", &"spine1", v.call(0, 0.68, -0.01))
	s.add(&"neck", &"chest", v.call(0, 0.83, -0.02))
	s.add(&"head", &"neck", v.call(0, 0.92, -0.03))
	s.add(&"jaw", &"head", v.call(0, 0.9, -0.1))
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		s.add(StringName("eye_" + sx), &"head", v.call(0.068 * side, 0.99, -0.125))
		s.add(StringName("lid_" + sx), &"head", v.call(0.068 * side, 0.99, -0.125))
		s.add(StringName("flipper_" + sx), &"chest", v.call(0.19 * side, 0.72, 0.0))
		s.add(StringName("flipper_tip_" + sx), StringName("flipper_" + sx), v.call(0.27 * side, 0.52, 0.01))
	s.add(&"tail1", &"pelvis", v.call(0, 0.22, 0.17))
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		s.add(StringName("leg_upper_" + sx), &"pelvis", v.call(0.09 * side, 0.27, 0.03))
		s.add(StringName("leg_lower_" + sx), StringName("leg_upper_" + sx), v.call(0.1 * side, 0.16, -0.01))
		s.add(StringName("leg_foot_" + sx), StringName("leg_lower_" + sx), v.call(0.105 * side, 0.045, 0.0))
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		var l := CreatureLeg.new()
		var fp := s.rest_pos[s.idx(StringName("leg_foot_" + sx))]
		l.setup(s, StringName("leg_" + sx), [StringName("leg_upper_" + sx), StringName("leg_lower_" + sx), StringName("leg_foot_" + sx)],
				Vector3(fp.x, 0.0, fp.z - 0.03 * k))
		l.group = CreatureLeg.Group.HIND
		l.knee_dir = Vector3.FORWARD
		l.paw_size = 0.16 * k
		l.weight = 0.15
		l.curl = 0.2
		l.tuck = Vector3(0.0, -0.12, 0.12) * k
		rig.legs.append(l)
	flip_l = s.idx(&"flipper_l")
	flip_r = s.idx(&"flipper_r")
	var m := rig.motor
	m.root = s.idx(&"root")
	m.pelvis = s.idx(&"pelvis")
	m.spine = PackedInt32Array([s.idx(&"spine1"), s.idx(&"chest")])
	m.neck = PackedInt32Array([s.idx(&"neck")])
	m.neck_weights = PackedFloat32Array([0.6])
	m.head = s.idx(&"head")
	m.jaw = s.idx(&"jaw")
	m.tail = PackedInt32Array([s.idx(&"tail1")])
	m.eye_l = s.idx(&"eye_l")
	m.eye_r = s.idx(&"eye_r")
	m.lid_l = s.idx(&"lid_l")
	m.lid_r = s.idx(&"lid_r")
	m.hind_z = 0.0
	m.front_z = 0.0
	m.head_stab = 0.5
	m.lid_open = 1.1
	m.jaw_open = 0.5
	rig.gaits.append(GaitEngine.make_gait({"name": &"waddle", "max_speed": 0.9 * sqrt(k), "duty": 0.62,
			"offsets": [0.0, 0.5], "freq": 2.0, "ref_speed": 0.55 * sqrt(k), "lift": 0.05 * k, "bob": 0.012,
			"bob_mult": 2.0, "roll": 0.16, "roll_phase": 0.0, "spine_yaw": 0.12, "spine_yaw_phase": 0.0, "head_bob": 0.02}))
	rig.gaits.append(GaitEngine.make_gait({"name": &"hurry", "duty": 0.5,
			"offsets": [0.0, 0.5], "freq": 3.2, "ref_speed": 1.4 * sqrt(k), "lift": 0.07 * k, "bob": 0.02,
			"bob_mult": 2.0, "roll": 0.2, "spine_yaw": 0.15, "head_bob": 0.03}))
	rig.gait.tempo = sqrt(k)
	rig.gait.settle_tolerance = 0.25
	rig.breath_period = 2.2
	rig.add_socket(&"saddle", &"spine1", Transform3D(Basis.IDENTITY, v.call(0, 0.0, 0.22)))
	rig.add_socket(&"back", &"spine1", Transform3D(Basis.IDENTITY, v.call(0, 0.0, 0.22)))
	rig.add_socket(&"rider_left", &"spine1", Transform3D(Basis.IDENTITY, v.call(-0.25, 0, 0)))
	rig.add_socket(&"rider_right", &"spine1", Transform3D(Basis.IDENTITY, v.call(0.25, 0, 0)))
	rig.add_socket(&"head", &"head", Transform3D(Basis.IDENTITY, v.call(0, 0.05, -0.05)))
	rig.add_socket(&"mouth", &"jaw", Transform3D(Basis.IDENTITY, v.call(0, 0, -0.1)))
	rig.add_socket(&"chest", &"chest", Transform3D(Basis.IDENTITY, v.call(0, 0, -0.18)))
	rig.add_socket(&"tail", &"tail1", Transform3D.IDENTITY)
	rig.set_dimensions({
		"length": 0.5 * k, "height": 1.08 * k, "width": 0.6 * k, "saddle_height": 0.75 * k, "paw_size": 0.16 * k,
		"weight": 0.15, "can_fly": false, "walk_speed": 0.55 * sqrt(k), "run_speed": 1.4 * sqrt(k),
		"sprint_speed": 6.0 * sqrt(k), "slide_speed": 6.0 * sqrt(k), "fly_speed": 0.0,
		"collision_radius": 0.28 * k, "collision_height": 1.05 * k, "mass": 30.0 * k * k * k,
	})


func build_mesh(rig: CreatureRig, kit: MeshKit) -> void:
	var s := rig.skel
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z) * k
	var back := color("back", BACK)
	kit.surface(&"body")
	# Upright egg body (vertical loft: u = 0 faces forward -> the white front is the
	# "dorsal" marking band).
	var body := [
		{"p": v.call(0, 0.16, 0.03), "w": 0.17 * k, "h": 0.15 * k},
		{"p": v.call(0, 0.32, 0.02), "w": 0.245 * k, "h": 0.21 * k},
		{"p": v.call(0, 0.5, 0.0), "w": 0.25 * k, "h": 0.22 * k},
		{"p": v.call(0, 0.68, -0.01), "w": 0.205 * k, "h": 0.185 * k},
		{"p": v.call(0, 0.83, -0.02), "w": 0.14 * k, "h": 0.13 * k},
		{"p": v.call(0, 0.92, -0.02), "w": 0.11 * k, "h": 0.105 * k},
	]
	kit.loft(body, {"segs": 18, "sub": 2, "color": back, "cap0": "round", "cap1": "none", "cap_len": 0.8, "mark_row": 1,
			"weights": s.chain_weighter([&"pelvis", &"spine1", &"chest", &"neck"], v.call(0, 0.95, -0.03))})
	# Otter head.
	var hw := s.rigid_weighter(&"head")
	var head := [
		{"p": v.call(0, 0.975, 0.055), "w": 0.095 * k, "h": 0.09 * k},
		{"p": v.call(0, 0.98, -0.02), "w": 0.13 * k, "h": 0.115 * k, "hb": 0.105 * k},
		{"p": v.call(0, 0.97, -0.1), "w": 0.115 * k, "h": 0.095 * k, "hb": 0.09 * k},
		{"p": v.call(0, 0.952, -0.16), "w": 0.075 * k, "h": 0.06 * k},
		{"p": v.call(0, 0.948, -0.195), "w": 0.06 * k, "h": 0.048 * k},
	]
	kit.loft(head, {"segs": 18, "sub": 2, "color": back, "cap0": "round", "cap1": "round", "cap_len": 0.7, "mark_row": 2, "weights": hw})
	kit.loft([{"p": v.call(0, 0.915, -0.08), "w": 0.07 * k, "h": 0.02 * k, "hb": 0.03 * k},
			{"p": v.call(0, 0.91, -0.17), "w": 0.045 * k, "h": 0.015 * k, "hb": 0.02 * k}],
			{"segs": 10, "sub": 1, "color": BELLY, "weights": s.rigid_weighter(&"jaw")})
	for side in [-1.0, 1.0]:
		kit.ellipsoid(v.call(0.085 * side, 1.075, 0.0), Vector3(0.032, 0.03, 0.018) * k, {"color": back, "weights": hw, "rings": 6, "segs": 8},
				Basis.from_euler(Vector3(0, 0.5 * side, 0)))
	# Flippers.
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		var a := s.rest_pos[s.idx(StringName("flipper_" + sx))]
		var b := s.rest_pos[s.idx(StringName("flipper_tip_" + sx))]
		kit.loft([{"p": a, "w": 0.06 * k, "h": 0.022 * k}, {"p": a.lerp(b, 0.5), "w": 0.065 * k, "h": 0.018 * k},
				{"p": b, "w": 0.03 * k, "h": 0.012 * k}],
				{"segs": 10, "sub": 2, "color": back, "cap1": "round", "weights": s.chain_weighter([StringName("flipper_" + sx)], b, 0.2)})
	kit.loft([{"p": v.call(0, 0.24, 0.13), "w": 0.07 * k, "h": 0.03 * k}, {"p": v.call(0, 0.15, 0.24), "w": 0.04 * k, "h": 0.015 * k}],
			{"segs": 8, "sub": 1, "color": back, "cap1": "point", "weights": s.rigid_weighter(&"tail1")})
	kit.surface(&"feet")
	for l in rig.legs:
		CreatureParts.limb(kit, rig, l, [Vector2(0.06, 0.06) * k, Vector2(0.05, 0.05) * k, Vector2(0.035, 0.035) * k, Vector2(0.03, 0.03) * k],
				v.call(0, 0.05, 0), {"segs": 8, "sub": 1, "color": FEET, "cap0": "none"})
		CreatureParts.paw(kit, rig, l, Vector3(0.055, 0.02, 0.085) * k, 3, 0.0, {"color": FEET, "segs": 10, "rings": 6}, &"feet", &"feet")
	kit.surface(&"nose")
	kit.ellipsoid(v.call(0, 0.968, -0.215), Vector3(0.026, 0.018, 0.016) * k, {"weights": hw, "rings": 6, "segs": 10})
	for side in [-1.0, 1.0]:
		for i in 3:
			var base: Vector3 = v.call(0.045 * side, 0.94 - i * 0.008, -0.18)
			var dir := Vector3(side, 0.15 - i * 0.12, 0.35).normalized()
			kit.tube(PackedVector3Array([base, base + dir * 0.06 * k, base + dir * 0.11 * k]), PackedFloat32Array([0.003 * k, 0.002 * k, 0.0005 * k]),
					{"weights": hw, "segs": 4, "sub": 1})
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		CreatureParts.eye(kit, rig, StringName("eye_" + sx), StringName("lid_" + sx), 0.022 * k, Vector3(0.45 * side, 0.05, -1.0).normalized(),
				&"body", &"eye", Vector3.ONE, {"color": back})
	kit.surface(&"body")


func material_for(surface: StringName, _detail: int, _lod: int) -> Material:
	match surface:
		&"body":
			return CreatureMaterials.skin("otter_penguin/body", Color.WHITE, {"shade_tint": Color(0.6, 0.66, 0.85), "rim": 0.4,
				"pattern": CreatureMaterials.Pattern.FUR, "pattern_scale": 30.0, "pattern_strength": 0.08,
				"marks": _marks(), "mark_rows": 3, "mark_colors": [BELLY, BELLY, BELLY], "outline_width": 1.0})
		&"feet":
			return CreatureMaterials.hard("otter_penguin/feet", FEET, {"outline_width": 0.8})
		&"nose":
			return CreatureMaterials.hard("otter_penguin/nose", Color(0.05, 0.05, 0.06), {"specular": 0.5, "outline": false})
		&"eye":
			return CreatureMaterials.eye("otter_penguin/eye", {"iris": Color(0.05, 0.04, 0.04), "iris_inner": Color(0.15, 0.1, 0.08),
				"iris_size": 1.0, "pupil_size": 0.6, "catchlight": 1.2})
	return CreatureMaterials.skin("otter_penguin/default", BACK)


static var _mark_tex: ImageTexture = null


static func _marks() -> ImageTexture:
	if _mark_tex == null:
		_mark_tex = CreatureMaterials.mark_texture([
			{},
			# Body (bottom -> neck): white front.
			{"dorsal": [[0.0, 0.18], [0.2, 0.25], [0.7, 0.22], [1.0, 0.16]]},
			# Head (back -> muzzle): white muzzle and cheeks.
			{"ventral": [[0.0, 0.0], [0.35, 0.18], [0.7, 0.32], [1.0, 0.5]], "lateral": [[0.0, 0.0], [0.6, 0.0], [0.8, 0.06], [1.0, 0.1]],
			"lateral_center": [[0.0, 0.32], [1.0, 0.3]]},
		])
	return _mark_tex


func idle_actions() -> Array[StringName]:
	return [&"look_around", &"preen", &"flap", &"look_around", &"shake"]


func make_action(action_name: StringName, opts: Dictionary) -> CreatureAction:
	match action_name:
		&"belly_slide":
			var a := CreatureAction.new(action_name, 0.5)
			a.hold = true
			a.blend_in = 0.15
			a.blend_out = 0.45
			a.add_event(0.45, &"slide_start")
			return a
		&"flap":
			var f := CreatureAction.new(action_name, 1.4)
			f.add_event(0.3, &"call")
			return f
		&"preen":
			return CreatureAction.new(action_name, 2.2)
	return super.make_action(action_name, opts)


func _slide_pose(rig: CreatureRig, pose: CreaturePose, w: float) -> void:
	pose.body_pitch += -1.42 * w
	pose.body_y += -0.13 * k * w
	pose.neck_pitch += 0.7 * w
	pose.head_pitch += 0.55 * w
	pose.head_stab += -0.5 * w
	pose.hind_free += w
	for l in rig.legs:
		pose.add_paw(l.index, Vector3(0.03 * l.side, 0.1, 0.1) * k * w)
	pose.add_extra(&"flipper_out", w)


func action_pose(rig: CreatureRig, a: CreatureAction, pose: CreaturePose) -> void:
	var w := a.weight
	match a.name:
		&"belly_slide":
			_slide_pose(rig, pose, w)
			return
		&"flap":
			var e := a.envelope(0.15, 0.2)
			pose.add_extra(&"flipper_flap", e * w)
			pose.head_pitch += 0.4 * e * w
			pose.jaw += 0.5 * a.window(0.2, 0.6, 0.1) * w
			return
		&"preen":
			var e := a.envelope(0.2, 0.2)
			pose.neck_yaw += 0.9 * e * w
			pose.head_pitch += -0.5 * e * w
			pose.head_yaw += 0.6 * e * w
			pose.head_roll += 0.2 * sin(a.t * 14.0) * e * w
			pose.eyes_narrow += e * w
			return
	super.action_pose(rig, a, pose)


func swim_pose(rig: CreatureRig, pose: CreaturePose) -> void:
	super.swim_pose(rig, pose)
	_slide_pose(rig, pose, rig.swim_w)


func post_pose(rig: CreatureRig, _delta: float) -> void:
	var out := rig.pose.get_extra(&"flipper_out")
	var flap := rig.pose.get_extra(&"flipper_flap")
	var waddle := rig.gait.out_roll * 1.5
	for f in [flip_l, flip_r]:
		var sd := -1.0 if f == flip_l else 1.0
		var ang := -sd * (0.15 + out * 1.1 + flap * (0.9 + 0.6 * sin(rig.time * 22.0)) + waddle * sd * 0.5)
		rig.skel.rot[f] = Quaternion(Vector3.BACK, ang) * Quaternion(Vector3.UP, out * 0.4 * sd)
		rig.skel.fk_list(rig.motor.skel_subtree(f))


func sound_for(_action: StringName, _event: StringName) -> StringName:
	return &""
