class_name AirWaveFx
extends Node3D
## Expanding ring of wind (Air Push, Gale Drop slam): a leaning wall of streaks
## races outward along the ground with a fainter second wall behind it and a quick
## dome burst at the centre. The front follows AirWaveFx.front(p, radius) exactly,
## which is also the gameplay hit front (a target is hit when the wall reaches it).
##
##   var w := AirWaveFx.spawn(self, ground_pos, 5.5, 0.3)

var wall: MeshInstance3D
var wall2: MeshInstance3D
var dome: MeshInstance3D
var mats: Array[ShaderMaterial] = []
var t := 0.0
var duration := 0.3
var radius := 5.0
var height := 1.3
var dome_on := true


## Front radius at normalized time p (0..1): fast start, easing out.
static func front(p: float, p_radius: float) -> float:
	var q := clampf(p, 0.0, 1.0)
	return lerpf(0.45, p_radius, 1.0 - (1.0 - q) * (1.0 - q))


static func spawn(from: Node, pos: Vector3, p_radius: float, p_duration: float = 0.3, opts: Dictionary = {}) -> AirWaveFx:
	var w := FxLib.take(from, &"air_wave", AirWaveFx._make) as AirWaveFx
	w.global_position = pos
	w.global_basis = Basis.IDENTITY
	w.radius = p_radius
	w.duration = maxf(p_duration, 0.08)
	w.height = float(opts.get("height", clampf(0.7 + p_radius * 0.12, 0.8, 1.8)))
	w.dome_on = bool(opts.get("dome", true))
	w.t = 0.0
	var op := float(opts.get("opacity", 0.9))
	w.mats[0].set_shader_parameter(&"opacity", op)
	w.mats[1].set_shader_parameter(&"opacity", op * 0.55)
	w.mats[2].set_shader_parameter(&"opacity", op * 0.7)
	w.dome.visible = w.dome_on
	w._apply(0.0)
	return w


static func _make() -> AirWaveFx:
	var w := AirWaveFx.new()
	w.name = "AirWave"
	w.wall = _mi(w, AirSheets.band(1.0, 0.35), {"streaks": 14.0, "twist": 0.4, "scroll": 2.6, "body": 0.3, "fade_bottom": 0.04, "fade_top": 0.55, "near_fade": 0.8})
	w.wall2 = _mi(w, AirSheets.band(1.0, 0.2), {"streaks": 9.0, "twist": -0.6, "scroll": -1.8, "body": 0.22, "fade_bottom": 0.05, "fade_top": 0.6, "near_fade": 0.8})
	w.dome = _mi(w, AirSheets.sphere(20, 10), {"streaks": 6.0, "twist": 1.5, "scroll": 2.0, "body": 0.1, "rim": 0.9, "fade_bottom": 0.45, "fade_top": 0.05, "near_fade": 1.0})
	return w


static func _mi(w: AirWaveFx, mesh: Mesh, opts: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := AirSheets.material(opts)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(mi)
	w.mats.append(m)
	return mi


func _apply(p: float) -> void:
	var r := front(p, radius)
	var h := height * lerpf(1.0, 0.55, p)
	wall.scale = Vector3(r, h, r)
	var r2 := front(maxf(p - 0.12, 0.0), radius) * 0.92
	wall2.scale = Vector3(r2, h * 0.75, r2)
	mats[0].set_shader_parameter(&"progress", smoothstep(0.45, 1.0, p))
	mats[1].set_shader_parameter(&"progress", smoothstep(0.3, 0.95, p))
	if dome_on:
		var dp := clampf(p / 0.45, 0.0, 1.0)
		var dr := lerpf(0.5, radius * 0.42, 1.0 - (1.0 - dp) * (1.0 - dp))
		dome.scale = Vector3(dr, dr * 0.8, dr)
		dome.position = Vector3(0, dr * 0.25, 0)
		mats[2].set_shader_parameter(&"progress", smoothstep(0.1, 1.0, dp))


func fx_reset() -> void:
	t = duration


func _process(delta: float) -> void:
	t += delta
	var p := clampf(t / duration, 0.0, 1.0)
	_apply(p)
	if p >= 1.0:
		FxLib.release(self)
