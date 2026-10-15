class_name RigGarmentBuilder
extends RefCounted
## Loose garments and accessories layered over the painted body: robe/tunic
## skirts and armor panels (with procedural skirt bones), bell sleeves, fur and
## trim rings, trim strips, shoulder pads, capes, sash knots, prayer beads,
## necklaces and face scarves. Headwear lives in RigHeadwearBuilder.
##
## Pieces are Dictionaries in spec["pieces"] with a "type" key; see
## docs/modules/characters.md for every type and its fields.

const SK = preload("res://src/characters/rig/rig_skeleton_def.gd")


## Adds skirt/cape bones the pieces need; returns spring chain descriptors.
static func add_bones(d: RigSkeletonDef, spec: Dictionary) -> Array:
	var chains: Array = []
	var h: float = d.p["height"]
	var need_skirt := false
	var need_cape := false
	for pc: Dictionary in spec.get("pieces", []):
		match String(pc.get("type", "")):
			"skirt":
				if pc.get("bones", true):
					need_skirt = true
			"cape":
				need_cape = true
	if need_skirt:
		var hip_y: float = d.p["hip_y"]
		var hd: float = float(d.p["hip_d"]) * h
		var hw: float = float(d.p["hip_w"]) * h
		var f := d.add_bone("skirt_f", SK.HIPS, Vector3(0, hip_y, -hd * 0.4))
		var bk := d.add_bone("skirt_b", SK.HIPS, Vector3(0, hip_y, hd * 0.4))
		var l := d.add_bone("skirt_l", SK.HIPS, Vector3(-hw * 0.5, hip_y, 0))
		var r := d.add_bone("skirt_r", SK.HIPS, Vector3(hw * 0.5, hip_y, 0))
		chains.append({"skirt": true, "bones": [f, bk, l, r]})
	if need_cape:
		var top := Vector3(0, float(d.p["shoulder_y"]), float(d.p["chest_d"]) * h * 1.1)
		var c1 := d.add_bone("cape_1", SK.UPPER_CHEST, top)
		var c2 := d.add_bone("cape_2", c1, top + Vector3(0, -0.22 * h, 0.02 * h))
		chains.append({"bones": [c1, c2], "tip": top + Vector3(0, -0.44 * h, 0.04 * h), "stiffness": 0.4, "damping": 0.45, "gravity": 0.9, "collide_back": true})
	return chains


static func build(outl: SkinMeshBuilder, flat: SkinMeshBuilder, d: RigSkeletonDef, spec: Dictionary, ctx: Dictionary) -> void:
	for pc: Dictionary in spec.get("pieces", []):
		match String(pc.get("type", "")):
			"skirt":
				_skirt(outl, d, pc, ctx)
			"sleeve":
				for side in 2:
					_sleeve(outl, d, side, pc, ctx)
			"ring":
				_ring(outl, d, pc, ctx)
			"strip":
				_strip(flat, d, pc, ctx)
			"pads":
				_pads(outl, d, pc)
			"cape":
				_cape(outl, d, pc, ctx)
			"knot":
				_knot(outl, d, pc, ctx)
			"beads":
				_beads(outl, d, pc, ctx)
			"necklace":
				_necklace(outl, d, pc)
			"scarf_mask":
				_scarf_mask(outl, flat, d, pc, ctx)
			"plate":
				_plate(outl, d, pc, ctx)
			_:
				RigHeadwearBuilder.build_piece(outl, flat, d, pc, ctx)


static func _ss(e0: float, e1: float, x: float) -> float:
	return smoothstep(e0, e1, x)


