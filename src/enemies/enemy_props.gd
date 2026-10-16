class_name EnemyProps
extends RefCounted
## Toon weapon props for enemies, in the HumanoidRig prop convention (grip at the
## origin, handle along +Y; HumanoidRig.attach_prop orients them in the hand):
## club, knife, bow (with a live string + nocked arrow), shield (strapped to the
## forearm), quiver (back), plus the flying arrow / thrown knife visuals.
## RigProps names (sword, spear, hammer, staff) are passed through.
##
##   EnemyProps.attach(rig, &"bow", &"hand_l")
##   var bow := EnemyProps.find(rig, &"bow") as EnemyProps.Bow; bow.draw = 0.8

const NAMES: PackedStringArray = ["club", "knife", "bow", "shield", "quiver"]
const WOOD := Color(0.5, 0.34, 0.2)
const DARK_WOOD := Color(0.3, 0.2, 0.13)
const METAL := Color(0.66, 0.68, 0.72)
const LEATHER := Color(0.42, 0.26, 0.15)
const RED := Color(0.62, 0.12, 0.08)
const GOLD := Color(0.84, 0.66, 0.26)

static var _meshes: Dictionary = {}
static var _mats: Dictionary = {}


## Attaches a prop to a rig socket. Returns the prop node (null if unknown).
static func attach(rig: HumanoidRig, prop: StringName, socket: StringName, faction: StringName = &"") -> Node3D:
	if rig == null:
		return null
	if RigProps.is_prop(prop):
		return rig.attach_prop(prop, socket)
	var node := make(prop, faction)
	if node == null:
		return null
	node.set_meta(&"enemy_prop", prop)
	if socket == &"back":
		var s := rig.get_socket(&"back")
		if s == null:
			return null
		s.add_child(node)
		node.transform = Transform3D(Basis(Vector3.BACK, 0.35), Vector3(0.12, -0.05, 0.12))
		return node
	return rig.attach_prop(node, socket)


## The first attached prop of a kind (bow, shield ...) on the rig, or null.
static func find(rig: HumanoidRig, prop: StringName) -> Node3D:
	if rig == null:
		return null
	for s: StringName in [&"hand_l", &"hand_r", &"back"]:
		var n := rig.get_prop(s) if s != &"back" else null
		if n != null and n.get_meta(&"enemy_prop", &"") == prop:
			return n
		if s == &"back":
			var sock := rig.get_socket(&"back")
			if sock:
				for c in sock.get_children():
					if c is Node3D and c.get_meta(&"enemy_prop", &"") == prop:
						return c
	return null


static func make(prop: StringName, faction: StringName = &"") -> Node3D:
	match prop:
		&"club":
			var n := Node3D.new()
			n.name = "Club"
			_part(n, _cyl(0.022, 0.026, 0.5), Vector3(0, 0.12, 0), WOOD)
			_part(n, _cyl(0.06, 0.04, 0.34), Vector3(0, 0.5, 0), DARK_WOOD)
			for k in 3:
				var stud := _part(n, _box(Vector3(0.03, 0.03, 0.03)), Vector3(0.055 * cos(k * 2.1), 0.56 + k * 0.05, 0.055 * sin(k * 2.1)), METAL)
				stud.rotation = Vector3(0.4, k * 1.3, 0.2)
			_part(n, _cyl(0.03, 0.03, 0.06), Vector3(0, -0.1, 0), LEATHER)
			return n
		&"knife":
			var n := Node3D.new()
			n.name = "Knife"
			_part(n, _cyl(0.016, 0.016, 0.13), Vector3(0, 0.0, 0), LEATHER)
			_part(n, _box(Vector3(0.07, 0.015, 0.02)), Vector3(0, 0.075, 0), METAL)
			var blade := _part(n, _box(Vector3(0.035, 0.26, 0.006)), Vector3(0, 0.21, 0), METAL)
			blade.material_override = _mat(METAL, true)
			return n
		&"bow":
			var b := Bow.new()
			b.name = "Bow"
			b.tint = RED if faction == &"fire_nation" else DARK_WOOD
			return b
		&"shield":
			var n := Node3D.new()
			n.name = "Shield"
			# Strapped to the forearm: face normal along -X (back of the left hand), centre toward the elbow.
			var face := MeshInstance3D.new()
			face.mesh = _disc(0.36, 0.06)
			face.material_override = _mat(RED if faction == &"fire_nation" else WOOD, true)
			face.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.07, 0.0, 0.1))
			n.add_child(face)
			var rim := MeshInstance3D.new()
			rim.mesh = _torus(0.36, 0.022)
			rim.material_override = _mat(GOLD if faction == &"fire_nation" else METAL, false)
			rim.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.1, 0.0, 0.1))
			n.add_child(rim)
			var boss := MeshInstance3D.new()
			boss.mesh = _sphere(0.07)
			boss.material_override = _mat(GOLD if faction == &"fire_nation" else METAL, false)
			boss.position = Vector3(-0.13, 0.0, 0.1)
			n.add_child(boss)
			if faction == &"fire_nation":
				# Flame emblem: three gold blades on the face.
				for k in 3:
					var fl := MeshInstance3D.new()
					fl.mesh = _box(Vector3(0.012, 0.2 - k * 0.04, 0.05))
					fl.material_override = _mat(GOLD, false)
					fl.transform = Transform3D(Basis(Vector3.RIGHT, (k - 1) * 0.5), Vector3(-0.105, 0.04, 0.1 + (k - 1) * 0.05))
					n.add_child(fl)
			return n
		&"quiver":
			var n := Node3D.new()
			n.name = "Quiver"
			_part(n, _cyl(0.07, 0.06, 0.55), Vector3(0, 0, 0), LEATHER)
			for k in 4:
				var a := k * 1.6
				_part(n, _cyl(0.006, 0.006, 0.2), Vector3(0.03 * cos(a), 0.36, 0.03 * sin(a)), WOOD)
				_part(n, _box(Vector3(0.04, 0.08, 0.005)), Vector3(0.03 * cos(a), 0.45, 0.03 * sin(a)), Color(0.92, 0.88, 0.8))
			return n
	push_warning("EnemyProps: unknown prop '%s'" % prop)
	return null


