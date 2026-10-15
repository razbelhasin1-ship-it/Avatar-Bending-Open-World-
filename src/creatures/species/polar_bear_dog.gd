extends CreatureSpecies
## Polar bear dog (Water companion): a massive white dog-bear, ~3 m nose to rump,
## ~1.8 m at the withers. Digitigrade legs with big paws, thick neck ruff, dog head
## with small rounded ears and a black nose, plumed tail. Gaits: walk, trot, gallop;
## actions: sit, lie_down, shake, howl, bark, growl, sniff, scratch + shared ones.

const FUR := Color(0.95, 0.95, 0.96)
const FUR_SHADE := Color(0.60, 0.68, 0.88)
const CREAM := Color(0.93, 0.90, 0.80)
const HEAD_ORIGIN := Vector3(0, 2.0, -1.34)
const HEAD_SCALE := 1.13


func id() -> StringName:
	return &"polar_bear_dog"


func _init() -> void:
	tune["sit_pitch"] = 0.48
	tune["sit_drop"] = 0.12
	tune["lie_drop"] = 0.78
	tune["neck_down"] = -0.95
	tune["head_up"] = 0.6
	tune["bite_reach"] = 0.45


## Head-local point: authored around HEAD_ORIGIN, enlarged by HEAD_SCALE.
func hp(x: float, y: float, z: float) -> Vector3:
	return (HEAD_ORIGIN + (Vector3(x, y, z) - HEAD_ORIGIN) * HEAD_SCALE) * k


