class_name BuildingKit
extends RefCounted
## Procedural architecture kit shared by settlement builders, POI structures and props.
## Thread-safe (pure geometry: GeoBuilder arrays), so whole city cells can be built on a
## WorkerThreadPool task; `build()` returns a KitResult that is instantiated on the main thread
## (KitResult.instantiate) or merged into a streamed cell (KitResult.add_to_payload).
##
##   var kit := BuildingKit.new(NationPalette.get_palette(&"earth_kingdom"), 0, seed)
##   kit.push(Transform3D(Basis(Vector3.UP, yaw), pos))          # local frame (-Z = front)
##   kit.box(Vector3(0, 0.3, 0), Vector3(10, 0.6, 8), &"base")    # centre + size, collides
##   kit.wall(Vector3(-5, 0.6, 4), Vector3(5, 0.6, 4), 3.2, 0.4, {"openings": [{"t": 0.5, "width": 1.6, "height": 2.4}]})
##   KitRoofs.hip(kit, Vector3(0, 3.8, 0), 10.0, 8.0, 3.0)
##   kit.lantern(Vector3(2, 2.6, 4.6), {"style": &"paper"})
##   kit.pop()
##   var res := kit.build()            # KitResult (arrays, collision, lights, markers)
##   add_child(res.instantiate())       # main thread
##
## Geometry goes into material *slots* (one surface each, so a whole cell of buildings is a
## handful of draw calls): &"solid" (vertex-coloured toon + ink outline), &"glow" (emissive),
## &"cloth" (wind-animated two-sided), &"ice" (glossy toon). Colours come from *roles* of the
## NationPalette (wall, roof, trim, wood, ...) or explicit Colors. `lod` 0 = full detail, 1 =
## simplified (no small ornaments, railings as slabs, coarser roofs), 2 = silhouette (impostor for
## distant views). Collision: axis boxes (walls, floors, posts) and trimesh faces (roofs, ramps,
## bridges) in kit space. Lights are recorded (position, colour, range) and become budgeted
## OmniLight3Ds (LightBudget) on instantiation. Full reference: docs/modules/worldcontent.md.

var palette: NationPalette
var lod: int = 0
var rng: RandomNumberGenerator
var slots: Dictionary = {}               # slot -> GeoBuilder
## Collision boxes [[Transform3D, Vector3 size], ...] and trimesh faces (kit space).
var boxes: Array = []
var faces := PackedVector3Array()
## Recorded lights: {"position", "color", "range", "energy", "priority"}.
var lights: Array[Dictionary] = []
## Named points/transforms (doors, interior centres, NPC spots) in kit space: name -> Transform3D.
var markers: Dictionary = {}
## Current local frame (push/pop).
var xform := Transform3D.IDENTITY
## Slight per-piece colour jitter (0 = exact palette colours).
var color_jitter := 0.04
## Slot used whenever a primitive asks for &"solid" (set to &"ice" to build ice architecture
## with every primitive, then back to &"solid").
var default_slot: StringName = &"solid"
var _stack: Array[Transform3D] = []


func _init(p_palette: NationPalette = null, p_lod: int = 0, seed: int = 1) -> void:
	palette = p_palette if p_palette else NationPalette.get_palette(&"neutral")
	lod = p_lod
	rng = ContentHash.rng(seed)


# --- frames, colours, slots ------------------------------------------------------------------

## Enters a local frame (relative to the current one).
func push(t: Transform3D) -> void:
	_stack.append(xform)
	xform = xform * t


func pop() -> void:
	if not _stack.is_empty():
		xform = _stack.pop_back()


## Frame at a position with a yaw (radians; 0 = facing -Z).
static func at(pos: Vector3, yaw: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)


## Colour of a role (StringName) or an explicit Color, with the kit's jitter.
func col(role: Variant, jitter: bool = true) -> Color:
	var c: Color = role if role is Color else palette.color(role)
	if jitter and color_jitter > 0.0:
		var k := 1.0 + rng.randf_range(-color_jitter, color_jitter)
		c = Color(c.r * k, c.g * k, c.b * k, c.a)
	return c


## The GeoBuilder of a slot with the current frame applied.
func g(slot: StringName = &"solid") -> GeoBuilder:
	if slot == &"solid":
		slot = default_slot
	if not slots.has(slot):
		slots[slot] = GeoBuilder.new()
	var b: GeoBuilder = slots[slot]
	b.xform = xform
	b.uv = Vector2.ZERO
	b.uv2 = Vector2.ZERO
	return b


func mark(name: StringName, t: Transform3D) -> void:
	markers[name] = xform * t


