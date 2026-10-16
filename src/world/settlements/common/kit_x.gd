class_name KitX
extends RefCounted
## Extra BuildingKit pieces shared by the settlement builders (thread-safe, current kit frame):
## emblems (Water Tribe moon + waves, Air Nomad swirl), icicles, rounded merlons, block joints,
## arched doorways with cloth curtains, ring walls and helpers to convert world points into a
## piece frame.


## World point -> piece-local point (piece "pos"/"yaw").
static func local(piece: Dictionary, world: Vector3) -> Vector3:
	return (world - (piece["pos"] as Vector3)).rotated(Vector3.UP, -float(piece["yaw"]))


## Water Tribe emblem relief in the local XY plane facing -Z at `c` (size = overall height):
## a crescent moon over three stacked wave curls.
static func emblem_water(kit: BuildingKit, c: Vector3, size: float, role: Variant = &"trim", depth: float = 0.12) -> void:
	var g := kit.g()
	var col := kit.col(role, false)
	var segs := 10 if kit.lod == 0 else 5
	# crescent: outer arc minus inner arc, approximated by a curved tube of decreasing radius
	var moon := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in segs + 1:
		var t := float(i) / segs
		var a := lerpf(PI * 0.15, PI * 1.85, t)
		moon.append(c + Vector3(cos(a + PI * 0.5) * size * 0.22, size * 0.28 + sin(a + PI * 0.5) * size * 0.22, -depth))
		radii.append(size * 0.055 * sin(t * PI) + 0.01)
	g.tube(moon, radii, 5, col)
	# three wave curls under the moon
	for k in 3:
		var y := -size * 0.08 - k * size * 0.13
		var w := size * (0.62 - k * 0.12)
		var line := PackedVector3Array()
		var rr := PackedFloat32Array()
		for i in segs + 1:
			var t := float(i) / segs
			line.append(c + Vector3((t - 0.5) * w, y + sin(t * TAU * 1.5) * size * 0.035, -depth))
			rr.append(size * 0.03)
		g.tube(line, rr, 4, col)


## Air Nomad swirl relief (three spiral arms around a hub) in the local XY plane facing -Z.
static func emblem_air(kit: BuildingKit, c: Vector3, size: float, role: Variant = &"trim", depth: float = 0.12) -> void:
	var g := kit.g()
	var col := kit.col(role, false)
	var segs := 12 if kit.lod == 0 else 6
	for arm in 3:
		var a0 := TAU * arm / 3.0
		var line := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in segs + 1:
			var t := float(i) / segs
			var rad := size * (0.06 + 0.42 * t)
			var a := a0 + t * PI * 1.25
			line.append(c + Vector3(cos(a) * rad, sin(a) * rad, -depth))
			radii.append(size * (0.025 + 0.05 * t * (1.0 - t * 0.6)))
		g.tube(line, radii, 5, col)
	g.cylinder(c + Vector3(0, 0, -depth - 0.04), c + Vector3(0, 0, -depth + 0.06), size * 0.1, size * 0.1, 8, col, 2)


## Flat ribbon lying on the plane y = pts.y (an inlay): quads facing up along the polyline,
## `widths` per point (full width). No collision (it sits on a collided floor).
static func ribbon(kit: BuildingKit, pts: PackedVector3Array, widths: PackedFloat32Array, col: Color) -> void:
	var g := kit.g()
	var n := pts.size()
	if n < 2:
		return
	var base := g.vertex_count()
	for i in n:
		var d := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		d.y = 0.0
		var side := Vector3(-d.z, 0.0, d.x).normalized() * widths[i] * 0.5
		g.vertex(pts[i] - side, Vector3.UP, col)
		g.vertex(pts[i] + side, Vector3.UP, col)
	for i in n - 1:
		var k := base + i * 2
		# counter-clockwise seen from above: (left_i, left_i+1, right_i+1, right_i) depends on the side
		var a := g.verts[k]
		var b := g.verts[k + 2]
		var c := g.verts[k + 3]
		if (b - a).cross(c - a).y >= 0.0:
			g.quad(k, k + 2, k + 3, k + 1)
		else:
			g.quad(k, k + 1, k + 3, k + 2)


