class_name PlayerStates
extends RefCounted
## The player's state machine. Every state other than Locomotion/Airborne has
## an exit path AND a timeout, so the player can never get stuck:
##
## | state        | exit                                   | timeout                 |
## | Locomotion   | -                                      | -                       |
## | Airborne     | landing                                | 6 s motionless -> Loco  |
## | Dodge/Action | ability finished / cancelled           | ability max_time + 1 s  |
## | Defend       | block released / chi out / guard break | 120 s                   |
## | HitStun      | stun time                              | 2 s                     |
## | KnockedDown  | down time -> GetUp                     | 4 s                     |
## | GetUp        | clip end (i-frames)                    | 1.2 s                   |
## | Dead         | respawn_at()                           | auto respawn 8 s        |
## | Mounted      | dismount() / seat freed                | -                       |
## | Interacting  | lock time / end_interaction()          | 10 s                    |
## | Cinematic    | exit_cinematic()                       | given (default 120 s)   |

const S := PlayerCharacter.State
## action -> controller slot, in priority order.
const BENDING_INPUTS: Array = [
	[&"dodge", &"dodge"], [&"block", &"defense"], [&"attack_light", &"light"], [&"attack_heavy", &"heavy"],
	[&"ability_1", &"technique_1"], [&"ability_2", &"technique_2"], [&"ability_3", &"technique_3"], [&"ability_4", &"technique_4"],
	[&"ability_special", &"signature"],
]
const SLOT_ACTION := {&"dodge": &"dodge", &"defense": &"block", &"light": &"attack_light", &"heavy": &"attack_heavy",
	&"technique_1": &"ability_1", &"technique_2": &"ability_2", &"technique_3": &"ability_3", &"technique_4": &"ability_4",
	&"signature": &"ability_special"}

var p: PlayerCharacter
var state: int = S.LOCOMOTION
var prev_state: int = S.LOCOMOTION
var state_time := 0.0
var timeout := INF
## HitStun / KnockedDown bookkeeping.
var stun_left := 0.0
var down_airborne := false
var getup_iframes := 0.0
var _air_grace := 0.0
var _still_air := 0.0


func _init(player: PlayerCharacter) -> void:
	p = player


func change(s: int, p_timeout: float = INF) -> void:
	if s == state and s != S.HITSTUN:
		timeout = p_timeout
		return
	prev_state = state
	_exit(state)
	state = s
	state_time = 0.0
	timeout = p_timeout
	p.state_changed.emit(state, prev_state)


func _exit(s: int) -> void:
	if s == S.INTERACTING:
		p.visual.stop(0.15)


func name_of(s: int) -> String:
	return PlayerCharacter.State.keys()[s]


func is_free() -> bool:
	return state == S.LOCOMOTION or state == S.AIRBORNE


# --- tick ------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	state_time += delta
	if state_time > timeout:
		_on_timeout()
	match state:
		S.LOCOMOTION, S.AIRBORNE:
			_free(delta)
		S.DODGE, S.ACTION, S.DEFEND:
			_ability(delta)
		S.HITSTUN:
			_hitstun(delta)
		S.KNOCKED_DOWN:
			_down(delta)
		S.GETUP:
			_getup(delta)
		S.DEAD:
			p.motor.brake(delta, 12.0)
			p.motor.integrate(delta)
		S.MOUNTED:
			p.update_mounted(delta)
		S.INTERACTING:
			p.motor.brake(delta, 30.0)
			p.motor.integrate(delta)
		S.CINEMATIC:
			p.motor.brake(delta, 30.0)
			p.motor.integrate(delta)


func _on_timeout() -> void:
	match state:
		S.AIRBORNE:
			# Wedged somewhere without ever landing: treat as grounded.
			change(S.LOCOMOTION)
		S.DODGE, S.ACTION, S.DEFEND:
			p.controller.cancel_current(&"timeout")
			_back_to_free()
		S.HITSTUN:
			_back_to_free()
		S.KNOCKED_DOWN:
			_start_getup()
		S.GETUP:
			_back_to_free()
		S.DEAD:
			if p.auto_respawn:
				p.respawn_at(Transform3D(Basis(Vector3.UP, p.motor.yaw), p.motor.last_safe_position()))
			else:
				timeout = INF
		S.INTERACTING:
			p.end_interaction()
		S.CINEMATIC:
			p.exit_cinematic()
		_:
			_back_to_free()


