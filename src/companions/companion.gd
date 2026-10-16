class_name Companion
extends CharacterBody3D
## The element companion (sky bison, dragon, polar bear dog, badgermole): a living partner
## and mount built on a CreatureRig (docs/modules/companions.md).
##
##   var c := Companion.create(&"sky_bison")
##   c.player = player
##   scene.spawn_companion(c, Companion.spawn_transform(player, &"sky_bison"))
##
## Components (RefCounted helpers, all driven from this node's physics tick, which runs
## before the player's so the rider seat is placed after the mount moved):
##   motor (CompanionMotor)   ground locomotion, whiskers, slopes, water, stuck detection
##   flight (CompanionFlight) takeoff / flight / landing (flyers)
##   brain (CompanionBrain)   follow formation, escort flight, idles + reactions, call,
##                            retreat, never-lost teleports
##   rider (CompanionRider)   mount / dismount transitions, saddle seat, rider tilt, prompt
##   ride (CompanionRide)     mounted controls (ground riding, flight, burrow trigger)
##   burrow (CompanionBurrow) badgermole tunnelling (dig in, travel, emerge)
##   assist (CompanionAssist) combat assist moves with real HitInfo
## Contracts: damageable (team PLAYER, never dies), HUD (`health`, get_status_text()),
## persistence (group &"persist" -> GameState.companion).

signal mode_changed(new_mode: int, old_mode: int)
## The player called the companion (companion_call).
signal called
## Rider seated (player) / rider left (null).
signal rider_changed(rider: Node3D)

enum Mode { FOLLOW, ESCORT, CALLED, RETREAT, ASSIST, WAIT, MOUNTING, RIDDEN, DISMOUNTING, BURROW }

const MODE_NAMES: Array[String] = ["follow", "escort", "called", "retreat", "assist", "wait", "mounting", "ridden", "dismounting", "burrow"]
## Hard caps per mode (s): a mode that runs longer is ended (no stuck states).
const MODE_TIMEOUT := {Mode.CALLED: 30.0, Mode.RETREAT: 45.0, Mode.ASSIST: 9.0, Mode.MOUNTING: 3.0,
		Mode.DISMOUNTING: 3.0, Mode.BURROW: 22.0}
## Out-of-combat regeneration (fraction of max health per second) after REGEN_DELAY.
const REGEN := 0.012
const REGEN_DELAY := 8.0
## A teleport happens when the companion is this far from the player (ground / flyer).
const LOST_GROUND := 110.0
const LOST_AIR := 650.0

@export var species: StringName = &"sky_bison"
## Rig look overrides (seed, colors, scale) passed to CreatureRig.create.
@export var rig_config: Dictionary = {}

var team: int = Combat.Team.PLAYER
var prof: CompanionProfile
var rig: CreatureRig
var health: HealthComponent
var motor: CompanionMotor
var flight: CompanionFlight = null
var brain: CompanionBrain
var rider: CompanionRider
var ride: CompanionRide
var burrow: CompanionBurrow = null
var assist: CompanionAssist
var player: PlayerCharacter = null
## Optional WorldRenderer (collision requests while far from the player, teleports).
var renderer: Node = null
var mode: int = Mode.FOLLOW
var mode_time := 0.0
var display_name := "Companion"
## Disable for scripted scenes: no autonomous behaviour (mount still works).
var autonomous := true
## Combat assist on/off (GameState.companion["assist"]).
var assist_enabled := true

var _built := false
var _since_damage := 99.0
var _safety_t := 0.0
var _collision_req := -1
var _status_override := ""
var _status_override_t := 0.0


## Builds a companion of `id` (CompanionProfile.SPECIES). cfg: rig (Dictionary of rig
## config overrides), autonomous (bool).
static func create(id: StringName, cfg: Dictionary = {}) -> Companion:
	var c := Companion.new()
	c.species = id
	c.name = "Companion_%s" % String(id).to_pascal_case()
	c.rig_config = cfg.get("rig", {})
	c.autonomous = bool(cfg.get("autonomous", true))
	return c


