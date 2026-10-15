class_name GaitEngine
extends RefCounted
## Phase-driven multi-leg stepping with no foot sliding.
##
## A global cycle phase advances at the gait frequency (which grows with speed); each
## leg lifts when its phase (cycle + per-gait offset) enters the swing window
## (phase >= duty). Planted feet are pinned in WORLD space, so the body moves over
## them without sliding; a swinging foot travels from its lift-off point to a landing
## point predicted from the hip's velocity so that it is under the hip at mid-stance.
## Landing probes the ground (physics ray on Layers.SOLID, WorldData.get_height
## fallback) and emits Events.footstep at the plant moment.
##
## When stopped, legs that are out of place (e.g. after turning on the spot) take
## corrective steps in gait order, then the creature stands still.
##
## Gait dictionaries (see make_gait()): name, max_speed, offsets (per leg), duty, freq,
## ref_speed, freq_exp, lift, bob, bob_mult, bob_phase, pitch, pitch_phase, roll,
## roll_phase, sway, spine_yaw, spine_yaw_phase, spine_pitch, spine_pitch_phase, head_bob.

var legs: Array[CreatureLeg] = []
var gaits: Array[Dictionary] = []
var cur := 0
var prev := 0
var blend := 1.0
var phase := 0.0
var speed := 0.0
var moving := false
## Completed cycles while moving (tests / diagnostics).
var cycles := 0
var footsteps := 0
## 0..1 how much gait oscillation is applied (fades in/out with motion).
var motion_w := 0.0
## Smoothed ground height under each leg group (world y), and lateral difference.
var support_y := PackedFloat32Array([0.0, 0.0, 0.0])
var support_valid := PackedByteArray([0, 0, 0])
var support_roll := 0.0

# Oscillation outputs for the motor (already scaled by motion_w).
var out_bob := 0.0
var out_pitch := 0.0
var out_roll := 0.0
var out_sway := 0.0
var out_spine_yaw := 0.0
var out_spine_pitch := 0.0
var out_head := 0.0

## Speed below which the creature counts as standing.
var stop_speed := 0.12
## Corrective step tolerance as a fraction of leg reach.
var settle_tolerance := 0.16
var settle_freq := 1.4
## Size factor for swing durations (big creatures step slower).
var tempo := 1.0

var _hip_prev: PackedVector3Array = PackedVector3Array()
var _hip_vel: PackedVector3Array = PackedVector3Array()
var _n_off: PackedVector3Array = PackedVector3Array()


## Fills defaults for a gait dictionary.
static func make_gait(d: Dictionary) -> Dictionary:
	var g := {
		"name": &"walk", "max_speed": INF, "offsets": [], "duty": 0.65, "freq": 1.0,
		"ref_speed": 1.5, "freq_exp": 0.5, "lift": 0.15, "bob": 0.03, "bob_mult": 2.0,
		"bob_phase": 0.0, "pitch": 0.0, "pitch_phase": 0.0, "roll": 0.0, "roll_phase": 0.0,
		"sway": 0.0, "spine_yaw": 0.0, "spine_yaw_phase": 0.0, "spine_pitch": 0.0,
		"spine_pitch_phase": 0.0, "head_bob": 0.0,
	}
	g.merge(d, true)
	return g


func setup(skel: RigSkeleton, leg_list: Array[CreatureLeg], gait_list: Array[Dictionary]) -> void:
	legs = leg_list
	gaits = gait_list
	_hip_prev.resize(legs.size())
	_hip_vel.resize(legs.size())
	_n_off.resize(legs.size())
	for i in legs.size():
		var l := legs[i]
		l.index = i
		var hip := skel.rest_pos[l.upper]
		_n_off[i] = Vector3(l.neutral.x - hip.x, 0.0, l.neutral.z - hip.z)


func current_gait() -> StringName:
	return gaits[cur]["name"] if not gaits.is_empty() else &""


## Frequency (cycles/s) of gait `g` at speed `s`.
func gait_freq(g: Dictionary, s: float) -> float:
	var ratio := maxf(s, 0.05) / maxf(float(g["ref_speed"]), 0.05)
	var f := float(g["freq"]) * pow(ratio, float(g["freq_exp"]))
	return clampf(f, float(g["freq"]) * 0.45, float(g["freq"]) * 2.2) / tempo


## Places all feet under their hips (creation / teleport).
func reset_feet(rig: CreatureRig) -> void:
	var xf := rig.global_transform
	for i in legs.size():
		var l := legs[i]
		var hip_w := xf * rig.skel.glob[l.upper].origin
		_hip_prev[i] = hip_w
		_hip_vel[i] = Vector3.ZERO
		var p := _neutral_world(rig, i, hip_w)
		var g := rig.probe_ground(p, hip_w.y + 2.0)
		l.foot_world = Vector3(p.x, g.y, p.z)
		l.ground_normal = rig.last_probe_normal
		l.planted = true
		l.swing_t = 1.0
		l.lift = 0.0
		l.in_window = false
	for k in 3:
		support_valid[k] = 0


