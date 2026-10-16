class_name EarthMeshes
extends RefCounted
## Flat-shaded, surface-coloured earthbending geometry (cached): rocks and slabs
## re-coloured from the shared FxMeshes shapes, hewn pillars, spikes, armour
## plates, broken ground chunks and grab jaws. Colours are baked into the vertex
## colours from EarthPalette, so every piece shares ONE toon material (white
## albedo + vertex colours + ink outline) and batches well.
##
##   mi.mesh = EarthMeshes.pillar(0.75, 2.8, 2, &"grass")   # base at y = 0, 0.7 m buried
##   mi.material_override = EarthMeshes.material()
##
## Meshes face -Z (spikes lean toward -Z), base at y = 0 unless noted.

static var _cache: Dictionary = {}
static var _mat: ShaderMaterial = null


## Shared toon material for every earth mesh (vertex colours carry the palette).
static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ToonMaterials.make(Color(1, 1, 1), {"vertex_color": true, "outline_width": 1.25, "rim": 0.22,
				"outline_color": Color(0.09, 0.07, 0.05)})
	return _mat


## A unique copy (hit flash on constructs).
static func flash_material() -> ShaderMaterial:
	return ToonMaterials.make(Color(1, 1, 1), {"vertex_color": true, "outline_width": 1.3, "rim": 0.22, "unique": true,
			"outline_color": Color(0.09, 0.07, 0.05)})


static func clear_cache() -> void:
	_cache.clear()


# --- re-coloured shared shapes ------------------------------------------------------------------

## FxMeshes.rock in the colours of `surface` (turf / snow / dust cap on top).
static func rock(variant: int, detail: int, surface: StringName) -> ArrayMesh:
	var k := "rock_%d_%d_%s" % [variant % 8, detail, EarthPalette.key(surface)]
	if not _cache.has(k):
		_cache[k] = recolor(FxMeshes.rock(variant % 8, detail), surface, 0.62)
	return _cache[k]


## FxMeshes.slab (walls, shields) in the colours of `surface`.
static func slab(size: Vector3, variant: int, surface: StringName) -> ArrayMesh:
	var k := "slab_%s_%d_%s" % [str(size), variant % 4, EarthPalette.key(surface)]
	if not _cache.has(k):
		_cache[k] = recolor(FxMeshes.slab(size, variant % 4), surface, 0.75)
	return _cache[k]


## Armour plate: a flattened chunky rock (~1 x 0.34 x 0.78 m before scaling).
static func plate(variant: int, surface: StringName) -> ArrayMesh:
	var k := "plate_%d_%s" % [variant % 6, EarthPalette.key(surface)]
	if not _cache.has(k):
		var squashed := transformed(FxMeshes.rock(variant % 6, 1), Basis.from_scale(Vector3(1.0, 0.34, 0.78)))
		_cache[k] = recolor(squashed, surface, 0.55)
	return _cache[k]


## Broken ground chunk (fissure edges, crater rims): a thin slab with the
## surface on top (turf, sand, snow ...), centred, base at y = 0.
static func chunk(variant: int, surface: StringName) -> ArrayMesh:
	var k := "chunk_%d_%s" % [variant % 3, EarthPalette.key(surface)]
	if not _cache.has(k):
		var s: Vector3 = [Vector3(1.0, 0.3, 0.7), Vector3(0.8, 0.26, 0.9), Vector3(1.2, 0.34, 0.6)][variant % 3]
		_cache[k] = recolor(FxMeshes.slab(s, variant % 4), surface, 0.7)
	return _cache[k]


## Maps a near-white vertex-coloured mesh onto the palette: luminance picks
## dark .. rock, faces pointing up take the cap colour (turf, snow, dust).
static func recolor(src: ArrayMesh, surface: StringName, cap_from: float = 0.6) -> ArrayMesh:
	var pal := EarthPalette.of(surface)
	var dark: Color = (pal["dark"] as Color).srgb_to_linear()
	var rockc: Color = (pal["rock"] as Color).srgb_to_linear()
	var band: Color = (pal["band"] as Color).srgb_to_linear()
	var cap: Color = (pal["cap"] as Color).srgb_to_linear()
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var cols := PackedColorArray()
		cols.resize(verts.size())
		var src_cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		for i in verts.size():
			var sc := src_cols[i] if i < src_cols.size() else Color(0.9, 0.9, 0.9)
			var l := clampf((sc.get_luminance() - 0.62) / 0.42, 0.0, 1.0)
			var c := dark.lerp(rockc, l)
			# Strata: mid-tone faces lean toward the band colour.
			c = c.lerp(band, clampf(1.0 - absf(l - 0.5) * 3.0, 0.0, 1.0) * 0.45)
			var ny := norms[i].y if i < norms.size() else 0.0
			if ny > cap_from:
				c = c.lerp(cap, smoothstep(cap_from, minf(cap_from + 0.25, 1.0), ny))
			cols[i] = c
		arr[Mesh.ARRAY_COLOR] = cols
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


