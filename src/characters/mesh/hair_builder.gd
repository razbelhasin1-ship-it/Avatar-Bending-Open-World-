class_name RigHairBuilder
extends RefCounted
## Stylized hair: a thick shell ("cap") hugging the skull down to a styled
## hairline (bangs, sideburns, nape), plus attachments: topknot (+ crown piece),
## bun, wolf tail, loopies, long back hair, braid. Tails and long hair are
## skinned to spring bones (created by add_bones()) for secondary motion.

const SK = preload("res://src/characters/rig/rig_skeleton_def.gd")

## Hairline presets: front / side / back polar angles, thickness, spikes.
const STYLES := {
	"short": {"front": 1.08, "side": 1.6, "back": 2.05, "thick": 0.12, "spikes": 9, "spike_amp": 0.22, "spike_span": 1.5, "burns": 0.2, "messy": 0.02},
	"spiky": {"front": 1.18, "side": 1.66, "back": 2.1, "thick": 0.1, "spikes": 9, "spike_amp": 0.26, "spike_span": 2.6, "burns": 0.12, "messy": 0.05},
	"slick": {"front": 0.98, "side": 1.6, "back": 2.05, "thick": 0.055, "spikes": 0, "burns": 0.1},
	"undercut": {"front": 1.02, "side": 1.08, "back": 1.25, "thick": 0.06, "spikes": 0, "burns": 0.0},
	"bangs": {"front": 1.32, "side": 1.72, "back": 2.2, "thick": 0.075, "spikes": 5, "spike_amp": 0.1, "spike_span": 1.2, "burns": 0.0},
	"parted": {"front": 1.08, "side": 1.72, "back": 2.25, "thick": 0.075, "spikes": 0, "burns": 0.0, "part": 0.3},
	"cropped": {"front": 1.05, "side": 1.5, "back": 1.95, "thick": 0.04, "spikes": 0, "burns": 0.1},
	"receding": {"front": 1.6, "side": 1.7, "back": 2.0, "thick": 0.035, "spikes": 0, "burns": 0.0, "bald_top": 0.75},
}


## Adds spring bones the style needs. Returns spring chain descriptors.
static func add_bones(d: RigSkeletonDef, hs: RigHeadShape, spec: Dictionary) -> Array:
	var chains: Array = []
	var style: String = spec.get("hair_style", "short")
	var extras: Array = spec.get("hair_extras", [])
	var head_h: float = d.p["head_h"]
	if extras.has("wolf_tail") or extras.has("ponytail"):
		var root := hs.point(PI, 0.62 if extras.has("wolf_tail") else 1.25, head_h * 0.06)
		var b1 := d.add_bone("hair_1", SK.HEAD, root)
		var b2 := d.add_bone("hair_2", b1, root + Vector3(0, -head_h * 0.08, head_h * 0.16))
		chains.append({"bones": [b1, b2], "tip": root + Vector3(0, -head_h * 0.24, head_h * 0.26), "stiffness": 0.5, "damping": 0.35, "gravity": 0.6})
	if style == "long" or extras.has("long") or extras.has("braid"):
		var root2 := hs.point(PI, 1.35, head_h * 0.05)
		var drop: float = head_h * (1.25 if extras.has("braid") else 0.95)
		var b3 := d.add_bone("hair_back_1", SK.HEAD, root2)
		var b4 := d.add_bone("hair_back_2", b3, root2 + Vector3(0, -drop * 0.5, head_h * 0.05))
		chains.append({"bones": [b3, b4], "tip": root2 + Vector3(0, -drop, head_h * 0.04), "stiffness": 0.55, "damping": 0.4, "gravity": 0.8, "collide_back": true})
	return chains


