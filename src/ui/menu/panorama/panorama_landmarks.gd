class_name PanoramaLandmarks
extends RefCounted
## Distant hints of the four nations for the menu panorama, built from primitives into
## single vertex-coloured meshes (one draw call each): an Air Temple on a far peak, a
## Ba Sing Se style great wall along a ridge, Water Tribe ice spires in the sea with a
## sun glint, and a Fire Nation volcano plume.

const STONE := Color(0.70, 0.66, 0.58)
const STONE_DARK := Color(0.50, 0.47, 0.42)
const TEMPLE_WALL := Color(0.86, 0.82, 0.74)
const TEMPLE_ROOF := Color(0.26, 0.42, 0.68)
const GOLD := Color(0.86, 0.66, 0.30)
const EK_ROOF := Color(0.30, 0.46, 0.30)
const ICE := Color(0.78, 0.90, 0.98)
const ICE_DEEP := Color(0.30, 0.55, 0.78)


static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	return m


# --- primitive appenders (SurfaceTool, flat normals, clockwise fronts) -------------------------

static func box(st: SurfaceTool, xf: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), [Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)]],
		[Vector3(-1, 0, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z)]],
		[Vector3(0, 1, 0), [Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)]],
		[Vector3(0, -1, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)]],
		[Vector3(0, 0, 1), [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3(0, 0, -1), [Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)]],
	]
	for f: Array in faces:
		var n: Vector3 = xf.basis * (f[0] as Vector3)
		var q: Array = f[1]
		_quad(st, xf * (q[0] as Vector3), xf * (q[1] as Vector3), xf * (q[2] as Vector3), xf * (q[3] as Vector3), n.normalized(), col)


## Quad given counter-clockwise as seen from outside (a, b, c, d); emitted clockwise.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	st.set_color(col)
	st.set_normal(n)
	for v: Vector3 in [a, c, b, a, d, c]:
		st.add_vertex(v)


## Cylinder (top_r == 0 -> cone) standing on `base` with `segs` sides.
static func cylinder(st: SurfaceTool, base: Vector3, r_bottom: float, r_top: float, height: float, segs: int, col: Color, roof_col: Color = Color(0, 0, 0, 0)) -> void:
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var p0 := base + d0 * r_bottom
		var p1 := base + d1 * r_bottom
		var q0 := base + d0 * r_top + Vector3.UP * height
		var q1 := base + d1 * r_top + Vector3.UP * height
		var slope := (r_bottom - r_top) / maxf(height, 0.01)
		var n := ((d0 + d1) * 0.5 + Vector3.UP * slope).normalized()
		st.set_color(col)
		st.set_normal(n)
		# outward faces, clockwise seen from outside
		for v: Vector3 in [p0, p1, q0, p1, q1, q0]:
			st.add_vertex(v)
		if r_top > 0.01:
			var cap: Color = roof_col if roof_col.a > 0.0 else col
			st.set_color(cap)
			st.set_normal(Vector3.UP)
			var top := base + Vector3.UP * height
			for v: Vector3 in [top, q0, q1]:
				st.add_vertex(v)


# --- landmarks ------------------------------------------------------------------------------