## Robe/tunic skirt or armor panels from `top` (torso t) down to `hem_y`
## (fraction of height). Fields: top, hem, flare, color, trim, trim_w, inner,
## a0/a1 (open panel), inflate, bones.
static func _skirt(b: SkinMeshBuilder, d: RigSkeletonDef, pc: Dictionary, ctx: Dictionary) -> void:
	var h: float = d.p["height"]
	var torso: RigLoft = ctx["torso"]
	var t_top: float = pc.get("top", 0.3)
	var top_c := torso.center(t_top)
	var hem_y: float = float(pc.get("hem", 0.3)) * h
	var flare: float = pc.get("flare", 1.2)
	var infl: float = float(pc.get("inflate", 0.008)) * h
	var hw: float = float(d.p["hip_w"]) * h
	var hd: float = float(d.p["hip_d"]) * h
	var hip_y: float = d.p["hip_y"]
	var has_bones: bool = d.find("skirt_f") >= 0 and bool(pc.get("bones", true))
	var bf := d.find("skirt_f")
	var bb := d.find("skirt_b")
	var top_y := top_c.y
	var span := maxf(top_y - hem_y, 0.01)
	var wfn := func(_t: float, _a: float, pos: Vector3) -> Dictionary:
		var k := clampf((top_y - pos.y) / span, 0.0, 1.0)
		var base: Dictionary
		if pos.y > d.rest_pos[SK.SPINE].y:
			base = SkinMeshBuilder.w2(SK.HIPS, SK.SPINE, _ss(d.rest_pos[SK.HIPS].y, d.rest_pos[SK.SPINE].y + 0.02 * h, pos.y))
		else:
			base = {SK.HIPS: 1.0}
		var lower := _ss(hip_y + 0.04 * h, hip_y - 0.12 * h, pos.y)
		if lower <= 0.0:
			return base
		var ang := atan2(pos.x, -pos.z)  # 0 front, +-PI back
		var side := 0 if pos.x < 0.0 else 1
		var sd := sin(ang) * sin(ang)
		var w := {}
		if has_bones:
			var cf := maxf(cos(ang), 0.0)
			var cb := maxf(-cos(ang), 0.0)
			w[bf] = cf * cf
			w[bb] = cb * cb
			w[SK.THIGH[side]] = sd * 0.85
			w[SK.HIPS] = sd * 0.15
		else:
			w[SK.THIGH[side]] = 0.55 + 0.25 * sd
			w[SK.HIPS] = 0.45 - 0.25 * sd
		return SkinMeshBuilder.wmix(base, w, lower * (0.6 + 0.4 * k))
	# Centered on the legs (z = 0) rather than on the torso's slightly-back spine.
	top_c.z = 0.0
	var bottom := Vector3(0, hem_y, 0.0)
	var mid_y := hip_y - 0.02 * h
	var path := PackedVector3Array([top_c, Vector3(0, mid_y, 0.0), bottom]) if top_y > mid_y + 0.02 * h else PackedVector3Array([top_c, bottom])
	var l := RigLoft.create(path, Vector3(0, 0, -1), wfn)
	# Profile: follow the (inflated) torso down to the hips, clear the legs,
	# then flare to the hem.
	var band_infl := 0.0
	for band: Dictionary in ctx.get("torso_bands", []):
		band_infl = maxf(band_infl, float(band.get("inflate", 0.0)))
	var lm := RigBodyBuilder.torso_landmarks(d)
	var ty0: float = lm["y0"]
	var ty1: float = lm["y1"]
	var hx := d.rest_pos[SK.THIGH_L].x
	var leg_r: float = 0.046 * h * float(d.p["limb"]) + float(ctx.get("leg_infl", 0.0))
	var clear := 0.01 * h
	var prof := PackedFloat32Array([0.0, 0.0, 0.0, 2.0])
	var n_upper := 4
	var y_end := minf(mid_y, top_y)
	for i in n_upper + 1:
		var y := lerpf(top_y, y_end, float(i) / float(n_upper))
		torso._profile(clampf((y - ty0) / (ty1 - ty0), 0.0, 1.0), prof)
		var lower := smoothstep(d.rest_pos[SK.HIPS].y + 0.03 * h, hip_y, y)
		var rs := maxf(prof[0] + band_infl + infl, lerpf(0.0, absf(hx) + leg_r + clear, lower))
		var rf := maxf(prof[1] + band_infl + infl, lerpf(0.0, leg_r + clear * 1.8, lower))
		var rb := prof[2] + band_infl + infl
		l.key(clampf((top_y - y) / span, 0.0, 1.0), rs, rf, rb)
	var hem_rs := maxf(hw * flare, absf(hx) + leg_r + clear) + infl
	l.key(1.0, hem_rs, maxf(hd * flare * 1.05, leg_r + clear * 2.0) + infl, hd * flare * 1.15 + infl)
	l.a0 = pc.get("a0", 0.0)
	l.a1 = pc.get("a1", 1.0)
	var col: Color = pc.get("color", Color.WHITE)
	var bands: Array = [{"t0": 0.0, "t1": 1.0, "color": col, "inflate": 0.0}]
	if pc.has("trim"):
		var tw: float = pc.get("trim_w", 0.12)
		bands = [{"t0": 0.0, "t1": 1.0 - tw, "color": col, "inflate": 0.0}, {"t0": 1.0 - tw, "t1": 1.0, "color": pc["trim"], "inflate": 0.002 * h}]
	if pc.has("band_top"):
		bands[0]["t0"] = 0.08
		bands.push_front({"t0": 0.0, "t1": 0.08, "color": pc["band_top"], "inflate": 0.002 * h})
	var segs := int(ctx.get("segs", 22)) + 6
	l.emit(b, 12, segs, bands)
	# Inner side so the hem reads from low angles.
	l.flip = true
	l.emit(b, 12, segs, [{"t0": 0.06, "t1": 1.0, "color": pc.get("inner", col.darkened(0.35)), "inflate": -0.003 * h}])
	l.flip = false


