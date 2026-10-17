class_name PlayerCharacter
extends CharacterBody3D
## The playable bender (docs/modules/player.md). Groups &"player",
## &"damageable", &"persist"; team Combat.Team.PLAYER; feet at the origin.
##
##   var p: PlayerCharacter = preload("res://scenes/player/player.tscn").instantiate()
##   p.element = ElementDefs.Element.FIRE      # default: GameState.element
##   world.add_child(p)
##   p.respawn_at(spawn_xform)                 # teleport (+ revive)
##   hud.bind_player(p)
##
## Components (children): PlayerInput, PlayerResources, PlayerTargeting,
## PlayerInteraction, BendingController, PlayerVisual (HumanoidRig), and a
## top-level PlayerCamera. Movement physics: PlayerMotor + LocomotionProfile.
## State machine: PlayerStates (every state has a timeout / exit path).

signal resource_changed(resource: StringName, value: float, max_value: float)
signal state_changed(new_state: int, old_state: int)
signal died
signal respawned

enum State { LOCOMOTION, AIRBORNE, DODGE, ACTION, DEFEND, HITSTUN, KNOCKED_DOWN, GETUP, DEAD, MOUNTED, INTERACTING, CINEMATIC }

const MAX_HEALTH := {ElementDefs.Element.AIR: 95.0, ElementDefs.Element.EARTH: 130.0, ElementDefs.Element.FIRE: 105.0, ElementDefs.Element.WATER: 110.0}
const MAX_POISE := {ElementDefs.Element.AIR: 22.0, ElementDefs.Element.EARTH: 55.0, ElementDefs.Element.FIRE: 32.0, ElementDefs.Element.WATER: 30.0}
const CAPSULE_RADIUS := 0.32
const CAPSULE_HEIGHT := 1.74

@export var element: int = ElementDefs.Element.NONE
## Rig look overrides (body, skin, hair_style, seed ...), see docs/modules/characters.md.
@export var appearance: Dictionary = {}
## Creates and drives a PlayerCamera (disable when another camera system owns the view).
@export var use_camera := true
## Respawn by itself at the last safe ground if nobody calls respawn_at() after death.
@export var auto_respawn := true
@export var auto_respawn_time := 8.0

var team: int = Combat.Team.PLAYER
var health: HealthComponent
var input: PlayerInput
var resources: PlayerResources
var targeting: PlayerTargeting
var interaction: PlayerInteraction
var controller: BendingController
var visual: PlayerVisual
var camera_rig: PlayerCamera
var motor: PlayerMotor
var states: PlayerStates
var ctx: BendingContext
var profile: LocomotionProfile
## Companion (set by the companions module; HUD reads it).
var companion: Node3D = null
## Mount seat while MOUNTED.
var mount_seat: Node3D = null
var mount_node: Node3D = null
var display_name := "You"

var _water_check := 0.0
var _built := false
var _death_emitted := false
var _was_floor := true


func _ready() -> void:
	add_to_group(&"player")
	add_to_group(&"damageable")
	add_to_group(&"persist")
	collision_layer = Layers.PLAYER
	collision_mask = Layers.SOLID | Layers.ENEMY | Layers.NPC
	if not ElementDefs.is_valid(element):
		element = GameState.element if GameState.has_element() else ElementDefs.Element.WATER
	_build()
	# Techniques learned / equipped anywhere (quest rewards, trainers, the skill tree, scripts)
	# are usable at once: the controller re-reads GameState and the HUD / touch buttons, which
	# poll get_ability_slot_info(), follow on the next frame.
	Events.abilities_equipped_changed.connect(_queue_loadout_reload)
	Events.ability_unlocked.connect(func(_id: StringName) -> void: _queue_loadout_reload())
	Events.player_spawned.emit(self)


var _reload_queued := false


func _queue_loadout_reload() -> void:
	if _reload_queued:
		return
	_reload_queued = true
	_reload_loadout.call_deferred()