func _back_to_free() -> void:
	change(S.LOCOMOTION if p.motor.on_floor or p.motor.swimming else S.AIRBORNE)


# --- free movement -------------------------------------------------------------------------

func _free(delta: float) -> void:
	var m := p.motor
	var inp := p.input
	# Jump / air jump / glide.
	if inp.consume(&"jump"):
		m.press_jump()
		if m.swimming:
			m.try_swim_exit()
		elif not m.try_ground_jump() and not m.on_floor and m.since_floor > m.profile.coyote_time:
			m.try_air_jump()
	else:
		# A jump pressed just before landing fires on touchdown (jump buffer).
		m.try_ground_jump()
	if inp.just_released(&"jump"):
		m.release_jump()
		m.set_gliding(false)
	if m.profile.can_glide() and not m.on_floor and inp.is_held(&"jump") and p.velocity.y < -0.5 and m.air_time > 0.25:
		m.set_gliding(true)
	elif m.gliding and (m.on_floor or not inp.is_held(&"jump")):
		m.set_gliding(false)
	# Bending (buffered presses fire on the first frame they are allowed).
	if _try_bending(state == S.AIRBORNE):
		return
	# Interact / lock-on.
	if inp.consume(&"interact"):
		p.try_interact()
		if state != S.LOCOMOTION and state != S.AIRBORNE:
			return
	# Movement.
	var face := p.strafe_direction()
	if m.swimming:
		m.swim(delta, inp.move_vector, inp.sprinting)
	elif m.on_floor:
		m.locomote(delta, inp.move_vector, inp.sprinting, face)
	else:
		m.air_move(delta, inp.move_vector, inp.sprinting, face)
	m.integrate(delta, 1.0)
	# Airborne <-> locomotion (short grace so small bumps never flicker states).
	if m.on_floor or m.swimming:
		_air_grace = 0.0
		_still_air = 0.0
		if state == S.AIRBORNE:
			change(S.LOCOMOTION)
	else:
		_air_grace += delta
		if state == S.LOCOMOTION and (_air_grace > 0.1 or p.velocity.y > 1.0):
			change(S.AIRBORNE, INF)
		if state == S.AIRBORNE:
			_still_air = _still_air + delta if p.velocity.length() < 0.4 else 0.0
			if _still_air > 6.0:
				_on_timeout()


## Tries buffered bending presses in priority order. Returns true when one started.
func _try_bending(airborne: bool) -> bool:
	var inp := p.input
	for pair: Array in BENDING_INPUTS:
		var action: StringName = pair[0]
		var slot: StringName = pair[1]
		if not inp.peek(action):
			continue
		if airborne and not p.can_bend_airborne(slot):
			continue
		if p.motor.swimming:
			inp.consume(action)
			continue
		var why := p.controller.request(slot)
		if why == &"":
			inp.consume(action)
			if not inp.is_held(action):
				# Tapped and released while buffered: it is a tap.
				p.controller.release(slot)
			_enter_for_current()
			return true
		if why != &"busy":
			inp.consume(action)
	return false


func _enter_for_current() -> void:
	var a := p.controller.current
	if a == null:
		_back_to_free()
		return
	var to := S.ACTION
	match p.controller.current_kind():
		&"dodge": to = S.DODGE
		&"defense": to = S.DEFEND
	change(to, a.max_time + 1.0)
	p.on_ability_started(a)


# --- abilities -------------------------------------------------------------------------------