## A flying arrow visual (-Z = tip direction; BendingProjectile aligns it).
static func arrow_visual(from: Node) -> Node3D:
	var n := Node3D.new()
	n.name = "Arrow"
	var shaft := MeshInstance3D.new()
	shaft.mesh = _cyl(0.008, 0.008, 0.75)
	shaft.material_override = _mat(WOOD, false)
	shaft.rotation = Vector3(PI * 0.5, 0, 0)
	n.add_child(shaft)
	var tip := MeshInstance3D.new()
	tip.mesh = _cone(0.02, 0.08)
	tip.material_override = _mat(METAL, false)
	tip.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -0.4))
	n.add_child(tip)
	for k in 2:
		var f := MeshInstance3D.new()
		f.mesh = _box(Vector3(0.004, 0.05, 0.1))
		f.material_override = _mat(Color(0.92, 0.88, 0.8), false)
		f.transform = Transform3D(Basis(Vector3.BACK, k * PI * 0.5), Vector3(0, 0, 0.32))
		n.add_child(f)
	FxLib.root(from).add_child(n)
	return n


## A spinning thrown knife visual.
static func knife_visual(from: Node) -> Node3D:
	var n := make(&"knife")
	FxLib.root(from).add_child(n)
	return n


# --- the bow (live string) ----------------------------------------------------------------------

