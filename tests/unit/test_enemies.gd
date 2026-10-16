extends TestCase
## Enemies module: archetype data, spawning, perception (cone, LOS, proximity),
## state flow idle -> alert -> strafe -> telegraphed attack, attack tokens, reactions
## by weight class, knockdown / get-up i-frames, shields, agile dodges, bending
## enemies through the real abilities, parries, leash / return, death rewards,
## surrender / flee, captain phases, encounter sites + director, combat state, and a
## no-stuck fuzz.

const E := ElementDefs.Element
const S := EnemyBase.State
const R := HitInfo.Reaction


func before_each() -> void:
	WorldData.use_flat_world(true)
	TimeDilation.enabled = false
	GroundSampler.clear_zones()
	BendingHits.clear_log()
	PlayerSim.ground(self)
	EnemySim.begin()
	Settings.set_value("gameplay", "difficulty", "normal")


func after_each() -> void:
	EnemySim.end()
	WorldData.use_flat_world(false)
	GroundSampler.clear_zones()
	TimeDilation.enabled = true
	TimeDilation.clear()
	Engine.time_scale = 1.0


func _player(pos: Vector3 = Vector3(0, 0, 6), element: int = E.FIRE) -> PlayerCharacter:
	var p := PlayerSim.player(self, element, pos)
	p.health.invulnerable = false
	return p


func _hit(src: Node, dmg: float, reaction: int, dir: Vector3, opts: Dictionary = {}) -> HitInfo:
	var h := HitInfo.make(dmg, src, int(opts.get("element", E.NONE)), reaction as HitInfo.Reaction, dir, float(opts.get("force", 4.0)))
	h.poise_damage = float(opts.get("poise", 10.0))
	h.is_heavy = bool(opts.get("heavy", false))
	h.is_projectile = bool(opts.get("projectile", false))
	h.stun_time = float(opts.get("stun", 0.0))
	h.lift = float(opts.get("lift", 0.0))
	if opts.has("origin"):
		h.origin = opts["origin"]
	return h


# --- data -----------------------------------------------------------------------------------------------

func test_archetypes_complete() -> void:
	EnemyClips.ensure()
	BendingClips.ensure()
	var ids := EnemyArchetypes.ids()
	expect(ids.size() >= 12, "at least 12 archetypes (%d)" % ids.size())
	var roles := {}
	for id in ids:
		var a := EnemyArchetypes.get_archetype(id)
		roles[a["role"]] = true
		expect(EnemyArchetypes.ROLES.has(a["role"]), "%s role" % id)
		expect(float(a["health"]) > 0.0 and float(a["poise"]) > 0.0, "%s health/poise" % id)
		expect(not (a["attacks"] as Array).is_empty(), "%s has attacks" % id)
		var look: Dictionary = a["look"]
		if look.has("creature"):
			expect(CreatureRig.species_list().has(StringName(look["creature"])), "%s creature species" % id)
		else:
			expect(CharacterOutfits.PRESETS.has(StringName(look.get("preset", &""))), "%s preset" % id)
		var all: Array = (a["attacks"] as Array).duplicate()
		for ph: Dictionary in a["phases"]:
			all.append_array(ph.get("attacks", []))
		for atk: Dictionary in all:
			var kind: StringName = atk.get("kind", &"")
			expect(kind in [&"melee", &"projectile", &"slam", &"bending", &"beast", &"charge"], "%s/%s kind" % [id, atk.get("id")])
			var clip: StringName = atk.get("clip", &"")
			if clip != &"":
				expect(AnimLibrary.has_clip(clip), "%s/%s clip %s" % [id, atk.get("id"), clip])
			var r: Vector2 = atk.get("range", Vector2(0, 2))
			expect(r.y > r.x, "%s/%s range" % [id, atk.get("id")])
			if kind in [&"melee", &"projectile", &"slam"]:
				var total := float(atk.get("approach", 0.2)) + float(atk.get("telegraph", 0.0))
				expect(total >= 0.3 or atk.get("glint", &"x") == &"", "%s/%s telegraph %.2f s readable" % [id, atk.get("id"), total])
	for role in EnemyArchetypes.ROLES:
		expect(roles.has(role), "role %s covered" % role)


func test_enemy_abilities_are_the_kit_scripts_and_unregistered() -> void:
	var before := AbilityRegistry.core_kit(E.FIRE)
	for el in [E.FIRE, E.EARTH, E.WATER]:
		var b := CharacterBody3D.new()
		add_child(b)
		var bc := BendingController.new()
		b.add_child(bc)
		bc.setup(BendingContext.new(b, null, el, Combat.Team.ENEMY))
		EnemyAbilities.setup_controller(bc, el, {"attacks": [{"bending": {"slot": &"light", "steps": 2}}]})
		for slot: StringName in [&"light", &"heavy", &"defense", &"dodge", &"technique_1"]:
			var d := bc.get_slot_def(slot)
			expect(d != null, "%s %s slot" % [ElementDefs.id_of(el), slot])
			if d:
				expect(String(d.id).begins_with("enemy_"), "%s enemy id" % d.id)
				expect(not AbilityRegistry.has(d.id), "%s not registered" % d.id)
				var kit := AbilityRegistry.get_def(StringName(String(d.id).trim_prefix("enemy_")))
				if kit:
					expect(d.script_path == kit.script_path, "%s uses the kit script" % d.id)
		expect((bc.get_slot_def(&"light").params["steps"] as Array).size() == 2, "chain trimmed to 2")
		b.queue_free()
	var after := AbilityRegistry.core_kit(E.FIRE)
	expect(before[&"light"] == after[&"light"], "player kit untouched")
	expect((AbilityRegistry.get_def(&"fire_combo").params["steps"] as Array).size() == 4, "kit chain untouched")


