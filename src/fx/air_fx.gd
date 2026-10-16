class_name AirFx
extends RefCounted
## Airbending visuals: pale swirling currents (helix gusts that travel with the
## attack, spinning rings for sweeps, shields and jumps) plus surface-aware
## ground puffs (dust on dirt/stone, leaves on grass, snow puffs on snow).
##
##   var g := AirFx.gust(self, Transform3D(basis, origin), 6.0, 0.8, 0.3)  # along -Z of the basis
##   AirFx.swirl(self, pos, 2.5, 0.6)                                       # ring of wind
##   AirFx.ground_puff(self, ground_pos, surface, 1.0)


static func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://src/fx/shaders/fx_air.gdshader")
	m.set_shader_parameter(&"noise_tex", FxLib.noise_texture(&"smooth"))
	return m


## Helical gust from xform.origin along -Z of xform, `length` long, opening to `radius`.
## follow: optional Node3D the gust stays attached to (projectiles).
static func gust(from: Node, xform: Transform3D, length: float, radius: float, duration: float = 0.3, opts: Dictionary = {}) -> AirGust:
	var g := FxLib.take(from, &"air_gust", AirGust.make) as AirGust
	g.setup(xform, length, radius, duration, opts)
	return g


## Spinning rings of wind around `pos` (sweeps, shields, air jumps).
static func swirl(from: Node, pos: Vector3, radius: float, duration: float = 0.5, opts: Dictionary = {}) -> AirSwirl:
	var s := FxLib.take(from, &"air_swirl", AirSwirl.make) as AirSwirl
	s.setup(pos, radius, duration, opts)
	return s


## Ground reaction to wind: dust / leaves / snow by surface, plus a faint ring.
static func ground_puff(from: Node, pos: Vector3, surface: StringName, strength: float = 1.0, dir: Vector3 = Vector3.UP) -> void:
	var col := FxLib.surface_color(surface)
	match surface:
		&"snow", &"ice":
			FxBurst.spawn(from, &"snow", pos, {"count": strength, "size": 0.8 + strength * 0.3, "dir": dir})
		&"water":
			FxBurst.spawn(from, &"spray", pos, {"count": strength, "dir": dir})
		&"grass":
			FxBurst.spawn(from, &"dust", pos, {"color": col.lightened(0.15), "count": 0.6 * strength, "dir": dir})
			FxBurst.spawn(from, &"leaves", pos, {"count": strength, "dir": dir})
		_:
			FxBurst.spawn(from, &"dust", pos, {"color": col, "count": strength, "dir": dir})
	FxRing.spawn(from, pos, 1.2 + strength, Color(0.9, 0.96, 1.0), 0.45, {"opacity": 0.45, "width": 0.12, "fill": 0.0})


## Travelling helix of wind ribbons.
class AirGust extends Node3D:
	var mesh_i: MeshInstance3D
	var inner: MeshInstance3D
	var mat: ShaderMaterial
	var mat_inner: ShaderMaterial
	var t := 0.0
	var duration := 0.3
	var follow: Node3D = null
	var follow_offset := Transform3D.IDENTITY

	static func make() -> AirGust:
		var g := AirGust.new()
		g.name = "AirGust"
		g.mesh_i = MeshInstance3D.new()
		g.mat = AirFx.material()
		g.mesh_i.material_override = g.mat
		g.mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(g.mesh_i)
		g.inner = MeshInstance3D.new()
		g.mat_inner = AirFx.material()
		g.mat_inner.set_shader_parameter(&"opacity", 0.6)
		g.inner.material_override = g.mat_inner
		g.inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(g.inner)
		return g

	func setup(xform: Transform3D, length: float, radius: float, p_duration: float, opts: Dictionary) -> void:
		global_transform = xform
		# Meshes are built at real size (cached per rounded length / radius) so
		# ribbon widths stay right for every gust size.
		var lq := maxf(1.0, roundf(length))
		var rq := maxf(0.2, snappedf(radius, 0.1))
		mesh_i.mesh = FxMeshes.helix(3, 1.3, rq * 0.22, rq, 0.16 + rq * 0.08, lq)
		inner.mesh = FxMeshes.helix(2, 0.8, rq * 0.08, rq * 0.45, 0.08 + rq * 0.05, lq * 0.9)
		mesh_i.scale = Vector3.ONE
		inner.scale = Vector3.ONE
		duration = maxf(p_duration, 0.05)
		t = 0.0
		follow = opts.get("follow", null)
		if follow:
			follow_offset = follow.global_transform.affine_inverse() * xform
		mat.set_shader_parameter(&"opacity", float(opts.get("opacity", 0.85)))
		mat.set_shader_parameter(&"tail", float(opts.get("tail", 0.75)))
		mat_inner.set_shader_parameter(&"tail", float(opts.get("tail", 0.75)) * 0.8)
		_apply(0.0)

	func _apply(p: float) -> void:
		var head := 0.05 + p * 1.25
		mat.set_shader_parameter(&"head", head)
		mat_inner.set_shader_parameter(&"head", head - 0.08)
		mesh_i.rotation.z = -p * 2.2
		inner.rotation.z = p * 3.0

	func fx_reset() -> void:
		t = duration

	func _process(delta: float) -> void:
		t += delta
		if follow != null and is_instance_valid(follow) and follow.is_inside_tree():
			global_transform = follow.global_transform * follow_offset
		var p := clampf(t / duration, 0.0, 1.0)
		_apply(p)
		if p >= 1.0:
			FxLib.release(self)


