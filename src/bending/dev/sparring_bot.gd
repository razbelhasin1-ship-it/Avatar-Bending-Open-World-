class_name SparringBot
extends CharacterBody3D
## Sparring partner that periodically TELEGRAPHS and then throws a fireball
## or swings a melee strike at the player, so block, parry and dodge can be
## practised and tested. Uses the same BendingContext / BendingProjectile /
## BendingHits pieces as the player (team ENEMY), i.e. exactly the path real
## enemies will take.
##
## Telegraph: the fist ignites + a red ring on the ground for `telegraph` s
## (TELEGRAPH_EVENT signal), then the attack releases (ATTACK signal with the
## exact release time, which playtests use to time a parry).

signal telegraphed(kind: StringName, release_in: float)
signal attacked(kind: StringName)

@export var team: int = Combat.Team.ENEMY
@export var max_health := 400.0
@export var display_name := "Sparring Partner"
## &"projectile", &"melee" or &"mixed" (melee when the player is close).
@export var mode: StringName = &"mixed"
@export var interval := 2.6
@export var telegraph := 0.55
@export var active := true
@export var damage := 12.0
@export var preset: StringName = &"fire_soldier"

var health: HealthComponent
var rig: HumanoidRig
var ctx: BendingContext
var target: Node3D = null
var attacks_made := 0
var hits_taken := 0

var _t := 1.5
var _phase := 0  # 0 idle, 1 telegraph, 2 recover
var _kind: StringName = &"projectile"
var _ring: FxRing = null
var _stun := 0.0
var _flame_t := 0.0
var _forced: StringName = &""


func _ready() -> void:
	add_to_group(&"damageable")
	add_to_group(&"sparring_bot")
	collision_layer = Layers.ENEMY
	collision_mask = Layers.SOLID
	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = max_health
	health.max_poise = 60.0
	add_child(health)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0, 0.875, 0)
	add_child(cs)
	rig = HumanoidRig.create({"preset": preset, "seed": 9, "style": &"fire"})
	rig.manual_update = true
	add_child(rig)
	rig.set_combat_stance(true)
	ctx = BendingContext.new(self, rig, ElementDefs.Element.FIRE, team)
	ctx.aim_provider = func() -> Dictionary:
		var t := _target()
		var d := (BendingContext.target_point(t) - (global_position + Vector3.UP * 1.3)).normalized() if t else -global_basis.z
		return {"direction": d, "target": t, "point": BendingContext.target_point(t) if t else global_position - global_basis.z * 10.0}


func get_display_name() -> String:
	return display_name


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.2


func is_alive() -> bool:
	return not health.is_dead()


func get_bending_context() -> BendingContext:
	return ctx


func _target() -> Node3D:
	if target != null and is_instance_valid(target) and target.is_inside_tree():
		return target
	return get_tree().get_first_node_in_group(&"player") as Node3D


func receive_hit(hit: HitInfo) -> int:
	if health.is_dead():
		return Combat.Result.IGNORED
	hits_taken += 1
	health.apply_damage(hit.damage, hit)
	rig.flash_hit()
	if hit.reaction >= HitInfo.Reaction.STAGGER:
		_interrupt()
		_stun = maxf(0.6, hit.stun_time)
		rig.play_reaction(hit.reaction, hit.direction)
		if hit.reaction == HitInfo.Reaction.KNOCKBACK or hit.reaction == HitInfo.Reaction.KNOCKDOWN:
			velocity.x = hit.direction.x * hit.force * 0.5
			velocity.z = hit.direction.z * hit.force * 0.5
		if hit.reaction == HitInfo.Reaction.KNOCKDOWN or hit.reaction == HitInfo.Reaction.LAUNCH:
			_stun = 1.6
	else:
		rig.play_reaction(HitInfo.Reaction.FLINCH, hit.direction)
	if health.is_dead():
		rig.play_reaction(&"death", hit.direction)
		_interrupt()
		get_tree().create_timer(2.5, false).timeout.connect(_revive)
		return Combat.Result.KILLED
	return Combat.Result.HIT


func _revive() -> void:
	if not is_inside_tree():
		return
	health.revive(1.0)
	rig.set_pose_state(&"normal", 0.0)
	rig.stop_action(0.0)
	_t = interval


