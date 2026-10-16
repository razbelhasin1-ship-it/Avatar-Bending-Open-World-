class_name EnemyBase
extends CharacterBody3D
## An enemy: a data-driven archetype (EnemyArchetypes) on a CharacterBody3D in groups
## &"damageable" + &"enemy", team ENEMY, physics layer Layers.ENEMY.
##
##   var e := EnemyBase.create(&"fire_soldier", {"home": xform, "seed": 7, "level": 2})
##   add_child(e)        # or EncounterDirector.spawn(...)
##
## Pieces: EnemyVisual (HumanoidRig / CreatureRig + props), EnemyPerception (sight,
## hearing, memory), EnemyBrain (state machine + decisions), EnemyActions (telegraph ->
## strike -> recover), EnemyDamage (receive_hit, reactions, death), a BendingController
## for elemental benders (the player's abilities through a non-player BendingContext),
## and an EnemyHealthBar. Every state has a timeout (no stuck states).

signal state_changed(new_state: int, old_state: int)
signal alerted(enemy: EnemyBase, target: Node3D)
signal damaged(enemy: EnemyBase, hit: HitInfo, result: int)
signal died(enemy: EnemyBase, killer: Node)
## how: &"killed", &"surrendered", &"fled".
signal defeated(enemy: EnemyBase, how: StringName)
signal attack_telegraphed(enemy: EnemyBase, attack: Dictionary, seconds: float)
signal attack_struck(enemy: EnemyBase, attack: Dictionary)
signal attack_finished(enemy: EnemyBase, attack: Dictionary, landed: bool)
## The body may be removed (death fade done, fled out of sight, surrendered and left).
signal despawn_ready(enemy: EnemyBase)

enum State { IDLE, PATROL, ALERT, CHASE, STRAFE, ATTACK, BLOCK, DODGE, RECOVER, STAGGER, KNOCKDOWN, GETUP, DEAD, RETURN, FLEE, SURRENDER }
const STATE_NAMES: Array[String] = ["Idle", "Patrol", "Alert", "Chase", "Strafe", "Attack", "Block", "Dodge", "Recover", "Stagger",
	"Knockdown", "GetUp", "Dead", "Return", "Flee", "Surrender"]
## Hard caps per state (s): the brain normally leaves much earlier.
const STATE_TIMEOUT := {State.ALERT: 12.0, State.ATTACK: 7.0, State.BLOCK: 3.0, State.DODGE: 1.5, State.RECOVER: 3.0,
	State.STAGGER: 3.0, State.KNOCKDOWN: 4.0, State.GETUP: 1.6, State.RETURN: 40.0, State.FLEE: 12.0}
const GRAVITY := 20.0
const ACCEL := 22.0
const TURN_RATE := 540.0

@export var archetype_id: StringName = &"bandit_brawler"
var team: int = Combat.Team.ENEMY
var archetype: Dictionary = {}
var role: StringName = &"brawler"
## Allies answer each other's calls within a faction (sites may mix archetypes).
var faction: StringName = &""
var element: int = ElementDefs.Element.NONE
var display_name := "Enemy"
var level := 1
var health: HealthComponent
var visual: EnemyVisual
var ctx: BendingContext
var controller: BendingController = null
var perception: EnemyPerception
var brain: EnemyBrain
var actions: EnemyActions
var bar: EnemyHealthBar
var rng := RandomNumberGenerator.new()
## Post (leash centre) and facing at rest.
var home := Transform3D.IDENTITY
var leash := 36.0
var patrol: PackedVector3Array = PackedVector3Array()
var site_id: StringName = &""
var state: State = State.IDLE
var state_time := 0.0
## Far from the player: no AI / physics / animation (EncounterDirector).
var dormant := false
## Grant XP + loot to the player on defeat (the director turns it off and pays itself).
var rewards := true
## Movement request from the brain.
var desired_velocity := Vector3.ZERO
var face_dir := Vector3.ZERO
var face_rate := TURN_RATE
## Current attack list (base attacks + unlocked phases).
var attacks: Array = []
var phase_index := 0
## Rolled once: &"" (fights to the end), &"flee" or &"surrender" at low health.
var low_health_mode: StringName = &""
var surrendered := false
var stun_t := 0.0
var down_t := 0.0
var iframes_t := 0.0
## Physical shield guard (defenders).
var guard_hp := 0.0
var guard_broken_t := 0.0
var airborne_reaction := false
var killer: Node = null
var kill_hit: HitInfo = null
## Recent hits (combo breakers): count and the window left.
var recent_hits := 0
var recent_hits_t := 0.0

