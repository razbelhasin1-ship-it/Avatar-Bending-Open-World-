class_name RigReactions
extends RefCounted
## Maps hit reactions (HitInfo.Reaction or names) + push direction to clips.
## Clip names are suffixed by where the hit came FROM: _front, _back, _left,
## _right (a hit from the front pushes the body backward).

const KIND_BY_REACTION := {
	0: &"flinch", 1: &"flinch", 2: &"stagger", 3: &"knockback", 4: &"knockdown",
	5: &"launch", 6: &"pull", 7: &"freeze",
}


static func kind_name(kind: Variant) -> StringName:
	if kind is int:
		return KIND_BY_REACTION.get(kind, &"flinch")
	return StringName(kind)


## Direction label of the attacker relative to the rig, from the push direction.
static func from_dir(rig: HumanoidRig, world_dir: Vector3) -> StringName:
	if world_dir.length_squared() < 1e-6:
		return &"front"
	var local := rig.skeleton.global_basis.inverse() * world_dir
	local.y = 0.0
	if local.length_squared() < 1e-8:
		return &"front"
	local = local.normalized()
	# Pushed toward +Z (backward) means the hit came from the front.
	if absf(local.z) >= absf(local.x):
		return &"front" if local.z > 0.0 else &"back"
	return &"left" if local.x > 0.0 else &"right"


static func play(rig: HumanoidRig, kind: Variant, world_dir: Vector3, strength: float) -> float:
	if rig.animator == null:
		return 0.0
	var k := kind_name(kind)
	var from := from_dir(rig, world_dir)
	var local := Vector3.ZERO
	if world_dir.length_squared() > 1e-6:
		local = (rig.skeleton.global_basis.inverse() * world_dir)
		local.y = 0.0
		local = local.normalized() if local.length_squared() > 1e-8 else Vector3(0, 0, 1)
	else:
		local = Vector3(0, 0, 1)
	match k:
		&"flinch", &"none":
			rig.animator.flinch(local, strength)
			return 0.0
		&"stagger", &"pull":
			rig.animator.flinch(local, strength * 0.6)
			return rig.play_action(StringName("stagger_%s" % from), {"blend_in": 0.04})
		&"knockback":
			rig.animator.flinch(local, strength * 0.5)
			return rig.play_action(&"knockback_back" if from == &"front" else StringName("stagger_%s" % from), {"blend_in": 0.04})
		&"knockdown":
			if rig.animator.pose_state != &"normal":
				rig.animator.set_pose_state(&"normal", 0.05)
			return rig.play_action(&"knockdown_front" if from == &"back" else &"knockdown_back", {"blend_in": 0.04})
		&"launch":
			return rig.play_action(&"launch", {"blend_in": 0.03})
		&"freeze":
			rig.animator.flinch(local, strength * 0.4)
			rig.animator.paused = true
			var dur := maxf(0.2, strength)
			# Weak reference: the rig may be freed before the freeze ends.
			var wr: WeakRef = weakref(rig)
			rig.get_tree().create_timer(dur, false).timeout.connect(func() -> void:
				var r := wr.get_ref() as HumanoidRig
				if r != null and r.animator:
					r.animator.paused = false)
			return dur
		&"death":
			if rig.animator.pose_state != &"normal":
				rig.animator.set_pose_state(&"normal", 0.05)
			return rig.play_action(&"death_front" if from != &"back" else &"death_back", {"blend_in": 0.05})
		&"getup":
			return get_up(rig)
	rig.animator.flinch(local, strength)
	return 0.0


## Gets up from knocked_down. Returns the clip duration.
static func get_up(rig: HumanoidRig) -> float:
	if rig.animator == null:
		return 0.0
	if rig.animator.pose_state == &"knocked_down":
		rig.animator.set_pose_state(&"normal", 0.0)
	return rig.play_action(&"getup", {"blend_in": 0.0})
