extends CreatureSpecies
## Badgermole (Earth companion): ~4.6 m long, low and massive, grey-brown fur with a
## cream face stripe and dark eye mask, tiny blind eyes, long mole snout with a pink
## nose and huge front digging claws. Gaits: waddling walk and a bounding run.
## Actions: dig_in (hold: scoops and sinks underground, hidden while burrowed; moving
## while burrowed leaves a trail of dirt puffs), emerge (bursts out of the ground),
## rear_up, sniff, dig (idle scratch at the ground) + shared ones.

const FUR := Color(0.6, 0.54, 0.46)
const SHADE := Color(0.55, 0.52, 0.66)
const STRIPE := Color(0.93, 0.89, 0.79)
const MASK := Color(0.2, 0.17, 0.15)
const CLAW := Color(0.92, 0.88, 0.76)
const NOSE := Color(0.88, 0.55, 0.55)
const ZS := 0.85
## How deep the body sinks when burrowed (below every part of the mesh).
const BURROW_DEPTH := 3.2

var burrowed := false
var depth := 0.0
var _trail_dist := 0.0
var _last_pos := Vector3.ZERO
var _emerge_fx_done := false


func id() -> StringName:
	return &"badgermole"


func _init() -> void:
	tune["sit_pitch"] = 0.3
	tune["sit_drop"] = 0.1
	tune["lie_drop"] = 0.45
	tune["rear_pitch"] = 0.85
	tune["neck_down"] = -0.5
	tune["head_up"] = 0.45
	tune["bite_reach"] = 0.4
	tune["shake_roll"] = 0.15


