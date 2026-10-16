class_name QuestPropMeshes
extends RefCounted
## Small toon meshes for quest props (pickups, things to inspect), built once per kind from
## primitive meshes with the shared toon + ink outline materials (ToonMaterials), cached.
## Kinds: herb, net, crate, letter, bowl, float, glider, ember, incense, tablet, chest, bundle.

static var _cache: Dictionary = {}
static var _glint_mat: ShaderMaterial = null


## A Node3D with the prop's meshes (shared resources). Origin on the ground, faces -Z.
static func build(kind: StringName, tint: Color = Color(-1, 0, 0)) -> Node3D:
	var root := Node3D.new()
	root.name = "Prop_%s" % kind
	for part: Array in _parts(kind, tint):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.material_override = part[1]
		mi.transform = part[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if part.size() > 3 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = 90.0
		root.add_child(mi)
	return root


## Pulsing glint billboard (quest_glint.gdshader) so props read from afar.
static func glint(color: Color = Color(1.0, 0.85, 0.45), size: float = 0.9) -> MeshInstance3D:
	if _glint_mat == null:
		_glint_mat = ShaderMaterial.new()
		_glint_mat.shader = load("res://src/quests/quest_glint.gdshader") as Shader
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	var m := _glint_mat.duplicate() as ShaderMaterial
	m.set_shader_parameter(&"tint", color)
	mi.material_override = m
	mi.scale = Vector3.ONE * size
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 160.0
	return mi


static func _mat(c: Color) -> Material:
	var key := "mat_%s" % c.to_html()
	if not _cache.has(key):
		_cache[key] = ToonMaterials.make(c, {"rim": 0.25})
	return _cache[key]


static func _glow_mat(c: Color) -> Material:
	var key := "glow_%s" % c.to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 2.2
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_cache[key] = m
	return _cache[key]


static func _mesh(key: String, make: Callable) -> Mesh:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


static func _box(x: float, y: float, z: float) -> Mesh:
	return _mesh("box_%s_%s_%s" % [x, y, z], func() -> Mesh:
		var b := BoxMesh.new()
		b.size = Vector3(x, y, z)
		return b)


static func _cyl(r_top: float, r_bot: float, h: float, sides: int = 10) -> Mesh:
	return _mesh("cyl_%s_%s_%s_%d" % [r_top, r_bot, h, sides], func() -> Mesh:
		var c := CylinderMesh.new()
		c.top_radius = r_top
		c.bottom_radius = r_bot
		c.height = h
		c.radial_segments = sides
		c.rings = 1
		return c)


static func _sphere(r: float, h: float = -1.0) -> Mesh:
	return _mesh("sph_%s_%s" % [r, h], func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = r
		s.height = h if h > 0.0 else r * 2.0
		s.radial_segments = 12
		s.rings = 6
		return s)


static func _torus(inner: float, outer: float) -> Mesh:
	return _mesh("tor_%s_%s" % [inner, outer], func() -> Mesh:
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = 14
		t.ring_segments = 6
		return t)


static func _t(pos: Vector3, rot: Vector3 = Vector3.ZERO, s: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot * (PI / 180.0)).scaled(s), pos)


