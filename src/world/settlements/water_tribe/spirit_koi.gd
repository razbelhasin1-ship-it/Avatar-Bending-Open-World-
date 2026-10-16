class_name SpiritKoi
extends Node3D
## Tui and La, the moon and ocean spirits: a white koi with a black spot and a black koi with a
## white spot circling each other at the surface of the Spirit Oasis pond (a slow yin-yang
## chase with tail beats and a faint glow after dark). Place the node at the pond centre on
## the water level.

const PERIOD := 26.0

## Radius of the swim circle (m).
var radius := 3.6
var _fish: Array[Node3D] = []
var _tails: Array[Node3D] = []
var _t := 0.0
static var _meshes: Array = []


func _ready() -> void:
	name = "SpiritKoi"
	if _meshes.is_empty():
		_meshes = [_make_fish(Color(0.97, 0.97, 0.95), Color(0.06, 0.06, 0.08)),
			_make_fish(Color(0.07, 0.07, 0.09), Color(0.96, 0.96, 0.94))]
	for i in 2:
		var f := Node3D.new()
		f.name = "Tui" if i == 0 else "La"
		var body := MeshInstance3D.new()
		body.mesh = (_meshes[i] as Array)[0]
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.add_child(body)
		var tail := MeshInstance3D.new()
		tail.mesh = (_meshes[i] as Array)[1]
		tail.position = Vector3(0, 0, 0.42)
		tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.add_child(tail)
		add_child(f)
		_fish.append(f)
		_tails.append(tail)
	_t = randf() * PERIOD
	_update(0.0)


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	_t += delta
	var a := _t / PERIOD * TAU
	for i in 2:
		var ang := a + PI * i
		# a slightly breathing circle so the pair drifts like a yin-yang
		var r := radius * (1.0 + 0.12 * sin(a * 2.0 + i * 1.7))
		var p := Vector3(cos(ang) * r, -0.06 + 0.03 * sin(_t * 1.3 + i), sin(ang) * r)
		var tangent := Vector3(-sin(ang), 0, cos(ang))
		var f := _fish[i]
		f.position = p
		f.basis = Basis.looking_at(tangent, Vector3.UP)
		_tails[i].rotation.y = sin(_t * 5.5 + i * 2.0) * 0.45
		f.rotation.z = sin(_t * 1.1 + i) * 0.06


## [body mesh, tail mesh] of a koi: base colour + spot colour (vertex colours, toon material).
static func _make_fish(base: Color, spot: Color) -> Array:
	var lb := base.srgb_to_linear()
	var ls := spot.srgb_to_linear()
	var g := GeoBuilder.new()
	# body: an elongated blob, forward = -Z
	g.blob(Vector3(0, 0, 0), 0.5, 2, lb, null, 0.0, Vector3(0.32, 0.22, 1.0))
	# spot on the head / back
	g.blob(Vector3(0, 0.07, -0.18), 0.1, 1, ls, null, 0.0, Vector3(1.1, 0.7, 1.1))
	# dorsal and pectoral fins
	g.flat_tri(Vector3(0, 0.1, -0.15), Vector3(0, 0.22, 0.05), Vector3(0, 0.1, 0.22), lb * 0.9)
	g.flat_tri(Vector3(0, 0.1, 0.22), Vector3(0, 0.22, 0.05), Vector3(0, 0.1, -0.15), lb * 0.9)
	for sx: float in [-1.0, 1.0]:
		g.flat_tri(Vector3(sx * 0.12, -0.03, -0.15), Vector3(sx * 0.3, -0.08, -0.02), Vector3(sx * 0.12, -0.04, 0.0), lb)
		g.flat_tri(Vector3(sx * 0.12, -0.04, 0.0), Vector3(sx * 0.3, -0.08, -0.02), Vector3(sx * 0.12, -0.03, -0.15), lb)
		# eyes
		g.blob(Vector3(sx * 0.1, 0.04, -0.4), 0.025, 0, ls)
	var t := GeoBuilder.new()
	for sy: float in [-1.0, 1.0]:
		t.flat_tri(Vector3(0, 0, 0), Vector3(0, sy * 0.18, 0.3), Vector3(0, sy * 0.02, 0.22), lb)
		t.flat_tri(Vector3(0, sy * 0.02, 0.22), Vector3(0, sy * 0.18, 0.3), Vector3(0, 0, 0), lb)
	var mat := ToonMaterials.make(Color.WHITE, {"vertex_color": true, "outline": true, "outline_width": 0.6, "rim": 0.5,
		"emission": Color(0.10, 0.13, 0.16), "emission_energy": 1.0})
	return [g.to_mesh(mat), t.to_mesh(mat)]
