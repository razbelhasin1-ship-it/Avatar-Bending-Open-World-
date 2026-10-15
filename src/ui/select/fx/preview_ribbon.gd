class_name PreviewRibbon
extends MeshInstance3D
## Dynamic ribbon/tube rebuilt every frame from a point list (ImmediateMesh):
## `set_strip()` makes a camera-facing ribbon (air currents), `set_tube()` a round tube
## (water streams). UV.x runs tail (0) -> head (1); vertex alpha comes from `alphas`.

var _im := ImmediateMesh.new()


func _init(mat: Material = null) -> void:
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mat:
		material_override = mat


## Camera-facing strip through `points` (world space) with per-point widths.
func set_strip(points: PackedVector3Array, widths: PackedFloat32Array, cam_pos: Vector3, alpha: float = 1.0) -> void:
	_im.clear_surfaces()
	var n := points.size()
	if n < 2:
		return
	var inv := global_transform.affine_inverse()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var p := points[i]
		var t := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
		var v := (cam_pos - p).normalized()
		var side := t.cross(v).normalized() * widths[i] * 0.5
		var u := float(i) / (n - 1)
		_im.surface_set_color(Color(1, 1, 1, alpha))
		_im.surface_set_uv(Vector2(u, 0.0))
		_im.surface_add_vertex(inv * (p - side))
		_im.surface_set_color(Color(1, 1, 1, alpha))
		_im.surface_set_uv(Vector2(u, 1.0))
		_im.surface_add_vertex(inv * (p + side))
	_im.surface_end()


## Round tube through `points` with per-point radii (`sides` around).
func set_tube(points: PackedVector3Array, radii: PackedFloat32Array, sides: int = 8, alpha: float = 1.0) -> void:
	_im.clear_surfaces()
	var n := points.size()
	if n < 2:
		return
	var inv := global_transform.affine_inverse()
	var frames: Array[Basis] = []
	var up := Vector3.UP
	for i in n:
		var t := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
		if absf(t.dot(up)) > 0.95:
			up = Vector3.RIGHT
		var b := t.cross(up).normalized()
		var nn := b.cross(t).normalized()
		up = nn
		frames.append(Basis(b, nn, t))
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n - 1:
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var quad := [[i, a0], [i + 1, a0], [i + 1, a1], [i, a0], [i + 1, a1], [i, a1]]
			for q: Array in quad:
				var k: int = q[0]
				var ang: float = q[1]
				var f := frames[k]
				var off := (f.x * cos(ang) + f.y * sin(ang)) * radii[k]
				_im.surface_set_color(Color(1, 1, 1, alpha))
				_im.surface_set_uv(Vector2(float(k) / (n - 1), fposmod(ang / TAU, 1.0)))
				_im.surface_set_normal(off.normalized())
				_im.surface_add_vertex(inv * (points[k] + off))
	_im.surface_end()


func clear() -> void:
	_im.clear_surfaces()
