class_name AnimLibrary
extends RefCounted
## Global registry of pose clips used by every HumanoidRig.
##
##   AnimLibrary.register(&"fire_jab_r", {
##       "length": 0.45, "mask": &"upper",
##       "events": [[0.38, &"release"]],
##       "keys": [
##           [0.25, {"hand_r": Vector3(0.05, -0.15, -0.1), "fist_r": 1.0}, &"inout"],
##           [0.4,  {"hand_r": Vector3(-0.05, 0.0, 0.98), "chest": Vector3(0, -25, 0)}, &"snap"],
##       ],
##   })
##   rig.play_action(&"fire_jab_r")
##
## Clip Dictionary fields (all optional except keys):
##   length (s), loop (bool, keys in [0,1)), mask (&"full", &"upper", &"arms",
##   &"arm_l", &"arm_r", &"legs", &"head"), events ([[t_norm, name]] or
##   {name: t_norm}), plants ([[t_norm, "l"/"r", weight]] footsteps), root
##   ([[t_norm, Vector3(right, up, forward) meters]] root motion), blend_in,
##   blend_out (s), next (clip to chain), then_state (pose state after end),
##   hold (keep the last key instead of returning to the base pose),
##   recover_ease, meta (Dictionary), keys ([[t_norm, {channel: value}, ease]]).
## Channels and units are documented in RigPose. Eases: &"linear", &"in",
## &"out", &"inout", &"snap", &"slow", &"hold".

static var _clips: Dictionary = {}
static var _builtin_loaded := false


## Registers (or replaces) a clip. Returns the compiled clip (null if invalid).
static func register(clip_name: StringName, clip: Dictionary) -> AnimClip:
	_ensure_builtin()
	var c := AnimClip.compile(clip_name, clip)
	if c != null:
		_clips[clip_name] = c
	return c


## Registers `new_name` as a copy of an existing clip (events report new_name).
static func alias(new_name: StringName, existing: StringName) -> AnimClip:
	_ensure_builtin()
	var src: AnimClip = _clips.get(existing, null)
	if src == null:
		push_warning("AnimLibrary.alias: unknown clip '%s'" % existing)
		return null
	var c := src.duplicate_as(new_name)
	_clips[new_name] = c
	return c


static func unregister(clip_name: StringName) -> void:
	_clips.erase(clip_name)


static func get_clip(clip_name: StringName) -> AnimClip:
	_ensure_builtin()
	return _clips.get(clip_name, null)


static func has_clip(clip_name: StringName) -> bool:
	_ensure_builtin()
	return _clips.has(clip_name)


static func clip_names() -> Array:
	_ensure_builtin()
	var out := _clips.keys()
	out.sort()
	return out


static func _ensure_builtin() -> void:
	if _builtin_loaded:
		return
	_builtin_loaded = true
	ClipsCore.register_all()
	ClipsReactions.register_all()
	ClipsCombat.register_all()
	ClipsElements.register_all()
	ClipsLife.register_all()
