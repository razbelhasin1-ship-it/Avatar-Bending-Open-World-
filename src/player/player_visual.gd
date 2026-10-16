class_name PlayerVisual
extends Node
## Owns the player's HumanoidRig: builds it from the element preset (air_nomad,
## earth_kingdom, fire_nation, water_tribe; style = element) and drives it from
## the gameplay state every physics tick. The rig runs with manual_update so its
## clip events (release / impact) fire on the same physics clock as gameplay.

var body: CharacterBody3D
var rig: HumanoidRig
var element: int = ElementDefs.Element.NONE
## Extra rig config merged over the preset (body, skin, hair, seed ...).
var appearance: Dictionary = {}
## Seconds until the combat stance relaxes (bending, damage, lock-on refresh it).
var combat_timer := 0.0

var _pose: StringName = &"normal"
var _status_amount := 0.0
var _status_color := Color.WHITE
var _held_pose: StringName = &""
var _skate_clip_on := false
var _glide_clip_on := false


func build(p_body: CharacterBody3D, p_element: int, p_appearance: Dictionary = {}) -> HumanoidRig:
	body = p_body
	element = p_element
	appearance = p_appearance
	BendingClips.ensure()
	var prof := LocomotionProfile.for_element(element)
	var cfg := {"preset": prof.rig_preset, "style": prof.rig_style, "seed": int(appearance.get("seed", 11))}
	for k: String in appearance:
		cfg[k] = appearance[k]
	if rig != null and is_instance_valid(rig):
		rig.queue_free()
	rig = HumanoidRig.create(cfg)
	rig.name = "Rig"
	rig.manual_update = true
	rig.emit_footsteps = true
	rig.emit_landed = true
	body.add_child(rig)
	rig.actor = body
	rig.set_style(prof.rig_style)
	rig.auto_lod = false
	rig.set_lod(0)
	_pose = &"normal"
	return rig


## Per physics tick after the body moved. `grounded` = on floor.
func tick(delta: float, grounded: bool) -> void:
	if rig == null:
		return
	combat_timer = maxf(0.0, combat_timer - delta)
	rig.set_combat_stance(combat_timer > 0.0)
	var v := body.velocity
	rig.set_locomotion(Vector3(v.x, 0.0, v.z) if grounded else v, grounded)
	rig.advance(delta)
	if _status_amount > 0.0:
		_status_amount = maxf(0.0, _status_amount - delta * 0.25)
		rig.set_status_tint(_status_color, _status_amount)


func enter_combat(seconds: float = 6.0) -> void:
	combat_timer = maxf(combat_timer, seconds)


## Sets the rig pose state (normal, airborne, falling, blocking, charging,
## swimming, riding, knocked_down, tumbling, dead) if it changed.
func set_pose(state: StringName, blend: float = 0.15) -> void:
	if rig == null or rig.get_pose_state() == state:
		_pose = state
		return
	_pose = state
	rig.set_pose_state(state, blend)


func get_pose() -> StringName:
	return rig.get_pose_state() if rig else &"normal"


func play(clip: StringName, opts: Dictionary = {}) -> float:
	if rig == null or not AnimLibrary.has_clip(clip):
		return 0.0
	_skate_clip_on = false
	_glide_clip_on = false
	return rig.play_action(clip, opts)


func stop(blend: float = 0.12) -> void:
	if rig:
		rig.stop_action(blend)
	_skate_clip_on = false
	_glide_clip_on = false


func current_clip() -> StringName:
	return rig.current_action() if rig else &""


## Looping full-body overlay clips owned by locomotion (skating, gliding).
func set_skating(on: bool) -> void:
	if rig == null:
		return
	if on and not _skate_clip_on:
		rig.play_action(&"water_skate", {"blend_in": 0.2})
		_skate_clip_on = true
	elif not on and _skate_clip_on:
		if rig.current_action() == &"water_skate":
			rig.stop_action(0.25)
		_skate_clip_on = false


func set_gliding(on: bool) -> void:
	if rig == null:
		return
	if on and not _glide_clip_on:
		rig.play_action(&"air_glide", {"blend_in": 0.18})
		_glide_clip_on = true
	elif not on and _glide_clip_on:
		if rig.current_action() == &"air_glide":
			rig.stop_action(0.2)
		_glide_clip_on = false


func land(impact: float) -> void:
	if rig:
		rig.land(impact)


func flash(color: Color = Color(1, 1, 1), duration: float = 0.16) -> void:
	if rig:
		rig.flash_hit(color, duration)


func reaction(kind: Variant, world_dir: Vector3, strength: float = 1.0) -> float:
	_skate_clip_on = false
	_glide_clip_on = false
	return rig.play_reaction(kind, world_dir, strength) if rig else 0.0


## Status overlay that fades by itself (soaked, frozen, burned).
func tint(color: Color, amount: float) -> void:
	_status_color = color
	_status_amount = maxf(_status_amount, clampf(amount, 0.0, 1.0))


func look_at_point(pos: Vector3, weight: float) -> void:
	if rig:
		rig.look_at_point(pos, weight)


func clear_look() -> void:
	if rig:
		rig.clear_look_at()


func socket(name: StringName) -> Node3D:
	return rig.get_socket(name) if rig else null


func socket_pos(name: StringName) -> Vector3:
	var s := socket(name)
	return s.global_position if s else body.global_position + Vector3.UP * 1.2