func test_spawn_every_archetype() -> void:
	var p := _player(Vector3(0, 0, 60))
	var x := -24.0
	for id in EnemyArchetypes.ids():
		var e := EnemySim.enemy(self, id, Vector3(x, 0, 0))
		x += 4.0
		expect(e.is_in_group(&"enemy") and e.is_in_group(&"damageable"), "%s groups" % id)
		expect(e.team == Combat.Team.ENEMY and e.collision_layer == Layers.ENEMY, "%s team/layer" % id)
		expect(e.is_alive() and e.health.health > 0.0, "%s alive" % id)
		expect(e.visual.node() != null, "%s visual" % id)
		expect((e.controller != null) == ElementDefs.is_valid(e.element), "%s controller iff bender" % id)
		await EnemySim.step([p, e], 20)
		expect(e.is_on_floor(), "%s stands on the ground" % id)
		e.queue_free()
	await physics_frames(2)


# --- perception -------------------------------------------------------------------------------------------

func test_perception_cone_los_and_proximity() -> void:
	var p := _player(Vector3(0, 0, 10))
	# Facing -Z: the player behind it (+Z) is not seen.
	var e := EnemySim.enemy(self, &"bandit_brawler", Vector3.ZERO)
	await EnemySim.settle(self)
	await EnemySim.step([p, e], 90)
	expect(not e.perception.is_spotted() and e.state in [S.IDLE, S.PATROL], "player behind is not spotted (%s)" % e.get_state_name())
	# In front at 10 m: spotted within ~0.4-1 s, alert beat, then combat.
	p.teleport(Transform3D(Basis(), Vector3(0, 0, -10)))
	var frames := await EnemySim.step_until([p, e], func() -> bool: return e.perception.is_spotted(), 120)
	expect(frames > 5 and frames < 80, "spotted in front after a short build-up (%d frames)" % frames)
	var f2 := await EnemySim.step_until([p, e], func() -> bool: return e.state in [S.CHASE, S.STRAFE, S.ATTACK], 120)
	expect(f2 >= 0, "engages after the spotted beat")
	e.queue_free()
	# A wall between them blocks sight.
	var e2 := EnemySim.enemy(self, &"bandit_brawler", Vector3(20, 0, 0))
	p.teleport(Transform3D(Basis(), Vector3(20, 0, -10)))
	PlayerSim.box(self, Vector3(20, 1.5, -5), Vector3(6, 3, 0.5))
	await EnemySim.settle(self)
	e2.perception.forget()
	await EnemySim.step([p, e2], 120)
	expect(not e2.perception.is_spotted(), "wall blocks line of sight")
	# Proximity: right behind it, it feels you.
	p.teleport(Transform3D(Basis(), Vector3(20, 0, 2.2)))
	var f3 := await EnemySim.step_until([p, e2], func() -> bool: return e2.perception.is_spotted(), 90)
	expect(f3 >= 0, "proximity sense behind")


func test_hearing_and_ally_call() -> void:
	var p := _player(Vector3(0, 0, 40))
	var a := EnemySim.enemy(self, &"fire_soldier", Vector3(0, 0, 0))
	var b := EnemySim.enemy(self, &"fire_archer", Vector3(8, 0, 0))
	await EnemySim.step([p, a, b], 10)
	# Combat noise near b draws it in (investigate).
	var h := _hit(p, 1.0, R.FLINCH, Vector3.FORWARD)
	h.position = Vector3(8, 1, 20)
	Events.hit_landed.emit(h, b, Combat.Result.HIT)
	expect(b.state == S.ALERT and not b.perception.engaged, "noise -> investigate")
	# a spots the player -> b (same faction, close) is called in.
	a.brain.engage(p)
	expect(b.perception.engaged, "ally answered the call")
	expect(a.state == S.ALERT and b.state == S.ALERT, "both in the spotted beat")


# --- combat flow ---------------------------------------------------------------------------------------------

