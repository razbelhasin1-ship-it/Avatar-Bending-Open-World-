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


## A deep-sea point of the real world map (open water, no safe ground within 120 m).
func _open_sea() -> Vector3:
	for r in range(1200, 4000, 100):
		for k in 24:
			var a := TAU * float(k) / 24.0
			var x := sin(a) * float(r)
			var z := cos(a) * float(r)
			var w := WorldData.get_water_height(x, z)
			if not is_finite(w) or w - WorldData.get_height(x, z) < 8.0:
				continue
			var s := WorldData.get_safe_ground(Vector3(x, w, z))
			if Vector2(s.x - x, s.z - z).length() > 120.0:
				return Vector3(x, w, z)
	return Vector3.INF


## Hopping off a mount that swims out at sea: WorldData's safe ground was the only fallback,
## so the rider arced to dry land hundreds of metres away (or to a port quay kilometres off).
## Now the rider slips into the water beside the mount (players swim and never drown).
func test_dismount_at_sea_stays_beside_the_mount() -> void:
	WorldData.use_flat_world(false)
	if not WorldData.has_world_data():
		WorldData.use_flat_world(true)
		fail("real world data needed")
		return
	var sea := _open_sea()
	if not expect(sea.is_finite(), "found open sea on the world map"):
		WorldData.use_flat_world(true)
		return
	var c := CompanionSim.companion(self, &"polar_bear_dog", sea - Vector3.UP * 1.0)
	var at: Vector3 = c.rider.call("_ground_beside")
	var d := Vector2(at.x - c.global_position.x, at.z - c.global_position.z).length()
	expect(d < c.prof.radius() + 3.0, "companion hop-down point stays beside the mount (%.0f m away)" % d)
	expect(absf(at.y - sea.y) < 0.5, "into the water at the surface (y %.2f, sea %.2f)" % [at.y, sea.y])
	# The player's own (external) dismount fallback.
	var p := PlayerSim.player(self, E.WATER, sea + Vector3.UP * 1.5)
	var seat := Node3D.new()
	add_child(seat)
	seat.global_position = sea + Vector3.UP * 1.5
	p.mount_on(c, seat)
	p.dismount()
	var pd := Vector2(p.global_position.x - sea.x, p.global_position.z - sea.z).length()
	expect(pd < 4.0, "external dismount at sea stays beside the seat (%.0f m away)" % pd)
	WorldData.use_flat_world(true)


# --- death / respawn -------------------------------------------------------------------------------

## The world's respawn sequence (death beat, fade, wait for the respawn point's ground) can be
## overtaken by the player's own auto-respawn backstop; the sequence then respawned the player a
## second time (player_respawned twice, health / chi reset twice). Found by the world fuzz.
func test_world_respawn_never_doubles_with_the_backstop() -> void:
	WorldData.use_flat_world(false)
	WorldData.load_world()
	GameState.new_game(E.WATER)
	var w := (load("res://scenes/world/world.tscn") as PackedScene).instantiate() as PlayableScene
	w.options = {"new_game": true, "skip_intro": true, "no_content": true}
	add_child(w)
	var t0 := Time.get_ticks_msec()
	while not w.is_ready and Time.get_ticks_msec() - t0 < 90000:
		await frames(1)
	if not expect(w.is_ready, "world ready"):
		w.queue_free()
		return
	var p: PlayerCharacter = w.player
	var home := WorldData.get_spawn(E.WATER)
	p.teleport(Transform3D(Basis(), home.origin + Vector3(20, 0, 30)))
	await physics_frames(5)
	var respawns := [0]
	var cb := func() -> void: respawns[0] += 1
	Events.player_respawned.connect(cb)
	# The backstop fires inside the world's sequence (after its 2.2 s beat, during the fade).
	p.auto_respawn_time = RespawnSystem.DEATH_DELAY + 0.3
	var hit := HitInfo.make(9999.0, null, E.FIRE, HitInfo.Reaction.KNOCKDOWN, Vector3.FORWARD, 2.0)
	hit.team = Combat.Team.ENEMY
	Combat.deal(p, hit)
	await physics_frames(2)
	expect(p.get_state() == S.DEAD, "dead")
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000 and (w.respawn.busy or not p.is_alive()):
		await frames(1)
	await physics_frames(5)
	Events.player_respawned.disconnect(cb)
	expect(p.is_alive() and not w.respawn.busy, "respawned")
	expect(respawns[0] == 1, "one respawn for one death (%d)" % respawns[0])
	expect(p.global_position.distance_to(home.origin) < 2.5, "ends at the respawn point (%.1f m)" % p.global_position.distance_to(home.origin))
	w.queue_free()
	await frames(3)
	WorldData.use_flat_world(true)


