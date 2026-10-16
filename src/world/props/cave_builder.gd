class_name CaveBuilder
extends RefCounted
## Cave mouths from WorldData cave POIs ({position (entrance on the cliff base), yaw (faces out of
## the cliff), tunnel [[x,y,z]...] descending under the terrain}).
##
## The terrain has no visual holes, so the entrance is built *in front of* the cliff: an inward-
## facing rock tunnel tube follows the recorded tunnel from 6 m outside the cliff to its end,
## a rocky mouth shell + boulders covers where the tube meets the cliff, and a dark veil a little
## inside the mouth hides the terrain surface that cuts through the tube (from inside the hill
## the single-sided terrain is invisible, so the tunnel interior shows). Walkability: trimesh
## collision of the whole tube plus a TerrainHoles capsule that removes the heightfield collision
## where the cliff crosses the tube. Interior: darkening rock, region features (glowing ice,
## lava veins, lanterns, glowing moss) and budgeted lights.
##
## build() is thread-safe and returns a Dictionary:
##   {"kit": KitResult (mouth shell, rocks, features — toon + outline, kit space = world),
##    "tube": Array (mesh arrays of the interior tube, no outline), "veil": Array (arrays),
##    "faces": PackedVector3Array (tube collision), "hole": [Vector2 a, Vector2 b, radius],
##    "markers": {&"entrance": Transform3D, &"end": Transform3D}, "origin": Vector3}

const WIDTH := 5.4
const HEIGHT := 4.6
const OUTSIDE := 2.5
const STEP := 2.0
const SIDES := 14


