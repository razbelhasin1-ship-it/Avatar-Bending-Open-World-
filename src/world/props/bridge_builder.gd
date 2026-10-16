class_name BridgeBuilder
extends RefCounted
## Bridges from WorldData.get_bridges() ({kind: stone|suspended, a, b, width, deck_height?, sag?})
## and for any builder that needs one (BuildingKit-based, thread-safe):
##   suspended(kit, a, b, width, sag, opts)  rope + plank bridge on a catenary sag between two
##       pylons, rope handrails with hangers, prayer flags; walkable plank deck (trimesh) and
##       railing barriers.
##   stone(kit, a, b, width, opts)           arched stone bridge: deck with a gentle hump,
##       crenellated parapets with lanterns, piers/arches down to the ground below, gate posts.
## a/b are the deck end points (deck surface height) in the kit's current frame.
## build(rec) -> {"kit": KitResult, "origin": Vector3} for a WorldData record (world space - origin).


static func build(rec: Dictionary) -> Dictionary:
	var a: Vector3 = rec["a"]
	var b: Vector3 = rec["b"]
	var origin := (a + b) * 0.5
	var region := WorldData.get_region(origin.x, origin.z)
	var nation := NationPalette.nation_for_region(region)
	var kit := BuildingKit.new(NationPalette.get_palette(nation), 0, ContentHash.hash_name(String(rec.get("id", "bridge"))))
	if rec.get("kind", &"stone") == &"suspended":
		suspended(kit, a - origin, b - origin, float(rec.get("width", 3.0)), float(rec.get("sag", 5.0)), {"origin": origin})
	else:
		var deck := float(rec.get("deck_height", maxf(a.y, b.y)))
		stone(kit, Vector3(a.x, deck, a.z) - origin, Vector3(b.x, deck, b.z) - origin, float(rec.get("width", 8.0)), {"origin": origin})
	return {"kit": kit.build(), "origin": origin}


## Deck height of a suspended bridge at t (0 at a, 1 at b): linear + parabolic sag.
static func deck_y(a: Vector3, b: Vector3, sag: float, t: float) -> float:
	return lerpf(a.y, b.y, t) - sag * 4.0 * t * (1.0 - t)


## Where the ground under the span falls away at each end: Vector2(t_a, t_b) (0..1 along a->b).
## The sag curve hangs between these cliff edges, so the deck meets each edge at its anchor height
## instead of running into the cliff face. `origin` = world offset of the kit frame (INF: 0, 1).
static func edges(a: Vector3, b: Vector3, origin: Vector3) -> Vector2:
	if not origin.is_finite():
		return Vector2(0.0, 1.0)
	var e := Vector2(0.0, 1.0)
	var t := 0.0
	while t < 0.45:
		var p := a.lerp(b, t) + origin
		if WorldData.get_height(p.x, p.z) - origin.y < a.y - 0.6:
			break
		e.x = t
		t += 0.0025
	t = 1.0
	while t > 0.55:
		var p := a.lerp(b, t) + origin
		if WorldData.get_height(p.x, p.z) - origin.y < b.y - 0.6:
			break
		e.y = t
		t -= 0.0025
	return e


## Deck height at t: on the ground up to each cliff edge, then the sagging span between the edges;
## never under the terrain (planks rest on it), so there is no step on or off the bridge.
static func deck_height(a: Vector3, b: Vector3, sag: float, origin: Vector3, t: float, e: Vector2) -> float:
	var y: float
	if t <= e.x:
		y = a.y
	elif t >= e.y:
		y = b.y
	else:
		var u := (t - e.x) / maxf(e.y - e.x, 0.001)
		y = lerpf(a.y, b.y, u) - sag * 4.0 * u * (1.0 - u)
	if origin.is_finite():
		# highest ground within 1.2 m along the span: the deck collision (2 m quads) then never dips
		# under a cliff lip of the 1 m heightfield, which would stop walkers like a low wall
		var dt := 0.6 / maxf(Vector2(b.x - a.x, b.z - a.z).length(), 1.0)
		for k in range(-2, 3):
			var p := a.lerp(b, clampf(t + k * dt, 0.0, 1.0)) + origin
			y = maxf(y, WorldData.get_height(p.x, p.z) - origin.y + 0.06)
	return y


