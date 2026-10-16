class_name NwtCivic
extends RefCounted
## Water Tribe civic architecture (BuildingKit recipes, thread-safe):
##   tier_wall    one chord of a retaining / quay / canal wall. Local frame: x along the wall
##                (-L/2..L/2), the FACE at z = 0 looking -Z towards the lower side, the body behind
##                it (z 0..depth), y = 0 at the lower ground / water, top flush with the upper
##                ground at H. Styles: &"tier" (pilasters, trim band, banners, dwellings in the
##                wall, rounded-merlon parapet), &"quay" (bollards, mooring rings, no parapet),
##                &"canal" (low coping with a curb), &"end" (plain parapet wall).
##   grand_stair  ice staircase over a radial ramp with cheek walls, lantern pillars at the foot
##                and a gateway arch at the top. Local: foot at the origin, climbing towards -Z.
##   canal_bridge arched ice footbridge crossing along local Z (deck flush with both banks).
##   pier         harbour pier: plank deck on ice piles, mooring posts, lantern, along -Z.
##   plaza        inlaid tile disc with the moon-and-waves mosaic.
##   gateway      free-standing arch over a street (two pylons with spires, emblem lintel).


static func build(kit: BuildingKit, kind: StringName, spec: Dictionary) -> void:
	match kind:
		&"tier_wall": tier_wall(kit, spec)
		&"grand_stair": grand_stair(kit, spec)
		&"canal_bridge": canal_bridge(kit, spec)
		&"pier": pier(kit, spec)
		&"plaza": plaza(kit, spec)
		&"gateway": gateway(kit, spec)


## Archetype key of a wall chord (lengths quantised by the planner).
static func wall_arch(spec: Dictionary) -> String:
	return "tier_wall:%s:%d:%d:%d:%d:%d" % [spec.get("style", &"tier"), roundi(float(spec["L"]) * 10.0),
		roundi(float(spec["H"]) * 10.0), roundi(float(spec.get("bottom", -1.2)) * 10.0), int(spec.get("v", 0)),
		int(spec.get("pilaster_end", false))]