static func build(poi: Dictionary) -> Dictionary:
	var entrance0: Vector3 = poi.get("entrance", poi["position"])
	var yaw := float(poi.get("yaw", 0.0))
	var out_dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var tunnel := anchor(poi.get("tunnel", PackedVector3Array([entrance0, entrance0 - out_dir * 40.0])), out_dir)
	var entrance := tunnel[0]
	var region: StringName = poi.get("region", &"wilds")
	var rng := ContentHash.rng(ContentHash.hash_name(String(poi.get("id", "cave"))))
	# path: from outside the cliff into the tunnel, resampled every STEP metres (smoothed)
	# a mouth high on a sheer cliff sits flush in the face instead of on a floating porch
	var below := entrance + out_dir * 2.5
	var outside := OUTSIDE if entrance.y - WorldData.get_height(below.x, below.z) < 3.0 else 3.0
	var raw := PackedVector3Array([entrance + out_dir * outside])
	raw.append_array(tunnel)
	var path := _resample(raw, STEP)
	var dist := PackedFloat32Array()     # signed distance along the path from the entrance
	var acc := -outside
	for i in path.size():
		if i > 0:
			acc += path[i].distance_to(path[i - 1])
		dist.append(acc)
	# where does the terrain cover the tube ceiling (+1 m)?
	var cover_i := path.size() - 1
	for i in path.size():
		if dist[i] > 0.0 and WorldData.get_height(path[i].x, path[i].z) > path[i].y + HEIGHT + 1.2:
			cover_i = i
			break
	var cover_s := dist[cover_i]
	var rock_l := TerrainPatterns.ROCK_L[TerrainPatterns.palette_index(region)].srgb_to_linear()
	var rock_d := TerrainPatterns.ROCK_D[TerrainPatterns.palette_index(region)].srgb_to_linear()
	var style := _style(String(poi.get("id", "")), region)
	# --- interior tube (inward faces) ---------------------------------------------------------
	var tube := GeoBuilder.new()
	var rings: Array = []
	for i in path.size():
		var t := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)])
		t.y *= 0.3
		t = t.normalized()
		var right := t.cross(Vector3.UP).normalized()
		var up := right.cross(t).normalized()
		var ring := PackedVector3Array()
		var wobble := 1.0 + (0.0 if dist[i] < 1.0 else 0.12)
		for k in SIDES:
			var a := TAU * float(k) / SIDES - PI * 0.5
			var nx := cos(a)
			var ny := sin(a)
			var hval := ContentHash.unit(ContentHash.hash4(ContentHash.hash_name(String(poi.get("id", "c"))), i, k))
			var rw := WIDTH * 0.5 * (1.0 + (hval - 0.5) * 0.25 * wobble)
			var rh := HEIGHT * 0.5 * (1.0 + (hval - 0.5) * 0.2 * wobble)
			var y := HEIGHT * 0.5 + ny * rh
			if y < 0.0:
				y = 0.0      # flat walkable floor
			ring.append(path[i] + right * nx * rw + up * (y - 0.02))
		rings.append(ring)
	var faces := PackedVector3Array()
	for i in rings.size():
		var depth := clampf(dist[i] / 40.0, 0.0, 1.0)
		var ring: PackedVector3Array = rings[i]
		var center := path[i] + Vector3(0, HEIGHT * 0.45, 0)
		for k in SIDES + 1:
			var p := ring[k % SIDES]
			var n := (center - p).normalized()
			var floor_v := p.y - path[i].y < 0.05
			var c := (rock_l * 0.8).lerp(rock_d * 0.7, smoothstep(0.0, 1.0, (dist[i] + outside) / 22.0 + 0.1))
			c = c * lerpf(1.0, 0.7, clampf((p.y - path[i].y) / HEIGHT, 0.0, 1.0))
			if floor_v:
				c = c * 0.8
			c = c * (0.85 + 0.3 * ContentHash.unit(ContentHash.hash4(i, k, 5)))
			if style == &"ice":
				c = Color(0.55, 0.75, 0.92).lerp(Color(0.18, 0.32, 0.55), depth)
			c.a = 0.0
			tube.raw_vertex(p, n, c, Vector2.ZERO)
	for i in rings.size() - 1:
		for k in SIDES:
			var a := i * (SIDES + 1) + k
			var b := (i + 1) * (SIDES + 1) + k
			# counter-clockwise seen from inside
			tube.quad(a, a + 1, b + 1, b)
			var r0: PackedVector3Array = rings[i]
			var r1: PackedVector3Array = rings[i + 1]
			# both windings: queries that skip back faces (camera shape casts) still hit from inside
			faces.append_array(PackedVector3Array([r0[k], r1[(k + 1) % SIDES], r0[(k + 1) % SIDES], r0[k], r1[k], r1[(k + 1) % SIDES]]))
			faces.append_array(PackedVector3Array([r0[k], r0[(k + 1) % SIDES], r1[(k + 1) % SIDES], r0[k], r1[(k + 1) % SIDES], r1[k]]))
	# end cap
	var last: PackedVector3Array = rings[rings.size() - 1]
	var endc := path[path.size() - 1] + Vector3(0, HEIGHT * 0.45, 0)
	var ci := tube.raw_vertex(endc, (path[path.size() - 2] - path[path.size() - 1]).normalized(), rock_d * 0.4, Vector2.ZERO)
	var base := (rings.size() - 1) * (SIDES + 1)
	for k in SIDES:
		tube.tri(ci, base + k, base + k + 1)
		faces.append_array(PackedVector3Array([endc, last[k], last[(k + 1) % SIDES], endc, last[(k + 1) % SIDES], last[k]]))
	# --- mouth: a rocky portal around the opening, blended into the slope (kit) ------------------
	var kit := BuildingKit.new(NationPalette.get_palette(&"neutral"), 0, rng.randi())
	kit.color_jitter = 0.0
	var mouth_i := 0
	for i in path.size():
		if dist[i] <= cover_s + 1.0:
			mouth_i = i
	var ice := style == &"ice"
	var shell_rock := Color(0.60, 0.76, 0.90).srgb_to_linear() if ice else rock_l.lerp(rock_d, 0.3)
	var slot: StringName = &"ice" if ice else &"solid"
	var cap_c: Color = {&"ice": Color(0.93, 0.96, 1.0), &"lava": Color(0.15, 0.12, 0.11), &"moss": Color(0.27, 0.42, 0.2),
		&"earth": Color(0.25, 0.37, 0.15), &"lanterns": Color(0.25, 0.37, 0.15)}[style]
	cap_c = cap_c.srgb_to_linear()
	# roof and flanks along the part of the tube that is above ground
	for i in range(0, mouth_i + 1):
		var ring: PackedVector3Array = rings[i]
		var center := path[i] + Vector3(0, HEIGHT * 0.45, 0)
		for k in SIDES:
			var p := ring[k]
			if p.y - path[i].y < HEIGHT * 0.15 or (i + k) % 2 == 1:
				continue
			var outw := (p - center).normalized()
			var r := rng.randf_range(1.4, 2.3)
			var q := p + outw * (r * 1.05)
			if WorldData.get_height(q.x, q.z) > q.y + r * 0.9:
				continue
			_rock(kit, q, r, shell_rock * rng.randf_range(0.85, 1.08), cap_c, rng, Vector3(1.1, 0.85, 1.1), slot)
			kit.collide_box(q, Vector3.ONE * r * 1.4)
	var t0 := (path[1] - path[0])
	t0.y = 0.0
	t0 = t0.normalized()
	var right0 := t0.cross(Vector3.UP).normalized()
	# footing under the outer tube where the ground falls away
	for i in mouth_i + 1:
		if dist[i] > 0.5:
			break
		var drop := path[i].y - WorldData.get_height(path[i].x, path[i].z)
		if drop > 0.3:
			for sx: float in [-0.6, 0.0, 0.6]:
				var r := clampf(drop * 0.6 + 1.2, 1.4, 3.0)
				var q := path[i] + right0 * sx * WIDTH * 0.6 - Vector3(0, r * 0.75, 0)
				_rock(kit, q, r, shell_rock * 0.8, cap_c, rng, Vector3(1.1, 0.8, 1.1), slot)
				if drop > 3.5:
					# a ledge bulging out of the cliff under a high mouth
					_rock(kit, q - Vector3(0, r * 1.3, 0) + t0 * (r * 0.6), r * 0.85, shell_rock * 0.7, cap_c, rng, Vector3(1.1, 0.9, 1.0), slot)
	# portal: two bands of rocks on half-ellipses framing the opening, leaning into the hill
	var face := path[0] + t0 * 0.9
	for band in 2:
		var n_arc := 9 + band * 3
		for k in n_arc + 1:
			var a := PI * float(k) / n_arc
			var r := rng.randf_range(1.3, 1.9) + band * 0.6
			var rx := WIDTH * 0.5 + r * 1.05 + band * 2.2
			var ry := HEIGHT + r * 0.75 + band * 2.0
			var y := sin(a) * ry - 0.4
			var q := face + right0 * (cos(a) * rx) + Vector3(0, y, 0) + t0 * (y * 0.22 + band * 0.9 + rng.randf_range(-0.2, 0.4))
			if WorldData.get_height(q.x, q.z) > q.y + r * 0.85:
				continue
			var c := shell_rock.lerp(rock_d if not ice else shell_rock * 0.7, clampf(0.35 - y * 0.04, 0.0, 0.4)) * rng.randf_range(0.88, 1.08)
			_rock(kit, q, r, c, cap_c, rng, Vector3(1.1, 0.9, 0.8), slot)
			kit.collide_box(q, Vector3(r * 1.5, r * 1.4, r * 1.2), Basis(Vector3.UP, atan2(t0.x, t0.z)))
	# lintel slab over the opening
	var lintel := face + Vector3(0, HEIGHT + 0.6, 0) + t0 * 0.3
	kit.g(slot).blob(lintel, 1.0, 0, rock_d.lerp(shell_rock, 0.45), rng, 0.15, Vector3(WIDTH * 0.72, 0.6, 1.5), Vector3.INF, 0.0, rock_d * 0.7, Vector2.ZERO, true)
	_features(kit, style, path, dist, rings, rng)
	# --- veil: where the hill surface starts to cut through the tube --------------------------------
	# (fine march: on a sheer cliff the surface crosses the opening within a metre)
	var cross := dist[dist.size() - 1]
	var d := dist[0]
	while d < dist[dist.size() - 1]:
		var q := _at_dist(path, dist, d)
		if WorldData.get_height(q.x, q.z) > q.y + 0.1:
			cross = d
			break
		d += 0.25
	var veil_d := clampf(cross - 0.35, -outside + 0.8, maxf(cover_s * 0.5, -outside + 0.8))
	var vp := _at_dist(path, dist, veil_d)
	var vt := (_at_dist(path, dist, veil_d + 0.5) - vp).normalized()
	var vr := vt.cross(Vector3.UP).normalized()
	var veil := GeoBuilder.new()
	var vn := -vt
	var hw := WIDTH * 0.62
	var vc := Color(0, 0, 0, 1)
	var v00 := veil.raw_vertex(vp - vr * hw + Vector3(0, -0.2, 0), vn, vc, Vector2(0, 0))
	veil.raw_vertex(vp + vr * hw + Vector3(0, -0.2, 0), vn, vc, Vector2(1, 0))
	veil.raw_vertex(vp + vr * hw + Vector3(0, HEIGHT + 0.6, 0), vn, vc, Vector2(1, 1))
	veil.raw_vertex(vp - vr * hw + Vector3(0, HEIGHT + 0.6, 0), vn, vc, Vector2(0, 1))
	# facing out of the cave (counter-clockwise seen from outside)
	if (veil.verts[v00 + 1] - veil.verts[v00]).cross(veil.verts[v00 + 2] - veil.verts[v00]).dot(vn) > 0.0:
		veil.quad(v00, v00 + 1, v00 + 2, v00 + 3)
	else:
		veil.quad(v00, v00 + 3, v00 + 2, v00 + 1)
	# hole in the terrain collision where the cliff crosses the tube
	var hole_end := path[mini(cover_i + 1, path.size() - 1)]
	var hole_start := _at_dist(path, dist, maxf(cross - 1.0, dist[0]))
	var markers := {
		&"entrance": Transform3D(Basis(Vector3.UP, yaw), entrance),
		&"end": Transform3D(Basis(Vector3.UP, yaw), path[path.size() - 1]),
	}
	for l in kit.lights:
		l["interior"] = true
	return {"kit": kit.build(), "tube": tube.arrays(), "veil": veil.arrays(), "faces": faces,
		"hole": [Vector2(hole_start.x, hole_start.z), Vector2(hole_end.x, hole_end.z), WIDTH * 0.5 + 0.8],
		"markers": markers, "origin": entrance, "style": style}


