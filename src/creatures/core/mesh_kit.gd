class_name MeshKit
extends RefCounted
## Procedural, skinned creature geometry.
##
## Everything is built from *lofts*: a sequence of cross-sections (superellipses with
## separate top/bottom half-heights) swept along a smooth Catmull-Rom path, optionally
## with rounded caps and "fluff" scallops for clumped fur silhouettes. Vertices carry
## skin weights from a weighting Callable (see RigSkeleton.chain_weighter), vertex
## colors and two UV sets with a fixed convention used by the creature shaders:
##
##   UV  = (u around the section: 0 = top/dorsal, 0.25 = right, 0.5 = bottom,
##          v along the part: 0..1)
##   UV2 = (u in meters around, v in meters along)  -> pattern / fur density
##
## Several named surfaces can be built at once (one material each); `commit()` returns
## an ArrayMesh with the surfaces in creation order.
##
## Section dictionary keys: p (Vector3 center), w (half width), h (top half height),
## hb (bottom half height, default h), n (superellipse exponent, default 2),
## up (orientation reference, default +Y or -Z for vertical paths), c (Color),
## f (fluff multiplier, default 1).

## Resolution multiplier (driven by Settings.detail_level()).
var res: float = 1.0

var _surfaces: Array[Surf] = []
var _cur: Surf = null


## Vertex/index buffers of one named surface.
class Surf:
	var name: StringName
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c := PackedColorArray()
	var b := PackedInt32Array()
	var w := PackedFloat32Array()
	var i := PackedInt32Array()


func _init(resolution: float = 1.0) -> void:
	res = resolution


## Selects (creating if needed) the surface subsequent geometry goes to.
func surface(surface_name: StringName) -> void:
	for s: Surf in _surfaces:
		if s.name == surface_name:
			_cur = s
			return
	_cur = Surf.new()
	_cur.name = surface_name
	_surfaces.append(_cur)


func surface_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for s: Surf in _surfaces:
		out.append(s.name)
	return out


func vertex_count() -> int:
	var n := 0
	for s: Surf in _surfaces:
		n += s.v.size()
	return n


## Builds the ArrayMesh (one surface per named surface, in creation order).
func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for s: Surf in _surfaces:
		if s.i.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.v
		arrays[Mesh.ARRAY_NORMAL] = s.n
		arrays[Mesh.ARRAY_TEX_UV] = s.uv
		arrays[Mesh.ARRAY_TEX_UV2] = s.uv2
		arrays[Mesh.ARRAY_COLOR] = s.c
		arrays[Mesh.ARRAY_BONES] = s.b
		arrays[Mesh.ARRAY_WEIGHTS] = s.w
		arrays[Mesh.ARRAY_INDEX] = s.i
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_name(mesh.get_surface_count() - 1, String(s.name))
	return mesh


# --- Lofts --------------------------------------------------------------------------

