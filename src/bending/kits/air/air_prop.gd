class_name AirProp
extends RigidBody3D
## Small loose physics props the wind can knock about (and people kick): clay
## pots (they shatter on hard knocks), crates, baskets, barrels. Toon meshes built
## in code, budgeted per scene (Settings.detail_level), asleep until something
## touches them.
##
##   AirProp.spawn(parent, &"pot", pos, yaw)
##   AirProp.scatter(parent, center, 3.0, 6)            # a few random props on the ground
##   prop.wind(Vector3(6, 2, 0), at, by)                 # the wind_reactive contract
##
## Layer Layers.PROJECTILE (free for loose props: characters walk through them and
## kick them instead of being blocked), mask WORLD | CONSTRUCT | PROJECTILE.
## Group &"wind_reactive": any node may join it with
## `func wind(impulse: Vector3, at: Vector3, by: Node) -> void` (AirEnv.blow calls it).

signal shattered(prop: AirProp)

const KINDS := {
	&"pot": {"mass": 2.0, "radius": 0.24, "height": 0.52, "color": Color(0.74, 0.42, 0.26), "breaks": true, "break_dv": 6.5},
	&"crate": {"mass": 6.0, "size": Vector3(0.62, 0.55, 0.62), "color": Color(0.62, 0.46, 0.28), "breaks": false},
	&"basket": {"mass": 1.2, "radius": 0.3, "height": 0.36, "color": Color(0.82, 0.67, 0.38), "breaks": false},
	&"barrel": {"mass": 9.0, "radius": 0.3, "height": 0.8, "color": Color(0.5, 0.33, 0.2), "breaks": false},
}
## Live props per scene by detail level (low .. ultra).
const BUDGET := [10, 18, 28, 40]

static var live: Array[AirProp] = []

var kind: StringName = &"pot"
var breaks := false
var break_dv := 99.0
var size := 0.5
var _prev_v := Vector3.ZERO
var _tick := 0
var _broken := false


## A prop of `kind` at `pos` (feet on the ground). Null when the scene budget is full.
static func spawn(parent: Node, p_kind: StringName, pos: Vector3, yaw: float = 0.0) -> AirProp:
	_prune()
	if live.size() >= int(BUDGET[clampi(Settings.detail_level(), 0, 3)]) or parent == null:
		return null
	var p := AirProp.new()
	p.kind = p_kind if KINDS.has(p_kind) else &"pot"
	parent.add_child(p)
	p.global_position = pos + Vector3.UP * 0.02
	p.rotation.y = yaw
	return p


## Scatters `count` props within `radius` of `center` on the ground below it.
static func scatter(parent: Node, center: Vector3, radius: float, count: int, kinds: Array = [], seed_value: int = 7) -> Array[AirProp]:
	var out: Array[AirProp] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pool: Array = kinds if not kinds.is_empty() else [&"pot", &"pot", &"crate", &"basket", &"barrel"]
	for i in count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var p := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		p.y = WorldData.get_height(p.x, p.z) if parent == null or not parent.is_inside_tree() else _ground(parent, p)
		var prop := spawn(parent, pool[rng.randi() % pool.size()], p, rng.randf() * TAU)
		if prop != null:
			out.append(prop)
	return out


static func _ground(from: Node, p: Vector3) -> float:
	var space := (from as Node3D).get_world_3d().direct_space_state if from is Node3D else null
	if space == null:
		return WorldData.get_height(p.x, p.z)
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 8.0, Layers.WORLD)
	var r := space.intersect_ray(q)
	return (r["position"] as Vector3).y if not r.is_empty() else WorldData.get_height(p.x, p.z)


static func _prune() -> void:
	for i in range(live.size() - 1, -1, -1):
		if not is_instance_valid(live[i]) or not live[i].is_inside_tree():
			live.remove_at(i)


func _ready() -> void:
	add_to_group(&"wind_reactive")
	add_to_group(&"air_prop")
	collision_layer = Layers.PROJECTILE
	collision_mask = Layers.WORLD | Layers.CONSTRUCT | Layers.PROJECTILE
	var d: Dictionary = KINDS[kind]
	mass = float(d["mass"])
	breaks = bool(d.get("breaks", false))
	break_dv = float(d.get("break_dv", 99.0))
	can_sleep = true
	linear_damp = 0.15
	angular_damp = 0.6
	var pm := PhysicsMaterial.new()
	pm.friction = 0.85
	pm.bounce = 0.12
	physics_material_override = pm
	_build(d)
	live.append(self)


func _exit_tree() -> void:
	live.erase(self)


func _build(d: Dictionary) -> void:
	var col: Color = d["color"]
	var cs := CollisionShape3D.new()
	var mi := MeshInstance3D.new()
	var mat := ToonMaterials.make(col, {"vertex_color": true, "outline_width": 0.8})
	mi.material_override = mat
	match kind:
		&"crate":
			var s: Vector3 = d["size"]
			size = s.y
			var box := BoxShape3D.new()
			box.size = s
			cs.shape = box
			cs.position = Vector3(0, s.y * 0.5, 0)
			mi.mesh = _crate_mesh(s, col)
		_:
			var r := float(d["radius"])
			var h := float(d["height"])
			size = h
			var cyl := CylinderShape3D.new()
			cyl.radius = r * 0.92
			cyl.height = h
			cs.shape = cyl
			cs.position = Vector3(0, h * 0.5, 0)
			mi.mesh = _lathe_mesh(kind, r, h, col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.visibility_range_end = 70.0
	add_child(cs)
	add_child(mi)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, size * 0.4, 0)