func test_engage_strafe_telegraph_strike() -> void:
	var p := _player(Vector3(0, 0, -6))
	var e := EnemySim.enemy(self, &"bandit_brawler", Vector3.ZERO, p)
	await EnemySim.settle(self)
	var telegraphs: Array = []
	var strikes: Array = []
	e.attack_telegraphed.connect(func(_e: EnemyBase, a: Dictionary, s: float) -> void: telegraphs.append([EnemySim.time, a.get("id"), s]))
	e.attack_struck.connect(func(_e: EnemyBase, a: Dictionary) -> void: strikes.append([EnemySim.time, a.get("id")]))
	var hp0 := p.health.health
	await EnemySim.step_until([p, e], func() -> bool: return not strikes.is_empty(), 900)

	expect(not telegraphs.is_empty() and not strikes.is_empty(), "telegraphed then struck")
	if not telegraphs.is_empty() and not strikes.is_empty():
		var lead: float = strikes[0][0] - telegraphs[0][0]
		expect(lead >= 0.3, "glint at least 0.3 s before the strike (%.2f)" % lead)
	await EnemySim.step([p, e], 10)
	expect(p.health.health < hp0, "the strike hurt the idle player")
	expect(EnemyTelegraph.glints_shown > 0, "glint shown")


func test_attack_tokens_limit_attackers() -> void:
	var p := _player(Vector3.ZERO)
	p.health.invulnerable = true
	var es: Array = [p]
	for i in 5:
		var a := TAU * i / 5.0
		var e := EnemySim.enemy(self, &"bandit_brawler", Vector3(cos(a) * 6.0, 0, sin(a) * 6.0), p, {"seed": 50 + i})
		e.perception.alert_to(p)
		es.append(e)
	var max_attacking := 0
	var max_tokens := 0
	var moving_samples := 0
	var circling_samples := 0
	for f in 900:
		await EnemySim.step(es, 1)
		var attacking := 0
		for n in es:
			if n is EnemyBase and (n as EnemyBase).state == S.ATTACK:
				attacking += 1
			if n is EnemyBase and (n as EnemyBase).state == S.STRAFE:
				circling_samples += 1
				if Vector2((n as EnemyBase).velocity.x, (n as EnemyBase).velocity.z).length() > 0.3:
					moving_samples += 1
		max_attacking = maxi(max_attacking, attacking)
		max_tokens = maxi(max_tokens, AttackTokens.count(p))
	expect(max_tokens <= 2, "never more than 2 tokens (%d)" % max_tokens)
	expect(max_attacking <= 2 and max_attacking >= 1, "at most 2 attacking at once (%d)" % max_attacking)
	expect(circling_samples > 0 and float(moving_samples) / circling_samples > 0.8, "circlers keep moving (%d/%d)" % [moving_samples, circling_samples])


func test_tokens_released_on_death_and_free() -> void:
	var p := _player(Vector3.ZERO)
	var a := EnemySim.enemy(self, &"bandit_brawler", Vector3(3, 0, 0), p)
	var b := EnemySim.enemy(self, &"bandit_brawler", Vector3(-3, 0, 0), p)
	expect(AttackTokens.request(a, p) and AttackTokens.request(b, p, true), "two tokens")
	expect(not AttackTokens.request(EnemySim.enemy(self, &"bandit_brawler", Vector3(0, 0, 3), p), p, true), "third refused")
	Combat.deal(a, _hit(p, 9999.0, R.STAGGER, Vector3.LEFT))
	expect(not a.is_alive() and AttackTokens.count(p) == 1, "death releases the token")
	b.queue_free()
	await frames(2)
	expect(AttackTokens.count(p) == 0, "freed holder pruned")
	Settings.set_value("gameplay", "difficulty", "story")
	expect(AttackTokens.max_tokens() == 1, "story: 1 attacker")
	Settings.set_value("gameplay", "difficulty", "hard")
	expect(AttackTokens.max_tokens() == 3, "hard: 3 attackers")
	Settings.set_value("gameplay", "difficulty", "normal")


# --- reactions -------------------------------------------------------------------------------------------

func test_reactions_by_weight_class() -> void:
	var p := _player(Vector3(0, 0, 20))
	var light := EnemySim.enemy(self, &"bandit_skirmisher", Vector3(-4, 0, 0))
	var heavy := EnemySim.enemy(self, &"earth_chief", Vector3(4, 0, 0))
	# A heavy earth knockdown: the light fighter goes down, the chief only staggers.
	Combat.deal(light, _hit(p, 10.0, R.KNOCKDOWN, Vector3.LEFT, {"poise": 40.0, "heavy": true, "force": 9.0, "element": E.EARTH}))
	Combat.deal(heavy, _hit(p, 10.0, R.KNOCKDOWN, Vector3.RIGHT, {"poise": 40.0, "heavy": true, "force": 9.0, "element": E.EARTH}))
	expect(light.state == S.KNOCKDOWN, "skirmisher knocked down (%s)" % light.get_state_name())
	expect(heavy.state == S.STAGGER, "chief staggered (%s)" % heavy.get_state_name())
	expect(Vector2(light.velocity.x, light.velocity.z).length() > Vector2(heavy.velocity.x, heavy.velocity.z).length(), "light fighter flies further")
	# A light flinch never interrupts the chief's armored attack.
	await EnemySim.step([p, light, heavy], 120)
	heavy.perception.alert_to(p)
	heavy.brain.target = p
	var stomp: Dictionary = {}
	for a: Dictionary in heavy.attacks:
		if a.get("id") == &"quake_stomp":
			stomp = a
	expect(heavy.actions.start(stomp, p), "stomp starts")
	heavy.set_state(S.ATTACK)
	await EnemySim.step([p, heavy], 20)
	Combat.deal(heavy, _hit(p, 5.0, R.STAGGER, Vector3.RIGHT, {"poise": 20.0}))
	expect(heavy.state == S.ATTACK and heavy.actions.is_busy(), "armored attack keeps going")


