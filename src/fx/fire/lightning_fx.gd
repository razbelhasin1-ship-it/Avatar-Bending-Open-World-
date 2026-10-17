class_name LightningFx
extends RefCounted
## Lightning visuals (Lightning Generation): jagged camera-facing ribbons with a
## white-hot core and a blue-violet glow (additive: readable without filling the
## screen), re-jagged a few times per bolt so it flickers like real discharge.
##
##   var b := LightningFx.bolt(self, hand, target_point, {"branches": 3, "width": 0.18})
##   var arcs := LightningFx.arcs(self, hand_node, 0.35)    # crackle around the hands
##   arcs.set_intensity(0.6); ...; arcs.stop()
## Pooled (FxLib) and capped.

const SHADER := preload("res://src/fx/fire/fx_lightning.gdshader")
const COLOR := Color(0.62, 0.74, 1.0)


static func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	return m


## A discharge from `a` to `b`. opts: width (m), branches (int), duration (s),
## jitter (m, how far the path wanders), reveal (s, time to grow from a to b).
static func bolt(from: Node, a: Vector3, b: Vector3, opts: Dictionary = {}) -> LightningBolt:
	FxLib.set_cap(&"lightning_bolt", 6)
	var n := FxLib.take(from, &"lightning_bolt", LightningBolt.make) as LightningBolt
	n.setup(a, b, opts)
	return n


## Crackling arcs around a node (charging hands). Follows `node` until stop().
static func arcs(from: Node, node: Node3D, radius: float = 0.3) -> LightningArcs:
	FxLib.set_cap(&"lightning_arcs", 4)
	var n := FxLib.take(from, &"lightning_arcs", LightningArcs.make) as LightningArcs
	n.setup(node, radius)
	return n


## Jagged polyline from a to b: `segments` points displaced sideways (mid-point
## heavy), tapering to the ends.
static func jag(a: Vector3, b: Vector3, segments: int, jitter: float, rng: RandomNumberGenerator) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var d := b - a
	var dist := d.length()
	if dist < 0.001:
		pts.append(a)
		pts.append(b)
		return pts
	var f := d / dist
	var s1 := f.cross(Vector3.UP)
	if s1.length_squared() < 0.01:
		s1 = f.cross(Vector3.RIGHT)
	s1 = s1.normalized()
	var s2 := f.cross(s1).normalized()
	for i in segments + 1:
		var u := float(i) / segments
		var p := a + d * u
		if i > 0 and i < segments:
			var env := sin(u * PI)
			p += (s1 * rng.randf_range(-1.0, 1.0) + s2 * rng.randf_range(-1.0, 1.0)) * jitter * env
		pts.append(p)
	return pts


## Appends a camera-facing ribbon through `pts` to an ImmediateMesh surface
## (already begun). Width tapers toward the end; COLOR.a carries `alpha`.
static func ribbon(im: ImmediateMesh, pts: PackedVector3Array, cam_pos: Vector3, width: float, alpha: float = 1.0, taper: float = 0.6) -> void:
	var n := pts.size()
	if n < 2:
		return
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in n:
		var p := pts[i]
		var dir := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var to_cam := (cam_pos - p).normalized()
		var side := dir.cross(to_cam)
		side = side.normalized() if side.length_squared() > 1e-6 else Vector3.UP
		var u := float(i) / (n - 1)
		var w := width * lerpf(1.0, 1.0 - taper, u) * 0.5
		var l := p - side * w
		var r := p + side * w
		if i > 0:
			var u0 := float(i - 1) / (n - 1)
			for v: Array in [[prev_l, Vector2(u0, 0)], [prev_r, Vector2(u0, 1)], [r, Vector2(u, 1)], [prev_l, Vector2(u0, 0)], [r, Vector2(u, 1)], [l, Vector2(u, 0)]]:
				im.surface_set_color(Color(1, 1, 1, alpha))
				im.surface_set_uv(v[1])
				im.surface_add_vertex(v[0])
		prev_l = l
		prev_r = r


static func camera_pos(node: Node) -> Vector3:
	var vp := node.get_viewport() if node and node.is_inside_tree() else null
	var cam := vp.get_camera_3d() if vp else null
	return cam.global_position if cam else Vector3(0, 50, 50)


