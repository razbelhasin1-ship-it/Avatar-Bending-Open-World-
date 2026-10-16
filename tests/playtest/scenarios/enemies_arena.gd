extends RefCounted
## Arena duel per archetype with the real player (InputMap actions only):
##   telegraph (glint) -> the player defends (parry for melee / dodge for projectiles)
##   -> counter-attack -> stagger -> heavy hit knockdown -> get-up -> defeat.
## Screenshots: <arch>_1_telegraph, _2_defend, _3_counter, _4_down, _5_getup, _6_defeat.
## ARCH="bandit_brawler,fire_soldier" ELEMENT=earth (default: one of each role).
var p: Playtest
var arena: Node
var player: PlayerCharacter
var log_t0 := 0


func run(pt: Playtest) -> void:
	p = pt
	var el := ElementDefs.from_id(StringName(OS.get_environment("ELEMENT"))) if OS.get_environment("ELEMENT") != "" else ElementDefs.Element.FIRE
	GameState.new_game(el, true)
	arena = await p.load_scene("res://scenes/dev/enemy_arena.tscn", {"element": el, "spawn": false})
	player = arena.get("player")
	player.camera_rig.require_capture = false
	player.resources.infinite_chi = true
	var ids: Array = []
	for s in OS.get_environment("ARCH").split(",", false):
		ids.append(StringName(s.strip_edges()))
	if ids.is_empty():
		ids = [&"bandit_brawler", &"bandit_skirmisher", &"bandit_archer", &"fire_shieldbearer", &"fire_soldier", &"earth_rogue",
			&"dai_li_agent", &"water_pirate", &"fire_captain", &"komodo_rhino"]
	for id: StringName in ids:
		await duel(id)
	p.check(true, "duels finished")


func _log(s: String) -> void:
	print("[%6.2f] %s" % [float(Engine.get_physics_frames() - log_t0) / 60.0, s])


