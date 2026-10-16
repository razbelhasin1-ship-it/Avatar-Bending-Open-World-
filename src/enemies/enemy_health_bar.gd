class_name EnemyHealthBar
extends Node3D
## Small floating health bar above an enemy: shown while it fights you (within
## SHOW_DISTANCE of the camera) and for a few seconds after it is hurt; a pale
## "damage trail" catches up with the fill so chunks of damage read clearly. Elites
## get a gold frame and a wider bar. Faces the camera; hidden on death.

const WIDTH := 0.82
const HEIGHT := 0.075
const SHOW_DISTANCE := 26.0

var enemy: Node3D
var elite := false
var _bg: MeshInstance3D
var _trail: MeshInstance3D
var _fill: MeshInstance3D
var _frame: MeshInstance3D
var _shown := 0.0
var _trail_v := 1.0
var _value := 1.0
var _hidden := false

static var _quad: QuadMesh = null
static var _mats: Dictionary = {}


func setup(p_enemy: Node3D, height: float, p_elite: bool) -> void:
	enemy = p_enemy
	elite = p_elite
	position = Vector3(0, height, 0)
	name = "HealthBar"


func _ready() -> void:
	var w := WIDTH * (1.45 if elite else 1.0)
	if elite:
		_frame = _make(Color(0.9, 0.7, 0.28), Vector2(w + 0.05, HEIGHT + 0.05), -0.003)
	_bg = _make(Color(0.08, 0.06, 0.06, 0.85), Vector2(w + 0.02, HEIGHT + 0.02), -0.002)
	_trail = _make(Color(0.98, 0.9, 0.75), Vector2(w, HEIGHT), -0.001)
	_fill = _make(Color(0.86, 0.2, 0.14) if not elite else Color(0.92, 0.42, 0.12), Vector2(w, HEIGHT), 0.0)
	visible = false


func _make(c: Color, size: Vector2, z: float) -> MeshInstance3D:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if c.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
		m.disable_receive_shadows = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = m
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = _mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(size.x, size.y, 1.0)
	mi.position = Vector3(0, 0, z)
	add_child(mi)
	return mi


func on_damaged() -> void:
	_shown = 5.0


func hide_now() -> void:
	_hidden = true
	visible = false


func _process(delta: float) -> void:
	if _hidden or enemy == null or not is_instance_valid(enemy):
		visible = false
		return
	_shown = maxf(0.0, _shown - delta)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		visible = false
		return
	var engaged := enemy.has_method("in_combat") and bool(enemy.call("in_combat"))
	var d := cam.global_position.distance_to(global_position)
	var want := (_shown > 0.0 or engaged) and d < SHOW_DISTANCE * (1.6 if elite else 1.0)
	visible = want
	if not want:
		return
	var h: HealthComponent = enemy.get("health")
	_value = h.ratio() if h else 1.0
	_trail_v = _value if _trail_v < _value else move_toward(_trail_v, _value, delta * 0.6)
	var w := WIDTH * (1.45 if elite else 1.0)
	_set_ratio(_fill, _value, w)
	_set_ratio(_trail, _trail_v, w)
	# Face the camera (upright).
	var to := cam.global_position - global_position
	to.y = 0.0
	if to.length_squared() > 1e-4:
		global_basis = Basis.looking_at(-to.normalized(), Vector3.UP)


func _set_ratio(mi: MeshInstance3D, r: float, w: float) -> void:
	r = clampf(r, 0.0, 1.0)
	mi.visible = r > 0.001
	mi.scale.x = maxf(w * r, 0.0001)
	mi.position.x = -w * 0.5 + w * r * 0.5
