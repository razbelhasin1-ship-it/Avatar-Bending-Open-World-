class_name OmashuCity
extends RefCounted
## Omashu's own structures (BuildingKit recipes, thread-safe; the rest of the city uses the Earth
## Kingdom recipes in warm sandstone, EkStyle.OMASHU / tone 1):
##   omashu_bridge     the Great Bridge over the chasm: a humped stone deck with crenellated
##                     parapets and lantern posts, two great arches springing from a central pier
##                     and the cliff abutments down to the chasm floor, spandrels, guardian
##                     badgermoles at the rim. Local frame: centre of the span, the rim towards -Z.
##                     spec: L, W, y0 / y1 (deck height at the city / rim end), floor (chasm floor)
##   omashu_chute      one segment of a mail chute: a U-shaped stone trough from spec a to b (local),
##                     on pillars down to the terraces (ga / gb: ground at the ends)
##   omashu_chute_hub  the chute station: round platform, a funnel basin where the chutes arrive,
##                     a sorting booth under a green roof, mail sacks and crates

const KINDS: Array[StringName] = [&"omashu_bridge", &"omashu_chute", &"omashu_chute_hub"]


static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	match kind:
		&"omashu_bridge": bridge(kit, spec)
		&"omashu_chute": chute(kit, spec)
		&"omashu_chute_hub": chute_hub(kit, spec)


static func deck_y(spec: Dictionary, t: float) -> float:
	# t = 0 at the city end (+Z), 1 at the rim (-Z)
	var hump := float(spec.get("L", 64.0)) * 0.03
	return lerpf(float(spec.get("y0", 0.0)), float(spec.get("y1", 0.0)), t) + hump * sin(t * PI)