func _reload_loadout() -> void:
	_reload_queued = false
	# Dev arenas run an element that is not the save's: their slots are set directly.
	if controller != null and GameState.element == element:
		controller.load_equipped()


func _build() -> void:
	_built = true
	var shape := CollisionShape3D.new()
	shape.name = "Capsule"
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_RADIUS
	cap.height = CAPSULE_HEIGHT
	shape.shape = cap
	shape.position = Vector3(0, CAPSULE_HEIGHT * 0.5, 0)
	add_child(shape)
	safe_margin = 0.02
	health = HealthComponent.new()
	health.name = "HealthComponent"
	add_child(health)
	input = PlayerInput.new()
	input.name = "PlayerInput"
	add_child(input)
	resources = PlayerResources.new()
	resources.name = "PlayerResources"
	resources.auto_tick = false
	resources.health = health
	add_child(resources)
	resources.changed.connect(_on_resource_changed)
	health.changed.connect(func(cur: float, mx: float) -> void: _on_resource_changed(&"health", cur, mx))
	targeting = PlayerTargeting.new()
	targeting.name = "PlayerTargeting"
	add_child(targeting)
	targeting.setup(self, team)
	interaction = PlayerInteraction.new()
	interaction.name = "PlayerInteraction"
	interaction.body = self
	add_child(interaction)
	visual = PlayerVisual.new()
	visual.name = "PlayerVisual"
	add_child(visual)
	controller = BendingController.new()
	controller.name = "BendingController"
	add_child(controller)
	states = PlayerStates.new(self)
	if use_camera:
		camera_rig = PlayerCamera.new()
		camera_rig.name = "PlayerCamera"
		camera_rig.target = self
		camera_rig.targeting = targeting
		add_child(camera_rig)
		camera_rig.make_current()
		camera_rig.snap_behind(self)
		targeting.camera = camera_rig.camera
		input.view = camera_rig
	set_element(element)


## Switches element: profile, rig (preset/style), core kit, techniques, health/poise.
func set_element(e: int) -> void:
	if states != null and states.state == State.MOUNTED:
		dismount()
	element = e if ElementDefs.is_valid(e) else ElementDefs.Element.WATER
	profile = LocomotionProfile.for_element(element)
	if motor == null:
		motor = PlayerMotor.new(self, profile)
	else:
		motor.set_profile(profile)
	var rig := visual.build(self, element, appearance)
	health.max_health = float(MAX_HEALTH.get(element, 100.0))
	health.max_poise = float(MAX_POISE.get(element, 30.0))
	health.health = health.max_health * clampf(GameState.player_health_ratio if GameState.element == element else 1.0, 0.05, 1.0)
	health.poise = health.max_poise
	resources.element = element
	if controller.is_busy():
		controller.cancel_current(&"element")
	ctx = BendingContext.new(self, rig, element, team)
	ctx.resources = resources
	ctx.aim_provider = aim
	ctx.on_hit = _on_ability_hit
	controller.setup(ctx)
	if GameState.element == element:
		AbilityRegistry.grant_starters(element)
	controller.load_equipped()
	var any_equipped := false
	for s in BendingController.TECHNIQUE_SLOTS:
		any_equipped = any_equipped or controller.get_slot_def(s) != null
	if not any_equipped:
		# Not this save's element (dev arenas): equip the element's starters directly.
		var i := 0
		for id in AbilityRegistry.starter_techniques(element):
			if i < 4:
				controller.set_slot(BendingController.TECHNIQUE_SLOTS[i], AbilityRegistry.get_def(id))
				i += 1
	states.change(State.LOCOMOTION)
	_on_resource_changed(&"health", health.health, health.max_health)
	resources.set_chi(resources.chi)


func get_bending_context() -> BendingContext:
	return ctx