# --- collision ---------------------------------------------------------------------------------

## Collision box in the current frame (centre + size, optional local rotation).
func collide_box(center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	boxes.append([xform * Transform3D(basis, center), size])


## Trimesh collision triangle(s) in the current frame (counter-clockwise from the walkable side).
func collide_faces(pts: PackedVector3Array) -> void:
	for i in range(0, pts.size() - 2, 3):
		var a := xform * pts[i]
		var b := xform * pts[i + 1]
		var c := xform * pts[i + 2]
		faces.append(a)
		faces.append(c)
		faces.append(b)


func collide_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	collide_faces(PackedVector3Array([a, b, c, a, c, d]))


# --- primitives ----------------------------------------------------------------------------------

## Axis box (centre + size) in the current frame.
func box(center: Vector3, size: Vector3, role: Variant = &"wall", collide: bool = true, slot: StringName = &"solid", skip: int = 0) -> void:
	g(slot).box(Transform3D(Basis.IDENTITY, center), size, col(role), skip)
	if collide:
		collide_box(center, size)


## Rotated box: `t` positions the box centre in the current frame.
func box_t(t: Transform3D, size: Vector3, role: Variant = &"wall", collide: bool = true, slot: StringName = &"solid") -> void:
	g(slot).box(t, size, col(role))
	if collide:
		boxes.append([xform * t, size])


## Box between two points along its length axis (beams, rails, rafters): from a to b with a
## square-ish cross-section (w = width horizontal, h = height).
func beam(a: Vector3, b: Vector3, w: float, h: float, role: Variant = &"wood", collide: bool = false) -> void:
	var d := b - a
	var l := d.length()
	if l < 1e-4:
		return
	var z := d / l
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	box_t(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, h, l), role, collide)


## Extruded polygon (x/z points in the current frame) from y0 to y1; collides as trimesh.
func slab(poly: PackedVector2Array, y0: float, y1: float, role: Variant = &"base", collide: bool = true, top_role: Variant = null) -> void:
	g(&"solid").extrude(poly, y0, y1, col(role), 3, col(top_role) if top_role != null else Color(-1, 0, 0))
	if collide:
		var tri := Geometry2D.triangulate_polygon(poly)
		for k in range(0, tri.size(), 3):
			var a := poly[tri[k]]
			var b := poly[tri[k + 1]]
			var c := poly[tri[k + 2]]
			var pa := Vector3(a.x, y1, a.y)
			var pb := Vector3(b.x, y1, b.y)
			var pc := Vector3(c.x, y1, c.y)
			if (pb - pa).cross(pc - pa).y < 0.0:
				collide_faces(PackedVector3Array([pa, pc, pb]))
			else:
				collide_faces(PackedVector3Array([pa, pb, pc]))
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var ccw := GeoBuilder.polygon_area(poly) > 0.0
			var p0 := Vector3(a.x, y0, a.y)
			var p1 := Vector3(b.x, y0, b.y)
			var p2 := Vector3(b.x, y1, b.y)
			var p3 := Vector3(a.x, y1, a.y)
			if ccw:
				collide_quad(p0, p1, p2, p3)
			else:
				collide_quad(p1, p0, p3, p2)


## Vertical cylinder (columns, towers, drums). top_radius < 0 = same as radius.
func cylinder(base: Vector3, height: float, radius: float, role: Variant = &"stone", sides: int = 12, collide: bool = true,
		top_radius: float = -1.0, slot: StringName = &"solid") -> void:
	var rt := radius if top_radius < 0.0 else top_radius
	var s := maxi(sides - (4 if lod >= 1 else 0) - (2 if lod >= 2 else 0), 5)
	g(slot).cylinder(base, base + Vector3(0, height, 0), radius, rt, s, col(role), 3, s > 6)
	if collide:
		var r := maxf(radius, rt) * 0.92
		collide_box(base + Vector3(0, height * 0.5, 0), Vector3(r * 2.0, height, r * 2.0))


## Column with plinth and capital. style: &"round" (wood/lacquer), &"square" (stone), &"ice".
func column(pos: Vector3, height: float, radius: float = 0.22, role: Variant = &"wood", style: StringName = &"round",
		base_role: Variant = &"stone") -> void:
	var plinth := radius * 1.7
	if lod < 2:
		box(pos + Vector3(0, 0.12, 0), Vector3(plinth * 2.0, 0.24, plinth * 2.0), base_role, false)
	match style:
		&"square":
			box(pos + Vector3(0, height * 0.5, 0), Vector3(radius * 2.0, height, radius * 2.0), role, false)
		&"ice":
			cylinder(pos, height, radius, role, 6, false, radius * 0.8, &"ice")
		_:
			cylinder(pos, height, radius, role, 10, false)
	if lod == 0:
		# capital / bracket block
		box(pos + Vector3(0, height - 0.12, 0), Vector3(radius * 2.6, 0.24, radius * 2.6), &"trim", false)
	collide_box(pos + Vector3(0, height * 0.5, 0), Vector3(radius * 2.0, height, radius * 2.0))


