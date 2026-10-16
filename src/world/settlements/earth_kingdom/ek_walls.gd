class_name EkWalls
extends RefCounted
## Earth Kingdom fortifications (BuildingKit recipes, thread-safe). Local frames: x along the
## wall, -Z = OUTSIDE (the enemy side / the lower tier), y = 0 on the ground at the wall line.
##   city_wall    one chord of Ba Sing Se's outer / inner wall: battered masonry body, buttresses,
##                string courses, arrow slits, crenellated outer parapet with green tile copings,
##                inner parapet (optional gap where a wall stair lands), walkway, banners
##   wall_tower   square bastion astride a city wall: battered body, crenellated top, a pavilion
##                with an emerald roof, slits, banner
##   great_gate   the gatehouse of an avenue: twin towers, lintel block with the Earth Kingdom
##                seal, open bronze-studded leaves, a two-tier gate hall on top, giant banners
##   ring_wall    retaining wall of a tier step with a parapet: &"crenel", &"balustrade", &"plain"
##   wall_stair   stair segment rising along the inner face of a city wall (support mass below)
##   grand_stair  stone stair over a steep avenue ramp with cheek walls and lantern pillars
##   gate_arch    paifang gateway over a street (lacquered posts, three tile roofs, seal plaque)

static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	match kind:
		&"city_wall": city_wall(kit, spec)
		&"wall_tower": wall_tower(kit, spec)
		&"great_gate": great_gate(kit, spec)
		&"ring_wall": ring_wall(kit, spec)
		&"wall_stair": wall_stair(kit, spec)
		&"grand_stair": grand_stair(kit, spec)
		&"gate_arch": gate_arch(kit, spec)


## Archetype key of a wall piece (every spec value the recipe reads).
static func arch_of(kind: StringName, spec: Dictionary) -> String:
	var keys := spec.keys()
	keys.sort()
	var parts := PackedStringArray([String(kind)])
	for k: Variant in keys:
		var v: Variant = spec[k]
		if v is float:
			parts.append("%s=%d" % [k, roundi(float(v) * 10.0)])
		elif v is Array:
			var a := PackedStringArray()
			for x: Variant in v:
				a.append(str(roundi(float(x) * 10.0)))
			parts.append("%s=%s" % [k, ",".join(a)])
		else:
			parts.append("%s=%s" % [k, str(v)])
	return ":".join(parts)


# --- city walls ------------------------------------------------------------------------------------

