class_name WaterSystem
extends Node3D
## World water: a camera-following ocean disc (dense near the camera, kilometres of coarse rings
## to the horizon), lake surfaces and Water Tribe canal surfaces built from WorldData records,
## splash ripples + spray for bending, and regional water colours.
##
## Gameplay never needs these meshes: water presence/levels come from WorldData. The visible
## ocean surface (with swell) is available from `surface_height(x, z)`.

const SHADER := preload("res://assets/shaders/world/water.gdshader")
const WATER_NRM := preload("res://assets/textures/world/water_nrm.png")
const NOISE_TEX := preload("res://assets/textures/world/noise.png")
const MAX_RIPPLES := 16

## Regional water colours: [shallow, deep] (sRGB).
const REGION_COLORS := {
	&"water_tribe": [Color(0.28, 0.56, 0.66), Color(0.035, 0.13, 0.25)],
	&"earth_kingdom": [Color(0.22, 0.60, 0.58), Color(0.03, 0.16, 0.29)],
	&"fire_nation": [Color(0.14, 0.70, 0.66), Color(0.02, 0.19, 0.33)],
	&"air_temple": [Color(0.24, 0.62, 0.72), Color(0.04, 0.17, 0.35)],
	&"wilds": [Color(0.22, 0.60, 0.60), Color(0.03, 0.16, 0.30)],
	&"ocean": [Color(0.20, 0.60, 0.64), Color(0.03, 0.15, 0.30)],
}

var ocean_material: ShaderMaterial
var inland_material: ShaderMaterial
var ocean: MeshInstance3D
var inland_root: Node3D
var spray: BurstPool
var waves := WaterWaves.new()
var wave_scale: float = 0.6

var _ripples: Array[Vector4] = []
var _next_ripple := 0
var _time := 0.0


func _ready() -> void:
	WorldShaderGlobals.ensure()
	_ripples.resize(MAX_RIPPLES)
	_ripples.fill(Vector4.ZERO)
	ocean_material = _make_material(false)
	inland_material = _make_material(true)
	inland_material.set_shader_parameter(&"depth_scale", 3.5)
	inland_material.set_shader_parameter(&"shallow_color", Color(0.30, 0.56, 0.48))
	inland_material.set_shader_parameter(&"deep_color", Color(0.05, 0.19, 0.22))
	inland_material.set_shader_parameter(&"foam_depth", 0.6)
	inland_material.set_shader_parameter(&"normal_strength", 0.4)
	inland_material.set_shader_parameter(&"wave_params", Vector4(0.0, 0.0, 1.0, 1.0))
	ocean = MeshInstance3D.new()
	ocean.name = "Ocean"
	# phones: 64 radial segments (~15k triangles instead of ~24k, perf_polish); the waves fade
	# out by 300 m there anyway
	ocean.mesh = build_ocean_mesh(64 if Settings.detail_level() == 0 else 96, 30000.0)
	ocean.material_override = ocean_material
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean.custom_aabb = AABB(Vector3(-30000, -4, -30000), Vector3(60000, 8, 60000))
	add_child(ocean)
	inland_root = build_inland_water(inland_material)
	add_child(inland_root)
	spray = BurstPool.new()
	spray.name = "Spray"
	add_child(spray)
	spray.setup(8, 40, 1.4, _spray_process(), BurstPool.soft_quad(0.22, Color(0.92, 0.97, 1.0, 0.85), 0.25))
	Events.graphics_settings_changed.connect(_apply_quality)
	_apply_quality()


func _make_material(inland: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.render_priority = 1
	WorldData.apply_height_uniforms(m)
	m.set_shader_parameter(&"has_world", WorldData.has_world_data())
	m.set_shader_parameter(&"inland", inland)
	m.set_shader_parameter(&"water_nrm", WATER_NRM)
	m.set_shader_parameter(&"noise_tex", NOISE_TEX)
	return m


func _apply_quality() -> void:
	# screen refraction + scene-depth soft edges need the Forward+/Mobile depth/screen copies;
	# the Compatibility renderer falls back to the heightmap water column (same colours/foam)
	var screen_ok := not Settings.is_compatibility_renderer()
	for m in [ocean_material, inland_material]:
		m.set_shader_parameter(&"use_screen", screen_ok)
		m.set_shader_parameter(&"wave_fade_distance", [300.0, 500.0, 700.0, 1000.0][Settings.detail_level()])


## Per-frame update: follow the camera, upload ripples and wave settings.
func update(cam_pos: Vector3, delta: float) -> void:
	_time += delta
	ocean.global_position = Vector3(cam_pos.x, 0.0, cam_pos.z)
	waves.params = Vector4(wave_scale, 0.75, 1.0, 1.0)
	waves.wind_direction = WorldShaderGlobals.get_value(&"wind_direction") if WorldShaderGlobals.get_value(&"wind_direction") != null else Vector2(0.8, 0.6)
	ocean_material.set_shader_parameter(&"wave_params", waves.params)


## Blends the regional water colours (region id -> weight).
func set_region_weights(weights: Dictionary) -> void:
	var sh := Color(0, 0, 0, 0)
	var dp := Color(0, 0, 0, 0)
	var total := 0.0
	for r: StringName in weights:
		var w: float = weights[r]
		if w <= 0.0 or not REGION_COLORS.has(r):
			continue
		sh += (REGION_COLORS[r][0] as Color) * w
		dp += (REGION_COLORS[r][1] as Color) * w
		total += w
	if total <= 0.0:
		return
	ocean_material.set_shader_parameter(&"shallow_color", sh / total)
	ocean_material.set_shader_parameter(&"deep_color", dp / total)


## Splash ring + foam + spray at a water surface point. `strength` 0.2 (pebble) .. 3 (boulder,
## water surge). Returns false when no water is there.
func splash(pos: Vector3, strength: float) -> bool:
	var level := WorldData.get_water_height(pos.x, pos.z)
	if level == -INF:
		return false
	var t := float(WorldShaderGlobals.get_value(&"world_time"))
	_ripples[_next_ripple] = Vector4(pos.x, pos.z, t, clampf(strength, 0.05, 3.0))
	_next_ripple = (_next_ripple + 1) % MAX_RIPPLES
	var arr := PackedVector4Array(_ripples)
	ocean_material.set_shader_parameter(&"ripples", arr)
	inland_material.set_shader_parameter(&"ripples", arr)
	spray.fire(Vector3(pos.x, level + 0.05, pos.z), clampf(0.6 + strength * 0.5, 0.4, 2.5))
	return true


## Visible water surface height at x/z: WorldData level plus the ocean swell (-INF = no water).
func surface_height(x: float, z: float) -> float:
	var level := WorldData.get_water_height(x, z)
	if level == -INF:
		return level
	if absf(level - WorldConstants.SEA_LEVEL) > 0.01:
		return level   # lakes and canals are calm
	var depth := level - WorldData.get_height(x, z)
	var mask := smoothstep(0.3, 6.0, depth)
	return level + waves.height_at(x, z, float(WorldShaderGlobals.get_value(&"world_time")), mask)


func _spray_process() -> ParticleProcessMaterial:
	var p := ParticleProcessMaterial.new()
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3(0, 1, 0)
	p.spread = 35.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -9.8, 0)
	p.damping_min = 0.5
	p.damping_max = 1.5
	p.scale_min = 0.5
	p.scale_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(1, 0.2))
	var ct := CurveTexture.new()
	ct.curve = curve
	p.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	p.color_ramp = gt
	return p


