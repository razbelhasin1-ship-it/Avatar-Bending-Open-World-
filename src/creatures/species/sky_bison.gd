extends CreatureSpecies
## Sky bison (Air companion): ~7.5 m long, ~4 m tall, six stubby legs under a huge
## fluffy cream body, brown arrow from the forehead down the back to the broad flat
## beaver tail, small curved horns, floppy ears, gentle face. Ground: lumbering
## six-leg wave gait (walk) and tripod trot (run). Flight: "swims" through the air with
## big slow vertical tail strokes, paddling legs, body undulation and banking.

const FUR := Color(0.97, 0.955, 0.92)
const FUR_SHADE := Color(0.64, 0.64, 0.86)
const ARROW := Color(0.47, 0.31, 0.18)
const HORN := Color(0.86, 0.74, 0.55)
const NOSE := Color(0.26, 0.17, 0.14)

var _stroke := 0.0
var _paddle := 0.0


func id() -> StringName:
	return &"sky_bison"


func can_fly() -> bool:
	return true


func _init() -> void:
	tune["sit_pitch"] = 0.22
	tune["sit_drop"] = 0.35
	tune["lie_drop"] = 1.05
	tune["rear_pitch"] = 0.42
	tune["neck_down"] = -0.42
	tune["head_up"] = 0.42
	tune["shake_roll"] = 0.12
	tune["bite_reach"] = 0.4
	tune["flight_blend"] = 1.3
	tune["takeoff_leap"] = 0.7