## spec: L (drawn length, already including the overlap with the neighbours), H, T, bottom,
## v (variant), gap ([x0, x1] opening of the inner parapet), banner (bool), door (bool).
static func city_wall(kit: BuildingKit, spec: Dictionary) -> void:
	var _tone := int(spec.get("tone", 0))
	var _s1 := EkStyle.stone(_tone, 0)
	var _s2 := EkStyle.stone(_tone, 1)
	var _sd := EkStyle.stone(_tone, 2)
	var _st := EkStyle.stone(_tone, 3)
	var L := float(spec["L"])
	var H := float(spec["H"])
	var T := float(spec["T"])
	var bottom := float(spec.get("bottom", -2.0))
	var v := int(spec.get("v", 0))
	var hl := L * 0.5
	var bat := H * 0.06
	var zo := -T * 0.5
	var zi := T * 0.5
	var stone := _s1 if v % 2 == 0 else _s2
	KitX.prism_x(kit, -hl, hl, PackedVector2Array([Vector2(zo - bat, bottom), Vector2(zi + bat * 0.35, bottom), Vector2(zi, H), Vector2(zo, H)]), stone)
	kit.collide_box(Vector3(0, (H + bottom) * 0.5, 0), Vector3(L, H - bottom, T))
	# outer parapet: solid lower course + merlons
	var ph := 1.4
	kit.box(Vector3(0, H + ph * 0.5, zo + 0.5), Vector3(L, ph, 1.0), _s2, false)
	kit.collide_box(Vector3(0, H + 1.5, zo + 0.5), Vector3(L, 3.0, 1.0))
	if kit.lod >= 2:
		kit.box(Vector3(0, H + 2.0, zo + 0.5), Vector3(L, 1.2, 1.0), _s2, false)
		return
	# base plinth, string course under the parapet, walkway paving
	var face_z := func(y: float) -> float: return (zo - bat) + bat * (y - bottom) / (H - bottom)
	kit.box(Vector3(0, (bottom + 2.4) * 0.5, (zo - bat - 0.7 + zi + bat * 0.35 + 0.5) * 0.5),
			Vector3(L, 2.4 - bottom, (zi + bat * 0.35 + 0.5) - (zo - bat - 0.7)), _sd, false)
	var sy := H - 2.4
	kit.box(Vector3(0, sy, face_z.call(sy) - 0.2), Vector3(L, 0.6, 0.7), _sd, false)
	kit.box(Vector3(0, H - 0.4, zi + 0.15), Vector3(L, 0.5, 0.5), _sd, false)
	kit.box(Vector3(0, H + 0.03, (zo + 1.0 + zi - 0.8) * 0.5), Vector3(L, 0.06, zi - zo - 1.8), _st, false)
	# merlons with green tile copings
	var mw := 1.8
	var gap := 1.2
	var n := maxi(int(floor((L + gap) / (mw + gap))), 1)
	var start := (L - (n * mw + (n - 1) * gap)) * 0.5
	for i in n:
		var cx := -hl + start + i * (mw + gap) + mw * 0.5
		kit.box(Vector3(cx, H + ph + 0.65, zo + 0.5), Vector3(mw, 1.3, 1.0), _s2, false)
		if kit.lod == 0:
			kit.box(Vector3(cx, H + ph + 1.38, zo + 0.5), Vector3(mw + 0.2, 0.16, 1.2), EkStyle.COPING, false)
	# inner parapet (with a gap where a wall stair lands)
	var gp: Array = spec.get("gap", [])
	var segs := [[-hl, hl]] if gp.is_empty() else [[-hl, float(gp[0])], [float(gp[1]), hl]]
	for sg: Array in segs:
		var a := float(sg[0])
		var b := float(sg[1])
		if b - a < 0.2:
			continue
		kit.box(Vector3((a + b) * 0.5, H + 0.55, zi - 0.35), Vector3(b - a, 1.1, 0.7), _s2, true)
		if kit.lod == 0:
			kit.box(Vector3((a + b) * 0.5, H + 1.14, zi - 0.35), Vector3(b - a, 0.1, 0.85), EkStyle.COPING, false)
	# buttress at the chord start (outer) and a pilaster (inner): the rhythm of the wall
	var bh := H - 1.2
	KitX.prism_x(kit, -hl - 1.3, -hl + 1.3, PackedVector2Array([Vector2(zo - bat - 2.4, bottom), Vector2(zo, bottom), Vector2(zo + 0.2, bh), Vector2(zo - 0.9, bh)]),
			_s2 if v % 2 == 0 else _s1)
	kit.box(Vector3(-hl, (bottom + H - 1.0) * 0.5, zi + 0.3), Vector3(2.0, H - 1.0 - bottom, 0.9), _s2, false)
	if kit.lod == 0:
		# arrow slits (two rows on tall walls)
		var rows := [H - 6.5] if H < 24.0 else [H - 6.5, H - 14.0]
		var xs := -hl + 4.0
		while xs < hl - 2.5:
			for y: float in rows:
				kit.box(Vector3(xs, y, face_z.call(y) - 0.02), Vector3(0.42, 1.9, 0.3), &"window", false)
			xs += 6.0
		# block courses: grooves following the battered outer face, joints on the inner face
		var gy := 4.0
		while gy < H - 3.0:
			kit.box(Vector3(0, gy, face_z.call(gy) - 0.03), Vector3(L, 0.12, 0.12), _sd, false)
			gy += 2.6
		KitX.joints(kit, -hl + 1.2, hl, 2.4, H - 1.0, zi + 0.02, 3.0, 1.0, _sd)
		if spec.get("door", false):
			# storage gate in the inner face
			kit.box(Vector3(hl * 0.35, 2.4, zi + 0.36), Vector3(3.4, 4.8, 0.2), &"window", false)
			kit.box(Vector3(hl * 0.35, 5.0, zi + 0.5), Vector3(4.4, 0.6, 0.5), _sd, false)
			for sx: float in [-1.0, 1.0]:
				kit.box(Vector3(hl * 0.35 + sx * 1.95, 2.4, zi + 0.5), Vector3(0.5, 4.8, 0.5), _sd, false)
		if v % 2 == 0:
			KitX.lantern(kit, Vector3(hl * 0.5, H, zi - 1.6), {"style": &"post", "height": 2.0, "light": v % 4 == 0, "range": 10.0})
	if spec.get("banner", false):
		var tilt := asin(bat / (H - bottom))
		KitX.banner(kit, Transform3D(Basis(Vector3.RIGHT, tilt), Vector3(hl * 0.25, H - 0.6, face_z.call(H - 0.6) - 0.3)), 3.2,
				minf(H * 0.42, 15.0), EkStyle.CLOTH_GREEN, EkStyle.CLOTH_GOLD, &"earth", 2)


