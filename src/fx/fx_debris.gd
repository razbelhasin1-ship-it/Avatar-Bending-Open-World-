class_name FxDebris
extends Node3D
## Pooled tumbling chunks (rock debris, ice shards, crumbling walls): a few real
## meshes simulated in script (ballistic + tumble + ground bounce + shrink), so
## they read as solid material on every renderer.
##
##   FxDebris.spawn(self, pos, {"kind": &"rock", "count": 8, "size": 0.25, "up": 6.0, "out": 4.0})
##   FxDebris.spawn(self, pos, {"kind": &"ice", "dir": hit_dir})

const MAX_CHUNKS := 12

var chunks: Array[MeshInstance3D] = []
var vel: Array[Vector3] = []
var spin: Array[Vector3] = []
var ground: Array[float] = []
var life := 0.0
var life_max := 1.4
var kind: StringName = &"rock"

static var _ice_mat: ShaderMaterial = null


static func spawn(from: Node, pos: Vector3, opts: Dictionary = {}) -> FxDebris:
	var k: StringName = opts.get("kind", &"rock")
	var d := FxLib.take(from, StringName("debris_" + String(k)), func() -> Node3D: return FxDebris._make(k)) as FxDebris
	d.global_position = pos
	d._launch(opts)
	return d


static func _make(k: StringName) -> FxDebris:
	var d := FxDebris.new()
	d.kind = k
	d.name = "Debris_%s" % k
	for i in MAX_CHUNKS:
		var m := MeshInstance3D.new()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if k == &"ice":
			m.mesh = FxMeshes.shard(0.5, 0.09, i % 4)
			m.material_override = ice_material()
		else:
			m.mesh = FxMeshes.rock(i % 6, 0)
			m.material_override = ToonMaterials.make(Color(0.56, 0.47, 0.37), {"outline": false, "vertex_color": true})
		d.add_child(m)
		d.chunks.append(m)
		d.vel.append(Vector3.ZERO)
		d.spin.append(Vector3.ZERO)
		d.ground.append(0.0)
	return d


static func ice_material() -> ShaderMaterial:
	if _ice_mat == null:
		_ice_mat = ShaderMaterial.new()
		_ice_mat.shader = preload("res://src/fx/shaders/fx_ice.gdshader")
		_ice_mat.next_pass = ToonMaterials.outline(0.7, Color(0.12, 0.22, 0.35))
	return _ice_mat


func _launch(opts: Dictionary) -> void:
	var count := clampi(int(round(float(opts.get("count", 7)) * clampf(FxLib.scale(), 0.5, 1.3))), 2, MAX_CHUNKS)
	var size := float(opts.get("size", 0.22))
	var up := float(opts.get("up", 5.5))
	var out := float(opts.get("out", 3.5))
	var dir: Vector3 = opts.get("dir", Vector3.ZERO)
	var color: Color = opts.get("color", Color(0.56, 0.47, 0.37))
	var gy := float(opts.get("ground_y", global_position.y - 0.05))
	life_max = float(opts.get("life", 1.5))
	life = life_max
	for i in MAX_CHUNKS:
		var m := chunks[i]
		m.visible = i < count
		if i >= count:
			continue
		var a := randf() * TAU
		var radial := Vector3(cos(a), 0.0, sin(a))
		var v := radial * out * randf_range(0.4, 1.0) + Vector3.UP * up * randf_range(0.55, 1.0)
		if dir != Vector3.ZERO:
			v += dir * out * randf_range(0.5, 1.2)
		vel[i] = v
		spin[i] = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
		ground[i] = gy
		var s := size * randf_range(0.55, 1.35)
		m.transform = Transform3D(Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU)).scaled(Vector3.ONE * s),
				radial * randf_range(0.0, 0.25) + Vector3.UP * randf_range(0.0, 0.2))
		if kind == &"rock" and m.material_override is ShaderMaterial:
			m.material_override = ToonMaterials.make(color, {"outline": false, "vertex_color": true})


func fx_reset() -> void:
	life = 0.0


func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		FxLib.release(self)
		return
	var shrink := clampf(life / minf(0.45, life_max), 0.0, 1.0)
	for i in chunks.size():
		var m := chunks[i]
		if not m.visible:
			continue
		vel[i].y -= 16.0 * delta
		var p := m.global_position + vel[i] * delta
		if p.y < ground[i] and vel[i].y < 0.0:
			p.y = ground[i]
			vel[i] = Vector3(vel[i].x * 0.45, -vel[i].y * 0.28, vel[i].z * 0.45)
			spin[i] *= 0.5
		m.global_position = p
		m.rotate_object_local(Vector3(1, 0, 0), spin[i].x * delta)
		m.rotate_object_local(Vector3(0, 1, 0), spin[i].y * delta)
		if shrink < 1.0:
			var b := m.basis.orthonormalized()
			var base_s := m.basis.get_scale().x
			m.basis = b.scaled(Vector3.ONE * maxf(0.001, base_s * exp(-delta * 7.0 * (1.0 - shrink))))