## A spawn transform beside the player on safe ground (formation slot side).
static func spawn_transform(p: Node3D, id: StringName) -> Transform3D:
	var prof_s := CompanionProfile.for_species(id)
	var fwd := -p.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-4 else Vector3.FORWARD
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var space := p.get_world_3d().direct_space_state if p.is_inside_tree() else null
	var want := p.global_position - right * prof_s.f(prof_s.follow, "side") * 0.8 - fwd * prof_s.f(prof_s.follow, "back") * 0.5
	var spot := Vector3.INF
	if CompanionNav.walkable(want.x, want.z, prof_s.f(prof_s.follow, "max_slope"), 0.2):
		var gy := CompanionNav.ground_y(space, Vector3(want.x, maxf(p.global_position.y, WorldData.get_height(want.x, want.z)) + 2.0, want.z), 4.0, 20.0)
		var g := Vector3(want.x, gy, want.z)
		if CompanionNav.open_space(space, g, prof_s.radius() * 0.9):
			spot = g
	if spot == Vector3.INF:
		spot = CompanionNav.find_spot_near(space, p.global_position, prof_s.radius(), prof_s.f(prof_s.follow, "max_slope"), 5.0, 16.0)
	if spot == Vector3.INF:
		spot = p.global_position + right * 3.0
	return Transform3D(Basis(Vector3.UP, CompanionNav.yaw_of(fwd)), spot)


func _ready() -> void:
	add_to_group(&"companion")
	add_to_group(&"damageable")
	add_to_group(&"persist")
	process_physics_priority = -10
	_build()


func _build() -> void:
	prof = CompanionProfile.for_species(species)
	display_name = String(GameState.companion.get("name", "")) if String(GameState.companion.get("type", "")) == String(species) else ""
	if display_name.is_empty():
		display_name = prof.display_name
	collision_layer = Layers.COMPANION
	collision_mask = Layers.SOLID
	var shape := CollisionShape3D.new()
	shape.name = "Body"
	var cap := CapsuleShape3D.new()
	cap.radius = prof.radius()
	cap.height = maxf(prof.body_height(), prof.radius() * 2.0 + 0.2)
	shape.shape = cap
	shape.position = Vector3(0.0, cap.height * 0.5, 0.0)
	add_child(shape)
	var cfg := {"seed": 17, "idle": true}
	cfg.merge(rig_config, true)
	rig = CreatureRig.create(species, cfg)
	add_child(rig)
	rig.footstep_actor = self
	var ex: Array[RID] = [get_rid()]
	rig.set_probe_exclude(ex)
	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = prof.max_health
	health.poise_regen_per_sec = 30.0
	add_child(health)
	health.health = prof.max_health * clampf(float(GameState.companion.get("health_ratio", 1.0)), 0.3, 1.0)
	motor = CompanionMotor.new(self, prof)
	motor.configure_body()
	motor.yaw = rotation.y
	if prof.can_fly:
		flight = CompanionFlight.new(self, rig, prof)
	if prof.can_burrow:
		burrow = CompanionBurrow.new(self)
	brain = CompanionBrain.new(self)
	rider = CompanionRider.new(self)
	ride = CompanionRide.new(self)
	assist = CompanionAssist.new(self)
	assist_enabled = bool(GameState.companion.get("assist", true))
	Events.dismounted.connect(_on_player_dismounted)
	brain.connect_events()
	_built = true


func _enter_tree() -> void:
	if _built:
		motor.yaw = rotation.y
		brain.connect_events()


func _exit_tree() -> void:
	if not _built:
		return
	brain.disconnect_events()
	rider.release_rider()
	_release_collision_request()
	if burrow:
		burrow.cleanup()
	assist.cleanup()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _built:
		if Events.dismounted.is_connected(_on_player_dismounted):
			Events.dismounted.disconnect(_on_player_dismounted)


