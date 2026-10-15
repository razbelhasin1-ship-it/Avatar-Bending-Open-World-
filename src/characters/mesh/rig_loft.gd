class_name RigLoft
extends RefCounted
## A skinned tube surface swept along a path with a superellipse cross-section
## (separate side/front/back radii) and color "bands" along its length.
##
## Parametrization: t in [0, 1] along the path, a in [0, 1) around the ring.
## a = 0 points to the side axis S = F x T, a = 0.25 to the front F.
## The same surface function places decals/strips on top of the tube (see
## surface_point()), so overlays deform exactly like the body under them.

var path := PackedVector3Array()
var _cum := PackedFloat32Array()
var ref_front := Vector3(0, 0, -1)
## Profile keys: t, side radius, front radius, back radius, squareness exponent.
var key_t := PackedFloat32Array()
var key_rs := PackedFloat32Array()
var key_rf := PackedFloat32Array()
var key_rb := PackedFloat32Array()
var key_n := PackedFloat32Array()
## Callable(t: float, a: float, pos: Vector3) -> Dictionary {bone: weight}.
var weight_fn: Callable
## Optional Callable(t: float, a: float, base: Color) -> Color for patterns.
var color_fn: Callable
## Optional Callable(t: float, a: float) -> float extra radius (bumps, fur, folds).
var bump_fn: Callable
var default_color := Color.WHITE
## Angular range for open sheets (capes, aprons). a1 - a0 < 1 leaves the ring open.
var a0 := 0.0
var a1 := 1.0
## Emits inward-facing geometry (inner side of skirts/sleeves/capes).
var flip := false


static func create(points: PackedVector3Array, front: Vector3, wfn: Callable) -> RigLoft:
	var l := RigLoft.new()
	l.set_path(points)
	l.ref_front = front.normalized()
	l.weight_fn = wfn
	return l


func set_path(points: PackedVector3Array) -> void:
	path = points
	_cum.resize(points.size())
	var total := 0.0
	_cum[0] = 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
		_cum[i] = total
	if total > 0.0:
		for i in points.size():
			_cum[i] /= total


## Adds a profile key (radii in meters). n = 2 ellipse, > 2 boxier.
func key(t: float, rs: float, rf: float, rb: float = -1.0, n: float = 2.0) -> RigLoft:
	key_t.append(t)
	key_rs.append(rs)
	key_rf.append(rf)
	key_rb.append(rf if rb < 0.0 else rb)
	key_n.append(n)
	return self


func length() -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
	return total


func center(t: float) -> Vector3:
	t = clampf(t, 0.0, 1.0)
	var n := path.size()
	for i in range(1, n):
		if t <= _cum[i] or i == n - 1:
			var seg := _cum[i] - _cum[i - 1]
			var u := (t - _cum[i - 1]) / seg if seg > 0.0 else 0.0
			return path[i - 1].lerp(path[i], clampf(u, 0.0, 1.0))
	return path[n - 1]


func tangent(t: float) -> Vector3:
	var e := 0.02
	var d := center(minf(t + e, 1.0)) - center(maxf(t - e, 0.0))
	if d.length_squared() < 1e-12:
		return (path[path.size() - 1] - path[0]).normalized()
	return d.normalized()


func _profile(t: float, out: PackedFloat32Array) -> void:
	var n := key_t.size()
	if n == 0:
		out[0] = 0.05; out[1] = 0.05; out[2] = 0.05; out[3] = 2.0
		return
	if t <= key_t[0]:
		out[0] = key_rs[0]; out[1] = key_rf[0]; out[2] = key_rb[0]; out[3] = key_n[0]
		return
	if t >= key_t[n - 1]:
		out[0] = key_rs[n - 1]; out[1] = key_rf[n - 1]; out[2] = key_rb[n - 1]; out[3] = key_n[n - 1]
		return
	var i := 1
	while i < n - 1 and t > key_t[i]:
		i += 1
	var t0 := key_t[i - 1]
	var t1 := key_t[i]
	var u := (t - t0) / maxf(t1 - t0, 1e-6)
	var i0 := maxi(i - 2, 0)
	var i3 := mini(i + 1, n - 1)
	out[0] = _cr(key_rs[i0], key_rs[i - 1], key_rs[i], key_rs[i3], u)
	out[1] = _cr(key_rf[i0], key_rf[i - 1], key_rf[i], key_rf[i3], u)
	out[2] = _cr(key_rb[i0], key_rb[i - 1], key_rb[i], key_rb[i3], u)
	out[3] = lerpf(key_n[i - 1], key_n[i], u)


static func _cr(p0: float, p1: float, p2: float, p3: float, u: float) -> float:
	# Catmull-Rom, clamped so radii never overshoot below the smaller neighbour.
	var v := 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)
	return clampf(v, minf(p1, p2) * 0.85, maxf(p1, p2) * 1.15)


var _prof := PackedFloat32Array([0.0, 0.0, 0.0, 2.0])


## Point on the surface at (t, a) pushed out by `inflate` meters.
func point(t: float, a: float, inflate: float = 0.0) -> Vector3:
	var c := center(t)
	var tg := tangent(t)
	var f := (ref_front - tg * ref_front.dot(tg))
	if f.length_squared() < 1e-8:
		f = Vector3.UP - tg * Vector3.UP.dot(tg)
	f = f.normalized()
	var s := f.cross(tg)
	_profile(t, _prof)
	var th := a * TAU
	var cs := cos(th)
	var sn := sin(th)
	var ex := 2.0 / maxf(_prof[3], 0.5)
	var x := signf(cs) * pow(absf(cs), ex)
	var y := signf(sn) * pow(absf(sn), ex)
	var bump := 0.0
	if bump_fn.is_valid():
		bump = bump_fn.call(t, a)
	var rs := _prof[0] + inflate + bump
	var rfb := (_prof[1] if sn > 0.0 else _prof[2]) + inflate + bump
	return c + s * (x * rs) + f * (y * rfb)


