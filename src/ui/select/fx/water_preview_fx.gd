class_name WaterPreviewFx
extends PreviewFx
## Waterbending showcase: a stream of water orbits the bender, is drawn into the hands
## and lashed out as whips that splash at the tip, then flows back into its orbit.

const POINTS := 30
const STREAM_SHADER := preload("res://src/ui/shaders/water_stream.gdshader")

var _stream: PreviewRibbon
var _pts: Array[Vector3] = []
var _mode := &"orbit"
var _mode_t := 0.0
var _hand := &"hand_r"


func sequence() -> Array[Dictionary]:
	return [
		{"clip": &"water_draw", "pause": 0.2},
		{"clip": &"water_whip_r", "pause": 0.3}, {"clip": &"water_whip_l", "pause": 0.5},
		{"clip": &"water_surge", "pause": 1.0},
	]


func _setup() -> void:
	var m := ShaderMaterial.new()
	m.shader = STREAM_SHADER
	m.set_shader_parameter(&"noise_tex", NOISE)
	_stream = PreviewRibbon.new(m)
	add_child(_stream)
	for i in POINTS:
		_pts.append(rig.global_position + Vector3.UP)


func on_event(clip: StringName, event: StringName) -> void:
	match [clip, event]:
		[&"water_draw", &"gather"]:
			_set_mode(&"gather")
		[&"water_whip_r", &"release"], [&"water_jab_r", &"release"]:
			_hand = &"hand_r"
			_set_mode(&"whip")
		[&"water_whip_l", &"release"], [&"water_jab_l", &"release"]:
			_hand = &"hand_l"
			_set_mode(&"whip")
		[&"water_surge", &"release"]:
			_hand = &"hand_r"
			_set_mode(&"surge")
		[&"water_whip_r", &"impact"], [&"water_whip_l", &"impact"]:
			spray(_pts[_pts.size() - 1], forward() + Vector3.UP * 0.4, Color(0.75, 0.92, 1.0), 18, 3.0, 0.035)


func _set_mode(m: StringName) -> void:
	_mode = m
	_mode_t = 0.0


func _target(s: float) -> Vector3:
	var base := rig.global_position
	var fwd := forward()
	var right := fwd.cross(Vector3.UP).normalized()
	match _mode:
		&"gather", &"whip", &"surge":
			var hand := socket_pos(_hand)
			var reach := clampf(_mode_t / 0.18, 0.0, 1.0)
			if _mode == &"gather":
				# coil from the hands down around the waist
				var a := s * TAU * 1.1 + time * 3.0
				return hand.lerp(base + Vector3(cos(a) * 0.55, 0.9 + s * 0.3, sin(a) * 0.55), s * 0.85)
			var length := (2.6 if _mode == &"whip" else 3.2) * reach
			var p := hand + fwd * s * length
			p += Vector3.UP * sin(s * PI) * (0.35 if _mode == &"surge" else 0.18)
			p += right * sin(s * PI * 2.0 + _mode_t * 9.0) * 0.18 * s
			return p
	# orbit: a lazy ribbon circling the waist
	var ang := time * 1.7 - s * 3.6
	var rad := 0.78 + 0.08 * sin(s * 6.0 + time)
	return base + Vector3(cos(ang) * rad, 1.0 + 0.22 * sin(s * 5.0 + time * 1.3), sin(ang) * rad)


func step(delta: float) -> void:
	_mode_t += delta
	if _mode == &"whip" and _mode_t > 0.55:
		_set_mode(&"orbit")
	elif _mode == &"surge" and _mode_t > 0.75:
		_set_mode(&"orbit")
	elif _mode == &"gather" and _mode_t > 1.0:
		_set_mode(&"orbit")
	var k := 1.0 - exp(-delta * (16.0 if _mode != &"orbit" else 7.0))
	for i in POINTS:
		var s := float(i) / (POINTS - 1)
		# the head leads, the tail follows a little later: fluid lag
		var kk := k * (1.0 - s * 0.35) if _mode == &"orbit" else k * (0.55 + s * 0.45)
		_pts[i] = _pts[i].lerp(_target(s), kk)
	var radii := PackedFloat32Array()
	for i in POINTS:
		var s := float(i) / (POINTS - 1)
		var thick := 0.075 if _mode != &"surge" else 0.12
		radii.append(thick * (0.35 + 0.65 * sin(PI * clampf(s * 1.1, 0.0, 1.0))) + 0.012)
	_stream.set_tube(PackedVector3Array(_pts), radii, 8, 1.0)