func test_knockdown_getup_has_iframes() -> void:
	var p := _player(Vector3(0, 0, 8))
	var e := EnemySim.enemy(self, &"bandit_brawler", Vector3.ZERO, p)
	e.perception.alert_to(p)
	e.perception.engaged = true
	e.brain.target = p
	Combat.deal(e, _hit(p, 5.0, R.KNOCKDOWN, Vector3.BACK, {"poise": 30.0, "stun": 1.0}))
	expect(e.state == S.KNOCKDOWN, "knocked down")
	var f := await EnemySim.step_until([p, e], func() -> bool: return e.state == S.GETUP, 240)
	expect(f > 30, "lies down for a while (%d frames)" % f)
	var r := Combat.deal(e, _hit(p, 5.0, R.FLINCH, Vector3.BACK))
	expect(r == Combat.Result.DODGED, "get-up i-frames")
	var f2 := await EnemySim.step_until([p, e], func() -> bool: return e.state in [S.STRAFE, S.CHASE, S.ATTACK], 120)
	expect(f2 >= 0, "back in the fight")


func test_shield_blocks_front_and_projectiles_breaks_on_heavies() -> void:
	var p := _player(Vector3(0, 0, -6))
	var e := EnemySim.enemy(self, &"fire_shieldbearer", Vector3.ZERO, p)
	e.perception.alert_to(p)
	e.brain.target = p
	e.set_state(S.STRAFE)
	expect(e.shield_up(), "guard up")
	var hp := e.health.health
	var r := Combat.deal(e, _hit(p, 10.0, R.STAGGER, Vector3.BACK, {"origin": Vector3(0, 1, -3)}))
	expect(r == Combat.Result.BLOCKED and e.health.health > hp - 3.0, "frontal melee blocked (chip only)")
	var rp := Combat.deal(e, _hit(p, 10.0, R.FLINCH, Vector3.BACK, {"origin": Vector3(0, 1, -5), "projectile": true, "element": E.WATER}))
	expect(rp == Combat.Result.BLOCKED, "frontal water projectile blocked")
	var rb := Combat.deal(e, _hit(p, 10.0, R.FLINCH, Vector3.FORWARD, {"origin": Vector3(0, 1, 3)}))
	expect(rb == Combat.Result.HIT, "hit from behind lands")
	e.set_state(S.STRAFE)
	for i in 3:
		Combat.deal(e, _hit(p, 20.0, R.KNOCKBACK, Vector3.BACK, {"origin": Vector3(0, 1, -3), "poise": 40.0, "heavy": true, "element": E.EARTH}))
	expect(e.guard_broken_t > 0.0 and e.state == S.STAGGER and not e.shield_up(), "heavy earth hits break the guard")


func test_agile_enemy_dodges_slow_heavy_projectile() -> void:
	var p := _player(Vector3(0, 0, -12))
	var e := EnemySim.enemy(self, &"bandit_skirmisher", Vector3.ZERO, p, {"seed": 7})
	e.archetype = e.archetype.duplicate(true)
	e.archetype["dodge"]["chance"] = 1.0
	e.perception.alert_to(p)
	e.perception.engaged = true
	e.brain.target = p
	e.set_state(S.STRAFE)
	var ctx := p.get_bending_context()
	var proj := BendingProjectile.launch(ctx, Vector3(0, 1.1, -7), Vector3.BACK, 18.0, {"damage": 20.0, "reaction": R.KNOCKDOWN, "heavy": true,
			"poise": 50.0}, {"radius": 0.4, "range": 30.0})
	var dodged := await EnemySim.step_until([p, e], func() -> bool: return e.state == S.DODGE, 40)
	expect(dodged >= 0, "skirmisher dodged the slow heavy projectile")
	await EnemySim.step([p, e], 40)
	expect(e.health.health == e.health.max_health, "and took no damage")
	if is_instance_valid(proj) and proj.alive:
		proj.destroy(false)


