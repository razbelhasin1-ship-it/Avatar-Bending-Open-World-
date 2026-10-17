extends TestCase
## bughunt_gameplay (wave 4 QA): regression tests for the gameplay bugs found by the adversarial
## bug hunt (docs/qa/bughunt_gameplay.md). Each test reproduces the original failure.

const E := ElementDefs.Element
const S := PlayerCharacter.State
const M := Companion.Mode

var _ground: StaticBody3D


func before_each() -> void:
	WorldData.use_flat_world(true)
	TimeDilation.enabled = false
	BendingHits.clear_log()
	GroundSampler.clear_zones()
	GameState.new_game(E.WATER)
	_ground = PlayerSim.ground(self, 600.0)


func after_each() -> void:
	WorldData.use_flat_world(false)
	WorldData.height_override = Callable()
	WorldData.clear_water_sources()
	GroundSampler.clear_zones()
	TimeDilation.enabled = true
	TimeDilation.clear()
	Engine.time_scale = 1.0
	for n in get_children():
		n.queue_free()
	await frames(2)


func _mounted(species: StringName, element: int) -> Array:
	var p := PlayerSim.player(self, element, Vector3.ZERO)
	var c := CompanionSim.companion(self, species, Vector3(-2.2, 0, 0), p)
	await CompanionSim.step(c, p, 30)
	await CompanionSim.tap(c, p, &"mount")
	await CompanionSim.step_until(c, p, func() -> bool: return c.mode == M.RIDDEN, 120)
	await CompanionSim.step(c, p, 5)
	return [c, p]


# --- mount / cinematic ------------------------------------------------------------------------------

## A cinematic (the tutorial ends on the Ride lesson, dialogues, scripted scenes) used to start
## while the player sat on the companion: the player left MOUNTED without a dismount, so the
## collision layers stayed 0 and the mount refs stayed set - after the cinematic the player fell
## through the floor and the companion stayed "ridden" with nobody on it.
func test_cinematic_while_mounted_dismounts_cleanly() -> void:
	var r: Array = await _mounted(&"polar_bear_dog", E.WATER)
	var c: Companion = r[0]
	var p: PlayerCharacter = r[1]
	if not expect(p.get_state() == S.MOUNTED and c.mode == M.RIDDEN, "seated first (%s / %s)" % [p.get_state_name(), c.get_mode_name()]):
		return
	var dismounts: Array = []
	var cb := func(m: Node3D) -> void: dismounts.append(m)
	Events.dismounted.connect(cb)
	p.enter_cinematic(3.0)
	await CompanionSim.step(c, p, 30)
	expect(p.get_state() == S.CINEMATIC, "in the cinematic (%s)" % p.get_state_name())
	expect(p.collision_layer == Layers.PLAYER and p.collision_mask == (Layers.SOLID | Layers.ENEMY | Layers.NPC), "collision restored for the cinematic (layer %d)" % p.collision_layer)
	expect(p.mount_node == null and p.mount_seat == null, "mount refs cleared")
	expect(dismounts.has(c), "Events.dismounted for the companion")
	expect(not c.is_ridden(), "companion no longer ridden (%s)" % c.get_mode_name())
	p.exit_cinematic()
	await CompanionSim.step(c, p, 90)
	Events.dismounted.disconnect(cb)
	expect(p.get_state() == S.LOCOMOTION and p.motor.on_floor, "standing after the cinematic (%s)" % p.get_state_name())
	expect(p.global_position.y > -0.3, "did not fall through the floor (y %.2f)" % p.global_position.y)
	expect(p.camera_rig == null or p.camera_rig.get("_override") == null, "camera override cleared")


## respawn_at / die never leave a seated rider half-mounted either.
func test_respawn_while_mounted_dismounts() -> void:
	var r: Array = await _mounted(&"badgermole", E.EARTH)
	var c: Companion = r[0]
	var p: PlayerCharacter = r[1]
	if not expect(p.get_state() == S.MOUNTED, "seated first"):
		return
	p.respawn_at(Transform3D(Basis.IDENTITY, Vector3(10, 0, 10)), 1.0)
	await CompanionSim.step(c, p, 60)
	expect(p.get_state() == S.LOCOMOTION, "on foot after the respawn (%s)" % p.get_state_name())
	expect(p.collision_layer == Layers.PLAYER and p.mount_node == null, "collision + refs restored")
	expect(p.global_position.y > -0.3 and Vector2(p.global_position.x - 10.0, p.global_position.z - 10.0).length() < 1.0, "at the respawn point (%s)" % p.global_position)
	expect(not c.is_ridden(), "companion released (%s)" % c.get_mode_name())