static func tier_wall(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec["L"])
	var H := float(spec["H"])
	var depth := float(spec.get("depth", 5.6))
	var bottom := float(spec.get("bottom", -1.2))
	var style: StringName = spec.get("style", &"tier")
	var v := int(spec.get("v", 0))
	var hl := L * 0.5
	var body_role: StringName = &"wall" if style != &"quay" else &"wall_alt"
	kit.box(Vector3(0, (H + bottom) * 0.5, depth * 0.5), Vector3(L + 0.04, H - bottom, depth), body_role)
	if kit.lod >= 2:
		if style == &"tier" and H > 4.0:
			kit.box(Vector3(0, H - 1.2, -0.08), Vector3(L, 0.6, 0.2), &"trim", false)
		return
	match style:
		&"tier", &"end":
			# plinth course, trim band, pilasters, parapet
			kit.box(Vector3(0, 0.55, -0.12), Vector3(L, 1.5, 0.26), &"base", false)
			if H > 4.0:
				kit.box(Vector3(0, H - 1.25, -0.1), Vector3(L, 0.5, 0.22), &"trim", false)
				kit.box(Vector3(0, H - 0.9, -0.05), Vector3(L, 0.14, 0.12), &"trim_alt", false)
				KitX.icicles(kit, Vector3(-hl, H - 1.5, -0.22), Vector3(hl, H - 1.5, -0.22), 1.1, 0.9)
			for px in ([-hl, hl] if spec.get("pilaster_end", false) else [-hl]):
				kit.box(Vector3(px, (H + bottom) * 0.5 + 0.2, -0.35), Vector3(1.3, H - bottom + 0.4, 0.75), &"wall_alt", true)
				kit.box(Vector3(px, H + 0.35, -0.1), Vector3(1.6, 0.3, 1.2), &"trim", false)
				if kit.lod == 0:
					kit.box(Vector3(px, 0.4, -0.45), Vector3(1.5, 0.8, 0.95), &"base", false)
					kit.ornament(Vector3(px, H + 1.15, 0.2), &"orb", 0.55, &"ice")
					kit.box(Vector3(px, H + 0.85, 0.2), Vector3(0.7, 0.7, 0.7), &"wall_alt", false)
			KitX.merlons(kit, Vector3(-hl + 0.5, H, 0.38), Vector3(hl - 0.5, H, 0.38), 0.75, 0.95, 0.95, 0.5, &"wall")
			if kit.lod == 0:
				kit.box(Vector3(0, H + 0.04, depth * 0.55), Vector3(L, 0.08, depth * 0.7), &"snow", false)
				KitX.joints(kit, -hl + 0.7, hl - 0.2, 1.3, H - 1.5, 0.0, 1.5)
			if style == &"tier" and H > 9.0:
				if v % 2 == 0:
					var bl := minf(H * 0.55, 10.0)
					kit.banner(Transform3D(Basis(), Vector3(hl * 0.15, H - 1.0, -0.28)), 1.7, bl, {"role": &"cloth", "alt_role": &"cloth_alt"})
				if v % 4 == 1:
					# a dwelling in the wall: arched door + windows above
					KitX.doorway(kit, Vector3(-hl * 0.3, 0.0, 0.0), 1.4, 2.4, &"trim", &"cloth", 0.0)
					KitX.window(kit, Vector3(-hl * 0.3, 4.2, 0.0), 0.7, 0.9, &"trim", 0.0, true)
					if kit.lod == 0:
						kit.box(Vector3(-hl * 0.3, 2.85, -0.45), Vector3(2.4, 0.15, 0.9), &"trim", false)
						kit.lantern(Vector3(-hl * 0.3 + 1.3, 2.1, -0.15), {"style": &"wall", "light": true, "range": 8.0})
				elif v % 4 == 3:
					for k in 2:
						KitX.window(kit, Vector3(lerpf(-hl * 0.5, hl * 0.4, k), H * 0.42, 0.0), 0.6, 0.85, &"trim", 0.0, k == 0)
		&"quay":
			kit.box(Vector3(0, H - 0.15, -0.12), Vector3(L, 0.3, 0.3), &"trim", false)
			kit.box(Vector3(0, 0.05, -0.1), Vector3(L, 0.5, 0.25), &"base", false)
			for k in maxi(int(L / 6.0), 1):
				var bx := -hl + (k + 0.5) * L / maxi(int(L / 6.0), 1)
				kit.cylinder(Vector3(bx, H, 0.5), 0.7, 0.22, &"stone_dark", 8, true, 0.18)
				if kit.lod == 0:
					kit.g().cylinder(Vector3(bx, H + 0.55, 0.5), Vector3(bx, H + 0.62, 0.5), 0.26, 0.26, 8, kit.col(&"trim"), 2)
					var ring := PackedVector3Array()
					for j in 9:
						var a := TAU * j / 8.0
						ring.append(Vector3(bx + cos(a) * 0.22, H - 0.9 + sin(a) * 0.22, -0.16))
					var rr := PackedFloat32Array()
					rr.resize(ring.size())
					rr.fill(0.03)
					kit.g().tube(ring, rr, 3, kit.col(&"metal"))
			if v % 3 == 0 and kit.lod == 0:
				# steps down to the water along the face
				for k in int(H / 0.3):
					kit.box(Vector3(-hl * 0.4 + k * 0.32, H - 0.15 - k * 0.3, -0.55), Vector3(0.32, 0.3, 1.1), &"wall_alt", false)
				kit.collide_quad(Vector3(-hl * 0.4 - 0.16, H, -1.1), Vector3(-hl * 0.4 - 0.16, H, 0.0),
						Vector3(-hl * 0.4 + int(H / 0.3) * 0.32, 0.0, 0.0), Vector3(-hl * 0.4 + int(H / 0.3) * 0.32, 0.0, -1.1))
			if kit.lod == 0:
				kit.box(Vector3(0, H + 0.03, depth * 0.5), Vector3(L, 0.06, depth * 0.8), &"snow", false)
		&"canal":
			kit.box(Vector3(0, H - 0.12, -0.18), Vector3(L, 0.24, 0.36), &"trim", false)
			kit.box(Vector3(0, H + 0.16, 0.25), Vector3(L - 0.2, 0.32, 0.45), &"wall_alt", true)
			if kit.lod == 0:
				KitX.joints(kit, -hl, hl, 0.0, H - 0.3, 0.0, 0.7)
				if v % 2 == 0:
					kit.cylinder(Vector3(hl * 0.4, H + 0.3, 0.6), 0.6, 0.15, &"wood_dark", 6, true)


