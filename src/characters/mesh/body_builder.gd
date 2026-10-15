class_name RigBodyBuilder
extends RefCounted
## Builds the skinned body volumes (torso, neck, arms, hands, legs, feet) as
## painted lofts: clothing is expressed as color bands + inflation on the body
## surface itself, so cloth never pokes through skin. Loose garments (skirts,
## sleeves, trims, armor) are added on top by RigGarmentBuilder.
##
## `spec` is a resolved outfit (see CharacterOutfits.resolve()).

const SK = preload("res://src/characters/rig/rig_skeleton_def.gd")


static func _ss(e0: float, e1: float, x: float) -> float:
	return smoothstep(e0, e1, x)


## Torso landmark t values for outfit authoring.
static func torso_landmarks(d: RigSkeletonDef) -> Dictionary:
	var h: float = d.p["height"]
	var y0: float = float(d.p["hip_y"]) - 0.045 * h
	var y1: float = float(d.p["neck_base_y"]) + 0.034 * h
	var span := y1 - y0
	var f := func(y: float) -> float: return clampf((y - y0) / span, 0.0, 1.0)
	return {
		"y0": y0, "y1": y1,
		"crotch": 0.0,
		"hip": f.call(float(d.p["hip_y"])),
		"belt": f.call(d.rest_pos[SK.HIPS].y + 0.035 * h),
		"waist": f.call(d.rest_pos[SK.SPINE].y + 0.012 * h),
		"chest": f.call(d.rest_pos[SK.CHEST].y + 0.02 * h),
		"armpit": f.call(d.rest_pos[SK.UPPER_CHEST].y - 0.005 * h),
		"shoulder": f.call(float(d.p["shoulder_y"]) + 0.012 * h),
		"neck": 1.0,
	}


