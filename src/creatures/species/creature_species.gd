class_name CreatureSpecies
extends RefCounted
## Base class for a creature species: builds the body (skeleton, legs, meshes,
## materials, sockets, gaits) and poses it every frame from the rig's locomotion
## state. Provides a shared action library (sniff, look_around, yawn, shake, sit,
## lie_down, rear_up, eat, bite, swipe, scratch, vocalizations...) that species tune
## through `tune` values or override in make_action()/action_pose().

## Size multiplier from config.scale (all lengths are built multiplied by it).
var k := 1.0
var cfg: Dictionary = {}
var rng := RandomNumberGenerator.new()

## Tunables used by the shared actions (meters/radians at k = 1; species override).
var tune := {
	"sit_pitch": 0.42, "sit_drop": 0.25, "lie_drop": 0.7, "rear_pitch": 0.75,
	"neck_down": -0.75, "head_up": 0.55, "roar_jaw": 1.0, "shake_roll": 0.22,
	"vocal": &"", "vocal_event": &"call", "bite_reach": 0.5, "hind_tuck": Vector3(0, 0.4, -0.3),
}


## Species id (&"sky_bison", ...).
func id() -> StringName:
	return &""


## Builds the creature into `rig`: must set rig.skel, rig.motor, rig.legs, rig.gaits,
## create the mesh via rig.finish_build(kit, materials) and define sockets.
func build(_rig: CreatureRig) -> void:
	pass


## Builds the skinned geometry (cached per species/mesh_key/detail by CreatureRig).
func build_mesh(_rig: CreatureRig, _kit: MeshKit) -> void:
	pass


## Values that change the generated mesh (scale, colors that are baked...).
func mesh_key() -> String:
	return "%f|%s" % [k, str(cfg.get("colors", {}))]


## Material for a mesh surface at a detail level (0..3) and LOD tier (0..2).
func material_for(_surface: StringName, _detail: int, _lod: int) -> Material:
	return CreatureMaterials.skin("default", Color.WHITE)


## Distance beyond which the mesh is hidden (meters).
func draw_distance() -> float:
	return 600.0


## Color from config "colors" overrides, or the species default.
func color(key: String, fallback: Color) -> Color:
	var c: Dictionary = cfg.get("colors", {})
	return c.get(key, fallback)


func can_fly() -> bool:
	return false


## Fills the pose channels from locomotion before actions are applied.
func animate(rig: CreatureRig, pose: CreaturePose, _delta: float) -> void:
	default_locomotion_pose(rig, pose)


## Flight pose (flyers override). Called with rig.flight_w > 0.
func flight_pose(_rig: CreatureRig, _pose: CreaturePose, _delta: float) -> void:
	pass


## Extra per-frame bone work after the body is posed and before leg IK
## (wings, trailing spines...).
func post_pose(_rig: CreatureRig, _delta: float) -> void:
	pass


## Last bone work after legs and springs (claws, extra props).
func final_pose(_rig: CreatureRig, _delta: float) -> void:
	pass


## Idle behaviours this species picks from when standing still.
func idle_actions() -> Array[StringName]:
	return [&"look_around", &"sniff", &"ear_twitch", &"yawn"]


## Name of the sound to play for an action event, or &"".
func sound_for(_action: StringName, _event: StringName) -> StringName:
	return &""


# --- Shared locomotion pose -------------------------------------------------------------