func build(rig: CreatureRig) -> void:
	var s := rig.skel
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z) * k
	s.add(&"root", &"", Vector3.ZERO)
	s.add(&"pelvis", &"root", v.call(0, 1.30, 0.60))
	s.add(&"spine1", &"pelvis", v.call(0, 1.35, 0.20))
	s.add(&"spine2", &"spine1", v.call(0, 1.40, -0.20))
	s.add(&"chest", &"spine2", v.call(0, 1.38, -0.60))
	s.add(&"neck1", &"chest", v.call(0, 1.55, -0.92))
	s.add(&"neck2", &"neck1", v.call(0, 1.80, -1.14))
	s.add(&"head", &"neck2", v.call(0, 2.00, -1.34))
	s.add(&"jaw", &"head", hp(0, 1.9, -1.4))
	s.add(&"ear_l", &"head", hp(-0.22, 2.27, -1.27))
	s.add(&"ear_r", &"head", hp(0.22, 2.27, -1.27))
	s.add(&"eye_l", &"head", hp(-0.208, 2.118, -1.53))
	s.add(&"eye_r", &"head", hp(0.208, 2.118, -1.53))
	s.add(&"lid_l", &"head", hp(-0.208, 2.118, -1.53))
	s.add(&"lid_r", &"head", hp(0.208, 2.118, -1.53))
	s.add(&"tail1", &"pelvis", v.call(0, 1.48, 0.98))
	s.add(&"tail2", &"tail1", v.call(0, 1.42, 1.22))
	s.add(&"tail3", &"tail2", v.call(0, 1.26, 1.45))
	s.add(&"tail4", &"tail3", v.call(0, 1.05, 1.60))
	for side in [-1.0, 1.0]:
		var sx: String = "l" if side < 0.0 else "r"
		s.add(StringName("fl_upper_" + sx), &"chest", v.call(0.40 * side, 1.28, -0.60))
		s.add(StringName("fl_lower_" + sx), StringName("fl_upper_" + sx), v.call(0.42 * side, 0.82, -0.44))
		s.add(StringName("fl_meta_" + sx), StringName("fl_lower_" + sx), v.call(0.42 * side, 0.27, -0.62))
		s.add(StringName("fl_foot_" + sx), StringName("fl_meta_" + sx), v.call(0.42 * side, 0.10, -0.68))
	for side in [-1.0, 1.0]:
		var sx: String = "l" if side < 0.0 else "r"
		s.add(StringName("hl_upper_" + sx), &"pelvis", v.call(0.38 * side, 1.30, 0.60))
		s.add(StringName("hl_lower_" + sx), StringName("hl_upper_" + sx), v.call(0.40 * side, 0.80, 0.38))
		s.add(StringName("hl_meta_" + sx), StringName("hl_lower_" + sx), v.call(0.40 * side, 0.43, 0.80))
		s.add(StringName("hl_foot_" + sx), StringName("hl_meta_" + sx), v.call(0.40 * side, 0.10, 0.72))
	# Legs: 0 FL, 1 FR, 2 HL, 3 HR.
	var order := [["fl", -1.0, CreatureLeg.Group.FRONT], ["fl", 1.0, CreatureLeg.Group.FRONT],
			["hl", -1.0, CreatureLeg.Group.HIND], ["hl", 1.0, CreatureLeg.Group.HIND]]
	for o: Array in order:
		var sx: String = "l" if float(o[1]) < 0.0 else "r"
		var pre: String = o[0]
		var l := CreatureLeg.new()
		var foot_p := s.rest_pos[s.idx(StringName(pre + "_foot_" + sx))]
		l.setup(s, StringName(pre + "_" + sx), [StringName(pre + "_upper_" + sx), StringName(pre + "_lower_" + sx),
				StringName(pre + "_meta_" + sx), StringName(pre + "_foot_" + sx)], Vector3(foot_p.x, 0.0, foot_p.z - 0.02 * k))
		l.group = o[2]
		l.knee_dir = Vector3.BACK if l.group == CreatureLeg.Group.FRONT else Vector3.FORWARD
		l.paw_size = 0.34 * k
		l.weight = 0.65
		l.curl = 0.9
		l.tuck = Vector3(0, -0.75, -0.25) * k if l.group == CreatureLeg.Group.FRONT else Vector3(0, -0.7, 0.35) * k
		rig.legs.append(l)
	var m := rig.motor
	m.root = s.idx(&"root")
	m.pelvis = s.idx(&"pelvis")
	m.spine = PackedInt32Array([s.idx(&"spine1"), s.idx(&"spine2"), s.idx(&"chest")])
	m.neck = PackedInt32Array([s.idx(&"neck1"), s.idx(&"neck2")])
	m.neck_weights = PackedFloat32Array([0.55, 0.45])
	m.head = s.idx(&"head")
	m.jaw = s.idx(&"jaw")
	m.tail = PackedInt32Array([s.idx(&"tail1"), s.idx(&"tail2"), s.idx(&"tail3"), s.idx(&"tail4")])
	m.ear_l = s.idx(&"ear_l")
	m.ear_r = s.idx(&"ear_r")
	m.eye_l = s.idx(&"eye_l")
	m.eye_r = s.idx(&"eye_r")
	m.lid_l = s.idx(&"lid_l")
	m.lid_r = s.idx(&"lid_r")
	m.breath_bones = PackedInt32Array([s.idx(&"spine2"), s.idx(&"chest")])
	m.hind_z = 0.6 * k
	m.front_z = -0.6 * k
	m.head_stab = 0.6
	m.jaw_open = 0.62
	m.lid_open = 1.15
	m.lid_closed = -0.3
	m.springs.append(SpringChain.new().setup(s, m.tail, v.call(0, 0.86, 1.70)))
	m.springs[0].stiffness = 38.0
	m.springs[0].damping = 7.5
	m.springs[0].falloff = 0.92
	m.springs[0].gravity = Vector3(0, -1.5, 0)
	var ear_l := SpringChain.new().setup(s, PackedInt32Array([s.idx(&"ear_l")]), hp(-0.28, 2.40, -1.26))
	var ear_r := SpringChain.new().setup(s, PackedInt32Array([s.idx(&"ear_r")]), hp(0.28, 2.40, -1.26))
	for e in [ear_l, ear_r]:
		e.stiffness = 140.0
		e.damping = 10.0
		m.springs.append(e)
	rig.gaits.append(GaitEngine.make_gait({"name": &"walk", "max_speed": 2.2 * sqrt(k), "duty": 0.68,
			"offsets": [0.25, 0.75, 0.0, 0.5], "freq": 1.0, "ref_speed": 1.6 * sqrt(k), "lift": 0.16 * k,
			"bob": 0.022, "bob_mult": 2.0, "roll": 0.02, "roll_phase": 0.25, "head_bob": 0.025,
			"spine_yaw": 0.04, "spine_yaw_phase": 0.25}))
	rig.gaits.append(GaitEngine.make_gait({"name": &"trot", "max_speed": 5.5 * sqrt(k), "duty": 0.5,
			"offsets": [0.0, 0.5, 0.5, 0.0], "freq": 1.55, "ref_speed": 3.8 * sqrt(k), "lift": 0.24 * k,
			"bob": 0.04, "bob_mult": 2.0, "bob_phase": 0.1, "head_bob": 0.03, "roll": 0.015}))
	rig.gaits.append(GaitEngine.make_gait({"name": &"gallop", "duty": 0.34,
			"offsets": [0.52, 0.62, 0.0, 0.1], "freq": 2.0, "ref_speed": 10.0 * sqrt(k), "lift": 0.36 * k,
			"bob": 0.11, "bob_mult": 1.0, "bob_phase": 0.3, "pitch": 0.09, "pitch_phase": 0.05,
			"spine_pitch": 0.16, "spine_pitch_phase": 0.55, "head_bob": 0.07}))
	rig.gait.tempo = sqrt(k)
	rig.breath_period = 3.6
	rig.add_socket(&"saddle", &"spine2", Transform3D(Basis.IDENTITY, v.call(0, 0.47, 0.05)))
	rig.add_socket(&"back", &"spine1", Transform3D(Basis.IDENTITY, v.call(0, 0.42, 0.0)))
	rig.add_socket(&"rider_left", &"spine2", Transform3D(Basis.IDENTITY, v.call(-0.62, 0.15, 0.05)))
	rig.add_socket(&"rider_right", &"spine2", Transform3D(Basis.IDENTITY, v.call(0.62, 0.15, 0.05)))
	rig.add_socket(&"head", &"head", Transform3D(Basis.IDENTITY, v.call(0, 0.12, -0.2)))
	rig.add_socket(&"mouth", &"jaw", Transform3D(Basis.IDENTITY, v.call(0, 0.04, -0.42)))
	rig.add_socket(&"chest", &"chest", Transform3D(Basis.IDENTITY, v.call(0, -0.25, -0.35)))
	rig.add_socket(&"tail", &"tail4", Transform3D.IDENTITY)
	rig.set_dimensions({
		"length": 3.0 * k, "height": 2.35 * k, "width": 1.3 * k, "saddle_height": 2.0 * k,
		"paw_size": 0.34 * k, "weight": 0.65, "can_fly": false, "walk_speed": 1.6 * sqrt(k),
		"run_speed": 4.5 * sqrt(k), "sprint_speed": 11.0 * sqrt(k), "fly_speed": 0.0,
		"collision_radius": 0.75 * k, "collision_height": 2.0 * k, "mass": 900.0 * k * k * k,
	})