static func torso_loft(d: RigSkeletonDef, spec: Dictionary) -> RigLoft:
	var h: float = d.p["height"]
	var p := d.p
	var lm := torso_landmarks(d)
	var y0: float = lm["y0"]
	var y1: float = lm["y1"]
	var pts := PackedVector3Array([
		Vector3(0, y0, 0.004 * h),
		Vector3(0, float(p["hip_y"]), 0.006 * h),
		Vector3(0, d.rest_pos[SK.SPINE].y, 0.006 * h),
		Vector3(0, d.rest_pos[SK.CHEST].y, 0.002 * h),
		Vector3(0, d.rest_pos[SK.UPPER_CHEST].y, 0.003 * h),
		Vector3(0, float(p["shoulder_y"]), 0.006 * h),
		Vector3(0, y1, 0.012 * h),
	])
	var hips_y := d.rest_pos[SK.HIPS].y
	var spine_y := d.rest_pos[SK.SPINE].y
	var chest_y := d.rest_pos[SK.CHEST].y
	var uc_y := d.rest_pos[SK.UPPER_CHEST].y
	var neck_y := d.rest_pos[SK.NECK].y
	var sh_y: float = p["shoulder_y"]
	var sx: float = float(p["shoulder_x"]) * h
	var hipw: float = float(p["hip_w"]) * h
	var wfn := func(_t: float, _a: float, pos: Vector3) -> Dictionary:
		var y := pos.y
		var w: Dictionary
		if y < spine_y:
			w = SkinMeshBuilder.w2(SK.HIPS, SK.SPINE, _ss(hips_y + 0.01 * h, spine_y + 0.02 * h, y))
		elif y < chest_y:
			w = SkinMeshBuilder.w2(SK.SPINE, SK.CHEST, _ss(spine_y + 0.01 * h, chest_y + 0.015 * h, y))
		elif y < uc_y + 0.01 * h:
			w = SkinMeshBuilder.w2(SK.CHEST, SK.UPPER_CHEST, _ss(chest_y + 0.01 * h, uc_y + 0.01 * h, y))
		else:
			w = SkinMeshBuilder.w2(SK.UPPER_CHEST, SK.NECK, _ss(neck_y - 0.004 * h, y1, y))
		var side := 0 if pos.x < 0.0 else 1
		var ax := absf(pos.x) / sx
		if y > uc_y - 0.03 * h:
			var k := _ss(0.3, 0.95, ax) * _ss(uc_y - 0.035 * h, sh_y, y)
			var cw := {SK.CLAVICLE[side]: 0.75, SK.UPPERARM[side]: 0.25 * _ss(0.75, 1.0, ax)}
			w = SkinMeshBuilder.wmix(w, cw, k * 0.85)
		if y < hips_y:
			var kx := _ss(0.25, 0.85, absf(pos.x) / hipw)
			var ky := _ss(hips_y, float(p["hip_y"]) - 0.03 * h, y)
			w = SkinMeshBuilder.wmix(w, {SK.THIGH[side]: 1.0}, kx * ky * 0.35)
		return w
	var l := RigLoft.create(pts, Vector3(0, 0, -1), wfn)
	var tf := func(y: float) -> float: return clampf((y - y0) / (y1 - y0), 0.0, 1.0)
	var bulk: Dictionary = spec.get("torso_bulk", {})
	var hw: float = p["hip_w"]
	var hd: float = p["hip_d"]
	var ww: float = p["waist_w"]
	var wd: float = p["waist_d"]
	var cw2: float = p["chest_w"]
	var cd: float = p["chest_d"]
	var nr: float = p["neck_r"]
	var bust: float = p["bust"]
	var gb := func(k: String) -> float: return float(bulk.get(k, 0.0))
	l.key(0.0, (hw * 0.6 + gb.call("hip")) * h, (hd * 0.62 + gb.call("hip")) * h, (hd * 0.72 + gb.call("hip")) * h)
	l.key(tf.call(float(p["hip_y"])), (hw * 1.04 + gb.call("hip")) * h, (hd * 0.92 + gb.call("hip")) * h, (hd * 1.12 + gb.call("hip")) * h)
	l.key(tf.call(hips_y + 0.03 * h), (hw * 0.97 + gb.call("hip")) * h, (hd * 0.9 + gb.call("hip")) * h, (hd * 1.0 + gb.call("hip")) * h)
	l.key(tf.call(spine_y + 0.012 * h), (ww + gb.call("waist")) * h, (wd + gb.call("waist")) * h, (wd * 0.92 + gb.call("waist")) * h)
	l.key(tf.call(chest_y + 0.02 * h), (cw2 + gb.call("chest")) * h, (cd * (1.1 + 0.16 * bust) + gb.call("chest")) * h, (cd * 0.98 + gb.call("chest")) * h)
	l.key(tf.call(uc_y), (cw2 * 1.04 + gb.call("chest")) * h, (cd * (1.04 + 0.1 * bust) + gb.call("chest")) * h, (cd + gb.call("chest")) * h)
	var shx: float = float(p["shoulder_x"])
	l.key(tf.call(sh_y - 0.012 * h), (lerpf(cw2 * 1.04, shx, 0.6) + gb.call("shoulder")) * h, (cd * 0.92 + gb.call("shoulder")) * h, (cd * 0.95 + gb.call("shoulder")) * h, 2.3)
	l.key(tf.call(sh_y + 0.014 * h), (shx * 0.96 + gb.call("shoulder")) * h, (cd * 0.72 + gb.call("shoulder")) * h, (cd * 0.8 + gb.call("shoulder")) * h, 2.6)
	l.key(tf.call(sh_y + 0.026 * h), (lerpf(shx, nr * 1.6, 0.55) + gb.call("neck")) * h, (cd * 0.55 + gb.call("neck")) * h, (cd * 0.62 + gb.call("neck")) * h, 2.2)
	l.key(1.0, (nr * 1.45 + gb.call("neck")) * h, (nr * 1.25 + gb.call("neck")) * h, (nr * 1.4 + gb.call("neck")) * h)
	return l


static func build_torso(b: SkinMeshBuilder, d: RigSkeletonDef, spec: Dictionary, segs: int) -> RigLoft:
	var l := torso_loft(d, spec)
	l.default_color = spec.get("skin", Color(0.9, 0.7, 0.55))
	if spec.has("torso_vneck"):
		var v: Dictionary = spec["torso_vneck"]
		var t_v: float = v["t"]
		var half: float = v["half"]
		var ac: float = v.get("center", 0.25)
		var vcol: Color = v["color"]
		l.color_fn = func(t: float, a: float, base: Color) -> Color:
			if t <= t_v:
				return base
			var k := (t - t_v) / maxf(1.0 - t_v, 0.001)
			return vcol if absf(a - ac) <= half * k + 0.004 else base
	l.emit(b, 34, segs, spec.get("torso_bands", []), true, false)
	l.color_fn = Callable()
	return l


