class_name TreeMeshes
extends RefCounted
## Procedural toon tree generators (thread-safe: GeoBuilder only). Every generator builds one
## species variant at one LOD (0 near with full canopies, 1 mid, 2 far impostor) with its base at
## the origin, in metres. Vertex conventions (see veg_common.gdshaderinc): COLOR = linear albedo +
## tint mask in alpha, UV.x = sway weight (stiffness baked per species), UV.y = 0 wood, 1 foliage,
## 2 embers, 3 cap (snow/moss).

const WOOD := 0.0
const LEAF := 1.0


## sRGB authoring colour -> linear vertex colour with a tint mask in alpha.
static func col(r: float, g: float, b: float, mask: float = 1.0) -> Color:
	var c := Color(r, g, b).srgb_to_linear()
	c.a = mask
	return c


## Recolours vertices [from, end) by height between y0 and y1 (bottom -> top colours) with a
## little per-vertex brightness noise; keeps each vertex's alpha.
static func gradient(g: GeoBuilder, from: int, y0: float, y1: float, bottom: Color, top: Color, rng: RandomNumberGenerator, noise: float = 0.08) -> void:
	for i in range(from, g.verts.size()):
		var t := clampf((g.verts[i].y - y0) / maxf(y1 - y0, 0.01), 0.0, 1.0)
		var c := bottom.lerp(top, t * t * (3.0 - 2.0 * t))
		var k := 1.0 + rng.randf_range(-noise, noise)
		g.colors[i] = Color(c.r * k, c.g * k, c.b * k, g.colors[i].a)


## Sets sway (uv.x) of vertices [from, end) from their height: (y / height)^1 * stiffness, and kind.
static func sway_by_height(g: GeoBuilder, from: int, height: float, stiffness: float, kind: float) -> void:
	for i in range(from, g.verts.size()):
		g.uvs[i] = Vector2(clampf(g.verts[i].y / maxf(height, 0.1), 0.0, 1.5) * stiffness, kind)


# --- Conifers --------------------------------------------------------------------------------------

## Pine/fir: stacked drooping star-shaped tiers. snow 0..1 = snow on the tier tops (cap kind).
static func conifer(rng: RandomNumberGenerator, lod: int, snow: float, height: float = 11.0, dark: bool = false) -> GeoBuilder:
	var g := GeoBuilder.new()
	var h := height * rng.randf_range(0.9, 1.1)
	var R := h * rng.randf_range(0.24, 0.28)
	var bark := col(0.33, 0.24, 0.18, 0.2)
	var needle_lo := col(0.07, 0.17, 0.12) if dark else col(0.10, 0.24, 0.13)
	var needle_hi := col(0.17, 0.36, 0.20) if dark else col(0.24, 0.45, 0.20)
	if lod < 2:
		var t0 := g.vertex_count()
		g.cylinder(Vector3.ZERO, Vector3(0, h * 0.9, 0), h * 0.026, h * 0.008, 6 if lod == 0 else 5, bark, 0)
		sway_by_height(g, t0, h, 0.7, WOOD)
	var tiers: int = [7, 4, 2][lod]
	var sides: int = [12, 8, 6][lod]
	for i in tiers:
		var t := float(i) / float(maxi(tiers - 1, 1))
		var y := lerpf(h * 0.16, h * 0.78, t)
		var th := lerpf(h * 0.30, h * 0.24, t)
		var r := R * lerpf(1.0, 0.32, t) * rng.randf_range(0.92, 1.08)
		if lod == 2:
			y = lerpf(h * 0.14, h * 0.5, t)
			th = h * 0.55 if i == 1 else h * 0.4
			r = R * (1.0 if i == 0 else 0.68)
		_conifer_tier(g, rng, y, th, r, sides, needle_lo, needle_hi, snow, h, lod)
	return g


