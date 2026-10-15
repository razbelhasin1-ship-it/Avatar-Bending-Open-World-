class_name BurstPool
extends Node3D
## Pool of one-shot GPUParticles3D bursts (snow puffs, water spray). `fire()` reuses the
## emitter that finished longest ago, so the cost is bounded by `size` whatever the request
## rate. Amounts scale with Settings.effects_scale().

var size: int = 8
var base_amount: int = 24
var _emitters: Array[GPUParticles3D] = []
var _next := 0


## Builds `count` emitters sharing one process material and draw pass.
func setup(count: int, amount: int, lifetime: float, process: ParticleProcessMaterial, draw_mesh: Mesh) -> void:
	size = count
	base_amount = amount
	for e in _emitters:
		e.queue_free()
	_emitters.clear()
	var n := maxi(int(round(amount * Settings.effects_scale())), 4)
	for i in count:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.explosiveness = 0.92
		p.amount = n
		p.lifetime = lifetime
		p.local_coords = false
		p.process_material = process
		p.draw_pass_1 = draw_mesh
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 6, 8))
		add_child(p)
		_emitters.append(p)


## Emits a burst at `pos`; `scale` widens the burst (emitter scale), `dir` tilts it.
func fire(pos: Vector3, scale: float = 1.0, dir: Vector3 = Vector3.UP) -> void:
	if _emitters.is_empty():
		return
	var p := _emitters[_next]
	_next = (_next + 1) % _emitters.size()
	var up := dir.normalized() if dir.length() > 0.001 else Vector3.UP
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var basis := Basis(side, up, side.cross(up)).orthonormalized().scaled(Vector3.ONE * clampf(scale, 0.2, 4.0))
	p.global_transform = Transform3D(basis, pos)
	p.restart()
	p.emitting = true


func active_count() -> int:
	var n := 0
	for e in _emitters:
		if e.emitting:
			n += 1
	return n


## Soft round particle texture (radial gradient, white with alpha falloff).
static func soft_dot_texture(size_px: int = 64, hardness: float = 0.35) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(hardness, Color(1, 1, 1, 0.85))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size_px
	t.height = size_px
	return t


## Billboard quad with a soft dot, lit per vertex, coloured by particle colour.
static func soft_quad(size_m: float, color: Color, hardness: float = 0.35) -> QuadMesh:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = soft_dot_texture(64, hardness)
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(size_m, size_m)
	q.material = m
	return q
