class_name PreviewFlourish
extends Node3D
## Small element-coloured effects for the skill-tree technique preview, fired on the clip's
## timed events (release / impact / freeze / gather ...) so the effect lands on the body
## motion. Presentation only (gameplay VFX live in src/fx and need a real scene): a pooled
## burst emitter, a travelling "bolt" for released techniques and a ground ring for stomps.
## Lives entirely inside the preview SubViewport's own World3D.

const EVENTS_RELEASE: Array[StringName] = [&"release", &"freeze", &"throw", &"fire", &"launch"]
const EVENTS_GROUND: Array[StringName] = [&"impact", &"stomp", &"slam", &"rise", &"quake", &"land"]
const EVENTS_GATHER: Array[StringName] = [&"gather", &"draw", &"lift", &"charge"]

var element := ElementDefs.Element.NONE
var rig: HumanoidRig
var budget := 1.0
## Effects fired so far (tests).
var fired := 0

var _bursts: Array[GPUParticles3D] = []
var _burst_i := 0
var _bolts: Array[MeshInstance3D] = []
var _bolt_i := 0
var _rings: Array[MeshInstance3D] = []
var _ring_i := 0
var _live: Array[Dictionary] = []    # {node, t, dur, kind, from, to}
static var _dot_tex: Texture2D = null


func attach(p_rig: HumanoidRig, p_element: int) -> void:
	rig = p_rig
	element = p_element
	budget = clampf(Settings.effects_scale(), 0.35, 1.4)
	for i in 3:
		_bursts.append(_make_burst())
		_bolts.append(_make_bolt())
		_rings.append(_make_ring())
	rig.action_event.connect(_on_event)


func _on_event(_clip: StringName, event: StringName) -> void:
	if event in EVENTS_RELEASE:
		var from := _hands()
		var fwd := -rig.global_transform.basis.z
		burst(from, 0.8)
		bolt(from, from + fwd * 3.6 + Vector3.UP * 0.05)
	elif event in EVENTS_GROUND:
		var feet := rig.global_position + Vector3.UP * 0.03
		ring(feet, 2.4)
		burst(feet + Vector3.UP * 0.2, 1.0)
	elif event in EVENTS_GATHER:
		burst(_hands(), 0.45)


func _hands() -> Vector3:
	var l := rig.get_socket(&"hand_l")
	var r := rig.get_socket(&"hand_r")
	if l and r:
		return (l.global_position + r.global_position) * 0.5
	return rig.global_position + Vector3.UP * 1.1


# --- effects ------------------------------------------------------------------------------------

func burst(at: Vector3, strength: float) -> void:
	var p := _bursts[_burst_i % _bursts.size()]
	_burst_i += 1
	p.global_position = at
	p.amount_ratio = clampf(strength * budget, 0.25, 1.0)
	p.restart()
	p.emitting = true
	fired += 1


func bolt(from: Vector3, to: Vector3) -> void:
	var b := _bolts[_bolt_i % _bolts.size()]
	_bolt_i += 1
	b.visible = true
	b.global_position = from
	b.scale = Vector3.ONE * 0.6
	var trail := b.get_node_or_null(^"Trail") as GPUParticles3D
	if trail:
		trail.emitting = true
	_live.append({"node": b, "t": 0.0, "dur": 0.42, "kind": &"bolt", "from": from, "to": to})
	fired += 1


func ring(at: Vector3, radius: float) -> void:
	var r := _rings[_ring_i % _rings.size()]
	_ring_i += 1
	r.visible = true
	r.global_position = at
	r.scale = Vector3(0.2, 1.0, 0.2)
	_live.append({"node": r, "t": 0.0, "dur": 0.5, "kind": &"ring", "radius": radius})
	fired += 1