## Bell sleeve from `from` (arm t) to `extend` (fraction of height) past the wrist.
static func _sleeve(b: SkinMeshBuilder, d: RigSkeletonDef, side: int, pc: Dictionary, ctx: Dictionary) -> void:
	var h: float = d.p["height"]
	var arm: RigLoft = (ctx["arms"] as Array)[side]
	var t0: float = pc.get("from", 0.45)
	var ext: float = float(pc.get("extend", 0.04)) * h
	var dir := d.arm_dir[side]
	var start := arm.center(t0)
	var el := d.rest_pos[SK.FOREARM[side]]
	var wr := d.rest_pos[SK.HAND[side]]
	var end := wr + dir * ext
	var t_el := clampf(start.distance_to(el) / maxf(start.distance_to(end), 0.01), 0.05, 0.95)
	var wfn := func(t: float, _a: float, _p: Vector3) -> Dictionary:
		if t < t_el + 0.08:
			return SkinMeshBuilder.w2(SK.UPPERARM[side], SK.FOREARM[side], _ss(t_el - 0.08, t_el + 0.08, t))
		return {SK.FOREARM[side]: 1.0}
	var pts := PackedVector3Array([start, el, end]) if t0 < 0.5 else PackedVector3Array([start, end])
	var l := RigLoft.create(pts, Vector3(0, 0, -1), wfn)
	var prof := PackedFloat32Array([0.0, 0.0, 0.0, 2.0])
	arm._profile(t0, prof)
	var r0 := prof[0] + 0.006 * h
	var flare: float = float(pc.get("flare", 0.06)) * h
	l.key(0.0, r0, r0)
	l.key(0.5, lerpf(r0, flare, 0.45), lerpf(r0, flare, 0.4))
	l.key(1.0, flare, flare * 0.9)
	var col: Color = pc.get("color", Color.WHITE)
	var bands: Array = [{"t0": 0.0, "t1": 1.0, "color": col, "inflate": 0.0}]
	if pc.has("trim"):
		bands = [{"t0": 0.0, "t1": 0.86, "color": col, "inflate": 0.0}, {"t0": 0.86, "t1": 1.0, "color": pc["trim"], "inflate": 0.0015 * h}]
	l.emit(b, 10, 16, bands)
	l.flip = true
	l.emit(b, 10, 16, [{"t0": 0.1, "t1": 1.0, "color": pc.get("inner", col.darkened(0.35)), "inflate": -0.002 * h}])