func test_bending_enemy_casts_real_ability_and_parry_staggers() -> void:
	var p := _player(Vector3(0, 0, -8))
	p.health.invulnerable = true
	var e := EnemySim.enemy(self, &"fire_soldier", Vector3.ZERO, p)
	await EnemySim.settle(self)
	e.perception.alert_to(p)
	e.perception.engaged = true
	e.brain.target = p
	var jabs: Dictionary = e.attacks[0]
	var hits: Array = []
	var cb := func(hit: HitInfo, target: Node, _r: int) -> void:
		if target == p:
			hits.append(hit)
	Events.hit_landed.connect(cb)
	expect(e.actions.start(jabs, p), "fire jabs start")
	e.set_state(S.ATTACK)

	await EnemySim.step_until([p, e], func() -> bool: return not hits.is_empty(), 180)
	Events.hit_landed.disconnect(cb)
	expect(not hits.is_empty(), "the enemy's fire bolt reached the player")
	if not hits.is_empty():
		var h: HitInfo = hits[0]
		expect(h.ability_id == &"enemy_fire_combo" and h.team == Combat.Team.ENEMY and h.is_projectile, "same ability, enemy team, projectile")
		expect(h.element == E.FIRE and h.status.has("burn"), "fire element + burn")
	# Parry a brawler's swing: the attacker staggers.
	await EnemySim.step([p, e], 120)
	e.queue_free()
	# In front of the player (it faces -Z), just inside the swing's reach.
	p.teleport(Transform3D(Basis(), Vector3(0, 0, -8)))
	var b := EnemySim.enemy(self, &"bandit_brawler", Vector3(0, 0, -10.2), p)
	await EnemySim.settle(self)
	b.perception.alert_to(p)
	b.perception.engaged = true
	b.brain.target = p
	var swing: Dictionary = b.attacks[0]
	b.actions.start(swing, p)
	b.set_state(S.ATTACK)
	var parried := false
	for f in 180:
		await EnemySim.step([p, b], 1)
		if b.actions.phase == EnemyActions.Phase.ACTIVE and not bool(p.input.virtual.get(&"block", false)):
			p.input.press(&"block")
		# The parry staggers the attacker; Fire's counter burst may floor it outright.
		if b.state == S.STAGGER or b.state == S.KNOCKDOWN:
			parried = true
			break
	p.input.release(&"block")
	expect(parried, "parried strike staggers (or floors) the brawler")


func test_leash_return_heals() -> void:
	var p := _player(Vector3(0, 0, -6))
	var e := EnemySim.enemy(self, &"bandit_brawler", Vector3.ZERO, p, {"leash": 12.0})
	e.brain.engage(p)
	Combat.deal(e, _hit(p, 30.0, R.FLINCH, Vector3.BACK))
	var hurt := e.health.health
	p.teleport(Transform3D(Basis(), Vector3(0, 0, -60)))
	var f := await EnemySim.step_until([p, e], func() -> bool: return e.state == S.RETURN, 600)
	expect(f >= 0, "gives up beyond the leash")
	var f2 := await EnemySim.step_until([p, e], func() -> bool: return e.state in [S.IDLE, S.PATROL], 1200)
	expect(f2 >= 0, "back at the post")
	expect(e.health.health > hurt, "healed on the way back")
	expect(e.flat_distance(Vector3.ZERO) < 1.5, "at home")
	expect(AttackTokens.count(p) == 0, "no token kept")


func test_death_rewards_and_events() -> void:
	GameState.new_game(E.FIRE)
	var p := _player(Vector3(0, 0, -6))
	var e := EnemySim.enemy(self, &"bandit_brawler", Vector3.ZERO, p, {"seed": 3})
	var killed: Array = []
	var cb := func(en: Node3D, k: Node) -> void: killed.append([en, k])
	Events.enemy_killed.connect(cb)
	var xp0 := GameState.xp + GameState.level * 100000
	var cur0 := GameState.currency
	var r := Combat.deal(e, _hit(p, 9999.0, R.KNOCKBACK, Vector3.FORWARD, {"force": 6.0}))
	Events.enemy_killed.disconnect(cb)
	expect(r == Combat.Result.KILLED and e.state == S.DEAD, "killed")
	expect(killed.size() == 1 and killed[0][1] == p, "Events.enemy_killed with the killer")
	expect(GameState.xp + GameState.level * 100000 > xp0, "XP granted")
	expect(GameState.currency > cur0 or not GameState.inventory.is_empty(), "loot granted")
	expect(e.collision_layer == 0 and not e.is_alive(), "corpse does not block")
	expect(Combat.deal(e, _hit(p, 5.0, R.FLINCH, Vector3.FORWARD)) == Combat.Result.IGNORED, "dead ignores hits")
	var gone := [false]
	e.despawn_ready.connect(func(_e: EnemyBase) -> void: gone[0] = true)
	await EnemySim.step([p, e], 60 * 7)
	expect(gone[0], "despawn after the fade")
	GameState.reset()


func test_surrender_and_flee() -> void:
	var p := _player(Vector3(0, 0, -6))
	var s := EnemySim.enemy(self, &"bandit_brawler", Vector3(-3, 0, 0), p, {"low_health_mode": &"surrender"})
	var f := EnemySim.enemy(self, &"bandit_archer", Vector3(3, 0, 0), p, {"low_health_mode": &"flee"})
	s.brain.engage(p)
	f.brain.engage(p)
	Combat.deal(s, _hit(p, s.health.max_health * 0.85, R.FLINCH, Vector3.FORWARD))
	Combat.deal(f, _hit(p, f.health.max_health * 0.8, R.FLINCH, Vector3.FORWARD))
	expect(s.state == S.SURRENDER and s.surrendered and s.has_meta(&"no_lock"), "surrendered")
	expect(Combat.deal(s, _hit(p, 50.0, R.FLINCH, Vector3.FORWARD)) == Combat.Result.IGNORED, "surrendered enemies are spared")
	expect(f.state == S.FLEE, "archer flees")
	var how := [&""]
	f.defeated.connect(func(_e: EnemyBase, h: StringName) -> void: how[0] = h)
	await EnemySim.step([p, s, f], 60 * 9)
	expect(how[0] == &"fled", "fled out of sight")
	expect(not f.visible or f.visual.node().visible == false, "gone")