## Sweeps `sections` (see class doc) along a smooth path.
## Options: segs (around, default 16), sub (rings between key sections, default 3),
## interp (false = use sections as rings directly), cap0/cap1 ("round", "point", "flat", "none"),
## cap_len (round cap length relative to radius, default 1), weights (Callable(p) ->
## [b0, w0, b1, w1...]), per_vertex (bool: evaluate weights per vertex), color (Color),
## fluff (amplitude, fraction of radius), lobes (scallops around), fluff_freq (along,
## per meter), seed (int), v_offset (meters added to UV2.y), mark_row (int, marking
## texture row, see CreatureMaterials.mark_texture), fur (0..1 shell fur amount, stored in
## vertex color alpha; default 1).
func loft(sections: Array, o: Dictionary = {}) -> void:
	var segs := maxi(4, int(round(float(o.get("segs", 16)) * res)))
	var sub := maxi(1, int(round(float(o.get("sub", 3)) * res)))
	var rings: Array[Dictionary] = []
	if o.get("interp", true) and sections.size() >= 2:
		for k in sections.size() - 1:
			for s in sub:
				rings.append(_interp_section(sections, k, float(s) / sub))
		rings.append(_norm_section(sections[sections.size() - 1]))
	else:
		for s: Dictionary in sections:
			rings.append(_norm_section(s))
	if rings.size() < 2:
		return
	var cap0: String = o.get("cap0", "round")
	var cap1: String = o.get("cap1", "round")
	var cap_len: float = o.get("cap_len", 1.0)
	var capn := maxi(2, int(round(4.0 * res)))
	# Tangents of the core path (needed for caps).
	var t_first: Vector3 = (rings[1]["p"] - rings[0]["p"]).normalized()
	var t_last: Vector3 = (rings[rings.size() - 1]["p"] - rings[rings.size() - 2]["p"]).normalized()
	if cap0 == "round" or cap0 == "point":
		var r0: Dictionary = rings[0]
		var pre: Array[Dictionary] = []
		var rad0: float = (float(r0["w"]) + float(r0["h"])) * 0.5 * cap_len
		var steps := capn if cap0 == "round" else 1
		for a in range(steps, 0, -1):
			var phi := float(a) / steps * PI * 0.5
			var r := r0.duplicate()
			var k := cos(phi) if cap0 == "round" else 0.0
			r["p"] = r0["p"] - t_first * rad0 * sin(phi)
			r["w"] = float(r0["w"]) * k
			r["h"] = float(r0["h"]) * k
			r["hb"] = float(r0["hb"]) * k
			pre.append(r)
		pre.append_array(rings)
		rings = pre
	if cap0 == "flat":
		var rf: Dictionary = rings[0].duplicate()
		rf["w"] = 0.0
		rf["h"] = 0.0
		rf["hb"] = 0.0
		rf["p"] = (rings[0]["p"] as Vector3) - t_first * 0.0005
		rings.push_front(rf)
	if cap1 == "flat":
		var rl: Dictionary = rings[rings.size() - 1].duplicate()
		rl["w"] = 0.0
		rl["h"] = 0.0
		rl["hb"] = 0.0
		rl["p"] = (rings[rings.size() - 1]["p"] as Vector3) + t_last * 0.0005
		rings.append(rl)
	if cap1 == "round" or cap1 == "point":
		var r1: Dictionary = rings[rings.size() - 1]
		var rad1: float = (float(r1["w"]) + float(r1["h"])) * 0.5 * cap_len
		var steps := capn if cap1 == "round" else 1
		for a in range(1, steps + 1):
			var phi := float(a) / steps * PI * 0.5
			var r := r1.duplicate()
			var k := cos(phi) if cap1 == "round" else 0.0
			r["p"] = r1["p"] + t_last * rad1 * sin(phi)
			r["w"] = float(r1["w"]) * k
			r["h"] = float(r1["h"]) * k
			r["hb"] = float(r1["hb"]) * k
			rings.append(r)
	_emit_rings(rings, segs, o)


## Ellipsoid centered at `center` with `radii`, oriented by `basis` (its -Z axis is the
## loft direction). Same options as loft().
func ellipsoid(center: Vector3, radii: Vector3, o: Dictionary = {}, basis: Basis = Basis.IDENTITY) -> void:
	var n := maxi(6, int(round(float(o.get("rings", 10)) * res)))
	var secs: Array = []
	for i in n + 1:
		var phi := float(i) / n * PI
		var z := -cos(phi) * radii.z
		var k := sin(phi)
		var p := center + basis * Vector3(0, 0, -z)
		secs.append({"p": p, "w": radii.x * k, "h": radii.y * k, "up": basis * Vector3.UP,
				"n": o.get("n", 2.0), "c": o.get("color", Color.WHITE)})
	var oo := o.duplicate()
	oo["interp"] = false
	oo["cap0"] = "none"
	oo["cap1"] = "none"
	loft(secs, oo)


## Tapered tube through `points` with per-point radius (e.g. horns, whiskers, claws).
## Options as loft(); `up` sets the orientation reference; flatten (0..1) squashes it.
func tube(points: PackedVector3Array, radii: PackedFloat32Array, o: Dictionary = {}) -> void:
	var secs: Array = []
	var flat: float = o.get("flatten", 0.0)
	for i in points.size():
		var s := {"p": points[i], "w": radii[i], "h": radii[i] * (1.0 - flat)}
		if o.has("up"):
			s["up"] = o["up"]
		secs.append(s)
	var oo := o.duplicate()
	if not oo.has("cap1"):
		oo["cap1"] = "point" if radii[radii.size() - 1] < 0.002 else "round"
	loft(secs, oo)