# --- main loop ------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _built or delta <= 0.0:
		return
	_ensure_player()
	if not global_position.is_finite():
		_safety_t = 0.0
		_safety(0.0)
	mode_time += delta
	_tick_health(delta)
	assist.cool(delta)
	if MODE_TIMEOUT.has(mode) and mode_time > float(MODE_TIMEOUT[mode]):
		_on_mode_timeout()
	if not is_ridden() and mode != Mode.BURROW:
		brain.commands()
	match mode:
		Mode.MOUNTING, Mode.DISMOUNTING:
			rider.tick_transition(delta)
		Mode.RIDDEN:
			ride.tick(delta)
		Mode.BURROW:
			burrow.tick(delta)
		Mode.ASSIST:
			assist.tick(delta)
		_:
			brain.tick(delta)
	rider.update_seat(delta)
	_feed_rig(delta)
	_safety(delta)


func _ensure_player() -> void:
	if player != null and is_instance_valid(player):
		return
	player = get_tree().get_first_node_in_group(&"player") as PlayerCharacter if is_inside_tree() else null


func set_mode(m: int) -> void:
	if m == mode:
		return
	var old := mode
	mode = m
	mode_time = 0.0
	if old == Mode.ASSIST:
		assist.cancel()
	mode_changed.emit(m, old)


func get_mode_name() -> String:
	return MODE_NAMES[mode]


func is_ridden() -> bool:
	return mode == Mode.RIDDEN or mode == Mode.MOUNTING or mode == Mode.DISMOUNTING or (mode == Mode.BURROW and burrow != null and burrow.ridden)


func is_flying() -> bool:
	return flight != null and flight.is_active()


func is_airborne() -> bool:
	return flight != null and flight.is_airborne()


func _on_mode_timeout() -> void:
	match mode:
		Mode.MOUNTING:
			rider.finish_mount()
		Mode.DISMOUNTING:
			rider.finish_dismount()
		Mode.BURROW:
			burrow.force_emerge()
		Mode.ASSIST:
			assist.cancel()
			set_mode(Mode.FOLLOW)
		Mode.CALLED:
			teleport_near_player()
			set_mode(Mode.FOLLOW)
		_:
			set_mode(Mode.ESCORT if is_airborne() else Mode.FOLLOW)


func _feed_rig(delta: float) -> void:
	if rig == null:
		return
	var v := velocity
	var airborne := is_airborne()
	var grounded := motor.on_floor or motor.swimming or (mode == Mode.BURROW)
	if flight != null and flight.is_active():
		grounded = not airborne
	rig.set_locomotion(v, grounded, delta)
	if flight != null and flight.is_active():
		rig.set_flight(flight.phase != CompanionFlight.Phase.LANDING, v, flight.bank, flight.pitch)
	rig.set_swimming(motor.swimming and not airborne, motor.water_y if is_finite(motor.water_y) else 0.0)
	rig.idle_enabled = autonomous and not is_ridden() and not airborne and mode in [Mode.FOLLOW, Mode.WAIT, Mode.RETREAT]


# --- player commands --------------------------------------------------------------------------------

## companion_call: come to the player (run, fly in or appear nearby when far / stuck).
func call_companion() -> void:
	if is_ridden():
		return
	called.emit()
	brain.on_called()


## True when `p` can climb on now (in range, both free).
func can_mount(p: Node3D) -> bool:
	return rider.can_mount(p)


## Starts the mount transition for `p` (also used by the mount Interactable).
func request_mount(p: Node3D) -> bool:
	return rider.begin_mount(p)


## Called by PlayerCharacter.update_mounted when the rider presses mount: dismounts with
## an animated hop on the ground or lets go in the air (the player falls / glides).
func request_dismount() -> void:
	if mode == Mode.RIDDEN:
		if is_airborne():
			rider.release_in_air()
		else:
			rider.begin_dismount()
	elif mode == Mode.MOUNTING:
		rider.finish_mount()