## Letting go of a flying mount teleports the rider to a point in the sky; that point used to
## become the motor's "last safe ground", so a save taken while falling (WorldSaveGuard stores
## last_safe_position() for an airborne player) - or after a later mid-air catch - put the
## continue point in mid-air (over the sea: a long swim back).
func test_midair_dismount_is_not_safe_ground() -> void:
	var p := PlayerSim.player(self, E.AIR, Vector3(3, 0, 3))
	await PlayerSim.step(p, 10)
	expect(p.motor.last_safe_position().distance_to(Vector3(3, 0, 3)) < 0.3, "standing spot is safe (%s)" % p.motor.last_safe_position())
	var mount := Node3D.new()
	add_child(mount)
	var seat := Node3D.new()
	mount.add_child(seat)
	seat.position = Vector3(0, 40, 0)
	p.mount_on(mount, seat)
	await PlayerSim.step(p, 10)
	p.dismount(Vector3(8, 40, 8))
	expect(p.get_state() != S.MOUNTED, "let go")
	var safe := p.motor.last_safe_position()
	expect(safe.y < 1.0, "mid-air release point is not safe ground (%s)" % safe)
	# Once the player stands on the ground again, that becomes the safe point.
	var n := await PlayerSim.step_until(p, func() -> bool: return p.motor.on_floor and p.get_state() == S.LOCOMOTION, 60 * 8)
	await PlayerSim.step(p, 3)
	expect(n >= 0, "landed")
	expect(p.motor.last_safe_position().distance_to(Vector3(8, 0, 8)) < 1.5, "landing spot becomes safe (%s)" % p.motor.last_safe_position())
	mount.queue_free()


# --- freed instances -----------------------------------------------------------------------------

## A projectile whose caster is freed while it flies (an enemy despawned / cleared mid-shot)
## built its HitInfo with the freed caster as a typed argument: a script error every frame
## until the projectile expired, and the hit never landed.
func test_projectile_outlives_its_caster() -> void:
	var caster := CharacterBody3D.new()
	add_child(caster)
	caster.global_position = Vector3(0, 0, 10)
	var ctx := BendingContext.new(caster, null, E.FIRE, Combat.Team.ENEMY)
	var p := PlayerSim.player(self, E.EARTH, Vector3.ZERO)
	await PlayerSim.step(p, 3)
	var taken: Array = []
	var cb := func(amount: float, hit: HitInfo) -> void: taken.append([amount, hit.source])
	Events.player_damaged.connect(cb)
	await physics_frames(2)
	var proj := BendingProjectile.launch(ctx, Vector3(0, 1.2, 8), Vector3(0, 0, -1), 20.0, {"damage": 7.0, "reaction": HitInfo.Reaction.FLINCH}, {"radius": 0.3, "range": 30.0})
	caster.free()
	for i in 60:
		await physics_frames(1)
		if not proj.alive:
			break
	Events.player_damaged.disconnect(cb)
	expect(not proj.alive, "projectile finished")
	expect(taken.size() == 1, "the shot still landed after its caster was gone (%d hits)" % taken.size())
	expect(taken.is_empty() or taken[0][1] == null, "no freed source on the hit")


## Air Tornado: a captured body freed mid-spin ("Trying to cast a freed object" every frame).
func test_tornado_survives_a_freed_captive() -> void:
	var p := PlayerSim.player(self, E.AIR, Vector3.ZERO)
	await PlayerSim.step(p, 3)
	var def := AbilityRegistry.get_def(&"air_tornado")
	if not expect(def != null, "air tornado registered"):
		return
	var ab := def.instantiate()
	ab.ctx = p.ctx
	ab.controller = p.controller
	var victim := CharacterBody3D.new()
	add_child(victim)
	victim.global_position = Vector3(0, 0, -5)
	ab.set("formed", true)
	ab.set("center", Vector3(0, 0, -5))
	(ab.get("captured") as Dictionary)[victim.get_instance_id()] = {"node": victim, "angle": 0.0, "t": 0.0, "h0": 0.0}
	victim.free()
	ab.call("_steer", 1.0 / 60.0)
	expect((ab.get("captured") as Dictionary).is_empty(), "freed captive dropped")
	(ab.get("captured") as Dictionary)[12345] = {"node": null, "angle": 0.0, "t": 0.0, "h0": 0.0}
	ab.call("_blow")
	expect((ab.get("captured") as Dictionary).is_empty(), "blow clears captives")
	ab.call("on_cancel", &"test")