static func suspended(kit: BuildingKit, a: Vector3, b: Vector3, width: float, sag: float, opts: Dictionary = {}) -> void:
	var origin: Vector3 = opts.get("origin", Vector3.INF)
	var e := edges(a, b, origin)
	var dir := Vector3(b.x - a.x, 0, b.z - a.z)
	var length := dir.length()
	dir = dir.normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var plank := 0.32
	var gap := 0.06
	var n := int(length / (plank + gap))
	# planks (each its own small box; deck collision as one quad strip)
	for i in n:
		var t := (float(i) + 0.5) / n
		var p := a.lerp(b, t)
		p.y = deck_height(a, b, sag, origin, t, e)
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var slope := atan2(deck_height(a, b, sag, origin, t1, e) - deck_height(a, b, sag, origin, t0, e), length / n)
		kit.box_t(Transform3D(Basis(side, Vector3.UP.rotated(side, slope), -dir.rotated(side, slope)).orthonormalized(), p - Vector3(0, 0.05, 0)),
				Vector3(width + rng_jitter(kit, 0.15), 0.09, plank), &"wood" if i % 5 else &"wood_dark", false)
	var segs := maxi(int(length / 2.0), 4)
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var p0 := a.lerp(b, t0)
		var p1 := a.lerp(b, t1)
		p0.y = deck_height(a, b, sag, origin, t0, e)
		p1.y = deck_height(a, b, sag, origin, t1, e)
		var hw := side * width * 0.5
		kit.collide_quad(p0 - hw, p0 + hw, p1 + hw, p1 - hw)
		# rope barrier (invisible walls at the handrails)
		for s: float in [-1.0, 1.0]:
			var m := (p0 + p1) * 0.5 + side * s * (width * 0.5 + 0.08) + Vector3(0, 0.6, 0)
			var sb := Basis(side, Vector3.UP, (p1 - p0).normalized()).orthonormalized()
			kit.boxes.append([kit.xform * Transform3D(sb, m), Vector3(0.12, 1.3, p0.distance_to(p1) + 0.05)])
	# handrail ropes (higher sag), hangers, foot ropes
	var rail_h := 1.05
	for s: float in [-1.0, 1.0]:
		var rope := PackedVector3Array()
		var foot := PackedVector3Array()
		var nr := maxi(int(length / 3.0), 6)
		for i in nr + 1:
			var t := float(i) / nr
			var p := a.lerp(b, t) + side * s * (width * 0.5 + 0.06)
			foot.append(Vector3(p.x, deck_height(a, b, sag, origin, t, e) + 0.02, p.z))
			rope.append(Vector3(p.x, deck_height(a, b, sag, origin, t, e) + rail_h + 0.15 * (1.0 - 4.0 * t * (1.0 - t)), p.z))
		var radii := PackedFloat32Array()
		radii.resize(rope.size())
		radii.fill(0.035)
		kit.g().tube(rope, radii, 4, kit.col(&"wood_dark"))
		kit.g().tube(foot, radii, 4, kit.col(&"wood_dark"))
		if kit.lod == 0:
			for i in range(1, rope.size() - 1):
				kit.g().cylinder(foot[i], rope[i], 0.02, 0.02, 3, kit.col(&"wood_dark"), 0)
	# pylons at both ends
	for end: Vector3 in [a, b]:
		var out: Vector3 = -dir if end == a else dir
		for s: float in [-1.0, 1.0]:
			var base: Vector3 = end + side * s * (width * 0.5 + 0.35) + out * 0.4
			kit.column(base - Vector3(0, 0.3, 0), 3.0, 0.22, &"wood", &"square", &"stone")
			kit.ornament(base + Vector3(0, 2.75, 0), &"finial", 0.6, &"trim")
		if kit.lod == 0:
			kit.beam(end + out * 0.4 + side * (width * 0.5 + 0.35) + Vector3(0, 2.5, 0), end + out * 0.4 - side * (width * 0.5 + 0.35) + Vector3(0, 2.5, 0), 0.25, 0.25, &"trim")
			# prayer flags strung from the pylons
			var fl := PackedVector3Array()
			for i in 9:
				var t := float(i) / 8.0
				fl.append(end + out * 0.4 + side * lerpf(-1.0, 1.0, t) * (width * 0.5 + 0.35) + Vector3(0, 2.4 - sin(t * PI) * 0.35, 0))
			for i in fl.size() - 1:
				var fc: Variant = [&"cloth", &"cloth_alt", &"accent", &"trim", &"roof"][i % 5]
				var mid := (fl[i] + fl[i + 1]) * 0.5
				kit.banner(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), mid), 0.28, 0.35, {"role": fc, "emblem": false, "rod": false, "tail": false})
	# stone landings
	for end: Vector3 in [a, b]:
		var out2: Vector3 = -dir if end == a else dir
		kit.box(end + out2 * 1.6 - Vector3(0, 0.5, 0), Vector3(width + 1.8, 1.0, 3.2), &"stone")