func build(rig: CreatureRig) -> void:
	var s := rig.skel
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z * ZS) * k
	s.add(&"root", &"", Vector3.ZERO)
	s.add(&"pelvis", &"root", v.call(0, 1.05, 1.3))
	s.add(&"spine1", &"pelvis", v.call(0, 1.12, 0.5))
	s.add(&"spine2", &"spine1", v.call(0, 1.15, -0.3))
	s.add(&"chest", &"spine2", v.call(0, 1.12, -1.0))
	s.add(&"neck", &"chest", v.call(0, 1.12, -1.55))
	s.add(&"head", &"neck", v.call(0, 1.14, -1.9))
	s.add(&"jaw", &"head", v.call(0, 0.98, -2.12))
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		s.add(StringName("eye_" + sx), &"head", v.call(0.27 * side, 1.27, -2.3))
		s.add(StringName("lid_" + sx), &"head", v.call(0.27 * side, 1.27, -2.3))
	s.add(&"tail1", &"pelvis", v.call(0, 1.12, 1.95))
	s.add(&"tail2", &"tail1", v.call(0, 1.02, 2.3))
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		s.add(StringName("fl_upper_" + sx), &"chest", v.call(0.72 * side, 1.0, -1.0))
		s.add(StringName("fl_lower_" + sx), StringName("fl_upper_" + sx), v.call(0.95 * side, 0.58, -0.82))
		s.add(StringName("fl_foot_" + sx), StringName("fl_lower_" + sx), v.call(1.0 * side, 0.2, -1.1))
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		s.add(StringName("hl_upper_" + sx), &"pelvis", v.call(0.68 * side, 0.98, 1.25))
		s.add(StringName("hl_lower_" + sx), StringName("hl_upper_" + sx), v.call(0.84 * side, 0.55, 1.02))
		s.add(StringName("hl_foot_" + sx), StringName("hl_lower_" + sx), v.call(0.88 * side, 0.16, 1.3))
	var order := [["fl", -1.0, CreatureLeg.Group.FRONT], ["fl", 1.0, CreatureLeg.Group.FRONT],
			["hl", -1.0, CreatureLeg.Group.HIND], ["hl", 1.0, CreatureLeg.Group.HIND]]
	for o: Array in order:
		var sx: String = "l" if float(o[1]) < 0.0 else "r"
		var pre: String = o[0]
		var l := CreatureLeg.new()
		var fp := s.rest_pos[s.idx(StringName(pre + "_foot_" + sx))]
		l.setup(s, StringName(pre + "_" + sx), [StringName(pre + "_upper_" + sx), StringName(pre + "_lower_" + sx),
				StringName(pre + "_foot_" + sx)], Vector3(fp.x, 0.0, fp.z - 0.05 * k))
		l.group = o[2]
		var sd: float = o[1]
		l.knee_dir = Vector3(0.4 * sd, 0, 1).normalized() if l.group == CreatureLeg.Group.FRONT else Vector3(0.3 * sd, 0, -1).normalized()
		l.paw_size = (0.62 if l.group == CreatureLeg.Group.FRONT else 0.42) * k
		l.weight = 1.0
		l.curl = 0.3
		l.tuck = Vector3(0.1 * sd, -0.45, -0.15) * k if l.group == CreatureLeg.Group.FRONT else Vector3(0.05 * sd, -0.45, 0.2) * k
		rig.legs.append(l)
	var m := rig.motor
	m.root = s.idx(&"root")
	m.pelvis = s.idx(&"pelvis")
	m.spine = PackedInt32Array([s.idx(&"spine1"), s.idx(&"spine2"), s.idx(&"chest")])
	m.neck = PackedInt32Array([s.idx(&"neck")])
	m.neck_weights = PackedFloat32Array([0.7])
	m.head = s.idx(&"head")
	m.jaw = s.idx(&"jaw")
	m.tail = PackedInt32Array([s.idx(&"tail1"), s.idx(&"tail2")])
	m.eye_l = s.idx(&"eye_l")
	m.eye_r = s.idx(&"eye_r")
	m.lid_l = s.idx(&"lid_l")
	m.lid_r = s.idx(&"lid_r")
	m.lid_open = 0.35
	m.lid_closed = -0.3
	m.breath_bones = PackedInt32Array([s.idx(&"spine1"), s.idx(&"spine2"), s.idx(&"chest")])
	m.hind_z = 1.25 * ZS * k
	m.front_z = -1.0 * ZS * k
	m.head_stab = 0.45
	m.jaw_open = 0.45
	m.look_neck_share = 0.5
	var ts := SpringChain.new().setup(s, m.tail, v.call(0, 0.92, 2.55))
	ts.stiffness = 60.0
	ts.damping = 7.0
	m.springs.append(ts)
	rig.gaits.append(GaitEngine.make_gait({"name": &"walk", "max_speed": 2.4 * sqrt(k), "duty": 0.7,
			"offsets": [0.25, 0.75, 0.0, 0.5], "freq": 0.95, "ref_speed": 1.4 * sqrt(k), "lift": 0.2 * k,
			"bob": 0.025, "bob_mult": 2.0, "roll": 0.045, "roll_phase": 0.15, "sway": 0.04, "head_bob": 0.03,
			"spine_yaw": 0.05, "spine_yaw_phase": 0.25}))
	rig.gaits.append(GaitEngine.make_gait({"name": &"run", "duty": 0.4,
			"offsets": [0.5, 0.58, 0.0, 0.06], "freq": 1.9, "ref_speed": 6.5 * sqrt(k), "lift": 0.32 * k,
			"bob": 0.09, "bob_mult": 1.0, "bob_phase": 0.3, "pitch": 0.08, "spine_pitch": 0.12,
			"spine_pitch_phase": 0.55, "head_bob": 0.05}))
	rig.gait.tempo = sqrt(k)
	rig.breath_period = 4.0
	rig.add_socket(&"saddle", &"spine2", Transform3D(Basis.IDENTITY, v.call(0, 0.72, 0.0)))
	rig.add_socket(&"back", &"spine1", Transform3D(Basis.IDENTITY, v.call(0, 0.7, 0.0)))
	rig.add_socket(&"rider_left", &"spine2", Transform3D(Basis.IDENTITY, v.call(-1.0, 0.25, 0.0)))
	rig.add_socket(&"rider_right", &"spine2", Transform3D(Basis.IDENTITY, v.call(1.0, 0.25, 0.0)))
	rig.add_socket(&"head", &"head", Transform3D(Basis.IDENTITY, v.call(0, 0.1, -0.4)))
	rig.add_socket(&"mouth", &"jaw", Transform3D(Basis.IDENTITY, v.call(0, 0.0, -0.75)))
	rig.add_socket(&"chest", &"chest", Transform3D(Basis.IDENTITY, v.call(0, -0.4, -0.3)))
	rig.add_socket(&"tail", &"tail2", Transform3D.IDENTITY)
	rig.add_socket(&"claw_left", &"fl_foot_l", Transform3D(Basis.IDENTITY, v.call(0, -0.1, -0.35)))
	rig.add_socket(&"claw_right", &"fl_foot_r", Transform3D(Basis.IDENTITY, v.call(0, -0.1, -0.35)))
	rig.set_dimensions({
		"length": 4.6 * k, "height": 1.95 * k, "width": 2.4 * k, "saddle_height": 1.87 * k,
		"paw_size": 0.62 * k, "weight": 1.0, "can_fly": false, "walk_speed": 1.4 * sqrt(k),
		"run_speed": 6.5 * sqrt(k), "sprint_speed": 8.5 * sqrt(k), "fly_speed": 0.0,
		"collision_radius": 1.1 * k, "collision_height": 1.8 * k, "mass": 4000.0 * k * k * k,
	})


