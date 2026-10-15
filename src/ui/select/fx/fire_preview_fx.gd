class_name FirePreviewFx
extends PreviewFx
## Firebending showcase: flickering fists, jab-jab-spin kick with flame bursts, a fire arc
## trailing the kicking foot and a charged fireball that streaks across the frame.

var _hands: Dictionary = {}       # socket -> GPUParticles3D
var _heat := 0.25
var _arc: PreviewRibbon
var _arc_pts: Array[Vector3] = []
var _arc_t := 0.0
var _arc_socket := &"foot_r"
var _balls: Array[Dictionary] = []


func sequence() -> Array[Dictionary]:
	return [
		{"clip": &"fire_jab_r", "pause": 0.08}, {"clip": &"fire_jab_l", "pause": 0.1},
		{"clip": &"fire_spin_kick_r", "pause": 0.7},
		{"clip": &"fire_charge_release", "pause": 1.2},
	]


func _setup() -> void:
	for s: StringName in [&"hand_l", &"hand_r"]:
		var f := make_flames(maxi(10, int(26 * budget)), 0.42, 0.26)
		add_child(f)
		_hands[s] = f
	var m := ribbon_material(Color(1.0, 0.55, 0.15), 0.95)
	m.set_shader_parameter(&"rim_tint", Color(1.0, 0.9, 0.5))
	m.set_shader_parameter(&"water", 0.0)
	_arc = PreviewRibbon.new(m)
	add_child(_arc)


func on_event(clip: StringName, event: StringName) -> void:
	if event != &"release":
		return
	match clip:
		&"fire_jab_r":
			_fireball(&"hand_r", 0.7, 7.5)
		&"fire_jab_l":
			_fireball(&"hand_l", 0.7, 7.5)
		&"fire_spin_kick_r", &"fire_kick_r":
			_arc_socket = &"foot_r"
			_arc_t = 0.45
			_arc_pts.clear()
		&"fire_charge_release":
			_fireball(&"hand_r", 1.5, 6.0)
	_heat = 1.0


func _fireball(socket_name: StringName, size: float, speed: float) -> void:
	var start := socket_pos(socket_name)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09 * size
	sm.height = 0.18 * size
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(1.0, 0.92, 0.65)
	sm.material = cm
	core.mesh = sm
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	core.global_position = start
	var trail := make_flames(maxi(16, int(48 * budget)), 0.32, 0.34 * size)
	(trail.process_material as ParticleProcessMaterial).gravity = Vector3(0, 0.6, 0)
	(trail.process_material as ParticleProcessMaterial).initial_velocity_max = 0.4
	add_child(trail)
	trail.global_position = start
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 2.2 * size
	light.omni_range = 2.2 * size
	add_child(light)
	light.global_position = start
	_balls.append({"core": core, "trail": trail, "light": light, "vel": forward() * speed, "life": 0.55, "size": size})


func step(delta: float) -> void:
	_heat = move_toward(_heat, 0.3, delta * 1.4)
	for s: StringName in _hands:
		var f: GPUParticles3D = _hands[s]
		f.global_position = socket_pos(s)
		f.amount_ratio = clampf(_heat, 0.15, 1.0)
	# fireballs
	for i in range(_balls.size() - 1, -1, -1):
		var b: Dictionary = _balls[i]
		b["life"] = float(b["life"]) - delta
		var core: MeshInstance3D = b["core"]
		var trail: GPUParticles3D = b["trail"]
		var light: OmniLight3D = b["light"]
		if float(b["life"]) > 0.0:
			core.global_position += (b["vel"] as Vector3) * delta
			trail.global_position = core.global_position
			light.global_position = core.global_position
		elif core.visible:
			core.visible = false
			trail.emitting = false
			spray(core.global_position, Vector3.UP, Color(1.0, 0.7, 0.3), 14, 2.5, 0.03, -2.0, 0.4)
			light.light_energy = 0.0
		if float(b["life"]) < -0.6:
			core.queue_free()
			trail.queue_free()
			light.queue_free()
			_balls.remove_at(i)
	# fire arc behind the kicking foot
	if _arc_t > 0.0:
		_arc_t -= delta
		_arc_pts.append(socket_pos(_arc_socket))
		if _arc_pts.size() > 16:
			_arc_pts.pop_front()
	elif not _arc_pts.is_empty():
		_arc_pts.pop_front()
	if _arc_pts.size() >= 2:
		var w := PackedFloat32Array()
		for k in _arc_pts.size():
			w.append(0.38 * sin(PI * float(k) / (_arc_pts.size() - 1)) + 0.04)
		_arc.set_strip(PackedVector3Array(_arc_pts), w, cam_pos(), 1.0)
	else:
		_arc.clear()