## Spinning wind rings (2-3 tilted bands) that expand and fade.
class AirSwirl extends Node3D:
	var rings: Array[MeshInstance3D] = []
	var mats: Array[ShaderMaterial] = []
	var t := 0.0
	var duration := 0.5
	var radius := 2.0
	var grow := 1.0
	var spin := 9.0
	var looping := false
	var follow: Node3D = null
	var height := 0.6

	static func make() -> AirSwirl:
		var s := AirSwirl.new()
		s.name = "AirSwirl"
		for i in 3:
			var m := MeshInstance3D.new()
			m.mesh = FxMeshes.ring(40, 0.22 - i * 0.04, 0.12)
			var mat := AirFx.material()
			mat.set_shader_parameter(&"looping", 1.0)
			mat.set_shader_parameter(&"streaks", 6.0 + i * 2.0)
			m.material_override = mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			s.add_child(m)
			s.rings.append(m)
			s.mats.append(mat)
		return s

	func setup(pos: Vector3, p_radius: float, p_duration: float, opts: Dictionary) -> void:
		global_position = pos
		global_basis = Basis.IDENTITY
		radius = p_radius
		duration = maxf(p_duration, 0.05)
		grow = float(opts.get("grow", 1.35))
		spin = float(opts.get("spin", 9.0))
		looping = bool(opts.get("loop", false))
		follow = opts.get("follow", null)
		height = float(opts.get("height", 0.6))
		t = 0.0
		for i in rings.size():
			var tilt := float(opts.get("tilt", 0.18))
			rings[i].rotation = Vector3(tilt * (1 if i % 2 == 0 else -1), i * 1.3, tilt * 0.6 * (i - 1))
			rings[i].position = Vector3(0, height * (float(i) / 2.0 - 0.3), 0)
			mats[i].set_shader_parameter(&"opacity", float(opts.get("opacity", 0.8)) * (1.0 - 0.18 * i))
		_apply(0.0)

	func _apply(p: float) -> void:
		var r := radius * lerpf(0.75, grow, 1.0 - pow(1.0 - p, 2.0)) if not looping else radius
		for i in rings.size():
			var rr := r * (1.0 - 0.12 * i)
			rings[i].scale = Vector3(rr, 1.0, rr)
			rings[i].rotate_y(spin * (1.0 + 0.3 * i) * get_process_delta_time() * (1 if i % 2 == 0 else -1))
		var fade := 1.0 if looping else 1.0 - smoothstep(0.55, 1.0, p)
		for i in mats.size():
			mats[i].set_shader_parameter(&"head", 1.0)
			rings[i].transparency = 1.0 - fade

	## Looping swirls (shields): call to fade out and release.
	func stop(fade: float = 0.2) -> void:
		looping = false
		duration = maxf(fade, 0.05)
		t = duration * 0.55

	func fx_reset() -> void:
		looping = false
		t = duration

	func _process(delta: float) -> void:
		if follow != null and is_instance_valid(follow) and follow.is_inside_tree():
			global_position = follow.global_position + Vector3.UP * 0.9
		if looping:
			_apply(0.5)
			return
		t += delta
		var p := clampf(t / duration, 0.0, 1.0)
		_apply(p)
		if p >= 1.0:
			FxLib.release(self)
