class_name PreviewFx
extends Node3D
## Base of the element-select preview effects: a looping showcase sequence of real
## HumanoidRig clips and visuals keyed to the clips' timed events (release / impact /
## stomp / lift / gather), so the effect always lands on the body motion.
## These are presentation effects for the menu only; gameplay bending lives in src/bending.

const NOISE := preload("res://assets/textures/world/clouds.png")
const FLAME_SHADER := preload("res://src/ui/shaders/flame_particle.gdshader")
const RIBBON_SHADER := preload("res://src/ui/shaders/ribbon.gdshader")

var rig: HumanoidRig
var camera: Camera3D
var element := ElementDefs.Element.NONE
var time := 0.0
## Effects budget (Settings.effects_scale()).
var budget := 1.0
## Silhouette mode (show-intro motif): effects only, rendered over a black figure.
var motif := false


## Hooks the effect to a rig and camera (call once, after both are in the tree).
func attach(p_rig: HumanoidRig, p_camera: Camera3D) -> void:
	rig = p_rig
	camera = p_camera
	budget = Settings.effects_scale()
	rig.action_event.connect(on_event)
	_setup()


## Override: build persistent effect nodes.
func _setup() -> void:
	pass


## Override: [{"clip": StringName, "speed": float, "pause": seconds after the clip}].
func sequence() -> Array[Dictionary]:
	return []


## Override: react to a clip's timed event.
func on_event(_clip: StringName, _event: StringName) -> void:
	pass


## Override: per-frame update.
func step(_delta: float) -> void:
	pass


func _process(delta: float) -> void:
	time += delta
	if rig:
		step(delta)


# --- helpers -----------------------------------------------------------------------------

func socket_pos(socket_name: StringName) -> Vector3:
	var s := rig.get_socket(socket_name)
	return s.global_position if s else rig.global_position + Vector3.UP


func forward() -> Vector3:
	return -rig.global_transform.basis.z


func cam_pos() -> Vector3:
	return camera.global_position if camera else Vector3(0, 1.5, 4)


## Additive flame emitter (used by fire hands, fireballs, kicks).
static func make_flames(amount: int, lifetime: float, size: float, hot: bool = true) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = size * 0.25
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, 2.2, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1, 0.15))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	if hot:
		g.set_color(0, Color(1.0, 0.95, 0.75, 1.0))
		g.add_point(0.25, Color(1.0, 0.62, 0.18, 0.95))
		g.add_point(0.6, Color(0.92, 0.22, 0.06, 0.7))
		g.set_color(g.get_point_count() - 1, Color(0.35, 0.05, 0.02, 0.0))
	else:
		g.set_color(0, Color(1.0, 0.7, 0.3, 0.8))
		g.set_color(1, Color(0.6, 0.1, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var m := ShaderMaterial.new()
	m.shader = FLAME_SHADER
	m.set_shader_parameter(&"noise_tex", NOISE)
	var q := QuadMesh.new()
	q.size = Vector2(size, size * 1.4)
	q.material = m
	p.draw_pass_1 = q
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 6, 8))
	return p


static func ribbon_material(color: Color, opacity: float = 0.8, additive: bool = false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = RIBBON_SHADER
	m.set_shader_parameter(&"tint", color)
	m.set_shader_parameter(&"opacity", opacity)
	m.set_shader_parameter(&"noise_tex", NOISE)
	if additive:
		m.render_priority = 1
	return m


## Short-lived droplet / spark burst (CPU particles, self-freeing).
func spray(pos: Vector3, dir: Vector3, color: Color, count: int, speed: float, size: float, gravity: float = -9.8, life: float = 0.6) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(4, int(count * budget))
	p.lifetime = life
	p.direction = dir
	p.spread = 30.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	sm.material = mat
	p.mesh = sm
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	mat.vertex_color_use_as_albedo = false
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