## Ring around a body loft (fur trim, cuffs, belts, wraps). Fields: part
## ("torso", "arm", "leg", "neck"), t, width (t units), thick (fraction of
## height), color, fur (bool), sides (for limbs: [0, 1]).
static func _ring(b: SkinMeshBuilder, d: RigSkeletonDef, pc: Dictionary, ctx: Dictionary) -> void:
	var h: float = d.p["height"]
	var part: String = pc.get("part", "torso")
	var lofts: Array = []
	match part:
		"torso":
			lofts = [ctx["torso"]]
		"arm":
			lofts = ctx["arms"]
		"leg":
			lofts = ctx["legs"]
		"neck":
			lofts = [RigBodyBuilder.neck_loft(d)]
	var t: float = pc.get("t", 0.5)
	var wdt: float = pc.get("width", 0.05)
	var thick: float = float(pc.get("thick", 0.01)) * h
	var fur: bool = pc.get("fur", false)
	var col: Color = pc.get("color", Color.WHITE)
	var seed_v: float = float(pc.get("seed", 1))
	for lo: RigLoft in lofts:
		var old_bump := lo.bump_fn
		if fur:
			var amp := thick * 0.45
			lo.bump_fn = func(tt: float, aa: float) -> float:
				var v := sin(aa * TAU * 9.0 + seed_v) * 0.5 + sin(aa * TAU * 17.0 + tt * 40.0 + seed_v * 2.0) * 0.35
				return amp * (0.5 + 0.5 * v)
		var t0 := clampf(t - wdt * 0.5, 0.0, 1.0)
		var t1 := clampf(t + wdt * 0.5, 0.0, 1.0)
		var e := 0.0015
		var bands := [
			{"t0": t0, "t1": t0 + e, "color": col, "inflate": thick * 0.25},
			{"t0": t0 + e, "t1": t1 - e, "color": col, "inflate": thick},
			{"t0": t1 - e, "t1": t1, "color": col, "inflate": thick * 0.25},
		]
		var segs := 20 if part == "torso" else 12
		if fur:
			segs = 36 if part == "torso" else 18
		lo.emit(b, maxi(3, int(6.0 / maxf(wdt, 0.05))), segs, bands, false, false, t0, t1)
		lo.bump_fn = old_bump


## Flat trim strip on a body loft along (t, a) points. Fields: part, side, pts
## (Array of Vector2(t, a)), width (fraction of height), color.
static func _strip(b: SkinMeshBuilder, d: RigSkeletonDef, pc: Dictionary, ctx: Dictionary) -> void:
	var h: float = d.p["height"]
	var part: String = pc.get("part", "torso")
	var lo: RigLoft
	match part:
		"arm":
			lo = (ctx["arms"] as Array)[int(pc.get("side", 1))]
		"leg":
			lo = (ctx["legs"] as Array)[int(pc.get("side", 1))]
		_:
			lo = ctx["torso"]
	var raw: Array = pc.get("pts", [])
	var pts := PackedVector2Array()
	# Resample for smooth curvature.
	for i in raw.size() - 1:
		var p0: Vector2 = raw[i]
		var p1: Vector2 = raw[i + 1]
		for k in 6:
			pts.append(p0.lerp(p1, float(k) / 6.0))
	if not raw.is_empty():
		pts.append(raw[raw.size() - 1])
	lo.emit_strip(b, pts, float(pc.get("width", 0.012)) * h, float(pc.get("lift", 0.012)) * h, pc.get("color", Color.WHITE))


## Shoulder pads: stacked domes. Fields: color, trim, layers, size, drop.
static func _pads(b: SkinMeshBuilder, d: RigSkeletonDef, pc: Dictionary) -> void:
	var h: float = d.p["height"]
	var layers: int = pc.get("layers", 1)
	var size: float = float(pc.get("size", 1.0))
	var col: Color = pc.get("color", Color.WHITE)
	var trim: Color = pc.get("trim", col.darkened(0.3))
	for side in 2:
		var s := SK.SIDE_SIGN[side]
		var sh := d.rest_pos[SK.UPPERARM[side]]
		for i in layers:
			var fi := float(i)
			var c := sh + Vector3(s * (0.012 + 0.012 * fi) * h, (0.022 - 0.03 * fi) * h, 0.0)
			var up := Vector3(s * (0.55 + 0.25 * fi), 1.0, 0.0).normalized()
			var out := Vector3(0, 0, -1).cross(up) * -s
			var r := Vector3(0.05, 0.022, 0.055) * h * size * (1.0 - 0.08 * fi)
			var bas := RigShapes.axes(out, up, Vector3.BACK, r)
			var w := {SK.UPPERARM[side]: 0.75 - 0.1 * fi, SK.CLAVICLE[side]: 0.25 + 0.1 * fi}
			var colr := col if i % 2 == 0 else trim
			RigShapes.sphere_fn(b,
				func(th: float, ph: float) -> Vector3: return c + bas * Vector3(sin(ph) * sin(th), cos(ph), -sin(ph) * cos(th)),
				func(_th: float, ph: float, _p: Vector3) -> Color: return trim if ph > 1.25 else colr,
				func(_th: float, _ph: float, _p: Vector3) -> Dictionary: return w,
				7, 14, PI * 0.5)


