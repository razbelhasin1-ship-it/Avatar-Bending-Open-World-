class_name OutpostBuilder
extends RefCounted
## Geometry of the authored encounter sites (BuildingKit, thread-safe):
## * Fire Nation war camp: red ridge tents around a fire pit, a command tent, spiked
##   barricades with an open gate, braziers + war banners at the gate, weapon racks,
##   crates and barrels.
## * Pirates' cove: patched tents, a beached rowboat, barrels and crates, a black flag.
## * Beast den: a ring of boulders, scattered bones and a trampled nest.
## Local frame: origin = site centre on the ground, -Z = the gate (site.yaw).
##
##   var r := OutpostBuilder.build(site, lod)    # {"kit": KitResult, "origin": Vector3, "smoke": [Vector3]}

const R_TENTS := 9.5
const R_FENCE := 13.0
const TENT_DARK := Color(0.38, 0.1, 0.08)
## Vertex colours are lit like the props (bright sun): keep the trampled earth dark.
const DIRT := Color(0.25, 0.19, 0.12)


static func build(site: EncounterSite, lod: int = 0) -> Dictionary:
	var nation: StringName = &"fire_nation" if site.style == &"fire_nation" else &"neutral"
	var seed_v := ContentHash.hash_name(String(site.id))
	var kit := BuildingKit.new(NationPalette.get_palette(nation), lod, seed_v)
	var rng := ContentHash.rng(seed_v)
	var origin := Vector3(site.center.x, WorldData.get_height(site.center.x, site.center.z), site.center.z)
	var ctx := {"kit": kit, "origin": origin, "yaw": site.yaw, "rng": rng, "smoke": [], "lod": lod}
	kit.push(Transform3D(Basis(Vector3.UP, site.yaw), Vector3.ZERO))
	if site.kind == &"den":
		_den(ctx)
	else:
		_fire_pit(ctx)
		if site.style == &"pirates":
			_pirate_cove(ctx)
		else:
			_war_camp(ctx)
	kit.pop()
	return {"kit": kit.build(), "origin": origin, "smoke": ctx["smoke"]}


## Local point dropped onto the terrain (local coordinates).
static func ground(ctx: Dictionary, local: Vector3) -> Vector3:
	var origin: Vector3 = ctx["origin"]
	var w := origin + Basis(Vector3.UP, float(ctx["yaw"])) * local
	return Vector3(local.x, WorldData.get_height(w.x, w.z) - origin.y + local.y, local.z)


static func ring(a_deg: float, r: float) -> Vector3:
	var a := deg_to_rad(a_deg)
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


## Yaw so a tent at `p` faces the centre (its door, -Z, toward the fire).
static func face_center(p: Vector3) -> float:
	return atan2(p.x, p.z)