# --- main loop ---------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _built or delta <= 0.0:
		return
	input.enabled = states.state != State.DEAD and states.state != State.CINEMATIC
	input.poll(delta)
	motor.sense()
	resources.tick(delta)
	_water_check -= delta
	if _water_check <= 0.0 and element == ElementDefs.Element.WATER:
		_water_check = 0.5
		resources.near_water = WaterSource.has_source(ctx)
	targeting.enabled = states.state not in [State.DEAD, State.CINEMATIC, State.MOUNTED]
	if input.consume(&"lock_on") and targeting.enabled:
		targeting.toggle_lock()
	targeting.tick(delta)
	ctx.move_input = input.move_vector
	controller.tick(delta)
	states.tick(delta)
	_post_move(delta)
	visual.tick(delta, motor.on_floor and not motor.swimming)
	interaction.enabled = states.is_free()
	interaction.tick(delta)
	_update_look()


func _post_move(_delta: float) -> void:
	var st := states.state
	# Pose states.
	if st == State.LOCOMOTION or st == State.AIRBORNE or st == State.ACTION or st == State.DODGE:
		if motor.swimming:
			visual.set_pose(&"swimming", 0.25)
		elif not motor.on_floor and st != State.DODGE:
			if motor.gliding:
				visual.set_pose(&"normal", 0.2)
			elif velocity.y < -4.0 and motor.air_time > 0.35:
				visual.set_pose(&"falling", 0.3)
			elif motor.air_time > 0.06:
				visual.set_pose(&"airborne", 0.12)
		elif visual.get_pose() in [&"airborne", &"falling", &"swimming"]:
			visual.set_pose(&"normal", 0.1)
	visual.set_gliding(motor.gliding and st == State.AIRBORNE)
	visual.set_skating(motor.skating and motor.on_floor and st == State.LOCOMOTION)
	if motor.landed_this_tick and st != State.KNOCKED_DOWN:
		_on_landed(motor.impact_speed, motor.fall_height)
	if camera_rig:
		var hv := Vector2(velocity.x, velocity.z).length()
		var fast := hv > profile.run_speed + 0.5 and st == State.LOCOMOTION
		camera_rig.fov_offset = lerpf(camera_rig.fov_offset, 6.0 if fast else 0.0, 0.08)


func _on_landed(impact: float, fall_h: float) -> void:
	var st := states.state
	var g := global_position
	var surf := motor.surface
	match profile.landing:
		&"cushion":
			if impact > 4.0:
				AirFx.ground_puff(self, g, surf, clampf(impact / 10.0, 0.4, 1.2))
				Audio.play_bending(element, &"jump", g, -6.0)
		&"quake":
			if fall_h >= profile.quake_fall_height:
				EarthFx.quake(self, g, 3.2, surf)
				Audio.play_bending(element, &"stomp", g)
				BendingHits.sphere(ctx, g + Vector3.UP * 0.4, 3.2, {"damage": 6.0, "reaction": HitInfo.Reaction.STAGGER, "force": 6.0,
						"stun": 0.5, "poise": 25.0}, HitInfo.new_attack_id(), &"earth_landing", {"push": &"radial"})
				BendingFeedback.shake(0.35, 0.25)
			elif impact > 6.0:
				EarthFx.dust_trail(self, g, Vector3.ZERO, surf, 1.5)
		&"spray":
			if surf == &"snow" or surf == &"ice" or motor.water_depth > 0.05:
				FxBurst.spawn(self, &"snow" if surf != &"water" else &"spray", g, {"count": clampf(impact / 8.0, 0.4, 1.4)})
		_:
			if impact > 7.0:
				FxBurst.spawn(self, &"dust", g, {"color": FxLib.surface_color(surf), "count": 0.6})
	if st == State.LOCOMOTION or st == State.AIRBORNE:
		if impact > 2.5 or motor.air_time > 0.3 or fall_h > 0.6:
			visual.land(impact * (0.6 if profile.landing == &"cushion" else 1.0))