## Closed thin slab spanning a grid of points (rows x cols), e.g. a wing membrane or
## a flat fin. `grid[r][c]` are positions; `thickness` in meters; the slab's top faces
## +normal of the grid. Weights are evaluated per vertex. Options: weights, color,
## color_edge (Color blended toward the last row), uv_scale.
func sheet(grid: Array, thickness: float, o: Dictionary = {}) -> void:
	var rows := grid.size()
	var cols := (grid[0] as PackedVector3Array).size()
	var weigh: Callable = o.get("weights", Callable())
	var col: Color = o.get("color", Color.WHITE)
	var col_edge: Color = o.get("color_edge", col)
	var s := _cur
	# Grid normals.
	var nrm: Array[PackedVector3Array] = []
	for r in rows:
		var row := PackedVector3Array()
		for c in cols:
			var a: Vector3 = grid[mini(r + 1, rows - 1)][c] - grid[maxi(r - 1, 0)][c]
			var b: Vector3 = grid[r][mini(c + 1, cols - 1)] - grid[r][maxi(c - 1, 0)]
			var n := b.cross(a)
			row.append(n.normalized() if n.length_squared() > 1e-12 else Vector3.UP)
		nrm.append(row)
	var base_top := s.v.size()
	for side in 2:
		var sign := 1.0 if side == 0 else -1.0
		for r in rows:
			for c in cols:
				var p: Vector3 = grid[r][c]
				var n: Vector3 = nrm[r][c] * sign
				var w := PackedFloat32Array([0, 1.0, 0, 0.0])
				if weigh.is_valid():
					w = weigh.call(p)
				var t := float(r) / maxf(1.0, rows - 1)
				_add_vertex(s, p + n * thickness * 0.5, n, Vector2(float(c) / maxf(1.0, cols - 1), t),
						Vector2(float(c), float(r)), col.lerp(col_edge, t * t), w)
	var base_bot := base_top + rows * cols
	for r in rows - 1:
		for c in cols - 1:
			var a := r * cols + c
			var b := a + 1
			var cc := a + cols + 1
			var d := a + cols
			# top (normal +n): emit clockwise-from-outside order
			_tri_oriented(s, base_top + a, base_top + b, base_top + cc, nrm[r][c])
			_tri_oriented(s, base_top + a, base_top + cc, base_top + d, nrm[r][c])
			_tri_oriented(s, base_bot + a, base_bot + b, base_bot + cc, -nrm[r][c])
			_tri_oriented(s, base_bot + a, base_bot + cc, base_bot + d, -nrm[r][c])
	# Rim: stitch top and bottom along the border.
	var border: Array[int] = []
	for c in cols: border.append(c)
	for r in range(1, rows): border.append(r * cols + cols - 1)
	for c in range(cols - 2, -1, -1): border.append((rows - 1) * cols + c)
	for r in range(rows - 2, 0, -1): border.append(r * cols)
	var center := Vector3.ZERO
	for r in rows:
		for c in cols:
			center += grid[r][c]
	center /= float(rows * cols)
	for k in border.size():
		var i0: int = border[k]
		var i1: int = border[(k + 1) % border.size()]
		var mid: Vector3 = (s.v[base_top + i0] + s.v[base_top + i1]) * 0.5
		var outward := (mid - center)
		_tri_oriented(s, base_top + i0, base_bot + i0, base_bot + i1, outward)
		_tri_oriented(s, base_top + i0, base_bot + i1, base_top + i1, outward)


## Eyeball of `radius` at `center` looking along `look`. UV stores the eye-local
## direction's xy and UV2.x its forwardness for creature_eye.gdshader. Options:
## scale (Vector3 squash in eye space), weights (Callable), up (Vector3).
func eye(center: Vector3, radius: float, look: Vector3, o: Dictionary = {}) -> void:
	var s := _cur
	var rings := maxi(8, int(round(12.0 * res)))
	var segs := maxi(10, int(round(18.0 * res)))
	var up_ref: Vector3 = o.get("up", Vector3.UP)
	var z := -look.normalized()
	var x := up_ref.cross(z).normalized()
	var y := z.cross(x).normalized()
	var b := Basis(x, y, z)
	var sc: Vector3 = o.get("scale", Vector3.ONE)
	var weigh: Callable = o.get("weights", Callable())
	var w := PackedFloat32Array([0, 1.0, 0, 0.0])
	if weigh.is_valid():
		w = weigh.call(center)
	var base := s.v.size()
	for i in rings + 1:
		var phi := float(i) / rings * PI
		for j in segs + 1:
			var th := float(j) / segs * TAU
			var d := Vector3(sin(phi) * cos(th), sin(phi) * sin(th), -cos(phi))
			var p := center + b * (d * sc * radius)
			var n := (b * (d / sc)).normalized()
			_add_vertex(s, p, n, Vector2(d.x, d.y), Vector2(-d.z, 0.0), Color(1, 1, 1, 0), w)
	var row_len := segs + 1
	for i in rings:
		for j in segs:
			var a := base + i * row_len + j
			var c := a + row_len + 1
			var bb := a + 1
			var d := a + row_len
			var out := s.v[a] + s.v[c] - center * 2.0
			_tri_oriented(s, a, bb, c, out)
			_tri_oriented(s, a, c, d, out)