## Copy of `src` with every vertex transformed by `b` (normals re-derived).
static func transformed(src: ArrayMesh, b: Basis) -> ArrayMesh:
	var out := ArrayMesh.new()
	var nb := b.inverse().transposed()
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in verts.size():
			verts[i] = b * verts[i]
			if i < norms.size():
				norms[i] = (nb * norms[i]).normalized()
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


# --- hewn geometry --------------------------------------------------------------------------------

## A hewn stone column: 7 irregular sides, strata bands, a chipped shoulder,
## the surface's cap on top, a flared base and 0.7 m buried below y = 0 (so it
## reads as coming OUT of the ground while it rises).
static func pillar(radius: float, height: float, variant: int, surface: StringName) -> ArrayMesh:
	var k := "pillar_%.2f_%.2f_%d_%s" % [radius, height, variant % 4, EarthPalette.key(surface)]
	if _cache.has(k):
		return _cache[k]
	var rng := RandomNumberGenerator.new()
	rng.seed = 911 + variant * 71
	var sides := 7
	var base_ang: Array[float] = []
	var base_rad: Array[float] = []
	for i in sides:
		base_ang.append(TAU * (float(i) + rng.randf_range(-0.22, 0.22)) / sides)
		base_rad.append(rng.randf_range(0.86, 1.1))
	var levels: Array[float] = [-0.7, 0.0]
	var n_bands := maxi(2, int(height / 0.55))
	for b in range(1, n_bands):
		levels.append(height * float(b) / n_bands + rng.randf_range(-0.08, 0.08))
	levels.append(height * 0.93)
	var rings: Array = []
	for li in levels.size():
		var y: float = levels[li]
		var u := clampf(y / height, 0.0, 1.0)
		var flare := 1.18 if li <= 1 else 1.0
		var taper := lerpf(1.0, 0.88, u)
		var ring := PackedVector3Array()
		for i in sides:
			var r := radius * base_rad[i] * taper * flare * rng.randf_range(0.95, 1.05)
			var a := base_ang[i] + rng.randf_range(-0.04, 0.04)
			var yy := y
			if li == levels.size() - 1:
				yy -= rng.randf_range(0.0, 0.22)  # chipped shoulder
			ring.append(Vector3(sin(a) * r, yy, -cos(a) * r))
		rings.append(ring)
	var top := Vector3(rng.randf_range(-0.08, 0.08) * radius, height + 0.04, rng.randf_range(-0.08, 0.08) * radius)
	var pal := EarthPalette.of(surface)
	var cols := {"rock": (pal["rock"] as Color).srgb_to_linear(), "dark": (pal["dark"] as Color).srgb_to_linear(),
			"band": (pal["band"] as Color).srgb_to_linear(), "cap": (pal["cap"] as Color).srgb_to_linear()}
	var tris := PackedVector3Array()
	var tri_cols := PackedColorArray()
	var hints := PackedVector3Array()
	for li in rings.size() - 1:
		var a: PackedVector3Array = rings[li]
		var b: PackedVector3Array = rings[li + 1]
		var c: Color = cols["dark"] if li == 0 else (cols["band"] if li % 2 == 0 else cols["rock"])
		for i in sides:
			var j := (i + 1) % sides
			var mid_y := (a[i].y + b[i].y) * 0.5
			var shade := rng.randf_range(0.9, 1.06)
			_tri(tris, tri_cols, hints, a[i], b[i], b[j], c * shade, Vector3(0, mid_y, 0))
			_tri(tris, tri_cols, hints, a[i], b[j], a[j], c * shade, Vector3(0, mid_y, 0))
	var last: PackedVector3Array = rings[rings.size() - 1]
	for i in sides:
		var j := (i + 1) % sides
		_tri(tris, tri_cols, hints, last[i], last[j], top, (cols["cap"] as Color) * rng.randf_range(0.92, 1.04), Vector3(0, -10.0, 0))
	var mesh := _build(tris, tri_cols, hints)
	_cache[k] = mesh
	return mesh


