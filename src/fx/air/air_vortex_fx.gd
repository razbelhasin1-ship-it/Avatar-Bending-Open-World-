class_name AirVortexFx
extends Node3D
## The Air Tornado: a funnel of wind narrow at the ground and flaring to the sky,
## an inner counter-spinning core, a dust skirt in the colours of the ground and
## debris / leaves orbiting up the column. The owner moves it (global_position),
## sets `power` (0..1 growth) and calls release() to fling it apart.
##
##   var v := AirVortexFx.spawn(self, ground_pos, 8.5, 3.4, surface)
##   v.power = 1.0; v.release()

const DEBRIS := 6

var outer: MeshInstance3D
var inner: MeshInstance3D
var skirt: MeshInstance3D
var mats: Array[ShaderMaterial] = []
var bits: Array[MeshInstance3D] = []
var bit_phase: Array[float] = []
var height := 8.5
var radius := 3.4
var power := 0.0
var spin := 4.5
var releasing := false
var _shown := 0.0
var _rel_t := 0.0
var _t := 0.0


static func spawn(from: Node, pos: Vector3, p_height: float = 8.5, p_radius: float = 3.4, surface: StringName = &"stone") -> AirVortexFx:
	var v := FxLib.take(from, &"air_vortex", AirVortexFx._make) as AirVortexFx
	v.global_position = pos
	v.global_basis = Basis.IDENTITY
	v.height = p_height
	v.radius = p_radius
	v.power = 0.0
	v._shown = 0.0
	v.releasing = false
	v._rel_t = 0.0
	v._t = 0.0
	v.scale = Vector3.ONE
	var dust := FxLib.surface_color(surface)
	if surface == &"snow" or surface == &"ice":
		dust = Color(0.92, 0.95, 1.0)
	elif surface == &"water":
		dust = Color(0.8, 0.9, 0.98)
	v.mats[2].set_shader_parameter(&"edge_color", dust.darkened(0.15))
	v.mats[2].set_shader_parameter(&"core_color", dust.lightened(0.35))
	var leafy := surface == &"grass"
	for i in v.bits.size():
		var b := v.bits[i]
		b.material_override = ToonMaterials.make(Color(0.42, 0.56, 0.24) if leafy and i % 2 == 0 else dust.darkened(0.25), {"outline": false, "vertex_color": true})
	v._apply(0.0)
	return v


static func _make() -> AirVortexFx:
	var v := AirVortexFx.new()
	v.name = "AirVortex"
	v.outer = v._mi(AirSheets.funnel(1.0, 0.22, 1.0, 0.04, 30, 14), {"streaks": 5.0, "twist": 2.6, "scroll": 2.4, "body": 0.2, "rim": 0.55,
		"fade_bottom": 0.05, "fade_top": 0.3, "near_fade": 3.0, "opacity": 0.82})
	v.inner = v._mi(AirSheets.funnel(1.0, 0.12, 0.5, 0.0, 22, 10), {"streaks": 4.0, "twist": -3.2, "scroll": -3.4, "body": 0.14, "rim": 0.3,
		"fade_bottom": 0.04, "fade_top": 0.4, "near_fade": 2.5, "opacity": 0.6})
	v.skirt = v._mi(AirSheets.funnel(1.0, 1.0, 1.7, 0.1, 26, 4), {"streaks": 8.0, "twist": 1.2, "scroll": 3.0, "body": 0.38, "rim": 0.2,
		"fade_bottom": 0.02, "fade_top": 0.7, "near_fade": 2.0, "opacity": 0.75, "line_sharp": 0.45})
	for i in DEBRIS:
		var b := MeshInstance3D.new()
		b.mesh = FxMeshes.rock(i % 6, 0)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		v.add_child(b)
		v.bits.append(b)
		v.bit_phase.append(float(i) / DEBRIS)
	return v


func _mi(mesh: Mesh, opts: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := AirSheets.material(opts)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mats.append(m)
	return mi


## Flings the funnel apart (fades over `fade` s, then returns to the pool).
func release(fade: float = 0.55) -> void:
	if releasing:
		return
	releasing = true
	_rel_t = 0.0
	set_meta(&"rel_fade", maxf(fade, 0.1))


func fx_reset() -> void:
	releasing = true
	_rel_t = 99.0


func _apply(delta: float) -> void:
	var g := _shown
	var h := height * lerpf(0.25, 1.0, g)
	var r := radius * lerpf(0.35, 1.0, g)
	var rel := 0.0
	if releasing:
		rel = clampf(_rel_t / float(get_meta(&"rel_fade", 0.5)), 0.0, 1.0)
		r *= 1.0 + rel * 0.9
		h *= 1.0 + rel * 0.25
	outer.scale = Vector3(r, h, r)
	inner.scale = Vector3(r * 0.95, h * 0.92, r * 0.95)
	skirt.scale = Vector3(r * 0.5, 1.6 * lerpf(0.5, 1.0, g), r * 0.5)
	outer.rotate_y(-spin * delta)
	inner.rotate_y(spin * 1.6 * delta)
	skirt.rotate_y(-spin * 1.2 * delta)
	var prog := lerpf(0.35, 0.0, g) + rel
	mats[0].set_shader_parameter(&"progress", prog)
	mats[1].set_shader_parameter(&"progress", prog + 0.05)
	mats[2].set_shader_parameter(&"progress", prog * 0.8)
	# Debris rides up the column on a widening spiral.
	for i in bits.size():
		var b := bits[i]
		var ph := fmod(bit_phase[i] + _t * 0.28, 1.0)
		var a := -_t * spin * (1.2 - ph * 0.5) + float(i) * 2.1
		var rr := r * (0.28 + ph * 0.55)
		b.position = Vector3(cos(a) * rr, ph * h * 0.75 + 0.3, sin(a) * rr)
		var s := 0.16 + 0.12 * float(i % 3)
		s *= (1.0 - rel) * clampf(g * 1.5, 0.0, 1.0)
		b.scale = Vector3.ONE * maxf(s, 0.001)
		b.rotation = Vector3(_t * 5.0 + i, _t * 3.0, _t * 4.0 - i)


func _process(delta: float) -> void:
	_t += delta
	_shown = move_toward(_shown, power, delta * 3.0)
	if releasing:
		_rel_t += delta
	_apply(delta)
	if releasing and _rel_t >= float(get_meta(&"rel_fade", 0.5)):
		FxLib.release(self)