func build(rig: CreatureRig) -> void:
	var s := rig.skel
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z) * k
	s.add(&"root", &"", Vector3.ZERO)
	s.add(&"pelvis", &"root", v.call(0, 2.30, 1.70))
	s.add(&"spine1", &"pelvis", v.call(0, 2.40, 0.50))
	s.add(&"spine2", &"spine1", v.call(0, 2.45, -0.60))
	s.add(&"chest", &"spine2", v.call(0, 2.40, -1.60))
	s.add(&"neck", &"chest", v.call(0, 2.50, -2.15))
	s.add(&"head", &"neck", v.call(0, 2.60, -2.50))
	s.add(&"jaw", &"head", v.call(0, 2.24, -2.80))
	s.add(&"ear_l", &"head", v.call(-1.02, 2.98, -2.62))
	s.add(&"ear_r", &"head", v.call(1.02, 2.98, -2.62))
	s.add(&"eye_l", &"head", v.call(-0.52, 2.88, -3.55))
	s.add(&"eye_r", &"head", v.call(0.52, 2.88, -3.55))
	s.add(&"lid_l", &"head", v.call(-0.52, 2.88, -3.55))
	s.add(&"lid_r", &"head", v.call(0.52, 2.88, -3.55))
	s.add(&"tail1", &"pelvis", v.call(0, 2.50, 2.30))
	s.add(&"tail2", &"tail1", v.call(0, 2.38, 2.98))
	s.add(&"tail3", &"tail2", v.call(0, 2.2, 3.75))
	# Six legs: front (chest), middle (spine1), hind (pelvis).
	var rows := [["f", -1.45, &"chest", CreatureLeg.Group.FRONT], ["m", 0.05, &"spine1", CreatureLeg.Group.MIDDLE],
			["h", 1.55, &"pelvis", CreatureLeg.Group.HIND]]
	for row: Array in rows:
		for side in [-1.0, 1.0]:
			var sx: String = "l" if side < 0.0 else "r"
			var pre: String = row[0] + "l_"
			var z: float = row[1]
			var knee_back: bool = row[3] != CreatureLeg.Group.HIND
			s.add(StringName(pre + "upper_" + sx), row[2], v.call(1.10 * side, 1.65, z))
			s.add(StringName(pre + "lower_" + sx), StringName(pre + "upper_" + sx), v.call(1.18 * side, 0.95, z + (0.2 if knee_back else -0.2)))
			s.add(StringName(pre + "foot_" + sx), StringName(pre + "lower_" + sx), v.call(1.18 * side, 0.30, z))
	for row: Array in rows:
		for side in [-1.0, 1.0]:
			var sx: String = "l" if side < 0.0 else "r"
			var pre: String = row[0] + "l_"
			var l := CreatureLeg.new()
			var fp := s.rest_pos[s.idx(StringName(pre + "foot_" + sx))]
			l.setup(s, StringName(pre + sx), [StringName(pre + "upper_" + sx), StringName(pre + "lower_" + sx),
					StringName(pre + "foot_" + sx)], Vector3(fp.x, 0.0, fp.z - 0.05 * k))
			l.group = row[3]
			l.knee_dir = Vector3.FORWARD if l.group == CreatureLeg.Group.HIND else Vector3.BACK
			l.paw_size = 0.9 * k
			l.weight = 1.0
			l.curl = 0.35
			l.lift_scale = 1.0
			l.tuck = Vector3(0.05 * side, -0.85, 0.15 if l.group == CreatureLeg.Group.HIND else -0.1) * k
			rig.legs.append(l)
	var m := rig.motor
	m.root = s.idx(&"root")
	m.pelvis = s.idx(&"pelvis")
	m.spine = PackedInt32Array([s.idx(&"spine1"), s.idx(&"spine2"), s.idx(&"chest")])
	m.neck = PackedInt32Array([s.idx(&"neck")])
	m.neck_weights = PackedFloat32Array([0.8])
	m.head = s.idx(&"head")
	m.jaw = s.idx(&"jaw")
	m.tail = PackedInt32Array([s.idx(&"tail1"), s.idx(&"tail2"), s.idx(&"tail3")])
	m.ear_l = s.idx(&"ear_l")
	m.ear_r = s.idx(&"ear_r")
	m.eye_l = s.idx(&"eye_l")
	m.eye_r = s.idx(&"eye_r")
	m.lid_l = s.idx(&"lid_l")
	m.lid_r = s.idx(&"lid_r")
	m.breath_bones = PackedInt32Array([s.idx(&"spine1"), s.idx(&"spine2"), s.idx(&"chest")])
	m.breath_scale = Vector3(0.018, 0.02, 0.006)
	m.hind_z = 1.55 * k
	m.front_z = -1.45 * k
	m.head_stab = 0.55
	m.jaw_open = 0.45
	m.lid_open = 1.05
	m.lid_closed = -0.32
	m.look_yaw_limit = 0.9
	m.look_neck_share = 0.45
	m.ear_flop = 0.0
	var tail_spring := SpringChain.new().setup(s, m.tail, v.call(0, 2.0, 4.7))
	tail_spring.stiffness = 30.0
	tail_spring.damping = 8.0
	tail_spring.falloff = 0.9
	m.springs.append(tail_spring)
	for en: StringName in [&"ear_l", &"ear_r"]:
		var sd := -1.0 if en == &"ear_l" else 1.0
		var e := SpringChain.new().setup(s, PackedInt32Array([s.idx(en)]), v.call(1.32 * sd, 2.6, -2.58))
		e.stiffness = 70.0
		e.damping = 6.0
		e.gravity = Vector3(0, -3.0, 0)
		m.springs.append(e)
	# Legs: 0 FL, 1 FR, 2 ML, 3 MR, 4 HL, 5 HR.
	rig.gaits.append(GaitEngine.make_gait({"name": &"walk", "max_speed": 2.6 * sqrt(k), "duty": 0.72,
			"offsets": [0.33, 0.83, 0.17, 0.67, 0.0, 0.5], "freq": 0.72, "ref_speed": 1.6 * sqrt(k),
			"lift": 0.32 * k, "bob": 0.06, "bob_mult": 2.0, "bob_phase": 0.15, "roll": 0.05, "roll_phase": 0.1,
			"sway": 0.06, "head_bob": 0.02, "spine_yaw": 0.03, "spine_yaw_phase": 0.35}))
	rig.gaits.append(GaitEngine.make_gait({"name": &"run", "duty": 0.5,
			"offsets": [0.0, 0.5, 0.5, 0.0, 0.0, 0.5], "freq": 1.2, "ref_speed": 4.8 * sqrt(k),
			"lift": 0.5 * k, "bob": 0.12, "bob_mult": 2.0, "bob_phase": 0.2, "roll": 0.035, "pitch": 0.025,
			"head_bob": 0.03}))
	rig.gait.tempo = sqrt(k)
	rig.gait.settle_tolerance = 0.2
	rig.breath_period = 5.0
	rig.add_socket(&"saddle", &"head", Transform3D(Basis.IDENTITY, v.call(0, 1.0, -0.05)))
	rig.add_socket(&"back", &"spine2", Transform3D(Basis.IDENTITY, v.call(0, 1.62, 0.1)))
	rig.add_socket(&"rider_left", &"spine2", Transform3D(Basis.IDENTITY, v.call(-0.75, 1.55, 0.35)))
	rig.add_socket(&"rider_right", &"spine2", Transform3D(Basis.IDENTITY, v.call(0.75, 1.55, 0.35)))
	rig.add_socket(&"head", &"head", Transform3D(Basis.IDENTITY, v.call(0, 0.25, -0.85)))
	rig.add_socket(&"mouth", &"jaw", Transform3D(Basis.IDENTITY, v.call(0, 0.02, -0.62)))
	rig.add_socket(&"chest", &"chest", Transform3D(Basis.IDENTITY, v.call(0, -0.9, -0.5)))
	rig.add_socket(&"tail", &"tail3", Transform3D(Basis.IDENTITY, v.call(0, -0.1, 0.6)))
	rig.set_dimensions({
		"length": 8.0 * k, "height": 4.0 * k, "width": 3.8 * k, "saddle_height": 3.6 * k,
		"paw_size": 0.9 * k, "weight": 1.0, "can_fly": true, "walk_speed": 1.6 * sqrt(k),
		"run_speed": 4.8 * sqrt(k), "sprint_speed": 6.5 * sqrt(k), "fly_speed": 22.0,
		"collision_radius": 1.8 * k, "collision_height": 4.0 * k, "mass": 9000.0 * k * k * k,
	})


