class_name NwtLandmarks
extends RefCounted
## The great structures of the Northern Water Tribe (BuildingKit recipes, thread-safe):
##   sea_wall     one chord of the great sea wall across the bay mouth. Local: x along the wall,
##                the ocean face at z = -T/2 (looking -Z), the bay face at +T/2, y = 0 at sea
##                level, walkway on top at `top`. Blind arcade on the ocean face, giant banners,
##                crenellated parapets both sides, braziers on the walk.
##   sea_tower    round guard tower standing on the wall (or at its bends), domed lookout.
##   sea_gate     the bay gate: two colossal towers with ice spires flanking the ship passage,
##                a lintel bridge carrying the walkway with the moon-and-waves emblem.
##   palace       the Chief's palace on its platform: domed hall, portico, towers with spires.
##   land_gate    gatehouse closing a tier end (local: passage along Z, wall along X).
##   city_tower   round tower with a tall ice spire for city walls and skyline accents.

const SEA_THICK := 24.0


static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	match kind:
		&"sea_wall": sea_wall(kit, spec)
		&"sea_tower": sea_tower(kit, spec)
		&"sea_gate": sea_gate(kit, spec)
		&"palace": palace(kit, spec)
		&"land_gate": land_gate(kit, spec)
		&"city_tower": city_tower(kit, spec)


static func sea_wall(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec["L"])
	var top := float(spec.get("top", 35.0))
	var base := float(spec.get("base", -7.0))
	var T := float(spec.get("thick", SEA_THICK))
	var v := int(spec.get("v", 0))
	var hl := L * 0.5
	var ht := T * 0.5
	kit.box(Vector3(0, (top + base) * 0.5, 0), Vector3(L + 0.05, top - base, T), &"wall")
	if kit.lod >= 2:
		kit.box(Vector3(0, top - 3.0, -ht - 0.2), Vector3(L, 1.4, 0.5), &"trim", false)
		kit.box(Vector3(0, top + 1.0, -ht + 0.6), Vector3(L, 2.0, 1.2), &"wall", false)
		kit.box(Vector3(0, top + 1.0, ht - 0.6), Vector3(L, 2.0, 1.2), &"wall", false)
		return
	for side: float in [-1.0, 1.0]:
		var fz: float = side * ht
		var out: float = side
		# wave-washed plinth
		kit.box(Vector3(0, 0.8, fz + out * 0.35), Vector3(L, 4.0, 0.7), &"base", false)
		# trim bands under the parapet
		kit.box(Vector3(0, top - 3.0, fz + out * 0.25), Vector3(L, 1.4, 0.5), &"trim", false)
		kit.box(Vector3(0, top - 2.1, fz + out * 0.15), Vector3(L, 0.3, 0.3), &"trim_alt", false)
		# parapet with rounded merlons along both edges of the walkway
		KitX.merlons(kit, Vector3(-hl + 0.4, top, fz - out * 0.7), Vector3(hl - 0.4, top, fz - out * 0.7), 1.4, 1.6, 1.5, 0.8, &"wall")
		if kit.lod == 0:
			KitX.icicles(kit, Vector3(-hl, top - 3.7, fz + out * 0.5), Vector3(hl, top - 3.7, fz + out * 0.5), 0.8, 1.6)
	# ocean face: blind arcade of tall arched niches (two per chord)
	var oz := -ht
	for k in 2:
		var cx := -hl + L * (k + 0.5) / 2.0
		var aw := minf(L * 0.32, 6.5)
		var ah := (top - 6.0) * 0.72
		kit.box(Vector3(cx, 3.0 + ah * 0.5, oz - 0.05), Vector3(aw, ah, 0.12), &"wall_alt", false)
		var segs := 8 if kit.lod == 0 else 4
		for i in segs:
			var a0 := PI * i / segs
			var a1 := PI * (i + 1) / segs
			var p0 := Vector3(cx + cos(a0) * aw * 0.5, 3.0 + ah + sin(a0) * aw * 0.5, oz - 0.3)
			var p1 := Vector3(cx + cos(a1) * aw * 0.5, 3.0 + ah + sin(a1) * aw * 0.5, oz - 0.3)
			kit.beam(p0, p1, 0.9, 0.9, &"wall_alt")
			if kit.lod == 0:
				kit.g().flat_tri(Vector3(cx, 3.0 + ah, oz - 0.08), p1 + Vector3(0, 0, 0.22), p0 + Vector3(0, 0, 0.22), kit.col(&"wall_alt"))
		for sx: float in [-1.0, 1.0]:
			kit.box(Vector3(cx + sx * (aw * 0.5 + 0.45), 3.0 + ah * 0.5, oz - 0.35), Vector3(0.9, ah, 0.7), &"wall_alt", false)
	# pilaster at the chord joint (both faces)
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(-hl, (top + base) * 0.5 + 0.5, side * (ht + 0.6)), Vector3(2.6, top - base + 1.0, 1.2), &"wall_alt", true)
		if kit.lod == 0:
			kit.box(Vector3(-hl, top + 1.2, side * (ht + 0.4)), Vector3(3.0, 0.5, 1.8), &"trim", false)
	# giant banners on the ocean face, braziers on the walkway
	if v % 2 == 0:
		KitX.banner(kit, Transform3D(Basis(), Vector3(0, top - 3.8, oz - 0.55)), 3.0, minf(top * 0.5, 16.0))
	if v % 2 == 1:
		KitX.banner(kit, Transform3D(Basis(Vector3.UP, PI), Vector3(0, top - 3.8, ht + 0.55)), 2.4, minf(top * 0.38, 12.0))
	if kit.lod == 0:
		kit.box(Vector3(0, top + 0.05, 0), Vector3(L, 0.1, T - 3.0), &"snow", false)
		# walkway paving lines
		for k in 3:
			kit.box(Vector3(0, top + 0.11, (k - 1) * T * 0.25), Vector3(L, 0.03, 0.2), &"wall_alt", false)
		if v % 3 == 0:
			kit.push(Transform3D(Basis(), Vector3(hl * 0.5, top, -ht + 3.0)))
			NwtProps.brazier(kit, 0)
			kit.pop()
			kit.push(Transform3D(Basis(), Vector3(-hl * 0.5, top, ht - 3.0)))
			NwtProps.brazier(kit, 1)
			kit.pop()