func _update_look() -> void:
	var t := targeting.get_lock_target()
	if t != null:
		visual.look_at_point(BendingContext.target_point(t), 0.85)
	elif targeting.soft_target != null and resources.in_combat():
		visual.look_at_point(BendingContext.target_point(targeting.soft_target), 0.5)
	elif camera_rig and states.state == State.LOCOMOTION:
		var f := -camera_rig.global_basis.z
		visual.look_at_point(global_position + Vector3.UP * 1.5 + f * 8.0, 0.35)
	else:
		visual.clear_look()


# --- aiming / helpers ------------------------------------------------------------------------------

## Aim for abilities: lock target, else soft-aim target, else the camera direction.
func aim() -> Dictionary:
	var t := targeting.aim_target()
	var dir := -global_basis.z
	var point := global_position + dir * 12.0 + Vector3.UP * 1.2
	if camera_rig:
		var cf := -camera_rig.camera.global_basis.z
		dir = Vector3(cf.x, clampf(cf.y + 0.12, -0.5, 0.5), cf.z).normalized()
		var from := camera_rig.camera.global_position
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(from, from + cf * 60.0, Layers.SOLID | Layers.ENEMY | Layers.WILDLIFE)
		var ex: Array[RID] = [get_rid()]
		q.exclude = ex
		var r := space.intersect_ray(q)
		point = r["position"] if not r.is_empty() else from + cf * 60.0
	if t != null:
		dir = (BendingContext.target_point(t) - (global_position + Vector3.UP * 1.2)).normalized()
		point = BendingContext.target_point(t)
	return {"direction": dir, "target": t, "point": point}


## Facing while strafing locked-on (ZERO = face travel).
func strafe_direction() -> Vector3:
	var t := targeting.get_lock_target()
	if t == null or input.sprinting:
		return Vector3.ZERO
	var to := t.global_position - global_position
	to.y = 0.0
	return to.normalized() if to.length() > 0.3 else Vector3.ZERO


## Which slots may start while airborne: dodges (if the element can), Air strikes.
func can_bend_airborne(slot: StringName) -> bool:
	if slot == &"dodge":
		return profile.dodge_in_air
	if element == ElementDefs.Element.AIR and (slot == &"light" or slot == &"heavy"):
		return true
	# Abilities that work in the air say so in their data (Jet Step: params.in_air).
	var d := controller.get_slot_def(slot) if controller else null
	if d != null and bool(d.params.get("in_air", false)):
		return true
	return false


func on_ability_started(_a: BendingAbility) -> void:
	visual.enter_combat(6.0)
	resources.mark_combat()
	interaction.hide_prompt()


func _on_ability_hit(_hit: HitInfo, _target: Node, result: int) -> void:
	if result == Combat.Result.HIT or result == Combat.Result.KILLED:
		resources.mark_combat()
		visual.enter_combat(8.0)


func _on_resource_changed(resource: StringName, value: float, max_value: float) -> void:
	resource_changed.emit(resource, value, max_value)
	Events.player_resource_changed.emit(resource, value, max_value)


# --- HUD contract ----------------------------------------------------------------------------------

func get_health_component() -> HealthComponent:
	return health


func get_resource(resource: StringName) -> Vector2:
	return resources.get_resource(resource) if resources else Vector2.ZERO


func get_ability_slot_info(i: int) -> Dictionary:
	return controller.get_slot_info(i) if controller else {}


## HUD contract (optional): the element's signature while it is still locked ({} once learned).
func get_locked_signature_info() -> Dictionary:
	return controller.locked_signature_info() if controller else {}


func get_lock_target() -> Node3D:
	return targeting.get_lock_target() if targeting else null


func get_companion() -> Node3D:
	return companion if companion != null and is_instance_valid(companion) else null


func get_display_name() -> String:
	return display_name


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.15


func is_alive() -> bool:
	return health != null and not health.is_dead()


func get_state() -> int:
	return states.state


func get_state_name() -> String:
	return states.name_of(states.state)


