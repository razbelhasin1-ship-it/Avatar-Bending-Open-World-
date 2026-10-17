class_name IcePrisonFx
extends Node3D
## Ice encasing a frozen target's legs (Ice Trap, Water Shield parry freeze,
## flash-freeze): crystals snap up around the feet, hold while the FREEZE lasts
## (following the target) and shatter when it ends. Pooled; only shown for
## freezes gameplay applied.
##
##   IcePrisonFx.encase(self, target, 2.0)

var mesh_i: MeshInstance3D
var target: Node3D = null
var duration := 2.0
var size := 1.0
var _t := 0.0
var _done := false


static func encase(from: Node, p_target: Node3D, p_duration: float, p_size: float = 1.0) -> IcePrisonFx:
	if p_target == null or not is_instance_valid(p_target):
		return null
	var f := FxLib.take(from, &"ice_prison", IcePrisonFx._make) as IcePrisonFx
	f.target = p_target
	f.duration = maxf(p_duration, 0.3)
	f.size = p_size
	f._t = 0.0
	f._done = false
	f.mesh_i.mesh = WaterMeshes.ice_prison(0.5, 1.1, randi() % 3)
	f.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU), p_target.global_position)
	f.mesh_i.scale = Vector3(p_size, 0.05, p_size)
	FxBurst.spawn(from, &"snow", p_target.global_position + Vector3.UP * 0.5, {"count": 0.6, "size": 0.6, "color": Color(0.9, 0.97, 1.0)})
	FxBurst.spawn(from, &"sparkle", p_target.global_position + Vector3.UP * 0.8, {"count": 0.8})
	return f


static func _make() -> IcePrisonFx:
	var f := IcePrisonFx.new()
	f.name = "IcePrison"
	f.mesh_i = MeshInstance3D.new()
	f.mesh_i.material_override = FxDebris.ice_material()
	f.mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.add_child(f.mesh_i)
	return f


## Shatters early (target freed, hit out of the ice).
func shatter() -> void:
	if _done:
		return
	_done = true
	var p := global_position
	IceFx.shatter(self, p + Vector3.UP * 0.6, Vector3.ZERO, 0.9 * size, p.y)
	Audio.play_bending(ElementDefs.Element.WATER, &"shatter", p + Vector3.UP * 0.6, -4.0)
	FxLib.release(self)


func fx_reset() -> void:
	_done = true


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if target != null and is_instance_valid(target) and target.is_inside_tree():
		global_position = target.global_position
	elif _t > 0.1:
		shatter()
		return
	var grow := clampf(_t / 0.12, 0.0, 1.0)
	var e := 1.0 + 1.6 * pow(grow - 1.0, 3.0) + 0.6 * pow(grow - 1.0, 2.0)
	mesh_i.scale = Vector3(size, maxf(0.05, e) * size, size)
	if _t >= duration:
		shatter()