## Southern Air Temple silhouette: stepped base, slender towers with blue cone roofs.
static func air_temple(scale: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := scale
	cylinder(st, Vector3(0, -30 * s, 0), 62 * s, 54 * s, 40 * s, 14, STONE_DARK)
	cylinder(st, Vector3(0, 10 * s, 0), 46 * s, 44 * s, 12 * s, 14, TEMPLE_WALL)
	# central tower
	cylinder(st, Vector3(0, 22 * s, 0), 11 * s, 9.5 * s, 72 * s, 12, TEMPLE_WALL)
	cylinder(st, Vector3(0, 94 * s, 0), 17 * s, 0.0, 44 * s, 12, TEMPLE_ROOF)
	cylinder(st, Vector3(0, 136 * s, 0), 1.2 * s, 0.6 * s, 16 * s, 6, GOLD)
	# side towers
	for spec: Array in [[-32.0, 10.0, 54.0], [30.0, 14.0, 46.0], [-14.0, -26.0, 40.0], [18.0, -30.0, 34.0], [-40.0, -12.0, 30.0]]:
		var p := Vector3(spec[0] * s, 22 * s, spec[1] * s)
		var h: float = spec[2] * s
		cylinder(st, p, 6.5 * s, 5.8 * s, h, 10, TEMPLE_WALL)
		cylinder(st, p + Vector3.UP * h, 10.5 * s, 0.0, h * 0.5, 10, TEMPLE_ROOF)
	# connecting walls
	box(st, Transform3D(Basis(), Vector3(-14 * s, 30 * s, 8 * s)), Vector3(40 * s, 16 * s, 6 * s), TEMPLE_WALL)
	box(st, Transform3D(Basis(), Vector3(12 * s, 30 * s, 10 * s)), Vector3(34 * s, 14 * s, 6 * s), TEMPLE_WALL)
	return st.commit()


## Great wall following `points` (world positions on the ground, ordered).
static func great_wall(points: PackedVector3Array, height: float = 16.0, thickness: float = 8.0, tower_every: int = 7) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var mid := (a + b) * 0.5
		var d := b - a
		var flat := Vector3(d.x, 0, d.z)
		var length := flat.length()
		if length < 0.1:
			continue
		var yaw := atan2(-flat.z, flat.x)
		var basis := Basis(Vector3.UP, yaw)
		var top := maxf(a.y, b.y)
		var low := minf(a.y, b.y)
		var seg_h := height + (top - low)
		var c := Vector3(mid.x, low - 6.0 + seg_h * 0.5 + 3.0, mid.z)
		box(st, Transform3D(basis, c), Vector3(length + 1.5, seg_h + 6.0, thickness), STONE)
		# crenellations along the outer edge
		var n_cren := maxi(1, int(length / 6.0))
		for k in n_cren:
			var t := (k + 0.5) / n_cren
			var p := a.lerp(b, t)
			var yy := maxf(a.y, b.y) + height - 3.0 + 1.6
			box(st, Transform3D(basis, Vector3(p.x, yy + 1.6, p.z) + basis.z * (thickness * 0.4)), Vector3(3.0, 3.2, 1.6), STONE_DARK)
		if i % tower_every == 0:
			var tb := Vector3(a.x, a.y - 4.0, a.z)
			box(st, Transform3D(basis, tb + Vector3.UP * (height + 10.0) * 0.5), Vector3(16.0, height + 14.0, 16.0), STONE)
			cylinder(st, tb + Vector3.UP * (height + 10.0), 14.0, 0.0, 11.0, 4, EK_ROOF)
	return st.commit()


## Cluster of jagged ice spires (Water Tribe hint), base at y = 0.
static func ice_spires(seed_v: int = 3) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# the floe the spires rise from
	cylinder(st, Vector3(0, -2.0, 0), 44.0, 40.0, 3.4, 11, ICE.lerp(ICE_DEEP, 0.25), ICE)
	var specs := [[0.0, 0.0, 46.0, 11.0], [-16.0, 6.0, 30.0, 9.0], [14.0, -4.0, 34.0, 8.0], [-26.0, -6.0, 18.0, 7.0],
			[26.0, 8.0, 20.0, 7.5], [5.0, 14.0, 22.0, 8.0], [-6.0, -16.0, 16.0, 6.0]]
	for sp: Array in specs:
		var base := Vector3(sp[0], -4.0, sp[1])
		var h: float = sp[2]
		var r: float = sp[3]
		var sides := rng.randi_range(5, 7)
		var tip := base + Vector3(rng.randf_range(-3, 3), h, rng.randf_range(-3, 3))
		var ring: Array[Vector3] = []
		for i in sides:
			var a := TAU * i / sides + rng.randf() * 0.4
			ring.append(base + Vector3(cos(a), 0, sin(a)) * r * rng.randf_range(0.75, 1.15))
		for i in sides:
			var p0 := ring[i]
			var p1 := ring[(i + 1) % sides]
			var n := (tip - p0).cross(p1 - p0).normalized()
			if n.dot(((p0 + p1) * 0.5 - base).normalized()) < 0.0:
				n = -n
			var lit := clampf(n.dot(Vector3(0.3, 0.5, 0.8).normalized()) * 0.5 + 0.5, 0.0, 1.0)
			st.set_color(ICE_DEEP.lerp(ICE, lit))
			st.set_normal(n)
			for v: Vector3 in [p0, p1, tip]:
				st.add_vertex(v)
	return st.commit()


static func ice_material() -> StandardMaterial3D:
	var m := material()
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.2
	m.emission_enabled = true
	m.emission = Color(0.18, 0.30, 0.42)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Low-poly pine (three stacked cones on a trunk), ~12 m tall, origin at the base.
static func pine_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	cylinder(st, Vector3(0, -1.0, 0), 0.5, 0.4, 3.0, 5, Color(0.30, 0.22, 0.16))
	cylinder(st, Vector3(0, 1.6, 0), 3.6, 0.0, 5.0, 7, Color(0.13, 0.25, 0.16))
	cylinder(st, Vector3(0, 4.2, 0), 2.8, 0.0, 4.6, 7, Color(0.15, 0.29, 0.18))
	cylinder(st, Vector3(0, 6.8, 0), 1.9, 0.0, 5.2, 7, Color(0.18, 0.33, 0.20))
	return st.commit()


## Scatters pines over the front slope of a range (below `max_height`, gentle slopes).
static func pine_forest(r: PanoramaRange, count: int, max_height: float, seed_v: int, scale: float = 1.0) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var xforms: Array[Transform3D] = []
	var tries := 0
	while xforms.size() < count and tries < count * 8:
		tries += 1
		var x := rng.randf_range(r.x0 + (r.x1 - r.x0) * 0.08, r.x1 - (r.x1 - r.x0) * 0.08)
		var v := rng.randf_range(0.02, r.crest + 0.1)
		var h := r.height_at(x, v)
		if h < 3.0 or h > max_height:
			continue
		var hx := r.height_at(x + 4.0, v)
		var hv := r.height_at(x, v + 4.0 / r.depth)
		var slope := Vector2(hx - h, hv - h).length() / 4.0
		if slope > 0.9:
			continue
		var s := rng.randf_range(0.7, 1.35) * scale
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.25), s))
		xforms.append(Transform3D(b, Vector3(x, h - 0.5, r.z_front - v * r.depth)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = pine_mesh()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		var tint := rng.randf_range(0.75, 1.15)
		mm.set_instance_color(i, Color(tint, tint * rng.randf_range(0.95, 1.08), tint))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := material()
	m.vertex_color_use_as_albedo = true
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Volcano smoke plume (GPU particles, soft puffs) rising from `vent`.
static func smoke_plume(vent: Vector3, sun_dir: Vector3, budget: float = 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "VolcanoPlume"
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 60.0
	pm.direction = Vector3(0.15, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 30.0
	pm.gravity = Vector3(6.0, 1.5, 0.0)
	pm.damping_min = 0.15
	pm.damping_max = 0.3
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(1, 2.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.06, Color(1, 1, 1, 0.85))
	g.add_point(0.6, Color(1, 1, 1, 0.5))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var m := ShaderMaterial.new()
	m.shader = preload("res://src/ui/shaders/soft_puff.gdshader")
	m.set_shader_parameter(&"noise_tex", preload("res://assets/textures/world/clouds.png"))
	m.set_shader_parameter(&"sun_dir", sun_dir)
	m.set_shader_parameter(&"glow", 0.9)
	m.set_shader_parameter(&"dark_color", Color(0.30, 0.25, 0.26))
	m.set_shader_parameter(&"light_color", Color(0.78, 0.66, 0.60))
	var quad := QuadMesh.new()
	quad.size = Vector2(320, 320)
	quad.material = m
	p.draw_pass_1 = quad
	p.amount = maxi(16, int(48 * budget))
	p.lifetime = 70.0
	p.preprocess = 70.0
	p.local_coords = false
	p.position = vent
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-1500, -200, -1500), Vector3(3000, 3000, 3000))
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	return p
