class_name FxRing
extends Node3D
## Pooled expanding ground ring / shockwave (stomps, sweeps, landings, impacts).
##
##   FxRing.spawn(self, pos, 3.5, Color(0.9, 0.8, 0.6), 0.5)

var mesh: MeshInstance3D
var mat: ShaderMaterial
var t := 0.0
var duration := 0.5


static func spawn(from: Node, pos: Vector3, radius: float, color: Color, duration_s: float = 0.5, opts: Dictionary = {}) -> FxRing:
	var r := FxLib.take(from, &"ring", FxRing._make) as FxRing
	var n: Vector3 = opts.get("normal", Vector3.UP)
	var b := Basis.IDENTITY
	if n.normalized().dot(Vector3.UP) < 0.999:
		var x := n.cross(Vector3.FORWARD).normalized()
		if x.length_squared() < 0.01:
			x = Vector3.RIGHT
		b = Basis(x, n.normalized(), x.cross(n.normalized())).orthonormalized()
	r.global_transform = Transform3D(b.scaled(Vector3(radius, 1.0, radius)), pos + n.normalized() * 0.04)
	r.duration = maxf(duration_s, 0.05)
	r.t = 0.0
	r.mat.set_shader_parameter(&"color", color)
	r.mat.set_shader_parameter(&"inner_color", opts.get("inner", color.lightened(0.15)))
	r.mat.set_shader_parameter(&"width", float(opts.get("width", 0.16)))
	r.mat.set_shader_parameter(&"opacity", float(opts.get("opacity", 0.8)))
	r.mat.set_shader_parameter(&"fill", float(opts.get("fill", 0.25)))
	r.mat.set_shader_parameter(&"seed", randf() * 10.0)
	r.mat.set_shader_parameter(&"progress", 0.0)
	return r


static func _make() -> FxRing:
	var r := FxRing.new()
	r.name = "Ring"
	r.mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	r.mesh.mesh = pm
	r.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.mat = ShaderMaterial.new()
	r.mat.shader = preload("res://src/fx/shaders/fx_ring.gdshader")
	r.mat.set_shader_parameter(&"noise_tex", FxLib.noise_texture(&"smooth"))
	r.mesh.material_override = r.mat
	r.add_child(r.mesh)
	return r


func fx_reset() -> void:
	t = duration


func _process(delta: float) -> void:
	t += delta
	var p := clampf(t / duration, 0.0, 1.0)
	mat.set_shader_parameter(&"progress", p)
	if p >= 1.0:
		FxLib.release(self)