static func _conifer_tier(g: GeoBuilder, rng: RandomNumberGenerator, y: float, th: float, r: float, sides: int,
		lo: Color, hi: Color, snow: float, h: float, lod: int) -> void:
	var apex := Vector3(rng.randf_range(-0.05, 0.05) * r, y + th, rng.randf_range(-0.05, 0.05) * r)
	var center := Vector3(0, y - th * 0.3, 0)
	var droop := th * 0.22
	var rot := rng.randf() * TAU
	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []
	for k in sides:
		var a := rot + TAU * float(k) / float(sides) + rng.randf_range(-0.12, 0.12)
		var tip := (k % 2 == 0) or lod == 2
		var rr := r * (1.0 if tip else 0.74) * rng.randf_range(0.9, 1.08)
		var dir := Vector3(cos(a), 0, sin(a))
		outer.append(Vector3(0, y - (droop if tip else droop * 0.4), 0) + dir * rr)
		inner.append(apex.lerp(Vector3(0, y, 0) + dir * rr, 0.55) + Vector3(0, th * 0.04, 0))
	var snow_on := snow > 0.0
	var base := g.vertex_count()
	# top surface: apex -> inner ring (snow cap) -> outer ring (needles)
	g.uv2 = Vector2(1, 0) if snow_on else Vector2.ZERO
	var ia := g.vertex(apex, Vector3.UP, hi, Vector2(0, LEAF))
	var ring_in := []
	var ring_out := []
	for k in sides:
		var n_in := ((inner[k] - center).normalized() + Vector3.UP * 0.6).normalized()
		var n_out := ((outer[k] - center).normalized() + Vector3.UP * 0.25).normalized()
		var snow_here := snow_on and rng.randf() < snow
		g.uv2 = Vector2(1, 0) if snow_here else Vector2.ZERO
		ring_in.append(g.vertex(inner[k], n_in, hi.lerp(lo, 0.3), Vector2(0, LEAF)))
		g.uv2 = Vector2.ZERO
		ring_out.append(g.vertex(outer[k], n_out, lo.lerp(hi, 0.35), Vector2(0, LEAF)))
	for k in sides:
		var k2 := (k + 1) % sides
		g.tri(ia, ring_in[k2], ring_in[k])
		g.quad(ring_in[k], ring_in[k2], ring_out[k2], ring_out[k])
	# underside: outer ring -> hub on the trunk (dark)
	var hub := g.vertex(Vector3(0, y + th * 0.18, 0), Vector3.DOWN, lo * 0.7, Vector2(0, LEAF))
	var ring_u := []
	for k in sides:
		var n := ((outer[k] - Vector3(0, y + th, 0)).normalized())
		ring_u.append(g.vertex(outer[k], n, Color(lo.r * 0.75, lo.g * 0.75, lo.b * 0.75, 1.0), Vector2(0, LEAF)))
	for k in sides:
		var k2 := (k + 1) % sides
		g.tri(hub, ring_u[k], ring_u[k2])
	sway_by_height(g, base, h, 0.8, LEAF)


# --- Broadleaf family --------------------------------------------------------------------------------

