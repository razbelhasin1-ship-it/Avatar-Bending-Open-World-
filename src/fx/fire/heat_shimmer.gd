class_name HeatShimmer
extends Node3D
## Heat haze over strong fire (explosions, a full Blaze Charge, the Inferno, big
## grass fires): a pooled camera-facing quad refracting the scene behind it.
## Only spawned where the screen texture is cheap (Forward+, effects high/ultra);
## elsewhere spawn() returns null and nothing depends on it.
##
##   HeatShimmer.spawn(self, pos, 1.6, 2.4, 0.8)        # width, height, seconds
##   var h := HeatShimmer.attach(self, node, 0.8, 1.2)  # follows a node until stop()

const SHADER := preload("res://src/fx/fire/fx_heat_shimmer.gdshader")

var mesh_i: MeshInstance3D
var mat: ShaderMaterial
var t := 0.0
var duration := 0.8
var peak := 1.0
var follow: Node3D = null
var sustained := false


static func supported() -> bool:
	return FxLib.tier() >= 2 and not Settings.is_compatibility_renderer() and not Settings.is_mobile_renderer() \
		and DisplayServer.get_name() != "headless"


static func spawn(from: Node, pos: Vector3, width: float = 1.4, height: float = 2.0, seconds: float = 0.8, strength: float = 1.0) -> HeatShimmer:
	if not supported():
		return null
	FxLib.set_cap(&"heat_shimmer", 6)
	var h := FxLib.take(from, &"heat_shimmer", HeatShimmer._make) as HeatShimmer
	h.global_position = pos + Vector3.UP * height * 0.5
	h.scale = Vector3(width, height, 1.0)
	h.duration = maxf(seconds, 0.05)
	h.peak = strength
	h.t = 0.0
	h.follow = null
	h.sustained = false
	h.mat.set_shader_parameter(&"opacity", strength)
	return h


static func attach(from: Node, node: Node3D, width: float = 0.8, height: float = 1.2, strength: float = 1.0) -> HeatShimmer:
	if node == null or not is_instance_valid(node):
		return null
	var h := spawn(from, node.global_position, width, height, 0.3, strength)
	if h:
		h.follow = node
		h.sustained = true
	return h


static func _make() -> HeatShimmer:
	var h := HeatShimmer.new()
	h.name = "HeatShimmer"
	h.mesh_i = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	h.mesh_i.mesh = q
	h.mat = ShaderMaterial.new()
	h.mat.shader = SHADER
	h.mat.set_shader_parameter(&"noise_tex", FxLib.noise_texture(&"smooth"))
	h.mesh_i.material_override = h.mat
	h.mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.add_child(h.mesh_i)
	return h


func stop(fade: float = 0.3) -> void:
	sustained = false
	follow = null
	t = 0.0
	duration = maxf(fade, 0.05)


func fx_reset() -> void:
	sustained = false
	follow = null
	t = duration


func _process(delta: float) -> void:
	if sustained:
		if follow != null and is_instance_valid(follow) and follow.is_inside_tree():
			global_position = follow.global_position + Vector3.UP * scale.y * 0.35
			mat.set_shader_parameter(&"opacity", peak)
			return
		stop(0.2)
	t += delta
	var u := clampf(t / duration, 0.0, 1.0)
	mat.set_shader_parameter(&"opacity", peak * (1.0 - u * u))
	if u >= 1.0:
		FxLib.release(self)