## Returns [position, normal] at (t, a) for placing overlays.
func surface_point(t: float, a: float, inflate: float = 0.0) -> Array:
	var p := point(t, a, inflate)
	var e := 0.004
	var da := point(t, a + e, inflate) - point(t, a - e, inflate)
	var t0 := clampf(t - e, 0.0, 1.0)
	var t1 := clampf(t + e, 0.0, 1.0)
	var dt := point(t1, a, inflate) - point(t0, a, inflate)
	var n := da.cross(dt)
	if n.length_squared() < 1e-14:
		n = p - center(t)
	return [p, n.normalized()]


func weights_at(t: float, a: float, pos: Vector3) -> Dictionary:
	return weight_fn.call(t, a, pos)


## Emits the tube into `b`.
## bands: Array of {"t0","t1","color","inflate"} covering the range (sorted);
## empty = one band of default_color. rings ~ ring count over the full length.
func emit(b: SkinMeshBuilder, rings: int, segs: int, bands: Array = [], cap_start: bool = false, cap_end: bool = false, t_start: float = 0.0, t_end: float = 1.0) -> void:
	if bands.is_empty():
		bands = [{"t0": t_start, "t1": t_end, "color": default_color, "inflate": 0.0}]
	b.begin_part()
	var rows: Array = []
	var skip := PackedInt32Array()
	var prev_inflate := 0.0
	var prev_color := default_color
	var first := true
	for band: Dictionary in bands:
		var bt0: float = maxf(float(band["t0"]), t_start)
		var bt1: float = minf(float(band["t1"]), t_end)
		if bt1 <= bt0 + 0.0001:
			continue
		var inflate: float = float(band.get("inflate", 0.0))
		var col: Color = band.get("color", default_color)
		if not first:
			# Boundary between bands: crisp color edge, optional hem lip.
			skip.append(rows.size() - 1)
			if absf(inflate - prev_inflate) > 0.0015:
				var outer := prev_color if prev_inflate > inflate else col
				rows.append(_ring(b, bt0, segs, prev_inflate, outer))
				rows.append(_ring(b, bt0, segs, inflate, outer))
				skip.append(rows.size() - 1)
		var count := maxi(1, int(round(float(rings) * (bt1 - bt0))))
		for k in count + 1:
			var t := lerpf(bt0, bt1, float(k) / float(count))
			rows.append(_ring(b, t, segs, inflate, col))
		prev_inflate = inflate
		prev_color = col
		first = false
	b.add_grid(rows, _closed(), skip, flip)
	if cap_start and rows.size() > 0:
		var c0 := b.add_vertex(center(t_start), _color_at(t_start, 0.0, (bands[0] as Dictionary).get("color", default_color)), weights_at(t_start, 0.0, center(t_start)))
		b.add_cap(rows[0], c0, not flip)
	if cap_end and rows.size() > 0:
		var lastc: Color = (bands[bands.size() - 1] as Dictionary).get("color", default_color)
		var c1 := b.add_vertex(center(t_end), _color_at(t_end, 0.0, lastc), weights_at(t_end, 0.0, center(t_end)))
		b.add_cap(rows[rows.size() - 1], c1, flip)
	b.end_part()


func _color_at(t: float, a: float, base: Color) -> Color:
	if color_fn.is_valid():
		return color_fn.call(t, a, base)
	return base


func _closed() -> bool:
	return a1 - a0 >= 0.9999


func _ring(b: SkinMeshBuilder, t: float, segs: int, inflate: float, col: Color) -> PackedInt32Array:
	var ring := PackedInt32Array()
	var closed := _closed()
	var count := segs if closed else segs + 1
	ring.resize(count)
	for i in count:
		var a := a0 + (a1 - a0) * float(i) / float(segs)
		var pos := point(t, a, inflate)
		ring[i] = b.add_vertex(pos, _color_at(t, a, col), weights_at(t, a, pos))
	return ring


## Adds a flat ribbon lying on the surface along a polyline of (t, a) points.
## Useful for trims, collars, sashes and painted markings.
func emit_strip(b: SkinMeshBuilder, pts: PackedVector2Array, width: float, lift: float, col: Color, taper: bool = false) -> void:
	b.begin_part()
	var n := pts.size()
	var left := PackedInt32Array()
	var right := PackedInt32Array()
	var positions: Array[Vector3] = []
	var nrms: Array[Vector3] = []
	for i in n:
		var sp := surface_point(pts[i].x, pts[i].y, lift)
		positions.append(sp[0])
		nrms.append(sp[1])
	for i in n:
		var tg: Vector3 = (positions[mini(i + 1, n - 1)] - positions[maxi(i - 1, 0)])
		var side := nrms[i].cross(tg).normalized()
		var w := width * 0.5
		if taper:
			w *= sin(PI * (0.08 + 0.84 * float(i) / float(maxi(n - 1, 1))))
		var wts := weights_at(pts[i].x, pts[i].y, positions[i])
		left.append(b.add_vertex(positions[i] - side * w, col, wts))
		right.append(b.add_vertex(positions[i] + side * w, col, wts))
	for i in n - 1:
		b.add_quad(right[i], left[i], left[i + 1], right[i + 1])
	b.end_part()