# --- enemies ---------------------------------------------------------------------------------------

## A suspicious enemy that hears a fight it cannot see: every new noise restarted its 7 s
## give-up clock, so it stayed in ALERT until the 12 s state timeout (an engine warning), went
## home and was pulled back into ALERT by the next noise - forever. Found by the arena fuzz.
func test_suspicion_gives_up_under_continuous_noise() -> void:
	EnemySim.begin()
	var p := PlayerSim.player(self, E.FIRE, Vector3(0, 0, 60))
	var e := EnemySim.enemy(self, &"pirate_archer", Vector3.ZERO)
	PlayerSim.box(self, Vector3(0, 1.5, 6), Vector3(12, 3, 0.5))
	await EnemySim.settle(self)
	e.brain.on_noise(Vector3(4, 0, 14), null)
	expect(e.state == EnemyBase.State.ALERT, "suspicious (%s)" % e.get_state_name())
	var max_alert := 0.0
	var left_alert := false
	for i in 60 * 14:
		if i % 30 == 0 and e.state == EnemyBase.State.ALERT:
			e.brain.on_noise(Vector3(4.0 + float(i % 7), 0, 14), null)   # a fight keeps sounding beyond the wall
		await EnemySim.step([p, e], 1)
		if e.state == EnemyBase.State.ALERT:
			max_alert = maxf(max_alert, e.state_time)
		else:
			left_alert = true
	EnemySim.end()
	expect(left_alert, "gave up the search")
	expect(max_alert < 9.0, "never reached the 12 s ALERT safety timeout (longest %.1f s)" % max_alert)


# --- focus / hitstop exploits --------------------------------------------------------------------

func _ring_of_dummies(center: Vector3, n: int, r: float) -> Array[TrainingDummy]:
	var out: Array[TrainingDummy] = []
	for i in n:
		var a := TAU * float(i) / float(n)
		var d := TrainingDummy.new()
		d.look = &"post"
		d.max_health = 5000.0
		d.position = center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		add_child(d)
		d.home = d.global_transform
		out.append(d)
	return out


## Counts Events.hitstop emissions and the Focus gained while `frames` steps run.
func _measure(p: PlayerCharacter, frames: int) -> Dictionary:
	var stops := [0]
	var cb := func(_d: float) -> void: stops[0] += 1
	Events.hitstop.connect(cb)
	var hits0 := BendingHits.applied_hits
	var gained := 0.0
	var last := p.resources.focus
	for i in frames:
		# One real physics frame per step: BendingFeedback dedupes hitstop per physics frame.
		await get_tree().physics_frame
		PlayerSim.step_once(p)
		if p.resources.focus > last:
			gained += p.resources.focus - last
		last = p.resources.focus
	Events.hitstop.disconnect(cb)
	return {"hitstops": stops[0], "focus": gained, "hits": BendingHits.applied_hits - hits0}


## A signature refilled the Focus it costs from its own pulses: Tidal Torrent's pull pulses
## (+6 Focus each, every 0.25 s, per target) gave a surrounded waterbender a full bar back at
## once, so the signature could be chained forever. Signatures never build Focus now.
func test_signature_does_not_refill_focus() -> void:
	for pair: Array in [[E.WATER, &"tidal_torrent"], [E.FIRE, &"inferno"], [E.EARTH, &"earthquake"], [E.AIR, &"air_tornado"]]:
		var p := PlayerSim.player(self, pair[0], Vector3(float(pair[0]) * 60.0 - 90.0, 0, 40))
		await PlayerSim.step(p, 3)
		var ds := _ring_of_dummies(p.global_position + Vector3(0, 0, -1), 4, 3.0)
		p.controller.set_slot(&"signature", AbilityRegistry.get_def(pair[1]))
		p.resources.infinite_chi = true
		p.resources.mark_combat()
		p.resources.set_focus(100.0)
		p.input.press(&"ability_special")
		await PlayerSim.step(p, 2)
		p.input.release(&"ability_special")
		var started: bool = p.controller.current != null and p.controller.current.def.id == pair[1]
		expect(started, "%s started" % pair[1])
		var m: Dictionary = await _measure(p, 60 * 5)
		expect(int(m["hits"]) >= 4, "%s landed hits (%d)" % [pair[1], m["hits"]])
		expect(float(m["focus"]) < 1.0, "%s gave back no Focus (%.0f gained from %d hits)" % [pair[1], m["focus"], m["hits"]])
		for d in ds:
			d.queue_free()
		p.queue_free()
		await frames(1)