static func neck_loft(d: RigSkeletonDef) -> RigLoft:
	var h: float = d.p["height"]
	var nr: float = float(d.p["neck_r"]) * h
	var y0: float = float(d.p["neck_base_y"]) - 0.02 * h
	var y1: float = float(d.p["chin_y"]) + 0.05 * h
	var neck_y := d.rest_pos[SK.NECK].y
	var head_y := d.rest_pos[SK.HEAD].y
	var wfn := func(_t: float, _a: float, pos: Vector3) -> Dictionary:
		if pos.y < neck_y + 0.01 * h:
			return SkinMeshBuilder.w2(SK.UPPER_CHEST, SK.NECK, _ss(y0, neck_y + 0.01 * h, pos.y))
		return SkinMeshBuilder.w2(SK.NECK, SK.HEAD, _ss(head_y - 0.035 * h, head_y + 0.005 * h, pos.y))
	var l := RigLoft.create(PackedVector3Array([Vector3(0, y0, 0.008 * h), Vector3(0, y1, 0.014 * h)]), Vector3(0, 0, -1), wfn)
	l.key(0.0, nr * 1.15, nr * 1.05, nr * 1.2)
	l.key(0.5, nr, nr * 0.95, nr * 1.05)
	l.key(1.0, nr * 1.02, nr * 0.95, nr * 1.1)
	return l


static func build_neck(b: SkinMeshBuilder, d: RigSkeletonDef, spec: Dictionary, segs: int) -> void:
	var l := neck_loft(d)
	l.default_color = spec.get("neck_color", spec.get("skin", Color.WHITE))
	l.emit(b, 5, segs, spec.get("neck_bands", []), false, false)


## Arm landmarks: t of shoulder and elbow along the arm loft.
static func arm_loft(d: RigSkeletonDef, side: int, spec: Dictionary) -> RigLoft:
	var h: float = d.p["height"]
	var lim: float = d.p["limb"]
	var dir := d.arm_dir[side]
	var sh := d.rest_pos[SK.UPPERARM[side]]
	var el := d.rest_pos[SK.FOREARM[side]]
	var wr := d.rest_pos[SK.HAND[side]]
	var top := sh - dir * 0.018 * h
	var total := top.distance_to(wr)
	var t_sh := 0.018 * h / total
	var t_el := top.distance_to(el) / total
	var bulk: float = spec.get("arm_bulk", 0.0)
	var wfn := func(t: float, _a: float, _pos: Vector3) -> Dictionary:
		var w: Dictionary
		if t < t_sh + 0.08:
			var k := _ss(0.0, t_sh + 0.08, t)
			w = SkinMeshBuilder.wmix({SK.UPPER_CHEST: 0.12, SK.CLAVICLE[side]: 0.38, SK.UPPERARM[side]: 0.5}, {SK.UPPERARM[side]: 1.0}, k)
		elif t < t_el + 0.06:
			w = SkinMeshBuilder.w2(SK.UPPERARM[side], SK.FOREARM[side], _ss(t_el - 0.05, t_el + 0.05, t))
		else:
			w = SkinMeshBuilder.w2(SK.FOREARM[side], SK.HAND[side], _ss(0.94, 1.02, t) * 0.4)
		return w
	var l := RigLoft.create(PackedVector3Array([top, sh, el, wr]), Vector3(0, 0, -1), wfn)
	var m := h * lim
	var bb := bulk * h
	l.key(0.0, 0.022 * m + bb, 0.024 * m + bb)
	l.key(t_sh * 0.5, 0.031 * m + bb, 0.032 * m + bb)
	l.key(t_sh, 0.035 * m + bb, 0.034 * m + bb, 0.035 * m + bb)
	l.key(t_sh + 0.1, 0.032 * m + bb, 0.031 * m + bb, 0.033 * m + bb)
	l.key(lerpf(t_sh, t_el, 0.55), 0.030 * m + bb, 0.031 * m + bb, 0.033 * m + bb)
	l.key(t_el - 0.03, 0.026 * m + bb, 0.026 * m + bb, 0.027 * m + bb)
	l.key(t_el + 0.07, 0.028 * m + bb, 0.027 * m + bb, 0.029 * m + bb)
	l.key(0.86, 0.022 * m + bb, 0.019 * m + bb, 0.021 * m + bb)
	l.key(1.0, 0.0185 * m + bb, 0.0145 * m + bb, 0.016 * m + bb)
	return l


static func build_arm(b: SkinMeshBuilder, d: RigSkeletonDef, side: int, spec: Dictionary, segs: int) -> RigLoft:
	var l := arm_loft(d, side, spec)
	l.default_color = spec.get("skin", Color.WHITE)
	l.emit(b, 20, segs, spec.get("arm_bands", []), true, true)
	return l