## Grand ice staircase over a ramp: rise H over run R (local -Z), width W of the ramp strip.
## spec: H, R, W, half (z where the outside ground switches from the lower to the upper tier).
static func grand_stair(kit: BuildingKit, spec: Dictionary) -> void:
	var H := float(spec["H"])
	var R := float(spec["R"])
	var W := float(spec.get("W", 16.0))
	var half := float(spec.get("half", R * 0.5))
	var sw := W - 4.0
	kit.stairs(Vector3(0, 0.0, 0.0), Vector3(0, H, -R), sw, {"role": &"wall_alt", "rise": 0.2})
	# cheek walls (2 m thick) on both sides
	var nseg := maxi(int(R / 4.0), 2)
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (sw * 0.5 + 1.0)
		for k in nseg:
			var z0 := -R * k / nseg
			var z1 := -R * (k + 1) / nseg
			var ry0 := H * k / nseg
			var ry1 := H * (k + 1) / nseg
			var outside := 0.0 if -z1 <= half else H
			var top := maxf(ry1, outside)
			kit.box(Vector3(x, (top - 1.2) * 0.5, (z0 + z1) * 0.5), Vector3(2.0, top + 1.2, absf(z1 - z0) + 0.02), &"wall")
			if outside < ry1 + 0.01 or -z0 < half:
				# sloped parapet along the stairs
				kit.beam(Vector3(x, ry0 + 0.55, z0), Vector3(x, ry1 + 0.55, z1), 1.6, 1.1, &"wall_alt", true)
		if kit.lod < 2:
			kit.beam(Vector3(x, 1.12, 0.0), Vector3(x, H + 1.12, -R), 1.75, 0.22, &"trim")
	# lantern pillars at the foot, gateway at the top
	if kit.lod < 2:
		for sx: float in [-1.0, 1.0]:
			var p := Vector3(sx * (sw * 0.5 + 1.0), 0.0, 1.2)
			kit.box(p + Vector3(0, 1.6, 0), Vector3(2.0, 3.2, 2.0), &"wall_alt", true)
			kit.box(p + Vector3(0, 3.3, 0), Vector3(2.3, 0.3, 2.3), &"trim", false)
			kit.push(Transform3D(Basis(), p + Vector3(0, 3.45, 0)))
			NwtProps.lamp_post(kit, 1, true)
			kit.pop()
	kit.push(Transform3D(Basis(), Vector3(0, H, -R + 1.5)))
	gateway(kit, {"span": sw + 2.0, "height": 8.0})
	kit.pop()


## Free-standing gateway: two pylons with ice spires and an emblem lintel (local XY plane,
## passage along Z). spec: span (clear width), height (clear).
static func gateway(kit: BuildingKit, spec: Dictionary) -> void:
	var span := float(spec.get("span", 8.0))
	var h := float(spec.get("height", 7.0))
	var pw := 1.8
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (span * 0.5 + pw * 0.5)
		kit.box(Vector3(x, h * 0.5, 0), Vector3(pw, h, pw), &"wall_alt", true)
		if kit.lod < 2:
			kit.box(Vector3(x, 0.4, 0), Vector3(pw + 0.4, 0.8, pw + 0.4), &"base", false)
			kit.box(Vector3(x, h * 0.62, 0), Vector3(pw + 0.12, 0.4, pw + 0.12), &"trim", false)
			if kit.lod == 0:
				kit.banner(Transform3D(Basis(), Vector3(x, h * 0.58, -pw * 0.5 - 0.05)), 1.2, h * 0.45, {"role": &"cloth", "alt_role": &"cloth_alt"})
		KitRoofs.cone(kit, Vector3(x, h + 1.6, 0), pw * 0.62, 4.5, {"role": NwtStyle.spire(0), "alt_role": NwtStyle.spire(1), "slot": &"ice", "flare": 0.1,
			"trim_role": &"trim", "finial_role": &"trim", "sides": 10})
	# lintel: a deep blue beam with a white cornice and the emblem
	kit.box(Vector3(0, h + 0.8, 0), Vector3(span + pw * 2.0 + 0.4, 1.6, pw * 0.9), &"wall", true)
	if kit.lod < 2:
		kit.box(Vector3(0, h + 0.2, 0), Vector3(span + pw * 2.0 + 0.2, 0.4, pw * 0.95), &"trim", false)
		kit.box(Vector3(0, h + 1.7, 0), Vector3(span + pw * 2.0 + 0.8, 0.25, pw + 0.3), &"trim_alt", false)
		KitX.emblem_water(kit, Vector3(0, h + 0.95, -pw * 0.45), 1.3, &"trim", 0.05)
		KitX.icicles(kit, Vector3(-span * 0.5, h, -pw * 0.45), Vector3(span * 0.5, h, -pw * 0.45), 1.2, 0.6)