static func _parts(kind: StringName, tint: Color) -> Array:
	var c := tint if tint.r >= 0.0 else Color(0.72, 0.6, 0.42)
	match kind:
		&"herb":
			var g := tint if tint.r >= 0.0 else Color(0.55, 0.82, 0.68)
			var out: Array = []
			for i in 5:
				var a := TAU * i / 5.0
				out.append([_cyl(0.0, 0.07, 0.34, 6), _mat(g), _t(Vector3(cos(a) * 0.09, 0.15, sin(a) * 0.09), Vector3(sin(a) * 18.0, 0, cos(a) * 18.0))])
			out.append([_sphere(0.16, 0.12), _mat(g.darkened(0.35)), _t(Vector3(0, 0.03, 0))])
			return out
		&"net":
			return [[_sphere(0.36, 0.22), _mat(Color(0.62, 0.56, 0.44)), _t(Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1.4, 1, 1))],
				[_torus(0.12, 0.17), _mat(Color(0.84, 0.64, 0.40)), _t(Vector3(0.28, 0.2, 0.1), Vector3(70, 0, 0))],
				[_torus(0.12, 0.17), _mat(Color(0.84, 0.64, 0.40)), _t(Vector3(-0.3, 0.16, -0.12), Vector3(80, 30, 0))]]
		&"crate":
			return [[_box(0.7, 0.55, 0.55), _mat(Color(0.56, 0.40, 0.26)), _t(Vector3(0, 0.275, 0))],
				[_box(0.74, 0.08, 0.59), _mat(Color(0.36, 0.26, 0.18)), _t(Vector3(0, 0.5, 0))],
				[_box(0.08, 0.5, 0.6), _mat(Color(0.36, 0.26, 0.18)), _t(Vector3(0, 0.27, 0))]]
		&"letter":
			return [[_box(0.32, 0.03, 0.22), _mat(Color(0.94, 0.88, 0.72)), _t(Vector3(0, 0.02, 0), Vector3(0, 12, 0))],
				[_cyl(0.05, 0.05, 0.02, 10), _mat(Color(0.72, 0.16, 0.12)), _t(Vector3(0.02, 0.045, 0.0))]]
		&"bowl":
			return [[_cyl(0.24, 0.13, 0.14, 14), _mat(c if tint.r >= 0.0 else Color(0.52, 0.66, 0.84)), _t(Vector3(0, 0.07, 0))],
				[_cyl(0.2, 0.2, 0.02, 14), _mat(Color(0.88, 0.94, 1.0)), _t(Vector3(0, 0.13, 0))]]
		&"float":
			return [[_sphere(0.14, 0.24), _mat(Color(0.86, 0.62, 0.36)), _t(Vector3(0, 0.12, 0))],
				[_torus(0.03, 0.05), _mat(Color(0.5, 0.42, 0.32)), _t(Vector3(0, 0.25, 0))]]
		&"glider":
			return [[_cyl(0.025, 0.025, 1.8, 6), _mat(Color(0.62, 0.40, 0.22)), _t(Vector3(0, 0.05, 0), Vector3(90, 0, 10))],
				[_box(0.5, 0.02, 0.7), _mat(Color(0.96, 0.72, 0.30)), _t(Vector3(0.3, 0.07, 0.0), Vector3(0, 0, 4))],
				[_box(0.5, 0.02, 0.7), _mat(Color(0.96, 0.72, 0.30)), _t(Vector3(-0.3, 0.07, 0.0), Vector3(0, 0, -4))]]
		&"ember":
			return [[_box(0.5, 0.36, 0.5), _mat(Color(0.30, 0.26, 0.24)), _t(Vector3(0, 0.18, 0))],
				[_sphere(0.13), _glow_mat(Color(1.0, 0.5, 0.16)), _t(Vector3(0, 0.46, 0)), true]]
		&"incense":
			return [[_cyl(0.14, 0.18, 0.18, 10), _mat(Color(0.42, 0.36, 0.48)), _t(Vector3(0, 0.09, 0))],
				[_cyl(0.008, 0.008, 0.4, 4), _mat(Color(0.62, 0.32, 0.22)), _t(Vector3(0.03, 0.36, 0), Vector3(0, 0, 6))],
				[_cyl(0.008, 0.008, 0.36, 4), _mat(Color(0.62, 0.32, 0.22)), _t(Vector3(-0.03, 0.34, 0.02), Vector3(-5, 0, -4))]]
		&"tablet":
			return [[_box(0.8, 1.2, 0.18), _mat(Color(0.62, 0.62, 0.60)), _t(Vector3(0, 0.6, 0))],
				[_box(0.9, 0.12, 0.3), _mat(Color(0.48, 0.48, 0.46)), _t(Vector3(0, 0.06, 0))]]
		&"chest":
			return [[_box(0.8, 0.45, 0.5), _mat(Color(0.52, 0.22, 0.16)), _t(Vector3(0, 0.225, 0))],
				[_cyl(0.25, 0.25, 0.8, 10), _mat(Color(0.46, 0.18, 0.12)), _t(Vector3(0, 0.45, 0), Vector3(0, 0, 90), Vector3(1, 1, 0.98))],
				[_box(0.14, 0.14, 0.04), _mat(Color(0.86, 0.68, 0.26)), _t(Vector3(0, 0.42, -0.26))]]
	# bundle (default)
	return [[_sphere(0.26, 0.34), _mat(c), _t(Vector3(0, 0.17, 0))],
		[_torus(0.06, 0.09), _mat(c.darkened(0.3)), _t(Vector3(0, 0.33, 0))]]