## The Air Nomad swirl as a flat inlay on the ground at local `c` (three tapering spiral arms
## around a hub), `size` across.
static func swirl_inlay(kit: BuildingKit, c: Vector3, size: float, col: Variant) -> void:
	var cc := kit.col(col, false)
	var segs := 14 if kit.lod == 0 else 7
	for arm in 3:
		var a0 := TAU * arm / 3.0
		var pts := PackedVector3Array()
		var ws := PackedFloat32Array()
		for i in segs + 1:
			var t := float(i) / segs
			var rad := size * (0.05 + 0.42 * t)
			var a := a0 + t * PI * 1.25
			pts.append(c + Vector3(cos(a) * rad, 0.0, sin(a) * rad))
			ws.append(size * (0.05 + 0.11 * t * (1.0 - t * 0.6)))
		ribbon(kit, pts, ws, cc)
	var hub := PackedVector2Array()
	for i in 10:
		var a := TAU * i / 10.0
		hub.append(Vector2(c.x + cos(a) * size * 0.09, c.z + sin(a) * size * 0.09))
	kit.g().extrude(hub, c.y, c.y + 0.005, cc, 2)


## The Water Tribe moon over three waves as a flat inlay on the ground at local `c` (the moon
## towards local -Z), `size` across.
static func water_inlay(kit: BuildingKit, c: Vector3, size: float, col: Variant) -> void:
	var cc := kit.col(col, false)
	var segs := 12 if kit.lod == 0 else 6
	var moon := PackedVector3Array()
	var mw := PackedFloat32Array()
	for i in segs + 1:
		var t := float(i) / segs
		var a := lerpf(PI * 0.15, PI * 1.85, t) + PI * 0.5
		moon.append(c + Vector3(cos(a) * size * 0.22, 0.0, -size * 0.28 - sin(a) * size * 0.22))
		mw.append(size * 0.11 * sin(t * PI) + 0.02)
	ribbon(kit, moon, mw, cc)
	for k in 3:
		var z := size * 0.08 + k * size * 0.13
		var w := size * (0.62 - k * 0.12)
		var line := PackedVector3Array()
		var lw := PackedFloat32Array()
		for i in segs + 1:
			var t := float(i) / segs
			line.append(c + Vector3((t - 0.5) * w, 0.0, z + sin(t * TAU * 1.5) * size * 0.035))
			lw.append(size * 0.06)
		ribbon(kit, line, lw, cc)


## Icicles hanging under an edge from a to b (local), count per metre. LOD0 only.
static func icicles(kit: BuildingKit, a: Vector3, b: Vector3, per_m: float = 1.6, max_len: float = 0.9) -> void:
	if kit.lod > 0:
		return
	var n := int(a.distance_to(b) * per_m)
	var ice := kit.col(&"ice", false)
	var g := kit.g(&"ice")
	for i in n:
		var p := a.lerp(b, (i + kit.rng.randf()) / maxf(n, 1))
		var l := kit.rng.randf_range(0.15, max_len)
		g.cone(p, p - Vector3(0, l, 0), kit.rng.randf_range(0.04, 0.09), 4, ice, false)


## Row of rounded merlons on top of a wall edge from a to b (base points on the wall top).
static func merlons(kit: BuildingKit, a: Vector3, b: Vector3, thick: float, h: float = 0.7, width: float = 0.9,
		gap: float = 0.55, role: Variant = &"wall", collide: bool = true) -> void:
	var length := a.distance_to(b)
	if length < width or kit.lod >= 2:
		return
	var x := (b - a) / length
	var n := int(floor((length + gap) / (width + gap)))
	var used := n * width + (n - 1) * gap
	var start := (length - used) * 0.5
	var basis := Basis(x, Vector3.UP, x.cross(Vector3.UP).normalized())
	for i in n:
		var cx := start + i * (width + gap) + width * 0.5
		var p := a + x * cx
		kit.box_t(Transform3D(basis, p + Vector3(0, h * 0.4, 0)), Vector3(width, h * 0.8, thick), role, false)
		if kit.lod == 0:
			# rounded cap: a short horizontal half-drum across the wall
			var hb := p + Vector3(0, h * 0.8, 0)
			var side := basis.z * thick * 0.5
			kit.g().cylinder(hb - side, hb + side, width * 0.5, width * 0.5, 8, kit.col(role), 3, true)
	if collide:
		var mid := (a + b) * 0.5 + Vector3(0, h * 0.5, 0)
		kit.boxes.append([kit.xform * Transform3D(basis, mid), Vector3(length, h, thick)])