## Round guard tower on the wall walk: drum rising `h` above `base_y` with a domed lookout.
static func sea_tower(kit: BuildingKit, spec: Dictionary) -> void:
	var r := float(spec.get("r", 6.0))
	var base_y := float(spec.get("base", -7.0))
	var h := float(spec.get("h", 52.0))
	var spire := float(spec.get("spire", 0.0))
	kit.cylinder(Vector3(0, base_y, 0), h - base_y, r, &"wall", 20, true)
	if kit.lod < 2:
		kit.cylinder(Vector3(0, h - 4.0, 0), 1.0, r + 0.25, &"trim", 20, false)
		kit.cylinder(Vector3(0, h - 0.4, 0), 0.6, r + 1.2, &"wall_alt", 20, true)
		for k in 12:
			var a := TAU * k / 12.0
			kit.box(Vector3(cos(a) * (r + 0.8), h + 0.8, sin(a) * (r + 0.8)), Vector3(1.4, 1.6, 1.0), &"wall", false)
		if kit.lod == 0:
			for k in 4:
				var a := TAU * k / 4.0 + PI * 0.25
				var dir := Vector3(cos(a), 0, sin(a))
				kit.push(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z) + PI), dir * (r - 0.02) + Vector3(0, h - 8.0, 0)))
				KitX.window(kit, Vector3.ZERO, 0.8, 1.6, &"trim", 0.0, true)
				kit.pop()
			KitX.icicles(kit, Vector3(-r * 0.7, h - 4.0, -r * 0.75), Vector3(r * 0.7, h - 4.0, -r * 0.75), 1.0, 1.0)
	if spire > 0.0:
		KitRoofs.cone(kit, Vector3(0, h + 1.6, 0), r * 0.75, spire, {"role": NwtStyle.spire(0), "alt_role": NwtStyle.spire(1), "slot": &"ice",
			"flare": 0.12, "trim_role": &"trim", "finial_role": &"trim", "sides": 16})
		kit.cylinder(Vector3(0, h, 0), 1.6, r * 0.78, &"wall_alt", 16, true)
	else:
		kit.cylinder(Vector3(0, h, 0), 1.6, r * 0.6, &"wall_alt", 16, true)
		KitRoofs.dome(kit, Vector3(0, h + 1.6, 0), r * 0.62, {"squash": 0.9, "role": NwtStyle.dome(0), "rib_role": &"wall_alt", "slot": &"ice",
			"finial": kit.lod < 2, "finial_role": &"trim"})
	if kit.lod < 2 and spec.get("brazier", true):
		kit.push(Transform3D(Basis(), Vector3(r * 0.55, h, -r * 0.55)))
		NwtProps.brazier(kit, 0)
		kit.pop()