# --- damage --------------------------------------------------------------------------------------

## Combat contract (docs/GAME_DESIGN.md §5): i-frames, defense / parry, poise,
## knockback per element, reactions, death. Sets hit.damage to the damage
## actually applied (damage numbers read it).
func receive_hit(hit: HitInfo) -> int:
	return PlayerDamage.receive(self, hit)


func die(hit: HitInfo = null) -> void:
	if _death_emitted:
		return
	_death_emitted = true
	# Never die half-mounted (collision off, seat refs set): get off first (bughunt_gameplay).
	if states.state == State.MOUNTED:
		dismount()
	controller.cancel_current(&"death")
	targeting.unlock()
	interaction.hide_prompt()
	var dir := hit.direction if hit else -global_basis.z
	visual.reaction(&"death", dir)
	velocity.x = 0.0
	velocity.z = 0.0
	states.change(State.DEAD, auto_respawn_time)
	GameState.incr_stat("deaths")
	died.emit()
	Events.player_died.emit()


## Respawn hook (the world scene drives it after Events.player_died): teleports,
## revives at 50% health (or `health_ratio`), clears states.
func respawn_at(xform: Transform3D, health_ratio: float = 0.5) -> void:
	if states.state == State.MOUNTED:
		dismount(xform.origin)
	controller.cancel_current(&"respawn")
	if health.is_dead():
		health.revive(health_ratio)
	_death_emitted = false
	motor.teleport(xform)
	visual.set_pose(&"normal", 0.0)
	visual.stop(0.0)
	if visual.rig:
		visual.rig.animator.paused = false
		visual.rig.animator.loco.reset(visual.rig.skeleton.global_transform)
	resources.set_chi(PlayerResources.CHI_MAX)
	states.change(State.LOCOMOTION)
	if camera_rig:
		camera_rig.snap_behind(self)
	respawned.emit()
	Events.player_respawned.emit()


func teleport(xform: Transform3D, mark_safe: bool = true) -> void:
	motor.teleport(xform, mark_safe)
	if visual.rig:
		visual.rig.animator.loco.reset(visual.rig.skeleton.global_transform)
	if camera_rig:
		camera_rig.snap_behind(self)


# --- persistence --------------------------------------------------------------------------------

func write_save_state() -> void:
	GameState.player_position = global_position
	GameState.player_yaw = motor.yaw if motor else rotation.y
	GameState.player_health_ratio = health.ratio() if health and not health.is_dead() else 0.5


## Places the player where the save says (if it has a position).
func apply_saved_state() -> bool:
	if not GameState.player_position.is_finite():
		return false
	teleport(Transform3D(Basis(Vector3.UP, GameState.player_yaw), GameState.player_position))
	health.health = health.max_health * clampf(GameState.player_health_ratio, 0.05, 1.0)
	_on_resource_changed(&"health", health.health, health.max_health)
	return true


# --- interaction / cinematic / mount hooks --------------------------------------------------------

func try_interact() -> bool:
	var it := interaction.current
	if it == null or not it.can_interact(self):
		return false
	var to := it.focus_point() - global_position
	to.y = 0.0
	if to.length() > 0.1:
		motor.face(to)
	if it.animation != &"":
		visual.play(it.animation, {"blend_in": 0.1})
	states.change(State.INTERACTING, clampf(it.lock_time, 0.05, 10.0))
	interaction.hide_prompt()
	it.interact(self)
	return true


## Ends Interacting early (dialogue closed etc.).
func end_interaction() -> void:
	if states.state == State.INTERACTING:
		states.change(State.LOCOMOTION)


## Locks the player for a cutscene (input off) for at most `max_seconds`.
func enter_cinematic(max_seconds: float = 120.0) -> void:
	# A cinematic that starts while riding (the tutorial ends on its Ride lesson) used to leave
	# MOUNTED without a dismount: collision stayed off and the mount kept its rider, so the
	# player fell through the floor when the cinematic ended. Get off first (bughunt_gameplay).
	if states.state == State.MOUNTED:
		dismount()
	controller.cancel_current(&"cinematic")
	targeting.unlock()
	interaction.hide_prompt()
	states.change(State.CINEMATIC, max_seconds)