## Generic canopy tree. style: &"oak" (EK broadleaf), &"blossom", &"tropical" (umbrella jungle tree),
## &"banyan" (wide, aerial roots), &"cypress" (columnar), &"maple" (rounder, lighter).
static func broadleaf(rng: RandomNumberGenerator, lod: int, style: StringName) -> GeoBuilder:
	var g := GeoBuilder.new()
	var p := _style(style)
	var h: float = p["height"] * rng.randf_range(0.88, 1.12)
	var bark: Color = p["bark"]
	var lo: Color = p["leaf_lo"]
	var hi: Color = p["leaf_hi"]
	var crown_y: float = h * float(p["crown_y"])
	var crown_r: float = h * float(p["crown_r"])
	var flat: float = p["flat"]
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * h * float(p["lean"]) * rng.randf()
	var top := Vector3(0, crown_y, 0) + lean
	# trunk
	if lod < 2:
		var t0 := g.vertex_count()
		var segs := 5 if lod == 0 else 3
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var r0: float = h * float(p["trunk"])
		for i in segs + 1:
			var t := float(i) / float(segs)
			var wob := Vector3(sin(t * 5.0 + rng.randf()) , 0, cos(t * 4.0 + rng.randf())) * h * float(p["twist"]) * t
			pts.append(Vector3(0, t * crown_y * 0.95, 0).lerp(top, t * t) + wob * (1.0 - t))
			radii.append(r0 * lerpf(1.25 if i == 0 else 1.0, 0.45, t))
		g.tube(pts, radii, 7 if lod == 0 else 5, bark)
		# root flare / buttresses
		if lod == 0:
			var nb: int = p["buttress"]
			for k in nb:
				var a := TAU * float(k) / float(nb) + rng.randf() * 0.5
				var d := Vector3(cos(a), 0, sin(a))
				var root := PackedVector3Array([d * r0 * 3.2 + Vector3(0, -0.15, 0), d * r0 * 1.6 + Vector3(0, r0 * 0.9, 0), Vector3(0, r0 * 3.0, 0)])
				g.tube(root, PackedFloat32Array([r0 * 0.18, r0 * 0.45, r0 * 0.5]), 4, bark)
		# branches toward the crown clusters
		sway_by_height(g, t0, h, 0.35, WOOD)
	# crown: clumps on two rings + a top; noise-displaced, soft canopy normals, darker inside
	var c0 := g.vertex_count()
	var layout := _crown_layout(rng, lod, style, top, crown_r, flat, int(p["clusters"]))
	var centers: Array[Vector3] = []
	for e: Array in layout:
		var c: Vector3 = e[0]
		centers.append(c)
		var sc := Vector3(1, flat, 1) if style != &"cypress" else Vector3(0.62, 1.0, 0.62)
		var sub := 1 if lod == 0 else 0
		if style == &"cypress" and lod < 2:
			sub = 1
		g.blob(c, e[1], sub, hi, rng, 0.2 if lod == 0 else 0.1, sc, top - Vector3(0, crown_r * flat * 0.3, 0), 0.7, lo, Vector2(0, LEAF))
		if lod == 0:
			leaf_tufts(g, rng, c, e[1], sc, 9 if style != &"cypress" else 7, e[1] * 0.32, top - Vector3(0, crown_r * flat * 0.3, 0), hi)
	gradient(g, c0, crown_y - crown_r * flat * 0.8, crown_y + crown_r * flat * 0.95, lo, hi, rng, 0.07)
	_canopy_ao(g, c0, top, crown_r, flat if style != &"cypress" else 1.8)
	sway_by_height(g, c0, h, float(p["sway"]), LEAF)
	if lod < 2 and style != &"cypress":
		# branches from the trunk top to the lower clumps
		var t1 := g.vertex_count()
		var r_b: float = h * float(p["trunk"])
		for i in range(1, centers.size(), 2 if lod == 0 else 3):
			var from := top.lerp(Vector3(0, crown_y * 0.7, 0), 0.6)
			var to := centers[i].lerp(top, 0.3) - Vector3(0, crown_r * flat * 0.2, 0)
			g.tube(PackedVector3Array([from, from.lerp(to, 0.5) + Vector3(0, 0.25, 0), to]),
					PackedFloat32Array([r_b * 0.45, r_b * 0.3, r_b * 0.14]), 4, bark)
		sway_by_height(g, t1, h, 0.45, WOOD)
	# blossom: sprinkle bright petal clusters
	if style == &"blossom" and lod == 0:
		var b0 := g.vertex_count()
		for i in 7:
			var c := centers[rng.randi() % centers.size()] + Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1.0), rng.randf_range(-1, 1)) * crown_r * 0.45
			g.blob(c, crown_r * 0.22, 1, col(1.0, 0.93, 0.96), rng, 0.15, Vector3(1, 0.8, 1), top, 0.6, col(0.98, 0.80, 0.88), Vector2(0, LEAF))
		sway_by_height(g, b0, h, float(p["sway"]), LEAF)
	# banyan aerial roots
	if style == &"banyan" and lod < 2:
		var r0 := g.vertex_count()
		var roots := 16 if lod == 0 else 7
		for i in roots:
			var a := rng.randf() * TAU
			var d := rng.randf_range(0.3, 0.92) * crown_r
			var x0 := top + Vector3(cos(a) * d, -crown_r * flat * 0.35, sin(a) * d)
			var x1 := Vector3(x0.x + rng.randf_range(-0.3, 0.3), -0.1, x0.z + rng.randf_range(-0.3, 0.3))
			var rr := rng.randf_range(0.04, 0.09) * h / 12.0
			g.tube(PackedVector3Array([x0, x0.lerp(x1, 0.5) + Vector3(rng.randf_range(-0.2, 0.2), 0, 0), x1]),
					PackedFloat32Array([rr * 0.7, rr, rr * 1.5]), 4, bark.lerp(col(0.55, 0.47, 0.38, 0.2), 0.4))
		sway_by_height(g, r0, h, 0.15, WOOD)
	return g


