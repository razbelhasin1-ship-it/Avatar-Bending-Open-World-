class_name WaterfallBuilder
extends RefCounted
## Waterfalls from WorldData.get_waterfalls() ({top, bottom, height, width, frozen, pool}).
##
## The water leaves the notched lip almost horizontally and falls in a ballistic curve that is
## pushed clear of the cliff (terrain sampled along the fall), as two layered animated sheets
## (waterfall.gdshader: accelerating streaks, foam at the lip and the plunge), a plunge-foam disc on
## the pool, wet boulders, mist puffs (GPUParticles3D scaled by Settings.effects_scale) and a
## positional roar (Audio loop, pitched-down rain bed). Frozen falls become a static ice cascade
## with icicles (glossy kit ice). build() is thread-safe; instantiate() runs on the main thread.

const SHEET_SHADER := preload("res://assets/shaders/content/waterfall.gdshader")
const FOAM_SHADER := preload("res://assets/shaders/content/water_foam.gdshader")
const MIST_SHADER := preload("res://assets/shaders/content/mist.gdshader")
const NOISE := preload("res://assets/textures/world/noise.png")

static var _sheet_mats: Dictionary = {}
static var _foam_mat: ShaderMaterial
static var _mist_mat: ShaderMaterial


## Thread-safe geometry: {"sheets": [[arrays, layer], ...], "foam": arrays, "kit": KitResult,
##  "path": PackedVector3Array, "plunge": Vector3, "height": float, "frozen": bool, "origin": Vector3}
static func build(rec: Dictionary) -> Dictionary:
	var top: Vector3 = rec["top"]
	var bottom: Vector3 = rec["bottom"]
	var width := float(rec.get("width", 8.0))
	var frozen: bool = rec.get("frozen", false)
	var rng := ContentHash.rng(ContentHash.hash_name(String(rec.get("id", "wf"))))
	var pool_level := bottom.y
	for lk in WorldData.get_lakes():
		if lk["id"] == rec.get("pool"):
			pool_level = float(lk["level"])
	var path := fall_path(top, Vector3(bottom.x, pool_level, bottom.z))
	var origin := top
	var res := {"sheets": [], "path": path, "plunge": path[path.size() - 1], "height": top.y - pool_level,
		"frozen": frozen, "origin": origin}
	var kit := BuildingKit.new(NationPalette.get_palette(&"water_tribe" if frozen else &"neutral"), 0, rng.randi())
	kit.color_jitter = 0.0
	if frozen:
		_ice_cascade(kit, path, width, rng, origin)
	else:
		res["sheets"].append([_sheet(path, width * 1.25, 0.0, origin), 0])
		res["sheets"].append([_sheet(path, width * 1.0, -0.7, origin), 1])
		res["foam"] = _foam_disc(path[path.size() - 1] - origin, width * 1.1)
	# boulders around the plunge and at the lip
	var region := WorldData.get_region(bottom.x, bottom.z)
	var rock := TerrainPatterns.ROCK_L[TerrainPatterns.palette_index(region)].srgb_to_linear()
	var plunge: Vector3 = path[path.size() - 1]
	var d := (plunge - Vector3(top.x, plunge.y, top.z)).normalized()
	var side := d.cross(Vector3.UP).normalized()
	for k in 7:
		var a := rng.randf_range(-1.6, 1.6)
		var q := plunge + side * a * width * 0.8 + d * rng.randf_range(-0.5, 1.5) * width * 0.5
		q.y = maxf(WorldData.get_height(q.x, q.z), pool_level - 0.6)
		var r := rng.randf_range(0.8, 2.0)
		var wet := rock * 0.55
		kit.g().blob(q - origin, r, 1, wet, rng, 0.25, Vector3(1.0, 0.7, 1.0), Vector3.INF, 0.0, wet * 0.7, Vector2.ZERO, true)
		kit.collide_box(q - origin, Vector3(r * 1.4, r, r * 1.4))
	for sgn in [-1.0, 1.0]:
		var q: Vector3 = top + side * sgn * (width * 0.55 + 0.6)
		q.y = WorldData.get_height(q.x, q.z)
		kit.g().blob(q - origin, 1.2, 1, rock * 0.7, rng, 0.25, Vector3(1.2, 0.8, 1.0), Vector3.INF, 0.0, rock * 0.5, Vector2.ZERO, true)
	res["kit"] = kit.build()
	return res