var _built := false
var _avoid_t := 0.0
var _avoid_dir := Vector3.ZERO
var _death_t := -1.0
var _dodge := {}
var _bark: Label3D = null
var _bark_t := 0.0
var _was_floor := true
var _fall_speed := 0.0


static func create(p_archetype: StringName, opts: Dictionary = {}) -> EnemyBase:
	var e := EnemyBase.new()
	e.archetype_id = p_archetype
	e.configure(opts)
	return e


## Options (before entering the tree): home (Transform3D), seed, level, leash, patrol
## (PackedVector3Array), site_id, rewards, low_health_mode.
func configure(opts: Dictionary) -> void:
	if opts.has("home"):
		home = opts["home"]
		transform = home
	rng.seed = int(opts.get("seed", randi()))
	level = int(opts.get("level", 1))
	leash = float(opts.get("leash", leash))
	if opts.has("patrol"):
		patrol = opts["patrol"]
	site_id = opts.get("site_id", &"")
	faction = opts.get("faction", &"")
	rewards = bool(opts.get("rewards", rewards))
	if opts.has("low_health_mode"):
		set_meta(&"low_health_mode", opts["low_health_mode"])


func _ready() -> void:
	add_to_group(&"damageable")
	add_to_group(&"enemy")
	collision_layer = Layers.ENEMY
	collision_mask = Layers.SOLID | Layers.ENEMY | Layers.PLAYER
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.45
	safe_margin = 0.02
	if home == Transform3D.IDENTITY:
		home = global_transform
	_build()


func _build() -> void:
	_built = true
	archetype = EnemyArchetypes.get_archetype(archetype_id)
	if archetype.is_empty():
		push_warning("EnemyBase: unknown archetype %s" % archetype_id)
		archetype = EnemyArchetypes.get_archetype(&"bandit_brawler")
	role = archetype["role"]
	if faction == &"":
		faction = archetype["faction"]
	element = int(archetype["element"])
	display_name = String(archetype["display_name"])
	attacks = (archetype["attacks"] as Array).duplicate()
	var shape := CollisionShape3D.new()
	shape.name = "Capsule"
	var cap := CapsuleShape3D.new()
	cap.radius = float(archetype["radius"])
	cap.height = maxf(float(archetype["height"]), cap.radius * 2.0 + 0.1)
	shape.shape = cap
	if role == &"beast":
		# Long creatures: a horizontal capsule along the body.
		cap.radius = 0.72
		cap.height = 3.6
		shape.rotation = Vector3(PI * 0.5, 0, 0)
		shape.position = Vector3(0, 0.72, 0.2)
	else:
		shape.position = Vector3(0, cap.height * 0.5, 0)
	add_child(shape)
	health = HealthComponent.new()
	health.name = "HealthComponent"
	var hp := float(archetype["health"]) * health_mult()
	health.max_health = hp
	health.max_poise = float(archetype["poise"])
	health.poise_regen_per_sec = maxf(10.0, float(archetype["poise"]) * 0.35)
	add_child(health)
	health.health = hp
	health.poise = health.max_poise
	visual = EnemyVisual.new()
	visual.build(self, archetype, rng.randi())
	if visual.rig:
		visual.rig.action_event.connect(_on_rig_event)
	if visual.creature:
		visual.creature.action_event.connect(_on_creature_event)
	ctx = BendingContext.new(self, visual.rig, element, team)
	ctx.aim_provider = _aim
	if ElementDefs.is_valid(element):
		controller = BendingController.new()
		controller.name = "BendingController"
		add_child(controller)
		controller.setup(ctx)
		EnemyAbilities.setup_controller(controller, element, archetype)
	perception = EnemyPerception.new()
	perception.setup(self, archetype, visual.height * 0.9)
	actions = EnemyActions.new(self)
	brain = EnemyBrain.new(self)
	guard_hp = float((archetype["block"] as Dictionary).get("guard_hp", 0.0))
	var lh: Dictionary = archetype["flee"]
	if has_meta(&"low_health_mode"):
		low_health_mode = get_meta(&"low_health_mode")
	elif not lh.is_empty():
		var r := rng.randf()
		if r < float(lh.get("surrender", 0.0)):
			low_health_mode = &"surrender"
		elif r < float(lh.get("surrender", 0.0)) + float(lh.get("flee", 0.0)):
			low_health_mode = &"flee"
	bar = EnemyHealthBar.new()
	bar.setup(self, visual.height + 0.32, int(archetype["tier"]) >= 2)
	add_child(bar)
	Events.hit_landed.connect(_on_any_hit)
	brain.start(State.PATROL if patrol.size() >= 2 else State.IDLE)