## Straight wall from a to b (base points; height up from a.y), thickness centred on the line.
## opts: role, base_role (plinth course), cap_role (coping), cap (bool), crenels ({"width",
## "gap", "height"}), openings ([{"t": 0..1 centre, "width", "height", "sill", "kind":
## &"door"|&"window"|&"gate", "frame_role", "leaf": &"none"|&"closed"|&"open", "round": bool}]),
## piers (spacing in m for pilasters), skip_ends (no end caps).
func wall(a: Vector3, b: Vector3, height: float, thickness: float, opts: Dictionary = {}) -> void:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := d.length()
	if length < 0.05:
		return
	var x := d / length
	var z := x.cross(Vector3.UP).normalized()
	push(Transform3D(Basis(x, Vector3.UP, z), a))
	var role: Variant = opts.get("role", &"wall")
	var openings: Array = (opts.get("openings", []) as Array).duplicate()
	openings.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["t"]) < float(q["t"]))
	var cursor := 0.0
	var spans: Array = []
	for o: Dictionary in openings:
		var ow := float(o.get("width", 1.4))
		var oh := minf(float(o.get("height", 2.3)), height - 0.2)
		var sill := float(o.get("sill", 0.0 if o.get("kind", &"door") != &"window" else 0.9))
		var c := clampf(float(o["t"]) * length, ow * 0.5, length - ow * 0.5)
		var x0 := c - ow * 0.5
		var x1 := c + ow * 0.5
		if x0 > cursor:
			spans.append([cursor, x0, 0.0, height])
		if sill > 0.0:
			spans.append([x0, x1, 0.0, sill])
		spans.append([x0, x1, sill + oh, height])
		cursor = x1
		if lod < 2:
			_opening_frame(c, ow, sill, oh, thickness, o, role)
	if cursor < length:
		spans.append([cursor, length, 0.0, height])
	for s: Array in spans:
		var sx0: float = s[0]
		var sx1: float = s[1]
		var y0: float = s[2]
		var y1: float = s[3]
		if sx1 - sx0 < 0.01 or y1 - y0 < 0.01:
			continue
		box(Vector3((sx0 + sx1) * 0.5, (y0 + y1) * 0.5, 0.0), Vector3(sx1 - sx0, y1 - y0, thickness), role)
	if lod < 2 and opts.get("base_role") != null:
		var bh := minf(0.5, height * 0.2)
		var bspans: Array = []
		var c2 := 0.0
		for o: Dictionary in openings:
			if float(o.get("sill", 0.0 if o.get("kind", &"door") != &"window" else 0.9)) > 0.0:
				continue
			var ow := float(o.get("width", 1.4))
			var c := clampf(float(o["t"]) * length, ow * 0.5, length - ow * 0.5)
			bspans.append([c2, c - ow * 0.5])
			c2 = c + ow * 0.5
		bspans.append([c2, length])
		for bs: Array in bspans:
			if float(bs[1]) - float(bs[0]) > 0.05:
				box(Vector3((float(bs[0]) + float(bs[1])) * 0.5, bh * 0.5, 0.0), Vector3(float(bs[1]) - float(bs[0]), bh, thickness + 0.12), opts["base_role"], false)
	if opts.get("cap", true) and lod < 2:
		var cap_role: Variant = opts.get("cap_role", &"trim")
		box(Vector3(length * 0.5, height + 0.08, 0.0), Vector3(length + 0.1, 0.16, thickness + 0.16), cap_role, false)
	var cr: Dictionary = opts.get("crenels", {})
	if not cr.is_empty() and lod < 2:
		var mw := float(cr.get("width", 0.9))
		var gap := float(cr.get("gap", 0.6))
		var mh := float(cr.get("height", 0.8))
		var n := int(floor((length + gap) / (mw + gap)))
		var used := n * mw + (n - 1) * gap
		var start := (length - used) * 0.5
		for i in n:
			var cx := start + i * (mw + gap) + mw * 0.5
			box(Vector3(cx, height + 0.16 + mh * 0.5, 0.0), Vector3(mw, mh, thickness), cr.get("role", role), true)
	var piers := float(opts.get("piers", 0.0))
	if piers > 0.0 and lod == 0:
		var np := int(length / piers)
		for i in range(1, np):
			var px := i * length / np
			var skip := false
			for o: Dictionary in openings:
				if absf(px - float(o["t"]) * length) < float(o.get("width", 1.4)) * 0.5 + 0.4:
					skip = true
			if not skip:
				box(Vector3(px, height * 0.5, 0.0), Vector3(0.35, height, thickness + 0.2), opts.get("pier_role", &"trim"), false)
	pop()


