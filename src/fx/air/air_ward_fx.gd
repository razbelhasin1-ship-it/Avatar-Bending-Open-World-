class_name AirWardFx
extends Node3D
## Vortex Ward: a spinning sphere of wind around the bender (streaking shell, two
## whirling bands, a ground ring of swept dust). Follows `follow`; burst() flings
## it outward and fades.
##
##   var w := AirWardFx.spawn(self, caster, 1.6)
##   w.burst()

var shell: MeshInstance3D
var bands: Array[MeshInstance3D] = []
var mats: Array[ShaderMaterial] = []
var follow: Node3D = null
var radius := 1.6
var _t := 0.0
var _burst := -1.0
var _grow := 0.0


static func spawn(from: Node, p_follow: Node3D, p_radius: float = 1.6) -> AirWardFx:
	var w := FxLib.take(from, &"air_ward", AirWardFx._make) as AirWardFx
	w.follow = p_follow
	w.radius = p_radius
	w._t = 0.0
	w._burst = -1.0
	w._grow = 0.0
	w.global_basis = Basis.IDENTITY
	if p_follow != null and is_instance_valid(p_follow):
		w.global_position = p_follow.global_position + Vector3.UP * 0.95
	w._apply(0.0)
	return w


static func _make() -> AirWardFx:
	var w := AirWardFx.new()
	w.name = "AirWard"
	w.shell = w._mi(AirSheets.sphere(26, 14), {"streaks": 7.0, "twist": 2.2, "scroll": 3.0, "body": 0.03, "rim": 0.32,
		"fade_bottom": 0.18, "fade_top": 0.12, "near_fade": 0.4, "opacity": 0.6, "line_sharp": 0.62})
	for i in 2:
		w.bands.append(w._mi(FxMeshes.ring(48, 0.16, 0.1), {"streaks": 7.0, "twist": 0.0, "scroll": 4.5, "body": 0.35, "line_sharp": 0.4,
			"fade_bottom": 0.0, "fade_top": 0.0, "near_fade": 0.4, "opacity": 0.65}))
	return w


func _mi(mesh: Mesh, opts: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := AirSheets.material(opts)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mats.append(m)
	return mi


func burst(fade: float = 0.3) -> void:
	if _burst < 0.0:
		_burst = 0.0
		set_meta(&"fade", maxf(fade, 0.05))


func fx_reset() -> void:
	_burst = 99.0
	set_meta(&"fade", 0.05)


func _apply(delta: float) -> void:
	var g := 1.0 - pow(1.0 - clampf(_grow, 0.0, 1.0), 3.0)
	var b := 0.0
	if _burst >= 0.0:
		b = clampf(_burst / float(get_meta(&"fade", 0.3)), 0.0, 1.0)
	var r := radius * g * (1.0 + b * 1.4)
	shell.scale = Vector3(r, r * 0.92, r)
	shell.rotate_y(5.0 * delta)
	bands[0].scale = Vector3.ONE * r * 1.04
	bands[1].scale = Vector3.ONE * r * 0.98
	bands[0].basis = Basis(Vector3(1, 0, 0.2).normalized(), 0.35) * Basis(Vector3.UP, _t * 7.0)
	bands[0].scale = Vector3.ONE * r * 1.04
	bands[1].basis = Basis(Vector3(-0.2, 0, 1).normalized(), -0.5) * Basis(Vector3.UP, -_t * 9.0)
	bands[1].scale = Vector3.ONE * r * 0.98
	for m in mats:
		m.set_shader_parameter(&"progress", b * 1.1)


func _process(delta: float) -> void:
	_t += delta
	_grow = minf(1.0, _grow + delta / 0.18)
	if follow != null and is_instance_valid(follow) and follow.is_inside_tree() and _burst < 0.0:
		global_position = follow.global_position + Vector3.UP * 0.95
	if _burst >= 0.0:
		_burst += delta
	_apply(delta)
	if _burst >= 0.0 and _burst >= float(get_meta(&"fade", 0.3)):
		FxLib.release(self)