## Re-anchors a recorded tunnel at the hillside: the tunnel is extended 40 m outwards (rising at
## its own grade) and starts where the ground first reaches its floor, so the mouth is
## neither buried under a slope nor standing in front of it; a mouth below the water level is
## lifted out of the water. Returns the tunnel from its new entrance inwards.
static func anchor(tunnel: PackedVector3Array, out_dir: Vector3) -> PackedVector3Array:
	var grade := 0.0
	if tunnel.size() > 1:
		var h := Vector2(tunnel[1].x - tunnel[0].x, tunnel[1].z - tunnel[0].z).length()
		grade = clampf((tunnel[0].y - tunnel[1].y) / maxf(h, 0.1), 0.0, 0.25)
	var pts := PackedVector3Array()
	for k in range(20, 0, -1):
		pts.append(tunnel[0] + out_dir * (k * 2.0) + Vector3(0, k * 2.0 * grade, 0))
	pts.append_array(tunnel)
	var c := 20
	for i in pts.size():
		if WorldData.get_height(pts[i].x, pts[i].z) >= pts[i].y + 0.3:
			c = i if i > 0 else 20
			break
	var out := pts.slice(maxi(c - 1, 0))
	var water := WorldData.get_water_height(out[0].x, out[0].z)
	if water > -INF and water > out[0].y - 0.4:
		var lift := minf(water + 0.4 - out[0].y, 6.0)
		for i in out.size():
			out[i].y += lift * clampf(1.0 - float(i) / 10.0, 0.35, 1.0)
	return out