## Ballistic fall from the lip to the pool, kept at least 1.5 m clear of the cliff.
static func fall_path(top: Vector3, bottom: Vector3) -> PackedVector3Array:
	var h := top.y - bottom.y
	var horiz := Vector2(bottom.x - top.x, bottom.z - top.z)
	var dist := horiz.length()
	var dir := horiz.normalized() if dist > 0.01 else Vector2(0, 1)
	var n := clampi(int(h / 2.5), 10, 60)
	var pts := PackedVector3Array()
	# a short run-in over the lip
	pts.append(Vector3(top.x - dir.x * 2.5, top.y + 0.15, top.z - dir.y * 2.5))
	var reach := 0.0          # horizontal distance from the lip never decreases (no zig-zag)
	for i in n + 1:
		var s := float(i) / n
		var fall := s * s
		var y := top.y - h * fall
		var out := dist * (1.0 - (1.0 - s) * (1.0 - s))
		# push clear of the cliff
		var push := 0.0
		while push < 40.0 and i < n and WorldData.get_height(top.x + dir.x * (out + push), top.z + dir.y * (out + push)) > y - 1.5:
			push += 1.0
		reach = maxf(reach, out + push)
		pts.append(Vector3(top.x + dir.x * reach, y, top.z + dir.y * reach))
	# smooth (pushing creates corners)
	for it in 6:
		for i in range(2, pts.size() - 1):
			var a := pts[i - 1]
			var b := pts[i + 1]
			var m := (a + b) * 0.5
			pts[i] = Vector3(lerpf(pts[i].x, m.x, 0.5), pts[i].y, lerpf(pts[i].z, m.z, 0.5))
	return pts