## Square bastion: spec S (width along the wall), H (wall height), T (wall thickness), out
## (protrusion beyond the outer face), top (extra height above the wall), roof (bool pavilion),
## bottom, v.
static func wall_tower(kit: BuildingKit, spec: Dictionary) -> void:
	var _tone := int(spec.get("tone", 0))
	var _s1 := EkStyle.stone(_tone, 0)
	var _s2 := EkStyle.stone(_tone, 1)
	var _sd := EkStyle.stone(_tone, 2)
	var _st := EkStyle.stone(_tone, 3)
	var S := float(spec.get("S", 14.0))
	var H := float(spec["H"])
	var T := float(spec["T"])
	var out := float(spec.get("out", 6.0))
	var Ht := H + float(spec.get("top", 7.0))
	var bottom := float(spec.get("bottom", -2.0))
	var v := int(spec.get("v", 0))
	var hs := S * 0.5
	var bat := Ht * 0.05
	var z0 := -T * 0.5 - out
	var z1 := T * 0.5 + 2.0
	KitX.prism_x(kit, -hs, hs, PackedVector2Array([Vector2(z0 - bat, bottom), Vector2(z1, bottom), Vector2(z1, Ht), Vector2(z0, Ht)]), _s2)
	# side faces are vertical: the prism's ends; battered outer face only
	kit.collide_box(Vector3(0, (Ht + bottom) * 0.5, (z0 + z1) * 0.5), Vector3(S, Ht - bottom, z1 - z0))
	var D := z1 - z0
	var cz := (z0 + z1) * 0.5
	var roof: bool = spec.get("roof", true)
	if kit.lod < 2:
		kit.box(Vector3(0, Ht - 0.45, cz), Vector3(S + 0.8, 0.9, D + 0.8), _sd, false)
		kit.box(Vector3(0, (bottom + 2.6) * 0.5, cz - bat * 0.5), Vector3(S + 1.2, 2.6 - bottom, D + bat + 1.2), _sd, false)
		# crenellated top ring
		var corners := PackedVector3Array([Vector3(-hs - 0.4, Ht, z0 - 0.4), Vector3(hs + 0.4, Ht, z0 - 0.4), Vector3(hs + 0.4, Ht, z1 + 0.4),
			Vector3(-hs - 0.4, Ht, z1 + 0.4)])
		for i in 4:
			kit.wall(corners[i], corners[(i + 1) % 4], 1.2, 0.8, {"role": _s1, "cap": false,
				"crenels": {"width": 1.4, "gap": 1.0, "height": 1.1, "role": _s1}})
	if kit.lod == 0:
		for y: float in [H * 0.55, H - 4.0, Ht - 3.0]:
			for sx: float in [-0.25, 0.25]:
				kit.box(Vector3(sx * S, y, z0 - bat * (1.0 - (y - bottom) / (Ht - bottom)) - 0.02), Vector3(0.45, 2.0, 0.3), &"window", false)
			kit.box(Vector3(-hs - 0.02, y, cz), Vector3(0.3, 2.0, 0.45), &"window", false)
			kit.box(Vector3(hs + 0.02, y, cz), Vector3(0.3, 2.0, 0.45), &"window", false)
	if v % 2 == 0 and kit.lod < 2:
		var tilt := asin(bat / (Ht - bottom))
		KitX.banner(kit, Transform3D(Basis(Vector3.RIGHT, tilt), Vector3(0, Ht - 1.4, z0 - 0.3 - bat * 1.4 / (Ht - bottom))), 3.4, minf(Ht * 0.45, 16.0),
				EkStyle.CLOTH_GREEN, EkStyle.CLOTH_GOLD, &"earth", 2)
	if not roof:
		return
	# pavilion: lacquered posts, emerald hip roof with gold ridges
	var pw := S - 3.0
	var pd := D - 4.0
	var ph := 3.6
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				kit.column(Vector3(sx * pw * 0.5, Ht, cz + sz * pd * 0.5), ph, 0.32, EkStyle.LACQUER, &"round", _sd)
			if kit.lod == 0:
				kit.column(Vector3(sx * pw * 0.17, Ht, cz - pd * 0.5), ph, 0.28, EkStyle.LACQUER, &"round", _sd)
		kit.beam(Vector3(-pw * 0.5, Ht + ph - 0.2, cz - pd * 0.5), Vector3(pw * 0.5, Ht + ph - 0.2, cz - pd * 0.5), 0.4, 0.4, EkStyle.COPING)
		kit.beam(Vector3(-pw * 0.5, Ht + ph - 0.2, cz + pd * 0.5), Vector3(pw * 0.5, Ht + ph - 0.2, cz + pd * 0.5), 0.4, 0.4, EkStyle.COPING)
		if kit.lod == 0:
			kit.lantern(Vector3(0, Ht + ph - 0.9, cz), {"style": &"paper", "range": 12.0, "energy": 1.8})
	else:
		kit.box(Vector3(0, Ht + ph * 0.5, cz), Vector3(pw, ph, pd), _sd, false)
	RoofsLite.hip(kit, Vector3(0, Ht + ph, cz), pw, pd, 3.2, EkStyle.roof_opts(EkStyle.PALACE, v, {"overhang": 1.4, "curve": 0.7}))
	if kit.lod < 2:
		kit.ornament(Vector3(0, Ht + ph + 3.3, cz), &"finial", 1.4, EkStyle.GOLD)


