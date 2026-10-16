class_name EarthShackleFx
extends Node3D
## Earth Grab's restraint: stone jaws burst out of the ground around a target's
## legs and clamp shut over the shins, a mound of earth piled around them. It
## rides with the gripped target, then crumbles (or snaps shut on empty ground
## and crumbles at once when the grab missed). Pooled (FxLib, cap 4).
##
##   var s := EarthShackleFx.spawn(self, ground_pos, &"dirt", target, 2.5)
##   s.release()          # crumble early (the target broke free / died)

const JAWS := 6

var jaws: Array[MeshInstance3D] = []
var mound: MeshInstance3D
var t := 0.0
var hold := 2.5
var target: Node3D = null
var surface: StringName = &"dirt"
var ground_y := 0.0
var _released := false
var _rel_t := 0.0
var _angles: Array[float] = []
var _radius := 0.5


static func spawn(from: Node, ground_pos: Vector3, p_surface: StringName, p_target: Node3D, p_hold: float, radius: float = 0.46) -> EarthShackleFx:
	FxLib.set_cap(&"earth_shackle", 4)
	var s := FxLib.take(from, &"earth_shackle", EarthShackleFx._make) as EarthShackleFx
	s.global_transform = Transform3D(Basis.IDENTITY, ground_pos)
	s.ground_y = ground_pos.y
	s.surface = p_surface
	s.target = p_target
	s.hold = maxf(p_hold, 0.2)
	s.t = 0.0
	s._released = false
	s._rel_t = 0.0
	s._radius = radius
	s._angles.clear()
	var a0 := randf() * TAU
	for i in JAWS:
		s._angles.append(a0 + TAU * float(i) / JAWS + randf_range(-0.15, 0.15))
		s.jaws[i].mesh = EarthMeshes.jaw(randf_range(0.75, 0.95), i % 3, p_surface)
		s.jaws[i].visible = true
	s.mound.mesh = EarthMeshes.rock(randi() % 6, 1, p_surface)
	s._pose(0.0)
	EarthFx.tear_out(s, ground_pos, 0.5, p_surface)
	FxLib.note(&"earth_shackle")
	return s


static func _make() -> EarthShackleFx:
	var s := EarthShackleFx.new()
	s.name = "EarthShackle"
	for i in JAWS:
		var m := MeshInstance3D.new()
		m.material_override = EarthMeshes.material()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.add_child(m)
		s.jaws.append(m)
	s.mound = MeshInstance3D.new()
	s.mound.material_override = EarthMeshes.material()
	s.mound.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(s.mound)
	return s


## Close 0..1 (0 = buried and splayed, 1 = clamped around the shins).
func _pose(close: float, sink: float = 0.0) -> void:
	var e := 1.0 - pow(1.0 - clampf(close, 0.0, 1.0), 3.0)
	for i in JAWS:
		var a := _angles[i]
		var outward := Vector3(sin(a), 0.0, -cos(a))
		var r := _radius * lerpf(1.5, 1.0, e)
		var p := outward * r + Vector3.DOWN * (lerpf(0.9, 0.0, e) + sink)
		# The jaw mesh curls toward its local +Z: face it so +Z points at the legs.
		var b := Basis.looking_at(outward, Vector3.UP)
		var tilt := deg_to_rad(lerpf(-40.0, 14.0, e))
		b = b.rotated(b.x, tilt)
		jaws[i].transform = Transform3D(b, p)
	mound.transform = Transform3D(Basis.from_scale(Vector3(1.5, 0.45, 1.5) * _radius * 2.0 * maxf(e, 0.05)), Vector3.DOWN * (0.18 + sink))


func release() -> void:
	if _released:
		return
	_released = true
	_rel_t = 0.0
	var c := global_position + Vector3.UP * 0.4
	FxDebris.spawn(self, c, {"count": 8, "size": 0.14, "up": 3.0, "out": 2.5, "ground_y": ground_y, "color": EarthPalette.color(surface, "debris")})
	FxBurst.spawn(self, &"dust", global_position + Vector3.UP * 0.2, {"color": EarthPalette.color(surface, "dust"), "count": 0.8, "size": 0.9})
	BendingFeedback.sound(ElementDefs.Element.EARTH, &"wall_break", c, -6.0)


func fx_reset() -> void:
	_released = true
	_rel_t = 1.0


func _process(delta: float) -> void:
	t += delta
	if _released:
		_rel_t += delta
		_pose(1.0, _rel_t * 2.2)
		if _rel_t >= 0.45:
			FxLib.release(self)
		return
	if target != null and is_instance_valid(target) and target.is_inside_tree():
		var tp := target.global_position
		global_position = Vector3(tp.x, ground_y, tp.z)
	_pose(t / 0.12)
	if t >= hold or (target != null and (not is_instance_valid(target) or not Combat.is_alive(target))):
		release()