func build_mesh(rig: CreatureRig, kit: MeshKit) -> void:
	var s := rig.skel
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z) * k
	var fur := color("fur", FUR)
	var head_w := s.rigid_weighter(&"head")
	kit.surface(&"fur")
	# Huge fluffy body, rump -> chest; the shaggy lower half hangs around the legs.
	var body := [
		{"p": v.call(0, 2.44, 2.64), "w": 0.92 * k, "h": 0.82 * k, "hb": 0.86 * k, "f": 0.5},
		{"p": v.call(0, 2.47, 2.28), "w": 1.52 * k, "h": 1.24 * k, "hb": 1.36 * k},
		{"p": v.call(0, 2.48, 1.40), "w": 1.82 * k, "h": 1.45 * k, "hb": 1.60 * k},
		{"p": v.call(0, 2.48, 0.30), "w": 1.90 * k, "h": 1.50 * k, "hb": 1.64 * k},
		{"p": v.call(0, 2.47, -0.90), "w": 1.84 * k, "h": 1.47 * k, "hb": 1.62 * k},
		{"p": v.call(0, 2.48, -1.80), "w": 1.62 * k, "h": 1.31 * k, "hb": 1.50 * k, "f": 1.3},
		{"p": v.call(0, 2.54, -2.32), "w": 1.30 * k, "h": 1.06 * k, "hb": 1.22 * k, "f": 1.6},
	]
	kit.loft(body, {"segs": 36, "sub": 3, "color": fur, "fluff": 0.05, "lobes": 23.0, "fluff_freq": 1.4, "fluff_lo": 2.2,
			"cap1": "round", "cap_len": 0.5, "seed": 21, "mark_row": 1,
			"weights": s.chain_weighter([&"pelvis", &"spine1", &"spine2", &"chest"], v.call(0, 2.5, -2.3))})
	# Fluffy collar where the head meets the body.
	var ruff := [
		{"p": v.call(0, 2.56, -1.95), "w": 1.36 * k, "h": 1.14 * k, "hb": 1.0 * k},
		{"p": v.call(0, 2.60, -2.32), "w": 1.36 * k, "h": 1.10 * k, "hb": 0.98 * k, "f": 1.6},
		{"p": v.call(0, 2.63, -2.62), "w": 1.16 * k, "h": 0.95 * k, "hb": 0.85 * k},
	]
	kit.loft(ruff, {"segs": 32, "sub": 3, "color": fur, "fluff": 0.075, "lobes": 21.0, "cap0": "none", "cap1": "round", "cap_len": 0.35,
			"seed": 23, "mark_row": 4, "weights": s.chain_weighter([&"chest", &"neck", &"head"], v.call(0, 2.6, -2.9))})
	# Head: broad, flat friendly face.
	var head := [
		{"p": v.call(0, 2.64, -2.30), "w": 1.04 * k, "h": 0.9 * k},
		{"p": v.call(0, 2.66, -2.70), "w": 1.15 * k, "h": 0.9 * k, "hb": 0.86 * k, "f": 1.5},
		{"p": v.call(0, 2.63, -3.05), "w": 1.05 * k, "h": 0.76 * k, "hb": 0.7 * k, "f": 0.8},
		{"p": v.call(0, 2.58, -3.33), "w": 0.92 * k, "h": 0.6 * k, "hb": 0.5 * k, "f": 0.2},
		{"p": v.call(0, 2.55, -3.50), "w": 0.78 * k, "h": 0.5 * k, "hb": 0.42 * k, "f": 0.0},
	]
	kit.loft(head, {"segs": 34, "sub": 3, "color": fur, "fluff": 0.05, "lobes": 17.0, "cap0": "round", "cap1": "round",
			"cap_len": 0.36, "seed": 25, "mark_row": 2, "fur": 0.4, "weights": head_w})
	# Upper lip pad under the nose.
	kit.ellipsoid(v.call(0, 2.43, -3.6), Vector3(0.6, 0.24, 0.22) * k, {"color": fur, "fur": 0.25, "weights": head_w,
			"rings": 10, "segs": 20, "mark_row": 0})
	# Chin / lower jaw.
	var jaw := [
		{"p": v.call(0, 2.22, -2.85), "w": 0.62 * k, "h": 0.12 * k, "hb": 0.2 * k},
		{"p": v.call(0, 2.18, -3.25), "w": 0.56 * k, "h": 0.1 * k, "hb": 0.17 * k},
		{"p": v.call(0, 2.17, -3.55), "w": 0.42 * k, "h": 0.08 * k, "hb": 0.13 * k},
	]
	kit.loft(jaw, {"segs": 20, "sub": 2, "color": fur, "fur": 0.35, "weights": s.rigid_weighter(&"jaw"), "cap1": "round", "cap_len": 0.6})
	# Brow tufts give the face its gentle expression.
	for side in [-1.0, 1.0]:
		kit.ellipsoid(v.call(0.5 * side, 3.04, -3.43), Vector3(0.24, 0.085, 0.14) * k, {"color": fur, "fur": 0.5,
				"weights": head_w, "rings": 8, "segs": 12}, Basis.from_euler(Vector3(0.3, 0.5 * side, -0.25 * side)))
	# Floppy ears hanging below the horns.
	for side in [-1.0, 1.0]:
		var en: StringName = &"ear_l" if side < 0.0 else &"ear_r"
		var b := s.rest_pos[s.idx(en)]
		CreatureParts.ear(kit, rig, en, b, b + v.call(0.18 * side, -0.16, 0.0), b + v.call(0.28 * side, -0.38, 0.02),
				Vector3(0.2, 0.19, 0.08) * k, 0.08 * k, {"color": fur, "segs": 14, "sub": 2, "fur": 0.5,
				"face": Vector3(side, 0.4, 0).normalized()})
	# Broad flat beaver tail, slightly drooping.
	var tail := [
		{"p": v.call(0, 2.5, 2.3), "w": 0.78 * k, "h": 0.48 * k},
		{"p": v.call(0, 2.38, 2.95), "w": 1.18 * k, "h": 0.3 * k, "n": 2.4},
		{"p": v.call(0, 2.2, 3.7), "w": 1.42 * k, "h": 0.22 * k, "n": 2.8},
		{"p": v.call(0, 2.05, 4.35), "w": 1.3 * k, "h": 0.17 * k, "n": 2.8},
		{"p": v.call(0, 2.0, 4.65), "w": 0.78 * k, "h": 0.13 * k, "n": 2.4},
	]
	kit.loft(tail, {"segs": 30, "sub": 3, "color": fur, "fluff": 0.05, "lobes": 19.0, "fluff_freq": 2.5, "cap1": "round",
			"cap_len": 0.45, "seed": 27, "mark_row": 3,
			"weights": s.chain_weighter([&"tail1", &"tail2", &"tail3"], v.call(0, 2.0, 4.7), 0.7)})
	# Six thick legs with big round feet.
	for l in rig.legs:
		CreatureParts.limb(kit, rig, l, [Vector2(0.45, 0.45) * k, Vector2(0.56, 0.56) * k, Vector2(0.48, 0.48) * k,
				Vector2(0.42, 0.4) * k], v.call(0, 0.2, 0.0),
				{"segs": 22, "sub": 3, "color": fur, "fluff": 0.07, "lobes": 9.0, "fluff_profile": [0.4, 1.0, 1.5, 0.4],
				"seed": 31 + l.index, "cap0": "none", "inset": 0.6})
		CreatureParts.paw(kit, rig, l, Vector3(0.46, 0.2, 0.48) * k, 3, 0.1 * k, {"color": fur, "segs": 18, "rings": 9, "fur": 0.4})
	# Horns.
	kit.surface(&"horn")
	for side in [-1.0, 1.0]:
		CreatureParts.horn(kit, rig, &"head", PackedVector3Array([v.call(0.62 * side, 3.34, -2.72), v.call(0.86 * side, 3.56, -2.78),
				v.call(0.98 * side, 3.78, -2.93), v.call(0.95 * side, 3.93, -3.13)]), 0.15 * k, {"sub": 4})
	# Nose pad with nostrils, mouth line.
	kit.surface(&"nose")
	kit.ellipsoid(v.call(0, 2.7, -3.71), Vector3(0.36, 0.16, 0.13) * k, {"weights": head_w,
			"color": Color(1, 1, 1, 0), "rings": 9, "segs": 18})
	kit.surface(&"mouth")
	for side in [-1.0, 1.0]:
		kit.ellipsoid(v.call(0.14 * side, 2.72, -3.82), Vector3(0.075, 0.045, 0.03) * k, {"weights": head_w,
				"color": Color(1, 1, 1, 0), "rings": 6, "segs": 10}, Basis.from_euler(Vector3(0, 0, 0.4 * side)))
	kit.ellipsoid(v.call(0, 2.33, -3.3), Vector3(0.4, 0.06, 0.28) * k, {"weights": head_w,
			"color": Color(1, 1, 1, 0), "rings": 8, "segs": 14})
	kit.surface(&"nose")
	kit.tube(PackedVector3Array([v.call(-0.58, 2.3, -3.42), v.call(-0.32, 2.21, -3.7), v.call(0.0, 2.2, -3.8),
			v.call(0.32, 2.21, -3.7), v.call(0.58, 2.3, -3.42)]), PackedFloat32Array([0.024 * k, 0.028 * k, 0.03 * k, 0.028 * k, 0.024 * k]),
			{"weights": head_w, "segs": 6, "sub": 3, "fur": 0.0, "cap0": "round"})
	# Eyes.
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		var look := Vector3(0.45 * side, 0.05, -1.0).normalized()
		CreatureParts.eye(kit, rig, StringName("eye_" + sx), StringName("lid_" + sx), 0.1 * k, look, &"fur", &"eye",
				Vector3(1.0, 1.08, 1.0), {"color": fur})
	kit.surface(&"fur")