## Gatehouse over an avenue: spec W (opening width), H (wall height), T (wall thickness), D
## (depth of the gatehouse), Wt (tower width), Ho (opening height), bottom, v.
static func great_gate(kit: BuildingKit, spec: Dictionary) -> void:
	var _tone := int(spec.get("tone", 0))
	var _s1 := EkStyle.stone(_tone, 0)
	var _s2 := EkStyle.stone(_tone, 1)
	var _sd := EkStyle.stone(_tone, 2)
	var _st := EkStyle.stone(_tone, 3)
	var W := float(spec.get("W", 18.0))
	var H := float(spec["H"])
	var T := float(spec["T"])
	var D := float(spec.get("D", T + 10.0))
	var Wt := float(spec.get("Wt", 16.0))
	var Ho := float(spec.get("Ho", minf(H - 8.0, 24.0)))
	var bottom := float(spec.get("bottom", -2.0))
	var Hg := H + 6.0
	var hd := D * 0.5
	var hw := W * 0.5
	# twin towers (battered outer faces)
	for sx: float in [-1.0, 1.0]:
		var xa := sx * hw
		var xb := sx * (hw + Wt)
		var x0 := minf(xa, xb)
		var x1 := maxf(xa, xb)
		var bat := Hg * 0.05
		KitX.prism_x(kit, x0, x1, PackedVector2Array([Vector2(-hd - bat, bottom), Vector2(hd + bat * 0.5, bottom), Vector2(hd, Hg), Vector2(-hd, Hg)]), _s1)
		kit.collide_box(Vector3((x0 + x1) * 0.5, (Hg + bottom) * 0.5, 0), Vector3(x1 - x0, Hg - bottom, D))
		if kit.lod < 2:
			kit.box(Vector3((x0 + x1) * 0.5, (bottom + 3.0) * 0.5, 0), Vector3(x1 - x0 + 1.0, 3.0 - bottom, D + bat * 2.0 + 1.0), _sd, false)
			kit.box(Vector3((x0 + x1) * 0.5, Hg - 0.5, 0), Vector3(x1 - x0 + 0.8, 1.0, D + 0.8), _sd, false)
			# giant banners on the outer and inner faces (following the battered faces)
			var tilt := asin(bat / (Hg - bottom))
			KitX.banner(kit, Transform3D(Basis(Vector3.RIGHT, tilt), Vector3((x0 + x1) * 0.5, Hg - 1.6, -hd - 0.35 - bat * 1.6 / (Hg - bottom))), Wt * 0.42,
					minf(Hg * 0.62, 24.0), EkStyle.CLOTH_GREEN, EkStyle.CLOTH_GOLD, &"earth", 3)
			KitX.banner(kit, Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, tilt * 0.5), Vector3((x0 + x1) * 0.5, Hg - 1.6, hd + 0.35)), Wt * 0.36,
					minf(Hg * 0.5, 18.0), EkStyle.CLOTH_GREEN, EkStyle.CLOTH_GOLD, &"earth", 2)
			if kit.lod == 0:
				for y: float in [Hg * 0.45, Hg * 0.7]:
					kit.box(Vector3((x0 + x1) * 0.5 + sx * Wt * 0.3, y, -hd - Hg * 0.05 * (1.0 - y / Hg) - 0.02), Vector3(0.5, 2.2, 0.3), &"window", false)
	# lintel block over the opening
	kit.box(Vector3(0, (Ho + Hg) * 0.5, 0), Vector3(W + 0.2, Hg - Ho, D - 0.6), _s2)
	if kit.lod < 2:
		# stepped frame around the opening (outer and inner faces)
		for sz: float in [-1.0, 1.0]:
			var z: float = sz * (hd - 0.1)
			kit.box(Vector3(0, Ho + 0.9, z), Vector3(W + 2.6, 1.8, 0.9), _sd, false)
			for sx: float in [-1.0, 1.0]:
				kit.box(Vector3(sx * (hw + 0.6), Ho * 0.5, z), Vector3(1.2, Ho, 0.9), _sd, false)
			# soffit beams under the lintel
		for k in 4:
			kit.box(Vector3(0, Ho - 0.3, lerpf(-hd + 2.0, hd - 2.0, k / 3.0)), Vector3(W, 0.6, 1.0), _sd, false)
		# the Earth Kingdom seal over the gate
		KitX.emblem_earth(kit, Vector3(0, (Ho + Hg) * 0.5 + 0.4, -hd - 0.05), minf(Hg - Ho - 2.0, 7.0), EkStyle.GOLD, 0.25)
		# open bronze-studded leaves swung back against the passage walls (inner end)
		for sx: float in [-1.0, 1.0]:
			var lz := hd - 2.0 - hw * 0.5
			kit.box(Vector3(sx * (hw - 0.45), Ho * 0.48, lz), Vector3(0.7, Ho * 0.96, hw), &"door", false)
			if kit.lod == 0:
				for row in 5:
					var y := Ho * (0.12 + row * 0.19)
					kit.box(Vector3(sx * (hw - 0.85), y, lz), Vector3(0.12, 0.35, hw - 0.4), EkStyle.GOLD, false)
				kit.ornament(Vector3(sx * (hw - 0.92), Ho * 0.45, lz - hw * 0.3), &"orb", 0.7, EkStyle.GOLD)
	# gate hall on top: platform, posts, two-tier roof
	var top := Hg
	var hall_w := W + Wt * 2.0 - 8.0
	var hall_d := D - 7.0
	if kit.lod < 2:
		var cren := {"width": 1.6, "gap": 1.1, "height": 1.2, "role": _s1}
		var pts := PackedVector3Array([Vector3(-hw - Wt, top, -hd), Vector3(hw + Wt, top, -hd), Vector3(hw + Wt, top, hd), Vector3(-hw - Wt, top, hd)])
		for i in 4:
			kit.wall(pts[i], pts[(i + 1) % 4], 1.2, 0.8, {"role": _s1, "cap": false, "crenels": cren})
		kit.box(Vector3(0, top + 0.4, 0), Vector3(hall_w + 2.0, 0.8, hall_d + 2.0), _sd)
		var hh := 6.0
		var ncol := 6
		for i in ncol:
			var x := lerpf(-hall_w * 0.5, hall_w * 0.5, float(i) / (ncol - 1))
			for sz: float in [-1.0, 1.0]:
				kit.column(Vector3(x, top + 0.8, sz * hall_d * 0.5), hh, 0.45, EkStyle.LACQUER, &"round", _sd)
		kit.box(Vector3(0, top + 0.8 + hh * 0.5, 0), Vector3(hall_w - 1.5, hh, hall_d - 1.5), EkStyle.wall(EkStyle.PALACE, 0))
		if kit.lod == 0:
			for i in ncol - 1:
				var x := lerpf(-hall_w * 0.5, hall_w * 0.5, (i + 0.5) / (ncol - 1))
				KitX.window(kit, Vector3(x, top + 0.8 + hh * 0.55, -hall_d * 0.5 + 0.7), 1.6, 1.8, EkStyle.COPING, 0.06, i % 2 == 0)
			for sx: float in [-1.0, 1.0]:
				kit.lantern(Vector3(sx * hall_w * 0.3, top + 0.8 + hh - 1.0, -hall_d * 0.5 - 0.4), {"style": &"paper", "range": 14.0, "energy": 2.0})
		kit.beam(Vector3(-hall_w * 0.5, top + 0.8 + hh - 0.3, -hall_d * 0.5), Vector3(hall_w * 0.5, top + 0.8 + hh - 0.3, -hall_d * 0.5), 0.5, 0.6, EkStyle.COPING)
		var y1 := top + 0.8 + hh
		var ro := EkStyle.roof_opts(EkStyle.PALACE, int(spec.get("v", 0)), {"overhang": 2.0, "curve": 0.9, "ornaments": true})
		KitRoofs.hip(kit, Vector3(0, y1, 0), hall_w, hall_d, 3.2, ro.merged({"ridge": 1.0}, true))
		kit.box(Vector3(0, y1 + 2.4 + 1.6, 0), Vector3(hall_w * 0.66, 3.2, hall_d * 0.6), EkStyle.wall(EkStyle.PALACE, 1))
		KitRoofs.hip(kit, Vector3(0, y1 + 5.6, 0), hall_w * 0.66, hall_d * 0.6, 4.2, ro.merged({"overhang": 1.8, "finial": true}, true))
	else:
		kit.box(Vector3(0, top + 3.8, 0), Vector3(hall_w, 6.0, hall_d), EkStyle.wall(EkStyle.PALACE, 0), false)
		RoofsLite.hip(kit, Vector3(0, top + 6.8, 0), hall_w, hall_d, 4.0, EkStyle.roof_opts(EkStyle.PALACE, 0, {"overhang": 2.0}))
		RoofsLite.hip(kit, Vector3(0, top + 10.4, 0), hall_w * 0.66, hall_d * 0.6, 4.2, EkStyle.roof_opts(EkStyle.PALACE, 0, {"overhang": 1.8}))
	# braziers + lanterns at the outer foot
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			kit.brazier(Vector3(sx * (hw + 2.5), 0.0, -hd - 3.5), {"height": 1.2, "radius": 0.7, "range": 14.0})
			kit.lantern(Vector3(sx * (hw + 2.5), 0.0, hd + 3.0), {"style": &"stone", "height": 2.4})