## Generic body motion from the gait engine: support height/pitch/roll, gait
## oscillations, lean into turns and acceleration, tail/ears dynamics, breathing.
func default_locomotion_pose(rig: CreatureRig, pose: CreaturePose) -> void:
	var ge := rig.gait
	var y0 := rig.global_position.y
	# Terrain: body height follows the average support height, pitch the front/hind slope.
	var front := ge.support_y[CreatureLeg.Group.FRONT] if ge.support_valid[0] else y0
	var hind := ge.support_y[CreatureLeg.Group.HIND] if ge.support_valid[2] else front
	var avg := (front + hind) * 0.5
	var span := maxf(absf(rig.motor.hind_z - rig.motor.front_z), 0.5)
	pose.body_y += clampf(avg - y0, -2.0 * k, 2.0 * k)
	pose.body_pitch += clampf(atan2(front - hind, span), -0.5, 0.5) * 0.85
	pose.body_roll += clampf(atan2(-ge.support_roll, rig.width_hint * 0.8), -0.3, 0.3) * 0.6
	# Gait oscillations.
	pose.body_y += ge.out_bob * k
	pose.body_pitch += ge.out_pitch
	pose.body_roll += ge.out_roll
	pose.body_x += ge.out_sway * k
	pose.spine_yaw += ge.out_spine_yaw
	pose.spine_pitch += ge.out_spine_pitch
	pose.head_pitch += ge.out_head
	# Lean into turns, pitch with acceleration, bend the spine into the turn.
	var turn := clampf(rig.yaw_rate, -2.5, 2.5)
	var spd := ge.speed
	pose.body_roll += -turn * clampf(spd / maxf(rig.run_speed, 0.1), 0.0, 1.0) * 0.12
	pose.spine_yaw += turn * 0.22
	pose.neck_yaw += turn * 0.18
	pose.head_yaw += turn * 0.12
	pose.body_pitch += clampf(-rig.local_accel.z * 0.012, -0.12, 0.12)
	# Tail: lifts with speed, counter-swings turns.
	pose.tail_pitch += clampf(spd / maxf(rig.run_speed, 0.1), 0.0, 1.3) * 0.18
	pose.tail_yaw += -turn * 0.25
	pose.ears_back += clampf(spd / maxf(rig.run_speed * 1.4, 0.1), 0.0, 1.0) * 0.6
	pose.breath += sin(rig.time * TAU / maxf(rig.breath_period * (1.0 - 0.45 * clampf(spd / maxf(rig.run_speed, 0.1), 0.0, 1.0)), 0.5))


# --- Shared actions ---------------------------------------------------------------------

## Creates an action (or null if this species does not support it).
func make_action(action_name: StringName, opts: Dictionary) -> CreatureAction:
	var a: CreatureAction = null
	match action_name:
		&"sniff":
			a = CreatureAction.new(action_name, 2.2)
		&"look_around":
			a = CreatureAction.new(action_name, 3.4)
		&"ear_twitch":
			a = CreatureAction.new(action_name, 0.45)
			a.blend_in = 0.05
			a.blend_out = 0.15
			a.opts["side"] = -1.0 if rng.randf() < 0.5 else 1.0
		&"yawn":
			a = CreatureAction.new(action_name, 2.6)
			a.add_event(0.9, &"yawn")
		&"shake":
			a = CreatureAction.new(action_name, 1.7)
			a.roots = true
			a.add_event(0.25, &"shake")
		&"roar", &"call", &"howl", &"bark", &"growl":
			a = CreatureAction.new(action_name, float(opts.get("duration", 2.2 if action_name != &"bark" else 0.7)))
			a.add_event(a.duration * 0.25, &"vocal_start")
			a.add_event(a.duration * 0.78, &"vocal_end")
		&"sit":
			a = CreatureAction.new(action_name, 0.9)
			a.opts["intro"] = 0.9
			a.hold = true
			a.roots = true
			a.cancel_on_move = true
			a.blend_out = 0.6
		&"lie_down":
			a = CreatureAction.new(action_name, 1.6)
			a.opts["intro"] = 1.6
			a.hold = true
			a.roots = true
			a.cancel_on_move = true
			a.blend_out = 1.0
		&"rear_up":
			a = CreatureAction.new(action_name, 2.2)
			a.roots = true
			a.blend_in = 0.35
			a.blend_out = 0.5
			a.add_event(0.7, &"peak")
			a.add_event(1.65, &"land")
		&"eat":
			a = CreatureAction.new(action_name, 3.2)
			a.roots = true
			a.add_event(1.0, &"chew")
		&"bite":
			a = CreatureAction.new(action_name, 0.75)
			a.blend_in = 0.08
			a.blend_out = 0.2
			a.add_event(0.32, &"hit")
		&"swipe":
			a = CreatureAction.new(action_name, 0.9)
			a.blend_in = 0.1
			a.blend_out = 0.25
			a.opts["side"] = float(opts.get("side", 1.0))
			a.add_event(0.42, &"hit")
		&"scratch":
			a = CreatureAction.new(action_name, 2.4)
			a.roots = true
	if a != null:
		a.opts.merge(opts)
	return a


