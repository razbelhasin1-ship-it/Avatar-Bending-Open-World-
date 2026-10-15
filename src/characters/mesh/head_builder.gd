class_name RigHeadBuilder
extends RefCounted
## Builds the head: skin volume, ears, nose, expressive eyes (white, iris,
## pupil, highlights, lash line), brows, mouth, markings (air nomad arrow,
## face paint) and the hair styles. Eyes and mouth are bound to their own bones
## (eye_l/eye_r scale to blink, mouth scales to open).

const SK = preload("res://src/characters/rig/rig_skeleton_def.gd")


## Builds every head part. `outl` receives outlined volumes, `flat` the decals.
static func build(outl: SkinMeshBuilder, flat: SkinMeshBuilder, d: RigSkeletonDef, spec: Dictionary, hs: RigHeadShape) -> void:
	var skin: Color = spec.get("skin", Color(0.9, 0.7, 0.55))
	var head_w := SkinMeshBuilder.w1(SK.HEAD)
	var rings := 18
	var segs := 28
	RigShapes.sphere_fn(outl,
		func(th: float, ph: float) -> Vector3: return hs.point(th, ph),
		func(_th: float, _ph: float, _p: Vector3) -> Color: return skin,
		func(_th: float, _ph: float, _p: Vector3) -> Dictionary: return head_w,
		rings, segs)
	_ears(outl, d, hs, skin)
	if not spec.get("face_hidden", false):
		_nose(flat, d, hs, skin)
		_eyes(flat, d, hs, spec)
		_brows(flat, d, hs, spec)
		_mouth(flat, d, hs, spec)
	if spec.get("arrow_tattoo", false):
		_arrow_tattoo(flat, hs, spec.get("tattoo_color", Color(0.16, 0.42, 0.8)), spec.get("hair_style", "bald") == "bald")
	if spec.has("face_paint"):
		_face_paint(flat, hs, spec["face_paint"])
	var beard: String = spec.get("beard", "")
	if beard != "":
		_beard(outl, flat, d, hs, spec, beard)


static func _eye_center(hs: RigHeadShape, d: RigSkeletonDef, side: int) -> Vector2:
	# Returns (theta, phi) of the eye center.
	var head_h: float = d.p["head_h"]
	var ph := hs.phi_at_height(float(d.p["eye_y"]))
	var th := SK.SIDE_SIGN[side] * (0.34 + 0.02 * (1.0 - float(d.p["head_w"]))) * (0.115 / maxf(hs.r_face / head_h * 0.115 / 0.4, 0.05)) * 0.4 / 0.115
	return Vector2(th, ph)


static func _ears(b: SkinMeshBuilder, d: RigSkeletonDef, hs: RigHeadShape, skin: Color) -> void:
	var head_h: float = d.p["head_h"]
	var y := float(d.p["eye_y"]) - head_h * 0.06
	for side in 2:
		var s := SK.SIDE_SIGN[side]
		var ph := hs.phi_at_height(y, s * PI * 0.5)
		var base := hs.point(s * PI * 0.53, ph)
		var c := base + Vector3(s * head_h * 0.012, 0, head_h * 0.01)
		var bas := RigShapes.axes(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(0.022, 0.07, 0.045) * head_h)
		bas = Basis(Vector3.UP, s * 0.25) * Basis(Vector3.FORWARD, -s * 0.12) * bas
		RigShapes.ellipsoid(b, c, bas, skin, SkinMeshBuilder.w1(SK.HEAD), 6, 10)


static func _nose(b: SkinMeshBuilder, d: RigSkeletonDef, hs: RigHeadShape, skin: Color) -> void:
	var head_h: float = d.p["head_h"]
	var y := float(d.p["eye_y"]) - head_h * 0.115
	var ph := hs.phi_at_height(y)
	var sp := hs.point(0.0, ph)
	var n := hs.normal(0.0, ph)
	var k := 1.0 if d.p["age"] != "child" else 0.75
	var c := sp + n * head_h * 0.004 + Vector3(0, head_h * 0.012, 0)
	var bas := RigShapes.axes(Vector3(1, 0, 0), Vector3(0, 1, 0).rotated(Vector3.RIGHT, -0.35), Vector3(0, 0, 1), Vector3(0.024, 0.055, 0.03) * head_h * k)
	RigShapes.ellipsoid(b, c, bas, skin * Color(1.0, 0.96, 0.95), SkinMeshBuilder.w1(SK.HEAD), 6, 10)


