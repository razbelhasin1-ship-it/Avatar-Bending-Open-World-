class_name PlantMeshes
extends RefCounted
## Procedural shrubs, hedges, ferns, rocks, ice, driftwood (vegetation shader) and ground-cover
## clumps (grass shader: grass, meadow grass, flowers, reeds, crops, tufts). Same vertex
## conventions as TreeMeshes. Ground-cover vertex colours are near white with tint mask 1 so the
## instance colour (terrain-matched on the CPU) paints them; flower heads/grain keep their colour
## (mask 0). UV.x of ground cover = height fraction (0 root .. 1 tip) for the grass shader.

const WOOD := 0.0
const LEAF := 1.0


static func col(r: float, g: float, b: float, mask: float = 1.0) -> Color:
	return TreeMeshes.col(r, g, b, mask)


# --- Shrubs ------------------------------------------------------------------------------------------

static func shrub(rng: RandomNumberGenerator, lod: int, snowy: bool = false) -> GeoBuilder:
	var g := GeoBuilder.new()
	var n: int = [5, 3, 1][lod]
	var lo := col(0.10, 0.25, 0.09)
	var hi := col(0.34, 0.52, 0.17)
	var center := Vector3(0, 0.45, 0)
	for i in n:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.15, 0.5) if i > 0 else 0.0
		var r := rng.randf_range(0.42, 0.62) if i > 0 else 0.68
		var c := Vector3(cos(a) * d, r * 0.7 + rng.randf_range(-0.05, 0.1), sin(a) * d)
		g.blob(c, r * (1.15 if lod >= 1 else 1.0), [1, 0, 0][lod], hi, rng, 0.16, Vector3(1, 0.85, 1), center, 0.65, lo, Vector2(0, LEAF))
	TreeMeshes.gradient(g, 0, 0.0, 1.2, lo, hi, rng, 0.08)
	TreeMeshes.sway_by_height(g, 0, 1.2, 0.35, LEAF)
	if snowy:
		for i in g.vertex_count():
			if g.normals[i].y > 0.55 and g.verts[i].y > 0.6:
				g.uv2s[i] = Vector2(1, 0)
	return g


## Farm hedge segment: 6 m long along +X (instances may stretch x), ~1.4 m high, a continuous
## clipped row made of strongly overlapping elongated clumps.
static func hedge(rng: RandomNumberGenerator, lod: int) -> GeoBuilder:
	var g := GeoBuilder.new()
	var n: int = [4, 3, 2][lod]
	var lo := col(0.08, 0.22, 0.08)
	var hi := col(0.28, 0.46, 0.14)
	for i in n:
		var x := lerpf(-2.2, 2.2, float(i) / float(maxi(n - 1, 1)))
		var r := 0.82 * (4.0 / float(n)) * 0.75 + 0.2
		g.blob(Vector3(x, 0.7, 0), r, [1, 0, 0][lod], hi, rng, 0.07, Vector3(1.7, 0.92, 0.72),
				Vector3(x, 0.1, 0), 0.75, lo, Vector2(0, LEAF))
	TreeMeshes.gradient(g, 0, 0.0, 1.5, lo, hi, rng, 0.05)
	TreeMeshes.sway_by_height(g, 0, 1.5, 0.25, LEAF)
	return g


## Fern: arched fronds radiating from the centre (forest floor, ~1 m).
static func fern(rng: RandomNumberGenerator, lod: int) -> GeoBuilder:
	var g := GeoBuilder.new()
	var n: int = [9, 6, 4][lod]
	var lo := col(0.10, 0.28, 0.08)
	var hi := col(0.38, 0.62, 0.18)
	for k in n:
		var a := TAU * float(k) / float(n) + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0, sin(a))
		var l := rng.randf_range(0.7, 1.1)
		var spine := PackedVector3Array()
		var sides := PackedVector3Array()
		var segs: int = [5, 3, 2][lod]
		var perp := dir.cross(Vector3.UP).normalized()
		for i in segs + 1:
			var t := float(i) / float(segs)
			spine.append(dir * l * t + Vector3(0, sin(t * PI * 0.8) * l * 0.55, 0))
			sides.append(perp * (sin(t * PI) * 0.16 + 0.01))
		g.strip(spine, sides, lo, hi, true, Vector2(0, LEAF), Vector2(0.6, LEAF))
	TreeMeshes.sway_by_height(g, 0, 0.8, 0.5, LEAF)
	return g


