class_name WindBladeFx
extends Node3D
## Wind Blade: a thin crescent of compressed air with a bright cutting edge and
## two fading after-images trailing it. It is the visual of the blade projectile
## (BendingProjectile places and orients the root along the flight; `roll` turns
## the crescent upright for aerial axe kicks).
##
##   var fx := WindBladeFx.spawn(self, 1.3, 0.0)     # half-width 1.3 m, flat
##   BendingProjectile.launch(..., {"visual": fx, "on_finish": func(v): v.finish()})

const SHADER := preload("res://src/fx/air/fx_wind_blade.gdshader")

var pivot: Node3D
var blades: Array[MeshInstance3D] = []
var mats: Array[ShaderMaterial] = []
var half_width := 1.3
var _fade := -1.0
var _fade_t := 0.0
var _t := 0.0


static func spawn(from: Node, p_half_width: float = 1.3, roll: float = 0.0) -> WindBladeFx:
	var w := FxLib.take(from, &"wind_blade", WindBladeFx._make) as WindBladeFx
	w.half_width = p_half_width
	w.pivot.rotation = Vector3(0, 0, roll)
	w._fade = -1.0
	w._fade_t = 0.0
	w._t = 0.0
	w._apply()
	return w


static func _make() -> WindBladeFx:
	var w := WindBladeFx.new()
	w.name = "WindBlade"
	w.pivot = Node3D.new()
	w.add_child(w.pivot)
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = AirSheets.blade(1.8, 0.46 - i * 0.08)
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter(&"noise_tex", FxLib.noise_texture(&"smooth"))
		m.set_shader_parameter(&"opacity", [1.0, 0.5, 0.25][i])
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.pivot.add_child(mi)
		w.blades.append(mi)
		w.mats.append(m)
	return w


func _apply() -> void:
	var f := 1.0
	if _fade > 0.0:
		f = 1.0 - clampf(_fade_t / _fade, 0.0, 1.0)
	var pulse := 1.0 + 0.06 * sin(_t * 40.0)
	for i in blades.size():
		var s := half_width * (1.0 - 0.08 * i) * pulse
		var b := blades[i]
		b.scale = Vector3(s, 1.0, s * 0.75)
		# The arc's middle sits on the projectile; after-images trail behind it.
		b.position = Vector3(0, 0, s * 0.75 + 0.55 * i)
		mats[i].set_shader_parameter(&"progress", (1.0 - f) * 1.1)


func finish(fade: float = 0.12) -> void:
	if _fade < 0.0:
		_fade = maxf(fade, 0.03)
		_fade_t = 0.0


func fx_reset() -> void:
	_fade = 0.01
	_fade_t = 1.0


func _process(delta: float) -> void:
	_t += delta
	if _fade > 0.0:
		_fade_t += delta
	_apply()
	if _fade > 0.0 and _fade_t >= _fade:
		FxLib.release(self)