## Arched footbridge crossing along local Z: spec span (bank to bank), width, hump.
static func canal_bridge(kit: BuildingKit, spec: Dictionary) -> void:
	var span := float(spec.get("span", 9.0))
	var w := float(spec.get("width", 5.0))
	var hump := float(spec.get("hump", 0.7))
	var land := 2.2
	var total := span + land * 2.0
	var n := 8 if kit.lod == 0 else 4
	var deck := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / n
		var z := lerpf(-total * 0.5, total * 0.5, t)
		var y := hump * sin(t * PI)
		deck.append(Vector3(0, y, z))
	for i in n:
		var a := deck[i]
		var b := deck[i + 1]
		kit.beam(a - Vector3(0, 0.3, 0), b - Vector3(0, 0.3, 0), w, 0.6, &"wall_alt")
		kit.collide_quad(Vector3(-w * 0.5, a.y, a.z), Vector3(w * 0.5, a.y, a.z), Vector3(w * 0.5, b.y, b.z), Vector3(-w * 0.5, b.y, b.z))
		for sx: float in [-1.0, 1.0]:
			var x: float = sx * (w * 0.5 - 0.22)
			kit.beam(Vector3(x, a.y + 0.45, a.z), Vector3(x, b.y + 0.45, b.z), 0.44, 0.9, &"wall", true)
			if kit.lod == 0:
				kit.beam(Vector3(x, a.y + 0.95, a.z), Vector3(x, b.y + 0.95, b.z), 0.56, 0.12, &"trim")
	# arch ring under the deck on both faces
	if kit.lod < 2:
		var segs := 9 if kit.lod == 0 else 5
		for sx: float in [-1.0, 1.0]:
			var x: float = sx * (w * 0.5 - 0.3)
			for k in segs:
				var u0 := PI * k / segs
				var u1 := PI * (k + 1) / segs
				var p0 := Vector3(x, -0.6 - span * 0.32 + sin(u0) * span * 0.32, -cos(u0) * span * 0.5)
				var p1 := Vector3(x, -0.6 - span * 0.32 + sin(u1) * span * 0.32, -cos(u1) * span * 0.5)
				kit.beam(p0, p1, 0.5, 0.5, &"trim")
			kit.box(Vector3(x, -1.6, 0.0), Vector3(0.4, 2.0, span * 0.6), &"wall_alt", false)
		# end posts with ice lanterns
		for sz: float in [-1.0, 1.0]:
			for sx: float in [-1.0, 1.0]:
				var p := Vector3(sx * (w * 0.5 - 0.22), 0.0, sz * (total * 0.5 - 0.3))
				kit.box(p + Vector3(0, 0.75, 0), Vector3(0.6, 1.5, 0.6), &"wall_alt", true)
				if kit.lod == 0:
					kit.ornament(p + Vector3(0, 1.75, 0), &"orb", 0.5, &"ice")
					if sz > 0.0 and sx > 0.0 and int(spec.get("v", 0)) % 2 == 0:
						kit.add_light(p + Vector3(0, 2.0, 0), Color(1.0, 0.85, 0.6), 8.0, 1.2, 0)
						var gb := kit.g(&"glow")
						gb.uv = Vector2(0, 0.5)
						gb.blob(p + Vector3(0, 1.75, 0), 0.18, 0, Color(1.0, 0.86, 0.6))


