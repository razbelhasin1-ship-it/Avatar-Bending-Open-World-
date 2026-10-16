class_name EnemyVisual
extends RefCounted
## The enemy's body visual: a HumanoidRig (soldiers, bandits, benders) or a
## CreatureRig (beasts) behind one small API, so the brain and the attack runner
## never care which one it is.
##
## Telegraphs: windup(clip, hold_at, approach) plays an attack clip up to its
## anticipation key and HOLDS it there (the animator barely creeps on), release()
## lets the strike run on at the attack speed. The rig runs in manual_update and is
## advanced in the enemy's physics tick, so clip events (release / impact) fire on
## the gameplay clock.

const CREEP_SPEED := 0.02
## Prop tip offsets along the prop's +Y (grip space), for glints and hit points.
const PROP_TIPS := {&"club": 0.66, &"sword": 0.72, &"knife": 0.34, &"spear": 1.4, &"hammer": 0.32}

var body: CharacterBody3D
var rig: HumanoidRig = null
var creature: CreatureRig = null
var height := 1.75
var faction: StringName = &""
var props: Dictionary = {}     # socket -> prop name
var bow: EnemyProps.Bow = null
var combat := false

var _hold_clip: StringName = &""
var _hold_at := -1.0
var _holding := false
var _status_amount := 0.0
var _status_color := Color.WHITE
var _death_t := -1.0


func build(p_body: CharacterBody3D, a: Dictionary, seed_v: int) -> void:
	body = p_body
	faction = a.get("faction", &"")
	var look: Dictionary = a.get("look", {})
	if look.has("creature"):
		var cfg := {"seed": seed_v, "scale": float(look.get("scale", 1.0)), "idle": false}
		creature = CreatureRig.create(StringName(look["creature"]), cfg)
		creature.name = "Creature"
		body.add_child(creature)
		creature.footstep_actor = body
		var dims := creature.get_dimensions()
		height = float(dims.get("height", 1.7))
		return
	EnemyClips.ensure()
	BendingClips.ensure()
	var rcfg := {"seed": seed_v}
	for k: String in look:
		rcfg[k] = look[k]
	rig = HumanoidRig.create(rcfg)
	rig.name = "Rig"
	rig.manual_update = true
	rig.emit_footsteps = true
	body.add_child(rig)
	rig.actor = body
	height = rig.get_height()
	for pr: Array in a.get("props", []):
		var n := EnemyProps.attach(rig, StringName(pr[0]), StringName(pr[1]), faction)
		if n != null:
			props[StringName(pr[1])] = StringName(pr[0])
			if n is EnemyProps.Bow:
				bow = n as EnemyProps.Bow


func is_creature() -> bool:
	return creature != null


func node() -> Node3D:
	return rig if rig != null else creature


## Per physics tick after the body moved.
func tick(delta: float, grounded: bool) -> void:
	var v := body.velocity
	if creature:
		creature.set_locomotion(Vector3(v.x, 0.0, v.z) if grounded else v, grounded, delta)
		_tick_death(delta)
		return
	if rig == null:
		return
	rig.set_combat_stance(combat)
	rig.set_locomotion(Vector3(v.x, 0.0, v.z) if grounded else v, grounded)
	_hold_step(delta)
	rig.advance(delta)
	if _status_amount > 0.0:
		_status_amount = maxf(0.0, _status_amount - delta * 0.3)
		rig.set_status_tint(_status_color, _status_amount)
	_tick_bow()


# --- actions --------------------------------------------------------------------------------------

## Plays a clip (humanoid) or action (creature). Returns its duration (s).
func play(clip: StringName, opts: Dictionary = {}) -> float:
	_holding = false
	if creature:
		return creature.play_action(clip, opts)
	if rig == null or not AnimLibrary.has_clip(clip):
		return 0.0
	return rig.play_action(clip, opts)


func stop(blend: float = -1.0) -> void:
	_holding = false
	if creature:
		creature.stop_action()
	elif rig:
		rig.stop_action(blend)


func current_action() -> StringName:
	if creature:
		return creature.current_action()
	return rig.current_action() if rig else &""


## Plays `clip` so that it reaches `hold_at` (normalized) after `approach` s, then holds.
func windup(clip: StringName, hold_at: float, approach: float, opts: Dictionary = {}) -> void:
	if creature:
		creature.play_action(clip, opts)
		return
	var c := AnimLibrary.get_clip(clip)
	if rig == null or c == null:
		return
	var start := float(opts.get("start", 0.0))
	hold_at = maxf(hold_at, start + 0.01)
	var speed := maxf((hold_at - start) * c.length / maxf(approach, 0.04), 0.05)
	rig.play_action(clip, {"speed": speed, "start": start, "blend_in": float(opts.get("blend_in", 0.08)), "mirror": bool(opts.get("mirror", false))})
	_hold_clip = clip
	_hold_at = hold_at
	_holding = true


func is_holding() -> bool:
	return _holding


## Lets a held windup run on at `speed`. Returns seconds until `event` (INF if none).
func release(speed: float = 1.0, event: StringName = &"impact") -> float:
	_holding = false
	if creature or rig == null:
		return INF
	var an := rig.animator
	if an == null or an.action == null:
		return INF
	an.action_speed = maxf(speed, 0.05)
	var et := an.action.event_time(event)
	if et < 0.0 and event == &"impact":
		et = an.action.event_time(&"release")
	if et < 0.0:
		return INF
	return maxf(0.0, (et - an.action_t)) * an.action.length / an.action_speed


