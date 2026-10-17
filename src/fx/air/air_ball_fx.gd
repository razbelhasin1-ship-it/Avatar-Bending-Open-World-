class_name AirBallFx
extends Node3D
## The Air Scooter's ball of air: a streaking spherical shell with a brighter core,
## two tilted wind bands whirling around it and a faint contact ring on the
## ground. The owner places it every tick (update(pos, velocity, delta)) and calls
## finish() when the ride ends.
##
##   var b := AirBallFx.spawn(self, 0.5)
##   b.update(feet_pos + Vector3.UP * 0.5, velocity, delta)
##   b.finish(0.2)

var shell: MeshInstance3D
var core: MeshInstance3D
var bands: Array[MeshInstance3D] = []
var mats: Array[ShaderMaterial] = []
var radius := 0.5
var _spin := 0.0
var _fade := -1.0
var _fade_t := 0.0
var _grow := 0.0


static func spawn(from: Node, p_radius: float = 0.5) -> AirBallFx:
	var b := FxLib.take(from, &"air_ball", AirBallFx._make) as AirBallFx
	b.radius = p_radius
	b._fade = -1.0
	b._fade_t = 0.0
	b._grow = 0.0
	b.global_basis = Basis.IDENTITY
	b._apply()
	return b


static func _make() -> AirBallFx:
	var b := AirBallFx.new()
	b.name = "AirBall"
	b.shell = b._mi(AirSheets.sphere(24, 12), {"streaks": 4.0, "twist": 1.6, "scroll": 3.2, "body": 0.2, "rim": 0.85,
		"fade_bottom": 0.0, "fade_top": 0.0, "near_fade": 0.6, "opacity": 0.85})
	b.core = b._mi(AirSheets.sphere(16, 8), {"streaks": 3.0, "twist": -2.0, "scroll": -4.0, "body": 0.35, "rim": 0.4,
		"fade_bottom": 0.0, "fade_top": 0.0, "near_fade": 0.5, "opacity": 0.55})
	for i in 2:
		var mi := b._mi(FxMeshes.ring(40, 0.2, 0.06), {"streaks": 6.0, "twist": 0.0, "scroll": 5.0, "body": 0.4, "line_sharp": 0.4,
			"fade_bottom": 0.0, "fade_top": 0.0, "near_fade": 0.6, "opacity": 0.7})
		b.bands.append(mi)
	return b


func _mi(mesh: Mesh, opts: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := AirSheets.material(opts)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mats.append(m)
	return mi


## Places the ball (centre) and spins it along the travel direction.
func update(center: Vector3, velocity: Vector3, delta: float) -> void:
	global_position = center
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	_spin += (8.0 + hv.length() / maxf(radius, 0.1)) * delta
	if hv.length() > 0.5:
		# Roll axis perpendicular to the motion: the streaks race forward under the feet.
		var axis := Vector3.UP.cross(hv.normalized())
		shell.basis = Basis(axis, _spin)
		core.basis = Basis(axis, -_spin * 1.3)
	else:
		shell.rotate_y(9.0 * delta)
		core.rotate_y(-12.0 * delta)
	bands[0].basis = Basis(Vector3(1, 0, 0.3).normalized(), 0.5) * Basis(Vector3.UP, _spin * 1.7)
	bands[1].basis = Basis(Vector3(-0.3, 0, 1).normalized(), -0.6) * Basis(Vector3.UP, -_spin * 2.1)


func finish(fade: float = 0.2) -> void:
	if _fade < 0.0:
		_fade = maxf(fade, 0.05)
		_fade_t = 0.0


func fx_reset() -> void:
	_fade = 0.01
	_fade_t = 1.0


func _apply() -> void:
	var g := 1.0 - pow(1.0 - clampf(_grow, 0.0, 1.0), 3.0)
	var f := 1.0
	if _fade > 0.0:
		f = 1.0 - clampf(_fade_t / _fade, 0.0, 1.0)
	var r := radius * g * lerpf(1.3, 1.0, f)
	shell.scale = Vector3.ONE * maxf(r, 0.01)
	core.scale = Vector3.ONE * maxf(r * 0.62, 0.01)
	for b in bands:
		b.scale = Vector3.ONE * maxf(r * 1.12, 0.01)
	for m in mats:
		m.set_shader_parameter(&"progress", (1.0 - f) * 1.1)


func _process(delta: float) -> void:
	_grow = minf(1.0, _grow + delta / 0.16)
	if _fade > 0.0:
		_fade_t += delta
	_apply()
	if _fade > 0.0 and _fade_t >= _fade:
		FxLib.release(self)