func build_mesh(rig: CreatureRig, kit: MeshKit) -> void:
	var s := rig.skel
	var v := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z * ZS) * k
	var fur := color("fur", FUR)
	var hw := s.rigid_weighter(&"head")
	kit.surface(&"fur")
	var body := [
		{"p": v.call(0, 1.1, 2.05), "w": 0.5 * k, "h": 0.42 * k, "hb": 0.4 * k},
		{"p": v.call(0, 1.13, 1.6), "w": 0.98 * k, "h": 0.6 * k, "hb": 0.55 * k},
		{"p": v.call(0, 1.14, 0.8), "w": 1.16 * k, "h": 0.64 * k, "hb": 0.6 * k},
		{"p": v.call(0, 1.14, -0.1), "w": 1.22 * k, "h": 0.66 * k, "hb": 0.62 * k},
		{"p": v.call(0, 1.13, -0.9), "w": 1.14 * k, "h": 0.62 * k, "hb": 0.6 * k, "f": 1.3},
		{"p": v.call(0, 1.13, -1.45), "w": 0.86 * k, "h": 0.52 * k, "hb": 0.52 * k, "f": 1.4},
		{"p": v.call(0, 1.13, -1.75), "w": 0.62 * k, "h": 0.42 * k, "hb": 0.42 * k},
	]
	kit.loft(body, {"segs": 30, "sub": 3, "color": fur, "fluff": 0.04, "lobes": 19.0, "fluff_lo": 2.0, "cap1": "round", "cap_len": 0.4,
			"seed": 41, "mark_row": 1, "weights": s.chain_weighter([&"pelvis", &"spine1", &"spine2", &"chest"], v.call(0, 1.12, -1.75))})
	var head := [
		{"p": v.call(0, 1.14, -1.55), "w": 0.6 * k, "h": 0.43 * k},
		{"p": v.call(0, 1.16, -1.95), "w": 0.56 * k, "h": 0.39 * k, "hb": 0.37 * k, "f": 1.3},
		{"p": v.call(0, 1.12, -2.3), "w": 0.4 * k, "h": 0.27 * k, "hb": 0.28 * k, "f": 0.5},
		{"p": v.call(0, 1.04, -2.65), "w": 0.24 * k, "h": 0.17 * k, "hb": 0.17 * k, "f": 0.0},
		{"p": v.call(0, 0.99, -2.97), "w": 0.14 * k, "h": 0.11 * k, "hb": 0.1 * k, "f": 0.0},
	]
	kit.loft(head, {"segs": 26, "sub": 3, "color": fur, "fluff": 0.04, "lobes": 15.0, "cap0": "round", "cap1": "round",
			"cap_len": 0.5, "seed": 43, "mark_row": 2, "fur": 0.45, "weights": hw})
	var jaw := [
		{"p": v.call(0, 0.98, -2.1), "w": 0.32 * k, "h": 0.05 * k, "hb": 0.11 * k},
		{"p": v.call(0, 0.93, -2.5), "w": 0.2 * k, "h": 0.04 * k, "hb": 0.08 * k},
		{"p": v.call(0, 0.91, -2.85), "w": 0.11 * k, "h": 0.03 * k, "hb": 0.05 * k},
	]
	kit.loft(jaw, {"segs": 16, "sub": 2, "color": fur, "fur": 0.3, "mark_row": 3, "weights": s.rigid_weighter(&"jaw")})
	# Tiny rounded ears tucked in the fur.
	for side in [-1.0, 1.0]:
		kit.ellipsoid(v.call(0.46 * side, 1.43, -1.78), Vector3(0.09, 0.07, 0.05) * k, {"color": fur.darkened(0.1), "weights": hw,
				"rings": 7, "segs": 10, "fur": 0.3}, Basis.from_euler(Vector3(0, 0.6 * side, 0)))
	# Short stubby tail.
	kit.loft([{"p": v.call(0, 1.14, 1.85), "w": 0.18 * k, "h": 0.16 * k}, {"p": v.call(0, 1.05, 2.25), "w": 0.14 * k, "h": 0.12 * k},
			{"p": v.call(0, 0.94, 2.5), "w": 0.06 * k, "h": 0.05 * k}],
			{"segs": 12, "sub": 2, "color": fur, "fluff": 0.12, "lobes": 6.0, "cap1": "point",
			"weights": s.chain_weighter([&"tail1", &"tail2"], v.call(0, 0.92, 2.55), 0.7)})
	# Legs: massive forelimbs with huge digging claws, smaller hind legs.
	for l in rig.legs:
		var front := l.group == CreatureLeg.Group.FRONT
		var r := [Vector2(0.32, 0.36), Vector2(0.38, 0.4), Vector2(0.3, 0.3), Vector2(0.24, 0.2)] if front \
				else [Vector2(0.3, 0.34), Vector2(0.34, 0.38), Vector2(0.24, 0.25), Vector2(0.19, 0.16)]
		var rr: Array = []
		for x: Vector2 in r:
			rr.append(x * k)
		CreatureParts.limb(kit, rig, l, rr, v.call(0, 0.12, 0.0), {"segs": 18, "sub": 3, "color": fur, "fluff": 0.06,
				"lobes": 8.0, "seed": 47 + l.index, "cap0": "none", "inset": 0.55, "fur": 0.8})
		if front:
			CreatureParts.paw(kit, rig, l, Vector3(0.3, 0.12, 0.32) * k, 4, 0.0, {"color": fur.darkened(0.15), "segs": 16, "rings": 8, "fur": 0.2})
			_claws(kit, rig, l, 0.55 * k)
		else:
			CreatureParts.paw(kit, rig, l, Vector3(0.22, 0.1, 0.25) * k, 4, 0.12 * k, {"color": fur.darkened(0.15), "segs": 14, "rings": 8, "fur": 0.2},
					&"claw", &"fur")
	# Pink mole nose with nostrils and whisker-like feelers.
	kit.surface(&"nose")
	kit.ellipsoid(v.call(0, 1.0, -3.08), Vector3(0.13, 0.1, 0.075) * k, {"weights": hw, "color": Color(1, 1, 1, 0), "rings": 9, "segs": 14})
	for i in 6:
		var a := float(i) / 6.0 * TAU
		var base: Vector3 = v.call(cos(a) * 0.1, 1.0 + sin(a) * 0.08, -3.1)
		var dir := Vector3(cos(a) * 0.6, sin(a) * 0.6, -1.0).normalized()
		kit.tube(PackedVector3Array([base, base + dir * 0.07 * k, base + dir * 0.13 * k]), PackedFloat32Array([0.022 * k, 0.018 * k, 0.008 * k]),
				{"weights": hw, "segs": 6, "sub": 1, "fur": 0.0})
	kit.surface(&"mouth")
	for side in [-1.0, 1.0]:
		kit.ellipsoid(v.call(0.05 * side, 1.0, -3.15), Vector3(0.025, 0.035, 0.02) * k, {"weights": hw, "rings": 6, "segs": 8, "fur": 0.0})
	kit.ellipsoid(v.call(0, 0.97, -2.5), Vector3(0.18, 0.04, 0.38) * k, {"weights": hw, "rings": 6, "segs": 10, "fur": 0.0})
	# Tiny, nearly closed eyes.
	for side in [-1.0, 1.0]:
		var sx := "l" if side < 0.0 else "r"
		CreatureParts.eye(kit, rig, StringName("eye_" + sx), StringName("lid_" + sx), 0.035 * k,
				Vector3(0.75 * side, 0.15, -1.0).normalized(), &"fur", &"eye", Vector3(1.3, 0.8, 1.0), {"color": MASK})
	kit.surface(&"fur")