# --- tier steps ---------------------------------------------------------------------------------

## Retaining wall of a tier step: face at z = 0 looking -Z (the lower side), body to `depth`
## behind it, y = 0 on the lower ground, the upper tier at H. spec: L, H, P (parapet height), depth,
## bottom, style (&"crenel" | &"balustrade" | &"plain"), v, end (pilaster at the start), banner.
static func ring_wall(kit: BuildingKit, spec: Dictionary) -> void:
	var _tone := int(spec.get("tone", 0))
	var _s1 := EkStyle.stone(_tone, 0)
	var _s2 := EkStyle.stone(_tone, 1)
	var _sd := EkStyle.stone(_tone, 2)
	var _st := EkStyle.stone(_tone, 3)
	var L := float(spec["L"])
	var H := float(spec["H"])
	var P := float(spec.get("P", 2.6))
	var depth := float(spec.get("depth", 5.0))
	var bottom := float(spec.get("bottom", -1.5))
	var style: StringName = spec.get("style", &"crenel")
	var v := int(spec.get("v", 0))
	var hl := L * 0.5
	var stone := _s1 if v % 2 == 0 else _s2
	kit.box(Vector3(0, (H + bottom) * 0.5, depth * 0.5), Vector3(L + 0.06, H - bottom, depth), stone)
	if kit.lod >= 2:
		if style == &"crenel":
			kit.box(Vector3(0, H + P * 0.5, 0.45), Vector3(L, P, 0.9), _s2, false)
		return
	kit.box(Vector3(0, (bottom + 1.6) * 0.5, -0.15), Vector3(L, 1.6 - bottom, 0.3), _sd, false)
	if H > 5.0:
		kit.box(Vector3(0, H - 1.0, -0.12), Vector3(L, 0.45, 0.3), _sd, false)
	if spec.get("end", true):
		kit.box(Vector3(-hl, (H + bottom) * 0.5, -0.35), Vector3(1.6, H - bottom, 0.7), _s2, false)
	if kit.lod == 0 and H > 3.0:
		KitX.joints(kit, -hl + 0.8, hl, 1.6, H - 1.3, 0.0, 1.6, -1.0, _sd)
	if H > 10.0:
		# tall terrace faces: pilasters, a frieze of small windows and dwellings cut into the wall
		kit.box(Vector3(hl * 0.05, (H + bottom) * 0.5, -0.25), Vector3(1.0, H - bottom, 0.5), _s2, false)
		if kit.lod == 0:
			for k in 3:
				KitX.window(kit, Vector3(-hl + L * (k + 0.5) / 3.0, H - 3.2, 0.0), 0.6, 0.8, EkStyle.COPING, 0.0, (v + k) % 4 == 0)
			if v % 3 == 1:
				KitX.doorway(kit, Vector3(-hl * 0.45, 0.0, 0.0), 1.5, 2.6, _sd, EkStyle.CLOTH_GREEN, 0.0)
				KitX.window(kit, Vector3(-hl * 0.45, 4.4, 0.0), 0.8, 0.9, EkStyle.COPING, 0.0, true)
				kit.box(Vector3(-hl * 0.45, 3.1, -0.45), Vector3(2.4, 0.15, 0.9), _sd, false)
				KitX.lantern(kit, Vector3(-hl * 0.45 + 1.3, 2.3, -0.15), {"style": &"wall", "light": v % 6 == 1, "range": 8.0})
	match style:
		&"crenel":
			kit.box(Vector3(0, H + (P - 1.1) * 0.5, 0.45), Vector3(L, P - 1.1, 0.9), _s2, false)
			kit.collide_box(Vector3(0, H + P * 0.5, 0.45), Vector3(L, P, 0.9))
			var mw := 1.5
			var gap := 1.0
			var n := maxi(int(floor((L + gap) / (mw + gap))), 1)
			var start := (L - (n * mw + (n - 1) * gap)) * 0.5
			for i in n:
				var cx := -hl + start + i * (mw + gap) + mw * 0.5
				kit.box(Vector3(cx, H + P - 0.55, 0.45), Vector3(mw, 1.1, 0.9), _s2, false)
				if kit.lod == 0:
					kit.box(Vector3(cx, H + P + 0.06, 0.45), Vector3(mw + 0.16, 0.14, 1.06), EkStyle.COPING, false)
			if kit.lod == 0 and v % 3 == 0:
				KitX.lantern(kit, Vector3(hl * 0.4, H, 1.6), {"style": &"post", "height": 1.8, "light": v % 6 == 0, "range": 9.0})
		&"balustrade":
			# white stone balustrade with lantern posts (views over the lower district)
			var rail_role := EkStyle.wall(EkStyle.UPPER, 2)
			kit.box(Vector3(0, H + 0.15, 0.35), Vector3(L, 0.3, 0.7), rail_role, false)
			kit.box(Vector3(0, H + 1.0, 0.35), Vector3(L, 0.16, 0.5), rail_role, false)
			kit.collide_box(Vector3(0, H + 0.6, 0.35), Vector3(L, 1.2, 0.6))
			var np := maxi(int(L / 2.2), 1)
			for i in np + 1:
				var x := -hl + L * float(i) / np
				kit.box(Vector3(x, H + 0.55, 0.35), Vector3(0.3, 0.9, 0.3), rail_role, false)
			if kit.lod == 0:
				for i in np:
					var x := -hl + L * (i + 0.5) / np
					kit.box(Vector3(x, H + 0.6, 0.35), Vector3(0.08, 0.6, 0.12), EkStyle.GOLD, false)
				KitX.lantern(kit, Vector3(-hl + 0.6, H, 0.35), {"style": &"stone", "height": 1.7, "light": v % 2 == 0, "range": 9.0})
		_:
			kit.box(Vector3(0, H + 0.5, 0.4), Vector3(L, 1.0, 0.8), _s2, true)
	if spec.get("banner", false) and H > 6.0:
		KitX.banner(kit, Transform3D(Basis(), Vector3(hl * 0.2, H - 1.4, -0.32)), 2.0, minf(H * 0.6, 10.0), EkStyle.CLOTH_GREEN, EkStyle.CLOTH_GOLD, &"earth")