## Hand: palm block, four fingers sharing the fingers/fingertips bones, thumb.
static func build_hand(b: SkinMeshBuilder, d: RigSkeletonDef, side: int, spec: Dictionary) -> void:
	var h: float = d.p["height"]
	var col: Color = spec.get("hand_color", spec.get("skin", Color.WHITE))
	var hl: float = float(d.p["hand"]) * h * (1.0 + float(spec.get("hand_scale", 0.0)))
	var dir := d.arm_dir[side]
	var pn := d.palm_normal[side]
	var wa := dir.cross(pn).normalized()
	var thumb_side := wa if wa.z < 0.0 else -wa
	var wr := d.rest_pos[SK.HAND[side]]
	var knuck := wr + dir * hl * 0.45
	var hb := SK.HAND[side]
	var fb := SK.FINGERS[side]
	var tb := SK.FINGERTIPS[side]
	var thb := SK.THUMB[side]
	var wfn_palm := func(t: float, _a: float, _p: Vector3) -> Dictionary:
		return SkinMeshBuilder.w2(hb, fb, _ss(0.82, 1.0, t) * 0.35)
	var palm := RigLoft.create(PackedVector3Array([wr - dir * hl * 0.04, knuck]), -pn, wfn_palm)
	var stone: bool = spec.get("stone_gloves", false)
	var g := 1.25 if stone else 1.0
	palm.key(0.0, 0.17 * hl * g, 0.09 * hl * g, 0.085 * hl * g, 2.6)
	palm.key(0.45, 0.24 * hl * g, 0.11 * hl * g, 0.10 * hl * g, 3.2)
	palm.key(1.0, 0.255 * hl * g, 0.095 * hl * g, 0.085 * hl * g, 3.0)
	palm.default_color = col
	palm.emit(b, 4, 10, [], true, true)
	var fingers_rest := d.rest_pos[fb]
	var tips_rest := d.rest_pos[tb]
	var lens := [0.5, 0.55, 0.52, 0.43]
	var offs := [0.18, 0.06, -0.06, -0.175]
	for i in 4:
		var base := knuck - dir * hl * 0.03 + thumb_side * hl * float(offs[i]) * g
		var flen := hl * float(lens[i])
		var tip := base + dir * flen
		var fwfn := func(_t: float, _a: float, pos: Vector3) -> Dictionary:
			var along := (pos - fingers_rest).dot(dir)
			var mid := (tips_rest - fingers_rest).dot(dir)
			if along < 0.0:
				return SkinMeshBuilder.w2(hb, fb, _ss(-0.05 * hl, 0.02 * hl, along))
			return SkinMeshBuilder.w2(fb, tb, _ss(mid - 0.04 * hl, mid + 0.04 * hl, along))
		var f := RigLoft.create(PackedVector3Array([base, tip]), -pn, fwfn)
		var r := 0.058 * hl * (0.88 if i == 3 else 1.0) * g
		f.key(0.0, r, r * 0.9)
		f.key(0.8, r * 0.92, r * 0.85)
		f.key(1.0, r * 0.45, r * 0.4)
		f.default_color = col
		f.emit(b, 6, 7, [], false, true)
	var tb0 := d.rest_pos[thb]
	var tdir := (dir * 0.55 + thumb_side * 0.75 - pn * 0.25).normalized()
	var twfn := func(t: float, _a: float, _p: Vector3) -> Dictionary:
		return SkinMeshBuilder.w2(hb, thb, _ss(0.0, 0.35, t))
	var th := RigLoft.create(PackedVector3Array([tb0 - tdir * hl * 0.08, tb0 + tdir * hl * 0.36]), -pn, twfn)
	th.key(0.0, 0.085 * hl * g, 0.075 * hl * g)
	th.key(0.5, 0.068 * hl * g, 0.06 * hl * g)
	th.key(1.0, 0.032 * hl * g, 0.03 * hl * g)
	th.default_color = col
	th.emit(b, 5, 7, [], true, true)