func _exit_tree() -> void:
	AttackTokens.release_all(self)
	if actions:
		actions.cancel(&"despawn")


# --- damageable contract -------------------------------------------------------------------------------

func receive_hit(hit: HitInfo) -> int:
	return EnemyDamage.receive(self, hit)


func is_alive() -> bool:
	return _built and health != null and not health.is_dead() and state != State.DEAD


func get_display_name() -> String:
	return display_name


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * (visual.height * 0.62 if visual else 1.1)


func get_health_component() -> HealthComponent:
	return health


func get_bending_context() -> BendingContext:
	return ctx


func get_state() -> int:
	return state


func get_state_name() -> String:
	return STATE_NAMES[state]


## Engaged with the player (music, HUD, director budgets).
func in_combat() -> bool:
	return state in [State.CHASE, State.STRAFE, State.ATTACK, State.BLOCK, State.DODGE, State.RECOVER, State.STAGGER,
			State.KNOCKDOWN, State.GETUP] or (state == State.ALERT and perception.engaged)


func is_elite() -> bool:
	return int(archetype.get("tier", 1)) >= 2


# --- difficulty / tuning --------------------------------------------------------------------------------

static func difficulty() -> String:
	return String(Settings.get_value("gameplay", "difficulty", "normal"))


func health_mult() -> float:
	var d := {"story": 0.75, "hard": 1.25}
	return float(d.get(difficulty(), 1.0)) * (1.0 + 0.08 * (level - 1))


## Telegraph length multiplier (difficulty x captain phase).
func telegraph_mult() -> float:
	var d := {"story": 1.3, "hard": 0.85}
	var m := float(d.get(difficulty(), 1.0))
	if phase_index > 0:
		m *= float((archetype["phases"][phase_index - 1] as Dictionary).get("telegraph", 1.0))
	return m


func cooldown_mult() -> float:
	var d := {"story": 1.35, "hard": 0.8}
	var m := float(d.get(difficulty(), 1.0))
	if phase_index > 0:
		m *= float((archetype["phases"][phase_index - 1] as Dictionary).get("cooldown", 1.0))
	return m


func recover_mult() -> float:
	return 1.15 if difficulty() == "story" else 1.0


func damage_mult() -> float:
	return 1.0 + 0.06 * (level - 1)


func speed_mult() -> float:
	var m := 1.0
	if phase_index > 0:
		m *= float((archetype["phases"][phase_index - 1] as Dictionary).get("speed", 1.0))
	return m


## How much projectiles lead a moving target (0..1).
func lead_amount() -> float:
	return {"story": 0.2, "hard": 0.75}.get(difficulty(), 0.5)


func attack_element(a: Dictionary) -> int:
	return int(a.get("element", element))


## Physical shield raised (defenders): frontal hits and projectiles are blocked.
func shield_up() -> bool:
	var b: Dictionary = archetype.get("block", {})
	if b.is_empty() or bool(b.get("bending", false)) or float(b.get("guard_hp", 0.0)) <= 0.0:
		return false
	if guard_hp <= 0.0 or guard_broken_t > 0.0 or actions.is_busy():
		return false
	return state in [State.CHASE, State.STRAFE, State.BLOCK, State.ALERT, State.IDLE, State.PATROL]