func build_mesh(rig: CreatureRig, kit: MeshKit) -> void:
	var s := rig.skel
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z) * k
	var fur := color("fur", FUR)
	var fluff_o := {"fluff": 0.06, "lobes": 15.0, "fluff_freq": 3.0}
	kit.surface(&"fur")
	# Torso: rump -> chest. Massive, deep chest, broad back.
	var body := [
		{"p": v.call(0, 1.40, 1.04), "w": 0.30 * k, "h": 0.24 * k, "hb": 0.22 * k, "f": 0.6},
		{"p": v.call(0, 1.40, 0.86), "w": 0.52 * k, "h": 0.37 * k, "hb": 0.36 * k},
		{"p": v.call(0, 1.39, 0.55), "w": 0.60 * k, "h": 0.40 * k, "hb": 0.41 * k},
		{"p": v.call(0, 1.40, 0.15), "w": 0.58 * k, "h": 0.40 * k, "hb": 0.38 * k},
		{"p": v.call(0, 1.41, -0.25), "w": 0.64 * k, "h": 0.45 * k, "hb": 0.50 * k},
		{"p": v.call(0, 1.39, -0.60), "w": 0.68 * k, "h": 0.47 * k, "hb": 0.58 * k, "f": 1.4},
		{"p": v.call(0, 1.44, -0.88), "w": 0.56 * k, "h": 0.41 * k, "hb": 0.52 * k, "f": 1.7},
		{"p": v.call(0, 1.53, -1.02), "w": 0.40 * k, "h": 0.32 * k, "hb": 0.36 * k},
	]
	var o := fluff_o.duplicate()
	o.merge({"segs": 28, "sub": 3, "color": fur, "seed": 3, "mark_row": 1,
			"weights": s.chain_weighter([&"pelvis", &"spine1", &"spine2", &"chest"], v.call(0, 1.42, -1.0))})
	kit.loft(body, o)
	# Neck with a thick ruff.
	var neck := [
		{"p": v.call(0, 1.50, -0.72), "w": 0.44 * k, "h": 0.42 * k},
		{"p": v.call(0, 1.68, -0.98), "w": 0.46 * k, "h": 0.40 * k, "hb": 0.46 * k, "f": 1.9},
		{"p": v.call(0, 1.88, -1.17), "w": 0.38 * k, "h": 0.32 * k, "hb": 0.37 * k, "f": 1.7},
		{"p": v.call(0, 2.02, -1.28), "w": 0.29 * k, "h": 0.25 * k},
	]
	o = fluff_o.duplicate()
	o.merge({"segs": 24, "sub": 3, "color": fur, "cap0": "round", "cap1": "round", "cap_len": 0.5, "seed": 5, "fluff": 0.1,
			"weights": s.chain_weighter([&"chest", &"neck1", &"neck2", &"head"], v.call(0, 2.0, -1.4))})
	kit.loft(neck, o)
	# Head: broad bear-like skull, short strong muzzle.
	var head := [
		{"p": hp(0, 2.06, -1.17), "w": 0.24 * k * HEAD_SCALE, "h": 0.21 * k * HEAD_SCALE, "f": 1.2},
		{"p": hp(0, 2.08, -1.29), "w": 0.34 * k * HEAD_SCALE, "h": 0.26 * k * HEAD_SCALE, "hb": 0.27 * k * HEAD_SCALE, "f": 1.7},
		{"p": hp(0, 2.06, -1.45), "w": 0.31 * k * HEAD_SCALE, "h": 0.22 * k * HEAD_SCALE, "hb": 0.25 * k * HEAD_SCALE, "f": 0.6},
		{"p": hp(0, 2.005, -1.58), "w": 0.225 * k * HEAD_SCALE, "h": 0.155 * k * HEAD_SCALE, "hb": 0.19 * k * HEAD_SCALE, "f": 0.0},
		{"p": hp(0, 1.97, -1.73), "w": 0.175 * k * HEAD_SCALE, "h": 0.122 * k * HEAD_SCALE, "hb": 0.13 * k * HEAD_SCALE, "f": 0.0},
		{"p": hp(0, 1.962, -1.83), "w": 0.148 * k * HEAD_SCALE, "h": 0.105 * k * HEAD_SCALE, "hb": 0.11 * k * HEAD_SCALE, "f": 0.0},
	]
	kit.loft(head, {"segs": 26, "sub": 3, "color": fur, "cap1": "round", "cap_len": 0.55, "fluff": 0.05,
			"lobes": 13.0, "weights": s.rigid_weighter(&"head"), "mark_row": 2, "seed": 9, "fur": 0.3})
	# Lower jaw.
	var jaw := [
		{"p": hp(0, 1.90, -1.40), "w": 0.17 * k * HEAD_SCALE, "h": 0.06 * k * HEAD_SCALE, "hb": 0.10 * k * HEAD_SCALE},
		{"p": hp(0, 1.875, -1.62), "w": 0.145 * k * HEAD_SCALE, "h": 0.05 * k * HEAD_SCALE, "hb": 0.08 * k * HEAD_SCALE},
		{"p": hp(0, 1.87, -1.79), "w": 0.105 * k * HEAD_SCALE, "h": 0.04 * k * HEAD_SCALE, "hb": 0.06 * k * HEAD_SCALE},
	]
	kit.loft(jaw, {"segs": 16, "sub": 2, "color": fur, "weights": s.rigid_weighter(&"jaw"), "fur": 0.35, "mark_row": 2})
	# Ears: small and rounded, bear-like.
	for side in [-1.0, 1.0]:
		var en: StringName = &"ear_l" if side < 0.0 else &"ear_r"
		var b := s.rest_pos[s.idx(en)]
		CreatureParts.ear(kit, rig, en, b - Vector3(0.0, 0.05, 0) * k * HEAD_SCALE, b + Vector3(0.035 * side, 0.07, 0.0) * k * HEAD_SCALE,
				b + Vector3(0.06 * side, 0.13, 0.01) * k * HEAD_SCALE,
				Vector3(0.11, 0.1, 0.06) * k * HEAD_SCALE, 0.04 * k * HEAD_SCALE, {"color": fur, "segs": 12, "sub": 2, "fur": 0.5,
				"face": Vector3(0.35 * side, 0, -1).normalized()})
	# Tail: big plume.
	var tail := [
		{"p": v.call(0, 1.48, 0.92), "w": 0.15 * k, "h": 0.15 * k},
		{"p": v.call(0, 1.44, 1.20), "w": 0.20 * k, "h": 0.20 * k},
		{"p": v.call(0, 1.27, 1.45), "w": 0.22 * k, "h": 0.21 * k},
		{"p": v.call(0, 1.05, 1.60), "w": 0.17 * k, "h": 0.16 * k},
		{"p": v.call(0, 0.86, 1.69), "w": 0.08 * k, "h": 0.08 * k},
	]
	kit.loft(tail, {"segs": 16, "sub": 3, "color": fur, "fluff": 0.24, "lobes": 7.0, "fluff_freq": 5.0, "cap1": "point",
			"weights": s.chain_weighter([&"tail1", &"tail2", &"tail3", &"tail4"], v.call(0, 0.86, 1.70), 0.8), "seed": 11})
	# Legs: thick furry columns, big paws.
	for l in rig.legs:
		if l.group == CreatureLeg.Group.FRONT:
			CreatureParts.limb(kit, rig, l, [Vector2(0.2, 0.24) * k, Vector2(0.26, 0.29) * k, Vector2(0.2, 0.21) * k,
					Vector2(0.15, 0.15) * k, Vector2(0.14, 0.13) * k], v.call(0, 0.15, 0.0),
					{"segs": 18, "sub": 3, "color": fur, "fluff": 0.09, "lobes": 7.0, "fluff_profile": [0.5, 1.4, 1.1, 0.5, 0.3], "seed": 13, "cap0": "none"})
			CreatureParts.paw(kit, rig, l, Vector3(0.16, 0.095, 0.19) * k, 4, 0.07 * k, {"color": fur, "segs": 16, "rings": 9, "fur": 0.45})
		else:
			CreatureParts.limb(kit, rig, l, [Vector2(0.22, 0.28) * k, Vector2(0.29, 0.34) * k, Vector2(0.21, 0.23) * k,
					Vector2(0.125, 0.13) * k, Vector2(0.13, 0.12) * k], v.call(0, 0.12, -0.04),
					{"segs": 18, "sub": 3, "color": fur, "fluff": 0.08, "lobes": 7.0, "fluff_profile": [0.5, 1.2, 0.9, 0.3, 0.2], "seed": 17, "cap0": "none"})
			CreatureParts.paw(kit, rig, l, Vector3(0.15, 0.09, 0.18) * k, 4, 0.065 * k, {"color": fur, "segs": 16, "rings": 9, "fur": 0.45})
	# Nose, mouth, teeth.
	kit.surface(&"nose")
	kit.ellipsoid(hp(0, 2.0, -1.875), Vector3(0.092, 0.064, 0.062) * k * HEAD_SCALE, {"weights": s.rigid_weighter(&"head"), "color": Color(1, 1, 1, 0), "rings": 9, "segs": 14})
	kit.surface(&"mouth")
	kit.ellipsoid(hp(0, 1.9, -1.58), Vector3(0.11, 0.05, 0.22) * k * HEAD_SCALE, {"weights": s.rigid_weighter(&"head"), "color": Color(1, 1, 1, 0), "rings": 8, "segs": 10})
	kit.surface(&"claw")
	CreatureParts.teeth(kit, rig, &"head", PackedVector3Array([hp(-0.085, 1.875, -1.79), hp(0.085, 1.875, -1.79)]), Vector3.DOWN, 0.065 * k, 0.019 * k)
	CreatureParts.teeth(kit, rig, &"jaw", PackedVector3Array([hp(-0.065, 1.9, -1.76), hp(0.065, 1.9, -1.76)]), Vector3.UP, 0.05 * k, 0.016 * k)
	# Eyes with dark rims, black lips.
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		var look := Vector3(0.55 * side, 0.06, -1.0).normalized()
		var ec := s.rest_pos[s.idx(StringName("eye_" + sx))]
		CreatureParts.eye(kit, rig, StringName("eye_" + sx), StringName("lid_" + sx), 0.064 * k,
				look, &"fur", &"eye", Vector3(1.0, 0.95, 1.0), {"color": fur})
		kit.surface(&"nose")
		kit.ellipsoid(ec - look * 0.014 * k, Vector3(0.078, 0.07, 0.055) * k, {"weights": s.rigid_weighter(&"head"),
				"color": Color(1, 1, 1, 0), "rings": 8, "segs": 12}, Basis.looking_at(look, Vector3.UP))
		kit.tube(PackedVector3Array([hp(0.19 * side, 1.89, -1.47), hp(0.168 * side, 1.862, -1.6), hp(0.135 * side, 1.856, -1.72), hp(0.07 * side, 1.86, -1.82)]),
				PackedFloat32Array([0.014 * k, 0.014 * k, 0.013 * k, 0.011 * k]), {"weights": s.rigid_weighter(&"head"), "segs": 6, "sub": 3, "fur": 0.0})
	kit.surface(&"fur")