func duel(id: StringName) -> void:
	log_t0 = Engine.get_physics_frames()
	p.release_all()
	AttackTokens.reset()
	player.respawn_at(Transform3D(Basis(), Vector3(0, 0, 4)), 1.0)
	player.camera_rig.snap_behind(player)
	var group: Array = arena.call("spawn_group", [id], [Vector3(0, 0, -5.5)])
	var e: EnemyBase = group[0]
	e.low_health_mode = &""
	await p.wait_game(0.3)
	# Lock on and let the enemy notice us.
	p.hold(&"lock_on")
	await p.wait_game(0.1)
	p.release(&"lock_on")
	e.brain.engage(player)
	var ranged := e.role == &"ranged" or e.role == &"bender"
	# 1) Wait for a telegraph and capture the glint.
	var tele := [false]
	var tele_cb := func(_e: EnemyBase, a: Dictionary, s: float) -> void:
		if not tele[0]:
			tele[0] = true
			_log("%s telegraphs %s (%.2fs)" % [id, a.get("id"), s])
	e.attack_telegraphed.connect(tele_cb)
	await _until(func() -> bool: return tele[0] or not e.is_alive(), 12.0)
	await p.screenshot("%s_1_telegraph" % id)
	# 2) Defend: melee strikes are parried, projectiles / area attacks dodged sideways.
	var a: Dictionary = e.actions.attack
	var melee: bool = a.get("kind", &"") in [&"melee", &"beast"] or (a.get("kind", &"") == &"bending" and e.flat_distance_to(player) < 3.0)
	var results: Array = []
	var res_cb := func(hit: HitInfo, target: Node, r: int) -> void:
		if target == player:
			results.append(r)
	Events.hit_landed.connect(res_cb)
	if melee:
		await _until(func() -> bool: return e.actions.phase == EnemyActions.Phase.ACTIVE or not e.actions.is_busy(), 4.0)
		p.hold(&"block")
		await p.wait_game(0.12)
		await p.screenshot("%s_2_defend" % id)
		await p.wait_game(0.3)
		p.release(&"block")
	else:
		await _until(func() -> bool: return e.actions.windup_left() < 0.12 or not e.actions.is_busy(), 4.0)
		p.hold(&"move_left")
		await p.wait_game(0.05)
		p.hold(&"dodge")
		await p.wait_game(0.1)
		p.release(&"dodge")
		await p.wait_game(0.15)
		await p.screenshot("%s_2_defend" % id)
		p.release(&"move_left")
		await p.wait_game(0.4)
	Events.hit_landed.disconnect(res_cb)
	_log("%s defense results %s (player hp %.0f)" % [id, results.map(func(r: int) -> String: return Combat.Result.keys()[r]), player.health.health])
	# 3) Counter: close in and strike while it recovers.
	var hp0 := e.health.health
	await _approach(e, 2.4)
	for i in 3:
		await p.tap(&"attack_light")
		await p.wait_game(0.18)
		if i == 1:
			await p.screenshot("%s_3_counter" % id)
	_log("%s took %.0f from the counter, state %s" % [id, hp0 - e.health.health, e.get_state_name()])
	# 4) Knockdown with a heavy (charged) strike; 5) get-up.
	await _approach(e, 2.6)
	var downed := [false]
	var st_cb := func(n: int, _o: int) -> void:
		if n == EnemyBase.State.KNOCKDOWN:
			downed[0] = true
	e.state_changed.connect(st_cb)
	for attempt in 3:
		if downed[0] or not e.is_alive():
			break
		p.hold(&"attack_heavy")
		await p.wait_game(1.0)
		p.release(&"attack_heavy")
		await _until(func() -> bool: return downed[0], 1.2)
		if not downed[0]:
			# Heavy fighters shrug a single heavy off: force the down for the shot sequence.
			Combat.deal(e, _down_hit(e))
	await p.wait_game(0.25)
	await p.screenshot("%s_4_down" % id)
	await _until(func() -> bool: return e.state == EnemyBase.State.GETUP or not e.is_alive(), 4.0)
	await p.wait_game(0.2)
	await p.screenshot("%s_5_getup" % id)
	_log("%s down + getup seen: %s" % [id, downed[0]])
	p.check(downed[0], "%s was knocked down" % id)
	# 6) Defeat: finish it with combos.
	e.health.health = minf(e.health.health, e.health.max_health * 0.15)
	await _until(func() -> bool: return e.state in [EnemyBase.State.STRAFE, EnemyBase.State.CHASE, EnemyBase.State.ATTACK] or not e.is_alive(), 3.0)
	var t := 0.0
	while e.is_alive() and t < 10.0:
		await _approach(e, 2.4)
		await p.tap(&"attack_light")
		await p.wait_game(0.15)
		t += 0.4
	await p.wait_game(0.5)
	await p.screenshot("%s_6_defeat" % id)
	p.check(not e.is_alive(), "%s defeated" % id)
	_log("%s defeated: %s, player hp %.0f" % [id, not e.is_alive(), player.health.health])
	p.release_all()
	await p.wait_game(0.3)


func _down_hit(e: EnemyBase) -> HitInfo:
	var h := HitInfo.make(4.0, player, ElementDefs.Element.EARTH, HitInfo.Reaction.KNOCKDOWN, e.global_position - player.global_position, 6.0)
	h.poise_damage = 200.0
	h.stun_time = 1.2
	h.is_heavy = true
	return h


## Walks toward the enemy until within `dist` (camera-relative move_forward while locked on).
func _approach(e: EnemyBase, dist: float) -> void:
	var t := 0.0
	while is_instance_valid(e) and e.is_alive() and e.flat_distance_to(player) > dist and t < 3.0:
		player.camera_rig.snap_behind(player)
		var to := e.global_position - player.global_position
		to.y = 0.0
		player.rotation.y = atan2(-to.x, -to.z)
		player.camera_rig.snap_behind(player)
		p.hold(&"move_forward")
		await p.wait_game(0.1)
		t += 0.1
	p.release(&"move_forward")


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await p.wait_game(1.0 / 60.0)
		t += 1.0 / 60.0
	return false
