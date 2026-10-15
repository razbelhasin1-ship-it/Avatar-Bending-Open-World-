class_name RigProps
extends RefCounted
## Simple toon props for hands and back: staff (air glider staff), spear,
## hammer, broom, fishing_rod, basket, sword, lantern. Prop space: the grip is
## at the origin and the handle runs along +Y. HumanoidRig.attach_prop()
## orients +Y along the thumb side of the gripping hand.

const NAMES: PackedStringArray = ["staff", "spear", "hammer", "broom", "fishing_rod", "basket", "sword", "lantern"]

const WOOD := Color(0.55, 0.38, 0.22)
const DARK_WOOD := Color(0.36, 0.24, 0.15)
const METAL := Color(0.62, 0.64, 0.68)
const STRAW := Color(0.86, 0.74, 0.44)

static var _mesh_cache: Dictionary = {}


static func is_prop(prop_name: StringName) -> bool:
	return NAMES.has(String(prop_name))


## Builds a prop node (meshes are shared per shape/size).
static func make(prop_name: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = "Prop_%s" % prop_name
	match String(prop_name):
		"staff":
			_cyl(root, 0.017, 0.017, 1.75, Vector3(0, 0.2, 0), WOOD)
			_cyl(root, 0.03, 0.022, 0.12, Vector3(0, 1.1, 0), Color(0.95, 0.55, 0.16))
			_box(root, Vector3(0.012, 0.32, 0.09), Vector3(0, 0.98, 0.0), Color(0.92, 0.82, 0.55))
			_box(root, Vector3(0.012, 0.22, 0.09), Vector3(0, -0.6, 0.0), Color(0.92, 0.82, 0.55))
		"spear":
			_cyl(root, 0.016, 0.016, 2.17, Vector3(0, 0.235, 0), DARK_WOOD)
			_cone(root, 0.035, 0.22, Vector3(0, 1.41, 0), METAL)
			_cyl(root, 0.026, 0.026, 0.05, Vector3(0, 1.28, 0), Color(0.7, 0.18, 0.12))
		"hammer":
			_cyl(root, 0.016, 0.016, 0.42, Vector3(0, 0.1, 0), WOOD)
			_box(root, Vector3(0.16, 0.07, 0.07), Vector3(0, 0.3, 0), METAL)
		"broom":
			_cyl(root, 0.015, 0.015, 1.2, Vector3(0, 0.1, 0), WOOD)
			_cone(root, 0.12, 0.38, Vector3(0, -0.6, 0), STRAW, true)
		"fishing_rod":
			_cyl(root, 0.012, 0.005, 2.2, Vector3(0, 0.95, 0), Color(0.6, 0.5, 0.3))
		"basket":
			_cyl(root, 0.17, 0.13, 0.2, Vector3(0, 0.0, -0.15), STRAW)
			_cyl(root, 0.15, 0.15, 0.02, Vector3(0, 0.1, -0.15), Color(0.5, 0.65, 0.3))
		"sword":
			_cyl(root, 0.016, 0.016, 0.2, Vector3(0, 0.0, 0), Color(0.2, 0.15, 0.12))
			_box(root, Vector3(0.12, 0.02, 0.03), Vector3(0, 0.11, 0), Color(0.85, 0.7, 0.3))
			_box(root, Vector3(0.05, 0.62, 0.008), Vector3(0, 0.43, 0), METAL)
		"lantern":
			_cyl(root, 0.006, 0.006, 0.18, Vector3(0, 0.0, 0), DARK_WOOD)
			_sphere(root, 0.1, Vector3(0, -0.2, 0), Color(0.95, 0.35, 0.18), Color(1.0, 0.55, 0.2))
		_:
			push_warning("RigProps: unknown prop '%s'" % prop_name)
	return root


static func _mi(parent: Node3D, mesh: Mesh, pos: Vector3, col: Color, glow: Color = Color(0, 0, 0)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	var opts := {"outline_width": 0.8}
	if glow != Color(0, 0, 0):
		opts["emission"] = glow
		opts["emission_energy"] = 1.5
	mi.material_override = ToonMaterials.make(col, opts)
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, col: Color) -> void:
	var key := "cyl%.3f_%.3f_%.3f" % [r_top, r_bot, h]
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = r_top
		m.bottom_radius = r_bot
		m.height = h
		m.radial_segments = 10
		m.rings = 1
		_mesh_cache[key] = m
	_mi(parent, _mesh_cache[key], pos, col)


static func _cone(parent: Node3D, r: float, h: float, pos: Vector3, col: Color, down: bool = false) -> void:
	var key := "cone%.3f_%.3f_%s" % [r, h, down]
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = r if down else 0.002
		m.bottom_radius = 0.002 if down else r
		if down:
			m.top_radius = 0.02
			m.bottom_radius = r
		m.height = h
		m.radial_segments = 10
		_mesh_cache[key] = m
	_mi(parent, _mesh_cache[key], pos, col)


static func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> void:
	var key := "box%s" % size
	if not _mesh_cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_mesh_cache[key] = m
	_mi(parent, _mesh_cache[key], pos, col)


static func _sphere(parent: Node3D, r: float, pos: Vector3, col: Color, glow: Color) -> void:
	var key := "sph%.3f" % r
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.2
		m.radial_segments = 12
		m.rings = 6
		_mesh_cache[key] = m
	_mi(parent, _mesh_cache[key], pos, col, glow)