## The bay gate: passage width W along local X centred at the origin, towers on both sides,
## lintel bridge at the walkway height. spec: W, top, base.
static func sea_gate(kit: BuildingKit, spec: Dictionary) -> void:
	var W := float(spec.get("W", 46.0))
	var top := float(spec.get("top", 35.0))
	var base := float(spec.get("base", -7.0))
	var T := SEA_THICK
	var tw := 18.0
	var clear := top - 9.0
	for sx: float in [-1.0, 1.0]:
		var cx: float = sx * (W * 0.5 + tw * 0.5)
		# tower body: square core with round corner turrets
		kit.box(Vector3(cx, (top + 12.0 + base) * 0.5, 0), Vector3(tw, top + 12.0 - base, T + 6.0), &"wall")
		for cz: float in [-1.0, 1.0]:
			var tc := Vector3(cx + sx * tw * 0.25, 0, cz * (T * 0.5 + 3.0))
			kit.cylinder(tc + Vector3(0, base, 0), top + 20.0 - base, 4.2, &"wall_alt", 16, true)
			if kit.lod < 2:
				kit.cylinder(tc + Vector3(0, top + 16.0, 0), 0.9, 4.5, &"trim", 16, false)
			KitRoofs.cone(kit, tc + Vector3(0, top + 20.0, 0), 4.6, 15.0, {"role": NwtStyle.spire(0), "alt_role": NwtStyle.spire(1), "slot": &"ice",
				"flare": 0.15, "trim_role": &"trim", "finial_role": &"trim", "sides": 16})
		# central spire over each tower
		kit.cylinder(Vector3(cx, top + 12.0, 0), 6.0, 6.5, &"wall_alt", 18, true)
		KitRoofs.cone(kit, Vector3(cx, top + 18.0, 0), 7.2, 26.0, {"role": NwtStyle.spire(0), "alt_role": NwtStyle.spire(1), "slot": &"ice",
			"flare": 0.1, "trim_role": &"trim", "finial_role": &"trim", "sides": 18})
		if kit.lod < 2:
			kit.box(Vector3(cx, top + 11.2, 0), Vector3(tw + 1.0, 1.6, T + 7.0), &"trim", false)
			kit.box(Vector3(cx, 0.8, 0), Vector3(tw + 1.2, 4.0, T + 7.2), &"base", false)
			for face: float in [-1.0, 1.0]:
				# waterbender alcoves facing the passage + banners on the ocean face
				kit.push(Transform3D(Basis(Vector3.UP, -sx * PI * 0.5), Vector3(cx - sx * tw * 0.5, 0, face * T * 0.25)))
				KitX.doorway(kit, Vector3(0, 3.0, 0), 3.0, 6.0, &"trim", null, 0.0)
				kit.pop()
			KitX.banner(kit, Transform3D(Basis(), Vector3(cx, top + 8.0, -T * 0.5 - 3.1)), 4.0, 22.0)
			KitX.banner(kit, Transform3D(Basis(Vector3.UP, PI), Vector3(cx, top + 8.0, T * 0.5 + 3.1)), 3.2, 16.0)
			if kit.lod == 0:
				for k in 3:
					kit.push(Transform3D(Basis(), Vector3(cx + (k - 1) * 4.5, top + 3.0 + k % 2 * 2.0, -T * 0.5 - 3.05)))
					KitX.window(kit, Vector3.ZERO, 1.0, 2.2, &"trim", 0.0, true)
					kit.pop()
	# the great ice gate leaves, swung open into the bay against the passage walls
	for sx: float in [-1.0, 1.0]:
		var lw := W * 0.5 - 1.0
		kit.box(Vector3(sx * (W * 0.5 - 1.8), (clear - 1.5) * 0.5 + base * 0.0 - 1.0, T * 0.5 + lw * 0.5 - 0.5), Vector3(2.4, clear + 1.5, lw),
				NwtStyle.dome(1), true, &"ice")
		if kit.lod < 2:
			for k in 3:
				kit.box(Vector3(sx * (W * 0.5 - 3.05), clear * (0.25 + k * 0.25), T * 0.5 + lw * 0.5 - 0.5), Vector3(0.2, 0.8, lw - 1.0), NwtStyle.navy(), false)
	# lintel bridge over the passage carrying the walkway; underside arch
	var span := W + 2.0
	kit.box(Vector3(0, (top + clear) * 0.5, 0), Vector3(span, top - clear, T), &"wall")
	if kit.lod < 2:
		var segs := 12 if kit.lod == 0 else 6
		for face: float in [-1.0, 1.0]:
			for i in segs:
				var a0 := PI * i / segs
				var a1 := PI * (i + 1) / segs
				var p0 := Vector3(-cos(a0) * W * 0.5, clear - 6.0 + sin(a0) * 6.0, face * (T * 0.5 + 0.2))
				var p1 := Vector3(-cos(a1) * W * 0.5, clear - 6.0 + sin(a1) * 6.0, face * (T * 0.5 + 0.2))
				kit.beam(p0, p1, 1.6, 1.6, &"trim")
			kit.box(Vector3(0, top - 3.0, face * (T * 0.5 + 0.3)), Vector3(span, 1.4, 0.6), &"trim", false)
			KitX.merlons(kit, Vector3(-span * 0.5, top, face * (T * 0.5 - 0.7)), Vector3(span * 0.5, top, face * (T * 0.5 - 0.7)), 1.4, 1.6, 1.5, 0.8)
		# the great emblem on the ocean face
		KitX.emblem_water(kit, Vector3(0, (top + clear) * 0.5 + 0.5, -T * 0.5 - 0.2), 11.0, NwtStyle.navy(), 0.4)
		KitX.emblem_water(kit, Vector3(0, (top + clear) * 0.5 + 0.5, T * 0.5 + 0.2), 8.0, NwtStyle.navy(), -0.3)
		if kit.lod == 0:
			KitX.icicles(kit, Vector3(-W * 0.5, clear - 0.2, -T * 0.5), Vector3(W * 0.5, clear - 0.2, -T * 0.5), 0.6, 2.4)
			kit.box(Vector3(0, top + 0.05, 0), Vector3(span, 0.1, T - 3.0), &"snow", false)
			for sx: float in [-1.0, 1.0]:
				kit.push(Transform3D(Basis(), Vector3(sx * 10.0, top, 0)))
				NwtProps.brazier(kit, 0)
				kit.pop()