static func build(outl: SkinMeshBuilder, d: RigSkeletonDef, hs: RigHeadShape, spec: Dictionary) -> void:
	var style: String = spec.get("hair_style", "short")
	var col: Color = spec.get("hair_color", Color(0.12, 0.09, 0.08))
	var extras: Array = spec.get("hair_extras", [])
	var covered: bool = spec.get("head_covered", false)
	if style != "bald" and not covered and STYLES.has(style):
		_cap(outl, hs, STYLES[style], col)
	elif style == "long" and not covered:
		_cap(outl, hs, STYLES["parted"], col)
	if covered:
		return
	var head_h: float = d.p["head_h"]
	var hw := SkinMeshBuilder.w1(SK.HEAD)
	for ex: String in extras:
		match ex:
			"topknot":
				var c := hs.point(PI * 0.98, 0.38, head_h * 0.05)
				var bas := RigShapes.axes(Vector3.RIGHT, Vector3(0, 1, 0.35), Vector3(0, -0.35, 1), Vector3(0.11, 0.13, 0.12) * head_h)
				RigShapes.ellipsoid(outl, c, bas, col, hw, 7, 12)
				var band_c: Color = spec.get("hair_band_color", col.darkened(0.3))
				var bc := hs.point(PI * 0.98, 0.42, head_h * 0.012)
				RigShapes.ellipsoid(outl, bc, RigShapes.axes(Vector3.RIGHT, Vector3(0, 1, 0.3), Vector3(0, -0.3, 1), Vector3(0.085, 0.035, 0.085) * head_h), band_c, hw, 5, 12)
				if spec.get("crown", false):
					_crown(outl, hs, head_h, spec.get("crown_color", Color(0.95, 0.74, 0.26)))
			"bun":
				var c2 := hs.point(PI, 1.05, head_h * 0.1)
				RigShapes.ellipsoid(outl, c2, RigShapes.axes(Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.15, 0.13, 0.11) * head_h), col, hw, 8, 14)
				var stick_c: Color = spec.get("hair_band_color", Color(0.75, 0.6, 0.3))
				var sa := c2 + Vector3(-head_h * 0.2, head_h * 0.08, head_h * 0.02)
				var sb := c2 + Vector3(head_h * 0.2, -head_h * 0.05, head_h * 0.02)
				RigShapes.bar(outl, PackedVector3Array([sa, sb]), PackedVector3Array([Vector3.BACK, Vector3.BACK]), head_h * 0.018, head_h * 0.018, stick_c, [hw, hw])
			"wolf_tail", "ponytail":
				_tail(outl, d, hs, spec, col, ex == "wolf_tail")
			"loopies":
				_loopies(outl, hs, head_h, col)
			"long":
				_long_back(outl, d, hs, col, false)
			"braid":
				_long_back(outl, d, hs, col, true)


## Cap shell from the crown down to the styled hairline, with a closing rim.
static func _cap(b: SkinMeshBuilder, hs: RigHeadShape, st: Dictionary, col: Color) -> void:
	var segs := 56
	var rings := 9
	var thick: float = float(st.get("thick", 0.07)) * hs.hh
	var spikes: int = st.get("spikes", 0)
	var amp: float = st.get("spike_amp", 0.0)
	var span: float = st.get("spike_span", 1.0)
	var burns: float = st.get("burns", 0.0)
	var messy: float = st.get("messy", 0.0)
	var part: float = st.get("part", 0.0)
	var bald_top: float = st.get("bald_top", 0.0)
	var line := func(th: float) -> float:
		var c := cos(th)
		var s := sin(th)
		var cf := maxf(c, 0.0) * maxf(c, 0.0)
		var cb := maxf(-c, 0.0) * maxf(-c, 0.0)
		var cs := s * s
		var ph: float = float(st["front"]) * cf + float(st["side"]) * cs + float(st["back"]) * cb
		var a := wrapf(th, -PI, PI)
		if spikes > 0 and absf(a) < span * 0.5:
			var u := (a / span + 0.5) * float(spikes)
			var tri := 1.0 - absf(fposmod(u, 1.0) * 2.0 - 1.0)
			var win := smoothstep(span * 0.5, span * 0.3, absf(a))
			ph += amp * tri * win
		if burns > 0.0:
			ph += burns * exp(-pow((absf(a) - 1.3) / 0.1, 2.0))
		if part > 0.0:
			ph -= part * 0.25 * exp(-pow((a - part) / 0.12, 2.0))
		return ph
	var w := SkinMeshBuilder.w1(SK.HEAD)
	b.begin_part()
	var rows: Array = []
	var edge_out := PackedInt32Array()
	var crown_pos := hs.point(0.0, 0.0, thick * (1.0 + messy * 2.0))
	var crown := b.add_vertex(crown_pos, col, w)
	var edge_phis := PackedFloat32Array()
	for th_i in segs:
		edge_phis.append(line.call(TAU * float(th_i) / float(segs)))
	for r in range(1, rings + 1):
		var s := float(r) / float(rings)
		var row := PackedInt32Array()
		for i in segs:
			var th := TAU * float(i) / float(segs)
			var ph := edge_phis[i] * pow(s, 0.92)
			var t := thick * (0.5 + 0.5 * pow(1.0 - s, 0.6))
			if messy > 0.0:
				t += messy * hs.hh * (0.5 + 0.5 * sin(th * 7.0 + s * 5.0)) * (1.0 - s * 0.5)
			if bald_top > 0.0:
				t *= smoothstep(bald_top * 0.6, bald_top, ph / maxf(edge_phis[i], 0.01) * 1.0)
			row.append(b.add_vertex(hs.point(th, ph, t), col, w))
		rows.append(row)
	b.add_grid(rows, true)
	b.add_cap(rows[0], crown, true)
	b.end_part()
	# Rim: from the outer edge down into the scalp.
	b.begin_part()
	var outer := PackedInt32Array()
	var inner := PackedInt32Array()
	for i in segs:
		var th := TAU * float(i) / float(segs)
		var ph := edge_phis[i]
		var t := thick * 0.5
		if bald_top > 0.0:
			t *= 1.0
		outer.append(b.add_vertex(hs.point(th, ph, t), col, w))
		inner.append(b.add_vertex(hs.point(th, ph + 0.02, -0.002), col.darkened(0.15), w))
	b.add_grid([outer, inner], true)
	b.end_part()


