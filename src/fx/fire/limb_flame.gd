class_name LimbFlame
extends Node3D
## A fist or foot catching fire for a strike: a banded flame sprite riding on the
## limb's socket (it moves WITH the punch / kick instead of being left behind) and a
## few embers, burning out in a quarter second. Pooled.
##
##   LimbFlame.attach(self, rig.get_socket(&"hand_r"), 1.0)

var sprite: MeshInstance3D
var mat: ShaderMaterial
var follow: Node3D = null
var strength := 1.0
var t := 0.0
var life := 0.28


static func attach(from: Node, socket: Node3D, p_strength: float = 1.0, p_life: float = 0.28) -> LimbFlame:
	if socket == null or not is_instance_valid(socket):
		return null
	FxLib.set_cap(&"limb_flame", 8)
	var f := FxLib.take(from, &"limb_flame", LimbFlame._make) as LimbFlame
	f.follow = socket
	f.strength = p_strength
	f.life = p_life
	f.t = 0.0
	f.global_position = socket.global_position
	f.mat.set_shader_parameter(&"opacity", 1.0)
	f.mat.set_shader_parameter(&"age", 0.0)
	return f


static func _make() -> LimbFlame:
	var f := LimbFlame.new()
	f.name = "LimbFlame"
	f.sprite = MeshInstance3D.new()
	f.sprite.mesh = FireFx.quad()
	f.mat = FireFx.flame_material(randf(), 0.75)
	f.mat.set_shader_parameter(&"scroll_speed", 3.0)
	f.mat.set_shader_parameter(&"intensity", 1.25)
	f.sprite.material_override = f.mat
	f.sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.add_child(f.sprite)
	return f


func fx_reset() -> void:
	t = life
	follow = null


func _process(delta: float) -> void:
	t += delta
	if follow != null and is_instance_valid(follow) and follow.is_inside_tree():
		global_position = follow.global_position + Vector3.UP * 0.08
	var u := clampf(t / maxf(life, 0.05), 0.0, 1.0)
	var s := (0.32 + 0.22 * strength) * (1.0 - 0.4 * u) * (0.9 + 0.15 * sin(t * 40.0))
	sprite.scale = Vector3(s, s * 1.35, s)
	mat.set_shader_parameter(&"age", u * 0.8)
	mat.set_shader_parameter(&"opacity", 1.0 - u * u)
	if u >= 1.0:
		follow = null
		FxLib.release(self)