func material_for(surface: StringName, detail: int, lod: int) -> Material:
	match surface:
		&"fur":
			return CreatureMaterials.skin("sky_bison/fur%d" % detail, color("fur", FUR), {
				"shade_tint": FUR_SHADE, "rim": 0.4, "pattern": CreatureMaterials.Pattern.FUR,
				"pattern_scale": 5.0, "pattern_strength": 0.08, "marks": _marks(), "mark_rows": 5,
				"mark_colors": [color("arrow", ARROW), color("arrow", ARROW), color("arrow", ARROW)],
				"outline_width": 1.35, "outline_push": 0.15, "mark_soft": 0.01,
				"shells": CreatureMaterials.shell_count(detail, lod),
				"fur": {"length": 0.12 * k, "density": 60.0 / k, "comb": Vector3(0, -0.4, 0.5), "strand_width": 0.75,
						"root_dark": 0.1, "tip_lighten": 0.04}})
		&"horn":
			return CreatureMaterials.hard("sky_bison/horn", color("horn", HORN), {"pattern": CreatureMaterials.Pattern.SMOOTH,
				"pattern_scale": 6.0, "pattern_strength": 0.1, "outline_width": 1.1})
		&"nose":
			return CreatureMaterials.hard("sky_bison/nose", NOSE, {"specular": 0.45, "outline_width": 1.0})
		&"mouth":
			return CreatureMaterials.hard("sky_bison/mouth", Color(0.12, 0.07, 0.07), {"outline": false})
		&"claw":
			return CreatureMaterials.hard("sky_bison/nail", Color(0.62, 0.55, 0.48), {"outline_width": 0.8})
		&"eye":
			return CreatureMaterials.eye("sky_bison/eye", {"iris": Color(0.12, 0.08, 0.06), "iris_inner": Color(0.3, 0.2, 0.14),
				"iris_size": 0.9, "pupil_size": 0.5})
	return CreatureMaterials.skin("sky_bison/default", FUR)