# --- mesh builders -------------------------------------------------------------------------------

## Radial ocean disc: dense rings near the centre growing geometrically to `radius`.
static func build_ocean_mesh(segments: int, radius: float) -> ArrayMesh:
	var radii := PackedFloat32Array([0.0])
	var r := 0.0
	while r < 36.0:
		r += 1.2
		radii.append(r)
	while r < radius:
		r *= 1.075
		radii.append(minf(r, radius))
	var verts := PackedVector3Array()
	verts.append(Vector3.ZERO)
	for k in range(1, radii.size()):
		for s in segments:
			var a := TAU * float(s) / float(segments)
			verts.append(Vector3(cos(a) * radii[k], 0.0, sin(a) * radii[k]))
	var idx := PackedInt32Array()
	for s in segments:
		var b := 1 + (s + 1) % segments
		idx.append_array([0, 1 + s, b])
	for k in range(1, radii.size() - 1):
		var r0 := 1 + (k - 1) * segments
		var r1 := r0 + segments
		for s in segments:
			var s1 := (s + 1) % segments
			idx.append_array([r0 + s, r1 + s, r1 + s1, r0 + s, r1 + s1, r0 + s1])
	return _mesh(verts, idx, PackedColorArray())


## Lakes (unfrozen) and canals as flat meshes at their levels. Canal vertices carry the flow
## direction in COLOR (rg = dir * 0.5 + 0.5, b = speed).
static func build_inland_water(material: Material) -> Node3D:
	var root := Node3D.new()
	root.name = "InlandWater"
	for lk in WorldData.get_lakes():
		if lk["frozen"]:
			continue
		var poly: PackedVector2Array = lk["polygon"]
		var tris := Geometry2D.triangulate_polygon(poly)
		if tris.is_empty():
			continue
		var level := float(lk["level"])
		var c: Vector3 = lk["center"]
		var cc := Vector2(c.x, c.z)
		var verts := PackedVector3Array()
		for p in poly:
			# grow outwards: the banks hide the excess, no gap at the shoreline
			var q := cc + (p - cc) * 1.08 + (p - cc).normalized() * 3.0
			verts.append(Vector3(q.x, level, q.y))
		root.add_child(_instance(_mesh(verts, tris, PackedColorArray()), material, "Lake_%s" % lk["id"]))
	for canal in WorldData.get_canals():
		var pts: PackedVector2Array = canal["points"]
		if pts.size() < 2:
			continue
		var hw := float(canal["width"]) * 0.5 + 1.0
		var level := float(canal["level"])
		var verts := PackedVector3Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		for k in pts.size():
			var a := pts[maxi(k - 1, 0)]
			var b := pts[mini(k + 1, pts.size() - 1)]
			var d := (b - a).normalized()
			var nrm := Vector2(-d.y, d.x) * hw
			var flow := Color(d.x * 0.5 + 0.5, d.y * 0.5 + 0.5, 0.35)
			verts.append(Vector3(pts[k].x + nrm.x, level, pts[k].y + nrm.y))
			verts.append(Vector3(pts[k].x - nrm.x, level, pts[k].y - nrm.y))
			cols.append(flow)
			cols.append(flow)
			if k > 0:
				var o := (k - 1) * 2
				idx.append_array([o, o + 2, o + 1, o + 1, o + 2, o + 3])
		root.add_child(_instance(_mesh(verts, idx, cols), material, "Canal_%s" % canal["id"]))
	return root


static func _instance(mesh: Mesh, material: Material, n: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _mesh(verts: PackedVector3Array, idx: PackedInt32Array, cols: PackedColorArray) -> ArrayMesh:
	# clockwise from above = front face in Godot
	var fixed := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		if (b - a).cross(c - a).y > 0.0:
			fixed.append_array([idx[t], idx[t + 2], idx[t + 1]])
		else:
			fixed.append_array([idx[t], idx[t + 1], idx[t + 2]])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = fixed
	if not cols.is_empty():
		arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