## Advances the cycle and steps the legs. `vel` is the world velocity of the creature.
func update(rig: CreatureRig, delta: float, vel: Vector3, can_step: bool) -> void:
	if gaits.is_empty() or legs.is_empty():
		return
	var xf := rig.global_transform
	var hspeed := Vector2(vel.x, vel.z).length()
	speed = lerpf(speed, hspeed, 1.0 - exp(-delta * 10.0))
	moving = speed > stop_speed and can_step
	_select_gait(delta)
	var g0: Dictionary = gaits[prev]
	var g1: Dictionary = gaits[cur]
	var duty := lerpf(float(g0["duty"]), float(g1["duty"]), blend)
	var freq := lerpf(gait_freq(g0, speed), gait_freq(g1, speed), blend)
	# Hip velocities (world), from the previous frame's solved pose.
	for i in legs.size():
		var hip_w := xf * rig.skel.glob[legs[i].upper].origin
		if delta > 0.0:
			var v := (hip_w - _hip_prev[i]) / delta
			if v.length() > 60.0:
				v = vel
			_hip_vel[i] = _hip_vel[i].lerp(v, 1.0 - exp(-delta * 12.0))
		_hip_prev[i] = hip_w
	# Settling when (almost) stopped.
	var needs_settle := false
	if not moving and can_step:
		for i in legs.size():
			var l := legs[i]
			if l.free > 0.5:
				continue
			if not l.planted:
				needs_settle = true
				break
			var nw := _neutral_world(rig, i, _hip_prev[i])
			if Vector2(l.foot_world.x - nw.x, l.foot_world.z - nw.z).length() > settle_tolerance * l.reach():
				needs_settle = true
				break
	var rate := 0.0
	if moving:
		rate = freq
	elif needs_settle:
		rate = gait_freq(gaits[0], float(gaits[0]["ref_speed"])) * settle_freq
	phase += rate * delta
	if phase >= 1.0:
		phase = fmod(phase, 1.0)
		if moving:
			cycles += 1
	motion_w = move_toward(motion_w, 1.0 if moving else 0.0, delta * (3.0 if moving else 2.0))
	# Legs.
	for i in legs.size():
		var l := legs[i]
		if l.free > 0.5:
			l.planted = false
			l.was_free = true
			l.swing_t = 1.0
			l.lift = 0.0
			continue
		if l.was_free and not l.planted and l.swing_t >= 1.0:
			# Coming back to the ground: quick landing step from where the paw hangs.
			l.was_free = false
			l.foot_world = l.paw_world
			_begin_swing(rig, l, clampf(0.22 * tempo, 0.12, 0.5))
		var off := _offset_for(i)
		var p := fposmod(phase + off, 1.0)
		var window := p >= duty and rate > 0.0
		if window and not l.in_window and l.planted and can_step:
			var nw := _neutral_world(rig, i, _hip_prev[i])
			var err := Vector2(l.foot_world.x - nw.x, l.foot_world.z - nw.z).length()
			if moving or err > settle_tolerance * l.reach():
				var sd := (1.0 - duty) / maxf(rate, 0.05)
				_begin_swing(rig, l, clampf(sd, 0.1, 1.2 * tempo))
		l.in_window = window
		# Safety: a planted foot left far behind (sudden dash / teleport) steps at once.
		if l.planted:
			var hw := _hip_prev[i]
			var dxz := Vector2(l.foot_world.x - hw.x, l.foot_world.z - hw.z).length()
			if dxz > l.reach() * 1.15:
				_begin_swing(rig, l, clampf(0.18 * tempo, 0.1, 0.4))
		if not l.planted and l.swing_t < 1.0:
			_advance_swing(rig, l, i, delta, duty, rate)
	_update_support(delta)
	_update_oscillation(g0, g1)


func _select_gait(delta: float) -> void:
	var target := 0
	for i in gaits.size():
		target = i
		var mx := float(gaits[i]["max_speed"])
		# Hysteresis: stay in the current gait 10 % past its limit.
		if i == cur:
			mx *= 1.1
		elif i < cur:
			mx *= 0.9
		if speed <= mx:
			break
	if target != cur:
		prev = cur
		cur = target
		blend = 0.0
	blend = minf(1.0, blend + delta / 0.35)


func _offset_for(i: int) -> float:
	var a: Array = gaits[prev]["offsets"]
	var b: Array = gaits[cur]["offsets"]
	var oa := float(a[i]) if i < a.size() else 0.0
	var ob := float(b[i]) if i < b.size() else 0.0
	# Circular interpolation of phase offsets.
	var d := fposmod(ob - oa + 0.5, 1.0) - 0.5
	return oa + d * blend