## Back cape / shawl. Fields: color, inner, length (fraction of height
## below the shoulders), width (x scale), top (torso t).
static func _cape(b: SkinMeshBuilder, d: RigSkeletonDef, pc: Dictionary, ctx: Dictionary) -> void:
	var h: float = d.p["height"]
	var torso: RigLoft = ctx["torso"]
	var c1 := d.find("cape_1")
	var c2 := d.find("cape_2")
	var top_t: float = pc.get("top", 0.92)
	var top := torso.center(top_t)
	var length: float = float(pc.get("length", 0.4)) * h
	var bottom := top + Vector3(0, -length, 0.03 * h)
	var y_mid := d.rest_pos[c2].y if c2 >= 0 else top.y - length * 0.5
	var wfn := func(_t: float, _a: float, pos: Vector3) -> Dictionary:
		if c1 < 0:
			return {SK.UPPER_CHEST: 1.0}
		if pos.y > top.y - 0.06 * h:
			return SkinMeshBuilder.w2(SK.UPPER_CHEST, c1, _ss(top.y, top.y - 0.06 * h, pos.y))
		return SkinMeshBuilder.w2(c1, c2, _ss(y_mid + 0.08 * h, y_mid - 0.1 * h, pos.y))
	var l := RigLoft.create(PackedVector3Array([top, bottom]), Vector3(0, 0, -1), wfn)
	var prof := PackedFloat32Array([0.0, 0.0, 0.0, 2.0])
	torso._profile(top_t, prof)
	var wk: float = pc.get("width", 1.0)
	l.key(0.0, prof[0] * 1.1 * wk + 0.01 * h, prof[1] + 0.01 * h, prof[2] + 0.012 * h)
	l.key(0.25, float(d.p["shoulder_x"]) * h * 1.15 * wk, float(d.p["chest_d"]) * h * 1.0, float(d.p["chest_d"]) * h * 1.25)
	l.key(1.0, float(d.p["shoulder_x"]) * h * 1.25 * wk, float(d.p["chest_d"]) * h * 1.0, float(d.p["chest_d"]) * h * 1.6)
	l.a0 = 0.52
	l.a1 = 0.98
	var col: Color = pc.get("color", Color.WHITE)
	l.emit(b, 10, 18, [{"t0": 0.0, "t1": 1.0, "color": col, "inflate": 0.0}])
	l.flip = true
	l.emit(b, 10, 18, [{"t0": 0.0, "t1": 1.0, "color": pc.get("inner", col.darkened(0.3)), "inflate": -0.003 * h}])


## Sash knot with two hanging tails. Fields: t (torso), a (angle), color.
static func _knot(b: SkinMeshBuilder, d: RigSkeletonDef, pc: Dictionary, ctx: Dictionary) -> void:
	var h: float = d.p["height"]
	var torso: RigLoft = ctx["torso"]
	var t: float = pc.get("t", 0.3)
	var a: float = pc.get("a", 0.2)
	var col: Color = pc.get("color", Color.WHITE)
	var sp := torso.surface_point(t, a, 0.012 * h)
	var pos: Vector3 = sp[0]
	var n: Vector3 = sp[1]
	var w := torso.weights_at(t, a, pos)
	var bas := RigShapes.axes(Vector3.UP.cross(n), Vector3.UP, n, Vector3(0.028, 0.022, 0.016) * h)
	RigShapes.ellipsoid(b, pos, bas, col, w, 6, 10)
	if pc.get("tails", true):
		var side := 0 if pos.x < 0.0 else 1
		for k in 2:
			var off := Vector3.UP.cross(n).normalized() * (float(k) - 0.5) * 0.03 * h
			var p0 := pos + off
			var len := (0.16 + 0.04 * float(k)) * h
			var pts := PackedVector3Array([p0, p0 + Vector3(0, -len * 0.5, 0) + n * 0.01 * h, p0 + Vector3(0, -len, 0) + n * 0.012 * h + off * 0.6])
			var ups := PackedVector3Array([n, n, n])
			var tw := SkinMeshBuilder.wmix(w, {SK.THIGH[side]: 1.0}, 0.45)
			RigShapes.bar(b, pts, ups, 0.03 * h, 0.005 * h, col.darkened(0.08 * float(k)), [w, tw, tw])