# --- Rocks / ice / wood -------------------------------------------------------------------------------

## Faceted rock of radius ~1 m (scale instances for size). cap = top faces become cap kind
## (snow/moss/ash colour from the material). lava = black basalt with glowing facets.
static func rock(rng: RandomNumberGenerator, lod: int, cap: bool, lava: bool = false) -> GeoBuilder:
	var g := GeoBuilder.new()
	var base := col(0.62, 0.60, 0.58) if not lava else col(0.13, 0.12, 0.12, 0.3)
	var sc := Vector3(rng.randf_range(0.9, 1.25), rng.randf_range(0.55, 0.8), rng.randf_range(0.8, 1.1))
	g.blob(Vector3(0, 0.25, 0), 1.0, [1, 0, 0][lod], base, rng, 0.22 if lod < 2 else 0.12, sc, Vector3.INF, 0.0,
			base * 0.8, Vector2(0, WOOD), true)
	# flat-shaded faces: decide cap / ember per face (3 consecutive vertices)
	for k in range(0, g.vertex_count(), 3):
		var n := g.normals[k]
		var shade := 0.82 + 0.3 * rng.randf()
		for j in 3:
			var c := g.colors[k + j]
			g.colors[k + j] = Color(c.r * shade, c.g * shade, c.b * shade, c.a)
		if cap and n.y > 0.62:
			for j in 3:
				g.uv2s[k + j] = Vector2(1, 0)
		elif lava:
			# glowing veins (shader pattern) across most faces, strongest low down
			var e := clampf(0.35 + 0.65 * rng.randf() - n.y * 0.3, 0.0, 1.0)
			for j in 3:
				g.uv2s[k + j] = Vector2(0, e)
	return g


## Angular ice chunk (radius ~1 m) or a tall serac cluster.
static func ice(rng: RandomNumberGenerator, lod: int, serac: bool) -> GeoBuilder:
	var g := GeoBuilder.new()
	var deep := col(0.42, 0.68, 0.86, 0.3)
	var light := col(0.82, 0.93, 0.99, 0.3)
	if not serac:
		g.blob(Vector3(0, 0.3, 0), 1.0, 0, light, rng, 0.35, Vector3(1.2, 0.8, 1.0), Vector3.INF, 0.0, deep, Vector2.ZERO, true)
		return g
	var n: int = [5, 3, 2][lod]
	for i in n:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 1.6) if i > 0 else 0.0
		var base := Vector3(cos(a) * d, -0.3, sin(a) * d)
		var h := rng.randf_range(3.0, 7.5) * (1.0 if i == 0 else 0.7)
		var tip := base + Vector3(rng.randf_range(-0.8, 0.8), h, rng.randf_range(-0.8, 0.8))
		var r := rng.randf_range(0.7, 1.3)
		var sides := 4 + rng.randi() % 2
		var v0 := g.vertex_count()
		g.cylinder(base, tip, r, r * 0.12, sides, deep, 0, false, light, rng.randf() * TAU)
		TreeMeshes.gradient(g, v0, -0.3, h, deep, light, rng, 0.05)
	return g