func test_captain_phase_change() -> void:
	var p := _player(Vector3(0, 0, -7))
	p.health.invulnerable = true
	var c := EnemySim.enemy(self, &"fire_captain", Vector3.ZERO, p)
	c.brain.engage(p)
	var n0 := c.attacks.size()
	Combat.deal(c, _hit(p, c.health.max_health * 0.7, R.FLINCH, Vector3.FORWARD))
	expect(c.phase_index == 1, "phase 2 at half health")
	expect(c.attacks.size() > n0, "new attacks unlocked")
	expect(c.state == S.ATTACK and c.actions.attack.get("id") == &"war_cry", "war cry burst")
	expect(c.telegraph_mult() < 1.0, "faster telegraphs in phase 2")
	await EnemySim.step([p, c], 120)
	expect(c.is_alive(), "still fighting")


# --- encounters -------------------------------------------------------------------------------------------

func test_encounter_sites_on_real_world() -> void:
	WorldData.use_flat_world(false)
	if not WorldData.has_world_data():
		return
	var sites := EncounterSites.build_all()
	expect(sites.size() >= 11, "sites built (%d)" % sites.size())
	var kinds := {}
	for s in sites:
		kinds[s.kind] = true
		print("    site %-26s %-8s %s yaw %.2f" % [s.id, s.kind, s.center.snapped(Vector3.ONE * 0.1), s.yaw])
		if s.kind == &"outpost" or s.kind == &"den":
			# Not astride a road, in a field or on town paving.
			for k in 12:
				var a := TAU * k / 12.0
				var q := s.center + Vector3(cos(a), 0, sin(a)) * s.radius
				expect(WorldData.get_road(q.x, q.z) <= 0.05, "%s: no road inside the camp" % s.id)
				var hints := WorldData.get_ground_hints(q.x, q.z)
				expect(hints.b < 0.15 and hints.g < 0.15, "%s: not in farmland / town" % s.id)
		expect(not s.members.is_empty(), "%s has members" % s.id)
		var c := s.center
		expect(WorldData.get_biome(c.x, c.z) != WorldData.Biome.OCEAN and WorldData.get_biome(c.x, c.z) != WorldData.Biome.CITY, "%s on land, outside cities" % s.id)
		expect(not WorldData.is_underwater(c + Vector3.UP * 0.5), "%s dry" % s.id)
		if s.kind == &"patrol":
			expect(s.route.size() >= 5, "%s route" % s.id)
			for q in s.route:
				expect(WorldData.get_road(q.x, q.z) > 0.05, "%s route on the road" % s.id)
				break
		for m in s.members:
			expect(EnemyArchetypes.has(m["archetype"]), "%s member %s" % [s.id, m["archetype"]])
	for k: StringName in [&"camp", &"outpost", &"patrol", &"den"]:
		expect(kinds.has(k), "site kind %s" % k)
	expect(sites.any(func(s: EncounterSite) -> bool: return s.id == &"ek_dustwind_camp"), "the raider camp POI is hostile")
	WorldData.use_flat_world(true)


func test_director_spawns_despawns_respawns_and_combat_state() -> void:
	GameState.new_game(E.EARTH)
	var p := _player(Vector3(0, 0, 0))
	p.health.invulnerable = true
	var d := EncounterDirector.new()
	d.use_world_sites = false
	add_child(d)
	d.setup(p)
	var site := EncounterSite.new()
	site.id = &"test_camp"
	site.display_name = "Test Camp"
	site.kind = &"camp"
	site.faction = &"bandits"
	site.center = Vector3(0, 0, -40)
	site.radius = 10.0
	site.respawn_time = 30.0
	site.add_member(&"bandit_brawler", Vector3(-2, 0, -40), 0.0, 1)
	site.add_member(&"bandit_archer", Vector3(2, 0, -40), 0.0, 2)
	d.sites.append(site)
	d.use_world_sites = true
	var combat_events: Array = []
	var cb := func(on: bool) -> void: combat_events.append(on)
	Events.combat_state_changed.connect(cb)
	await EnemySim.step([p, d], 40)
	expect(site.active and d.active_count() == 2, "site activated near the player")
	for e in d.enemies:
		e.set_physics_process(false)
	# Fight: engage -> combat on.
	for e in d.enemies:
		e.brain.engage(p)
	await EnemySim.step([p, d] + d.enemies, 90)
	expect(d.in_combat and combat_events.has(true), "combat state on")
	# Kill both -> cleared, flag saved, combat off after the delay.
	for e in d.enemies.duplicate():
		Combat.deal(e, _hit(p, 9999.0, R.FLINCH, Vector3.FORWARD))
	expect(site.is_cleared() and site.cleared_at >= 0.0, "site cleared")
	expect((GameState.world_flags.get(EncounterDirector.FLAG_KEY, {}) as Dictionary).has("test_camp"), "cleared flag saved")
	await EnemySim.step([p, d], 60 * 4)
	expect(not d.in_combat and not combat_events.is_empty() and combat_events.back() == false, "combat state off after the delay")
	# Far away + time passed -> respawn, then spawn again when close.
	p.teleport(Transform3D(Basis(), Vector3(0, 0, 400)))
	await EnemySim.step([p, d], 120)
	expect(not site.active, "deactivated far away")
	GameState.play_time += 31.0
	await EnemySim.step([p, d], 120)
	expect(site.alive_members() == 2, "respawned out of sight")
	p.teleport(Transform3D(Basis(), Vector3(0, 0, -20)))
	await EnemySim.step([p, d], 120)
	expect(site.active and d.active_count() == 2, "back when the player returns")
	Events.combat_state_changed.disconnect(cb)
	d.queue_free()
	GameState.reset()