## Upper/lower lid heights for x in [-1, 1] (inner -> outer corner).
static func _lid_up(x: float, eh: float, tilt: float) -> float:
	var k := clampf(1.0 - x * x, 0.0, 1.0)
	return eh * 0.56 * pow(k, 0.62) * (1.0 - 0.12 * x) + tilt * x * eh


static func _lid_lo(x: float, eh: float, tilt: float) -> float:
	var k := clampf(1.0 - x * x, 0.0, 1.0)
	return -eh * 0.44 * pow(k, 0.85) * (1.0 + 0.1 * x) + tilt * x * eh


static func _eyes(b: SkinMeshBuilder, d: RigSkeletonDef, hs: RigHeadShape, spec: Dictionary) -> void:
	var head_h: float = d.p["head_h"]
	var es: float = float(d.p["eye_size"]) * float(spec.get("eye_scale", 1.0))
	var ew := 0.19 * head_h * es
	var round_k := 0.56 if d.p["female"] or d.p["age"] in ["child", "teen"] else 0.5
	var eh := ew * round_k
	var tilt: float = spec.get("eye_tilt", 0.06 if d.p["female"] else 0.03)
	var white := Color(0.97, 0.96, 0.94)
	var iris_c: Color = spec.get("eye_color", Color(0.32, 0.2, 0.12))
	var lash_c: Color = (spec.get("hair_color", Color(0.1, 0.08, 0.07)) as Color).darkened(0.45)
	var eye_y: float = d.p["eye_y"]
	var ph := hs.phi_at_height(eye_y)
	var sep := ew * 0.62 + head_h * 0.035
	for side in 2:
		var out := -SK.SIDE_SIGN[side]  # character right eye is on the viewer's left
		var cu := -SK.SIDE_SIGN[side] * sep
		var wbone := SkinMeshBuilder.w1(SK.EYE[side])
		var surf := func(u: float, v: float) -> Array: return hs.face_surf(0.0, ph, u, v, 0.0)
		# Eye white (almond), CCW in viewer space.
		var n := 20
		var outline := PackedVector2Array()
		for i in n + 1:
			var x := 1.0 - 2.0 * float(i) / float(n)  # outer -> inner along the top
			outline.append(Vector2(cu + out * x * ew * 0.5, _lid_up(x, eh, tilt)))
		for i in range(1, n):
			var x := -1.0 + 2.0 * float(i) / float(n)  # inner -> outer along the bottom
			outline.append(Vector2(cu + out * x * ew * 0.5, _lid_lo(x, eh, tilt)))
		if out < 0.0:
			outline.reverse()
		RigShapes.patch(b, surf, outline, 0.0016, white, wbone, 3)
		# Iris (clipped against the lids), pupil and highlights.
		var ir := eh * 0.5
		var icx := cu - out * ew * 0.04
		var icy := -eh * 0.02
		var iris := PackedVector2Array()
		var pupil := PackedVector2Array()
		for i in 20:
			var a := TAU * float(i) / 20.0
			var q := Vector2(icx + cos(a) * ir * 0.9, icy + sin(a) * ir)
			var lx := clampf((q.x - cu) / (out * ew * 0.5), -0.98, 0.98)
			q.y = clampf(q.y, _lid_lo(lx, eh, tilt) * 0.94, _lid_up(lx, eh, tilt) * 0.9)
			iris.append(q)
			var pq := Vector2(icx + cos(a) * ir * 0.42, icy + sin(a) * ir * 0.48)
			pq.y = clampf(pq.y, _lid_lo(lx, eh, tilt) * 0.9, _lid_up(lx, eh, tilt) * 0.86)
			pupil.append(pq)
		RigShapes.patch(b, surf, iris, 0.0024, iris_c, wbone, 2)
		RigShapes.patch(b, surf, pupil, 0.0030, iris_c.darkened(0.75), wbone, 1)
		var hl1 := RigShapes.ellipse2(Vector2(icx + out * ir * 0.32, icy + ir * 0.36), ir * 0.24, ir * 0.24, 10)
		RigShapes.patch(b, surf, hl1, 0.0036, Color(1, 1, 1), wbone, 1)
		var hl2 := RigShapes.ellipse2(Vector2(icx - out * ir * 0.3, icy - ir * 0.38), ir * 0.11, ir * 0.11, 8)
		RigShapes.patch(b, surf, hl2, 0.0036, Color(1, 1, 1), wbone, 1)
		# Upper lash line, thicker toward the outer corner with a small flick.
		var lo := PackedVector2Array()
		var hi := PackedVector2Array()
		var m := 16
		var flick: float = 0.22 if d.p["female"] else 0.08
		for i in m + 1:
			var x := -1.04 + 2.16 * float(i) / float(m)
			var xc := clampf(x, -1.0, 1.0)
			var y0 := _lid_up(xc, eh, tilt) - eh * 0.05
			var th := eh * (0.10 + 0.12 * smoothstep(-0.8, 0.7, x))
			if x > 1.0:
				y0 += (x - 1.0) * eh * flick * 6.0
				th *= 0.6
			lo.append(Vector2(cu + out * x * ew * 0.5, y0))
			hi.append(Vector2(cu + out * x * ew * 0.5, y0 + th))
		RigShapes.band2d(b, surf, lo, hi, 0.0040, lash_c, wbone)
		# Lower lid hint at the outer half.
		var llo := PackedVector2Array()
		var lhi := PackedVector2Array()
		for i in 7:
			var x := 0.15 + 0.85 * float(i) / 6.0
			var y0 := _lid_lo(x, eh, tilt)
			llo.append(Vector2(cu + out * x * ew * 0.5, y0 - eh * 0.06))
			lhi.append(Vector2(cu + out * x * ew * 0.5, y0 - eh * 0.06 + eh * 0.05 * sin(PI * float(i) / 6.0)))
		RigShapes.band2d(b, surf, llo, lhi, 0.0030, lash_c.lerp(Color(0.5, 0.3, 0.25), 0.4), wbone)
		# Keep the eye bone pivot at the real eye center (blink squash point).
		var ec: Array = hs.face_surf(0.0, ph, cu, 0.0, 0.0)
		d.rest_pos[SK.EYE[side]] = ec[0]