## Small outward-pointing leaf pyramids on a clump's surface: breaks the faceted silhouette into
## a leafy edge for the price of 3 triangles each (canopy-soft normals, recoloured later).
static func leaf_tufts(g: GeoBuilder, rng: RandomNumberGenerator, c: Vector3, r: float, sc: Vector3, n: int, size: float, nc: Vector3, color: Color) -> void:
	for k in n:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.35, 1.0), rng.randf_range(-1, 1)).normalized()
		var p := c + Vector3(d.x * sc.x, d.y * sc.y, d.z * sc.z) * r * 0.92
		var nrm := Vector3(d.x / sc.x, d.y / maxf(sc.y, 0.05), d.z / sc.z).normalized()
		var t1 := nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT).normalized()
		var t2 := nrm.cross(t1)
		var s := size * rng.randf_range(0.7, 1.2)
		var apex := p + nrm * s * 1.3 + Vector3(0, -s * 0.25, 0)
		var b := [p + t1 * s, p + (t2 * 0.87 - t1 * 0.5) * s, p + (-t2 * 0.87 - t1 * 0.5) * s]
		var soft := (apex - nc).normalized()
		var ia := g.vertex(apex, soft, color, Vector2(0, LEAF))
		var ib := []
		for q: Vector3 in b:
			ib.append(g.vertex(q, ((q - nc).normalized() + nrm).normalized(), color, Vector2(0, LEAF)))
		for j in 3:
			# outward faces (counter-clockwise seen from outside)
			var i0: int = ib[j]
			var i1: int = ib[(j + 1) % 3]
			var fn := (g.verts[i1] - g.verts[i0]).cross(g.verts[ia] - g.verts[i0])
			if fn.dot(nrm) >= 0.0:
				g.tri(i0, i1, ia)
			else:
				g.tri(i1, i0, ia)


## Clump centres/radii of a crown: [[centre, radius], ...].
static func _crown_layout(rng: RandomNumberGenerator, lod: int, style: StringName, top: Vector3, R: float, flat: float, clusters: int) -> Array:
	var out := []
	if style == &"cypress":
		var n: int = [4, 3, 2][lod]
		for i in n:
			var t := float(i) / float(maxi(n - 1, 1))
			out.append([top + Vector3(rng.randf_range(-0.1, 0.1) * R, lerpf(-0.9, 1.1, t) * R, rng.randf_range(-0.1, 0.1) * R), R * lerpf(0.95, 0.55, t)])
		return out
	if lod == 2:
		out.append([top + Vector3(0, R * flat * 0.15, 0), R * 0.85])
		for k in 2:
			var a := rng.randf() * TAU + k * PI
			out.append([top + Vector3(cos(a) * R * 0.5, -R * flat * 0.2, sin(a) * R * 0.5), R * 0.62])
		return out
	if lod == 1:
		out.append([top + Vector3(0, R * flat * 0.2, 0), R * 0.66])
		var n1 := 5
		var rot1 := rng.randf() * TAU
		for k in n1:
			var a := rot1 + TAU * float(k) / float(n1)
			out.append([top + Vector3(cos(a) * R * 0.6, -R * flat * 0.12, sin(a) * R * 0.6), R * rng.randf_range(0.48, 0.56)])
		return out
	out.append([top + Vector3(0, R * flat * 0.32, 0), R * 0.5])
	var upper := 5
	var lower := maxi(clusters - upper - 1, 4)
	var rot := rng.randf() * TAU
	for k in upper:
		var a := rot + TAU * float(k) / float(upper) + rng.randf_range(-0.25, 0.25)
		var d := R * rng.randf_range(0.42, 0.56)
		out.append([top + Vector3(cos(a) * d, R * flat * rng.randf_range(0.0, 0.2), sin(a) * d), R * rng.randf_range(0.4, 0.5)])
	for k in lower:
		var a := rot + PI / float(upper) + TAU * float(k) / float(lower) + rng.randf_range(-0.2, 0.2)
		var d := R * rng.randf_range(0.7, 0.86)
		out.append([top + Vector3(cos(a) * d, -R * flat * rng.randf_range(0.2, 0.42), sin(a) * d), R * rng.randf_range(0.34, 0.44)])
	return out