static func _crown(b: SkinMeshBuilder, hs: RigHeadShape, head_h: float, col: Color) -> void:
	var w := SkinMeshBuilder.w1(SK.HEAD)
	var base := hs.point(PI * 0.98, 0.18, head_h * 0.1)
	# Flame-shaped plate: a flattened teardrop with a tall center tip.
	var fwd := Vector3(0, 0.25, -1).normalized()
	var bas := RigShapes.axes(Vector3.RIGHT, Vector3(0, 1, 0.25), fwd, Vector3(0.05, 0.09, 0.02) * head_h)
	RigShapes.ellipsoid(b, base + Vector3(0, head_h * 0.02, 0), bas, col, w, 6, 12)
	for s: float in [-1.0, 1.0]:
		var side_c := base + Vector3(s * head_h * 0.045, head_h * 0.0, head_h * 0.005)
		var bas2 := RigShapes.axes(Vector3(1, 0, 0), Vector3(s * 0.4, 1, 0.2), fwd, Vector3(0.028, 0.055, 0.016) * head_h)
		RigShapes.ellipsoid(b, side_c, bas2, col, w, 5, 10)


static func _tail(b: SkinMeshBuilder, d: RigSkeletonDef, hs: RigHeadShape, spec: Dictionary, col: Color, wolf: bool) -> void:
	var head_h: float = d.p["head_h"]
	var b1 := d.find("hair_1")
	var b2 := d.find("hair_2")
	var root := d.rest_pos[b1]
	var mid := d.rest_pos[b2]
	var tip := root + (Vector3(0, -head_h * 0.24, head_h * 0.26) if wolf else Vector3(0, -head_h * 0.75, head_h * 0.12))
	if not wolf:
		mid = root + Vector3(0, -head_h * 0.35, head_h * 0.12)
	var wfn := func(t: float, _a: float, _p: Vector3) -> Dictionary:
		if t < 0.15:
			return SkinMeshBuilder.w2(SK.HEAD, b1, t / 0.15)
		return SkinMeshBuilder.w2(b1, b2, smoothstep(0.35, 0.7, t))
	var l := RigLoft.create(PackedVector3Array([root - Vector3(0, -head_h * 0.02, head_h * 0.04), mid, tip]), Vector3.UP, wfn)
	var r := head_h * (0.05 if wolf else 0.06)
	l.key(0.0, r * 0.9, r * 0.8)
	l.key(0.2, r, r * 0.85)
	l.key(0.6, r * 0.8, r * 0.6)
	l.key(1.0, r * 0.12, r * 0.08)
	l.default_color = col
	l.emit(b, 10, 10, [], true, true)
	var band_c: Color = spec.get("hair_band_color", col.darkened(0.35))
	var bc := root + Vector3(0, 0, head_h * 0.01)
	RigShapes.ellipsoid(b, bc, RigShapes.axes(Vector3.RIGHT, Vector3(0, 0.6, 1), Vector3(0, 1, -0.6), Vector3(r * 1.15, r * 0.5, r * 1.15)), band_c, SkinMeshBuilder.w1(SK.HEAD), 4, 10)


