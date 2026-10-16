class_name EarthBurrowFx
extends Node3D
## A ripple running under the ground: a hump of broken earth travels from `a`
## to `b` over `duration` s, shedding dust and clods (Earth Grab's reach - it is
## also the telegraph of where the grab will close). Pooled (FxLib, cap 4).
##
##   EarthBurrowFx.spawn(self, from_ground, to_ground, 0.25, &"dirt", ground_fn)

var hump: MeshInstance3D
var a := Vector3.ZERO
var b := Vector3.ZERO
var duration := 0.25
var t := 0.0
var kind: StringName = &"dirt"
var ground_fn: Callable = Callable()
var _next_puff := 0.0


static func spawn(from: Node, p_a: Vector3, p_b: Vector3, p_duration: float, p_kind: StringName, p_ground_fn: Callable = Callable()) -> EarthBurrowFx:
	FxLib.set_cap(&"earth_burrow", 4)
	var f := FxLib.take(from, &"earth_burrow", EarthBurrowFx._make) as EarthBurrowFx
	f.a = p_a
	f.b = p_b
	f.duration = maxf(p_duration, 0.05)
	f.kind = p_kind
	f.ground_fn = p_ground_fn
	f.t = 0.0
	f._next_puff = 0.0
	f.hump.mesh = EarthMeshes.rock(randi() % 6, 1, p_kind)
	f.global_position = p_a
	f._place(0.0)
	return f


static func _make() -> EarthBurrowFx:
	var f := EarthBurrowFx.new()
	f.name = "EarthBurrow"
	f.hump = MeshInstance3D.new()
	f.hump.material_override = EarthMeshes.material()
	f.hump.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.add_child(f.hump)
	return f


func _place(u: float) -> void:
	var p := a.lerp(b, u)
	if ground_fn.is_valid():
		p.y = float(ground_fn.call(p))
	global_position = p
	var d := b - a
	d.y = 0.0
	if d.length_squared() > 1e-4:
		hump.basis = Basis.looking_at(d.normalized(), Vector3.UP) * Basis.from_scale(Vector3(1.05, 0.62, 1.5))
	# Rises out of the ground at the start, stays proud while running.
	hump.position = Vector3.DOWN * lerpf(0.25, 0.05, clampf(u * 4.0, 0.0, 1.0))


func fx_reset() -> void:
	t = duration + 1.0


func _process(delta: float) -> void:
	t += delta
	var u := clampf(t / duration, 0.0, 1.0)
	_place(u)
	var traveled := a.distance_to(b) * u
	if traveled >= _next_puff and u < 1.0:
		_next_puff += 0.7
		FxBurst.spawn(self, &"dust", global_position, {"color": EarthPalette.color(kind, "dust"), "count": 0.3, "size": 0.55, "speed": 0.6})
		FxDebris.spawn(self, global_position, {"count": 2, "size": 0.07, "up": 2.0, "out": 0.6, "ground_y": global_position.y,
				"color": EarthPalette.color(kind, "debris")})
	if u >= 1.0:
		hump.position = Vector3.DOWN * clampf((t - duration) * 1.5, 0.0, 0.5)
		if t >= duration + 0.3:
			FxLib.release(self)