## Poise armor of whatever the enemy is doing (attack hyper armor, bending action armor).
func current_armor() -> float:
	var a := 0.0
	if actions.is_busy() and not actions.in_recover():
		a = actions.armor
	if controller and controller.is_busy():
		a = maxf(a, ctx.poise_armor)
	return a


# --- main loop ------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _built or dormant or delta <= 0.0:
		return
	state_time += delta
	recent_hits_t -= delta
	if recent_hits_t <= 0.0:
		recent_hits = 0
	iframes_t = maxf(0.0, iframes_t - delta)
	guard_broken_t = maxf(0.0, guard_broken_t - delta)
	if guard_broken_t <= 0.0 and guard_hp <= 0.0 and float((archetype["block"] as Dictionary).get("guard_hp", 0.0)) > 0.0:
		guard_hp = float(archetype["block"]["guard_hp"])
	actions.tick_cooldowns(delta)
	if state != State.DEAD:
		perception.tick(delta)
		brain.tick(delta)
		actions.tick(delta)
		if controller:
			ctx.move_input = desired_velocity.normalized() if desired_velocity.length() > 0.1 else Vector3.ZERO
			controller.tick(delta)
		_check_state_timeout()
	_integrate(delta)
	move_and_slide()
	_post_move(delta)
	_guard_pose()
	visual.tick(delta, is_on_floor())
	_tick_bark(delta)
	if state == State.DEAD:
		_tick_death(delta)