func _claws(kit: MeshKit, rig: CreatureRig, l: CreatureLeg, length: float) -> void:
	var s := rig.skel
	var w := s.rigid_weighter(s.names[l.foot])
	var c := s.rest_pos[l.foot] + Vector3(0, -l.ankle_h + 0.1 * k, -0.25 * k)
	kit.surface(&"claw")
	for i in 4:
		var f := (float(i) - 1.5) / 1.5
		var base := c + Vector3(f * 0.2 * k, 0.04 * k, -0.08 * k * (1.0 - absf(f) * 0.4))
		var dir := Vector3(f * 0.12, -0.25, -1.0).normalized()
		var ln := length * (1.0 - absf(f) * 0.2)
		kit.tube(PackedVector3Array([base, base + dir * ln * 0.45 + Vector3(0, 0.05 * k, 0), base + dir * ln * 0.8 - Vector3(0, 0.02 * k, 0),
				base + dir * ln + Vector3(0, -0.12 * k, 0.05 * k)]),
				PackedFloat32Array([0.065 * k, 0.055 * k, 0.035 * k, 0.0]), {"weights": w, "segs": 8, "sub": 3, "fur": 0.0, "flatten": 0.35})
	kit.surface(&"fur")


func material_for(surface: StringName, detail: int, lod: int) -> Material:
	match surface:
		&"fur":
			return CreatureMaterials.skin("badgermole/fur%d" % detail, color("fur", FUR), {
				"shade_tint": SHADE, "rim": 0.35, "pattern": CreatureMaterials.Pattern.FUR, "pattern_scale": 7.0,
				"pattern_strength": 0.14, "marks": _marks(), "mark_rows": 4, "mark_colors": [STRIPE, STRIPE, MASK],
				"outline_width": 1.25, "outline_push": 0.15, "shells": CreatureMaterials.shell_count(detail, lod),
				"fur": {"length": 0.05 * k, "density": 85.0 / k, "comb": Vector3(0, -0.2, 0.6), "strand_width": 0.7,
						"root_dark": 0.12, "tip_lighten": 0.08}})
		&"claw":
			return CreatureMaterials.hard("badgermole/claw", CLAW, {"specular": 0.4, "outline_width": 1.0})
		&"nose":
			return CreatureMaterials.hard("badgermole/nose", NOSE, {"specular": 0.5, "rim": 0.3, "outline_width": 0.9})
		&"mouth":
			return CreatureMaterials.hard("badgermole/mouth", Color(0.25, 0.1, 0.1), {"outline": false})
		&"eye":
			return CreatureMaterials.eye("badgermole/eye", {"iris": Color(0.08, 0.06, 0.06), "iris_inner": Color(0.2, 0.15, 0.15),
				"sclera": Color(0.25, 0.2, 0.2), "iris_size": 0.9, "pupil_size": 0.3, "catchlight": 0.6})
	return CreatureMaterials.skin("badgermole/default", FUR)