## Recurve bow in grip space; `draw` (0..1) pulls the string to `draw_point` (world)
## and shows a nocked arrow while drawn.
class Bow extends Node3D:
	var tint := DARK_WOOD
	var draw := 0.0
	var draw_point := Vector3.INF
	var show_arrow := false
	var _string_a: MeshInstance3D
	var _string_b: MeshInstance3D
	var _arrow: Node3D
	var _tip_top := Vector3(0, 0.62, -0.06)
	var _tip_bot := Vector3(0, -0.62, -0.06)

	func _ready() -> void:
		# Limbs: three segments per side bending toward -Z (away from the archer).
		var pts := [Vector3(0, 0.0, 0.02), Vector3(0, 0.22, 0.0), Vector3(0, 0.44, -0.05), Vector3(0, 0.62, -0.06)]
		for side: float in [1.0, -1.0]:
			for i in 3:
				var a: Vector3 = pts[i] * Vector3(1, side, 1)
				var b: Vector3 = pts[i + 1] * Vector3(1, side, 1)
				var seg := MeshInstance3D.new()
				seg.mesh = EnemyProps._cyl(0.022 - i * 0.005, 0.024 - i * 0.005, 1.0)
				seg.material_override = EnemyProps._mat(tint, false)
				seg.transform = EnemyProps.segment_xform(a, b)
				add_child(seg)
		var grip := MeshInstance3D.new()
		grip.mesh = EnemyProps._cyl(0.03, 0.03, 0.12)
		grip.material_override = EnemyProps._mat(LEATHER, false)
		add_child(grip)
		for i in 2:
			var s := MeshInstance3D.new()
			s.mesh = EnemyProps._cyl(0.004, 0.004, 1.0)
			s.material_override = EnemyProps._mat(Color(0.9, 0.86, 0.78), false)
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(s)
			if i == 0:
				_string_a = s
			else:
				_string_b = s
		_arrow = Node3D.new()
		var shaft := MeshInstance3D.new()
		shaft.mesh = EnemyProps._cyl(0.007, 0.007, 0.72)
		shaft.material_override = EnemyProps._mat(WOOD, false)
		_arrow.add_child(shaft)
		var tip := MeshInstance3D.new()
		tip.mesh = EnemyProps._cone(0.018, 0.07)
		tip.material_override = EnemyProps._mat(METAL, false)
		tip.position = Vector3(0, 0.39, 0)
		_arrow.add_child(tip)
		_arrow.visible = false
		add_child(_arrow)
		_update_string()

	func _process(_delta: float) -> void:
		_update_string()

	func _update_string() -> void:
		var nock := Vector3(0, 0, -0.04)
		if draw > 0.01 and draw_point.is_finite():
			var local := global_transform.affine_inverse() * draw_point
			nock = nock.lerp(local, clampf(draw, 0.0, 1.0))
		if _string_a:
			_string_a.transform = EnemyProps.segment_xform(_tip_top, nock)
			_string_b.transform = EnemyProps.segment_xform(_tip_bot, nock)
		if _arrow:
			_arrow.visible = show_arrow
			if show_arrow:
				# From the nock through the grip, tip beyond the bow.
				var dir := (Vector3(0, 0, 0.0) - nock)
				if dir.length_squared() < 1e-4:
					dir = Vector3(0, 0, -1)
				_arrow.transform = Transform3D(EnemyProps.dir_basis(dir.normalized()), nock + dir.normalized() * 0.36)

	## World position of the nocked arrow tip (projectile spawn).
	func arrow_tip() -> Vector3:
		return global_transform * Vector3(0, 0, -0.12)


# --- mesh helpers ---------------------------------------------------------------------------------

## Transform placing a unit-height Y cylinder between a and b.
static func segment_xform(a: Vector3, b: Vector3) -> Transform3D:
	var d := b - a
	var l := d.length()
	if l < 1e-4:
		return Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.001, 1)), a)
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y * l, z), (a + b) * 0.5)


## Orthonormal basis whose +Y is `y` (unit).
static func dir_basis(y: Vector3) -> Basis:
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y).normalized())


static func _mat(c: Color, outline: bool) -> Material:
	var key := "%s_%s" % [c.to_html(), outline]
	if not _mats.has(key):
		_mats[key] = ToonMaterials.make(c, {"outline_width": 0.7} if outline else {"outline": false})
	return _mats[key]


static func _part(parent: Node3D, mesh: Mesh, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(col, true)
	parent.add_child(mi)
	return mi


static func _cyl(r_top: float, r_bot: float, h: float) -> Mesh:
	var key := "cyl%.3f_%.3f_%.3f" % [r_top, r_bot, h]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = r_top
		m.bottom_radius = r_bot
		m.height = h
		m.radial_segments = 8
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func _cone(r: float, h: float) -> Mesh:
	var key := "cone%.3f_%.3f" % [r, h]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = 0.001
		m.bottom_radius = r
		m.height = h
		m.radial_segments = 8
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func _box(size: Vector3) -> Mesh:
	var key := "box%s" % size
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func _sphere(r: float) -> Mesh:
	var key := "sph%.3f" % r
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 1.4
		m.radial_segments = 10
		m.rings = 5
		_meshes[key] = m
	return _meshes[key]


## Flat disc (cylinder) of radius r and thickness t, axis +Y.
static func _disc(r: float, t: float) -> Mesh:
	var key := "disc%.3f_%.3f" % [r, t]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = r * 0.92
		m.bottom_radius = r
		m.height = t
		m.radial_segments = 16
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func _torus(r: float, t: float) -> Mesh:
	var key := "tor%.3f_%.3f" % [r, t]
	if not _meshes.has(key):
		var m := TorusMesh.new()
		m.inner_radius = r - t
		m.outer_radius = r + t
		m.rings = 18
		m.ring_segments = 5
		_meshes[key] = m
	return _meshes[key]