## Stair segment rising along the inner face of a city wall: local x from -L/2 (y0) to +L/2 (y1),
## the stair strip at z = z0 .. z0 + w (inside the wall), a support mass down to the ground.
## spec: L, y0, y1, z0, w, top (bool: a landing reaching back onto the wall walk at the end).
static func wall_stair(kit: BuildingKit, spec: Dictionary) -> void:
	var _tone := int(spec.get("tone", 0))
	var _s1 := EkStyle.stone(_tone, 0)
	var _s2 := EkStyle.stone(_tone, 1)
	var _sd := EkStyle.stone(_tone, 2)
	var _st := EkStyle.stone(_tone, 3)
	var L := float(spec["L"])
	var y0 := float(spec["y0"])
	var y1 := float(spec["y1"])
	var z0 := float(spec.get("z0", 8.0))
	var w := float(spec.get("w", 4.0))
	var top: bool = spec.get("top", false)
	var hl := L * 0.5
	var run_end := hl - (w if top else 0.0)
	var ww := w + 0.6
	var zc := z0 + ww * 0.5
	var stone := _s2
	if y0 > 0.05:
		kit.box(Vector3((-hl + run_end) * 0.5, (y0 - 1.5) * 0.5, zc), Vector3(run_end + hl + 0.05, y0 + 1.5, ww), stone, false)
	kit.stairs(Vector3(-hl, y0, zc), Vector3(run_end, y1, zc), ww, {"role": _st, "rise": 0.2})
	# infill between the steps and the battered wall face (flush with the nosings; it sinks into
	# the wall's batter lower down) so there is no gap to fall into on the wall side
	kit.beam(Vector3(-hl, y0 - 0.6, z0 - 1.0), Vector3(run_end, y1 - 0.6, z0 - 1.0), 2.2, 1.2, stone, true)
	# outer parapet riding on the step ends + a green coping
	var zr := z0 + w + 0.3
	kit.beam(Vector3(-hl, y0 + 0.5, zr), Vector3(run_end, y1 + 0.5, zr), 0.6, 1.0, stone, true)
	if kit.lod == 0:
		kit.beam(Vector3(-hl, y0 + 1.05, zr), Vector3(run_end, y1 + 1.05, zr), 0.75, 0.12, EkStyle.COPING)
	if top:
		# landing back onto the wall walk (the chord's inner parapet has a gap here)
		kit.box(Vector3((run_end + hl) * 0.5, (y1 - 1.5) * 0.5, z0 + (ww - 2.6) * 0.5), Vector3(hl - run_end, y1 + 1.5, ww + 2.6), stone)
		kit.box(Vector3((run_end + hl) * 0.5, y1 + 0.5, zr), Vector3(hl - run_end, 1.0, 0.6), stone, true)
		if kit.lod == 0:
			kit.box(Vector3((run_end + hl) * 0.5, y1 + 0.02, z0 + (ww - 1.2) * 0.5), Vector3(hl - run_end, 0.04, ww + 1.2), _st, false)


