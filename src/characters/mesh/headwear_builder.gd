class_name RigHeadwearBuilder
extends RefCounted
## Hats, helmets, hoods and headbands. All pieces are rigidly bound to the
## head (or neck/upper chest for the hood) and placed with RigHeadShape.

const SK = preload("res://src/characters/rig/rig_skeleton_def.gd")


static func build_piece(outl: SkinMeshBuilder, flat: SkinMeshBuilder, d: RigSkeletonDef, pc: Dictionary, ctx: Dictionary) -> void:
	var hs: RigHeadShape = ctx["head"]
	match String(pc.get("type", "")):
		"hat_cone":
			_hat_cone(outl, d, hs, pc)
		"helmet_fire":
			_helmet_fire(outl, flat, d, hs, pc)
		"helmet_wolf":
			_helmet_wolf(outl, flat, d, hs, pc)
		"helmet_round":
			_helmet_round(outl, d, hs, pc)
		"hood_back":
			_hood_back(outl, d, pc)
		"headband":
			_headband(outl, hs, pc)
		_:
			push_warning("RigGarmentBuilder: unknown piece type '%s'" % pc.get("type", ""))


## Grid patch on the head between theta [th0, th1] and phi [ph0, ph1].
static func head_shell(b: SkinMeshBuilder, hs: RigHeadShape, th0: float, th1: float, ph0: float, ph1: float, lift: float, col_fn: Callable, w: Dictionary, cols: int = 16, rows: int = 8) -> void:
	b.begin_part()
	var closed := th1 - th0 >= TAU - 0.001
	var grid: Array = []
	for r in rows + 1:
		var ph := lerpf(ph0, ph1, float(r) / float(rows))
		var row := PackedInt32Array()
		var count := cols if closed else cols + 1
		for c in count:
			var th := lerpf(th0, th1, float(c) / float(cols))
			var pos := hs.point(th, ph, lift)
			row.append(b.add_vertex(pos, col_fn.call(th, ph), w))
		grid.append(row)
	b.add_grid(grid, closed)
	b.end_part()


## Conical straw/soldier hat. Fields: radius, height (fraction of body
## height), color, under, band (Color), tilt (radians, forward).
static func _hat_cone(b: SkinMeshBuilder, d: RigSkeletonDef, hs: RigHeadShape, pc: Dictionary) -> void:
	var h: float = d.p["height"]
	var head_h: float = d.p["head_h"]
	var r: float = float(pc.get("radius", 0.15)) * h
	var height: float = float(pc.get("height", 0.08)) * h
	var col: Color = pc.get("color", Color(0.8, 0.7, 0.45))
	var brim_y: float = float(d.p["crown_y"]) - head_h * float(pc.get("sit", 0.2))
	var tilt: float = pc.get("tilt", 0.0)
	var w := SkinMeshBuilder.w1(SK.HEAD)
	var base := Vector3(hs.c.x, brim_y, hs.c.z + head_h * 0.02)
	var axis := Vector3.UP.rotated(Vector3.RIGHT, -tilt)
	var apex := base + axis * height
	var wfn := func(_t: float, _a: float, _p: Vector3) -> Dictionary: return w
	var l := RigLoft.create(PackedVector3Array([base, apex]), Vector3(0, 0, -1), wfn)
	l.key(0.0, r, r)
	l.key(0.08, r * 0.9, r * 0.9)
	l.key(1.0, r * 0.02, r * 0.02)
	l.default_color = col
	var bands: Array = []
	if pc.has("rim"):
		bands = [{"t0": 0.0, "t1": 0.05, "color": pc["rim"], "inflate": 0.0}, {"t0": 0.05, "t1": 1.0, "color": col, "inflate": 0.0}]
	l.emit(b, 10, 28, bands)
	l.flip = true
	l.emit(b, 6, 28, [{"t0": 0.0, "t1": 1.0, "color": pc.get("under", col.darkened(0.45)), "inflate": -0.004 * h}])
	if pc.has("band"):
		var bc: Color = pc["band"]
		var y0 := brim_y - head_h * 0.02
		var bl := RigLoft.create(PackedVector3Array([Vector3(hs.c.x, y0 - head_h * 0.08, hs.c.z), Vector3(hs.c.x, y0 + head_h * 0.06, hs.c.z)]), Vector3(0, 0, -1), wfn)
		var hw := hs.hw * 1.06
		bl.key(0.0, hw, hs.hdf * 1.03, hs.hdb * 1.02)
		bl.key(1.0, hw * 0.98, hs.hdf * 1.0, hs.hdb * 0.99)
		bl.default_color = bc
		bl.emit(b, 2, 24, [], false, false)
	if pc.has("ornament"):
		var oc: Color = pc["ornament"]
		var op := hs.point(0.0, 0.95, head_h * 0.06)
		RigShapes.ellipsoid(b, op + Vector3(0, -head_h * 0.02, 0), RigShapes.axes(Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.05, 0.05, 0.02) * head_h), oc, w, 5, 10)