## Wind contract: an impulse (N·s scaled by mass) applied at `at`; pots shatter when
## blasted hard enough.
func wind(impulse: Vector3, at: Vector3, _by: Node = null) -> void:
	if _broken:
		return
	sleeping = false
	var j := impulse * mass
	var off := at - global_position
	off = off.limit_length(size)
	apply_impulse(j, Vector3(off.x, clampf(off.y, size * 0.2, size * 0.9), off.z))
	if breaks and impulse.length() > break_dv * 1.6:
		shatter()


func shatter() -> void:
	if _broken:
		return
	_broken = true
	var c: Color = (KINDS[kind] as Dictionary)["color"]
	var p := global_position + Vector3.UP * size * 0.4
	FxDebris.spawn(self, p, {"kind": &"rock", "count": 8, "size": 0.12, "up": 3.5, "out": 2.5, "color": c, "dir": linear_velocity.normalized() * 0.6})
	FxBurst.spawn(self, &"dust", p, {"color": c.lightened(0.25), "count": 0.6})
	Audio.play_sfx(&"rock_debris", p, -6.0)
	shattered.emit(self)
	queue_free()


func _physics_process(_delta: float) -> void:
	var v := linear_velocity
	if breaks and not sleeping and (v - _prev_v).length() > break_dv:
		shatter()
		return
	_prev_v = v
	_tick += 1
	if _tick % 3 != 0:
		return
	_kick()


## Characters walking or running through the prop kick it along.
func _kick() -> void:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = size * 0.5 + 0.38
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * size * 0.5)
	q.collision_mask = Layers.PLAYER | Layers.ENEMY | Layers.NPC | Layers.COMPANION
	for r: Dictionary in space.intersect_shape(q, 4):
		var b := r.get("collider") as CharacterBody3D
		if b == null:
			continue
		var hv := Vector3(b.velocity.x, 0.0, b.velocity.z)
		var away := global_position - b.global_position
		away.y = 0.0
		if hv.length() < 0.8 and away.length() > 0.5:
			continue
		var push := hv * 0.55 + away.normalized() * 1.2 + Vector3.UP * minf(hv.length() * 0.18, 1.6)
		wind(push / maxf(mass, 0.5) * minf(mass, 3.0), global_position + Vector3.UP * size * 0.3, b)


static func _lathe_mesh(k: StringName, r: float, h: float, col: Color) -> ArrayMesh:
	# Profile (radius factor, height factor) bottom to top.
	var prof: Array = []
	match k:
		&"pot":
			prof = [[0.0, 0.0], [0.55, 0.0], [0.8, 0.12], [1.0, 0.42], [0.92, 0.66], [0.62, 0.84], [0.56, 0.92], [0.7, 1.0], [0.6, 1.0]]
		&"barrel":
			prof = [[0.0, 0.0], [0.86, 0.0], [0.94, 0.15], [1.0, 0.5], [0.94, 0.85], [0.86, 1.0], [0.0, 1.0]]
		_:
			prof = [[0.0, 0.0], [0.78, 0.0], [0.88, 0.2], [1.0, 0.85], [1.04, 1.0], [0.96, 1.0], [0.9, 0.9]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 14
	for i in prof.size() - 1:
		var a0: Array = prof[i]
		var a1: Array = prof[i + 1]
		for j in seg:
			var t0 := TAU * float(j) / seg
			var t1 := TAU * float(j + 1) / seg
			var c := _shade(k, col, float(a0[1]), j)
			var c2 := _shade(k, col, float(a1[1]), j)
			var p00 := Vector3(cos(t0) * r * float(a0[0]), h * float(a0[1]), sin(t0) * r * float(a0[0]))
			var p01 := Vector3(cos(t1) * r * float(a0[0]), h * float(a0[1]), sin(t1) * r * float(a0[0]))
			var p10 := Vector3(cos(t0) * r * float(a1[0]), h * float(a1[1]), sin(t0) * r * float(a1[0]))
			var p11 := Vector3(cos(t1) * r * float(a1[0]), h * float(a1[1]), sin(t1) * r * float(a1[0]))
			st.set_color(c)
			st.add_vertex(p00)
			st.set_color(c2)
			st.add_vertex(p10)
			st.set_color(c)
			st.add_vertex(p01)
			st.set_color(c)
			st.add_vertex(p01)
			st.set_color(c2)
			st.add_vertex(p10)
			st.set_color(c2)
			st.add_vertex(p11)
	st.generate_normals()
	return st.commit()


static func _shade(k: StringName, col: Color, y: float, j: int) -> Color:
	match k:
		&"barrel":
			# Iron hoops near the ends and the middle.
			if absf(y - 0.15) < 0.04 or absf(y - 0.85) < 0.04 or absf(y - 0.5) < 0.03:
				return Color(0.25, 0.22, 0.2)
			return col.darkened(0.1 if j % 2 == 0 else 0.0)
		&"basket":
			return col.darkened(0.14 if (j + int(y * 8.0)) % 2 == 0 else 0.0)
		&"pot":
			return col.lightened(0.18) if absf(y - 0.66) < 0.05 else col
	return col


static func _crate_mesh(s: Vector3, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bm := BoxMesh.new()
	bm.size = s
	var arr := bm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in idx.size():
		var v := verts[idx[i]] + Vector3(0, s.y * 0.5, 0)
		# Darker frame along the edges, planks in between.
		var edge_x := absf(v.x) > s.x * 0.42
		var edge_z := absf(v.z) > s.z * 0.42
		var edge_y := v.y < s.y * 0.08 or v.y > s.y * 0.92
		st.set_color(col.darkened(0.3) if (int(edge_x) + int(edge_z) + int(edge_y)) >= 2 else col)
		st.add_vertex(v)
	st.generate_normals()
	return st.commit()