func material_for(surface: StringName, detail: int, lod: int) -> Material:
	match surface:
		&"fur":
			var marks := _marks()
			return CreatureMaterials.skin("polar_bear_dog/fur%d" % detail, color("fur", FUR), {
				"shade_tint": FUR_SHADE, "rim": 0.45, "pattern": CreatureMaterials.Pattern.FUR,
				"pattern_scale": 9.0, "pattern_strength": 0.1, "marks": marks, "mark_rows": 3,
				"mark_colors": [CREAM, CREAM, CREAM], "outline_width": 1.35,
				"shells": CreatureMaterials.shell_count(detail, lod),
				"outline_push": 0.15, "fur": {"length": 0.075 * k, "density": 90.0 / k, "comb": Vector3(0, -0.3, 0.55),
				"strand_width": 0.7, "root_dark": 0.1, "tip_lighten": 0.05}})
		&"nose":
			return CreatureMaterials.hard("pbd/nose", Color(0.06, 0.06, 0.07), {"specular": 0.6, "specular_size": 0.25, "outline_width": 0.8})
		&"mouth":
			return CreatureMaterials.hard("pbd/mouth", Color(0.42, 0.12, 0.14), {"outline": false, "specular": 0.2})
		&"claw":
			return CreatureMaterials.hard("pbd/claw", Color(0.86, 0.84, 0.76), {"outline_width": 0.6})
		&"eye":
			return CreatureMaterials.eye("pbd/eye", {"iris": Color(0.17, 0.1, 0.06), "iris_inner": Color(0.38, 0.24, 0.12),
					"iris_size": 0.86, "pupil_size": 0.5})
	return CreatureMaterials.skin("pbd/default", FUR)