## Applies an action's contribution to the pose (weight = a.weight).
func action_pose(rig: CreatureRig, a: CreatureAction, pose: CreaturePose) -> void:
	var w := a.weight
	var t := a.t
	var p := a.progress()
	match a.name:
		&"sniff":
			var e := a.envelope(0.25, 0.25)
			pose.neck_pitch += tune["neck_down"] * 0.7 * e * w
			pose.head_pitch += -0.25 * e * w
			pose.head_yaw += sin(t * 2.4) * 0.35 * e * w
			pose.sniff += e * w
			pose.head_pitch += sin(t * 52.0) * 0.012 * e * w
			pose.ears_back += -0.3 * e * w
		&"look_around":
			var e := a.envelope(0.15, 0.2)
			var yaw := 0.0
			if p < 0.4:
				yaw = smoothstep(0.0, 0.3, p) * 0.9
			elif p < 0.75:
				yaw = lerpf(0.9, -0.9, smoothstep(0.4, 0.65, p))
			else:
				yaw = -0.9 * (1.0 - smoothstep(0.75, 1.0, p))
			pose.neck_yaw += yaw * 0.6 * e * w
			pose.head_yaw += yaw * 0.5 * e * w
			pose.head_pitch += 0.12 * e * w
			pose.ear_l += 0.3 * sin(p * 9.0) * e * w
		&"ear_twitch":
			var e := sin(p * PI) * w
			if float(a.opts.get("side", 1.0)) < 0.0:
				pose.ear_l += 0.9 * e * sin(p * 25.0)
			else:
				pose.ear_r += 0.9 * e * sin(p * 25.0)
		&"yawn":
			var e := a.window(0.15, 0.85, 0.25)
			pose.jaw += 1.0 * e * w
			pose.head_pitch += 0.45 * e * w
			pose.neck_pitch += 0.15 * e * w
			pose.blink += e * w
			pose.ears_back += 0.6 * e * w
		&"shake":
			var e := a.window(0.05, 0.9, 0.15)
			var osc := sin(t * TAU * 5.5)
			pose.body_roll += osc * tune["shake_roll"] * e * w
			pose.spine_roll += osc * tune["shake_roll"] * 1.4 * e * w
			pose.head_roll += sin(t * TAU * 5.5 + 0.8) * 0.5 * e * w
			pose.ear_l += osc * 1.2 * e * w
			pose.ear_r -= osc * 1.2 * e * w
			pose.tail_yaw += sin(t * TAU * 5.5 + 1.6) * 0.6 * e * w
			pose.blink += e * w
		&"roar", &"call", &"howl", &"bark", &"growl":
			var wind := a.window(0.0, 0.3, 0.15)
			var e := a.window(0.2, 0.92, 0.12)
			var up: float = tune["head_up"] * (1.4 if a.name == &"howl" else (0.4 if a.name == &"growl" else 1.0))
			pose.neck_pitch += (-0.25 * wind + up * 0.6 * e) * w
			pose.head_pitch += (-0.15 * wind + up * 0.5 * e) * w
			pose.jaw += float(tune["roar_jaw"]) * e * w * (0.45 if a.name == &"growl" else 1.0) * (0.8 + 0.2 * sin(t * 30.0))
			pose.ears_back += 0.8 * e * w
			pose.eyes_narrow += 0.6 * e * w
			pose.body_pitch += 0.05 * e * w
			pose.spine_pitch += -0.05 * wind * w
			if a.name == &"howl":
				pose.head_stab += 0.3 * w
		&"sit":
			var e := smoothstep(0.0, 1.0, minf(1.0, t / float(a.opts.get("intro", a.duration))))
			pose.pitch_pivot += 1.0 * w
			pose.body_pitch += float(tune["sit_pitch"]) * e * w
			pose.body_y += -float(tune["sit_drop"]) * k * e * w
			pose.tail_pitch += -0.5 * e * w
			pose.head_pitch += -0.2 * e * w
			pose.neck_pitch += 0.15 * e * w
			pose.head_stab += 0.3 * w
		&"lie_down":
			var pi := minf(1.0, t / float(a.opts.get("intro", a.duration)))
			var e1 := smoothstep(0.0, 0.6, pi)
			var e2 := smoothstep(0.3, 1.0, pi)
			pose.body_y += -float(tune["lie_drop"]) * k * (e1 * 0.55 + e2 * 0.45) * w
			pose.pitch_pivot += -0.3 * w
			pose.body_pitch += 0.04 * e2 * w
			pose.neck_pitch += -0.15 * e2 * w
			pose.head_pitch += -0.1 * e2 * w
			pose.eyes_narrow += 0.65 * e2 * w
			pose.tail_curl += 0.4 * e2 * w
			for l in rig.legs:
				if l.group == CreatureLeg.Group.FRONT:
					pose.add_paw(l.index, Vector3(0, 0, -l.reach() * 0.45) * e2 * w)
				else:
					pose.add_paw(l.index, Vector3(l.side * l.reach() * 0.12, 0, -l.reach() * 0.25) * e2 * w)
		&"rear_up":
			var e := a.window(0.0, 1.0, 0.35)
			pose.pitch_pivot += -1.0 * w
			pose.body_pitch += float(tune["rear_pitch"]) * e * w
			pose.front_free += e * w
			pose.neck_pitch += -0.25 * e * w
			pose.head_pitch += -0.35 * e * w
			pose.head_stab += 0.25 * w
			pose.jaw += 0.6 * a.window(0.3, 0.75, 0.1) * w
			pose.tail_pitch += -0.4 * e * w
			for l in rig.legs:
				if l.group == CreatureLeg.Group.FRONT:
					var paw := sin(t * 7.0 + l.side) * 0.18 * l.reach()
					pose.add_paw(l.index, Vector3(0, paw, -0.15 * l.reach()) * e * w)
		&"eat":
			var e := a.envelope(0.2, 0.2)
			pose.neck_pitch += float(tune["neck_down"]) * e * w
			pose.head_pitch += -0.35 * e * w
			pose.jaw += (0.25 + 0.25 * sin(t * 9.0)) * a.window(0.25, 0.9, 0.1) * w
			pose.eyes_narrow += 0.3 * e * w
		&"bite":
			var wind := a.window(0.0, 0.4, 0.2)
			var strike := a.window(0.3, 0.7, 0.12)
			pose.neck_pitch += (0.2 * wind - 0.25 * strike) * w
			pose.body_z += (0.15 * wind - float(tune["bite_reach"]) * strike) * k * w
			pose.jaw += (0.9 * wind * (1.0 - strike) + 0.1) * w
			pose.ears_back += 0.9 * (wind + strike) * w
			pose.body_pitch += -0.06 * strike * w
		&"swipe":
			var side := float(a.opts.get("side", 1.0))
			var wind := a.window(0.0, 0.45, 0.2)
			var strike := a.window(0.35, 0.8, 0.12)
			pose.body_roll += side * (0.1 * wind - 0.12 * strike) * w
			pose.pitch_pivot += -0.5 * w
			pose.body_pitch += 0.12 * (wind + strike) * w
			pose.head_yaw += side * 0.3 * strike * w
			for l in rig.legs:
				if l.group == CreatureLeg.Group.FRONT and signf(l.side) == signf(side):
					var r := l.reach()
					rig.set_leg_free(l.index, (wind + strike) * w)
					pose.add_paw(l.index, (Vector3(side * 0.3 * r, 0.6 * r, -0.4 * r) * wind
							+ Vector3(-side * 0.5 * r, 0.25 * r, -0.7 * r) * strike) * w)
		&"scratch":
			var e := a.window(0.0, 1.0, 0.2)
			pose.pitch_pivot += 1.0 * w
			pose.body_pitch += float(tune["sit_pitch"]) * 0.8 * e * w
			pose.body_y += -float(tune["sit_drop"]) * k * 0.8 * e * w
			pose.body_roll += 0.12 * e * w
			pose.head_roll += 0.45 * e * w
			pose.head_yaw += -0.35 * e * w
			pose.eyes_narrow += 0.8 * e * w
			for l in rig.legs:
				if l.group == CreatureLeg.Group.HIND and l.side > 0.0:
					rig.set_leg_free(l.index, a.window(0.15, 0.9, 0.12) * w)
					var r := l.reach()
					var sc := sin(t * TAU * 6.0) * 0.12 * r
					pose.add_paw(l.index, Vector3(0.1 * r, 0.75 * r + sc, -0.9 * r) * e * w)