func _opening_frame(c: float, ow: float, sill: float, oh: float, th: float, o: Dictionary, wall_role: Variant) -> void:
	var fr: Variant = o.get("frame_role", &"trim")
	var kind: StringName = o.get("kind", &"door")
	var fw := 0.14
	var depth := th + 0.1
	# jambs + lintel
	box(Vector3(c - ow * 0.5 - fw * 0.5, sill + oh * 0.5, 0), Vector3(fw, oh, depth), fr, false)
	box(Vector3(c + ow * 0.5 + fw * 0.5, sill + oh * 0.5, 0), Vector3(fw, oh, depth), fr, false)
	box(Vector3(c, sill + oh + fw * 0.5, 0), Vector3(ow + fw * 2.0, fw, depth), fr, false)
	if kind == &"window":
		box(Vector3(c, sill - 0.05, 0), Vector3(ow + 0.3, 0.1, depth + 0.1), fr, false)
		# dark inset + lattice
		box(Vector3(c, sill + oh * 0.5, 0), Vector3(ow, oh, th * 0.35), &"window", false)
		if lod == 0:
			var bars := maxi(int(ow / 0.3), 2)
			for i in range(1, bars):
				box(Vector3(c - ow * 0.5 + i * ow / bars, sill + oh * 0.5, 0), Vector3(0.04, oh, th * 0.5), fr, false)
			box(Vector3(c, sill + oh * 0.5, 0), Vector3(ow, 0.04, th * 0.5), fr, false)
	elif kind == &"gate" and lod == 0:
		# decorative arch ring over the gate on both faces
		var r := ow * 0.5 + 0.25
		var segs := 9
		for i in segs:
			var a0 := PI * float(i) / segs
			var a1 := PI * float(i + 1) / segs
			var p0 := Vector3(c + cos(a0) * r, sill + oh - 0.1 + sin(a0) * r * 0.45, 0)
			var p1 := Vector3(c + cos(a1) * r, sill + oh - 0.1 + sin(a1) * r * 0.45, 0)
			beam(p0, p1, depth + 0.2, 0.3, fr)
	var leaf: StringName = o.get("leaf", &"closed" if kind == &"door" else &"none")
	if kind != &"window" and leaf != &"none":
		if leaf == &"open":
			box_t(Transform3D(Basis(Vector3.UP, 1.4), Vector3(c - ow * 0.5 + 0.05, sill + oh * 0.5, -th * 0.5 - ow * 0.25)),
					Vector3(ow * 0.5, oh, 0.07), &"door", false)
		else:
			box(Vector3(c, sill + oh * 0.5, 0), Vector3(ow, oh, th * 0.3), &"door", true)
			if lod == 0:
				box(Vector3(c, sill + oh * 0.5, th * 0.17), Vector3(0.05, oh, 0.03), &"trim", false)
				for side in [-1.0, 1.0]:
					g().cylinder(Vector3(c + side * 0.18, sill + oh * 0.48, th * 0.16), Vector3(c + side * 0.18, sill + oh * 0.48, th * 0.24), 0.07, 0.07, 6, col(&"metal"), 2)


## Closed loop of walls through `points` (base points). Same opts as wall().
func wall_loop(points: PackedVector3Array, height: float, thickness: float, opts: Dictionary = {}, closed: bool = true) -> void:
	var n := points.size()
	for i in (n if closed else n - 1):
		var o := opts.duplicate()
		var per: Dictionary = opts.get("per_segment", {})
		if per.has(i):
			o.merge(per[i], true)
		wall(points[i], points[(i + 1) % n], height, thickness, o)
	if lod < 2:
		for i in (n if closed else n):
			var p := points[i]
			box(p + Vector3(0, (height + 0.4) * 0.5, 0), Vector3(thickness + 0.3, height + 0.4, thickness + 0.3), opts.get("corner_role", opts.get("role", &"wall")), true)