## Stone stair over a steep avenue ramp (foot at the origin, climbing along -Z): spec H, R, W,
## half (z where the outside ground changes from the lower to the upper tier).
static func grand_stair(kit: BuildingKit, spec: Dictionary) -> void:
	var _tone := int(spec.get("tone", 0))
	var _s1 := EkStyle.stone(_tone, 0)
	var _s2 := EkStyle.stone(_tone, 1)
	var _sd := EkStyle.stone(_tone, 2)
	var _st := EkStyle.stone(_tone, 3)
	var H := float(spec["H"])
	var R := float(spec["R"])
	var W := float(spec.get("W", 22.0))
	var half := float(spec.get("half", R * 0.5))
	var sw := W - 4.0
	var steps: bool = spec.get("steps", true)
	if steps:
		kit.stairs(Vector3(0, 0.0, 0.0), Vector3(0, H, -R), sw, {"role": EkStyle.PAVING, "rise": 0.19})
	var nseg := maxi(int(R / 6.0), 2)
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (sw * 0.5 + 1.0)
		for k in nseg:
			var z0 := -R * k / nseg
			var z1 := -R * (k + 1) / nseg
			var ry1 := H * (k + 1) / nseg
			var ry0 := H * k / nseg
			var outside := 0.0 if -z1 <= half else H
			var top := maxf(ry1, outside)
			kit.box(Vector3(x, (top - 1.5) * 0.5, (z0 + z1) * 0.5), Vector3(2.0, top + 1.5, absf(z1 - z0) + 0.02), _s1)
			if outside < ry1 + 0.01 or -z0 < half:
				kit.beam(Vector3(x, ry0 + 0.55, z0), Vector3(x, ry1 + 0.55, z1), 1.4, 1.1, _s2, true)
		if kit.lod < 2:
			kit.beam(Vector3(x, 1.12, 0.0), Vector3(x, H + 1.12, -R), 1.6, 0.16, EkStyle.COPING)
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			for zz: float in [1.4, -R - 1.4]:
				var y := 0.0 if zz > 0.0 else H
				var p := Vector3(sx * (sw * 0.5 + 1.0), y, zz)
				kit.box(p + Vector3(0, 1.3, 0), Vector3(2.2, 2.6, 2.2), _s2, true)
				kit.box(p + Vector3(0, 2.7, 0), Vector3(2.5, 0.3, 2.5), _sd, false)
				KitX.lantern(kit, p + Vector3(0, 2.85, 0), {"style": &"stone", "height": 1.8, "light": zz > 0.0, "range": 11.0})
		# landing strips mid-flight (darker paving bands)
		if kit.lod == 0 and steps:
			for k in range(1, 4):
				var t := float(k) / 4.0
				kit.box(Vector3(0, H * t + 0.02, -R * t), Vector3(sw, 0.04, 0.5), EkStyle.PAVING_DARK, false)