func exit_cinematic() -> void:
	if states.state == State.CINEMATIC:
		states.change(State.LOCOMOTION)


## Companions module: seats the player on `seat` (Node3D following the mount's
## saddle socket). The body stops colliding and follows the seat every tick.
func mount_on(mount: Node3D, seat: Node3D) -> void:
	controller.cancel_current(&"mount")
	targeting.unlock()
	interaction.hide_prompt()
	mount_node = mount
	mount_seat = seat
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	motor.carried = true
	visual.set_pose(&"riding", 0.2)
	states.change(State.MOUNTED)
	if camera_rig:
		camera_rig.set_target_override(mount)
		camera_rig.set_mode(&"mount", {"height": 3.0, "distance": 7.0, "shoulder": 0.0})
	Events.mounted.emit(mount)


## Leaves the mount, landing at `at` (default: beside the seat on the ground).
func dismount(at: Vector3 = Vector3.INF) -> void:
	if states.state != State.MOUNTED:
		return
	var m := mount_node
	var pos := at
	if not pos.is_finite():
		var base := mount_seat.global_position if mount_seat != null and is_instance_valid(mount_seat) else global_position
		var side := (mount_seat.global_basis.x if mount_seat != null and is_instance_valid(mount_seat) else global_basis.x) * 1.8
		var want := base + side
		pos = want
		if WorldData.has_world_data():
			# Out at sea the nearest safe ground can be far away (a port km off): slip into the
			# water beside the mount instead (the player swims, never drowns) (bughunt_gameplay).
			var safe := WorldData.get_safe_ground(want)
			var w := WorldData.get_water_height(want.x, want.z)
			var at_sea := is_finite(w) and w - WorldData.get_height(want.x, want.z) > 1.0
			if safe.is_finite() and (not at_sea or Vector2(safe.x - want.x, safe.z - want.z).length() < 10.0):
				pos = safe
			elif at_sea:
				pos = Vector3(want.x, w, want.z)
		pos.y = maxf(pos.y, ctx.ground_y(want, 3.0, 12.0))
	mount_node = null
	mount_seat = null
	collision_layer = Layers.PLAYER
	collision_mask = Layers.SOLID | Layers.ENEMY | Layers.NPC
	motor.carried = false
	visual.set_pose(&"normal", 0.2)
	# A dismount point may be mid-air (letting go of a flyer) or over water: it only becomes
	# the last safe ground once the player actually stands there (bughunt_gameplay).
	teleport(Transform3D(Basis(Vector3.UP, motor.yaw), pos), false)
	states.change(State.LOCOMOTION)
	if camera_rig:
		camera_rig.clear_target_override()
		camera_rig.set_mode(&"default")
	Events.dismounted.emit(m)


func update_mounted(_delta: float) -> void:
	if mount_seat == null or not is_instance_valid(mount_seat) or not mount_seat.is_inside_tree():
		dismount()
		return
	global_position = mount_seat.global_position
	var f := -mount_seat.global_basis.z
	motor.face(f)
	velocity = Vector3.ZERO
	# A ground mount on the floor carries the rider's safe ground along (tunnelling = collision off).
	var carrier := mount_node as CharacterBody3D if is_instance_valid(mount_node) else null
	if carrier != null and carrier.collision_layer != 0 and carrier.is_on_floor():
		motor.carrier_on_floor(carrier.global_position, carrier.get_floor_normal())
	if input.consume(&"mount"):
		# The mount may animate the dismount (hop down / let go in the air): companions module.
		if mount_node != null and is_instance_valid(mount_node) and mount_node.has_method("request_dismount"):
			mount_node.call("request_dismount")
		else:
			dismount()
