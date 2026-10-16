class_name EarthRubble
extends Node3D
## Broken ground that stays a while: tilted slabs jutting up along a fissure,
## chunks around a crater rim, stones scattered by a quake. One MultiMesh per
## set (one draw call), surface-coloured meshes (EarthMeshes), pops up out of
## the ground, stays, then sinks back (6-16 s by Settings detail level).
## Pooled and capped (FxLib).
##
##   EarthRubble.spawn(self, xforms, &"grass", &"chunk")    # Array[Transform3D] on the ground
##   EarthRubble.ring_xforms(center, 1.4, 8, ground_fn)      # helpers that build the transforms

const MAX := 16
## Seconds a set stays, by detail level.
const LIFE := [6.0, 9.0, 12.0, 16.0]
const CAPS := [3, 5, 8, 12]

var mmi: MultiMeshInstance3D
var t := 0.0
var life := 9.0
var rise := 0.12
var sink_depth := 0.55
var _base := Vector3.ZERO

static var _cap_lvl := -1


## Shows `xforms` (at most 16) as broken ground of `surface`. mesh_kind:
## &"chunk" (ground plates with the surface on top) or &"rock".
static func spawn(from: Node, xforms: Array, surface: StringName = &"dirt", mesh_kind: StringName = &"chunk", p_life: float = -1.0) -> EarthRubble:
	if xforms.is_empty():
		return null
	var lvl := clampi(Settings.detail_level(), 0, 3)
	if _cap_lvl != lvl:
		_cap_lvl = lvl
		FxLib.set_cap(&"earth_rubble", CAPS[lvl])
	var r := FxLib.take(from, &"earth_rubble", EarthRubble._make) as EarthRubble
	var v := randi() % 3
	r.mmi.multimesh.mesh = EarthMeshes.chunk(v, surface) if mesh_kind == &"chunk" else EarthMeshes.rock(v, 0, surface)
	var n := mini(xforms.size(), MAX)
	r.mmi.multimesh.visible_instance_count = n
	# Anchor the set at the first transform; instances are relative to it.
	r._base = (xforms[0] as Transform3D).origin
	r.global_transform = Transform3D(Basis.IDENTITY, r._base)
	for i in n:
		var x: Transform3D = xforms[i]
		r.mmi.multimesh.set_instance_transform(i, Transform3D(x.basis, x.origin - r._base))
	r.t = 0.0
	r.life = p_life if p_life > 0.0 else LIFE[lvl]
	r.mmi.position = Vector3.DOWN * 0.3
	FxLib.note(&"earth_rubble")
	return r


static func _make() -> EarthRubble:
	var r := EarthRubble.new()
	r.name = "EarthRubble"
	r.mmi = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	r.mmi.multimesh = mm
	r.mmi.material_override = EarthMeshes.material()
	r.mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if FxLib.tier() >= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(r.mmi)
	return r


func fx_reset() -> void:
	t = life


func _process(delta: float) -> void:
	t += delta
	if t < rise:
		mmi.position = Vector3.DOWN * 0.3 * (1.0 - t / rise)
	elif t > life - 1.2:
		var k := clampf((t - (life - 1.2)) / 1.2, 0.0, 1.0)
		mmi.position = Vector3.DOWN * sink_depth * k * k
	else:
		mmi.position = Vector3.ZERO
	if t >= life:
		mmi.multimesh.visible_instance_count = 0
		FxLib.release(self)


# --- transform helpers ----------------------------------------------------------------------------

## Chunks around a crater rim, tilted outward (`ground_fn(Vector3) -> float` gives
## the ground height; size ~0.35 m).
static func ring_xforms(center: Vector3, radius: float, count: int, ground_fn: Callable, size: float = 0.35) -> Array:
	var out: Array = []
	var a0 := randf() * TAU
	for i in count:
		var a := a0 + TAU * float(i) / count + randf_range(-0.25, 0.25)
		var rr := radius * randf_range(0.85, 1.15)
		var p := center + Vector3(sin(a), 0.0, -cos(a)) * rr
		p.y = float(ground_fn.call(p)) if ground_fn.is_valid() else center.y
		var outward := Vector3(sin(a), 0.0, -cos(a))
		var tilt_axis := outward.cross(Vector3.UP).normalized()
		var b := Basis(Vector3.UP, a + randf_range(-0.6, 0.6)).rotated(tilt_axis, -deg_to_rad(randf_range(18.0, 42.0)))
		var s := size * randf_range(0.7, 1.3)
		out.append(Transform3D(b * Basis.from_scale(Vector3(s, s * randf_range(0.8, 1.3), s)), p + Vector3.UP * s * 0.05))
	return out


## Slabs jutting up along the segment a -> b on both sides of the line, tilted
## away from it (a fissure's broken edges).
static func line_xforms(a: Vector3, b: Vector3, count: int, ground_fn: Callable, size: float = 0.45, spread: float = 0.5) -> Array:
	var out: Array = []
	var d := b - a
	d.y = 0.0
	var dir := d.normalized() if d.length_squared() > 1e-4 else Vector3.FORWARD
	var side := Vector3(-dir.z, 0.0, dir.x)
	for i in count:
		var u := (float(i) + randf_range(0.2, 0.8)) / count
		var sgn := 1.0 if i % 2 == 0 else -1.0
		var p := a.lerp(b, u) + side * sgn * spread * randf_range(0.6, 1.2)
		p.y = float(ground_fn.call(p)) if ground_fn.is_valid() else a.lerp(b, u).y
		var yaw := atan2(-dir.x, -dir.z) + randf_range(-0.35, 0.35)
		var bas := Basis(Vector3.UP, yaw).rotated(dir, sgn * deg_to_rad(randf_range(20.0, 48.0)))
		var s := size * randf_range(0.7, 1.25) * (1.0 - u * 0.35)
		out.append(Transform3D(bas * Basis.from_scale(Vector3(s, s, s)), p))
	return out


## Stones scattered in a disc.
static func scatter_xforms(center: Vector3, radius: float, count: int, ground_fn: Callable, size: float = 0.22) -> Array:
	var out: Array = []
	for i in count:
		var a := randf() * TAU
		var rr := sqrt(randf()) * radius
		var p := center + Vector3(cos(a), 0.0, sin(a)) * rr
		p.y = float(ground_fn.call(p)) if ground_fn.is_valid() else center.y
		var s := size * randf_range(0.6, 1.4)
		var b := Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
		out.append(Transform3D(b * Basis.from_scale(Vector3(s, s * 0.8, s)), p + Vector3.UP * s * 0.25))
	return out
