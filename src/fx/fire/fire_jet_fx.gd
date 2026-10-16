class_name FireJetFx
extends Node3D
## A thrusting jet of flame (Jet Step from the feet and palms): two crossed banded
## flame quads stretched along the thrust (wide and white-hot at the nozzle, licking
## out to a red tip) plus a short exhaust of flame puffs that trail behind as the
## bender moves. Re-aim it every frame; stop() lets it gutter out.
##
##   var j := FireJetFx.spawn(self)
##   j.aim(foot_pos, Vector3.DOWN, 1.1, 1.0)    # every frame: nozzle, direction, length, strength
##   j.stop()

var quads: Array[MeshInstance3D] = []
var mats: Array[ShaderMaterial] = []
var exhaust: GPUParticles3D
var length := 1.0
var strength := 1.0
var _dying := -1.0
var _t := 0.0


static func spawn(from: Node) -> FireJetFx:
	FxLib.set_cap(&"fire_jet", 8)
	var j := FxLib.take(from, &"fire_jet", FireJetFx._make) as FireJetFx
	j._dying = -1.0
	j._t = 0.0
	for m in j.mats:
		m.set_shader_parameter(&"opacity", 1.0)
		m.set_shader_parameter(&"age", 0.0)
	j.exhaust.restart()
	j.exhaust.emitting = true
	return j


static func _make() -> FireJetFx:
	var j := FireJetFx.new()
	j.name = "FireJet"
	for i in 2:
		var m := MeshInstance3D.new()
		m.mesh = FireFx.quad()
		var mat := FireFx.flame_material(0.4 * i + 0.13, 1.0)
		mat.set_shader_parameter(&"billboard", 0.0)
		mat.set_shader_parameter(&"scroll_speed", 4.0)
		mat.set_shader_parameter(&"intensity", 1.25)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.rotation = Vector3(0, PI * 0.5 * i, 0)
		j.add_child(m)
		j.quads.append(m)
		j.mats.append(mat)
	var p := GPUParticles3D.new()
	p.amount = FxLib.amount(14)
	p.lifetime = 0.28
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.06
	pm.direction = Vector3.UP
	pm.spread = 9.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 6.0
	pm.damping_max = 10.0
	pm.scale_min = 0.32
	pm.scale_max = 0.5
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.6))
	sc.add_point(Vector2(0.4, 1.0))
	sc.add_point(Vector2(1.0, 0.2))
	var ct := CurveTexture.new()
	ct.curve = sc
	pm.scale_curve = ct
	p.process_material = pm
	p.draw_pass_1 = FireFx.quad()
	p.material_override = FireFx.flame_material(0.7, 0.3)
	j.exhaust = p
	j.add_child(p)
	return j


## Places the jet: `nozzle` (world), thrust `dir` (where the flame goes), `len` m, `k` 0..1.
func aim(nozzle: Vector3, dir: Vector3, len_m: float = 1.0, k: float = 1.0) -> void:
	var d := dir.normalized() if dir.length_squared() > 1e-4 else Vector3.DOWN
	var x := d.cross(Vector3.FORWARD if absf(d.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(d).normalized()
	# Local +Y runs along the flame (base at the nozzle, tongue outward).
	global_transform = Transform3D(Basis(x, d, z), nozzle)
	length = len_m
	strength = k


func stop() -> void:
	if _dying < 0.0:
		_dying = 0.0
		exhaust.emitting = false


func fx_reset() -> void:
	_dying = 1.0


func _process(delta: float) -> void:
	_t += delta
	var flick := 0.9 + 0.1 * sin(_t * 41.0) + 0.06 * sin(_t * 67.0)
	var w := 0.32 + 0.14 * strength
	var l := length * flick * (0.4 + 0.6 * strength)
	for q in quads:
		q.scale = Vector3(w, l, w)
		q.position = Vector3(0, l * 0.42, 0)
	if _dying >= 0.0:
		_dying += delta
		var a := clampf(1.0 - _dying / 0.15, 0.0, 1.0)
		for m in mats:
			m.set_shader_parameter(&"opacity", a)
		if _dying >= 0.45:
			FxLib.release(self)