func _ability(delta: float) -> void:
	var c := p.controller
	if not c.is_busy():
		_back_to_free()
		_free_after_ability(delta)
		return
	var inp := p.input
	# Holds / charges end when their button is no longer held.
	if c.current != null and c.current.input_held and not inp.is_held(SLOT_ACTION.get(c.current.slot, &"")):
		c.release(c.current.slot)
	# Cancels / chains from buffered presses.
	var before := c.current
	if _try_bending(not p.motor.on_floor):
		if c.current != before:
			return
	_apply_request(delta)


## Applies the running ability's movement request to the body.
func _apply_request(delta: float) -> void:
	var ctx := p.ctx
	var m := p.motor
	match ctx.move_mode:
		BendingContext.Move.BRAKE:
			if m.on_floor:
				m.brake(delta, ctx.brake_rate)
			else:
				m.air_move(delta, Vector3.ZERO, false)
		BendingContext.Move.FREE:
			var mv := p.input.move_vector * ctx.move_speed_scale
			if m.on_floor:
				m.locomote(delta, mv, false, ctx.face_dir if ctx.face_dir != Vector3.ZERO else p.strafe_direction())
			else:
				m.air_move(delta, mv, false)
		BendingContext.Move.DRIVE:
			m.drive(delta, ctx.move_velocity, 400.0)
		BendingContext.Move.HOLD:
			p.velocity.x = 0.0
			p.velocity.z = 0.0
		BendingContext.Move.ROOT:
			var rm := p.visual.rig.consume_root_motion() if p.visual.rig else Vector3.ZERO
			p.velocity.x = rm.x / maxf(delta, 0.0001)
			p.velocity.z = rm.z / maxf(delta, 0.0001)
	if ctx.face_dir != Vector3.ZERO and ctx.move_mode != BendingContext.Move.FREE:
		m.face_toward(ctx.face_dir, delta, ctx.face_rate)
	elif ctx.face_dir != Vector3.ZERO:
		m.face_toward(ctx.face_dir, delta, ctx.face_rate)
	m.integrate(delta, ctx.gravity_scale)


func _free_after_ability(delta: float) -> void:
	# Same tick: keep moving so there is no dead frame after an action.
	if state == S.LOCOMOTION or state == S.AIRBORNE:
		var m := p.motor
		if m.on_floor:
			m.locomote(delta, p.input.move_vector, p.input.sprinting, p.strafe_direction())
		else:
			m.air_move(delta, p.input.move_vector, p.input.sprinting)
		m.integrate(delta)


# --- reactions ---------------------------------------------------------------------------------

func enter_hitstun(seconds: float) -> void:
	stun_left = clampf(seconds, 0.12, 2.0)
	change(S.HITSTUN, 2.0)


func _hitstun(delta: float) -> void:
	stun_left -= delta
	var m := p.motor
	if m.on_floor:
		m.brake(delta, 16.0)
	m.integrate(delta)
	if stun_left <= 0.0:
		_back_to_free()


func enter_knockdown(airborne: bool, down_time: float = 0.9) -> void:
	down_airborne = airborne
	stun_left = down_time
	change(S.KNOCKED_DOWN, 4.0)


func _down(delta: float) -> void:
	var m := p.motor
	if down_airborne:
		m.integrate(delta)
		if m.on_floor and state_time > 0.1:
			down_airborne = false
			p.visual.land(m.impact_speed)
			p.visual.set_pose(&"knocked_down", 0.05)
		return
	if m.on_floor:
		m.brake(delta, 10.0)
	m.integrate(delta)
	stun_left -= delta
	if stun_left <= 0.0:
		_start_getup()


func _start_getup() -> void:
	var d := RigReactions.get_up(p.visual.rig) if p.visual.rig else 0.6
	getup_iframes = 0.6
	change(S.GETUP, clampf(d, 0.4, 1.2))


func _getup(delta: float) -> void:
	getup_iframes = maxf(0.0, getup_iframes - delta)
	p.motor.brake(delta, 30.0)
	p.motor.integrate(delta)
	# Getting up can be cancelled into a dodge after the i-frames.
	if getup_iframes <= 0.0 and p.input.peek(&"dodge"):
		_back_to_free()