## Straight stairs from `bottom` (front-bottom centre) to `top` (back-top centre). Visual steps,
## walkable ramp collision. opts: role, rise (step height, default 0.18), sides (bool: side walls), side_role.
func stairs(bottom: Vector3, top: Vector3, width: float, opts: Dictionary = {}) -> void:
	var d := Vector3(top.x - bottom.x, 0, top.z - bottom.z)
	var run := d.length()
	var rise := top.y - bottom.y
	if run < 0.05 or absf(rise) < 0.05:
		return
	var z := -d / run          # local -Z = up the stairs direction
	var x := Vector3.UP.cross(z).normalized()
	push(Transform3D(Basis(x, Vector3.UP, z), bottom))
	var step_h := float(opts.get("rise", 0.18))
	var n := maxi(int(ceil(absf(rise) / step_h)), 1)
	if lod >= 1:
		n = maxi(n / 2, 1)
	var role: Variant = opts.get("role", &"stone")
	for i in n:
		var y1 := rise * float(i + 1) / n
		var z0 := -run * float(i) / n
		var z1 := -run * float(i + 1) / n
		box(Vector3(0, y1 * 0.5, (z0 + z1) * 0.5), Vector3(width, absf(y1), absf(z1 - z0)), role, false)
	# walkable ramp along the step nosings
	collide_quad(Vector3(-width * 0.5, 0, 0), Vector3(width * 0.5, 0, 0), Vector3(width * 0.5, rise, -run), Vector3(-width * 0.5, rise, -run))
	if opts.get("sides", false):
		var sr: Variant = opts.get("side_role", &"stone_dark")
		for side in [-1.0, 1.0]:
			var sx: float = side * (width * 0.5 + 0.15)
			g(&"solid").extrude(PackedVector2Array([Vector2(sx - 0.15, 0.0), Vector2(sx + 0.15, 0.0), Vector2(sx + 0.15, -run), Vector2(sx - 0.15, -run)]),
					0.0, 0.3, col(sr), 0)
			# sloped balustrade
			beam(Vector3(sx, 0.55, 0), Vector3(sx, rise + 0.55, -run), 0.3, 0.3, sr, true)
			box(Vector3(sx, 0.3, 0), Vector3(0.36, 0.6, 0.36), sr, true)
	pop()