func test_far_calm_enemies_go_dormant() -> void:
	var p := _player(Vector3(0, 0, 0))
	var d := EncounterDirector.new()
	d.use_world_sites = false
	add_child(d)
	d.setup(p)
	var near := d.spawn_enemy(&"bandit_brawler", Transform3D(Basis(), Vector3(0, 0, -20)))
	var far := d.spawn_enemy(&"bandit_brawler", Transform3D(Basis(), Vector3(0, 0, -90)))
	near.set_physics_process(false)
	far.set_physics_process(false)
	await EnemySim.step([p, d], 30)
	expect(far.dormant and not near.dormant, "far calm enemy dormant, near one awake")
	expect(Combat.deal(far, _hit(p, 5.0, R.FLINCH, Vector3.FORWARD)) == Combat.Result.IGNORED, "dormant enemies are out of play")
	d.queue_free()


# --- fairness -----------------------------------------------------------------------------------------------

func test_area_strike_is_guarded_by_attacker_position() -> void:
	# The overhead smash's sphere centre lies BEHIND a close player; the guard must still
	# judge the hit by where the brawler stands (in front) and block it.
	var p := _player(Vector3(0, 0, -1.2))
	p.rotation.y = PI   # face +Z, toward the enemy
	var e := EnemySim.enemy(self, &"bandit_brawler", Vector3(0, 0, 0.4), p)
	p.targeting.lock(e)
	await EnemySim.settle(self)
	e.perception.alert_to(p)
	e.perception.engaged = true
	e.brain.target = p
	var smash: Dictionary = {}
	for a: Dictionary in e.attacks:
		if a.get("id") == &"overhead_smash":
			smash = a
	var results: Array = []
	var cb := func(_h: HitInfo, t: Node, r: int) -> void:
		if t == p:
			results.append(r)
	Events.hit_landed.connect(cb)
	e.actions.start(smash, p)
	e.set_state(S.ATTACK)
	await EnemySim.step([p, e], 10)
	p.input.press(&"block")
	await EnemySim.step_until([p, e], func() -> bool: return not results.is_empty(), 180)
	p.input.release(&"block")
	Events.hit_landed.disconnect(cb)
	expect(not results.is_empty(), "the smash resolved on the player")
	if not results.is_empty():
		expect(int(results[0]) in [Combat.Result.BLOCKED, Combat.Result.DEFLECTED], "frontal smash blocked (%s)" % Combat.Result.keys()[int(results[0])])
	expect(p.get_state() != PlayerCharacter.State.KNOCKED_DOWN, "not knocked down through the guard")


func test_offscreen_enemies_circle_into_view_before_attacking() -> void:
	var p := _player(Vector3.ZERO)
	p.health.invulnerable = true
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.2, 4.5), Vector3(0, 1.0, -4.0), Vector3.UP)
	cam.make_current()
	var e := EnemySim.enemy(self, &"bandit_brawler", Vector3(0.5, 0, 5.5), p, {"seed": 21})
	e.brain.engage(p)
	expect(not e.brain.in_player_view(), "behind the camera = off-screen")
	var started := [false]
	var flank := [false]
	var seen_at_start := [false]
	var off_t := [0.0]
	e.attack_telegraphed.connect(func(_e: EnemyBase, _a: Dictionary, _s: float) -> void:
		if not started[0]:
			started[0] = true
			flank[0] = e.flanking
			seen_at_start[0] = e.brain.in_player_view())
	var frames := await EnemySim.step_until([p, e], func() -> bool:
		if not e.brain.in_player_view():
			off_t[0] += EnemySim.DT
		return started[0], 900)
	expect(frames >= 0, "it attacks eventually")
	expect(seen_at_start[0] or (flank[0] and off_t[0] >= EnemyBrain.FLANK_PATIENCE - 0.05),
			"attacked from view, or flanking only after %.1f s (seen %s flank %s off %.2f)" % [EnemyBrain.FLANK_PATIENCE, seen_at_start[0], flank[0], off_t[0]])
	if flank[0]:
		expect(e.telegraph_mult() > 1.2 or not e.actions.is_busy(), "flanking attacks telegraph longer")
	cam.queue_free()