# --- Internals ------------------------------------------------------------------------

func _norm_section(s: Dictionary) -> Dictionary:
	var h: float = s.get("h", s.get("w", 0.1))
	return {
		"p": s["p"], "w": float(s.get("w", h)), "h": h, "hb": float(s.get("hb", h)),
		"n": float(s.get("n", 2.0)), "up": s.get("up", Vector3.ZERO), "c": s.get("c", Color(-1, 0, 0)),
		"f": float(s.get("f", 1.0)),
	}


func _interp_section(secs: Array, k: int, t: float) -> Dictionary:
	var s1 := _norm_section(secs[k])
	var s2 := _norm_section(secs[k + 1])
	var s0 := _norm_section(secs[k - 1]) if k > 0 else s1
	var s3 := _norm_section(secs[k + 2]) if k + 2 < secs.size() else s2
	var p0: Vector3 = s0["p"] if k > 0 else s1["p"] * 2.0 - s2["p"]
	var p3: Vector3 = s3["p"] if k + 2 < secs.size() else s2["p"] * 2.0 - s1["p"]
	var out := {}
	out["p"] = _cr_v(p0, s1["p"], s2["p"], p3, t)
	for key: String in ["w", "h", "hb", "f"]:
		var v := _cr_f(s0[key], s1[key], s2[key], s3[key], t)
		var lo := minf(s1[key], s2[key])
		var hi := maxf(s1[key], s2[key])
		out[key] = clampf(v, lo - (hi - lo) * 0.15, hi + (hi - lo) * 0.15)
		out[key] = maxf(out[key], 0.0)
	out["n"] = lerpf(s1["n"], s2["n"], t)
	var u1: Vector3 = s1["up"]
	var u2: Vector3 = s2["up"]
	if u1 == Vector3.ZERO and u2 == Vector3.ZERO:
		out["up"] = Vector3.ZERO
	else:
		if u1 == Vector3.ZERO: u1 = u2
		if u2 == Vector3.ZERO: u2 = u1
		out["up"] = u1.lerp(u2, t).normalized()
	var c1: Color = s1["c"]
	var c2: Color = s2["c"]
	if c1.r < 0.0 and c2.r < 0.0:
		out["c"] = c1
	else:
		if c1.r < 0.0: c1 = c2
		if c2.r < 0.0: c2 = c1
		out["c"] = c1.lerp(c2, smoothstep(0.0, 1.0, t))
	return out