## Prayer beads draped around the neck. Fields: color, count, big_color.
static func _beads(b: SkinMeshBuilder, d: RigSkeletonDef, pc: Dictionary, ctx: Dictionary) -> void:
	var h: float = d.p["height"]
	var torso: RigLoft = ctx["torso"]
	var count: int = pc.get("count", 16)
	var col: Color = pc.get("color", Color(0.55, 0.32, 0.18))
	for i in count:
		var a := float(i) / float(count)
		var front := maxf(sin(a * TAU), 0.0)
		var t := 0.9 - 0.2 * pow(front, 2.0)
		var sp := torso.surface_point(t, a, 0.013 * h)
		var w := torso.weights_at(t, a, sp[0])
		var r := 0.0105 * h * (1.5 if i == count / 4 else 1.0)
		RigShapes.ellipsoid(b, sp[0], Basis().scaled(Vector3.ONE * r), pc.get("big_color", col) if i == count / 4 else col, w, 4, 6)


## Choker/necklace with a pendant. Fields: color, pendant_color.
static func _necklace(b: SkinMeshBuilder, d: RigSkeletonDef, pc: Dictionary) -> void:
	var h: float = d.p["height"]
	var neck := RigBodyBuilder.neck_loft(d)
	var col: Color = pc.get("color", Color(0.2, 0.3, 0.6))
	neck.emit(b, 3, 14, [{"t0": 0.3, "t1": 0.42, "color": col, "inflate": 0.003 * h}], false, false, 0.3, 0.42)
	var sp := neck.surface_point(0.32, 0.25, 0.006 * h)
	var n: Vector3 = sp[1]
	var bas := RigShapes.axes(Vector3.RIGHT, Vector3.UP, n, Vector3(0.012, 0.014, 0.004) * h)
	RigShapes.ellipsoid(b, (sp[0] as Vector3) + Vector3(0, -0.012 * h, 0), bas, pc.get("pendant_color", Color(0.3, 0.55, 0.85)), {SK.NECK: 0.6, SK.UPPER_CHEST: 0.4}, 5, 10)


## Cloth scarf over the lower face (bandits) + neck wrap.
static func _scarf_mask(outl: SkinMeshBuilder, _flat: SkinMeshBuilder, d: RigSkeletonDef, pc: Dictionary, ctx: Dictionary) -> void:
	var h: float = d.p["height"]
	var hs: RigHeadShape = ctx["head"]
	var col: Color = pc.get("color", Color(0.5, 0.2, 0.15))
	var head_h: float = d.p["head_h"]
	var ph_top := hs.phi_at_height(float(d.p["eye_y"]) - head_h * 0.1)
	var w := SkinMeshBuilder.w1(SK.HEAD)
	# Shell over the lower half of the face, wrapping to the ears.
	RigShapes.sphere_fn(outl,
		func(th: float, ph: float) -> Vector3:
			var p2 := ph_top + (PI * 0.92 - ph_top) * (ph / PI)
			return hs.point(th, p2, 0.006 * h),
		func(_th: float, _ph: float, _p: Vector3) -> Color: return col,
		func(_th: float, _ph: float, _p: Vector3) -> Dictionary: return w,
		6, 22, PI)
	var neck := RigBodyBuilder.neck_loft(d)
	neck.emit(outl, 4, 14, [{"t0": 0.2, "t1": 0.85, "color": col, "inflate": 0.006 * h}], false, false, 0.2, 0.85)


## Armor plate shell over a torso band region (front/back). Fields: t0, t1,
## a0, a1, color, trim, lift.
static func _plate(b: SkinMeshBuilder, d: RigSkeletonDef, pc: Dictionary, ctx: Dictionary) -> void:
	var h: float = d.p["height"]
	var torso: RigLoft = ctx["torso"]
	var t0: float = pc.get("t0", 0.45)
	var t1: float = pc.get("t1", 0.85)
	var lift: float = float(pc.get("lift", 0.012)) * h
	var col: Color = pc.get("color", Color.WHITE)
	var trim: Color = pc.get("trim", col.darkened(0.35))
	var old_a0 := torso.a0
	var old_a1 := torso.a1
	torso.a0 = pc.get("a0", 0.05)
	torso.a1 = pc.get("a1", 0.45)
	torso.emit(b, 8, 14, [{"t0": t0, "t1": t0 + 0.03, "color": trim, "inflate": lift}, {"t0": t0 + 0.03, "t1": t1, "color": col, "inflate": lift}], false, false, t0, t1)
	torso.a0 = old_a0
	torso.a1 = old_a1