## The Chief's palace on its raised platform (origin = platform centre at platform height,
## front = -Z towards the bay). spec: r (platform radius), drop (platform height above the tier).
static func palace(kit: BuildingKit, spec: Dictionary) -> void:
	var pr := float(spec.get("r", 48.0))
	var drop := float(spec.get("drop", 4.0))
	# platform rim wall (polygon ring) + front stair
	var n := 24 if kit.lod == 0 else 12
	var ring := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		ring.append(Vector2(cos(a), sin(a)) * pr)
	kit.slab(ring, -drop - 1.0, 0.0, &"wall_alt", false, &"floor")
	if kit.lod < 2:
		var rim := PackedVector3Array()
		for i in n + 1:
			var a := TAU * i / n
			rim.append(Vector3(cos(a) * (pr - 0.3), 0, sin(a) * (pr - 0.3)))
		for i in n:
			var a := TAU * (i + 0.5) / n
			if absf(wrapf(a - PI * 1.5, -PI, PI)) < 0.25:
				continue
			kit.beam(rim[i] + Vector3(0, 0.45, 0), rim[i + 1] + Vector3(0, 0.45, 0), 0.5, 0.9, &"wall", true)
			kit.beam(rim[i] - Vector3(0, drop * 0.5, 0) + Vector3(cos(a), 0, sin(a)) * 0.4, rim[i + 1] - Vector3(0, drop * 0.5, 0) + Vector3(cos(a), 0, sin(a)) * 0.4, 0.3, 0.4, &"trim")
	kit.stairs(Vector3(0, -drop, -pr - drop * 3.2), Vector3(0, 0.0, -pr + 0.5), 16.0, {"role": &"wall_alt", "sides": true, "side_role": &"trim"})
	# main hall
	var w := 52.0
	var d := 30.0
	var h := 17.0
	var hz := -2.0
	kit.box(Vector3(0, h * 0.5, hz), Vector3(w, h, d), &"wall")
	if kit.lod < 2:
		kit.box(Vector3(0, 0.6, hz), Vector3(w + 0.6, 1.2, d + 0.6), &"base", false)
		kit.box(Vector3(0, h - 1.0, hz), Vector3(w + 0.3, 0.8, d + 0.3), &"trim", false)
		kit.box(Vector3(0, h - 0.3, hz), Vector3(w + 0.6, 0.3, d + 0.6), &"trim_alt", false)
		KitX.merlons(kit, Vector3(-w * 0.5 + 0.5, h, hz - d * 0.5 + 0.4), Vector3(w * 0.5 - 0.5, h, hz - d * 0.5 + 0.4), 0.8, 1.2, 1.2, 0.6)
		KitX.merlons(kit, Vector3(-w * 0.5 + 0.5, h, hz + d * 0.5 - 0.4), Vector3(w * 0.5 - 0.5, h, hz + d * 0.5 - 0.4), 0.8, 1.2, 1.2, 0.6)
		# tall windows on the facade
		for i in 8:
			var wx := lerpf(-w * 0.42, w * 0.42, i / 7.0)
			if absf(wx) < 5.0:
				continue
			KitX.window(kit, Vector3(wx, 8.0, hz - d * 0.5), 1.5, 4.6, NwtStyle.navy(), 0.0, i % 3 == 0)
		if kit.lod == 0:
			KitX.joints(kit, -w * 0.5, w * 0.5, 1.2, h - 1.4, hz - d * 0.5, 1.4)
			KitX.icicles(kit, Vector3(-w * 0.5, h - 1.4, hz - d * 0.5 - 0.2), Vector3(w * 0.5, h - 1.4, hz - d * 0.5 - 0.2), 0.8, 1.2)
	# portico: ice columns, pediment with the emblem, great door
	var pz := hz - d * 0.5 - 5.5
	for i in 8:
		var cx := lerpf(-16.0, 16.0, i / 7.0)
		kit.column(Vector3(cx, 0.0, pz), 13.0, 0.95, &"ice", &"ice", &"wall_alt")
	kit.box(Vector3(0, 13.7, pz + 2.2), Vector3(35.0, 1.6, 6.0), &"wall", true)
	if kit.lod < 2:
		kit.box(Vector3(0, 13.0, pz - 0.8), Vector3(35.2, 0.5, 0.5), NwtStyle.navy(), false)
		KitX.emblem_water(kit, Vector3(0, 16.4, pz - 0.4), 4.6, NwtStyle.navy(), 0.1)
		kit.box(Vector3(0, 16.0, pz + 1.0), Vector3(13.0, 3.4, 1.0), &"wall_alt", false)
		kit.door(Transform3D(Basis(), Vector3(0, 0, hz - d * 0.5 - 0.05)), 5.0, 8.0, {"frame_role": &"trim", "leaf": &"closed", "thickness": 0.5})
	# great dome on a drum
	kit.cylinder(Vector3(0, h, hz), 6.0, 14.0, &"wall_alt", 24, true)
	if kit.lod < 2:
		kit.cylinder(Vector3(0, h + 5.3, hz), 0.7, 14.3, NwtStyle.navy(), 24, false)
		if kit.lod == 0:
			for k in 12:
				var a := TAU * k / 12.0
				var dir := Vector3(cos(a), 0, sin(a))
				kit.push(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z) + PI), dir * 13.98 + Vector3(0, h + 2.8, hz)))
				KitX.window(kit, Vector3.ZERO, 0.7, 1.8, &"trim", 0.0, k % 2 == 0)
				kit.pop()
	KitRoofs.dome(kit, Vector3(0, h + 6.0, hz), 14.6, {"squash": 0.95, "role": NwtStyle.dome(2), "rib_role": &"wall_alt", "slot": &"ice",
		"finial": true, "finial_role": &"trim"})
	# towers: two front, two back corners, the high keep behind the dome
	var towers := [[Vector3(-w * 0.5 - 2.5, 0, hz - d * 0.5 + 1.5), 5.4, 40.0, 20.0], [Vector3(w * 0.5 + 2.5, 0, hz - d * 0.5 + 1.5), 5.4, 40.0, 20.0],
		[Vector3(-w * 0.5 - 1.0, 0, hz + d * 0.5), 4.2, 30.0, 14.0], [Vector3(w * 0.5 + 1.0, 0, hz + d * 0.5), 4.2, 30.0, 14.0],
		[Vector3(0, 0, hz + d * 0.5 + 7.0), 7.0, 60.0, 30.0], [Vector3(-14.0, 0, hz + d * 0.5 + 4.0), 3.6, 46.0, 16.0],
		[Vector3(14.0, 0, hz + d * 0.5 + 4.0), 3.6, 46.0, 16.0]]
	for t: Array in towers:
		var tc: Vector3 = t[0]
		var tr: float = t[1]
		var th: float = t[2]
		kit.cylinder(tc, th, tr, &"wall", 18, true)
		if kit.lod < 2:
			for band in [th * 0.35, th * 0.7]:
				kit.cylinder(tc + Vector3(0, band, 0), 0.6, tr + 0.15, &"trim", 18, false)
			kit.cylinder(tc + Vector3(0, th - 0.3, 0), 0.6, tr + 1.0, &"wall_alt", 18, true)
			if kit.lod == 0:
				for k in 10:
					var a := TAU * k / 10.0
					kit.box(tc + Vector3(cos(a) * (tr + 0.65), th + 0.75, sin(a) * (tr + 0.65)), Vector3(0.9, 1.1, 0.9), &"wall", false)
				for k in 3:
					var a := PI * 0.5 + (k - 1) * 0.9 + PI
					var dir := Vector3(cos(a), 0, sin(a))
					kit.push(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z) + PI), dir * (tr - 0.02) + Vector3(0, th * 0.82, 0) + tc))
					KitX.window(kit, Vector3.ZERO, 0.7, 1.6, &"trim", 0.0, true)
					kit.pop()
		kit.cylinder(tc + Vector3(0, th, 0), 2.2, tr * 0.8, &"wall_alt", 16, true)
		KitRoofs.cone(kit, tc + Vector3(0, th + 2.2, 0), tr * 0.95, t[3], {"role": NwtStyle.spire(1), "alt_role": NwtStyle.spire(2), "slot": &"ice",
			"flare": 0.12, "trim_role": &"trim", "finial_role": &"trim", "sides": 16})
	# side wings with small domes
	for sx: float in [-1.0, 1.0]:
		var wc := Vector3(sx * (w * 0.5 + 8.5), 0, hz + 3.0)
		kit.box(wc + Vector3(0, 5.5, 0), Vector3(13.0, 11.0, 18.0), &"wall_alt")
		if kit.lod < 2:
			kit.box(wc + Vector3(0, 10.6, 0), Vector3(13.3, 0.6, 18.3), NwtStyle.navy(), false)
			for k in 3:
				KitX.window(kit, wc + Vector3((k - 1) * 4.0, 5.5, -9.0), 1.0, 2.2, NwtStyle.navy(), 0.0, k == 1)
		KitRoofs.dome(kit, wc + Vector3(0, 11.0, 0), 5.6, {"squash": 0.85, "role": NwtStyle.dome(0), "rib_role": &"wall_alt", "slot": &"ice",
			"finial": kit.lod < 2, "finial_role": &"trim"})
	# banners, braziers, sculptures on the forecourt
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			KitX.banner(kit, Transform3D(Basis(), Vector3(sx * 9.0, h - 1.6, hz - d * 0.5 - 0.3)), 2.8, 12.0)
			KitX.banner(kit, Transform3D(Basis(), Vector3(sx * 19.0, h - 1.6, hz - d * 0.5 - 0.3)), 2.8, 12.0)
			kit.push(Transform3D(Basis(), Vector3(sx * 11.0, 0, -pr + 6.0)))
			NwtProps.brazier(kit, 0)
			kit.pop()
			kit.push(Transform3D(Basis(), Vector3(sx * 24.0, 0, -pr + 14.0)))
			NwtProps.sculpture(kit, 1 if sx < 0.0 else 0)
			kit.pop()
	kit.mark(&"door", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, pz - 3.0)))