static func _brows(b: SkinMeshBuilder, d: RigSkeletonDef, hs: RigHeadShape, spec: Dictionary) -> void:
	var head_h: float = d.p["head_h"]
	var es: float = float(d.p["eye_size"]) * float(spec.get("eye_scale", 1.0))
	var ew := 0.19 * head_h * es
	var ph := hs.phi_at_height(float(d.p["eye_y"]))
	var sep := ew * 0.62 + head_h * 0.035
	var col: Color = spec.get("brow_color", (spec.get("hair_color", Color(0.12, 0.09, 0.08)) as Color).darkened(0.2))
	var thick: float = head_h * (0.016 if d.p["female"] else 0.024) * float(spec.get("brow_scale", 1.0))
	var raise: float = ew * (0.62 if d.p["female"] else 0.55)
	var angle: float = spec.get("brow_angle", 0.0)
	for side in 2:
		var out := -SK.SIDE_SIGN[side]
		var cu := -SK.SIDE_SIGN[side] * sep
		var surf := func(u: float, v: float) -> Array: return hs.face_surf(0.0, ph, u, v, 0.0)
		var lo := PackedVector2Array()
		var hi := PackedVector2Array()
		var n := 10
		for i in n + 1:
			var x := -0.95 + 2.05 * float(i) / float(n)
			var arch := 0.18 * ew * (1.0 - pow((x - 0.15) / 1.1, 2.0))
			var y0 := raise + arch + angle * x * ew * 0.3
			var t := thick * (1.0 - 0.55 * smoothstep(-0.2, 1.1, x)) * (0.7 + 0.3 * smoothstep(-1.0, -0.6, x))
			lo.append(Vector2(cu + out * x * ew * 0.5, y0 - t * 0.5))
			hi.append(Vector2(cu + out * x * ew * 0.5, y0 + t * 0.5))
		RigShapes.band2d(b, surf, lo, hi, 0.0022, col, SkinMeshBuilder.w1(SK.HEAD))