## Horizontal block-joint grooves on a flat face (local): face from x0..x1 at depth z (facing -Z
## when `out` = -1, +Z when +1), rows every `course` metres from y0 to y1. LOD0 only.
static func joints(kit: BuildingKit, x0: float, x1: float, y0: float, y1: float, z: float, course: float = 1.2,
		out: float = -1.0, role: Variant = &"wall_alt") -> void:
	if kit.lod > 0:
		return
	var y := y0 + course
	var row := 0
	while y < y1 - 0.2:
		kit.box(Vector3((x0 + x1) * 0.5, y, z + out * 0.015), Vector3(x1 - x0, 0.06, 0.04), role, false)
		# staggered vertical joints
		var step := course * 1.6
		var xx := x0 + (step * 0.5 if row % 2 == 1 else step)
		while xx < x1 - 0.3:
			kit.box(Vector3(xx, y - course * 0.5, z + out * 0.015), Vector3(0.05, course - 0.06, 0.04), role, false)
			xx += step
		y += course
		row += 1


## Arched doorway inset on a face facing -Z at local `c` (bottom centre): dark opening with an
## arch top, a frame, and a cloth curtain (LOD0). w/h = opening size.
static func doorway(kit: BuildingKit, c: Vector3, w: float = 1.3, h: float = 2.2, frame_role: Variant = &"trim",
		curtain: Variant = &"cloth", depth: float = 0.08) -> void:
	kit.box(c + Vector3(0, (h - w * 0.5) * 0.5, -depth), Vector3(w, h - w * 0.5, 0.06), &"window", false)
	if kit.lod < 2:
		var segs := 6 if kit.lod == 0 else 3
		var g := kit.g()
		var dark := kit.col(&"window", false)
		var fr := kit.col(frame_role)
		var y0 := h - w * 0.5
		for i in segs:
			var a0 := PI * float(i) / segs
			var a1 := PI * float(i + 1) / segs
			var p0 := c + Vector3(cos(a0) * w * 0.5, y0 + sin(a0) * w * 0.5, -depth - 0.03)
			var p1 := c + Vector3(cos(a1) * w * 0.5, y0 + sin(a1) * w * 0.5, -depth - 0.03)
			g.flat_tri(c + Vector3(0, y0, -depth - 0.03), p1, p0, dark)
			kit.beam(p0 + Vector3(0, 0, -0.04), p1 + Vector3(0, 0, -0.04), 0.16, 0.16, frame_role)
		for sx: float in [-1.0, 1.0]:
			kit.box(c + Vector3(sx * (w * 0.5 + 0.08), y0 * 0.5, -depth - 0.06), Vector3(0.16, y0, 0.16), frame_role, false)
		if kit.lod == 0 and curtain != null:
			kit.banner(Transform3D(Basis(), c + Vector3(0, y0 + 0.05, -depth - 0.1)), w * 0.92, y0 * 0.82,
					{"role": curtain, "alt_role": &"cloth_alt", "rod": true, "tail": false})


## Records a night glow point at local `pos` (no light): the settlement providers draw every
## glow and every non-interior light record of a cell as a night glow sprite (SettlementFx).
## Recipes call it where they draw a lit window or an unlit lamp, so glows sit exactly on them.
static func glow(kit: BuildingKit, pos: Vector3, color: Color = Color(1.0, 0.70, 0.38), size: float = 1.0) -> void:
	kit.lights.append({"position": kit.xform * pos, "color": color, "range": 0.0, "energy": 0.0, "glow_only": true, "glow": size})


## BuildingKit.lantern that also records a night glow when the lantern has no light
## (opts.light = false), at the spot where its light would sit.
static func lantern(kit: BuildingKit, pos: Vector3, opts: Dictionary = {}) -> void:
	kit.lantern(pos, opts)
	if opts.get("light", true):
		return
	var style: StringName = opts.get("style", &"paper")
	var lc := pos
	var col: Color = opts.get("color", Color(1.0, 0.80, 0.52))
	match style:
		&"post", &"stone":
			lc = pos + Vector3(0, float(opts.get("height", 1.7)) * 0.82, 0)
		&"ice":
			lc = pos + Vector3(0, float(opts.get("height", 1.6)) * 0.82, 0)
			col = opts.get("color", Color(0.7, 0.85, 1.0))
		&"wall":
			lc = pos + Vector3(0, 0.05, -0.2)
	glow(kit, lc, col, 0.8)