## Gatehouse closing a tier end: passage (width W, height h) along local Z through a wall of
## length span along X. spec: W, h, span, depth.
static func land_gate(kit: BuildingKit, spec: Dictionary) -> void:
	var W := float(spec.get("W", 14.0))
	var h := float(spec.get("h", 10.0))
	var dep := float(spec.get("depth", 10.0))
	for sx: float in [-1.0, 1.0]:
		var cx: float = sx * (W * 0.5 + 5.0)
		kit.box(Vector3(cx, (h + 8.0) * 0.5 - 0.6, 0), Vector3(10.0, h + 8.0 + 1.2, dep), &"wall")
		kit.cylinder(Vector3(cx + sx * 3.0, -1.0, -dep * 0.5), h + 15.0, 3.6, &"wall_alt", 16, true)
		KitRoofs.cone(kit, Vector3(cx + sx * 3.0, h + 14.0, -dep * 0.5), 4.0, 12.0, {"role": NwtStyle.spire(0), "alt_role": NwtStyle.spire(1), "slot": &"ice",
			"flare": 0.12, "trim_role": &"trim", "finial_role": &"trim", "sides": 16})
		if kit.lod < 2:
			kit.box(Vector3(cx, h + 5.0, 0), Vector3(10.3, 0.8, dep + 0.3), &"trim", false)
			KitX.banner(kit, Transform3D(Basis(), Vector3(cx, h + 4.0, -dep * 0.5 - 0.2)), 1.8, 8.0)
			kit.push(Transform3D(Basis(), Vector3(cx - sx * 3.0, 0, -dep * 0.5 - 3.0)))
			NwtProps.brazier(kit, 0)
			kit.pop()
	kit.box(Vector3(0, h + 4.0, 0), Vector3(W + 0.2, 8.0, dep), &"wall")
	if kit.lod < 2:
		kit.box(Vector3(0, h + 0.3, 0), Vector3(W, 0.6, dep + 0.4), &"trim", false)
		KitX.emblem_water(kit, Vector3(0, h + 4.0, -dep * 0.5 - 0.1), 4.5, &"trim", 0.1)
		KitX.merlons(kit, Vector3(-W * 0.5 - 9.0, h + 8.0, -dep * 0.5 + 0.5), Vector3(W * 0.5 + 9.0, h + 8.0, -dep * 0.5 + 0.5), 1.0, 1.2)
		KitX.merlons(kit, Vector3(-W * 0.5 - 9.0, h + 8.0, dep * 0.5 - 0.5), Vector3(W * 0.5 + 9.0, h + 8.0, dep * 0.5 - 0.5), 1.0, 1.2)
		KitX.icicles(kit, Vector3(-W * 0.5, h, -dep * 0.5 - 0.2), Vector3(W * 0.5, h, -dep * 0.5 - 0.2), 1.0, 1.2)