static func bridge(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec.get("L", 64.0))
	var W := float(spec.get("W", 14.0))
	var fl := float(spec.get("floor", -70.0))
	var hl := L * 0.5
	var hw := W * 0.5
	var s1 := EkStyle.stone(1, 0)
	var s2 := EkStyle.stone(1, 1)
	var sd := EkStyle.stone(1, 2)
	var st := EkStyle.stone(1, 3)
	var n := 16 if kit.lod == 0 else 8
	var zt := func(t: float) -> float: return lerpf(hl, -hl, t)
	var deck_th := 1.6
	# deck + walkable surface
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var a := Vector3(0, deck_y(spec, t0), zt.call(t0))
		var b := Vector3(0, deck_y(spec, t1), zt.call(t1))
		kit.beam(a - Vector3(0, deck_th * 0.5, 0), b - Vector3(0, deck_th * 0.5, 0), W, deck_th, s1)
		if kit.lod < 2:
			kit.beam(a + Vector3(0, 0.02, 0), b + Vector3(0, 0.02, 0), W - 2.2, 0.04, st)
		kit.collide_quad(Vector3(-hw, a.y, a.z), Vector3(hw, a.y, a.z), Vector3(hw, b.y, b.z), Vector3(-hw, b.y, b.z))
		# crenellated parapets
		for sx: float in [-1.0, 1.0]:
			var x: float = sx * (hw - 0.4)
			kit.beam(Vector3(x, a.y + 0.6, a.z), Vector3(x, b.y + 0.6, b.z), 0.8, 1.2, s2, true)
			if kit.lod == 0:
				var mid := (a + b) * 0.5
				kit.box(Vector3(x, mid.y + 1.6, mid.z), Vector3(0.8, 0.8, 1.6), s2, false)
				kit.box(Vector3(x, mid.y + 2.06, mid.z), Vector3(1.0, 0.14, 1.8), EkStyle.COPING, false)
	# central pier and the two arches down into the chasm
	var pier_t := 0.5
	var pz: float = zt.call(pier_t)
	var py := deck_y(spec, pier_t) - deck_th
	kit.box(Vector3(0, (py + fl) * 0.5, pz), Vector3(W + 2.0, py - fl, 7.0), s2)
	if kit.lod < 2:
		kit.box(Vector3(0, fl + 6.0, pz), Vector3(W + 4.0, 12.0, 9.0), sd, false)
		for sx: float in [-1.0, 1.0]:
			kit.box(Vector3(sx * (hw + 1.4), (py + fl) * 0.5, pz), Vector3(0.8, py - fl, 3.0), s1, false)
	for half in 2:
		var ta := 0.0 if half == 0 else pier_t
		var tb := pier_t if half == 0 else 1.0
		var za: float = zt.call(ta)
		var zb: float = zt.call(tb)
		var span := absf(zb - za)
		var spring := fl + (py - fl) * 0.35
		var rise := (py - 1.0) - spring
		var segs := 12 if kit.lod == 0 else 6
		var prev := Vector3.ZERO
		for k in segs + 1:
			var u := float(k) / segs
			var z := lerpf(za, zb, u)
			var y := spring + rise * sin(u * PI)
			var p := Vector3(0, y, z)
			if k > 0:
				for sx: float in [-1.0, 1.0]:
					kit.beam(prev + Vector3(sx * (hw - 0.6), 0, 0), p + Vector3(sx * (hw - 0.6), 0, 0), 1.4, 1.6, sd)
				# spandrel fill between the arch ring and the deck
				var dz := absf(p.z - prev.z)
				var top := deck_y(spec, lerpf(ta, tb, u - 0.5 / segs)) - deck_th
				var bot := (prev.y + p.y) * 0.5 + 0.6
				if top - bot > 0.3:
					kit.box(Vector3(0, (top + bot) * 0.5, (prev.z + p.z) * 0.5), Vector3(W - 0.4, top - bot, dz + 0.05), s1, false)
				# soffit under the arch
				if kit.lod < 2:
					kit.beam(prev + Vector3(0, -0.6, 0), p + Vector3(0, -0.6, 0), W - 1.6, 0.5, sd)
			prev = p
		# abutments at the cliffs: solid masonry down to the floor
		if half == 0:
			var ay := deck_y(spec, 0.0) - deck_th
			kit.box(Vector3(0, (ay + fl) * 0.5, hl - 2.0), Vector3(W + 3.0, ay - fl, 6.0), s2)
		else:
			var ay2 := deck_y(spec, 1.0) - deck_th
			kit.box(Vector3(0, (ay2 + fl) * 0.5, -hl + 2.0), Vector3(W + 3.0, ay2 - fl, 6.0), s2)
	if kit.lod >= 2:
		return
	# lantern pillars along the parapets, guardian badgermoles at the rim end
	for k in 5:
		var t := float(k) / 4.0
		var y := deck_y(spec, t)
		for sx: float in [-1.0, 1.0]:
			var p := Vector3(sx * (hw - 0.4), y + 1.2, zt.call(t))
			kit.box(p + Vector3(0, 0.9, 0), Vector3(1.1, 1.8, 1.1), s2, true)
			KitX.lantern(kit, p + Vector3(0, 1.8, 0), {"style": &"stone", "height": 1.6, "light": k % 2 == 0, "range": 11.0, "role": s1})
	var ry := deck_y(spec, 1.0)
	for sx: float in [-1.0, 1.0]:
		kit.push(Transform3D(Basis(Vector3.UP, PI), Vector3(sx * (hw + 3.2), ry, -hl + 1.0)))
		EkProps.statue(kit, 0)
		kit.pop()
		KitX.banner(kit, Transform3D(Basis(), Vector3(sx * (hw + 0.1), deck_y(spec, 0.5) - 0.5, zt.call(0.5) - 3.6)), 3.0, 16.0,
				EkStyle.CLOTH_GREEN, EkStyle.CLOTH_GOLD, &"earth", 2)


static func chute(kit: BuildingKit, spec: Dictionary) -> void:
	var a: Vector3 = spec["a"]
	var b: Vector3 = spec["b"]
	var s1 := EkStyle.stone(1, 0)
	var sd := EkStyle.stone(1, 2)
	var dir := (b - a)
	var len := dir.length()
	if len < 0.5:
		return
	var side := Vector3(-dir.z, 0, dir.x).normalized()
	# trough: bed + two low walls (U profile), inner channel polished
	kit.beam(a - Vector3(0, 0.15, 0), b - Vector3(0, 0.15, 0), 1.3, 0.3, s1)
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			kit.beam(a + side * sx * 0.58 + Vector3(0, 0.22, 0), b + side * sx * 0.58 + Vector3(0, 0.22, 0), 0.16, 0.5, s1)
		kit.beam(a + Vector3(0, 0.01, 0), b + Vector3(0, 0.01, 0), 0.9, 0.04, EkStyle.stone(1, 3))
	# pillars down to the ground (at the start; the last segment also at its end)
	var ga := float(spec.get("ga", 0.0))
	var gb := float(spec.get("gb", 0.0))
	for e: Array in [[a, ga], [b, gb]]:
		var p: Vector3 = e[0]
		var g := float(e[1])
		var hgt := p.y - 0.3 - g
		if hgt < 0.4:
			continue
		kit.box(Vector3(p.x, g + hgt * 0.5, p.z), Vector3(0.7, hgt, 0.7), sd if kit.lod < 2 else s1, true)
		if kit.lod == 0:
			kit.box(Vector3(p.x, p.y - 0.42, p.z), Vector3(1.1, 0.24, 1.1), EkStyle.COPING, false)
			kit.box(Vector3(p.x, g + 0.3, p.z), Vector3(1.0, 0.6, 1.0), s1, false)