static func rng_jitter(kit: BuildingKit, amount: float) -> float:
	return kit.rng.randf_range(-amount, amount)


static func stone(kit: BuildingKit, a: Vector3, b: Vector3, width: float, opts: Dictionary = {}) -> void:
	var dir := Vector3(b.x - a.x, 0, b.z - a.z)
	var length := dir.length()
	dir = dir.normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var origin: Vector3 = opts.get("origin", Vector3.ZERO)
	var hump := float(opts.get("hump", minf(length * 0.03, 1.5)))
	var segs := maxi(int(length / 4.0), 4)
	var deck_th := 1.2
	var pts := PackedVector3Array()
	for i in segs + 1:
		var t := float(i) / segs
		var p := a.lerp(b, t)
		p.y += hump * sin(t * PI)
		pts.append(p)
	for i in segs:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		kit.beam(p0 - Vector3(0, deck_th * 0.5, 0), p1 - Vector3(0, deck_th * 0.5, 0), width, deck_th, &"stone")
		var hw := side * width * 0.5
		kit.collide_quad(p0 - hw, p0 + hw, p1 + hw, p1 - hw)
		# parapets
		for s: float in [-1.0, 1.0]:
			var q0 := p0 + side * s * (width * 0.5 - 0.3)
			var q1 := p1 + side * s * (width * 0.5 - 0.3)
			kit.beam(q0 + Vector3(0, 0.55, 0), q1 + Vector3(0, 0.55, 0), 0.5, 1.1, &"wall", true)
			if kit.lod == 0:
				kit.beam(q0 + Vector3(0, 1.15, 0), q1 + Vector3(0, 1.15, 0), 0.62, 0.14, &"stone_dark")
	# posts with lanterns every few segments
	for i in range(0, segs + 1, 2):
		for s: float in [-1.0, 1.0]:
			var q := pts[i] + side * s * (width * 0.5 - 0.3)
			kit.box(q + Vector3(0, 0.8, 0), Vector3(0.7, 1.6, 0.7), &"stone_dark", true)
			if i % 4 == 0 and kit.lod < 2:
				kit.lantern(q + Vector3(0, 1.6, 0), {"style": &"stone", "height": 1.3, "range": 9.0})
	# piers and arches down to the ground
	var spans := maxi(int(length / 22.0), 2)
	for i in range(1, spans):
		var t := float(i) / spans
		var p := a.lerp(b, t)
		var world := p + origin
		var ground := WorldData.get_height(world.x, world.z) - origin.y
		var top := p.y + hump * sin(t * PI) - deck_th
		var h := top - ground
		if h > 2.0:
			kit.box(Vector3(p.x, ground + h * 0.5, p.z), Vector3(width * 0.8, h, 3.5), &"stone", true)
			if kit.lod < 2:
				kit.box(Vector3(p.x, ground + h * 0.5, p.z), Vector3(width * 0.85, h * 0.9, 4.0), &"base", false)
	if kit.lod < 2:
		for i in spans:
			var t0 := float(i) / spans
			var t1 := float(i + 1) / spans
			var m := a.lerp(b, (t0 + t1) * 0.5)
			var r := length / spans * 0.42
			var arch_top := m.y + hump * sin((t0 + t1) * 0.5 * PI) - deck_th
			var steps := 10
			for k in steps:
				var u0 := PI * float(k) / steps
				var u1 := PI * float(k + 1) / steps
				for s: float in [-1.0, 1.0]:
					var face := side * s * (width * 0.5 - 0.2)
					var e0 := m + face - dir * cos(u0) * r
					var e1 := m + face - dir * cos(u1) * r
					e0.y = arch_top - r * 0.55 + sin(u0) * r * 0.55
					e1.y = arch_top - r * 0.55 + sin(u1) * r * 0.55
					kit.beam(e0, e1, 0.5, 0.7, &"stone_dark")
	# gate posts at the ends
	for end: Vector3 in [a, b]:
		var out: Vector3 = -dir if end == a else dir
		for s: float in [-1.0, 1.0]:
			var g := end + side * s * (width * 0.5 + 0.4) + out * 0.5
			kit.box(g + Vector3(0, 2.0, 0), Vector3(1.4, 4.0, 1.4), &"stone", true)
			kit.ornament(g + Vector3(0, 4.0, 0), &"finial", 1.1, &"trim")