## A jagged stone spike `height` tall: 5 sides, tip leaning `lean` (fraction
## of the height) toward -Z, base 0.4 m buried.
static func spike(height: float, radius: float, variant: int, surface: StringName, lean: float = 0.25) -> ArrayMesh:
	var k := "spike_%.2f_%.2f_%d_%.2f_%s" % [height, radius, variant % 4, lean, EarthPalette.key(surface)]
	if _cache.has(k):
		return _cache[k]
	var rng := RandomNumberGenerator.new()
	rng.seed = 313 + variant * 29
	var sides := 5
	var pal := EarthPalette.of(surface)
	var rockc: Color = (pal["rock"] as Color).srgb_to_linear()
	var dark: Color = (pal["dark"] as Color).srgb_to_linear()
	var light: Color = (pal["dust"] as Color).srgb_to_linear().lerp(rockc, 0.45)
	var levels := [[-0.4, 1.12], [0.0, 1.0], [height * 0.45, 0.62], [height * 0.8, 0.27]]
	var rings: Array = []
	for li in levels.size():
		var y := float(levels[li][0])
		var rr := float(levels[li][1]) * radius
		var u := clampf(y / height, 0.0, 1.0)
		var off := Vector3(0, 0, -lean * height * u * u)
		var ring := PackedVector3Array()
		var twist := rng.randf_range(-0.3, 0.3)
		for i in sides:
			var a := TAU * float(i) / sides + twist + rng.randf_range(-0.12, 0.12)
			var r := rr * rng.randf_range(0.82, 1.12)
			ring.append(Vector3(sin(a) * r, y, -cos(a) * r) + off)
		rings.append(ring)
	var tip := Vector3(rng.randf_range(-0.05, 0.05), height, -lean * height)
	var tris := PackedVector3Array()
	var tri_cols := PackedColorArray()
	var hints := PackedVector3Array()
	for li in rings.size() - 1:
		var a: PackedVector3Array = rings[li]
		var b: PackedVector3Array = rings[li + 1]
		var c := dark if li == 0 else rockc.lerp(light, float(li - 1) * 0.35)
		var axis := Vector3(0, (a[0].y + b[0].y) * 0.5, -lean * height * pow(clampf((a[0].y + b[0].y) * 0.5 / height, 0.0, 1.0), 2.0))
		for i in sides:
			var j := (i + 1) % sides
			var sh := rng.randf_range(0.88, 1.06)
			_tri(tris, tri_cols, hints, a[i], b[i], b[j], c * sh, axis)
			_tri(tris, tri_cols, hints, a[i], b[j], a[j], c * sh, axis)
	var last: PackedVector3Array = rings[rings.size() - 1]
	var axis_top := Vector3(0, height * 0.85, -lean * height * 0.72)
	for i in sides:
		var j := (i + 1) % sides
		_tri(tris, tri_cols, hints, last[i], last[j], tip, light * rng.randf_range(0.92, 1.05), axis_top)
	var mesh := _build(tris, tri_cols, hints)
	_cache[k] = mesh
	return mesh


## A curved stone jaw (grab): a flattened spike bending inward (toward +Z of
## its base, i.e. toward the grabbed legs when the jaw faces them along -Z).
static func jaw(height: float, variant: int, surface: StringName) -> ArrayMesh:
	var k := "jaw_%.2f_%d_%s" % [height, variant % 3, EarthPalette.key(surface)]
	if not _cache.has(k):
		_cache[k] = transformed(spike(height, 0.2, variant, surface, -0.38), Basis.from_scale(Vector3(1.25, 1.0, 0.7)))
	return _cache[k]


# --- builders -------------------------------------------------------------------------------------

## Adds a triangle, oriented so its front face (clockwise, Godot convention)
## points away from `hint` (a point on the shape's axis); hint.y < -5 = "up".
static func _tri(tris: PackedVector3Array, cols: PackedColorArray, hints: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, col: Color, hint: Vector3) -> void:
	tris.append(a)
	tris.append(b)
	tris.append(c)
	cols.append(col)
	hints.append(hint)


static func _build(tris: PackedVector3Array, cols: PackedColorArray, hints: PackedVector3Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var vcols := PackedColorArray()
	var n_tris := tris.size() / 3
	verts.resize(n_tris * 3)
	norms.resize(n_tris * 3)
	vcols.resize(n_tris * 3)
	for t in n_tris:
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			n = Vector3.UP
		var h := hints[t]
		var out_dir := Vector3.UP if h.y < -5.0 else ((a + b + c) / 3.0 - h)
		if h.y >= -5.0:
			out_dir.y *= 0.25
		# (b - a) x (c - a) is the counter-clockwise normal: flip to make the
		# outward side the clockwise (front) one.
		if n.dot(out_dir) > 0.0:
			var tmp := b
			b = c
			c = tmp
		else:
			n = -n
		n = n.normalized()
		verts[t * 3] = a
		verts[t * 3 + 1] = b
		verts[t * 3 + 2] = c
		for k in 3:
			norms[t * 3 + k] = n
			vcols[t * 3 + k] = cols[t]
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = vcols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