## Harbour pier along local -Z (length L, width W) from the quay edge (origin at deck level).
## spec: L, W, depth (water depth below the deck), head (T-head width, 0 = none).
static func pier(kit: BuildingKit, spec: Dictionary) -> void:
	var L := float(spec.get("L", 24.0))
	var W := float(spec.get("W", 4.5))
	var dep := float(spec.get("depth", 12.0))
	var head := float(spec.get("head", 0.0))
	var planks := int(L / 0.6) if kit.lod == 0 else 1
	if kit.lod == 0:
		for i in planks:
			var z := -L * (i + 0.5) / planks
			kit.box(Vector3(0, -0.08, z), Vector3(W + kit.rng.randf_range(-0.1, 0.1), 0.16, 0.55), &"wood" if i % 6 else &"wood_dark", false)
	else:
		kit.box(Vector3(0, -0.08, -L * 0.5), Vector3(W, 0.16, L), &"wood", false)
	kit.collide_box(Vector3(0, -0.2, -L * 0.5), Vector3(W, 0.4, L))
	# beams + ice piles
	kit.box(Vector3(0, -0.4, -L * 0.5), Vector3(W - 0.4, 0.5, L), &"wood_dark", false)
	var np := maxi(int(L / 5.0), 2)
	for i in np + 1:
		var z := -L * i / np
		for sx: float in [-1.0, 1.0]:
			kit.cylinder(Vector3(sx * (W * 0.5 - 0.25), -dep, z), dep - 0.3, 0.35, &"wall_alt", 8, i > 0, 0.3)
			if kit.lod == 0 and i > 0 and i % 2 == 0:
				kit.cylinder(Vector3(sx * (W * 0.5 + 0.1), 0.0, z), 0.8, 0.13, &"wood_dark", 6, true)
	if head > 0.0:
		var hz := -L - 2.0
		kit.box(Vector3(0, -0.1, hz), Vector3(head, 0.2, 4.0), &"wood", true)
		kit.box(Vector3(0, -0.45, hz), Vector3(head - 0.4, 0.5, 3.6), &"wood_dark", false)
		for sx: float in [-1.0, 1.0]:
			kit.cylinder(Vector3(sx * (head * 0.5 - 0.3), -dep, hz), dep + 0.9, 0.35, &"wall_alt", 8, true, 0.3)
	if kit.lod < 2:
		kit.push(Transform3D(Basis(), Vector3(W * 0.5 - 0.4, 0.0, -L + 0.6)))
		NwtProps.lamp_post(kit, 0, true)
		kit.pop()
		if kit.lod == 0:
			kit.railing(PackedVector3Array([Vector3(-W * 0.5 + 0.1, 0, -1.0), Vector3(-W * 0.5 + 0.1, 0, -L * 0.45)]), 0.9, {"spacing": 2.0, "collide": true})


## Inlaid plaza disc (spec r): blue ring, white field, mosaic of the moon and waves. Collides.
static func plaza(kit: BuildingKit, spec: Dictionary) -> void:
	var r := float(spec.get("r", 12.0))
	var sides := 32 if kit.lod == 0 else 16
	var ring := func(rad: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in sides:
			var a := TAU * i / sides
			pts.append(Vector2(cos(a), sin(a)) * rad)
		return pts
	kit.slab(ring.call(r), -0.3, 0.06, &"trim", true)
	if kit.lod < 2:
		kit.slab(ring.call(r - 0.7), 0.0, 0.08, &"wall_alt", false)
		kit.slab(ring.call(r * 0.55), 0.0, 0.1, &"wall", false)
		if kit.lod == 0:
			# radiating tile joints
			for i in 16:
				var a := TAU * i / 16.0
				var p0 := Vector3(cos(a), 0, sin(a)) * (r * 0.56)
				var p1 := Vector3(cos(a), 0, sin(a)) * (r - 0.75)
				kit.beam(p0 + Vector3(0, 0.085, 0), p1 + Vector3(0, 0.085, 0), 0.08, 0.02, &"trim")
			# moon + waves mosaic lying on the ground (rotated emblem)
			kit.push(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.11, 0)))
			KitX.emblem_water(kit, Vector3(0, 0, 0), r * 0.75, &"trim", 0.0)
			kit.pop()