## Ribbon along the path (UV.x across, UV.y metres fallen), offset towards the cliff by `back`.
## The ribbon keeps one horizontal orientation (the overall fall direction), so near-vertical
## stretches of the path cannot twist it.
static func _sheet(path: PackedVector3Array, width: float, back: float, origin: Vector3) -> Array:
	var g := GeoBuilder.new()
	var n := path.size()
	var cols := 6
	var fallen := 0.0
	var top_y := path[1].y
	var fd := fall_dir(path)
	var side := Vector3.UP.cross(fd).normalized()
	for i in n:
		var p := path[i]
		var t := (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		var nrm := t.cross(side).normalized()
		if nrm.dot(fd) < 0.0:
			nrm = -nrm
		if i > 0:
			fallen = maxf(top_y - p.y, 0.0)
		var spread := 1.0 + 0.45 * clampf(fallen / maxf(top_y - path[n - 1].y, 1.0), 0.0, 1.0)
		for c in cols + 1:
			var u := float(c) / cols
			var q := p + side * (u - 0.5) * width * spread - fd * back
			g.raw_vertex(q - origin, nrm, Color(1, 1, 1, 1), Vector2(u, fallen))
	for i in n - 1:
		for c in cols:
			var k := i * (cols + 1) + c
			g.quad(k, k + 1, k + cols + 2, k + cols + 1)
	return g.arrays()


## Overall horizontal direction of a fall path (away from the cliff).
static func fall_dir(path: PackedVector3Array) -> Vector3:
	var d := Vector3(path[path.size() - 1].x - path[0].x, 0, path[path.size() - 1].z - path[0].z)
	return d.normalized() if d.length() > 0.05 else Vector3(0, 0, 1)


static func _foam_disc(center: Vector3, r: float) -> Array:
	var g := GeoBuilder.new()
	var segs := 20
	var c := g.raw_vertex(center + Vector3(0, 0.06, 0), Vector3.UP, Color.WHITE, Vector2.ZERO)
	for k in segs + 1:
		var a := TAU * float(k) / segs
		g.raw_vertex(center + Vector3(cos(a) * r, 0.06, sin(a) * r), Vector3.UP, Color.WHITE, Vector2(cos(a), sin(a)))
	for k in segs:
		g.tri(c, c + 1 + k + 1, c + 1 + k)
	return g.arrays()


## Frozen fall: a wall of bulging ice columns of uneven length over a darker back curtain,
## icy bulges, icicles and a frozen plunge pool (all glossy kit ice).
static func _ice_cascade(kit: BuildingKit, path: PackedVector3Array, width: float, rng: RandomNumberGenerator, origin: Vector3) -> void:
	var n := path.size()
	var deep := Color(0.40, 0.64, 0.88).srgb_to_linear()
	var pale := Color(0.88, 0.95, 1.0).srgb_to_linear()
	var fd := fall_dir(path)
	var side := Vector3.UP.cross(fd).normalized()
	var gi := kit.g(&"ice")
	# back curtain (faces away from the cliff), widening downwards
	for i in n - 1:
		var p0 := path[i] - fd * 0.9
		var p1 := path[i + 1] - fd * 0.9
		var w0 := width * (0.6 + 0.3 * float(i) / n)
		var w1 := width * (0.6 + 0.3 * float(i + 1) / n)
		gi.flat_quad(p1 - side * w1 - origin, p1 + side * w1 - origin, p0 + side * w0 - origin, p0 - side * w0 - origin, deep * 0.8)
	# columns
	var cols := 11
	for c in cols:
		var u := float(c) / (cols - 1) - 0.5
		var stop := n - 1 - rng.randi_range(0, n / 4)
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var phase := rng.randf() * TAU
		for i in range(1, stop + 1, 2):
			var f := float(i) / n
			var p := path[i] + side * u * width * (1.1 + 0.4 * f) + fd * rng.randf_range(-0.2, 0.3)
			pts.append(p - origin)
			radii.append((0.75 + 0.45 * sin(f * 9.0 + phase) + rng.randf_range(0.0, 0.4)) * (1.0 - 0.5 * absf(u)))
		if pts.size() >= 2:
			gi.tube(pts, radii, 7, pale, deep)
			var tip: Vector3 = pts[pts.size() - 1]
			gi.cone(tip, tip - Vector3(0, rng.randf_range(1.5, 4.0), 0), radii[radii.size() - 1] * 0.9, 6, deep, true)
	# frozen bulges where the water piled up
	for k in 14:
		var i := rng.randi_range(2, n - 2)
		var p := path[i] + side * rng.randf_range(-0.5, 0.5) * width + fd * 0.6 - origin
		gi.blob(p, rng.randf_range(0.9, 1.8), 1, pale.lerp(deep, rng.randf_range(0.2, 0.7)), rng, 0.2, Vector3(1.3, 0.8, 0.7))
	# icicles along the lip
	for k in 16:
		var p := path[1] + side * rng.randf_range(-0.6, 0.6) * width + fd * 0.4 - origin
		gi.cone(p, p - Vector3(0, rng.randf_range(1.0, 3.5), 0), rng.randf_range(0.18, 0.4), 5, pale, true)
	var pl := path[n - 1] - origin
	gi.blob(pl + Vector3(0, -0.2, 0), width * 0.8, 1, pale, rng, 0.15, Vector3(1.4, 0.25, 1.2))


# --- main thread -----------------------------------------------------------------------------

static func sheet_material(layer: int, height: float) -> ShaderMaterial:
	var key := "%d|%d" % [layer, int(height / 10.0)]
	if _sheet_mats.has(key):
		return _sheet_mats[key]
	WorldShaderGlobals.ensure()
	var m := ShaderMaterial.new()
	m.shader = SHEET_SHADER
	m.set_shader_parameter(&"noise_tex", NOISE)
	m.set_shader_parameter(&"fall_height", maxf(height, 5.0))
	if layer == 1:
		m.set_shader_parameter(&"speed", 5.5)
		m.set_shader_parameter(&"deep_color", Color(0.20, 0.42, 0.55))
		m.set_shader_parameter(&"opacity", 0.75)
		m.set_shader_parameter(&"streak_scale", 1.4)
		m.render_priority = -1
	_sheet_mats[key] = m
	return m


static func foam_material() -> ShaderMaterial:
	if _foam_mat == null:
		WorldShaderGlobals.ensure()
		_foam_mat = ShaderMaterial.new()
		_foam_mat.shader = FOAM_SHADER
		_foam_mat.set_shader_parameter(&"noise_tex", NOISE)
	return _foam_mat


static func mist_material() -> ShaderMaterial:
	if _mist_mat == null:
		WorldShaderGlobals.ensure()
		_mist_mat = ShaderMaterial.new()
		_mist_mat.shader = MIST_SHADER
		_mist_mat.set_shader_parameter(&"tint", Color(0.94, 0.97, 1.0, 0.8))
	return _mist_mat


## Creates the node (sheets, foam, rocks, mist, sound) from build() output. `parent` receives it;
## `loops` collects Audio loop ids (stopped by the caller on release). Main thread.
static func instantiate(data: Dictionary, parent: Node3D, loops: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Waterfall"
	parent.add_child(root)
	root.global_position = data["origin"]
	var kit_res: KitResult = data["kit"]
	root.add_child(kit_res.instantiate({"name": "Rocks", "lights": false}))
	if data["frozen"]:
		return root
	for s: Array in data["sheets"]:
		var mi := MeshInstance3D.new()
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s[0])
		mi.mesh = m
		mi.material_override = sheet_material(s[1], data["height"])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 2600.0
		root.add_child(mi)
	if data.has("foam"):
		var fm := MeshInstance3D.new()
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["foam"])
		fm.mesh = am
		fm.material_override = foam_material()
		fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fm.visibility_range_end = 900.0
		root.add_child(fm)
	var plunge: Vector3 = data["plunge"]
	root.add_child(make_mist(plunge - (data["origin"] as Vector3), float(data["height"])))
	var id := Audio.play_loop(&"amb_rain", null, 3.0, 2.0, plunge)
	if id > 0:
		Audio.set_loop_pitch(id, 0.62)
		loops.append(id)
	return root


## Mist puffs rising from a plunge point (local position), count scaled by effects_scale.
static func make_mist(local_pos: Vector3, height: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Mist"
	p.amount = maxi(int(34.0 * Settings.effects_scale()), 8)
	p.lifetime = 4.5
	p.preprocess = 4.0
	p.position = local_pos + Vector3(0, 1.0, 0)
	p.local_coords = false
	p.visibility_range_end = 450.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 3.0
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0 + height * 0.02
	pm.gravity = Vector3(0, 0.4, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.2
	pm.scale_min = 4.0
	pm.scale_max = 8.0 + height * 0.04
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	grad.add_point(0.2, Color(1, 1, 1, 0.8))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = mist_material()
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 40, 40))
	return p