static func _loopies(b: SkinMeshBuilder, hs: RigHeadShape, head_h: float, col: Color) -> void:
	var w := SkinMeshBuilder.w1(SK.HEAD)
	for s: float in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		var n := 14
		for i in n + 1:
			var f := float(i) / float(n)
			# A teardrop loop hanging from the temple in front of the ear.
			var th := s * (1.05 + 0.25 * sin(f * TAU) * 0.5 + 0.12 * f)
			var ph := 1.35 + 0.55 * (0.5 - 0.5 * cos(f * TAU))
			var lift := head_h * (0.03 + 0.05 * sin(f * PI))
			pts.append(hs.point(th, ph, lift))
		var wfn := func(_t: float, _a: float, _p: Vector3) -> Dictionary: return w
		var l := RigLoft.create(pts, Vector3(s, 0, 0), wfn)
		l.key(0.0, head_h * 0.028, head_h * 0.028)
		l.key(0.5, head_h * 0.022, head_h * 0.022)
		l.key(1.0, head_h * 0.026, head_h * 0.026)
		l.default_color = col
		l.emit(b, 16, 7, [], true, true)


static func _long_back(b: SkinMeshBuilder, d: RigSkeletonDef, hs: RigHeadShape, col: Color, braid: bool) -> void:
	var head_h: float = d.p["head_h"]
	var b1 := d.find("hair_back_1")
	var b2 := d.find("hair_back_2")
	var root := d.rest_pos[b1]
	var drop: float = head_h * (1.25 if braid else 0.95)
	var top := hs.point(PI, 0.9, head_h * 0.04)
	var tip := root + Vector3(0, -drop, head_h * 0.04)
	var mid_y := d.rest_pos[b2].y
	var wfn := func(_t: float, _a: float, pos: Vector3) -> Dictionary:
		if pos.y > root.y:
			return SkinMeshBuilder.w1(SK.HEAD)
		if pos.y > mid_y:
			return SkinMeshBuilder.w2(SK.HEAD, b1, smoothstep(root.y, root.y - head_h * 0.25, pos.y))
		return SkinMeshBuilder.w2(b1, b2, smoothstep(mid_y + head_h * 0.1, mid_y - head_h * 0.2, pos.y))
	if braid:
		var l := RigLoft.create(PackedVector3Array([top, root + Vector3(0, -head_h * 0.1, head_h * 0.06), tip]), Vector3.BACK, wfn)
		l.key(0.0, head_h * 0.12, head_h * 0.06)
		l.key(0.2, head_h * 0.07, head_h * 0.06)
		l.key(1.0, head_h * 0.035, head_h * 0.03)
		l.bump_fn = func(t: float, _a: float) -> float: return head_h * 0.012 * absf(sin(t * 34.0))
		l.default_color = col
		l.emit(b, 40, 10, [], true, true)
	else:
		var l2 := RigLoft.create(PackedVector3Array([top, root + Vector3(0, -head_h * 0.2, head_h * 0.1), tip]), Vector3.BACK, wfn)
		l2.key(0.0, hs.hw * 0.85, head_h * 0.06, head_h * 0.08)
		l2.key(0.3, hs.hw * 0.95, head_h * 0.05, head_h * 0.03)
		l2.key(0.85, hs.hw * 0.8, head_h * 0.035, head_h * 0.02)
		l2.key(1.0, hs.hw * 0.45, head_h * 0.012, head_h * 0.01)
		l2.default_color = col
		l2.emit(b, 14, 16, [], true, true)
