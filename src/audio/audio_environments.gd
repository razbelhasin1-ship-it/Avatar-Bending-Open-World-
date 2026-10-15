class_name AudioEnvironments
extends RefCounted
## Reverb presets for Audio.set_environment(). One AudioEffectReverb lives at
## the end of the SFX bus (added at runtime, never in project.godot) and its
## parameters glide between presets so walking into a cave is not a hard cut.

const PRESETS := {
	## Open air: a faint slap-back from terrain, almost dry.
	&"open": {"room_size": 0.3, "damping": 0.65, "wet": 0.05, "dry": 1.0, "predelay_msec": 35.0, "predelay_feedback": 0.15, "hipass": 0.25, "spread": 0.8},
	## Forest: soft diffuse tail, highs absorbed by foliage.
	&"forest": {"room_size": 0.45, "damping": 0.8, "wet": 0.09, "dry": 1.0, "predelay_msec": 25.0, "predelay_feedback": 0.2, "hipass": 0.2, "spread": 0.9},
	## Cave / tunnels: long, dark, strong early echoes.
	&"cave": {"room_size": 0.88, "damping": 0.4, "wet": 0.3, "dry": 0.92, "predelay_msec": 55.0, "predelay_feedback": 0.45, "hipass": 0.05, "spread": 1.0},
	## City streets: medium slap from walls.
	&"city": {"room_size": 0.55, "damping": 0.5, "wet": 0.13, "dry": 1.0, "predelay_msec": 45.0, "predelay_feedback": 0.35, "hipass": 0.15, "spread": 0.9},
	## Temple halls: big, smooth stone room.
	&"temple": {"room_size": 0.82, "damping": 0.28, "wet": 0.24, "dry": 0.95, "predelay_msec": 70.0, "predelay_feedback": 0.3, "hipass": 0.1, "spread": 1.0},
	## Ice caverns / walls: bright, glassy reflections.
	&"ice": {"room_size": 0.72, "damping": 0.08, "wet": 0.2, "dry": 0.96, "predelay_msec": 40.0, "predelay_feedback": 0.42, "hipass": 0.2, "spread": 1.0},
}

const KEYS := ["room_size", "damping", "wet", "dry", "predelay_msec", "predelay_feedback", "hipass", "spread"]


static func has_preset(env_name: StringName) -> bool:
	return PRESETS.has(env_name)


static func preset(env_name: StringName) -> Dictionary:
	return PRESETS.get(env_name, PRESETS[&"open"])


## Returns the reverb effect on `bus_name`, adding one if needed.
static func ensure_reverb(bus_name: StringName) -> AudioEffectReverb:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return null
	for i in AudioServer.get_bus_effect_count(idx):
		var e := AudioServer.get_bus_effect(idx, i)
		if e is AudioEffectReverb:
			return e as AudioEffectReverb
	var rv := AudioEffectReverb.new()
	apply(rv, preset(&"open"))
	AudioServer.add_bus_effect(idx, rv)
	return rv


## Writes a preset (or an interpolated dictionary) into the effect.
static func apply(rv: AudioEffectReverb, p: Dictionary) -> void:
	if rv == null:
		return
	rv.room_size = p["room_size"]
	rv.damping = p["damping"]
	rv.wet = p["wet"]
	rv.dry = p["dry"]
	rv.predelay_msec = p["predelay_msec"]
	rv.predelay_feedback = p["predelay_feedback"]
	rv.hipass = p["hipass"]
	rv.spread = p["spread"]


## Linear blend of two presets.
static func blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k: String in KEYS:
		out[k] = lerpf(float(a[k]), float(b[k]), t)
	return out