## External dismounts (travel, respawn rescue, player code): clean up and go on alone.
func _on_player_dismounted(m: Node3D) -> void:
	if m != self or not _built:
		return
	if rider.phase != CompanionRider.Phase.NONE and not rider.is_releasing():
		rider.release_rider()
		if burrow and burrow.is_active():
			burrow.ridden = false
		elif is_airborne():
			set_mode(Mode.ESCORT)
		else:
			set_mode(Mode.FOLLOW)


## Teleports to a safe spot near the player (off-screen when possible). Flyers far away
## with `air` = true appear in the sky behind the camera and fly in.
func teleport_near_player(air: bool = false) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var pp := player.global_position
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var view := -cam.global_basis.z if cam else -player.global_basis.z
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = [get_rid(), player.get_rid()]
	if air and prof.can_fly:
		var back := CompanionNav.flat_dir(-view)
		if back == Vector3.ZERO:
			back = Vector3.BACK
		back = back.rotated(Vector3.UP, randf_range(-0.6, 0.6))
		var pos := pp + back * 95.0
		pos.y = maxf(CompanionNav.surface_y(pos.x, pos.z) + flight.f("clearance") * 2.5, pp.y + flight.f("escort_height") + 8.0)
		if burrow and burrow.is_active():
			burrow.cleanup()
		motor.teleport(pos, CompanionNav.yaw_of(CompanionNav.flat_dir(pp - pos)))
		flight.start_airborne(motor.yaw, flight.f("cruise"))
		rig.reset_feet()
		return true
	var spot := CompanionNav.find_spot_near(space, pp, prof.radius(), prof.f(prof.follow, "max_slope"), 9.0, 22.0, view, ex)
	if spot == Vector3.INF:
		spot = WorldData.get_safe_ground(pp + CompanionNav.flat_dir(-view) * 8.0)
	if renderer != null and is_instance_valid(renderer) and renderer.has_method("ensure_collision_now"):
		renderer.call("ensure_collision_now", spot)
	if flight != null and flight.is_active():
		flight.cancel()
	if burrow and burrow.is_active():
		burrow.cleanup()
	motor.teleport(spot + Vector3.UP * 0.05, CompanionNav.yaw_of(CompanionNav.flat_dir(pp - spot)))
	rig.reset_feet()
	return true


# --- damage / health --------------------------------------------------------------------------------

## Damageable contract. Companions are never killed: health stops at 1 and the companion
## retreats to recover. Ridden or burrowed companions ignore hits (like their rider).
func receive_hit(hit: HitInfo) -> int:
	if is_ridden() or (burrow != null and burrow.is_active()):
		return Combat.Result.IGNORED
	var dmg := hit.damage * (1.0 - prof.armor) * Settings.difficulty_damage_scale()
	dmg = minf(dmg, maxf(health.health - 1.0, 0.0))
	hit.damage = dmg
	health.apply_damage(dmg, hit)
	_since_damage = 0.0
	rig.flash_hit(1.0)
	if hit.status.has("burn"):
		rig.set_status(Color(1.0, 0.45, 0.15), 0.5)
	# A shove for heavy hits (the body stays put otherwise; creatures are heavy).
	if hit.force > 6.0 and not is_airborne():
		motor.speed = -minf(hit.force * 0.25, 3.0)
	brain.on_damaged(hit)
	return Combat.Result.HIT


func is_alive() -> bool:
	return true


func get_health_component() -> HealthComponent:
	return health


func _tick_health(delta: float) -> void:
	_since_damage += delta
	var in_fight := player != null and is_instance_valid(player) and player.resources != null and player.resources.in_combat()
	var rate := 0.0
	if mode == Mode.RETREAT and _since_damage > 2.0:
		rate = 0.05
	elif _since_damage > REGEN_DELAY and not in_fight:
		rate = REGEN
	if rate > 0.0 and health.health < health.max_health:
		health.heal(health.max_health * rate * delta)
	if _status_override_t > 0.0:
		_status_override_t -= delta


func since_damage() -> float:
	return _since_damage


# --- HUD / lock-on / persistence --------------------------------------------------------------------