## Colour of a lit window pane (glow slot): a warm amber that reads as a curtained window by day
## and glows at night.
static func lit_window_color(kit: BuildingKit) -> Color:
	var g := kit.col(&"glow", false)
	return Color(g.r * 0.55, g.g * 0.42, g.b * 0.26)


## Window inset (dark with a light frame) on a face facing -Z at local `c` (centre).
static func window(kit: BuildingKit, c: Vector3, w: float = 0.7, h: float = 0.9, frame_role: Variant = &"trim",
		depth: float = 0.06, lit: bool = false) -> void:
	if lit:
		# amber by day, glowing at night (kit_glow multiplies by 0.6 by day, 2.6 at night)
		kit.g(&"glow").box(Transform3D(Basis(), c + Vector3(0, 0, -depth)), Vector3(w, h, 0.05), lit_window_color(kit))
		glow(kit, c + Vector3(0, 0, -depth - 0.15), Color(1.0, 0.70, 0.38), clampf(w * 1.2, 0.6, 1.4))
	else:
		kit.box(c + Vector3(0, 0, -depth), Vector3(w, h, 0.05), &"window", false)
	if kit.lod == 0:
		kit.box(c + Vector3(0, h * 0.5 + 0.06, -depth - 0.04), Vector3(w + 0.24, 0.12, 0.1), frame_role, false)
		kit.box(c + Vector3(0, -h * 0.5 - 0.05, -depth - 0.05), Vector3(w + 0.3, 0.1, 0.14), frame_role, false)
		if lit:
			# mullions + side jambs: a lit pane reads as a window, not a coloured patch
			kit.box(c + Vector3(0, 0, -depth - 0.04), Vector3(0.06, h, 0.04), frame_role, false)
			kit.box(c + Vector3(0, h * 0.1, -depth - 0.04), Vector3(w, 0.06, 0.04), frame_role, false)
			for sx: float in [-1.0, 1.0]:
				kit.box(c + Vector3(sx * (w * 0.5 + 0.04), 0, -depth - 0.04), Vector3(0.08, h + 0.1, 0.06), frame_role, false)