## One discharge (main bolt + branches), re-jagged while it lives.
class LightningBolt extends Node3D:
	var mesh_i: MeshInstance3D
	var im: ImmediateMesh
	var mat: ShaderMaterial
	var a := Vector3.ZERO
	var b := Vector3.FORWARD
	var width := 0.16
	var branches := 3
	var jitter := 0.6
	var duration := 0.38
	var reveal_t := 0.05
	var t := 0.0
	var _rejag_t := 0.0
	var _rng := RandomNumberGenerator.new()

	static func make() -> LightningBolt:
		var n := LightningBolt.new()
		n.name = "LightningBolt"
		n.im = ImmediateMesh.new()
		n.mesh_i = MeshInstance3D.new()
		n.mesh_i.mesh = n.im
		n.mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.mat = LightningFx.material()
		n.mesh_i.material_override = n.mat
		n.add_child(n.mesh_i)
		return n

	func setup(p_a: Vector3, p_b: Vector3, opts: Dictionary) -> void:
		global_transform = Transform3D.IDENTITY
		a = p_a
		b = p_b
		width = float(opts.get("width", 0.16))
		branches = int(opts.get("branches", 3))
		jitter = float(opts.get("jitter", clampf(a.distance_to(b) * 0.06, 0.15, 1.4)))
		duration = float(opts.get("duration", 0.38))
		reveal_t = float(opts.get("reveal", 0.05))
		t = 0.0
		_rejag_t = 0.0
		_rng.seed = randi()
		mat.set_shader_parameter(&"seed", _rng.randf())
		mat.set_shader_parameter(&"fade", 0.0)
		mat.set_shader_parameter(&"intensity", float(opts.get("intensity", 1.4)))
		_build()

	func fx_reset() -> void:
		t = duration + 1.0

	func _build() -> void:
		im.clear_surfaces()
		var cam := LightningFx.camera_pos(self)
		var segs := clampi(int(a.distance_to(b) / 0.7), 6, 40)
		var main := LightningFx.jag(a, b, segs, jitter, _rng)
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		LightningFx.ribbon(im, main, cam, width, 1.0, 0.45)
		# Branches fork off the main path and die out.
		var count := branches if FxLib.tier() >= 1 else mini(branches, 1)
		for k in count:
			var i := _rng.randi_range(1, maxi(1, main.size() - 3))
			var start := main[i]
			var along := (main[mini(i + 1, main.size() - 1)] - start).normalized()
			var off := (along + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.6), _rng.randf_range(-1, 1)) * 0.9).normalized()
			var end := start + off * _rng.randf_range(0.8, 2.6)
			LightningFx.ribbon(im, LightningFx.jag(start, end, 5, 0.25, _rng), cam, width * 0.5, 0.7, 0.9)
		im.surface_end()

	func _process(delta: float) -> void:
		t += delta
		_rejag_t += delta
		if _rejag_t > 0.055 and t < duration * 0.6:
			_rejag_t = 0.0
			_build()
		mat.set_shader_parameter(&"reveal", clampf(t / maxf(reveal_t, 0.001), 0.0, 1.0) * 1.05)
		mat.set_shader_parameter(&"fade", clampf((t - duration * 0.45) / (duration * 0.55), 0.0, 1.0))
		if t >= duration:
			im.clear_surfaces()
			FxLib.release(self)


## Small arcs crackling around a point (charging fingertips).
class LightningArcs extends Node3D:
	var mesh_i: MeshInstance3D
	var im: ImmediateMesh
	var mat: ShaderMaterial
	var follow: Node3D = null
	var radius := 0.3
	var intensity := 0.3
	var _t := 0.0
	var _stopping := -1.0
	var _rng := RandomNumberGenerator.new()

	static func make() -> LightningArcs:
		var n := LightningArcs.new()
		n.name = "LightningArcs"
		n.im = ImmediateMesh.new()
		n.mesh_i = MeshInstance3D.new()
		n.mesh_i.mesh = n.im
		n.mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.mat = LightningFx.material()
		n.mat.set_shader_parameter(&"intensity", 1.0)
		n.mesh_i.material_override = n.mat
		n.add_child(n.mesh_i)
		return n

	func setup(node: Node3D, r: float) -> void:
		follow = node
		radius = r
		intensity = 0.3
		_t = 0.0
		_stopping = -1.0
		_rng.seed = randi()
		global_transform = Transform3D.IDENTITY
		mat.set_shader_parameter(&"fade", 0.0)

	func set_intensity(k: float) -> void:
		intensity = clampf(k, 0.0, 1.5)

	func stop() -> void:
		if _stopping < 0.0:
			_stopping = 0.0

	func fx_reset() -> void:
		_stopping = 1.0

	func _process(delta: float) -> void:
		_t += delta
		if _stopping >= 0.0:
			_stopping += delta
			mat.set_shader_parameter(&"fade", clampf(_stopping / 0.12, 0.0, 1.0))
			if _stopping > 0.12:
				im.clear_surfaces()
				FxLib.release(self)
			return
		if follow == null or not is_instance_valid(follow) or not follow.is_inside_tree():
			stop()
			return
		if _t < 0.045:
			return
		_t = 0.0
		var c := follow.global_position
		var cam := LightningFx.camera_pos(self)
		im.clear_surfaces()
		var n := 1 + int(round(intensity * (3.0 if FxLib.tier() >= 2 else 1.5)))
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in n:
			var d1 := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
			var d2 := (d1 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))).normalized()
			var r := radius * (0.5 + intensity * 0.8)
			LightningFx.ribbon(im, LightningFx.jag(c + d1 * r * 0.3, c + d2 * r, 4, r * 0.25, _rng), cam, 0.035 + 0.03 * intensity, 0.9, 0.7)
		im.surface_end()
		mat.set_shader_parameter(&"intensity", 0.6 + intensity)