func _neutral_world(rig: CreatureRig, i: int, hip_w: Vector3) -> Vector3:
	var l := legs[i]
	var pb := rig.global_transform.basis * rig.skel.glob[rig.skel.parent[l.upper]].basis
	var fwd := -pb.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		fwd = -rig.global_transform.basis.z
		fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var o := _n_off[i]
	return hip_w + right * o.x - fwd * o.z


func _begin_swing(_rig: CreatureRig, l: CreatureLeg, dur: float) -> void:
	l.planted = false
	l.swing_from = l.foot_world
	l.swing_t = 0.0
	l.swing_dur = maxf(dur, 0.05)
	l.swing_to = l.foot_world
	l.lift = 0.0


func _advance_swing(rig: CreatureRig, l: CreatureLeg, i: int, delta: float, duty: float, rate: float) -> void:
	# Re-predicts the landing point every frame so the foot tracks speed/turn changes.
	l.swing_t = minf(1.0, l.swing_t + delta / l.swing_dur)
	var remaining := (1.0 - l.swing_t) * l.swing_dur
	var stance := duty / maxf(rate, 0.05) if moving else 0.0
	var nw := _neutral_world(rig, i, _hip_prev[i])
	var target := nw + Vector3(_hip_vel[i].x, 0.0, _hip_vel[i].z) * (remaining + stance * 0.5)
	var g := rig.probe_ground(target, _hip_prev[i].y + 1.5)
	l.swing_to = Vector3(target.x, g.y, target.z)
	l.ground_normal = rig.last_probe_normal
	var s := l.swing_t
	var e := s * s * (3.0 - 2.0 * s)
	var pos := l.swing_from.lerp(l.swing_to, e)
	var step_len := Vector2(l.swing_to.x - l.swing_from.x, l.swing_to.z - l.swing_from.z).length()
	var gg: Dictionary = gaits[cur]
	var h := float(gg["lift"]) * l.lift_scale * clampf(0.35 + step_len / maxf(l.reach(), 0.1), 0.35, 1.3)
	# Asymmetric arc: lifts quickly, reaches forward, then plants.
	var arc := sin(pow(s, 0.8) * PI)
	pos.y += h * arc
	l.foot_world = pos
	l.lift = s
	if l.swing_t >= 1.0:
		l.planted = true
		l.lift = 0.0
		l.foot_world = l.swing_to
		l.surface = rig.surface_at(l.foot_world)
		footsteps += 1
		rig.on_foot_planted(l)


func _update_support(delta: float) -> void:
	var sums := [0.0, 0.0, 0.0]
	var counts := [0, 0, 0]
	var left := 0.0
	var right := 0.0
	var nl := 0
	var nr := 0
	for l in legs:
		if l.free > 0.5:
			continue
		var y := l.foot_world.y if l.planted else l.swing_to.y
		sums[l.group] += y
		counts[l.group] += 1
		if l.side < 0.0:
			left += y
			nl += 1
		else:
			right += y
			nr += 1
	var k := 1.0 - exp(-delta * 6.0)
	for gi in 3:
		if counts[gi] > 0:
			var avg: float = sums[gi] / counts[gi]
			if support_valid[gi] == 0:
				support_y[gi] = avg
				support_valid[gi] = 1
			else:
				support_y[gi] = lerpf(support_y[gi], avg, k)
	if nl > 0 and nr > 0:
		support_roll = lerpf(support_roll, left / nl - right / nr, k)


func _update_oscillation(g0: Dictionary, g1: Dictionary) -> void:
	var w := motion_w
	var ph := phase * TAU
	out_bob = _osc(g0, g1, "bob", "bob_mult", "bob_phase", ph) * w
	out_pitch = _osc(g0, g1, "pitch", "", "pitch_phase", ph) * w
	out_roll = _osc(g0, g1, "roll", "", "roll_phase", ph) * w
	out_sway = _osc(g0, g1, "sway", "", "roll_phase", ph) * w
	out_spine_yaw = _osc(g0, g1, "spine_yaw", "", "spine_yaw_phase", ph) * w
	out_spine_pitch = _osc(g0, g1, "spine_pitch", "", "spine_pitch_phase", ph) * w
	out_head = _osc(g0, g1, "head_bob", "bob_mult", "bob_phase", ph) * w


func _osc(g0: Dictionary, g1: Dictionary, amp_key: String, mult_key: String, phase_key: String, ph: float) -> float:
	var a := float(g0[amp_key]) * cos((ph * (float(g0[mult_key]) if mult_key != "" else 1.0)) + float(g0[phase_key]) * TAU)
	var b := float(g1[amp_key]) * cos((ph * (float(g1[mult_key]) if mult_key != "" else 1.0)) + float(g1[phase_key]) * TAU)
	return lerpf(a, b, blend)