static func leg_loft(d: RigSkeletonDef, side: int, spec: Dictionary) -> RigLoft:
	var h: float = d.p["height"]
	var lim: float = d.p["limb"]
	var hip := d.rest_pos[SK.THIGH[side]]
	var knee := d.rest_pos[SK.SHIN[side]]
	var ankle := d.rest_pos[SK.FOOT[side]]
	var top := hip + Vector3(0, 0.04 * h, 0)
	var total := top.distance_to(knee) + knee.distance_to(ankle)
	var t_hip := 0.04 * h / total
	var t_knee := top.distance_to(knee) / total
	var wfn := func(t: float, _a: float, _pos: Vector3) -> Dictionary:
		if t < t_hip + 0.12:
			return SkinMeshBuilder.w2(SK.HIPS, SK.THIGH[side], _ss(0.0, t_hip + 0.12, t))
		if t < t_knee + 0.08:
			return SkinMeshBuilder.w2(SK.THIGH[side], SK.SHIN[side], _ss(t_knee - 0.055, t_knee + 0.055, t))
		return SkinMeshBuilder.w2(SK.SHIN[side], SK.FOOT[side], _ss(0.95, 1.02, t) * 0.35)
	var l := RigLoft.create(PackedVector3Array([top, hip, knee, ankle]), Vector3(0, 0, -1), wfn)
	var m := h * lim
	var bb: float = float(spec.get("leg_bulk", 0.0)) * h
	var hipk: float = float(d.p["hip_w"]) / 0.086
	l.key(0.0, 0.04 * m * hipk + bb, 0.044 * m + bb, 0.05 * m + bb)
	l.key(t_hip, 0.044 * m * hipk + bb, 0.046 * m + bb, 0.053 * m + bb)
	l.key(t_hip + 0.12, 0.044 * m + bb, 0.045 * m + bb, 0.047 * m + bb)
	l.key(t_knee - 0.13, 0.037 * m + bb, 0.038 * m + bb, 0.037 * m + bb)
	l.key(t_knee - 0.03, 0.033 * m + bb, 0.034 * m + bb, 0.031 * m + bb)
	l.key(t_knee + 0.04, 0.031 * m + bb, 0.03 * m + bb, 0.033 * m + bb)
	l.key(t_knee + 0.16, 0.033 * m + bb, 0.028 * m + bb, 0.039 * m + bb)
	l.key(0.88, 0.022 * m + bb, 0.021 * m + bb, 0.023 * m + bb)
	l.key(1.0, 0.0195 * m + bb, 0.019 * m + bb, 0.021 * m + bb)
	return l


static func build_leg(b: SkinMeshBuilder, d: RigSkeletonDef, side: int, spec: Dictionary, segs: int) -> RigLoft:
	var l := leg_loft(d, side, spec)
	l.default_color = spec.get("skin", Color.WHITE)
	l.emit(b, 22, segs, spec.get("leg_bands", []), false, true)
	return l


## Shoe/boot/bare foot along the sole from heel to toe tip.
static func build_foot(b: SkinMeshBuilder, d: RigSkeletonDef, side: int, spec: Dictionary) -> void:
	var h: float = d.p["height"]
	var fl: float = float(d.p["foot"]) * h
	var x := d.rest_pos[SK.FOOT[side]].x
	var ball_z := d.rest_pos[SK.TOES[side]].z
	var style: String = spec.get("foot_style", "shoe")
	var g: float = 1.12 if style == "boot" else (0.94 if style == "bare" else 1.0)
	var ks := [[0.0, 0.05, 0.045, 0.05], [0.1, 0.105, 0.115, 0.085], [0.38, 0.115, 0.095, 0.075], [0.62, 0.125, 0.07, 0.068], [0.86, 0.11, 0.05, 0.055], [1.0, 0.04, 0.02, 0.03]]
	var pts := PackedVector3Array()
	for k: Array in ks:
		var t: float = k[0]
		var z := lerpf(fl * 0.17, -fl * 0.9, t)
		pts.append(Vector3(x, float(k[3]) * fl * g + 0.0015, z))
	var shin := SK.SHIN[side]
	var foot := SK.FOOT[side]
	var toes := SK.TOES[side]
	var wfn := func(_t: float, _a: float, pos: Vector3) -> Dictionary:
		var w := SkinMeshBuilder.w2(foot, toes, _ss(ball_z + 0.04 * fl, ball_z - 0.06 * fl, pos.z))
		if pos.y > 0.06 * fl and pos.z > -0.25 * fl:
			w = SkinMeshBuilder.wmix(w, {shin: 1.0}, _ss(0.3 * fl, 0.55 * fl, pos.y) * 0.5)
		return w
	var l := RigLoft.create(pts, Vector3.UP, wfn)
	for k: Array in ks:
		l.key(float(k[0]), float(k[1]) * fl * g, float(k[2]) * fl * g, float(k[3]) * fl * g, 2.7)
	l.default_color = spec.get("foot_color", spec.get("skin", Color.WHITE))
	l.emit(b, 12, 12, spec.get("foot_bands", []), true, true)