## Paifang gateway over a street (passage along local Z): spec span (clear width), height.
static func gate_arch(kit: BuildingKit, spec: Dictionary) -> void:
	var span := float(spec.get("span", 10.0))
	var h := float(spec.get("height", 7.0))
	var side := span * 0.32
	var xs := [-span * 0.5 - side, -span * 0.5, span * 0.5, span * 0.5 + side]
	for i in 4:
		var x: float = xs[i]
		var ph := h if i == 1 or i == 2 else h * 0.78
		kit.column(Vector3(x, 0, 0), ph, 0.42, EkStyle.LACQUER, &"round", EkStyle.WALL_DARK)
		if kit.lod < 2:
			kit.box(Vector3(x, 0.6, 0), Vector3(1.3, 1.2, 1.3), EkStyle.WALL_DARK, false)
	var ro := EkStyle.roof_opts(EkStyle.UPPER, 0, {"overhang": 0.8, "curve": 0.6})
	kit.box(Vector3(0, h - 0.4, 0), Vector3(span + 1.0, 0.8, 0.9), EkStyle.COPING, true)
	RoofsLite.hip(kit, Vector3(0, h + 0.6, 0), span + 1.2, 1.4, 1.3, ro)
	for sx: float in [-1.0, 1.0]:
		var cx: float = sx * (span * 0.5 + side * 0.5)
		kit.box(Vector3(cx, h * 0.78 - 0.35, 0), Vector3(side + 0.8, 0.7, 0.8), EkStyle.COPING, false)
		RoofsLite.hip(kit, Vector3(cx, h * 0.78 + 0.35, 0), side + 1.0, 1.2, 1.0, ro)
	if kit.lod < 2:
		kit.box(Vector3(0, h - 1.5, 0), Vector3(span * 0.45, 1.3, 0.5), EkStyle.GOLD, false)
		KitX.emblem_earth(kit, Vector3(0, h - 1.5, -0.25), 1.1, EkStyle.COPING, 0.06)
		kit.beam(Vector3(-span * 0.5 - side, h * 0.6, 0), Vector3(span * 0.5 + side, h * 0.6, 0), 0.4, 0.5, EkStyle.LACQUER)
