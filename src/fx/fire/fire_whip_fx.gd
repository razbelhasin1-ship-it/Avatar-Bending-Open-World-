class_name FireWhipFx
extends Node3D
## A lash of flame along a moving curve (Fire Whip): a camera-facing ribbon with
## the banded flame-ribbon shader, thick at the hand and tapering to a hot tip.
## The ability feeds the curve every tick; finish() lets it burn out.
##
##   var w := FireWhipFx.spawn(self)
##   w.set_points(points, 0.32)        # every tick (hand -> tip)
##   w.finish(0.25)                    # burns out, back to the pool

var mesh_i: MeshInstance3D
var im: ImmediateMesh
var mat: ShaderMaterial
var points := PackedVector3Array()
var width := 0.3
var _dying := -1.0
var _fade := 0.25


static func spawn(from: Node) -> FireWhipFx:
	FxLib.set_cap(&"fire_whip", 4)
	var w := FxLib.take(from, &"fire_whip", FireWhipFx._make) as FireWhipFx
	w.global_transform = Transform3D.IDENTITY
	w._dying = -1.0
	w.points = PackedVector3Array()
	w.mat.set_shader_parameter(&"fade", 0.0)
	w.mat.set_shader_parameter(&"opacity", 1.0)
	w.im.clear_surfaces()
	return w


static func _make() -> FireWhipFx:
	var w := FireWhipFx.new()
	w.name = "FireWhip"
	w.im = ImmediateMesh.new()
	w.mesh_i = MeshInstance3D.new()
	w.mesh_i.mesh = w.im
	w.mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.mat = FireFx.ribbon_material()
	w.mat.set_shader_parameter(&"symmetric", 1.0)
	w.mat.set_shader_parameter(&"head", 1.05)
	w.mat.set_shader_parameter(&"tail", 1.2)
	w.mat.set_shader_parameter(&"tongue_scale", 7.0)
	w.mat.set_shader_parameter(&"scroll_speed", 3.0)
	w.mesh_i.material_override = w.mat
	w.add_child(w.mesh_i)
	return w


func set_points(pts: PackedVector3Array, p_width: float = 0.3) -> void:
	points = pts
	width = p_width
	_rebuild()


func _rebuild() -> void:
	im.clear_surfaces()
	var n := points.size()
	if n < 2:
		return
	var cam := LightningFx.camera_pos(self)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in n:
		var p := points[i]
		var dir := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := dir.cross((cam - p).normalized())
		side = side.normalized() if side.length_squared() > 1e-6 else Vector3.UP
		var u := float(i) / (n - 1)
		# Thick near the hand, a bulge of fire mid-way, a thin hot tip.
		var w := width * (0.55 + 0.65 * sin(clampf(u * 1.15, 0.0, 1.0) * PI * 0.9)) * lerpf(1.0, 0.35, u * u)
		var l := p - side * w
		var r := p + side * w
		if i > 0:
			var u0 := float(i - 1) / (n - 1)
			for v: Array in [[prev_l, Vector2(u0, 0)], [prev_r, Vector2(u0, 1)], [r, Vector2(u, 1)], [prev_l, Vector2(u0, 0)], [r, Vector2(u, 1)], [l, Vector2(u, 0)]]:
				im.surface_set_uv(v[1])
				im.surface_add_vertex(v[0])
		prev_l = l
		prev_r = r
	im.surface_end()


func tip() -> Vector3:
	return points[points.size() - 1] if points.size() > 0 else global_position


func finish(fade: float = 0.25) -> void:
	if _dying >= 0.0:
		return
	_dying = 0.0
	_fade = maxf(fade, 0.05)


func fx_reset() -> void:
	_dying = 10.0


func _process(delta: float) -> void:
	if _dying < 0.0:
		return
	_dying += delta
	var k := clampf(_dying / _fade, 0.0, 1.0)
	mat.set_shader_parameter(&"fade", k)
	mat.set_shader_parameter(&"opacity", 1.0 - k * k)
	if k >= 1.0:
		im.clear_surfaces()
		FxLib.release(self)