## Darkens canopy vertices towards the crown centre and underside (fake ambient occlusion).
static func _canopy_ao(g: GeoBuilder, from: int, center: Vector3, R: float, flat: float) -> void:
	for i in range(from, g.verts.size()):
		var d := g.verts[i] - center
		var q := Vector3(d.x / R, d.y / (R * flat), d.z / R).length()
		var ao := lerpf(0.5, 1.0, smoothstep(0.25, 0.95, q))
		ao *= lerpf(0.72, 1.0, smoothstep(-0.6, 0.3, g.normals[i].y))
		var c := g.colors[i]
		g.colors[i] = Color(c.r * ao, c.g * ao, c.b * ao, c.a)


static func _style(style: StringName) -> Dictionary:
	match style:
		&"blossom":
			return {"height": 7.0, "crown_y": 0.66, "crown_r": 0.42, "flat": 0.72, "trunk": 0.045, "twist": 0.08, "lean": 0.12,
				"clusters": 10, "buttress": 3, "sway": 0.55, "bark": col(0.26, 0.18, 0.16, 0.2),
				"leaf_lo": col(0.86, 0.50, 0.64), "leaf_hi": col(1.0, 0.80, 0.88)}
		&"tropical":
			return {"height": 13.0, "crown_y": 0.72, "crown_r": 0.44, "flat": 0.55, "trunk": 0.032, "twist": 0.03, "lean": 0.06,
				"clusters": 10, "buttress": 5, "sway": 0.4, "bark": col(0.42, 0.36, 0.28, 0.2),
				"leaf_lo": col(0.03, 0.20, 0.10), "leaf_hi": col(0.18, 0.48, 0.14)}
		&"banyan":
			return {"height": 11.0, "crown_y": 0.72, "crown_r": 0.62, "flat": 0.5, "trunk": 0.075, "twist": 0.06, "lean": 0.03,
				"clusters": 12, "buttress": 6, "sway": 0.3, "bark": col(0.38, 0.33, 0.27, 0.2),
				"leaf_lo": col(0.05, 0.22, 0.10), "leaf_hi": col(0.24, 0.50, 0.16)}
		&"cypress":
			return {"height": 9.0, "crown_y": 0.55, "crown_r": 0.25, "flat": 1.0, "trunk": 0.03, "twist": 0.0, "lean": 0.02,
				"clusters": 3, "buttress": 0, "sway": 0.5, "bark": col(0.30, 0.22, 0.17, 0.2),
				"leaf_lo": col(0.06, 0.18, 0.09), "leaf_hi": col(0.20, 0.38, 0.15)}
		&"maple":
			return {"height": 8.5, "crown_y": 0.66, "crown_r": 0.40, "flat": 0.85, "trunk": 0.04, "twist": 0.05, "lean": 0.08,
				"clusters": 10, "buttress": 3, "sway": 0.5, "bark": col(0.32, 0.25, 0.20, 0.2),
				"leaf_lo": col(0.20, 0.36, 0.08), "leaf_hi": col(0.58, 0.72, 0.22)}
	# oak (Earth Kingdom broadleaf)
	return {"height": 10.0, "crown_y": 0.64, "crown_r": 0.40, "flat": 0.78, "trunk": 0.045, "twist": 0.06, "lean": 0.08,
		"clusters": 11, "buttress": 4, "sway": 0.42, "bark": col(0.30, 0.23, 0.18, 0.2),
		"leaf_lo": col(0.09, 0.26, 0.09), "leaf_hi": col(0.36, 0.56, 0.17)}


# --- Palms ---------------------------------------------------------------------------------------------