var _mark_tex: ImageTexture = null


func _marks() -> ImageTexture:
	if _mark_tex == null:
		_mark_tex = CreatureMaterials.mark_texture([
			{},
			# Body (rump -> chest): the arrow shaft along the spine.
			{"dorsal": [[0.0, 0.0], [0.03, 0.07], [0.12, 0.062], [0.9, 0.055], [1.0, 0.06]]},
			# Head (back -> face): shaft, then the arrowhead pointing at the nose.
			{"dorsal": [[0.0, 0.055], [0.34, 0.055], [0.35, 0.13], [0.52, 0.075], [0.74, 0.0], [1.0, 0.0]]},
			# Tail (root -> tip): brown top widening over the paddle.
			{"dorsal": [[0.0, 0.07], [0.25, 0.14], [0.6, 0.2], [0.9, 0.21], [1.0, 0.18]]},
			# Collar: the shaft continues over the ruff.
			{"dorsal": [[0.0, 0.06], [1.0, 0.055]]},
		])
	return _mark_tex


func idle_actions() -> Array[StringName]:
	return [&"look_around", &"ear_twitch", &"yawn", &"sniff", &"groan", &"look_around", &"lie_down", &"shake"]


func make_action(action_name: StringName, opts: Dictionary) -> CreatureAction:
	match action_name:
		&"groan":
			var g := CreatureAction.new(action_name, 2.4)
			g.add_event(0.5, &"vocal_start")
			g.add_event(2.0, &"vocal_end")
			return g
		&"takeoff":
			var t := CreatureAction.new(action_name, 2.2)
			t.roots = true
			t.blend_in = 0.25
			t.blend_out = 0.6
			t.add_event(0.7, &"leap")
			t.add_event(0.85, &"stroke")
			t.add_event(1.75, &"stroke")
			return t
		&"land":
			var l := CreatureAction.new(action_name, 1.9)
			l.blend_in = 0.4
			l.blend_out = 0.6
			l.add_event(0.2, &"stroke")
			l.add_event(1.25, &"touchdown")
			return l
	return super.make_action(action_name, opts)