func _process(delta: float) -> void:
	for i in range(_live.size() - 1, -1, -1):
		var e: Dictionary = _live[i]
		var n: MeshInstance3D = e["node"]
		e["t"] = float(e["t"]) + delta
		var u := clampf(float(e["t"]) / float(e["dur"]), 0.0, 1.0)
		var mat := n.material_override as StandardMaterial3D
		if e["kind"] == &"bolt":
			var k := 1.0 - pow(1.0 - u, 2.0)
			n.global_position = (e["from"] as Vector3).lerp(e["to"], k)
			n.scale = Vector3.ONE * lerpf(0.6, 1.25, k) * (1.0 - smoothstep(0.75, 1.0, u))
			if element == ElementDefs.Element.EARTH:
				n.rotate_x(delta * 9.0)
		else:
			var rad := float(e["radius"]) * (1.0 - pow(1.0 - u, 3.0))
			n.scale = Vector3(maxf(rad, 0.05), 1.0, maxf(rad, 0.05))
		if mat:
			mat.albedo_color.a = (1.0 - u) * _alpha()
		if u >= 1.0:
			n.visible = false
			var trail := n.get_node_or_null(^"Trail") as GPUParticles3D
			if trail:
				trail.emitting = false
			_live.remove_at(i)


# --- construction -------------------------------------------------------------------------------

func _color() -> Color:
	match element:
		ElementDefs.Element.FIRE: return Color(1.0, 0.55, 0.18)
		ElementDefs.Element.WATER: return Color(0.45, 0.78, 1.0)
		ElementDefs.Element.EARTH: return Color(0.62, 0.50, 0.36)
		ElementDefs.Element.AIR: return Color(0.92, 0.96, 1.0)
	return UiTheme.GOLD


func _alpha() -> float:
	return 0.75 if element == ElementDefs.Element.AIR else 0.95


func _emissive() -> bool:
	return element == ElementDefs.Element.FIRE or element == ElementDefs.Element.WATER


## Additive blending glows on dark stages; water's stage is pale ice, so water mixes instead.
func _additive() -> bool:
	return element == ElementDefs.Element.FIRE


static func _dot() -> Texture2D:
	if _dot_tex:
		return _dot_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 64
	_dot_tex = gt
	return gt


func _make_burst() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 40
	p.lifetime = 0.6
	p.explosiveness = 0.92
	p.local_coords = false
	var heavy := element == ElementDefs.Element.EARTH or element == ElementDefs.Element.WATER
	p.process_material = _particles(1.4, 3.8, Vector3(0, -6.0 if heavy else 0.8, 0), 180.0, 0.14)
	p.draw_pass_1 = _particle_quad(0.26 if element != ElementDefs.Element.AIR else 0.34)
	add_child(p)
	return p


## A short-lived particle trail that follows a travelling bolt (world-space particles).
func _make_trail() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.emitting = false
	p.amount = 36
	p.lifetime = 0.38
	p.local_coords = false
	p.process_material = _particles(0.2, 0.9, Vector3(0, -2.0 if element == ElementDefs.Element.WATER else 0.4, 0), 180.0, 0.08)
	p.draw_pass_1 = _particle_quad(0.22 if element != ElementDefs.Element.AIR else 0.3)
	return p


func _particles(vmin: float, vmax: float, gravity: Vector3, spread: float, radius: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3(0, 1, 0)
	pm.spread = spread
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = gravity
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var ramp := Gradient.new()
	var c := _color()
	ramp.set_color(0, Color(c if _additive() else c.lightened(0.3), 1.0))
	ramp.set_color(1, Color(c, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	return pm


func _particle_quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if _additive() else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _dot()
	q.material = m
	return q


func _make_bolt() -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if _emissive() or element == ElementDefs.Element.AIR else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var c := _color()
	m.albedo_color = Color(c, _alpha())
	match element:
		ElementDefs.Element.EARTH:
			var b := BoxMesh.new()
			b.size = Vector3(0.36, 0.3, 0.34)
			n.mesh = b
			m.albedo_color = Color(c, 1.0)
		ElementDefs.Element.AIR:
			var t := TorusMesh.new()
			t.inner_radius = 0.16
			t.outer_radius = 0.24
			n.mesh = t
			n.rotation.x = PI * 0.5
		_:
			var s := SphereMesh.new()
			s.radius = 0.17
			s.height = 0.34
			s.radial_segments = 16
			s.rings = 8
			n.mesh = s
	if _additive():
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	n.material_override = m
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.visible = false
	var trail := _make_trail()
	trail.name = "Trail"
	n.add_child(trail)
	add_child(n)
	return n


func _make_ring() -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.9
	t.outer_radius = 1.0
	t.rings = 48
	t.ring_segments = 6
	n.mesh = t
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(_color(), _alpha())
	if _additive():
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	n.material_override = m
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.visible = false
	add_child(n)
	return n