func _integrate(delta: float) -> void:
	var on_floor := is_on_floor()
	var grav_scale := 1.0
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var target_v := Vector3.ZERO
	var accel := ACCEL
	var face := face_dir
	var rate := face_rate
	match state:
		State.STAGGER, State.KNOCKDOWN, State.GETUP, State.DEAD, State.SURRENDER:
			accel = 9.0 if not on_floor else 12.0
			face = Vector3.ZERO
		State.DODGE:
			if not _dodge.is_empty():
				target_v = _dodge_velocity()
				accel = 200.0
				face = Vector3.ZERO
			elif controller and controller.is_busy():
				target_v = _ctx_velocity(hv)
				accel = 200.0
				grav_scale = ctx.gravity_scale
		_:
			if controller and controller.is_busy():
				target_v = _ctx_velocity(hv)
				accel = 200.0 if ctx.move_mode == BendingContext.Move.DRIVE else maxf(ctx.brake_rate, 20.0)
				grav_scale = ctx.gravity_scale
				if ctx.face_dir != Vector3.ZERO:
					face = ctx.face_dir
					rate = ctx.face_rate
			elif actions.is_busy():
				target_v = actions.drive
				accel = 60.0 if actions.drive != Vector3.ZERO else 30.0
				if actions.face_locked:
					face = Vector3.ZERO
			else:
				target_v = desired_velocity
	if not on_floor:
		accel *= 0.25
	hv = hv.move_toward(target_v, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if not on_floor:
		velocity.y -= GRAVITY * grav_scale * delta
		_fall_speed = minf(_fall_speed, velocity.y)
	elif velocity.y < 0.0:
		velocity.y = -0.5
	# Facing.
	if face == Vector3.ZERO and state in [State.CHASE, State.PATROL, State.RETURN, State.FLEE, State.ALERT] and hv.length() > 0.5:
		face = hv
	if face != Vector3.ZERO:
		_turn_toward(face, rate, delta)


func _ctx_velocity(_hv: Vector3) -> Vector3:
	match ctx.move_mode:
		BendingContext.Move.DRIVE:
			return Vector3(ctx.move_velocity.x, 0.0, ctx.move_velocity.z)
		BendingContext.Move.FREE:
			return desired_velocity * clampf(ctx.move_speed_scale * 2.0, 0.0, 1.0)
		BendingContext.Move.HOLD:
			return Vector3.ZERO
		BendingContext.Move.ROOT:
			var rm := visual.rig.consume_root_motion() if visual.rig else Vector3.ZERO
			return Vector3(rm.x, 0.0, rm.z) / maxf(get_physics_process_delta_time(), 0.001)
	return Vector3.ZERO


func _turn_toward(dir: Vector3, rate_deg: float, delta: float) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 1e-4:
		return
	var want := atan2(-d.x, -d.z)
	var diff := wrapf(want - rotation.y, -PI, PI)
	var step := deg_to_rad(rate_deg) * delta
	rotation.y += clampf(diff, -step, step)


func _post_move(_delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_floor:
		var impact := -_fall_speed
		_fall_speed = 0.0
		if airborne_reaction:
			airborne_reaction = false
			visual.land(impact)
			EnemyDamage.on_landed_knockdown(self)
		elif impact > 6.0:
			visual.land(impact)
	_was_floor = on_floor
	# Never fall out of the world.
	if global_position.y < WorldData.get_height(global_position.x, global_position.z) - 6.0 or not global_position.is_finite():
		var g := WorldData.get_safe_ground(home.origin)
		global_position = g if g.is_finite() else home.origin
		velocity = Vector3.ZERO


## Defenders keep the shield raised (upper-body loop) whenever the guard is up in combat.
func _guard_pose() -> void:
	if visual.rig == null or float((archetype.get("block", {}) as Dictionary).get("guard_hp", 0.0)) <= 0.0:
		return
	var want := shield_up() and (in_combat() or state == State.ALERT)
	var cur := visual.current_action()
	if want and cur == &"":
		visual.play(&"enemy_shield_guard", {"blend_in": 0.15})
	elif not want and cur == &"enemy_shield_guard":
		visual.stop(0.15)


func _check_state_timeout() -> void:
	var cap: float = STATE_TIMEOUT.get(state, INF)
	if state_time > cap:
		push_warning("EnemyBase %s: state %s timed out" % [display_name, get_state_name()])
		brain.on_state_timeout(state)


func set_state(s: State) -> void:
	if s == state:
		return
	var old := state
	state = s
	state_time = 0.0
	if old == State.DODGE:
		_dodge = {}
	state_changed.emit(s, old)


# --- movement helpers (used by the brain) -----------------------------------------------------------------

func forward() -> Vector3:
	var f := -global_basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 1e-6 else Vector3.FORWARD


func flat_dir_to(n: Node3D) -> Vector3:
	if n == null or not is_instance_valid(n):
		return forward()
	var d := n.global_position - global_position
	d.y = 0.0
	return d.normalized() if d.length_squared() > 1e-4 else forward()


func flat_distance_to(n: Node3D) -> float:
	if n == null or not is_instance_valid(n):
		return INF
	var d := n.global_position - global_position
	d.y = 0.0
	return d.length()


func flat_distance(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func ground_point(p: Vector3) -> Vector3:
	return ctx.ground_point(p) if is_inside_tree() else Vector3(p.x, WorldData.get_height(p.x, p.z), p.z)


func near_player(dist: float) -> bool:
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	return p != null and p.global_position.distance_to(global_position) <= dist


## Steers toward a world point at `speed` (avoidance + separation + ledge/water checks).
func steer_to(point: Vector3, speed: float) -> void:
	var d := point - global_position
	d.y = 0.0
	if d.length() < 0.25:
		desired_velocity = Vector3.ZERO
		return
	steer_dir(d.normalized(), speed * clampf(d.length() / 0.8, 0.3, 1.0))


func steer_dir(dir: Vector3, speed: float) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 1e-6 or speed <= 0.0:
		desired_velocity = Vector3.ZERO
		return
	d = d.normalized()
	d = _separate(d)
	d = _avoid(d)
	desired_velocity = d * speed * speed_mult()


func stop_moving() -> void:
	desired_velocity = Vector3.ZERO


## Pushes the direction away from allies closer than 1.4 m.
func _separate(d: Vector3) -> Vector3:
	var push := Vector3.ZERO
	for n in get_tree().get_nodes_in_group(&"enemy"):
		if n == self or not (n is Node3D):
			continue
		var o := global_position - (n as Node3D).global_position
		o.y = 0.0
		var l := o.length()
		if l > 0.01 and l < 1.6:
			push += o / l * (1.6 - l)
	if push == Vector3.ZERO:
		return d
	return (d + push * 0.9).normalized()


## Whisker avoidance against walls / constructs / drops / deep water (cached 0.2 s).
func _avoid(d: Vector3) -> Vector3:
	_avoid_t -= get_physics_process_delta_time()
	if _avoid_t > 0.0 and _avoid_dir != Vector3.ZERO and _avoid_dir.dot(d) > 0.3:
		return _avoid_dir
	_avoid_t = 0.2
	_avoid_dir = Vector3.ZERO
	if _clear(d):
		return d
	for ang: float in [0.6, -0.6, 1.1, -1.1, 1.6, -1.6]:
		var r := d.rotated(Vector3.UP, ang)
		if _clear(r):
			_avoid_dir = r
			return r
	return Vector3.ZERO


func _clear(d: Vector3) -> bool:
	var from := global_position + Vector3.UP * 0.6
	var to := from + d * 1.4
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.SOLID)
	q.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return false
	var ahead := global_position + d * 1.6
	var gy := WorldData.get_height(ahead.x, ahead.z)
	if not WorldData.has_world_data():
		return true
	if gy < global_position.y - 2.5:
		return false
	var wh := WorldData.get_water_height(ahead.x, ahead.z)
	return not (is_finite(wh) and wh - gy > 0.9)


# --- dodge (physical) -------------------------------------------------------------------------------------

## Evasive sidestep / backstep with i-frames (non-benders; benders use their dodge ability).
func begin_dodge(dir: Vector3) -> bool:
	var d: Dictionary = archetype["dodge"]
	if d.is_empty() or not is_on_floor():
		return false
	if bool(d.get("bending", false)) and controller:
		ctx.move_input = dir.normalized()
		if controller.request(&"dodge") != &"":
			return false
		set_state(State.DODGE)
		return true
	var dur := float(d.get("duration", 0.32))
	var dist := float(d.get("distance", 3.2))
	_dodge = {"dir": Vector3(dir.x, 0, dir.z).normalized(), "dur": dur, "dist": dist, "t": 0.0}
	iframes_t = float(d.get("iframes", 0.24))
	var lr := (_dodge["dir"] as Vector3).dot(global_basis.x)
	var fb := (_dodge["dir"] as Vector3).dot(forward())
	var clip: StringName = &"dodge_back" if fb < -0.5 else (&"dodge_side_r" if lr > 0.0 else &"dodge_side_l")
	var c := AnimLibrary.get_clip(clip)
	visual.play(clip, {"speed": (c.length / (dur + 0.15)) if c else 1.0, "blend_in": 0.03})
	Audio.play_sfx(&"dodge_whoosh", global_position + Vector3.UP, -4.0)
	set_state(State.DODGE)
	return true


func _dodge_velocity() -> Vector3:
	var t := float(_dodge["t"]) + get_physics_process_delta_time()
	_dodge["t"] = t
	var dur := float(_dodge["dur"])
	var u := clampf(t / dur, 0.0, 1.0)
	return (_dodge["dir"] as Vector3) * float(_dodge["dist"]) * 1.5 / dur * (1.0 - u * u)


func dodge_done() -> bool:
	if not _dodge.is_empty():
		return float(_dodge["t"]) >= float(_dodge["dur"]) + 0.12
	return controller == null or not controller.is_busy()


# --- runner hooks ------------------------------------------------------------------------------------------

func on_attack_started(_a: Dictionary, _windup_s: float) -> void:
	visual.combat = true


func on_telegraph(a: Dictionary, seconds: float) -> void:
	attack_telegraphed.emit(self, a, seconds)


func on_attack_struck(a: Dictionary) -> void:
	attack_struck.emit(self, a)


func on_attack_finished(a: Dictionary, landed: bool) -> void:
	attack_finished.emit(self, a, landed)
	brain.on_attack_finished(a, landed)


func _on_rig_event(clip: StringName, event: StringName) -> void:
	if actions:
		actions.on_rig_event(clip, event)


func _on_creature_event(action: StringName, event: StringName) -> void:
	if actions:
		actions.on_creature_event(action, event)


## Combat noise: hits landing near an unaware enemy draw it in.
func _on_any_hit(hit: HitInfo, target: Node, _result: int) -> void:
	if dormant or state == State.DEAD or perception == null or perception.engaged:
		return
	var pos := hit.position if hit.position != Vector3.ZERO else (target as Node3D).global_position if target is Node3D else Vector3.INF
	if perception.hear(pos, 1.0):
		brain.on_noise(pos, hit.source as Node3D if hit.source is Node3D else null)


func _aim() -> Dictionary:
	var t := perception.target if perception else null
	if t == null or not is_instance_valid(t):
		return {"direction": forward(), "target": null, "point": global_position + forward() * 10.0}
	var tp := BendingContext.target_point(t)
	var from := global_position + Vector3.UP * 1.3
	return {"direction": (tp - from).normalized(), "target": t, "point": tp}


# --- barks -------------------------------------------------------------------------------------------------

## A short floating line above the head ("Intruder!", "I yield!").
func bark(text: String, seconds: float = 1.8) -> void:
	if text.is_empty() or not bool(Settings.get_value("gameplay", "subtitles", true)):
		return
	if _bark == null:
		_bark = Label3D.new()
		_bark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bark.font_size = 44
		_bark.pixel_size = 0.004
		_bark.outline_size = 10
		_bark.modulate = Color(1, 0.96, 0.86)
		_bark.outline_modulate = Color(0.08, 0.05, 0.04)
		_bark.no_depth_test = true
		_bark.position = Vector3(0, visual.height + 0.95, 0)
		add_child(_bark)
	_bark.text = text
	_bark.visible = true
	_bark.modulate.a = 1.0
	_bark_t = seconds


func _tick_bark(delta: float) -> void:
	if _bark == null or _bark_t <= 0.0:
		return
	_bark_t -= delta
	_bark.modulate.a = clampf(_bark_t / 0.4, 0.0, 1.0)
	if _bark_t <= 0.0:
		_bark.visible = false


func show_alert_mark() -> void:
	var m := EnemyTelegraph.AlertMark.new()
	m.position = Vector3(0, visual.height + 0.55, 0)
	add_child(m)


# --- death / despawn ----------------------------------------------------------------------------------------

func begin_death_fade() -> void:
	_death_t = 0.0


func _tick_death(delta: float) -> void:
	if _death_t < 0.0:
		return
	_death_t += delta
	if _death_t > 5.0:
		var n := visual.node()
		if n:
			n.position.y -= delta * 0.6
	if _death_t > 6.6 and _death_t - delta <= 6.6:
		visual.set_visible(false)
		despawn_ready.emit(self)


## Instantly leaves the world (fled / surrendered and gone / director despawn).
func vanish() -> void:
	AttackTokens.release_all(self)
	actions.cancel(&"despawn")
	visual.set_visible(false)
	collision_layer = 0
	despawn_ready.emit(self)


## Far, dormant patrol members keep walking their route kinematically (no physics).
func advance_dormant_patrol(dt: float) -> void:
	if not dormant or patrol.size() < 2 or dt <= 0.0:
		return
	var i := brain.get_patrol_index() % patrol.size()
	var goal := patrol[i]
	var d := goal - global_position
	d.y = 0.0
	var step := float(archetype["speed"]["walk"]) * dt
	if d.length() <= step:
		global_position = Vector3(goal.x, WorldData.get_height(goal.x, goal.z), goal.z)
		brain.set_patrol_index(i + 1)
		return
	var p := global_position + d.normalized() * step
	p.y = WorldData.get_height(p.x, p.z)
	global_position = p
	rotation.y = atan2(-d.x, -d.z)


## Full reset at the post (director respawns from a pool).
func reset_to_home() -> void:
	actions.cancel(&"reset")
	if controller and controller.is_busy():
		controller.cancel_current(&"reset")
	health.revive(1.0)
	global_transform = home
	velocity = Vector3.ZERO
	perception.forget()
	brain.start(State.PATROL if patrol.size() >= 2 else State.IDLE)