static func _cr_v(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


static func _cr_f(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _emit_rings(rings: Array[Dictionary], segs: int, o: Dictionary) -> void:
	var s := _cur
	var nr := rings.size()
	var weigh: Callable = o.get("weights", Callable())
	var per_vertex: bool = o.get("per_vertex", false)
	var base_col: Color = o.get("color", Color.WHITE)
	var fluff: float = o.get("fluff", 0.0)
	var lobes: float = o.get("lobes", 9.0)
	var fluff_freq: float = o.get("fluff_freq", 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(o.get("seed", 1))
	var jitter := PackedFloat32Array()
	for j in 64:
		jitter.append(rng.randf())
	var v_off: float = o.get("v_offset", 0.0)
	var mark_row := float(int(o.get("mark_row", 0)))
	var fur_amt: float = o.get("fur", 1.0)
	# Arc length along the path.
	var arc := PackedFloat32Array([0.0])
	for i in range(1, nr):
		arc.append(arc[i - 1] + (rings[i]["p"] as Vector3).distance_to(rings[i - 1]["p"]))
	var total := maxf(arc[nr - 1], 1e-4)
	# Positions.
	var pos: Array[PackedVector3Array] = []
	var centers := PackedVector3Array()
	var tangents := PackedVector3Array()
	for i in nr:
		var r: Dictionary = rings[i]
		var p: Vector3 = r["p"]
		var t: Vector3
		if i == 0:
			t = (rings[1]["p"] as Vector3) - p
		elif i == nr - 1:
			t = p - (rings[i - 1]["p"] as Vector3)
		else:
			t = (rings[i + 1]["p"] as Vector3) - (rings[i - 1]["p"] as Vector3)
		if t.length_squared() < 1e-12:
			t = tangents[i - 1] if i > 0 else Vector3.FORWARD
		t = t.normalized()
		tangents.append(t)
		centers.append(p)
		var up_ref: Vector3 = r["up"]
		if up_ref == Vector3.ZERO:
			up_ref = Vector3.UP if absf(t.y) < 0.85 else Vector3.FORWARD
		if absf(t.dot(up_ref)) > 0.98:
			up_ref = Vector3.FORWARD if absf(t.z) < 0.9 else Vector3.UP
		var right := t.cross(up_ref).normalized()
		var up := right.cross(t).normalized()
		var w: float = r["w"]
		var h: float = r["h"]
		var hb: float = r["hb"]
		var e := 2.0 / maxf(0.5, float(r["n"]))
		var fl: float = fluff * float(r["f"])
		var row := PackedVector3Array()
		row.resize(segs + 1)
		for j in segs + 1:
			var u := float(j) / segs
			var th := u * TAU
			var sn := sin(th)
			var cs := cos(th)
			var x := signf(sn) * pow(absf(sn), e)
			var y := signf(cs) * pow(absf(cs), e)
			var rr := 1.0
			if fl > 0.0:
				var ph := u * lobes + arc[i] * fluff_freq * 0.37 + jitter[int(arc[i] * fluff_freq) & 63] * 0.6
				var lobe := pow(0.5 + 0.5 * cos(ph * TAU), 2.0)
				rr += fl * (lobe - 0.35) * (0.7 + 0.6 * jitter[(j * 7 + i) & 63])
			row[j] = p + (right * (x * w) + up * (y * (h if y >= 0.0 else hb))) * rr
		pos.append(row)
	# Emit vertices.
	var base := s.v.size()
	for i in nr:
		var r: Dictionary = rings[i]
		var col: Color = r["c"]
		if col.r < 0.0:
			col = base_col
		var wr := PackedFloat32Array([0, 1.0, 0, 0.0])
		if weigh.is_valid() and not per_vertex:
			wr = weigh.call(centers[i])
		var perim := PI * (float(r["w"]) + (float(r["h"]) + float(r["hb"])) * 0.5)
		for j in segs + 1:
			var p := pos[i][j]
			var jn := j + 1 if j < segs else 1
			var jp := j - 1 if j > 0 else segs - 1
			var around := pos[i][jn] - pos[i][jp]
			var along := pos[mini(i + 1, nr - 1)][j] - pos[maxi(i - 1, 0)][j]
			var n := around.cross(along)
			if n.length_squared() < 1e-14:
				n = tangents[i] * (-1.0 if i < nr / 2 else 1.0)
			else:
				n = n.normalized()
				if n.dot(p - centers[i]) < 0.0 and (p - centers[i]).length_squared() > 1e-10:
					n = -n
			var w := wr
			if per_vertex and weigh.is_valid():
				w = weigh.call(p)
			var u := float(j) / segs
			_add_vertex(s, p, n, Vector2(u, mark_row + arc[i] / total * 0.998), Vector2(u * perim, arc[i] + v_off),
					Color(col.r, col.g, col.b, col.a * fur_amt), w)
	var idx := s.i
	var row_len := segs + 1
	for i in nr - 1:
		for j in segs:
			var a := base + i * row_len + j
			var b := a + 1
			var c := a + row_len + 1
			var d := a + row_len
			# Clockwise-from-outside winding (Godot front faces).
			idx.append(a); idx.append(c); idx.append(b)
			idx.append(a); idx.append(d); idx.append(c)


func _add_vertex(s: Surf, p: Vector3, n: Vector3, uv: Vector2, uv2: Vector2, c: Color, w: PackedFloat32Array) -> void:
	s.v.append(p)
	s.n.append(n)
	s.uv.append(uv)
	s.uv2.append(uv2)
	var lc := Color(c.r, c.g, c.b).srgb_to_linear()
	s.c.append(Color(lc.r, lc.g, lc.b, c.a))
	var b := s.b
	var wt := s.w
	var total := 0.0
	var k := 0
	while k < w.size() and k < 8:
		total += w[k + 1]
		k += 2
	if total <= 0.0:
		total = 1.0
	for m in 4:
		if m * 2 + 1 < w.size():
			b.append(int(w[m * 2]))
			wt.append(w[m * 2 + 1] / total)
		else:
			b.append(int(w[0]))
			wt.append(0.0)


func _tri_oriented(s: Surf, a: int, b: int, c: int, outward: Vector3) -> void:
	var v := s.v
	var fn := (v[b] - v[a]).cross(v[c] - v[a])
	var idx := s.i
	# Godot front faces are clockwise as seen from outside: cross() points inward.
	if fn.dot(outward) > 0.0:
		idx.append(a); idx.append(c); idx.append(b)
	else:
		idx.append(a); idx.append(b); idx.append(c)