func action_pose(rig: CreatureRig, a: CreatureAction, pose: CreaturePose) -> void:
	var w := a.weight
	match a.name:
		&"groan":
			var e := a.window(0.15, 0.9, 0.2)
			pose.neck_pitch += 0.25 * e * w
			pose.head_pitch += 0.3 * e * w
			pose.jaw += 0.7 * e * w * (0.85 + 0.15 * sin(a.t * 9.0))
			pose.eyes_narrow += 0.7 * e * w
			pose.ears_back += 0.4 * e * w
			return
		&"takeoff":
			var crouch := a.window(0.0, 0.42, 0.18)
			var leap := a.window(0.3, 0.75, 0.15)
			pose.body_y += (-0.45 * crouch) * k * w
			pose.body_pitch += (-0.05 * crouch + 0.16 * leap) * w
			pose.tail_pitch += (0.6 * crouch - 0.9 * leap) * w
			pose.head_pitch += (-0.1 * crouch + 0.15 * leap) * w
			pose.ears_back += leap * w
			pose.jaw += 0.3 * a.window(0.3, 0.6, 0.1) * w
			return
		&"land":
			var reach := a.window(0.1, 0.7, 0.2)
			var impact := a.window(0.62, 0.95, 0.12)
			pose.body_pitch += 0.14 * reach * w
			pose.tail_pitch += -0.7 * reach * w
			pose.body_y += -0.35 * impact * k * w
			pose.head_pitch += -0.1 * reach * w
			for l in rig.legs:
				pose.add_paw(l.index, Vector3(0, -0.3, -0.15) * k * reach * w)
			return
	super.action_pose(rig, a, pose)


