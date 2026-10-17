class_name AirSheets
extends RefCounted
## Meshes and materials for the Air technique visuals (src/fx/air): wind sheets
## drawn with fx_air_sheet.gdshader. Meshes are cached per shape.
##
##   var m := AirSheets.material({"streaks": 9.0, "twist": 2.0, "rim": 0.6})
##   mi.mesh = AirSheets.funnel(9.0, 0.8, 3.6)          # tornado: narrow at the ground
##   mi.mesh = AirSheets.band(1.2, 0.35)                 # shockwave wall, radius 1

const SHADER := preload("res://src/fx/air/fx_air_sheet.gdshader")

static var _cache: Dictionary = {}


## A new material instance (each effect animates its own uniforms).
## opts: any fx_air_sheet uniform (opacity, streaks, twist, scroll, body, rim, fade_bottom,
## fade_top, near_fade, line_sharp, core_color, edge_color).
static func material(opts: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"noise_tex", FxLib.noise_texture(&"smooth"))
	for k: String in opts:
		m.set_shader_parameter(StringName(k), opts[k])
	return m


## Surface of revolution from y = 0 (radius r0) to y = height (radius r1), bulging by
## `belly` in the middle. UV.x around (wraps twice so streaks stay crisp), UV.y up.
static func funnel(height: float, r0: float, r1: float, belly: float = 0.0, around: int = 28, rings: int = 12) -> ArrayMesh:
	var key := "funnel_%.2f_%.2f_%.2f_%.2f_%d_%d" % [height, r0, r1, belly, around, rings]
	if _cache.has(key):
		return _cache[key]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in rings + 1:
		var v := float(j) / rings
		# Tornado profile: tight at the ground, flaring toward the top.
		var r := lerpf(r0, r1, v * v * 0.7 + v * 0.3) + belly * sin(PI * v)
		for i in around + 1:
			var u := float(i) / around
			var a := u * TAU
			var dir := Vector3(cos(a), 0.0, sin(a))
			verts.append(dir * r + Vector3.UP * v * height)
			uvs.append(Vector2(u * 2.0, v))
			normals.append(dir)
	for j in rings:
		for i in around:
			var k := j * (around + 1) + i
			var k2 := k + around + 1
			idx.append_array([k, k2, k + 1, k + 1, k2, k2 + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_cache[key] = m
	return m


## Full ring wall at radius 1 (y 0..height, leaning out by `lean`): shockwave fronts.
static func band(height: float = 1.0, lean: float = 0.3, around: int = 40) -> ArrayMesh:
	return funnel(height, 1.0, 1.0 + lean, 0.0, around, 2)


## UV sphere of radius 1 (UV.x around, UV.y bottom 0 .. top 1).
static func sphere(around: int = 24, rings: int = 12) -> ArrayMesh:
	var key := "sphere_%d_%d" % [around, rings]
	if _cache.has(key):
		return _cache[key]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in rings + 1:
		var v := float(j) / rings
		var phi := PI * (v - 0.5)
		for i in around + 1:
			var u := float(i) / around
			var a := u * TAU
			var p := Vector3(cos(a) * cos(phi), sin(phi), sin(a) * cos(phi))
			verts.append(p)
			normals.append(p)
			uvs.append(Vector2(u * 2.0, v))
	for j in rings:
		for i in around:
			var k := j * (around + 1) + i
			var k2 := k + around + 1
			idx.append_array([k, k2, k + 1, k + 1, k2, k2 + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_cache[key] = m
	return m


## Crescent blade in the XZ plane: an arc of `arc` radians at radius 1 around -Z,
## `width` thick in the middle and pointed at both tips. UV.x along, UV.y across.
static func blade(arc: float = 2.0, width: float = 0.32, segments: int = 24) -> ArrayMesh:
	var key := "blade_%.2f_%.2f" % [arc, width]
	if _cache.has(key):
		return _cache[key]
	var pts := PackedVector3Array()
	var sides := PackedVector3Array()
	for i in segments + 1:
		var u := float(i) / segments
		var a := lerpf(-arc * 0.5, arc * 0.5, u)
		var dir := Vector3(sin(a), 0.0, -cos(a))
		var w := width * pow(sin(PI * u), 0.8)
		# Thicker toward the outer (leading) edge: a cutting crescent.
		pts.append(dir * (1.0 - w * 0.25))
		sides.append(dir * w * 0.5)
	var m := FxMeshes.strip(pts, sides)
	_cache[key] = m
	return m