## Bleached driftwood log (or a mossy fallen log when mossy) lying along +X, ~4 m.
static func log_piece(rng: RandomNumberGenerator, lod: int, mossy: bool) -> GeoBuilder:
	var g := GeoBuilder.new()
	var wood := col(0.72, 0.68, 0.62, 0.3) if not mossy else col(0.36, 0.27, 0.20, 0.3)
	var l := rng.randf_range(3.0, 4.8)
	var r := rng.randf_range(0.16, 0.26)
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var segs: int = [5, 3, 2][lod]
	for i in segs + 1:
		var t := float(i) / float(segs)
		pts.append(Vector3(lerpf(-l * 0.5, l * 0.5, t), r * 0.8 + sin(t * 3.0) * 0.08, sin(t * 2.3 + rng.randf()) * 0.18))
		radii.append(r * lerpf(1.1, 0.7, t))
	g.tube(pts, radii, [6, 5, 4][lod], wood)
	if lod == 0:
		# root stubs at the thick end + a branch stub
		for k in 4:
			var a := rng.randf() * TAU
			var from := pts[0]
			var to := from + Vector3(-0.25, sin(a) * 0.5, cos(a) * 0.5) * rng.randf_range(0.6, 1.0)
			g.tube(PackedVector3Array([from, to]), PackedFloat32Array([r * 0.5, r * 0.15]), 4, wood)
		var bp := pts[segs / 2 + 1]
		g.tube(PackedVector3Array([bp, bp + Vector3(0.3, 0.6, 0.25)]), PackedFloat32Array([r * 0.35, r * 0.1]), 4, wood)
	if mossy:
		for i in g.vertex_count():
			if g.normals[i].y > 0.5:
				g.uv2s[i] = Vector2(1, 0)
	return g


# --- Ground cover (grass shader) --------------------------------------------------------------------

## Grass clump: `blades` curved tapering blades within `radius`, heights in [h0, h1] m.
static func grass(rng: RandomNumberGenerator, blades: int, radius: float, h0: float, h1: float, width: float = 0.04, segs: int = 3) -> GeoBuilder:
	var g := GeoBuilder.new()
	for b in blades:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius
		var root := Vector3(cos(a) * d, -0.02, sin(a) * d)
		var h := rng.randf_range(h0, h1)
		var face := rng.randf() * TAU
		var lean_dir := Vector3(cos(a), 0, sin(a)) * 0.6 + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
		var lean := rng.randf_range(0.15, 0.45) * h
		var side := Vector3(cos(face), 0, sin(face))
		var bright := rng.randf_range(0.85, 1.12)
		var c := Color(bright, bright, bright, 1.0)
		var base := g.vertex_count()
		for i in segs + 1:
			var t := float(i) / float(segs)
			var p := root + Vector3(0, h * t, 0) + lean_dir * lean * t * t
			var w := width * (1.0 - t) * (1.0 - t * 0.2) + 0.002
			var n := side.cross(Vector3.UP).normalized()
			g.raw_vertex(p - side * w, n, c, Vector2(t, LEAF))
			g.raw_vertex(p + side * w, n, c, Vector2(t, LEAF))
		for i in segs:
			var k := base + i * 2
			g.quad(k, k + 1, k + 3, k + 2)
	return g


## Flowers: a few stems (tinted like grass) with flat 5-petal heads in `petal` colour.
static func flowers(rng: RandomNumberGenerator, petal: Color, center: Color, stems: int = 5) -> GeoBuilder:
	var g := grass(rng, 7, 0.22, 0.18, 0.32, 0.03, 2)
	for s in stems:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * 0.25
		var root := Vector3(cos(a) * d, 0.0, sin(a) * d)
		var h := rng.randf_range(0.25, 0.45)
		var top := root + Vector3(rng.randf_range(-0.05, 0.05), h, rng.randf_range(-0.05, 0.05))
		var side := Vector3(cos(a + 1.0), 0, sin(a + 1.0))
		var base := g.vertex_count()
		var stem_c := Color(0.9, 0.95, 0.9, 1.0)
		g.raw_vertex(root - side * 0.006, Vector3.UP, stem_c, Vector2(0, LEAF))
		g.raw_vertex(root + side * 0.006, Vector3.UP, stem_c, Vector2(0, LEAF))
		g.raw_vertex(top - side * 0.004, Vector3.UP, stem_c, Vector2(1, LEAF))
		g.raw_vertex(top + side * 0.004, Vector3.UP, stem_c, Vector2(1, LEAF))
		g.quad(base, base + 1, base + 3, base + 2)
		# head: 5 petals around a centre (flat, tilted)
		var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.1, 0.5))
		var pc := petal * rng.randf_range(0.9, 1.1)
		pc.a = 0.0
		var cc := center
		cc.a = 0.0
		var hc := g.raw_vertex(top, tilt * Vector3.UP, cc, Vector2(1, LEAF))
		var r := rng.randf_range(0.035, 0.06)
		var ring := []
		for k in 10:
			var aa := TAU * float(k) / 10.0
			var rr := r if k % 2 == 0 else r * 0.45
			ring.append(g.raw_vertex(top + tilt * Vector3(cos(aa) * rr, 0.004, sin(aa) * rr), tilt * Vector3.UP, pc, Vector2(1, LEAF)))
		for k in 10:
			g.tri(hc, ring[(k + 1) % 10], ring[k])
	return g