static func chute_hub(kit: BuildingKit, _spec: Dictionary) -> void:
	var s1 := EkStyle.stone(1, 0)
	var s2 := EkStyle.stone(1, 1)
	var sides := 20 if kit.lod == 0 else 10
	var ring := PackedVector2Array()
	for i in sides:
		var ang := TAU * i / sides
		ring.append(Vector2(cos(ang), sin(ang)) * 7.0)
	kit.slab(ring, -0.3, 0.3, s2, true)
	# funnel basin where the chutes arrive
	kit.g().cylinder(Vector3(2.5, 0.3, 2.5), Vector3(2.5, 1.6, 2.5), 1.4, 2.4, 12, kit.col(s1), 0)
	kit.g().cylinder(Vector3(2.5, 1.55, 2.5), Vector3(2.5, 1.6, 2.5), 2.2, 2.2, 12, kit.col(EkStyle.stone(1, 2)), 2)
	kit.collide_box(Vector3(2.5, 0.95, 2.5), Vector3(3.6, 1.3, 3.6))
	# sorting booth
	kit.box(Vector3(-2.4, 0.3 + 1.4, 1.6), Vector3(4.0, 2.8, 3.0), EkStyle.wall(EkStyle.OMASHU, 1))
	RoofsLite.hip(kit, Vector3(-2.4, 3.1, 1.6), 4.0, 3.0, 1.6, EkStyle.roof_opts(EkStyle.OMASHU, 0, {"overhang": 0.8}))
	if kit.lod >= 2:
		return
	EkHomes.door(kit, Vector3(-2.4, 0.3, 0.08), 1.1, 2.1, EkStyle.timber(EkStyle.OMASHU))
	kit.box(Vector3(-2.4, 1.3, 0.0), Vector3(2.6, 0.12, 0.6), EkStyle.timber(EkStyle.OMASHU), false)
	if kit.lod == 0:
		for k in 6:
			var a := TAU * k / 6.0
			var sp := Vector3(-3.5 + cos(a) * 1.2, 0.3, -2.2 + sin(a) * 0.9)
			kit.g().blob(sp + Vector3(0, 0.35, 0), 0.36, 0, kit.col(Color(0.78, 0.70, 0.52).srgb_to_linear()), null, 0.0, Vector3(1.0, 0.8, 0.9))
		kit.push(Transform3D(Basis(), Vector3(4.6, 0.3, -2.6)))
		EkProps.crates(kit, 1)
		kit.pop()
		kit.lantern(Vector3(-2.4, 2.6, -0.4), {"style": &"paper", "range": 8.0})


static func extras(_piece: Dictionary) -> Array:
	return []


static func glows(piece: Dictionary) -> Array:
	var out: Array = []
	if piece["kind"] == &"omashu_bridge":
		var spec: Dictionary = piece["spec"]
		var hl := float(spec.get("L", 64.0)) * 0.5
		var hw := float(spec.get("W", 14.0)) * 0.5
		for k in 5:
			var t := float(k) / 4.0
			for sx: float in [-1.0, 1.0]:
				out.append([SettlementBuilder.at(piece, Vector3(sx * (hw - 0.4), deck_y(spec, t) + 4.2, lerpf(hl, -hl, t))), SettlementFx.GLOW_LAMP, 1.1])
	elif piece["kind"] == &"omashu_chute_hub":
		out.append([SettlementBuilder.at(piece, Vector3(-2.4, 2.6, -0.4)), SettlementFx.GLOW_LAMP, 1.0])
	return out