func _hold_step(delta: float) -> void:
	if not _holding or rig == null:
		return
	var an := rig.animator
	if an == null or an.action == null or an.action.name != _hold_clip:
		_holding = false
		return
	if an.action_t >= _hold_at:
		an.action_speed = CREEP_SPEED
		return
	# Land exactly on the hold point (no overshoot into the strike).
	var next := an.action_t + delta * an.action_speed / an.action.length
	if next > _hold_at:
		an.action_speed = maxf((_hold_at - an.action_t) * an.action.length / maxf(delta, 1e-4), CREEP_SPEED)


# --- reactions ------------------------------------------------------------------------------------

func reaction(kind: Variant, dir: Vector3, strength: float = 1.0) -> float:
	_holding = false
	if creature:
		creature.flash_hit(1.0)
		var k := RigReactions.kind_name(kind)
		if k in [&"stagger", &"knockback", &"pull"]:
			return creature.play_action(&"shake")
		if k in [&"knockdown", &"launch"]:
			creature.play_action(&"lie_down")
			return 1.2
		return 0.0
	if rig == null:
		return 0.0
	return rig.play_reaction(kind, dir, strength)


func get_up() -> float:
	if creature:
		creature.stop_action()
		return 0.6
	return RigReactions.get_up(rig) if rig else 0.0


func land(impact: float) -> float:
	if rig:
		return rig.land(impact)
	return 0.0


func die(dir: Vector3) -> void:
	_holding = false
	if creature:
		creature.play_action(&"lie_down")
		_death_t = 0.0
		return
	if rig:
		rig.play_reaction(&"death", dir)
		rig.clear_look_at()


func flash(color: Color = Color(1, 1, 1)) -> void:
	if creature:
		creature.flash_hit(1.0)
	elif rig:
		rig.flash_hit(color)


func tint(color: Color, amount: float) -> void:
	_status_color = color
	_status_amount = maxf(_status_amount, amount)
	if creature:
		creature.set_status(color, amount)


func status_from(hit: HitInfo) -> void:
	if hit.status.has("burn"):
		tint(Color(1.0, 0.45, 0.2), 0.45)
	elif hit.status.has("soaked"):
		tint(Color(0.45, 0.7, 1.0), 0.5)
	elif hit.status.has("chill") or hit.status.has("frozen") or hit.reaction == HitInfo.Reaction.FREEZE:
		tint(Color(0.75, 0.92, 1.0), 0.6)


func look_at(p: Vector3, weight: float = 0.9) -> void:
	if creature:
		creature.look_at_point(p, weight)
	elif rig:
		rig.look_at_point(p, weight)


func clear_look() -> void:
	if creature:
		creature.clear_look()
	elif rig:
		rig.clear_look_at()


func set_pose(state: StringName, blend: float = 0.15) -> void:
	if rig and rig.get_pose_state() != state:
		rig.set_pose_state(state, blend)


func get_pose() -> StringName:
	return rig.get_pose_state() if rig else &"normal"


func set_visible(on: bool) -> void:
	var n := node()
	if n:
		n.visible = on


# --- sockets ----------------------------------------------------------------------------------------

func socket_pos(socket: StringName) -> Vector3:
	var o := body.global_position
	var fwd := -body.global_basis.z
	match socket:
		&"weapon":
			return weapon_tip(&"hand_r")
		&"spear_tip":
			return weapon_tip(&"hand_r")
		&"arrow":
			if bow and is_instance_valid(bow):
				return bow.arrow_tip()
			return socket_pos(&"hand_l")
		&"hands":
			return (socket_pos(&"hand_l") + socket_pos(&"hand_r")) * 0.5
	if creature:
		var s := creature.get_socket(socket)
		if s:
			return s.global_position
		return o + Vector3.UP * height * 0.7 + fwd * 1.5
	if rig:
		var s2 := rig.get_socket(socket)
		if s2:
			return s2.global_position
	return o + Vector3.UP * 1.2 + fwd * 0.3


## World position of the tip of the prop held at `socket` (hand if none).
func weapon_tip(socket: StringName = &"hand_r") -> Vector3:
	if rig:
		var p := rig.get_prop(socket)
		if p != null and is_instance_valid(p):
			var name: StringName = props.get(socket, &"")
			return p.global_transform * Vector3(0, float(PROP_TIPS.get(name, 0.4)), 0)
		var s := rig.get_socket(socket)
		if s:
			return s.global_position
	return body.global_position + Vector3.UP * 1.2


# --- bow --------------------------------------------------------------------------------------------

func _tick_bow() -> void:
	if bow == null or not is_instance_valid(bow) or rig == null:
		return
	var an := rig.animator
	if an and an.action != null and an.action.name == &"enemy_bow_shot":
		var t := an.action_t
		bow.draw = clampf((t - 0.25) / 0.3, 0.0, 1.0) if t < 0.6 else 0.0
		bow.show_arrow = t >= 0.28 and t < 0.6
		var s := rig.get_socket(&"hand_r")
		if s:
			bow.draw_point = s.global_position
	else:
		bow.draw = 0.0
		bow.show_arrow = false


# --- creature death -----------------------------------------------------------------------------------

func _tick_death(delta: float) -> void:
	if _death_t < 0.0 or creature == null:
		return
	_death_t += delta
	# Roll onto the side after the legs give way.
	var u := clampf((_death_t - 0.4) / 0.7, 0.0, 1.0)
	var target := u * u * (3.0 - 2.0 * u) * deg_to_rad(78.0)
	creature.rotation.z = target
	creature.position.y = -sin(target) * 0.25
