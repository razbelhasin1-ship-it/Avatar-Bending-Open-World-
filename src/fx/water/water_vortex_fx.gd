class_name WaterVortexFx
extends Node3D
## Tidal Torrent's spiralling water vortex: several thick water streams
## corkscrewing up around the bender (WaterStream), a water column lifting the
## bender, and a swirling ring wave at the base. The ability drives it:
##
##   var v := WaterVortexFx.spawn(self, center, 3.5, 5.5)
##   v.tick(center, power, lift, delta)    # every frame: follow, grow (power 0..1)
##   v.collapse()                          # streams fall, column drains, frees itself

var streams: Array[WaterStream] = []
var column: MeshInstance3D
var column_mat: ShaderMaterial
var skirt: MeshInstance3D
var skirt_mat: ShaderMaterial
var center := Vector3.ZERO
var radius := 3.5
var height := 5.5
var power := 0.0
var lift := 0.0
var phase := 0.0
var _collapse := -1.0
var _n := 4


static func spawn(from: Node, p_center: Vector3, p_radius: float = 3.5, p_height: float = 5.5) -> WaterVortexFx:
	var v := WaterVortexFx.new()
	v.name = "WaterVortex"
	FxLib.root(from).add_child(v)
	v._build(p_center, p_radius, p_height)
	return v


func _build(p_center: Vector3, p_radius: float, p_height: float) -> void:
	center = p_center
	radius = p_radius
	height = p_height
	_n = 4 if FxLib.tier() > 0 else 3
	for i in _n:
		streams.append(WaterStream.spawn(self))
	column = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 18
	cyl.rings = 3
	cyl.cap_top = false
	cyl.cap_bottom = false
	column.mesh = cyl
	column_mat = WaterWaveFx.material()
	column_mat.set_shader_parameter(&"flow", -2.2)
	column_mat.set_shader_parameter(&"streak_scale", Vector2(5.0, 2.0))
	column_mat.set_shader_parameter(&"vertex_foam", 0.0)
	column_mat.set_shader_parameter(&"foam_floor", 0.2)
	column.material_override = column_mat
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(column)
	skirt = MeshInstance3D.new()
	skirt.mesh = WaterMeshes.crest(TAU, 2.0, 0.9, 0.9, 40)
	skirt_mat = WaterWaveFx.material()
	skirt_mat.set_shader_parameter(&"streak_scale", Vector2(14.0, 1.2))
	skirt.material_override = skirt_mat
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(skirt)
	global_position = center
	tick(center, 0.0, 0.0, 0.0)


## Follows `p_center` (ground point under the bender); power 0..1 grows the
## vortex; lift = height of the water column under the bender's feet.
func tick(p_center: Vector3, p_power: float, p_lift: float, delta: float) -> void:
	if _collapse >= 0.0:
		return
	center = p_center
	power = clampf(p_power, 0.0, 1.0)
	lift = maxf(p_lift, 0.0)
	global_position = center
	phase += delta * (3.0 + power * 4.5)
	var r := lerpf(1.2, radius, power)
	var h := lerpf(1.5, height, power)
	for s in _n:
		var st := streams[s]
		if not is_instance_valid(st):
			continue
		var pts := PackedVector3Array()
		var m := 12
		for k in m:
			var u := float(k) / (m - 1)
			var a := phase * (1.0 + 0.15 * float(s % 2)) + u * 3.6 + TAU * float(s) / _n
			var rr := lerpf(r * 0.55, r, sqrt(u)) * (1.0 + 0.08 * sin(phase * 2.0 + float(s)))
			pts.append(center + Vector3(cos(a) * rr, 0.15 + u * h, sin(a) * rr))
		st.set_points(pts, (0.2 + 0.2 * power), 0.12 + 0.1 * power)
		st.set_spray(power > 0.3)
	column.visible = lift > 0.05
	if column.visible:
		column.scale = Vector3(1.0, lift + 0.2, 1.0)
		column.position = Vector3(0, (lift + 0.2) * 0.5 - 0.1, 0)
	skirt.scale = Vector3(0.6 + power * 0.9, 0.4 + power * 0.8, 0.6 + power * 0.9)
	skirt.rotation.y = phase * 0.6


## The vortex is thrown: streams retract, column and skirt drain away.
func collapse(duration: float = 0.5) -> void:
	if _collapse >= 0.0:
		return
	_collapse = 0.0
	for st in streams:
		if is_instance_valid(st):
			st.finish(duration * 0.6)
	streams.clear()
	set_meta(&"collapse_time", maxf(duration, 0.1))
	FxBurst.spawn(self, &"spray", center + Vector3.UP * 1.0, {"count": 1.5, "size": 1.6, "radius": 2.5, "spread": 90.0})


func _process(delta: float) -> void:
	if _collapse < 0.0:
		return
	_collapse += delta
	var d := float(get_meta(&"collapse_time", 0.5))
	var k := clampf(_collapse / d, 0.0, 1.0)
	column_mat.set_shader_parameter(&"fade", 1.0 - k)
	skirt_mat.set_shader_parameter(&"fade", 1.0 - k)
	column.scale.y = maxf(0.05, (lift + 0.2) * (1.0 - k))
	skirt.scale.y *= 1.0 - k * 0.2
	if k >= 1.0:
		queue_free()


func _exit_tree() -> void:
	for st in streams:
		if is_instance_valid(st):
			st.finish(0.1)
	streams.clear()