static func _mouth(b: SkinMeshBuilder, d: RigSkeletonDef, hs: RigHeadShape, spec: Dictionary) -> void:
	var head_h: float = d.p["head_h"]
	var my := d.rest_pos[SK.MOUTH].y
	var ph := hs.phi_at_height(my)
	var surf := func(u: float, v: float) -> Array: return hs.face_surf(0.0, ph, u, v, 0.0)
	var mw := head_h * (0.085 if d.p["female"] else 0.095)
	var col := Color(0.36, 0.14, 0.12)
	var smile: float = spec.get("smile", 0.15)
	var lo := PackedVector2Array()
	var hi := PackedVector2Array()
	var n := 10
	for i in n + 1:
		var x := -1.0 + 2.0 * float(i) / float(n)
		var y0 := smile * head_h * 0.02 * x * x
		var t := head_h * 0.0075 * (1.0 - 0.6 * x * x)
		lo.append(Vector2(x * mw * 0.5, y0 - t))
		hi.append(Vector2(x * mw * 0.5, y0 + t * 0.6))
	RigShapes.band2d(b, surf, lo, hi, 0.0018, col, SkinMeshBuilder.w1(SK.MOUTH))
	if d.p["female"]:
		var llo := PackedVector2Array()
		var lhi := PackedVector2Array()
		for i in 7:
			var x := -0.6 + 1.2 * float(i) / 6.0
			llo.append(Vector2(x * mw * 0.5, -head_h * 0.012 - head_h * 0.008 * (1.0 - x * x)))
			lhi.append(Vector2(x * mw * 0.5, -head_h * 0.010))
		RigShapes.band2d(b, surf, llo, lhi, 0.0012, (spec.get("skin", Color.WHITE) as Color).lerp(Color(0.8, 0.35, 0.35), 0.35), SkinMeshBuilder.w1(SK.MOUTH))
	d.rest_pos[SK.MOUTH] = (hs.face_surf(0.0, ph, 0.0, 0.0, 0.0)[0] as Vector3)


## Air nomad arrow: a stripe from the nape over the crown ending in an arrowhead
## pointing down to the brow.
static func _arrow_tattoo(b: SkinMeshBuilder, hs: RigHeadShape, col: Color, bald: bool) -> void:
	var w := SkinMeshBuilder.w1(SK.HEAD)
	var width := hs.hh * 0.18
	var lift := 0.0012 if bald else 0.0
	var ph_tip := hs.phi_at_height(hs.c.y + hs.hh * 0.15)
	var lo := PackedVector2Array()
	var hi := PackedVector2Array()
	# Stripe in (theta, phi): run from behind (phi increasing past the crown) to the forehead.
	var n := 22
	for i in n + 1:
		var f := float(i) / float(n)
		var ph := lerpf(-1.75, ph_tip - 0.22, f)
		lo.append(Vector2(-width * 0.5, ph))
		hi.append(Vector2(width * 0.5, ph))
	var surf := func(u: float, phv: float) -> Array:
		var th := -u / hs.r_face
		var p := phv
		if p < 0.0:
			p = -p
			th = PI - th
		var nn := hs.normal(th, p)
		return [hs.point(th, p), nn]
	b.begin_part()
	var a := PackedInt32Array()
	var c := PackedInt32Array()
	for i in lo.size():
		var s0: Array = surf.call(lo[i].x, lo[i].y)
		var s1: Array = surf.call(hi[i].x, hi[i].y)
		a.append(b.add_vertex((s0[0] as Vector3) + (s0[1] as Vector3) * (lift + 0.0015), col, w))
		c.append(b.add_vertex((s1[0] as Vector3) + (s1[1] as Vector3) * (lift + 0.0015), col, w))
	for i in lo.size() - 1:
		b.add_quad(a[i], a[i + 1], c[i + 1], c[i])
	b.end_part()
	# Arrowhead triangle pointing down onto the forehead.
	var ph0 := ph_tip - 0.28
	var surf2 := func(u: float, v: float) -> Array: return hs.face_surf(0.0, ph0, u, v, 0.0)
	var tri := PackedVector2Array([Vector2(width * 1.35, 0.0), Vector2(0.0, -hs.hh * 0.32), Vector2(-width * 1.35, 0.0)])
	tri.reverse()
	var tri2 := PackedVector2Array([Vector2(width * 1.35, 0.0), Vector2(-width * 1.35, 0.0), Vector2(0.0, -hs.hh * 0.32)])
	RigShapes.patch(b, surf2, tri2, lift + 0.0018, col, w, 2)