var _mark_tex: ImageTexture = null


func _marks() -> ImageTexture:
	if _mark_tex == null:
		_mark_tex = CreatureMaterials.mark_texture([
			{},
			# Body: lighter belly, the face stripe runs onto the shoulders.
			{"ventral": [[0.0, 0.1], [0.5, 0.14], [1.0, 0.12]], "dorsal": [[0.0, 0.0], [0.78, 0.0], [0.9, 0.025], [1.0, 0.045]]},
			# Head (back -> snout): cream center stripe, dark mask through the eyes, pale cheeks.
			{"dorsal": [[0.0, 0.05], [0.4, 0.07], [0.75, 0.06], [0.92, 0.0], [1.0, 0.0]],
			"lateral": [[0.0, 0.0], [0.2, 0.04], [0.45, 0.065], [0.7, 0.05], [0.85, 0.0]],
			"lateral_center": [[0.0, 0.2], [0.5, 0.2], [1.0, 0.24]],
			"ventral": [[0.0, 0.15], [0.5, 0.2], [0.85, 0.18], [1.0, 0.1]]},
			# Jaw: pale.
			{"ventral": [[0.0, 0.3], [1.0, 0.3]], "dorsal": [[0.0, 0.2], [1.0, 0.2]]},
		])
	return _mark_tex