## Round tower with an ice spire (city walls, skyline accents). spec: r, h, spire, base.
static func city_tower(kit: BuildingKit, spec: Dictionary) -> void:
	var r := float(spec.get("r", 3.5))
	var h := float(spec.get("h", 18.0))
	var base := float(spec.get("base", -1.5))
	var tint := NwtStyle.wall(int(h) + int(r * 10.0))
	kit.cylinder(Vector3(0, base, 0), h - base, r, tint, 16, true)
	if kit.lod < 2:
		kit.cylinder(Vector3(0, h * 0.55, 0), 0.5, r + 0.12, NwtStyle.navy(), 16, false)
		kit.cylinder(Vector3(0, h - 1.0, 0), 0.6, r + 0.1, NwtStyle.navy(), 16, false)
		kit.cylinder(Vector3(0, h - 0.2, 0), 0.5, r + 0.7, &"wall_alt", 16, true)
		if kit.lod == 0:
			for k in 8:
				var a := TAU * k / 8.0
				kit.box(Vector3(cos(a) * (r + 0.45), h + 0.6, sin(a) * (r + 0.45)), Vector3(0.8, 0.9, 0.8), &"wall", false)
			kit.push(Transform3D(Basis(), Vector3(0, h * 0.75, -r + 0.02)))
			KitX.window(kit, Vector3.ZERO, 0.6, 1.3, &"trim", 0.0, true)
			kit.pop()
	kit.cylinder(Vector3(0, h, 0), 1.6, r * 0.78, &"wall_alt", 14, true)
	KitRoofs.cone(kit, Vector3(0, h + 1.6, 0), r * 0.92, float(spec.get("spire", r * 3.6)), {"role": NwtStyle.spire(int(h) % 3), "alt_role": NwtStyle.spire(int(h) % 3 + 1),
		"slot": &"ice", "flare": 0.12, "trim_role": &"trim", "finial_role": &"trim", "sides": 14})