## Fire Nation soldier helmet: dark skull cap with crest + skull-like face mask.
static func _helmet_fire(outl: SkinMeshBuilder, flat: SkinMeshBuilder, d: RigSkeletonDef, hs: RigHeadShape, pc: Dictionary) -> void:
	var h: float = d.p["height"]
	var head_h: float = d.p["head_h"]
	var col: Color = pc.get("color", Color(0.32, 0.08, 0.07))
	var mask: Color = pc.get("mask", Color(0.16, 0.15, 0.16))
	var trim: Color = pc.get("trim", Color(0.12, 0.1, 0.1))
	var w := SkinMeshBuilder.w1(SK.HEAD)
	var lift := 0.012 * h
	# Cap: full coverage down past the ears, with a flared neck guard.
	head_shell(outl, hs, 0.0, TAU, 0.0, 1.0, lift, func(_t: float, _p: float) -> Color: return col, w, 28, 6)
	head_shell(outl, hs, 0.0, TAU, 1.0, 1.32, lift, func(th: float, _p: float) -> Color: return trim if absf(wrapf(th, -PI, PI)) < 0.9 else col, w, 28, 3)
	head_shell(outl, hs, 1.2, TAU - 1.2, 1.32, 2.25, lift * 1.4, func(_t: float, ph: float) -> Color: return trim if ph > 2.1 else col, w, 18, 6)
	# Crest along the top.
	var cr := hs.point(0.0, 0.1, lift + head_h * 0.04)
	RigShapes.ellipsoid(outl, cr + Vector3(0, 0, head_h * 0.12), RigShapes.axes(Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.025, 0.09, 0.3) * head_h), trim, w, 6, 12)
	# Face mask: grid over the face below the brow.
	head_shell(outl, hs, -1.3, 1.3, 1.0, PI * 0.93, 0.0105 * h, func(_t: float, _p: float) -> Color: return mask, w, 18, 12)
	var eye_ph := hs.phi_at_height(float(d.p["eye_y"]))
	var surf := func(u: float, v: float) -> Array: return hs.face_surf(0.0, eye_ph, u, v, 0.0)
	var sep := head_h * 0.135
	for s: float in [-1.0, 1.0]:
		var hole := RigShapes.ellipse2(Vector2(s * sep, head_h * 0.005), head_h * 0.075, head_h * 0.042, 14)
		RigShapes.patch(flat, surf, hole, 0.0125 * h, Color(0.02, 0.02, 0.02), w, 2)
		# Cheekbone ridges.
		var lo := PackedVector2Array()
		var hi := PackedVector2Array()
		for i in 7:
			var f := float(i) / 6.0
			var u := s * lerpf(head_h * 0.05, head_h * 0.2, f)
			lo.append(Vector2(u, -head_h * (0.12 + 0.05 * f)))
			hi.append(Vector2(u, -head_h * (0.1 + 0.05 * f)))
		if s < 0.0:
			lo.reverse()
			hi.reverse()
		RigShapes.band2d(flat, surf, lo, hi, 0.0125 * h, mask.lightened(0.25), w)
	RigShapes.patch(flat, surf, PackedVector2Array([Vector2(-head_h * 0.025, -head_h * 0.07), Vector2(0, -head_h * 0.13), Vector2(head_h * 0.025, -head_h * 0.07)]), 0.0125 * h, Color(0.02, 0.02, 0.02), w, 1)
	var teeth_lo := PackedVector2Array()
	var teeth_hi := PackedVector2Array()
	for i in 9:
		var x := -1.0 + 2.0 * float(i) / 8.0
		teeth_lo.append(Vector2(x * head_h * 0.08, -head_h * 0.235))
		teeth_hi.append(Vector2(x * head_h * 0.08, -head_h * (0.205 + 0.01 * float(i % 2))))
	RigShapes.band2d(flat, surf, teeth_lo, teeth_hi, 0.0125 * h, mask.lightened(0.35), w)