## Point at signed distance `d` along the path (dist = distances of the path points).
static func _at_dist(path: PackedVector3Array, dist: PackedFloat32Array, d: float) -> Vector3:
	if d <= dist[0]:
		return path[0]
	for i in range(1, path.size()):
		if dist[i] >= d:
			return path[i - 1].lerp(path[i], (d - dist[i - 1]) / maxf(dist[i] - dist[i - 1], 0.001))
	return path[path.size() - 1]


## A rock with a darker underside and a moss/snow/ash cap on top (thread-safe).
static func _rock(kit: BuildingKit, q: Vector3, r: float, c: Color, cap_c: Color, rng: RandomNumberGenerator, scale: Vector3,
		slot: StringName = &"solid") -> void:
	kit.g(slot).blob(q, r, 1, c, rng, 0.28, scale, Vector3.INF, 0.0, c * 0.62, Vector2.ZERO, true)
	if rng.randf() < 0.35:
		kit.g().blob(q + Vector3(0, r * scale.y * 0.72, 0), r * 0.7, 0, cap_c * rng.randf_range(0.9, 1.1), rng, 0.2,
				Vector3(1.3, 0.45, 1.2), Vector3.INF, 0.0, cap_c * 0.7, Vector2.ZERO, true)


static func _style(id: String, region: StringName) -> StringName:
	if id.contains("ice") or region == &"water_tribe":
		return &"ice"
	if id.contains("magma") or region == &"fire_nation":
		return &"lava"
	if id.contains("lantern"):
		return &"lanterns"
	if region == &"air_temple":
		return &"moss"
	return &"earth"