## Inclined walkable slab from bottom (front centre) to top (back centre).
func ramp(bottom: Vector3, top: Vector3, width: float, thickness: float = 0.3, role: Variant = &"stone") -> void:
	var d := top - bottom
	var l := d.length()
	if l < 0.05:
		return
	var zf := d / l
	var x := zf.cross(Vector3.UP).normalized() if absf(zf.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var y := x.cross(zf).normalized()
	var t := Transform3D(Basis(x, y, -zf), (bottom + top) * 0.5 - y * thickness * 0.5)
	g().box(t, Vector3(width, thickness, l), col(role))
	var hx := x * width * 0.5
	collide_quad(bottom - hx, bottom + hx, top + hx, top - hx)


## Railing through `points` (base points on the deck). opts: role, post_role, spacing, rails (1-2),
## collide (default true: an invisible-thick barrier per segment).
func railing(points: PackedVector3Array, height: float = 1.0, opts: Dictionary = {}) -> void:
	var role: Variant = opts.get("role", &"wood")
	var post_role: Variant = opts.get("post_role", role)
	var spacing := float(opts.get("spacing", 1.8))
	var rails := int(opts.get("rails", 2))
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var seg := a.distance_to(b)
		if lod >= 2:
			beam(a + Vector3(0, height * 0.5, 0), b + Vector3(0, height * 0.5, 0), 0.08, height, role)
		else:
			beam(a + Vector3(0, height, 0), b + Vector3(0, height, 0), 0.1, 0.1, role)
			if rails > 1 and lod == 0:
				beam(a + Vector3(0, height * 0.5, 0), b + Vector3(0, height * 0.5, 0), 0.06, 0.06, role)
			var np := maxi(int(seg / spacing), 1)
			for k in np:
				var p := a.lerp(b, float(k) / np)
				box(p + Vector3(0, height * 0.5, 0), Vector3(0.12, height, 0.12), post_role, false)
		if opts.get("collide", true):
			var mid := (a + b) * 0.5 + Vector3(0, height * 0.5, 0)
			var dir := (b - a).normalized()
			var xz := Vector3(dir.x, 0, dir.z).normalized()
			if xz.length_squared() > 0.0:
				var basis := Basis(xz.cross(Vector3.UP).normalized(), Vector3.UP, xz).orthonormalized()
				boxes.append([xform * Transform3D(basis, mid), Vector3(0.15, height + 0.2, seg)])
	if lod < 2 and not points.is_empty():
		var last := points[points.size() - 1]
		box(last + Vector3(0, height * 0.5, 0), Vector3(0.14, height, 0.14), post_role, false)


## Free-standing door with frame at `t` (origin = bottom centre, -Z = outside).
func door(t: Transform3D, width: float = 1.2, height: float = 2.2, opts: Dictionary = {}) -> void:
	push(t)
	var o := {"kind": &"door", "frame_role": opts.get("frame_role", &"trim"), "leaf": opts.get("leaf", &"closed")}
	_opening_frame(0.0, width, 0.0, height, float(opts.get("thickness", 0.3)), o, &"wall")
	pop()


## Window frame with lattice at `t` (origin = sill centre on the wall face).
func window(t: Transform3D, width: float = 1.0, height: float = 1.1, opts: Dictionary = {}) -> void:
	push(t)
	_opening_frame(0.0, width, 0.0, height, float(opts.get("thickness", 0.3)), {"kind": &"window", "frame_role": opts.get("frame_role", &"trim")}, &"wall")
	pop()


## Semicircular arch spanning from pier a to pier b (base points), `height` to the springing line.
func arch(a: Vector3, b: Vector3, height: float, thickness: float = 0.6, depth: float = 0.8, role: Variant = &"stone") -> void:
	var span := a.distance_to(b)
	var mid := (a + b) * 0.5
	var x := (b - a).normalized()
	var z := x.cross(Vector3.UP).normalized()
	push(Transform3D(Basis(x, Vector3.UP, z), mid))
	box(Vector3(-span * 0.5, height * 0.5, 0), Vector3(thickness, height, depth), role)
	box(Vector3(span * 0.5, height * 0.5, 0), Vector3(thickness, height, depth), role)
	var r := span * 0.5
	var segs: int = [12, 7, 4][clampi(lod, 0, 2)]
	for i in segs:
		var a0 := PI * float(i) / segs
		var a1 := PI * float(i + 1) / segs
		var p0 := Vector3(-cos(a0) * r, height + sin(a0) * r, 0)
		var p1 := Vector3(-cos(a1) * r, height + sin(a1) * r, 0)
		beam(p0, p1, depth, thickness, role, true)
	pop()


## Lantern / light fixture at `pos`. opts: style (&"paper" hanging, &"post", &"stone", &"ice",
## &"brazier", &"wall"), color (glow colour, default palette glow), light (bool, default true),
## range (m), energy, height (post styles), role.
func lantern(pos: Vector3, opts: Dictionary = {}) -> void:
	var style: StringName = opts.get("style", &"paper")
	var glow: Color = opts.get("color", palette.color(&"glow"))
	var gb := g(&"glow")
	gb.uv = Vector2(0, 1)       # flicker amount for kit_glow.gdshader
	var light_pos := pos
	match style:
		&"paper":
			# cord, top cap, paper body, bottom cap
			if lod == 0:
				g().cylinder(pos + Vector3(0, 0.35, 0), pos + Vector3(0, 0.8, 0), 0.012, 0.012, 3, col(&"wood_dark"), 0)
			g().cylinder(pos + Vector3(0, 0.26, 0), pos + Vector3(0, 0.36, 0), 0.12, 0.08, 6, col(&"wood_dark"), 2)
			gb = g(&"glow")
			gb.uv = Vector2(0, 1)
			gb.blob(pos, 0.24, 1 if lod == 0 else 0, glow, null, 0.0, Vector3(1, 1.15, 1), pos, 0.6, glow * 0.85)
			g().cylinder(pos - Vector3(0, 0.36, 0), pos - Vector3(0, 0.26, 0), 0.08, 0.12, 6, col(&"wood_dark"), 1)
		&"post", &"stone":
			var h := float(opts.get("height", 1.7))
			var stone := style == &"stone"
			var r: Variant = opts.get("role", &"stone" if stone else &"wood_dark")
			box(pos + Vector3(0, 0.1, 0), Vector3(0.5, 0.2, 0.5), &"stone_dark", false)
			if stone:
				box(pos + Vector3(0, h * 0.35, 0), Vector3(0.28, h * 0.6, 0.28), r, false)
				box(pos + Vector3(0, h * 0.68, 0), Vector3(0.5, 0.1, 0.5), r, false)
			else:
				g().cylinder(pos, pos + Vector3(0, h * 0.75, 0), 0.07, 0.06, 6, col(r), 0)
			var lc := pos + Vector3(0, h * 0.82, 0)
			gb = g(&"glow")
			gb.uv = Vector2(0, 1)
			gb.box(Transform3D(Basis(), lc), Vector3(0.3, 0.32, 0.3), glow)
			if lod == 0:
				for cx in [-1.0, 1.0]:
					for cz in [-1.0, 1.0]:
						box(lc + Vector3(cx * 0.16, 0, cz * 0.16), Vector3(0.04, 0.34, 0.04), r, false)
			g().cone(lc + Vector3(0, 0.17, 0), lc + Vector3(0, 0.45, 0), 0.33, 4 if stone else 6, col(&"roof" if not stone else r))
			light_pos = lc
			collide_box(pos + Vector3(0, h * 0.5, 0), Vector3(0.4, h, 0.4))
		&"ice":
			var h2 := float(opts.get("height", 1.6))
			g(&"ice").cylinder(pos, pos + Vector3(0, h2 * 0.7, 0), 0.22, 0.16, 6, col(&"ice"), 1)
			var lc2 := pos + Vector3(0, h2 * 0.82, 0)
			gb = g(&"glow")
			gb.uv = Vector2(0, 0.4)
			gb.blob(lc2, 0.2, 0, opts.get("color", Color(0.7, 0.85, 1.0)), null, 0.0, Vector3(0.8, 1.4, 0.8))
			light_pos = lc2
			glow = opts.get("color", Color(0.7, 0.85, 1.0))
			collide_box(pos + Vector3(0, h2 * 0.5, 0), Vector3(0.4, h2, 0.4))
		&"brazier":
			brazier(pos, opts)
			return
		&"wall":
			box(pos + Vector3(0, 0, 0.1), Vector3(0.12, 0.3, 0.2), &"metal", false)
			gb = g(&"glow")
			gb.uv = Vector2(0, 1)
			gb.box(Transform3D(Basis(), pos + Vector3(0, 0.05, -0.12)), Vector3(0.24, 0.3, 0.24), glow)
			light_pos = pos + Vector3(0, 0.05, -0.2)
	if opts.get("light", true):
		add_light(light_pos, glow, float(opts.get("range", 9.0)), float(opts.get("energy", 1.6)))


## Fire bowl on a tripod with glowing coals and a flame; records a light.
func brazier(pos: Vector3, opts: Dictionary = {}) -> void:
	var h := float(opts.get("height", 0.9))
	var r := float(opts.get("radius", 0.45))
	var metal: Variant = opts.get("role", &"metal")
	if lod < 2:
		for k in 3:
			var a := TAU * k / 3.0
			beam(pos + Vector3(cos(a) * r * 0.9, 0, sin(a) * r * 0.9), pos + Vector3(cos(a) * r * 0.5, h, sin(a) * r * 0.5), 0.06, 0.06, &"wood_dark")
	g().cylinder(pos + Vector3(0, h - 0.05, 0), pos + Vector3(0, h + 0.3, 0), r * 0.55, r, 10 if lod == 0 else 6, col(metal), 1)
	var fire: Color = opts.get("color", Color(1.0, 0.55, 0.15))
	var gb := g(&"glow")
	gb.uv = Vector2(0, 1)
	gb.cylinder(pos + Vector3(0, h + 0.24, 0), pos + Vector3(0, h + 0.3, 0), r * 0.92, r * 0.9, 8, fire * 0.8, 2)
	if lod == 0:
		for k in 3:
			var a := TAU * k / 3.0 + 0.4
			var b := pos + Vector3(cos(a) * r * 0.3, h + 0.28, sin(a) * r * 0.3)
			gb.cone(b, b + Vector3(0, 0.45 + 0.15 * k, 0), r * 0.32, 5, fire)
	collide_box(pos + Vector3(0, (h + 0.3) * 0.5, 0), Vector3(r * 1.6, h + 0.3, r * 1.6))
	if opts.get("light", true):
		add_light(pos + Vector3(0, h + 0.7, 0), fire, float(opts.get("range", 11.0)), float(opts.get("energy", 2.2)))


## Records a budgeted point light (kit space). priority: higher stays on when over budget.
func add_light(pos: Vector3, color: Color, range_m: float = 9.0, energy: float = 1.6, priority: int = 0) -> void:
	lights.append({"position": xform * pos, "color": color, "range": range_m, "energy": energy, "priority": priority})


## Hanging banner: `t` origin = top centre, hangs along -Y, faces -Z. opts: role, alt_role
## (emblem/border colour), emblem (bool), rod (bool), tail (pointed bottom).
func banner(t: Transform3D, width: float, length: float, opts: Dictionary = {}) -> void:
	push(t)
	var c0 := col(opts.get("role", &"cloth"), false)
	var c1 := col(opts.get("alt_role", &"cloth_alt"), false)
	var nx: int = [4, 2, 1][clampi(lod, 0, 2)]
	var ny: int = [8, 4, 2][clampi(lod, 0, 2)]
	var cb := g(&"cloth")
	var base := cb.vertex_count()
	for j in ny + 1:
		var v := float(j) / ny
		for i in nx + 1:
			var u := float(i) / nx
			var px := (u - 0.5) * width
			var py := -v * length
			if opts.get("tail", true) and j == ny:
				py -= (0.5 - absf(u - 0.5)) * width * 0.6
			var c := c0
			if opts.get("emblem", true):
				var border := absf(u - 0.5) > 0.38 or v < 0.08 or v > 0.9
				var diamond := absf(u - 0.5) * 1.6 + absf(v - 0.42) * 1.1 < 0.25
				if border or diamond:
					c = c1
			cb.vertex(Vector3(px, py, 0), Vector3(0, 0, -1), c, Vector2(v, u))
	for j in ny:
		for i in nx:
			var k := base + j * (nx + 1) + i
			cb.quad(k, k + nx + 1, k + nx + 2, k + 1)
	if opts.get("rod", true):
		g().cylinder(Vector3(-width * 0.55, 0.03, 0), Vector3(width * 0.55, 0.03, 0), 0.03, 0.03, 5, col(&"wood_dark"), 3)
	pop()


## Flag on a pole: pole from base, flag pinned at the pole top, flying along +X of `t`.
func flag(t: Transform3D, pole_h: float = 5.0, width: float = 1.6, height: float = 1.0, opts: Dictionary = {}) -> void:
	push(t)
	cylinder(Vector3.ZERO, pole_h, 0.06, opts.get("pole_role", &"wood_dark"), 6, true, 0.04)
	g().blob(Vector3(0, pole_h + 0.06, 0), 0.09, 0, col(&"metal"))
	var cb := g(&"cloth")
	var nx: int = [6, 3, 1][clampi(lod, 0, 2)]
	var ny: int = [3, 2, 1][clampi(lod, 0, 2)]
	var c0 := col(opts.get("role", &"cloth"), false)
	var c1 := col(opts.get("alt_role", &"cloth_alt"), false)
	var base := cb.vertex_count()
	for j in ny + 1:
		var v := float(j) / ny
		for i in nx + 1:
			var u := float(i) / nx
			var c := c1 if (absf(v - 0.5) < 0.18 and u > 0.25 and u < 0.75) else c0
			cb.vertex(Vector3(0.05 + u * width, pole_h - 0.05 - v * height, 0), Vector3(0, 0, -1), c, Vector2(u, v))
	for j in ny:
		for i in nx:
			var k := base + j * (nx + 1) + i
			cb.quad(k, k + 1, k + nx + 2, k + nx + 1)
	pop()


## Simple solid ornament: &"finial" (stacked spheres + spike), &"horn" (upturned ridge curl),
## &"orb" (sphere), &"spike" (cone). size = overall height.
func ornament(pos: Vector3, kind: StringName, size: float = 0.6, role: Variant = &"metal", dir: Vector3 = Vector3.UP) -> void:
	if lod >= 2 and kind != &"finial":
		return
	match kind:
		&"finial":
			g().blob(pos + Vector3(0, size * 0.18, 0), size * 0.18, 0 if lod > 0 else 1, col(role))
			g().cone(pos + Vector3(0, size * 0.3, 0), pos + Vector3(0, size, 0), size * 0.1, 6, col(role))
		&"horn":
			var d := dir.normalized()
			var p1 := pos + d * size * 0.45 + Vector3(0, size * 0.35, 0)
			var p2 := pos + d * size * 0.7 + Vector3(0, size, 0)
			g().tube(PackedVector3Array([pos, p1, p2]), PackedFloat32Array([size * 0.14, size * 0.1, size * 0.02]), 5, col(role))
		&"orb":
			g().blob(pos, size * 0.5, 1 if lod == 0 else 0, col(role))
		&"spike":
			g().cone(pos, pos + dir.normalized() * size, size * 0.15, 5, col(role))


# --- output ----------------------------------------------------------------------------------------

## Finishes the kit: mesh arrays per slot, collision, lights, markers (thread-safe).
func build() -> KitResult:
	var r := KitResult.new()
	var total := AABB()
	var first := true
	for slot: StringName in [&"solid", &"ice", &"glow", &"cloth"]:
		if not slots.has(slot):
			continue
		var b: GeoBuilder = slots[slot]
		if b.is_empty():
			continue
		r.surfaces.append([b.arrays(), slot])
		r.triangle_count += b.triangle_count()
		var bb := b.aabb()
		total = bb if first else total.merge(bb)
		first = false
	r.aabb = total
	r.boxes = boxes
	r.faces = faces
	r.lights = lights
	r.markers = markers
	return r