## Points along an arc of the ring layout (world space), every ~step metres, inclusive.
static func arc(L: RingLayout, r: float, b0: float, b1: float, y: float, step: float = 8.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := maxi(int(ceil(RingLayout.arc_len(b1 - b0, r) / step)), 1)
	for i in n + 1:
		var b := lerpf(b0, b1, float(i) / n)
		var p := L.xz(r, b)
		out.append(Vector3(p.x, y, p.y))
	return out


## Hanging nation banner (cloth slot, ripples in the wind): `t` origin = top centre, hangs
## along -Y facing -Z. A field colour with thin edge stripes, a pointed tail and an emblem
## sampled per vertex: &"moon" (Water Tribe crescent over waves), &"swirl" (Air Nomad ring),
## &"none". field/trim: palette roles or Colors.
static func banner(kit: BuildingKit, t: Transform3D, width: float, length: float, field: Variant = &"cloth",
		trim: Variant = &"cloth_alt", emblem: StringName = &"moon") -> void:
	kit.push(t)
	var c0 := kit.col(field, false)
	var c1 := kit.col(trim, false)
	var nx: int = [8, 3, 1][clampi(kit.lod, 0, 2)]
	var ny: int = [14, 5, 2][clampi(kit.lod, 0, 2)]
	var cb := kit.g(&"cloth")
	var base := cb.vertex_count()
	var aspect := length / maxf(width, 0.01)
	for j in ny + 1:
		var v := float(j) / ny
		for i in nx + 1:
			var u := float(i) / nx
			var px := (u - 0.5) * width
			var py := -v * length
			if j == ny:
				py -= (0.5 - absf(u - 0.5)) * width * 0.7
			var c := c0
			if kit.lod < 2:
				if absf(u - 0.5) > 0.42 or (v > 0.06 and v < 0.1) or (v > 0.84 and v < 0.88):
					c = c1
				var ex := (u - 0.5)
				var ey := (v - 0.36) * aspect
				match emblem:
					&"moon":
						var d := Vector2(ex, ey).length()
						var d2 := Vector2(ex - 0.12, ey - 0.04).length()
						if d < 0.3 and d2 > 0.24:
							c = c1
						if v > 0.6 and v < 0.66 and absf(u - 0.5) < 0.3:
							c = c1
					&"swirl":
						var d := Vector2(ex, ey).length()
						if d > 0.17 and d < 0.27:
							c = c1
					&"earth":
						# Earth Kingdom: a ring around a square (the coin seal)
						var d := Vector2(ex, ey).length()
						if (d > 0.21 and d < 0.29) or (absf(ex) < 0.1 and absf(ey) < 0.1):
							c = c1
					&"fire":
						# Fire Nation: a rising flame (round base, tapering tongue)
						var fy := ey + 0.02
						if Vector2(ex, fy - 0.1).length() < 0.15 or (fy > -0.34 and fy < 0.1 and absf(ex) < 0.15 * (fy + 0.34) / 0.44):
							c = c1
			cb.vertex(Vector3(px, py, 0), Vector3(0, 0, -1), c, Vector2(v, u))
	for j in ny:
		for i in nx:
			var k := base + j * (nx + 1) + i
			cb.quad(k, k + nx + 1, k + nx + 2, k + 1)
	if kit.lod < 2:
		kit.g().cylinder(Vector3(-width * 0.56, 0.03, 0), Vector3(width * 0.56, 0.03, 0), 0.04, 0.04, 5, kit.col(&"wood_dark"), 3)
	kit.pop()


## Inward-facing hemisphere (a domed ceiling seen from inside), radius r squashed in y.
static func inner_dome(kit: BuildingKit, c: Vector3, r: float, squash: float, col: Color) -> void:
	var g := kit.g()
	var sides := 18 if kit.lod == 0 else 10
	var rings := 6 if kit.lod == 0 else 3
	var base := g.vertex_count()
	for j in rings + 1:
		var phi := PI * 0.5 * float(j) / rings
		for i in sides + 1:
			var a := TAU * float(i % sides) / sides
			var n := Vector3(cos(a) * cos(phi), sin(phi), sin(a) * cos(phi))
			var shade := lerpf(0.8, 1.05, float(j) / rings)
			g.vertex(c + Vector3(n.x * r, n.y * r * squash, n.z * r), -n, col * shade)
	for j in rings:
		for i in sides:
			var k := base + j * (sides + 1) + i
			g.quad(k, k + 1, k + sides + 2, k + sides + 1)


## A tuft of three crossing grass blades (double-sided solid triangles) at local `p`.
static func grass_tuft(kit: BuildingKit, p: Vector3, h: float, col: Color, rng: RandomNumberGenerator) -> void:
	var g := kit.g()
	var tip := col.lightened(0.25)
	for k in 3:
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0, sin(a)) * 0.07
		var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		var top := p + Vector3(0, h * rng.randf_range(0.7, 1.1), 0) + lean
		var n := d.cross(Vector3.UP).normalized()
		var i := g.vertex(p - d, n, col)
		g.vertex(p + d, n, col)
		g.vertex(top, n, tip)
		g.tri(i, i + 1, i + 2)
		var j := g.vertex(p + d, -n, col)
		g.vertex(p - d, -n, col)
		g.vertex(top, -n, tip)
		g.tri(j, j + 1, j + 2)


## Thin string of flags/pennants between two local points (cloth slot), sagging by `sag`.
static func flag_string(kit: BuildingKit, a: Vector3, b: Vector3, sag: float, roles: Array, size: float = 0.32) -> void:
	if kit.lod > 0:
		return
	var n := maxi(int(a.distance_to(b) / (size * 1.4)), 2)
	var dir := (b - a)
	var yaw := atan2(dir.x, dir.z)
	var prev := a
	var rope := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / n
		var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		rope.append(p)
		if i > 0:
			var mid := (prev + p) * 0.5
			kit.banner(Transform3D(Basis(Vector3.UP, yaw), mid), size, size * 1.2,
					{"role": roles[i % roles.size()], "emblem": false, "rod": false, "tail": true})
		prev = p
	var radii := PackedFloat32Array()
	radii.resize(rope.size())
	radii.fill(0.015)
	kit.g().tube(rope, radii, 3, kit.col(&"wood_dark"))