## Interior details per style + lights.
static func _features(kit: BuildingKit, style: StringName, path: PackedVector3Array, dist: PackedFloat32Array, rings: Array, rng: RandomNumberGenerator) -> void:
	var n := path.size()
	for i in range(2, n, 3):
		var ring: PackedVector3Array = rings[i]
		var k := rng.randi() % SIDES
		var p := ring[k]
		var c := path[i] + Vector3(0, HEIGHT * 0.45, 0)
		var inward := (c - p).normalized()
		match style:
			&"ice":
				var gb := kit.g(&"glow")
				gb.uv = Vector2(0, 0.2)
				for j in 3:
					var q := p + inward * 0.2 + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.6, 0.6))
					gb.cone(q, q + inward * rng.randf_range(0.6, 1.4) + Vector3(0, 0.3, 0), 0.2, 5, Color(0.55, 0.85, 1.0), true)
			&"lava":
				var gb2 := kit.g(&"glow")
				gb2.uv = Vector2(0, 1)
				var f := path[i]
				var t := (path[mini(i + 1, n - 1)] - f).normalized()
				var r := t.cross(Vector3.UP).normalized()
				gb2.box(Transform3D(Basis(r, Vector3.UP, -t), f + r * (WIDTH * 0.42) + Vector3(0, 0.05, 0)), Vector3(0.35, 0.08, STEP * 1.1), Color(1.0, 0.35, 0.08))
			&"moss":
				var gb3 := kit.g(&"glow")
				gb3.uv = Vector2(0, 0.1)
				gb3.blob(p + inward * 0.1, 0.5, 0, Color(0.45, 0.9, 0.6), rng, 0.2, Vector3(1.2, 0.4, 1.2))
			_:
				pass
	# lights: one just inside, then every ~25 m
	var lc: Color = {&"ice": Color(0.6, 0.85, 1.0), &"lava": Color(1.0, 0.45, 0.15), &"moss": Color(0.6, 1.0, 0.75)}.get(style, Color(1.0, 0.75, 0.45))
	var next := 4.0
	for i in n:
		if dist[i] >= next:
			if style == &"lanterns" or style == &"earth":
				var t := (path[mini(i + 1, n - 1)] - path[i]).normalized()
				var r := t.cross(Vector3.UP).normalized()
				kit.lantern(path[i] + r * (WIDTH * 0.42) + Vector3(0, 0, 0), {"style": &"post", "height": 1.6, "range": 10.0, "energy": 1.5})
			else:
				kit.add_light(path[i] + Vector3(0, HEIGHT * 0.6, 0), lc, 11.0, 1.4, 1)
			next += 25.0


## Catmull-Rom resampling of a polyline at ~`step` metres.
static func _resample(pts: PackedVector3Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := pts.size()
	for i in n - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, n - 1)]
		var segs := maxi(int(ceil(p1.distance_to(p2) / step)), 1)
		for k in segs:
			var t := float(k) / segs
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[n - 1])
	return out