# --- Behaviour -------------------------------------------------------------------------

func idle_actions() -> Array[StringName]:
	return [&"sniff", &"look_around", &"dig", &"sniff", &"yawn", &"shake"]


func make_action(action_name: StringName, opts: Dictionary) -> CreatureAction:
	match action_name:
		&"dig_in":
			var a := CreatureAction.new(action_name, 2.8)
			a.hold = true
			a.roots = true
			a.blend_out = 0.8
			for i in 8:
				a.add_event(0.35 + i * 0.26, &"scoop")
			a.add_event(2.8, &"burrowed")
			return a
		&"emerge":
			var e := CreatureAction.new(action_name, 2.2)
			e.roots = true
			e.blend_in = 0.01
			e.blend_out = 0.5
			e.cut_previous = true
			e.add_event(0.15, &"burst")
			e.add_event(1.4, &"shake")
			return e
		&"dig":
			var d := CreatureAction.new(action_name, 2.4)
			d.roots = true
			for i in 6:
				d.add_event(0.4 + i * 0.27, &"scoop")
			return d
	var a2 := super.make_action(action_name, opts)
	if a2 != null and action_name == &"sniff":
		a2.add_event(0.9, &"snort")
	return a2


func action_pose(rig: CreatureRig, a: CreatureAction, pose: CreaturePose) -> void:
	var w := a.weight
	var h := BURROW_DEPTH * k
	match a.name:
		&"dig_in":
			var dig := smoothstep(0.1, 0.4, a.t)
			var sink := smoothstep(0.6, a.duration, a.t)
			pose.neck_pitch += -0.5 * dig * w
			pose.head_pitch += -0.3 * dig * w
			pose.pitch_pivot += 1.0 * w
			pose.body_pitch += (-0.12 * dig * (1.0 - sink) - 0.38 * sin(PI * sink)) * w
			pose.body_y += -h * sink * w
			pose.front_free += dig * w
			pose.hind_free += sink * w
			pose.eyes_narrow += w
			_scoop(rig, pose, a.t, dig * w)
			if a.t >= a.duration and not a.stopping:
				burrowed = true
				# The held dig pose is now replaced by the burrowed state in animate().
				return
			if a.stopping and burrowed:
				# Released without "emerge": come back out properly.
				burrowed = false
				if rig.fx:
					CreatureFx.debris_burst(rig.get_parent(), rig.global_position, rig.surface_at(rig.global_position), 2.5, 1.2 * k)
			return
		&"emerge":
			burrowed = false
			var rise := smoothstep(0.05, 1.1, a.t)
			var settle := smoothstep(1.1, 1.8, a.t)
			pose.body_y += -h * (1.0 - rise) * w
			pose.pitch_pivot += -1.0 * w
			pose.body_pitch += (0.5 * rise * (1.0 - settle)) * w
			pose.front_free += (1.0 - settle) * w
			pose.hind_free += (1.0 - rise) * w
			pose.head_pitch += 0.3 * rise * (1.0 - settle) * w
			var shake := a.window(0.62, 0.95, 0.06)
			pose.body_roll += sin(a.t * TAU * 5.0) * 0.14 * shake * w
			pose.head_roll += sin(a.t * TAU * 5.0 + 0.8) * 0.4 * shake * w
			pose.eyes_narrow += w
			return
		&"dig":
			var e := a.envelope(0.15, 0.15)
			pose.neck_pitch += -0.45 * e * w
			pose.head_pitch += -0.25 * e * w
			pose.body_pitch += -0.08 * e * w
			_scoop(rig, pose, a.t, e * w)
			return
		&"rear_up":
			super.action_pose(rig, a, pose)
			# Show off the claws.
			var e := a.window(0.0, 1.0, 0.35)
			for l in rig.legs:
				if l.group == CreatureLeg.Group.FRONT:
					pose.add_paw(l.index, Vector3(l.side * 0.25, 0.25, -0.2) * k * e * w)
			return
	super.action_pose(rig, a, pose)