## Earth Kingdom emblem relief in the local XY plane facing -Z at `c` (size = diameter): a ring
## around a square seal, the coin-like insignia of the Earth Kingdom.
static func emblem_earth(kit: BuildingKit, c: Vector3, size: float, role: Variant = &"trim_alt", depth: float = 0.12) -> void:
	var g := kit.g()
	var col := kit.col(role, false)
	var segs := 16 if kit.lod == 0 else 8
	var ring := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in segs + 1:
		var a := TAU * float(i) / segs
		ring.append(c + Vector3(cos(a) * size * 0.42, sin(a) * size * 0.42, -depth))
		radii.append(size * 0.06)
	g.tube(ring, radii, 4, col)
	kit.box(c + Vector3(0, 0, -depth), Vector3(size * 0.36, size * 0.36, 0.08), role, false)
	if kit.lod == 0:
		kit.box(c + Vector3(0, 0, -depth - 0.05), Vector3(size * 0.2, size * 0.2, 0.06), &"trim", false)


## Fire Nation emblem relief in the local XY plane facing -Z at `c` (size = height): a central
## flame tongue with two curling side flames rising from a round base.
static func emblem_fire(kit: BuildingKit, c: Vector3, size: float, role: Variant = &"trim_alt", depth: float = 0.12) -> void:
	var g := kit.g()
	var col := kit.col(role, false)
	var segs := 8 if kit.lod == 0 else 4
	for k in 3:
		var side := float(k - 1)
		var line := PackedVector3Array()
		var radii := PackedFloat32Array()
		var hgt := size * (1.0 if k == 1 else 0.62)
		for i in segs + 1:
			var t := float(i) / segs
			var x := side * size * (0.16 + 0.1 * sin(t * PI)) - side * size * 0.12 * t * t
			line.append(c + Vector3(x, -size * 0.38 + t * hgt, -depth))
			radii.append(size * (0.13 if k == 1 else 0.08) * (1.0 - t * 0.92) + 0.01)
		g.tube(line, radii, 5, col)
	g.blob(c + Vector3(0, -size * 0.32, -depth), size * 0.16, 0, col)


## Prism along local X from x0 to x1 with a cross-section `profile` of (z, y) points (any
## winding; faces point away from the profile centroid). caps: 1 = end cap at x0, 2 = at x1.
## Walls with battered faces, sloped copings, parapets. No collision (add boxes / faces).
static func prism_x(kit: BuildingKit, x0: float, x1: float, profile: PackedVector2Array, role: Variant, caps: int = 3,
		slot: StringName = &"solid") -> void:
	var g := kit.g(slot)
	var col := kit.col(role)
	var n := profile.size()
	if n < 3:
		return
	var cz := 0.0
	var cy := 0.0
	for p in profile:
		cz += p.x
		cy += p.y
	cz /= n
	cy /= n
	for i in n:
		var p := profile[i]
		var q := profile[(i + 1) % n]
		var a := Vector3(x0, p.y, p.x)
		var b := Vector3(x1, p.y, p.x)
		var c := Vector3(x1, q.y, q.x)
		var d := Vector3(x0, q.y, q.x)
		var nrm := (b - a).cross(c - a)
		var mid := Vector3(0, (p.y + q.y) * 0.5 - cy, (p.x + q.x) * 0.5 - cz)
		if nrm.dot(mid) >= 0.0:
			g.flat_quad(a, b, c, d, col)
		else:
			g.flat_quad(a, d, c, b, col)
	if caps == 0:
		return
	var tri := Geometry2D.triangulate_polygon(profile)
	for k in range(0, tri.size(), 3):
		var p0 := profile[tri[k]]
		var p1 := profile[tri[k + 1]]
		var p2 := profile[tri[k + 2]]
		for end: int in [1, 2]:
			if caps & end == 0:
				continue
			var x := x0 if end == 1 else x1
			var out := -1.0 if end == 1 else 1.0
			var a := Vector3(x, p0.y, p0.x)
			var b := Vector3(x, p1.y, p1.x)
			var c := Vector3(x, p2.y, p2.x)
			if (b - a).cross(c - a).x * out >= 0.0:
				g.flat_tri(a, b, c, col)
			else:
				g.flat_tri(a, c, b, col)