## Trampled earth: a ragged two-ring disc of radius `r` around local `c` that follows the
## terrain (camp floor, paths to the tents).
static func dirt(ctx: Dictionary, c: Vector3, r: float, col: Color = DIRT) -> void:
	var kit: BuildingKit = ctx["kit"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var n := 12
	var inner: Array[Vector3] = []
	var outer: Array[Vector3] = []
	for k in n:
		var a := TAU * k / n
		var ro := r * rng.randf_range(0.72, 1.08)
		inner.append(ground(ctx, Vector3(c.x + cos(a) * ro * 0.55, 0, c.z + sin(a) * ro * 0.55)) + Vector3.UP * 0.06)
		outer.append(ground(ctx, Vector3(c.x + cos(a) * ro, 0, c.z + sin(a) * ro)) + Vector3.UP * 0.04)
	var cc := ground(ctx, Vector3(c.x, 0, c.z)) + Vector3.UP * 0.07
	var g := kit.g()
	var edge := col.lerp(Color(0.2, 0.24, 0.1), 0.45)
	for k in n:
		var k2 := (k + 1) % n
		g.flat_tri(cc, inner[k2], inner[k], col)
		g.flat_tri(inner[k], inner[k2], outer[k2], col.lerp(edge, 0.5))
		g.flat_tri(inner[k], outer[k2], outer[k], edge)


static func _fire_pit(ctx: Dictionary) -> void:
	var kit: BuildingKit = ctx["kit"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var fp := ground(ctx, Vector3.ZERO)
	dirt(ctx, Vector3.ZERO, 4.2)
	for k in 9:
		var a := TAU * k / 9.0
		kit.g().blob(fp + Vector3(cos(a) * 0.95, 0.1, sin(a) * 0.95), 0.24, 0, kit.col(&"stone_dark"), rng, 0.2, Vector3(1.2, 0.8, 1.0))
	for k in 4:
		var a := TAU * k / 4.0 + 0.3
		kit.beam(fp + Vector3(cos(a) * 0.6, 0.08, sin(a) * 0.6), fp + Vector3(-cos(a) * 0.1, 0.5, -sin(a) * 0.1), 0.1, 0.1, &"wood_dark")
	var gb := kit.g(&"glow")
	gb.uv = Vector2(0, 1)
	for k in 3:
		var q := fp + Vector3(rng.randf_range(-0.2, 0.2), 0.15, rng.randf_range(-0.2, 0.2))
		gb.cone(q, q + Vector3(0, 0.6 + 0.2 * k, 0), 0.24, 5, Color(1.0, 0.5, 0.12))
	kit.add_light(fp + Vector3(0, 1.1, 0), Color(1.0, 0.6, 0.3), 13.0, 2.4, 2)
	(ctx["smoke"] as Array).append(fp + Vector3(0, 0.9, 0))


static func _war_camp(ctx: Dictionary) -> void:
	var kit: BuildingKit = ctx["kit"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var lod := int(ctx["lod"])
	# Tents (doors toward the fire), the command tent at the back.
	# Army tents: Fire Nation red, every other one a darker maroon (no gold: it reads as a sign).
	for a: float in [30.0, 150.0, -20.0, 200.0]:
		var p := ground(ctx, ring(a, R_TENTS))
		_tent(kit, p, face_center(p), {"w": 3.2, "d": 3.8, "h": 2.5, "role": &"cloth" if int(a) % 60 == 30 else TENT_DARK})
		dirt(ctx, ring(a, R_TENTS - 3.2), 1.9)
	# Worn path from the gate to the fire.
	for z: float in [-6.5, -10.0, -13.0]:
		dirt(ctx, Vector3(rng.randf_range(-0.4, 0.4), 0, z), 2.0)
	var cmd := ground(ctx, ring(90.0, R_TENTS + 1.5))
	_tent(kit, cmd, face_center(cmd), {"w": 4.4, "d": 5.4, "h": 3.1, "role": &"cloth"})
	kit.banner(Transform3D(Basis(Vector3.UP, face_center(cmd)), cmd + Vector3(0, 2.9, 0) + (Vector3.ZERO - cmd).normalized() * 2.8), 0.9, 1.8,
			{"role": &"cloth", "alt_role": &"cloth_alt"})
	# Spiked barricades on an arc, the gate (-Z) left open.
	if lod < 2:
		var n := 14
		for k in n:
			var a := -60.0 + 300.0 * float(k) / float(n - 1)
			var p := ground(ctx, ring(a, R_FENCE))
			_barricade(kit, p, deg_to_rad(a), rng)
	# Gate: braziers + war flags.
	for s: float in [-1.0, 1.0]:
		var gp := ground(ctx, Vector3(s * 3.4, 0, -R_FENCE + 0.4))
		kit.brazier(gp, {"height": 1.0, "radius": 0.42, "range": 10.0, "energy": 2.0})
		var fpos := ground(ctx, Vector3(s * 4.6, 0, -R_FENCE - 0.4))
		kit.flag(Transform3D(Basis(), fpos), 5.2, 1.5, 1.0, {"role": &"cloth", "alt_role": &"metal"})
	# Supplies.
	for a: float in [0.0, 120.0, 175.0, 245.0]:
		var p := ground(ctx, ring(a + rng.randf_range(-8, 8), 6.8 + rng.randf() * 1.2))
		if int(a) % 2 == 0:
			kit.box(p + Vector3(0, 0.4, 0), Vector3(0.8, 0.8, 0.8), &"wood", true)
			kit.box(p + Vector3(0.12, 1.05, 0.05), Vector3(0.5, 0.5, 0.5), &"wood_dark", true)
		else:
			kit.cylinder(p, 0.9, 0.35, &"wood", 8, true)
			kit.cylinder(p + Vector3(0.75, 0, 0.1), 0.9, 0.35, &"wood_dark", 8, true)
	_rack(kit, ground(ctx, ring(-40.0, 6.0)), deg_to_rad(-40.0 + 90.0))
	_rack(kit, ground(ctx, ring(220.0, 6.2)), deg_to_rad(220.0 + 90.0))


static func _pirate_cove(ctx: Dictionary) -> void:
	var kit: BuildingKit = ctx["kit"]
	var rng: RandomNumberGenerator = ctx["rng"]
	for a: float in [60.0, 130.0, 200.0]:
		dirt(ctx, ring(a, R_TENTS - 4.0), 1.8, Color(0.36, 0.31, 0.22))
		var p := ground(ctx, ring(a, R_TENTS - 1.0))
		_tent(kit, p, face_center(p), {"w": 3.0, "d": 3.6, "h": 2.3, "role": Color(0.55, 0.47, 0.36) if int(a) % 20 == 0 else Color(0.36, 0.42, 0.5)})
	# Beached rowboat on its side by the camp.
	var bp := ground(ctx, ring(-15.0, 8.0))
	kit.push(Transform3D(Basis(Vector3.UP, 1.1) * Basis(Vector3.BACK, 0.25), bp + Vector3(0, 0.25, 0)))
	BoatBuilder.rowboat(kit, {"length": 4.0})
	kit.pop()
	kit.collide_box(bp + Vector3(0, 0.4, 0), Vector3(1.4, 0.8, 4.0), Basis(Vector3.UP, 1.1))
	for k in 7:
		var p := ground(ctx, ring(240.0 + k * 14.0 + rng.randf_range(-4, 4), 6.5 + rng.randf() * 1.5))
		if k % 3 == 0:
			kit.box(p + Vector3(0, 0.38, 0), Vector3(0.75, 0.75, 0.75), &"wood", true)
		else:
			kit.cylinder(p, 0.85, 0.33, &"wood_dark" if k % 2 else &"wood", 8, true)
	var fpos := ground(ctx, ring(100.0, 12.0))
	kit.flag(Transform3D(Basis(), fpos), 5.0, 1.4, 0.95, {"role": Color(0.09, 0.08, 0.1), "alt_role": Color(0.9, 0.88, 0.8)})
	_rack(kit, ground(ctx, ring(20.0, 6.0)), deg_to_rad(110.0))
	for s: float in [-1.0, 1.0]:
		kit.lantern(ground(ctx, Vector3(s * 3.0, 0, -6.0)), {"style": &"post"})


static func _den(ctx: Dictionary) -> void:
	var kit: BuildingKit = ctx["kit"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var stone := Color(0.42, 0.38, 0.34)
	for k in 9:
		var a := 360.0 * k / 9.0 + rng.randf_range(-15, 15)
		if absf(wrapf(a + 90.0, -180.0, 180.0)) < 25.0:
			continue
		var p := ground(ctx, ring(a, 10.0 + rng.randf() * 2.0))
		var s := rng.randf_range(0.9, 1.7)
		kit.g().blob(p + Vector3(0, s * 0.45, 0), s, 1, stone, rng, 0.25, Vector3(1.2, 0.85, 1.0), Vector3.INF, 0.0, stone * 0.8)
		kit.collide_box(p + Vector3(0, s * 0.45, 0), Vector3(s * 1.8, s * 1.2, s * 1.8))
	var bone := Color(0.9, 0.86, 0.76)
	for k in 6:
		var p := ground(ctx, ring(rng.randf() * 360.0, rng.randf_range(2.5, 7.5)))
		var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		kit.beam(p + Vector3(0, 0.08, 0), p + dir * rng.randf_range(0.6, 1.2) + Vector3(0, 0.08, 0), 0.08, 0.08, bone)
		if k % 2 == 0:
			kit.g().blob(p + Vector3(0, 0.12, 0), 0.16, 0, bone, rng, 0.1, Vector3(1.0, 0.8, 1.3))
	# Trampled nest of dry grass.
	var gp := ground(ctx, Vector3(0, 0, 2.0))
	kit.g().blob(gp + Vector3(0, -0.05, 0), 2.2, 1, Color(0.62, 0.52, 0.32), rng, 0.15, Vector3(1.3, 0.1, 1.0))


static func _tent(kit: BuildingKit, p: Vector3, yaw: float, spec: Dictionary) -> void:
	BuildingPresets.tent(kit, Transform3D(Basis(Vector3.UP, yaw), p - Vector3(0, 0.08, 0)), spec)
	kit.collide_box(p + Vector3(0, float(spec.get("h", 2.4)) * 0.4, 0), Vector3(float(spec.get("w", 3.0)) * 0.9, float(spec.get("h", 2.4)) * 0.8,
			float(spec.get("d", 3.6)) * 0.9), Basis(Vector3.UP, yaw))


## A spiked log barricade (two crossed stakes + a rail) tangent to the ring at angle a.
static func _barricade(kit: BuildingKit, p: Vector3, a: float, rng: RandomNumberGenerator) -> void:
	var tangent := Vector3(-sin(a), 0, cos(a))
	var out := Vector3(cos(a), 0, sin(a))
	for s: float in [-0.7, 0.0, 0.7]:
		var base := p + tangent * s
		var tip := base + out * 0.7 + Vector3(0, 1.5 + rng.randf() * 0.3, 0)
		kit.beam(base - out * 0.4, tip, 0.12, 0.12, &"wood")
		kit.g().cone(tip, tip + (tip - base).normalized() * 0.25, 0.07, 4, kit.col(&"wood_dark"), false)
	kit.beam(p - tangent * 1.1 + Vector3(0, 0.6, 0), p + tangent * 1.1 + Vector3(0, 0.6, 0), 0.1, 0.1, &"wood_dark")
	kit.collide_box(p + Vector3(0, 0.7, 0) + out * 0.15, Vector3(2.3, 1.4, 0.6), Basis(Vector3.UP, atan2(-tangent.x, -tangent.z)))


static func _rack(kit: BuildingKit, p: Vector3, yaw: float) -> void:
	kit.push(Transform3D(Basis(Vector3.UP, yaw), p))
	kit.beam(Vector3(-1.0, 1.1, 0), Vector3(1.0, 1.1, 0), 0.1, 0.1, &"wood")
	for s: float in [-1.0, 1.0]:
		kit.beam(Vector3(s, 0, 0), Vector3(s, 1.2, 0), 0.1, 0.1, &"wood")
	for k in 4:
		kit.beam(Vector3(-0.7 + k * 0.45, 0.05, 0.25), Vector3(-0.6 + k * 0.45, 1.75, -0.05), 0.04, 0.04, &"metal")
	kit.pop()
	kit.collide_box(p + Vector3(0, 0.7, 0), Vector3(2.2, 1.4, 0.5), Basis(Vector3.UP, yaw))