static func palm(rng: RandomNumberGenerator, lod: int) -> GeoBuilder:
	var g := GeoBuilder.new()
	var h := rng.randf_range(8.0, 12.0)
	var bend := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * h * rng.randf_range(0.12, 0.3)
	var segs: int = [8, 5, 3][lod]
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in segs + 1:
		var t := float(i) / float(segs)
		pts.append(Vector3(0, h * t, 0) + bend * (t * t))
		radii.append(lerpf(0.3, 0.17, t) * (1.0 + (0.08 if i % 2 == 0 else -0.04)))
	var t0 := g.vertex_count()
	if lod < 2:
		g.tube(pts, radii, 7 if lod == 0 else 5, col(0.46, 0.38, 0.29, 0.2))
		# ring bands
		for i in range(t0, g.vertex_count()):
			var ring := int(round(g.verts[i].y / h * segs))
			if ring % 2 == 1:
				g.colors[i] = col(0.36, 0.29, 0.22, 0.2)
	sway_by_height(g, t0, h, 0.5, WOOD)
	var crown := pts[segs]
	var fronds: int = [12, 7, 6][lod]
	var f0 := g.vertex_count()
	for k in fronds:
		var a := TAU * float(k) / float(fronds) + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0, sin(a))
		var length := rng.randf_range(3.6, 4.8) * h / 10.0
		var lift := rng.randf_range(0.3, 0.9)
		var n: int = [7, 4, 3][lod]
		var spine := PackedVector3Array()
		var sides := PackedVector3Array()
		var perp := dir.cross(Vector3.UP).normalized()
		for i in n:
			var t := float(i) / float(n - 1)
			var p := crown + dir * length * t + Vector3(0, lift * length * 0.5 * t - length * 0.75 * t * t, 0)
			spine.append(p)
			var w := sin(pow(t, 0.7) * PI) * 0.34 * (1.0 if t > 0.05 else 0.3) + 0.02
			# slight V fold: sides tilt up
			sides.append(perp * w + Vector3(0, w * 0.35, 0))
		var lo := col(0.14, 0.34, 0.10)
		var hi := col(0.42, 0.62, 0.18)
		g.strip(spine, sides, lo, hi, true, Vector2(0, LEAF), Vector2(0, LEAF))
	sway_by_height(g, f0, h, 0.75, LEAF)
	# extra flutter on frond tips: increase sway with distance from the crown
	for i in range(f0, g.vertex_count()):
		var d := Vector2(g.verts[i].x - crown.x, g.verts[i].z - crown.z).length()
		g.uvs[i] = Vector2(g.uvs[i].x + d * 0.18, LEAF)
	if lod == 0:
		var c0 := g.vertex_count()
		for k in 4:
			var a := rng.randf() * TAU
			g.blob(crown + Vector3(cos(a) * 0.25, -0.35, sin(a) * 0.25), 0.16, 1, col(0.36, 0.26, 0.14, 0.3), null, 0.0)
		sway_by_height(g, c0, h, 0.5, WOOD)
	return g


# --- Bamboo grove --------------------------------------------------------------------------------------