## Reeds: tall blades + cattails.
static func reeds(rng: RandomNumberGenerator) -> GeoBuilder:
	var g := grass(rng, 10, 0.3, 0.9, 1.6, 0.025, 3)
	for k in 3:
		var a := rng.randf() * TAU
		var root := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.25)
		var h := rng.randf_range(1.2, 1.7)
		var top := root + Vector3(rng.randf_range(-0.1, 0.1), h, rng.randf_range(-0.1, 0.1))
		var v0 := g.vertex_count()
		g.cylinder(root, top, 0.008, 0.006, 3, Color(0.9, 0.95, 0.85, 1.0), 0)
		g.cylinder(top - Vector3(0, 0.22, 0), top - Vector3(0, 0.02, 0), 0.028, 0.026, 5, col(0.36, 0.22, 0.12, 0.0), 2)
		for i in range(v0, g.vertex_count()):
			g.uvs[i] = Vector2(clampf(g.verts[i].y / 1.6, 0.0, 1.0), LEAF)
	return g


## Wheat clump: thin stalks, a couple of leaves and slim golden ears (instance tint = brightness).
static func wheat(rng: RandomNumberGenerator) -> GeoBuilder:
	var g := GeoBuilder.new()
	var stalk := col(0.70, 0.60, 0.33)
	var leaf := col(0.60, 0.58, 0.30)
	var grain := col(0.84, 0.68, 0.36)
	for s in 16:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * 0.3
		var root := Vector3(cos(a) * d, -0.02, sin(a) * d)
		var h := rng.randf_range(0.8, 1.05)
		var lean := Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1))
		var top := root + Vector3(0, h, 0) + lean
		var side := Vector3(cos(a + 1.3), 0, sin(a + 1.3))
		var base := g.vertex_count()
		g.raw_vertex(root - side * 0.006, Vector3.UP, stalk, Vector2(0, LEAF))
		g.raw_vertex(root + side * 0.006, Vector3.UP, stalk, Vector2(0, LEAF))
		g.raw_vertex(top - side * 0.004, Vector3.UP, stalk, Vector2(0.9, LEAF))
		g.raw_vertex(top + side * 0.004, Vector3.UP, stalk, Vector2(0.9, LEAF))
		g.quad(base, base + 1, base + 3, base + 2)
		# drooping ear
		var tip := top + Vector3(lean.x * 0.6, 0.15, lean.z * 0.6) + side * 0.02
		var v0 := g.vertex_count()
		g.cylinder(top - Vector3(0, 0.02, 0), tip, 0.014, 0.004, 4, grain, 0, true, grain * 1.08)
		for i in range(v0, g.vertex_count()):
			g.uvs[i] = Vector2(1.0, LEAF)
		if s % 3 == 0:
			# a leaf blade from mid stalk
			var mid := root + Vector3(0, h * 0.45, 0)
			var ld := Vector3(cos(a + 2.0), 0, sin(a + 2.0))
			var spine := PackedVector3Array([mid, mid + ld * 0.12 + Vector3(0, 0.05, 0), mid + ld * 0.24 - Vector3(0, 0.03, 0)])
			var sides := PackedVector3Array([ld.cross(Vector3.UP) * 0.008, ld.cross(Vector3.UP) * 0.014, ld.cross(Vector3.UP) * 0.002])
			var l0 := g.vertex_count()
			g.strip(spine, sides, leaf, leaf, false)
			for i in range(l0, g.vertex_count()):
				g.uvs[i] = Vector2(0.5, LEAF)
	return g