## Water Jet pulses every 0.15 s: each landed pulse requested hitstop (a stutter every pulse)
## and gave +6 Focus - one 3 s jet on a single dummy filled the signature bar.
func test_water_jet_pulses_no_hitstop_spam_or_focus_farm() -> void:
	var p := PlayerSim.player(self, E.WATER, Vector3.ZERO)
	await PlayerSim.step(p, 3)
	var ds := _ring_of_dummies(Vector3(0, 0, -5), 1, 0.0)
	p.controller.set_slot(&"technique_1", AbilityRegistry.get_def(&"water_jet"))
	p.resources.infinite_chi = true
	p.resources.mark_combat()
	p.resources.set_focus(0.0)
	p.input.press(&"ability_1")
	var m: Dictionary = await _measure(p, 60 * 4)
	p.input.release(&"ability_1")
	await PlayerSim.step(p, 30)
	expect(int(m["hits"]) >= 10, "the jet kept hitting (%d pulses landed)" % m["hits"])
	expect(int(m["hitstops"]) <= 2, "no hitstop per pulse (%d hitstops)" % m["hitstops"])
	expect(float(m["focus"]) <= 30.0, "no Focus farm from the stream (%.0f Focus from %d pulses)" % [m["focus"], m["hits"]])
	for d in ds:
		d.queue_free()


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


## Suspected, refuted: the picked interactable freed between two 10 Hz picks (a despawned NPC,
## a picked-up prop) and interact pressed. A freed instance read from a typed member compares
## equal to null, so try_interact() simply refuses - kept as a guard.
func test_interact_with_a_freed_interactable() -> void:
	var p := PlayerSim.player(self, E.EARTH, Vector3.ZERO)
	await PlayerSim.step(p, 3)
	var it := Interactable.new()
	it.prompt = "Pick up"
	it.position = Vector3(0, 0, -1.2)
	add_child(it)
	await PlayerSim.step(p, 12)
	expect(p.interaction.current == it, "picked as the current interactable")
	it.free()
	expect(not p.try_interact(), "a freed interactable is ignored")
	expect(p.get_state() == S.LOCOMOTION, "no interacting state")


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


## Companion assist: the target enemy freed during the approach / fire breath (a fled enemy
## vanishing, a despawn) was passed to a typed `_valid_enemy` -> a script error every tick
## until the 9 s assist cap. Found by the fuzz (893 errors in a 3-minute arena run).
func test_companion_assist_survives_a_freed_target() -> void:
	var p := PlayerSim.player(self, E.FIRE, Vector3.ZERO)
	var c := CompanionSim.companion(self, &"dragon", Vector3(-4, 0, 2), p)
	await CompanionSim.step(c, p, 5)
	var e := EnemyBase.create(&"bandit_brawler", {"home": Transform3D(Basis.IDENTITY, Vector3(0, 0, -8)), "rewards": false})
	add_child(e)
	await CompanionSim.step(c, p, 2)
	c.assist.begin(e)
	c.set_mode(M.ASSIST)
	await CompanionSim.step(c, p, 3)
	e.free()
	await CompanionSim.step(c, p, 10)
	expect(c.assist.phase == CompanionAssist.Phase.NONE, "assist dropped the freed target (phase %d)" % c.assist.phase)
	expect(c.mode != M.ASSIST, "companion back to following (%s)" % c.get_mode_name())
	# Fire breath with the target gone mid-breath.
	var e2 := EnemyBase.create(&"bandit_brawler", {"home": Transform3D(Basis.IDENTITY, Vector3(0, 0, -6)), "rewards": false})
	add_child(e2)
	c.assist.cooldown_left = 0.0
	c.assist.begin(e2)
	c.set_mode(M.ASSIST)
	c.assist.call("_start_act")
	e2.free()
	await CompanionSim.step(c, p, 90)
	expect(c.assist.phase != CompanionAssist.Phase.ACT or c.assist.t < CompanionAssist.ACT_TIMEOUT + 0.1, "breath ends on its own")