## Water tribe wolf helmet: pale wolf head with muzzle and ears over the brow.
static func _helmet_wolf(outl: SkinMeshBuilder, flat: SkinMeshBuilder, d: RigSkeletonDef, hs: RigHeadShape, pc: Dictionary) -> void:
	var h: float = d.p["height"]
	var head_h: float = d.p["head_h"]
	var col: Color = pc.get("color", Color(0.86, 0.87, 0.9))
	var dark: Color = pc.get("dark", Color(0.32, 0.35, 0.42))
	var w := SkinMeshBuilder.w1(SK.HEAD)
	var lift := 0.012 * h
	head_shell(outl, hs, 0.0, TAU, 0.0, 1.0, lift, func(th: float, _p: float) -> Color: return dark if absf(wrapf(th, -PI, PI)) > 2.4 else col, w, 26, 6)
	head_shell(outl, hs, 0.0, TAU, 1.0, 1.45, lift, func(th: float, ph: float) -> Color: return dark if ph > 1.35 and absf(wrapf(th, -PI, PI)) < 1.2 else col, w, 26, 4)
	# Muzzle over the forehead.
	var m0 := hs.point(0.0, 1.1, lift + head_h * 0.02)
	var mb := RigShapes.axes(Vector3.RIGHT, Vector3(0, 1, 0.3), Vector3(0, -0.3, 1), Vector3(0.1, 0.07, 0.17) * head_h)
	RigShapes.ellipsoid(outl, m0 + Vector3(0, head_h * 0.03, -head_h * 0.08), mb, col, w, 7, 12)
	RigShapes.ellipsoid(outl, m0 + Vector3(0, head_h * 0.02, -head_h * 0.24), Basis().scaled(Vector3(0.035, 0.03, 0.03) * head_h), dark, w, 4, 8)
	for s: float in [-1.0, 1.0]:
		var ec := hs.point(s * 0.7, 0.55, lift + head_h * 0.05)
		var eb := RigShapes.axes(Vector3(1, 0, 0), Vector3(s * 0.3, 1, 0.2), Vector3(0, 0, 1), Vector3(0.05, 0.11, 0.03) * head_h)
		RigShapes.ellipsoid(outl, ec + Vector3(0, head_h * 0.05, 0), eb, col, w, 5, 8)
		var eye := hs.point(s * 0.28, 1.0, lift + head_h * 0.045)
		RigShapes.ellipsoid(flat, eye, Basis().scaled(Vector3(0.026, 0.014, 0.012) * head_h), dark, w, 4, 8)


## Round soldier/guard helmet with a short brim. Fields: color, trim.
static func _helmet_round(b: SkinMeshBuilder, d: RigSkeletonDef, hs: RigHeadShape, pc: Dictionary) -> void:
	var h: float = d.p["height"]
	var col: Color = pc.get("color", Color(0.35, 0.45, 0.3))
	var trim: Color = pc.get("trim", col.darkened(0.35))
	var w := SkinMeshBuilder.w1(SK.HEAD)
	head_shell(b, hs, 0.0, TAU, 0.0, 1.15, 0.012 * h, func(_t: float, ph: float) -> Color: return trim if ph > 1.05 else col, w, 26, 6)
	head_shell(b, hs, -1.6, 1.6, 1.15, 1.3, 0.024 * h, func(_t: float, _p: float) -> Color: return trim, w, 16, 2)
	var top := hs.point(0.0, 0.0, 0.02 * h)
	RigShapes.ellipsoid(b, top, Basis().scaled(Vector3.ONE * 0.012 * h), trim, w, 4, 8)


## Bunched parka hood resting behind the neck. Fields: color.
static func _hood_back(b: SkinMeshBuilder, d: RigSkeletonDef, pc: Dictionary) -> void:
	var h: float = d.p["height"]
	var col: Color = pc.get("color", Color(0.2, 0.38, 0.68))
	var c := Vector3(0, float(d.p["neck_base_y"]) + 0.004 * h, float(d.p["chest_d"]) * h * 0.95)
	var bas := RigShapes.axes(Vector3.RIGHT, Vector3(0, 1, 0.4), Vector3(0, -0.4, 1), Vector3(0.085, 0.05, 0.045) * h)
	RigShapes.ellipsoid(b, c, bas, col, {SK.UPPER_CHEST: 0.7, SK.NECK: 0.3}, 7, 14)


static func _headband(b: SkinMeshBuilder, hs: RigHeadShape, pc: Dictionary) -> void:
	var col: Color = pc.get("color", Color(0.6, 0.15, 0.12))
	var ph: float = pc.get("phi", 1.12)
	head_shell(b, hs, 0.0, TAU, ph, ph + 0.16, 0.006, func(_t: float, _p: float) -> Color: return col, SkinMeshBuilder.w1(SK.HEAD), 28, 1)