static func bamboo(rng: RandomNumberGenerator, lod: int) -> GeoBuilder:
	var g := GeoBuilder.new()
	var culms: int = [12, 8, 5][lod]
	var culm_c := col(0.56, 0.64, 0.27, 0.6)
	var node_c := col(0.40, 0.48, 0.20, 0.6)
	var leaf_lo := col(0.18, 0.38, 0.12)
	var leaf_hi := col(0.42, 0.62, 0.20)
	var hmax := 0.0
	for c in culms:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * 1.3
		var base := Vector3(cos(a) * d, -0.1, sin(a) * d)
		var h := rng.randf_range(6.0, 10.5)
		hmax = maxf(hmax, h)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.4, 1.4) + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		var segs: int = [6, 3, 1][lod]
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var r := rng.randf_range(0.055, 0.085)
		for i in segs + 1:
			var t := float(i) / float(segs)
			pts.append(base + Vector3(0, h * t, 0) + lean * t * t)
			radii.append(r * lerpf(1.0, 0.6, t))
		var t0 := g.vertex_count()
		if lod < 2:
			g.tube(pts, radii, 5 if lod == 0 else 4, culm_c)
			for i in range(t0, g.vertex_count()):
				if fmod(g.verts[i].y, 0.55) < 0.06:
					g.colors[i] = node_c
		sway_by_height(g, t0, 9.0, 0.9, WOOD)
		# leaves along the upper half
		var l0 := g.vertex_count()
		if lod == 0:
			for k in 16:
				var t := rng.randf_range(0.45, 1.0)
				var p := base + Vector3(0, h * t, 0) + lean * t * t
				var la := rng.randf() * TAU
				var ld := Vector3(cos(la), 0, sin(la))
				var len := rng.randf_range(0.35, 0.6)
				var spine := PackedVector3Array([p, p + ld * len * 0.5 + Vector3(0, -0.03, 0), p + ld * len + Vector3(0, -len * 0.35, 0)])
				var side := ld.cross(Vector3.UP).normalized()
				var sides := PackedVector3Array([side * 0.01, side * 0.055, side * 0.004])
				g.strip(spine, sides, leaf_lo, leaf_hi, true, Vector2(0, LEAF), Vector2(0, LEAF))
		else:
			# leaf masses
			for k in (2 if lod == 1 else 1):
				var t := rng.randf_range(0.6, 0.95) if lod == 1 else 0.8
				var p := base + Vector3(0, h * t, 0) + lean * t * t
				g.blob(p, 1.1 if lod == 1 else 1.6, 0, leaf_hi.lerp(leaf_lo, 0.5), rng, 0.2, Vector3(1, 1.4, 1), p, 0.5, leaf_lo * 0.8, Vector2(0, LEAF))
		sway_by_height(g, l0, 9.0, 1.2, LEAF)
	return g


# --- Dead / charred --------------------------------------------------------------------------------------

## Bare tree. embers = glowing cracks near the base (volcanic charred trees).
static func bare(rng: RandomNumberGenerator, lod: int, charred: bool) -> GeoBuilder:
	var g := GeoBuilder.new()
	var h := rng.randf_range(5.0, 8.5)
	var bark := col(0.09, 0.08, 0.08, 0.15) if charred else col(0.52, 0.49, 0.45, 0.3)
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var segs: int = [6, 3, 2][lod]
	var off := Vector3.ZERO
	for i in segs + 1:
		var t := float(i) / float(segs)
		off += Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)) * (1.0 if i > 0 else 0.0)
		pts.append(Vector3(0, h * t, 0) + off * t)
		radii.append(lerpf(0.26, 0.05, t))
	var t0 := g.vertex_count()
	g.tube(pts, radii, [6, 5, 4][lod], bark)
	var branches: int = [6, 3, 0][lod]
	for b in branches:
		var t := rng.randf_range(0.35, 0.85)
		var i := int(t * segs)
		var from := pts[i].lerp(pts[mini(i + 1, segs)], 0.5)
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), rng.randf_range(0.5, 1.2), sin(a)).normalized()
		var l := h * rng.randf_range(0.18, 0.35)
		var mid := from + d * l * 0.5 + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		var end := from + d * l + Vector3(0, rng.randf_range(-0.2, 0.4), 0)
		g.tube(PackedVector3Array([from, mid, end]), PackedFloat32Array([0.07, 0.04, 0.012]), 4, bark)
		if lod == 0 and rng.randf() < 0.6:
			var e2 := end + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.2, 0.7), rng.randf_range(-0.6, 0.6))
			g.tube(PackedVector3Array([mid, mid.lerp(e2, 0.5), e2]), PackedFloat32Array([0.035, 0.02, 0.008]), 3, bark)
	sway_by_height(g, t0, h, 0.25, WOOD)
	if charred and lod < 2:
		# glowing cracks: patches of vertices near the base become embers
		for i in range(t0, g.vertex_count()):
			var p := g.verts[i]
			var n := sin(p.x * 13.0 + p.y * 7.0) * cos(p.z * 11.0 - p.y * 5.0)
			if p.y < h * 0.35 and n > 0.45:
				g.uv2s[i] = Vector2(0, 1)
				g.colors[i] = Color(0.05, rng.randf() * 0.1, 0.03, 0.0)
	return g
