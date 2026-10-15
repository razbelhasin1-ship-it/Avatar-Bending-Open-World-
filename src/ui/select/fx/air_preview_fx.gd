class_name AirPreviewFx
extends PreviewFx
## Airbending showcase: currents spiralling around the bender, palm strikes that push
## gusts out across the frame, and a sweeping kick ringed by a wind wave.

const STREAKS := 4

var _swirls: Array[PreviewRibbon] = []
var _gusts: Array[Dictionary] = []
var _energy := 0.4


func sequence() -> Array[Dictionary]:
	return [
		{"clip": &"air_jab_r", "pause": 0.05}, {"clip": &"air_jab_l", "pause": 0.4},
		{"clip": &"air_sweep", "pause": 0.6},
		{"clip": &"air_blast", "pause": 1.0},
	]


func _setup() -> void:
	for i in 3:
		var m := ribbon_material(Color(0.92, 0.97, 1.0), 0.75)
		m.set_shader_parameter(&"streaks", 2.0 + i)
		var r := PreviewRibbon.new(m)
		add_child(r)
		_swirls.append(r)


func on_event(clip: StringName, event: StringName) -> void:
	if event != &"release":
		return
	_energy = 1.0
	match clip:
		&"air_jab_r": _gust(socket_pos(&"hand_r"), forward(), 0.5)
		&"air_jab_l": _gust(socket_pos(&"hand_l"), forward(), 0.5)
		&"air_blast": _gust((socket_pos(&"hand_r") + socket_pos(&"hand_l")) * 0.5, forward(), 1.0)
		&"air_sweep": _ring(rig.global_position + Vector3.UP * 0.25)


func _gust(origin: Vector3, dir: Vector3, power: float) -> void:
	for k in STREAKS:
		var m := ribbon_material(Color(0.95, 0.98, 1.0), 0.85)
		var r := PreviewRibbon.new(m)
		add_child(r)
		var off := Vector3(randf_range(-0.25, 0.25), randf_range(-0.2, 0.25), randf_range(-0.25, 0.25)) * power
		_gusts.append({"ribbon": r, "origin": origin + off, "dir": (dir + Vector3(0, randf_range(-0.06, 0.1), 0)).normalized(),
				"t": -k * 0.03, "life": 0.55, "len": 1.4 * power + 0.6, "width": 0.14 * power + 0.05, "ring": false, "curl": randf_range(-1, 1)})


func _ring(center: Vector3) -> void:
	var m := ribbon_material(Color(0.95, 0.98, 1.0), 0.8)
	var r := PreviewRibbon.new(m)
	add_child(r)
	_gusts.append({"ribbon": r, "origin": center, "dir": Vector3.FORWARD, "t": 0.0, "life": 0.6, "len": 0.0, "width": 0.18, "ring": true, "curl": 0.0})


func step(delta: float) -> void:
	_energy = move_toward(_energy, 0.4, delta * 0.8)
	var base := rig.global_position
	for i in _swirls.size():
		var pts := PackedVector3Array()
		var w := PackedFloat32Array()
		var n := 26
		var speed := 2.4 + i * 0.7
		var span := 4.2
		var a0 := time * speed + i * TAU / 3.0
		var rad := 0.62 + 0.12 * i + 0.25 * _energy
		for k in n:
			var s := float(k) / (n - 1)
			var a := a0 - s * span
			var h := 0.25 + fposmod(0.35 * i + s * 0.9 + time * 0.25, 1.6)
			var rr := rad * (0.85 + 0.25 * sin(s * PI))
			pts.append(base + Vector3(cos(a) * rr, h, sin(a) * rr))
			w.append(0.09 * sin(PI * s) * (0.6 + _energy))
		_swirls[i].set_strip(pts, w, cam_pos(), 0.55 + 0.45 * _energy)
	for gi in range(_gusts.size() - 1, -1, -1):
		var g: Dictionary = _gusts[gi]
		g["t"] = float(g["t"]) + delta
		var t: float = g["t"]
		var life: float = g["life"]
		var r: PreviewRibbon = g["ribbon"]
		if t >= life:
			r.queue_free()
			_gusts.remove_at(gi)
			continue
		if t < 0.0:
			continue
		var k := t / life
		var pts2 := PackedVector3Array()
		var w2 := PackedFloat32Array()
		var n2 := 16
		if bool(g["ring"]):
			var rad2 := 0.3 + k * 2.4
			for j in n2 * 2:
				var a := TAU * j / (n2 * 2 - 1)
				pts2.append((g["origin"] as Vector3) + Vector3(cos(a) * rad2, 0.05 * sin(a * 3.0 + t * 8.0), sin(a) * rad2))
				w2.append(float(g["width"]) * (1.0 - k))
		else:
			var dir: Vector3 = g["dir"]
			var side := dir.cross(Vector3.UP).normalized()
			var head := (g["origin"] as Vector3) + dir * (k * 4.5)
			for j in n2:
				var s := float(j) / (n2 - 1)
				var p := head - dir * (1.0 - s) * float(g["len"])
				p += side * sin(s * PI * 2.0 + t * 10.0) * 0.08 * float(g["curl"])
				pts2.append(p)
				w2.append(float(g["width"]) * sin(PI * s) * (1.0 - k * 0.6))
		r.set_strip(pts2, w2, cam_pos(), 1.0 - k)