## Schedules the next telegraph in `seconds` (tests / playtests time defenses
## with it). `kind` forces &"projectile" or &"melee" for that attack.
func attack_in(seconds: float, kind: StringName = &"") -> void:
	_interrupt()
	_t = maxf(0.0, seconds)
	_forced = kind
	active = true


func _interrupt() -> void:
	_phase = 0
	_t = interval
	if _ring and is_instance_valid(_ring):
		FxLib.release(_ring)
	_ring = null


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 14.0 * delta
	else:
		var hv := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, 12.0 * delta)
		velocity.x = hv.x
		velocity.z = hv.y
	move_and_slide()
	rig.set_locomotion(Vector3(velocity.x, 0, velocity.z), is_on_floor())
	rig.advance(delta)
	if health.is_dead():
		return
	if _stun > 0.0:
		_stun -= delta
		if _stun <= 0.0 and rig.get_pose_state() == &"knocked_down":
			RigReactions.get_up(rig)
		return
	var t := _target()
	if t == null or not active:
		return
	var to := t.global_position - global_position
	to.y = 0.0
	if to.length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-delta * 6.0))
	if to.length() > 28.0:
		return
	_t -= delta
	match _phase:
		0:
			if _t <= 0.0:
				_kind = &"melee" if (mode == &"melee" or (mode == &"mixed" and to.length() < 2.6)) else &"projectile"
				if _forced != &"":
					_kind = _forced
					_forced = &""
				_phase = 1
				_t = telegraph
				_start_telegraph()
		1:
			_flame_t -= delta
			if _flame_t <= 0.0:
				_flame_t = 0.06
				FxBurst.spawn(self, &"flame", ctx.socket_pos(&"hand_r"), {"size": 0.35, "count": 0.3, "speed": 0.5})
			if _t <= 0.0:
				_release()
				_phase = 2
				_t = 0.7
		2:
			if _t <= 0.0:
				_phase = 0
				_t = interval


func _start_telegraph() -> void:
	telegraphed.emit(_kind, telegraph)
	_ring = FxRing.spawn(self, global_position, 1.4 if _kind == &"melee" else 0.9, Color(1.0, 0.25, 0.12), telegraph + 0.1,
			{"opacity": 0.85, "width": 0.22, "fill": 0.2})
	# Wind-up pose: fire_charge_hold (fists pulled back) for the whole telegraph.
	rig.play_action(&"fire_charge_hold", {"blend_in": 0.1})
	Audio.play_bending(ElementDefs.Element.FIRE, &"ignite", global_position + Vector3.UP, -6.0)


func _release() -> void:
	attacks_made += 1
	_ring = null
	attacked.emit(_kind)
	var t := _target()
	if _kind == &"melee":
		rig.play_action(&"fire_kick_r", {"start": 0.35, "speed": 1.2})
		var a := global_position + Vector3.UP * 1.0
		var b := a - global_basis.z * 2.3
		BendingHits.sweep(ctx, a, b, 0.6, {"damage": damage, "reaction": HitInfo.Reaction.STAGGER, "force": 5.0, "stun": 0.45, "poise": 20.0},
				HitInfo.new_attack_id(), &"bot_kick")
		var yb := Basis(Vector3.UP, rotation.y)
		FireFx.arc(self, Transform3D(yb, global_position + Vector3.UP * 1.0), 1.0, -1.0, 1.6, 0.14, {"width": 0.5})
		Audio.play_bending(ElementDefs.Element.FIRE, &"cast_light", a, -2.0)
	else:
		rig.play_action(&"fire_charge_release", {"start": 0.3})
		var from := ctx.hands_pos() - global_basis.z * 0.4
		var dir := ctx.aim_dir_from(from, 22.0, 0.3)
		var ball := FireFx.ball(self, 0.3, true)
		BendingProjectile.launch(ctx, from, dir, 22.0, {"damage": damage, "reaction": HitInfo.Reaction.KNOCKBACK, "force": 6.0, "poise": 20.0,
				"heavy": false, "deflectable": true, "status": {"burn": 1.5}}, {"radius": 0.3, "range": 30.0, "visual": ball, "align": false,
				"ability_id": &"bot_fireball"})
		FireFx.muzzle(self, from, dir, 1.0)
		Audio.play_bending(ElementDefs.Element.FIRE, &"cast_heavy", from, -2.0)
	if t == null:
		return