var _mark_tex: ImageTexture = null


func _marks() -> ImageTexture:
	if _mark_tex == null:
		_mark_tex = CreatureMaterials.mark_texture([
			{},
			# Body: soft cream belly.
			{"ventral": [[0.0, 0.0], [0.15, 0.12], [0.8, 0.14], [1.0, 0.1]]},
			# Head: cream muzzle underside.
			{"ventral": [[0.0, 0.0], [0.4, 0.0], [0.6, 0.18], [1.0, 0.22]]},
		])
	return _mark_tex


func idle_actions() -> Array[StringName]:
	return [&"look_around", &"sniff", &"ear_twitch", &"yawn", &"scratch", &"shake", &"sit", &"look_around"]


func make_action(action_name: StringName, opts: Dictionary) -> CreatureAction:
	var a := super.make_action(action_name, opts)
	if action_name == &"howl" and a != null:
		a.duration = 3.6
		a.roots = true
		a.events.clear()
		a.add_event(0.9, &"vocal_start").add_event(3.0, &"vocal_end")
	return a


func action_pose(rig: CreatureRig, a: CreatureAction, pose: CreaturePose) -> void:
	if a.name == &"howl":
		# Sits back and howls at the sky.
		var e := a.envelope(0.2, 0.15)
		var w := a.weight
		pose.pitch_pivot += 1.0 * w
		pose.body_pitch += tune["sit_pitch"] * e * w
		pose.body_y += -tune["sit_drop"] * k * e * w
		var song := a.window(0.25, 0.85, 0.08)
		pose.neck_pitch += 0.55 * song * w
		pose.head_pitch += 0.75 * song * w
		pose.jaw += (0.55 + 0.1 * sin(a.t * 5.0)) * song * w
		pose.eyes_narrow += 0.9 * song * w
		pose.ears_back += 0.7 * song * w
		pose.tail_pitch += -0.5 * e * w
		pose.head_stab += 0.3 * w
		return
	super.action_pose(rig, a, pose)


func default_locomotion_pose(rig: CreatureRig, pose: CreaturePose) -> void:
	super.default_locomotion_pose(rig, pose)
	# Happy tail: wags when walking toward something / idle, streams out when galloping.
	var spd := rig.gait.speed
	pose.tail_wag += 0.12 * (1.0 - clampf(spd / 4.0, 0.0, 1.0))
	pose.tail_wag_speed += 1.3
	# Plume hangs low when walking, streams out behind at a gallop.
	pose.tail_pitch += -0.45 + 0.45 * clampf((spd - 3.0) / 7.0, 0.0, 1.0)


func sound_for(action: StringName, event: StringName) -> StringName:
	if event != &"vocal_start":
		return &""
	match action:
		&"growl":
			return &"dog_growl"
		&"bark", &"howl", &"roar", &"call":
			return &"dog_bark"
	return &""