static func _face_paint(b: SkinMeshBuilder, hs: RigHeadShape, paint: Dictionary) -> void:
	var col: Color = paint.get("color", Color(0.92, 0.93, 0.95))
	var w := SkinMeshBuilder.w1(SK.HEAD)
	var eye_ph := hs.phi_at_height(hs.c.y - hs.hh * 0.18)
	var surf := func(u: float, v: float) -> Array: return hs.face_surf(0.0, eye_ph, u, v, 0.0)
	match String(paint.get("style", "warrior")):
		"warrior":
			# White mask band across the eyes with dark lower edge (wolf-warrior style).
			var lo := PackedVector2Array()
			var hi := PackedVector2Array()
			for i in 17:
				var x := -1.0 + 2.0 * float(i) / 16.0
				var u := x * hs.hw * 1.05
				lo.append(Vector2(u, -hs.hh * (0.16 + 0.1 * absf(x))))
				hi.append(Vector2(u, hs.hh * (0.22 - 0.06 * absf(x))))
			RigShapes.band2d(b, surf, lo, hi, 0.0010, col, w)
		_:
			pass


static func _beard(outl: SkinMeshBuilder, flat: SkinMeshBuilder, d: RigSkeletonDef, hs: RigHeadShape, spec: Dictionary, style: String) -> void:
	var head_h: float = d.p["head_h"]
	var col: Color = spec.get("beard_color", spec.get("hair_color", Color(0.8, 0.8, 0.8)))
	var w := SkinMeshBuilder.w1(SK.HEAD)
	var chin_ph := hs.phi_at_height(float(d.p["chin_y"]) + head_h * 0.05)
	var cp := hs.point(0.0, chin_ph)
	if style == "long" or style == "goatee":
		var length := head_h * (0.42 if style == "long" else 0.2)
		var top := cp + Vector3(0, head_h * 0.06, -head_h * 0.01)
		var bot := cp + Vector3(0, -length, -head_h * 0.07)
		var wfn := func(_t: float, _a: float, _p: Vector3) -> Dictionary: return w
		var l := RigLoft.create(PackedVector3Array([top, bot]), Vector3(0, 0, -1), wfn)
		var bw := head_h * (0.22 if style == "long" else 0.1)
		l.key(0.0, bw, head_h * 0.07, head_h * 0.06)
		l.key(0.35, bw * 0.9, head_h * 0.08, head_h * 0.07)
		l.key(1.0, bw * 0.12, head_h * 0.03, head_h * 0.02)
		l.default_color = col
		l.emit(outl, 8, 12, [], true, true)
	# Mustache: two drooping tapered strips above the mouth.
	var mph := hs.phi_at_height(d.rest_pos[SK.MOUTH].y + head_h * 0.035)
	var surf := func(u: float, v: float) -> Array: return hs.face_surf(0.0, mph, u, v, 0.0)
	for s: float in [-1.0, 1.0]:
		var lo := PackedVector2Array()
		var hi := PackedVector2Array()
		for i in 9:
			var x := float(i) / 8.0
			var u := s * x * head_h * 0.11
			var y := -x * x * head_h * 0.06
			var t := head_h * 0.022 * (1.0 - x * 0.7)
			lo.append(Vector2(u, y - t * 0.5))
			hi.append(Vector2(u, y + t * 0.5))
		if s < 0.0:
			lo.reverse()
			hi.reverse()
		RigShapes.band2d(flat, surf, lo, hi, 0.004, col, w)