func get_display_name() -> String:
	return display_name


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * prof.body_height() * 0.6


## Status line for the HUD companion panel.
func get_status_text() -> String:
	if _status_override_t > 0.0 and not _status_override.is_empty():
		return _status_override
	match mode:
		Mode.FOLLOW:
			if motor.swimming:
				return "Swimming"
			return "Following" if motor.speed > 0.6 else ("Resting" if rig.is_action_playing(&"lie_down") or rig.is_action_playing(&"sit") else "Waiting")
		Mode.ESCORT:
			return "Flying overhead" if flight == null or flight.phase != CompanionFlight.Phase.LANDING else "Landing"
		Mode.CALLED:
			return "Coming"
		Mode.RETREAT:
			return "Hurt · recovering"
		Mode.ASSIST:
			return "Fighting"
		Mode.WAIT:
			return "Staying"
		Mode.MOUNTING:
			return "Mounting"
		Mode.DISMOUNTING:
			return "Dismounting"
		Mode.RIDDEN:
			if flight != null and flight.is_active():
				return "Flying" if flight.phase == CompanionFlight.Phase.FLY else ("Taking off" if flight.phase == CompanionFlight.Phase.TAKEOFF else "Landing")
			return "Ridden"
		Mode.BURROW:
			return "Burrowing"
	return "Following"


## Briefly overrides the HUD status line ("Can't land here", "Too steep to burrow").
func flash_status(text: String, seconds: float = 2.0) -> void:
	_status_override = text
	_status_override_t = seconds


func write_save_state() -> void:
	GameState.companion["type"] = String(species)
	if String(GameState.companion.get("name", "")).is_empty():
		GameState.companion["name"] = prof.display_name
	GameState.companion["health_ratio"] = clampf(health.ratio(), 0.05, 1.0) if health else 1.0
	GameState.companion["assist"] = assist_enabled


# --- safety -----------------------------------------------------------------------------------------

## Never lost: invalid positions, falling out of the world or straying too far bring the
## companion back next to the player. Keeps terrain collision around it while far away.
func _safety(delta: float) -> void:
	_safety_t -= delta
	if _safety_t > 0.0:
		return
	_safety_t = 0.25
	if not global_position.is_finite():
		if not teleport_near_player():
			global_position = WorldData.get_safe_ground(Vector3.ZERO)
		return
	if player == null or not is_instance_valid(player) or is_ridden():
		_release_collision_request()
		return
	var d := global_position.distance_to(player.global_position)
	var waiting := mode == Mode.WAIT
	var pst := player.get_state()
	var player_ok := pst != PlayerCharacter.State.CINEMATIC and pst != PlayerCharacter.State.DEAD
	if player_ok and mode == Mode.BURROW and d > LOST_GROUND:
		burrow.cleanup()
		teleport_near_player()
		set_mode(Mode.FOLLOW)
	elif player_ok and not waiting and mode != Mode.BURROW:
		if is_airborne():
			if d > LOST_AIR:
				teleport_near_player(true)
				set_mode(Mode.ESCORT)
		elif d > LOST_GROUND:
			if prof.can_fly and d < LOST_AIR:
				brain.fly_to_player()
			else:
				teleport_near_player()
				set_mode(Mode.FOLLOW)
		elif global_position.y < -250.0:
			teleport_near_player()
	_update_collision_request(d)


func _update_collision_request(d: float) -> void:
	if renderer == null or not is_instance_valid(renderer) or not renderer.has_method("request_collision_around"):
		return
	if d > 90.0 and not is_airborne():
		if _collision_req < 0:
			_collision_req = int(renderer.call("request_collision_around", global_position, 40.0, 0.0))
		else:
			renderer.call("move_collision_request", _collision_req, global_position)
	else:
		_release_collision_request()


func _release_collision_request() -> void:
	if _collision_req >= 0 and renderer != null and is_instance_valid(renderer) and renderer.has_method("release_collision_request"):
		renderer.call("release_collision_request", _collision_req)
	_collision_req = -1