func test_heavy_blasts_topple_light_fighters_not_brutes() -> void:
	var p := _player(Vector3(0, 0, 20))
	var archer := EnemySim.enemy(self, &"bandit_archer", Vector3(-4, 0, 0))
	var chief := EnemySim.enemy(self, &"earth_chief", Vector3(4, 0, 0))
	var blast := {"poise": 50.0, "heavy": true, "force": 14.0, "element": E.AIR}
	Combat.deal(archer, _hit(p, 8.0, R.KNOCKBACK, Vector3.LEFT, blast))
	Combat.deal(chief, _hit(p, 8.0, R.KNOCKBACK, Vector3.RIGHT, blast))
	expect(archer.state == S.KNOCKDOWN, "archer toppled (%s)" % archer.get_state_name())
	expect(chief.state != S.KNOCKDOWN, "chief stands (%s)" % chief.get_state_name())
	# A follow-up stagger on the floor keeps it down (no knockdown -> stagger downgrade).
	Combat.deal(archer, _hit(p, 2.0, R.STAGGER, Vector3.LEFT, {"poise": 30.0}))
	expect(archer.state == S.KNOCKDOWN, "still down after a stagger hit (%s)" % archer.get_state_name())


# --- budget ---------------------------------------------------------------------------------------------------

func test_cost_of_a_full_budget_fight() -> void:
	# The high-detail budget (15) all engaged around the player: AI + physics + animation
	# per physics frame on this machine (printed; bounded loosely against regressions).
	var p := _player(Vector3.ZERO)
	p.health.invulnerable = true
	var ids: Array[StringName] = [&"bandit_brawler", &"bandit_skirmisher", &"bandit_archer", &"fire_soldier", &"fire_shieldbearer"]
	var nodes: Array = [p]
	for i in 15:
		var a := TAU * i / 15.0
		var e := EnemySim.enemy(self, ids[i % ids.size()], Vector3(cos(a) * 10.0, 0, sin(a) * 10.0), p, {"seed": 900 + i})
		e.brain.engage(p)
		nodes.append(e)
	await EnemySim.step(nodes, 60)
	var t0 := Time.get_ticks_usec()
	await EnemySim.step(nodes, 180)
	var per_frame := float(Time.get_ticks_usec() - t0) / 180.0 / 1000.0
	print("    15 engaged enemies + player: %.2f ms per physics frame" % per_frame)
	expect(per_frame < 25.0, "15 engaged enemies cost %.2f ms per frame" % per_frame)


# --- robustness ---------------------------------------------------------------------------------------------

func test_no_stuck_states_fuzz() -> void:
	var p := _player(Vector3.ZERO)
	p.health.invulnerable = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var ids: Array[StringName] = [&"bandit_brawler", &"bandit_skirmisher", &"fire_shieldbearer", &"fire_soldier", &"earth_rogue",
		&"water_pirate", &"dai_li_agent", &"fire_captain", &"komodo_rhino", &"bandit_archer"]
	var nodes: Array = [p]
	for i in ids.size():
		var a := TAU * i / ids.size()
		var e := EnemySim.enemy(self, ids[i], Vector3(cos(a) * 9.0, 0, sin(a) * 9.0), p, {"seed": 300 + i})
		e.health.max_health = 99999.0
		e.health.health = 99999.0
		e.brain.engage(p)
		nodes.append(e)
	var longest := {}
	var reactions := [R.FLINCH, R.STAGGER, R.KNOCKBACK, R.KNOCKDOWN, R.LAUNCH, R.PULL, R.FREEZE]
	for f in 3000:
		await EnemySim.step(nodes, 1)
		if f % 7 == 0:
			var t: EnemyBase = nodes[1 + rng.randi() % ids.size()]
			var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
			Combat.deal(t, _hit(p, rng.randf_range(1, 12), reactions[rng.randi() % reactions.size()], dir,
					{"poise": rng.randf_range(5, 70), "force": rng.randf_range(0, 10), "lift": rng.randf_range(0, 6), "stun": rng.randf_range(0, 1.5),
					"heavy": rng.randf() < 0.3, "origin": t.global_position + dir * -2.0}))
		if f % 90 == 0:
			p.teleport(Transform3D(Basis(), Vector3(rng.randf_range(-10, 10), 0, rng.randf_range(-10, 10))))
		for n in nodes:
			if n is EnemyBase:
				var e := n as EnemyBase
				var key := "%s/%s" % [e.archetype_id, e.get_state_name()]
				longest[key] = maxf(float(longest.get(key, 0.0)), e.state_time)
				var cap: float = EnemyBase.STATE_TIMEOUT.get(e.state, INF)
				if e.state_time > cap + 0.5:
					fail("%s stuck in %s for %.1f s" % [e.archetype_id, e.get_state_name(), e.state_time])
				if not e.global_position.is_finite() or e.global_position.y < -5.0:
					fail("%s left the world" % e.archetype_id)
		expect(AttackTokens.count(p) <= AttackTokens.max_tokens(), "token cap")
	var stuck_strafe := false
	for k: String in longest:
		if (k.ends_with("/Stagger") or k.ends_with("/Knockdown")) and float(longest[k]) > 4.5:
			stuck_strafe = true
	expect(not stuck_strafe, "no reaction state lasted too long")