## Alternating front-paw scooping (paws free, swinging down and back).
func _scoop(rig: CreatureRig, pose: CreaturePose, t: float, w: float) -> void:
	for l in rig.legs:
		if l.group != CreatureLeg.Group.FRONT:
			continue
		rig.set_leg_free(l.index, w)
		var ph := t * TAU * 1.9 + (PI if l.side > 0.0 else 0.0)
		pose.add_paw(l.index, Vector3(0, 0.1 + 0.18 * sin(ph), -0.35 + 0.35 * cos(ph)) * k * w)


func on_event(rig: CreatureRig, _action: StringName, event: StringName) -> void:
	if not rig.fx or not rig.is_inside_tree():
		return
	match event:
		&"scoop":
			var side := &"claw_left" if rig.rng_range(0.0, 1.0) < 0.5 else &"claw_right"
			var p := rig.get_socket(side).global_position
			p.y = rig.probe_ground(p, p.y + 1.0).y
			CreatureFx.debris_burst(rig.get_parent(), p, rig.surface_at(p), 0.7, 0.35 * k)
		&"burst":
			CreatureFx.debris_burst(rig.get_parent(), rig.global_position, rig.surface_at(rig.global_position), 3.0, 1.3 * k)
		&"burrowed":
			CreatureFx.debris_burst(rig.get_parent(), rig.global_position, rig.surface_at(rig.global_position), 1.5, 1.0 * k)


func animate(rig: CreatureRig, pose: CreaturePose, delta: float) -> void:
	super.animate(rig, pose, delta)
	if burrowed:
		pose.body_y += -BURROW_DEPTH * k
		pose.front_free += 1.0
		pose.hind_free += 1.0
		# Tunnelling: a line of dirt puffs follows the badgermole underground.
		var p := rig.global_position
		if rig.is_inside_tree():
			_trail_dist += p.distance_to(_last_pos)
			if _trail_dist > 1.4 * k and rig.fx:
				_trail_dist = 0.0
				CreatureFx.debris_burst(rig.get_parent(), p, rig.surface_at(p), 0.5, 0.6 * k)
	_last_pos = rig.global_position


func final_pose(rig: CreatureRig, _delta: float) -> void:
	# Hidden while fully underground (no overdraw, nothing poking through thin ground).
	var hidden := burrowed and not rig.is_action_playing(&"emerge")
	if rig.mesh_instance.visible == hidden:
		rig.mesh_instance.visible = not hidden


func sound_for(_action: StringName, event: StringName) -> StringName:
	match event:
		&"scoop", &"burrowed", &"burst":
			return &"badgermole_dig"
		&"vocal_start", &"snort":
			return &"badgermole_snort"
	return &""