func default_locomotion_pose(rig: CreatureRig, pose: CreaturePose) -> void:
	super.default_locomotion_pose(rig, pose)
	# Heavy, gentle creature: the tail drags low and sways with the walk.
	pose.tail_pitch += -0.22 - 0.12 * clampf(rig.gait.speed / maxf(rig.run_speed, 0.1), 0.0, 1.0)
	pose.tail_yaw += sin(rig.gait.phase * TAU) * 0.08 * rig.gait.motion_w


## Flight: big slow tail strokes drive the "swimming" motion; legs paddle at low
## speed and tuck at cruise; the body undulates opposite to the tail and banks.
func flight_pose(rig: CreatureRig, pose: CreaturePose, delta: float) -> void:
	var fw := rig.flight_w
	var vel := rig.flight_velocity if rig.flying else rig.velocity
	var spd := vel.length()
	var freq := (0.32 + spd * 0.012) / sqrt(k)
	var prev := _stroke
	_stroke = fmod(_stroke + delta * freq, 1.0)
	if rig.sounds and fw > 0.6 and prev < 0.25 and _stroke >= 0.25 and rig.lod <= 1 and rig.is_inside_tree():
		Audio.play_sfx(&"wing_flap_large", rig.global_position + rig.global_basis.z * 3.5 * k, -6.0, 0.1, 180.0)
	var ph := _stroke * TAU
	var amp := 0.5 + clampf(spd / 30.0, 0.0, 0.25)
	pose.tail_pitch += fw * amp * sin(ph)
	pose.spine_pitch += fw * 0.05 * sin(ph - 1.3)
	pose.body_pitch += fw * (rig.flight_pitch * 0.85 + 0.035 * sin(ph - 2.4))
	pose.body_roll += fw * rig.flight_bank * 0.9
	pose.body_y += fw * 0.12 * sin(ph - 2.0) * k
	pose.spine_yaw += fw * rig.flight_bank * 0.15
	pose.head_pitch += fw * (-rig.flight_pitch * 0.5 + 0.04)
	pose.head_roll += fw * -rig.flight_bank * 0.35
	pose.ears_back += fw * 0.8
	pose.head_stab += fw * 0.2
	# Paddling legs: fast at low speed, folded at cruise.
	var paddle := clampf(1.0 - spd / 14.0, 0.15, 1.0)
	_paddle = fmod(_paddle + delta * (0.6 + 0.6 * paddle), 1.0)
	for l in rig.legs:
		var lp := _paddle * TAU + float(l.index) * 1.3 + (PI if l.side > 0.0 else 0.0)
		var reach := l.reach()
		pose.add_paw(l.index, Vector3(0.0, 0.2 * sin(lp), 0.35 * cos(lp)) * reach * paddle * fw)
		pose.add_paw(l.index, Vector3(0.0, 0.25, 0.25) * reach * (1.0 - paddle) * fw)


func sound_for(action: StringName, event: StringName) -> StringName:
	match event:
		&"vocal_start":
			return &"bison_groan" if action == &"groan" else &"bison_call"
		&"stroke", &"leap":
			return &"wing_flap_large"
		&"touchdown":
			return &"land_heavy"
	return &""
