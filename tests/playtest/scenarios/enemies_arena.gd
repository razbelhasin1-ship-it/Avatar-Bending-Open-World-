extends RefCounted
## Arena duels with the real player, driven only through InputMap actions (GAME_DESIGN §5).
## One duel per archetype, each with the player element that suits the matchup:
##   1 telegraph   the enemy winds up (glint on the weapon / hand, ground ring, charge)
##   2 defend      parry melee (block on the strike), dodge or guard projectiles / areas
##   3 counter     light combo while it recovers (or reels from the parry)
##   4 down        a charged heavy knocks it off its feet (boulder / toppling blast)
##   5 get-up      it rises (i-frames) and re-engages
##   6 defeat      health cut to 20 % first (time saver), then finished with light strikes
## Screenshots <arch>_<n>_<step> come from an observer camera framing both fighters;
## <arch>_0_view is the player's own camera at the telegraph. A fairness report is
## printed per duel (telegraph lead before the strike, defense result, recovery window,
## damage taken / dealt). ARCH="a,b" picks duels, ELEMENT=fire forces the player element.

const E := ElementDefs.Element
const S := EnemyBase.State
## Player element per archetype (interesting matchups, natural knockdowns).
const MATCHUPS := {
	&"bandit_brawler": E.FIRE, &"bandit_skirmisher": E.AIR, &"bandit_archer": E.WATER, &"fire_shieldbearer": E.EARTH,
	&"fire_soldier": E.WATER, &"fire_archer": E.AIR, &"earth_rogue": E.AIR, &"dai_li_agent": E.FIRE, &"water_pirate": E.EARTH,
	&"pirate_cutlass": E.FIRE, &"pirate_archer": E.EARTH, &"fire_captain": E.EARTH, &"earth_chief": E.EARTH, &"komodo_rhino": E.EARTH,
}
const DEFAULT := [&"bandit_brawler", &"bandit_skirmisher", &"bandit_archer", &"fire_shieldbearer", &"fire_soldier", &"earth_rogue",
	&"dai_li_agent", &"water_pirate", &"fire_captain", &"earth_chief", &"komodo_rhino"]
const DT := 1.0 / 60.0

var p: Playtest
var arena: Node
var player: PlayerCharacter
var cam: Camera3D
var log_t0 := 0
var report: Array[String] = []
var _hits_on_player: Array = []
var _hits_on_enemy: Array = []
var _tele: Array = []
var _strikes: Array = []


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(E.FIRE, true)
	arena = await p.load_scene("res://scenes/dev/enemy_arena.tscn", {"element": E.FIRE, "spawn": false})
	player = arena.get("player")
	player.camera_rig.require_capture = false
	player.resources.infinite_chi = true
	cam = Camera3D.new()
	cam.name = "ObserverCamera"
	cam.fov = 52.0
	arena.add_child(cam)
	Events.hit_landed.connect(_on_hit)
	var ids: Array = []
	for s in OS.get_environment("ARCH").split(",", false):
		ids.append(StringName(s.strip_edges()))
	if ids.is_empty():
		ids = DEFAULT
	for id: StringName in ids:
		await duel(id)
	print("\n==== FAIRNESS REPORT ====")
	for l in report:
		print(l)
	p.check(true, "duels finished")


func _log(s: String) -> void:
	print("[%6.2f] %s" % [float(Engine.get_physics_frames() - log_t0) / 60.0, s])


func _now() -> float:
	return float(Engine.get_physics_frames() - log_t0) / 60.0


func _on_hit(hit: HitInfo, target: Node, r: int) -> void:
	if target == player:
		_hits_on_player.append({"t": _now(), "r": r, "id": hit.ability_id, "dmg": hit.damage})
		_log("    player hit by %s: %s %.1f dmg %s (player %s)" % [hit.ability_id, Combat.Result.keys()[r], hit.damage,
				HitInfo.Reaction.keys()[hit.reaction], player.get_state_name()])
	elif target is EnemyBase:
		_hits_on_enemy.append({"t": _now(), "r": r, "id": hit.ability_id, "dmg": hit.damage, "e": target})


# --- one duel ---------------------------------------------------------------------------------------------

func duel(id: StringName) -> void:
	log_t0 = Engine.get_physics_frames()
	p.release_all()
	AttackTokens.reset()
	var el: int = MATCHUPS.get(id, E.FIRE)
	if OS.get_environment("ELEMENT") != "":
		el = ElementDefs.from_id(StringName(OS.get_environment("ELEMENT")))
	GameState.element = el
	player.set_element(el)
	player.resources.infinite_chi = true
	player.respawn_at(Transform3D(Basis(), Vector3(0, 0, 4)), 1.0)
	player.camera_rig.snap_behind(player)
	var group: Array = arena.call("spawn_group", [id], [Vector3(0, 0, -3.5)])
	var e: EnemyBase = group[0]
	e.low_health_mode = &""
	_hits_on_player.clear()
	_hits_on_enemy.clear()
	_tele.clear()
	_strikes.clear()
	e.attack_telegraphed.connect(func(_e: EnemyBase, a: Dictionary, s: float) -> void:
		_tele.append({"t": _now(), "id": a.get("id"), "s": s}))
	e.attack_struck.connect(func(_e: EnemyBase, a: Dictionary) -> void:
		_strikes.append({"t": _now(), "id": a.get("id")}))
	e.state_changed.connect(func(n: int, o: int) -> void:
		_log("  %s %s -> %s" % [id, EnemyBase.STATE_NAMES[o], EnemyBase.STATE_NAMES[n]]))
	_log("=== %s vs %s player" % [id, ElementDefs.id_of(el)])
	await p.wait_game(0.3)
	await _lock(e)
	e.brain.engage(player)
	var hp_start := player.health.health

	# 1) Telegraph -----------------------------------------------------------------------------------------
	var t_wait := 0.0
	while _tele.is_empty() and e.is_alive() and t_wait < 14.0:
		_face(e)
		await p.wait_game(DT)
		t_wait += DT
	p.check(not _tele.is_empty(), "%s telegraphed an attack" % id)
	var a: Dictionary = e.actions.attack
	_log("%s telegraphs %s (%.2fs to the strike phase), dist %.1f m" % [id, a.get("id"), float(_tele[0]["s"]) if not _tele.is_empty() else -1.0,
			e.flat_distance_to(player)])
	await p.screenshot("%s_0_view" % id)
	await _shot("%s_1_telegraph" % id, e, 0.62)

	# 2) Defend ---------------------------------------------------------------------------------------------
	var plan := _plan(e, a, el)
	var n_before := _hits_on_player.size()
	_log("%s defense plan: %s" % [id, plan])
	var defended := await _defend(e, a, plan, id)
	var res_names: Array = []
	for i in range(n_before, _hits_on_player.size()):
		res_names.append(Combat.Result.keys()[int(_hits_on_player[i]["r"])])
	var lead := -1.0
	if not _tele.is_empty() and not _strikes.is_empty():
		lead = float(_strikes[0]["t"]) - float(_tele[0]["t"])
	_log("%s defense: %s -> %s, telegraph lead %.2fs" % [id, plan, res_names, lead])

	# 3) Counter --------------------------------------------------------------------------------------------
	var hp0 := e.health.health
	var n_hits := _hits_on_enemy.size()
	var counter_state := ""
	var shot_taken := false
	for k in 6:
		if not e.is_alive():
			break
		await _approach(e, 3.2 if el != E.WATER else 3.6)
		await p.tap(&"attack_light")
		for w in 14:
			await p.wait_game(DT)
			if not shot_taken and _hits_on_enemy.size() > n_hits:
				shot_taken = true
				counter_state = e.get_state_name()
				await _shot("%s_3_counter" % id, e, 0.5)
		if k >= 2 and hp0 - e.health.health > 0.0:
			break
	if not shot_taken:
		await _shot("%s_3_counter" % id, e, 0.5)
	var dealt := hp0 - e.health.health
	_log("%s counter: %.0f damage, state at first hit %s" % [id, dealt, counter_state])
	p.check(dealt > 0.0, "%s took damage from the counter" % id)

	# 4) Knockdown with a charged heavy ---------------------------------------------------------------------
	var downed := [false]
	var down_cb := func(n: int, _o: int) -> void:
		if n == S.KNOCKDOWN:
			downed[0] = true
	e.state_changed.connect(down_cb)
	# Keep it standing for the knockdown + get-up beats (the counter may have nearly killed it).
	e.health.health = maxf(e.health.health, e.health.max_health * 0.8)
	for attempt in 6:
		if downed[0] or not e.is_alive():
			break
		await _wait_ready(e)
		await _approach(e, 4.0 if el != E.EARTH else 5.0)
		_face(e)
		var nh := _hits_on_enemy.size()
		p.hold(&"attack_heavy")
		for w in 87:   # a full charge (tap 0.2 s + charge 1.0-1.2 s)
			_face(e)
			await p.wait_game(DT)
		p.release(&"attack_heavy")
		var t := 0.0
		while not downed[0] and t < 1.6:
			await p.wait_game(DT)
			t += DT
		var hs: Array = []
		for i in range(nh, _hits_on_enemy.size()):
			hs.append("%s:%s" % [_hits_on_enemy[i]["id"], Combat.Result.keys()[int(_hits_on_enemy[i]["r"])]])
		_log("%s heavy attempt %d: down=%s state=%s hits=%s" % [id, attempt + 1, downed[0], e.get_state_name(), hs])
		if not downed[0] and hs.is_empty():
			# Missed / blocked by cover: circle for a new angle.
			p.hold(&"move_left")
			await p.wait_game(0.7)
			p.release(&"move_left")
	p.check(downed[0], "%s was knocked down by a charged heavy (%s)" % [id, ElementDefs.id_of(el)])
	if downed[0]:
		var t2 := 0.0
		while e.state == S.KNOCKDOWN and e.state_time < 0.55 and t2 < 2.0:
			await p.wait_game(DT)
			t2 += DT
		await _shot("%s_4_down" % id, e, 0.55)
		# 5) Get-up
		var t3 := 0.0
		while e.state != S.GETUP and e.is_alive() and t3 < 4.0:
			await p.wait_game(DT)
			t3 += DT
		var saw_getup := e.state == S.GETUP
		await p.wait_game(0.15)
		await _shot("%s_5_getup" % id, e, 0.55)
		var r_iframe := e.state == S.GETUP
		p.check(saw_getup, "%s got up" % id)
		var t4 := 0.0
		while e.state in [S.GETUP, S.KNOCKDOWN] and t4 < 3.0:
			await p.wait_game(DT)
			t4 += DT
		p.check(e.state in [S.STRAFE, S.CHASE, S.ATTACK, S.BLOCK, S.DODGE], "%s re-engaged after the get-up (%s)" % [id, e.get_state_name()])
		_log("%s get-up seen %s (i-frames during it: %s)" % [id, saw_getup, r_iframe])

	# 6) Defeat --------------------------------------------------------------------------------------------
	e.health.health = minf(e.health.health, e.health.max_health * 0.2)
	var t5 := 0.0
	while e.is_alive() and t5 < 14.0:
		await _approach(e, 3.0)
		await p.tap(&"attack_light")
		await p.wait_game(0.2)
		t5 += 0.4
	await p.wait_game(0.9)
	await _shot("%s_6_defeat" % id, e, 0.6)
	p.check(not e.is_alive(), "%s defeated" % id)
	var taken := hp_start - player.health.health
	var rec := float(a.get("recover", 0.4)) * e.recover_mult()
	report.append("%-18s vs %-5s | %-14s tele %.2fs lead %.2fs ring %s | defend %-9s -> %-22s | recover %.2fs | counter %3.0f dmg | down %s | player -%.0f hp" % [
			id, ElementDefs.id_of(el), a.get("id"), float(_tele[0]["s"]) if not _tele.is_empty() else -1.0, lead, float(a.get("ring", 0.0)) > 0.0,
			plan, str(res_names), rec, dealt, downed[0], taken])
	_log("%s defeated: %s, player hp %.0f" % [id, not e.is_alive(), player.health.health])
	p.release_all()
	if is_instance_valid(e) and e.state_changed.is_connected(down_cb):
		e.state_changed.disconnect(down_cb)
	await p.wait_game(0.3)


# --- defense ----------------------------------------------------------------------------------------------

## parry (melee), dodge_proj (projectiles), dodge_side (charges), dodge_out (areas), guard (hold the defense).
func _plan(e: EnemyBase, a: Dictionary, el: int) -> StringName:
	var kind: StringName = a.get("kind", &"melee")
	if kind == &"charge":
		return &"dodge_side"
	if float(a.get("ring", 0.0)) >= 2.5 or bool(a.get("leap", false)):
		return &"guard" if el == E.EARTH else &"dodge_out"
	if kind in [&"melee", &"beast", &"slam"]:
		return &"parry"
	if kind == &"bending":
		var b: Dictionary = a.get("bending", {})
		if e.flat_distance_to(player) < 4.0 and b.get("slot", &"") == &"light":
			return &"parry"
	return &"guard" if el == E.EARTH else &"dodge_proj"


func _defend(e: EnemyBase, a: Dictionary, plan: StringName, id: StringName) -> bool:
	var n0 := _hits_on_player.size()
	match plan:
		&"parry":
			# Block so the strike lands inside the 0.15 s parry window.
			var t := 0.0
			while t < 4.0 and e.actions.is_busy():
				_face(e)
				var act := e.actions
				if a.get("kind", &"") == &"bending":
					if act.windup_left() <= 0.02 or act.phase != EnemyActions.Phase.WINDUP:
						break
				elif act.phase == EnemyActions.Phase.ACTIVE and act.phase_t >= act._strike_at - 0.19:
					break
				elif act.phase == EnemyActions.Phase.RECOVER:
					break
				await p.wait_game(DT)
				t += DT
			p.hold(&"block")
			await _shot_on_result("%s_2_defend" % id, e, n0, 0.7)
			await p.wait_game(0.2)
			p.release(&"block")
		&"guard":
			var t := 0.0
			while t < 4.0 and e.actions.is_busy() and e.actions.windup_left() > 0.12:
				_face(e)
				await p.wait_game(DT)
				t += DT
			p.hold(&"block")
			await _shot_on_result("%s_2_defend" % id, e, n0, 1.4)
			await p.wait_game(0.3)
			p.release(&"block")
		&"dodge_proj":
			# Wait for the projectile in flight, then dodge across its path.
			var t := 0.0
			var proj: BendingProjectile = null
			while t < 4.0:
				_face(e)
				for pr in BendingProjectile.incoming(player.global_position + Vector3.UP, 16.0, Combat.Team.PLAYER):
					var tti := pr.global_position.distance_to(player.global_position + Vector3.UP) / maxf(pr.velocity.length(), 1.0)
					if tti < 0.3:
						proj = pr
				if proj != null or (not e.actions.is_busy() and t > 0.5):
					break
				await p.wait_game(DT)
				t += DT
			await _dodge_side(e)
			await _shot_on_result("%s_2_defend" % id, e, n0, 0.25)
		&"dodge_side", &"dodge_out":
			var t := 0.0
			while t < 4.0 and e.actions.is_busy():
				var act := e.actions
				if plan == &"dodge_side" and act.phase == EnemyActions.Phase.ACTIVE and e.flat_distance_to(player) < 5.5:
					break
				if plan == &"dodge_out" and act.windup_left() <= 0.16:
					break
				await p.wait_game(DT)
				t += DT
			if plan == &"dodge_out":
				await _dodge_dir(&"move_back", e)
			else:
				await _dodge_side(e)
			await _shot_on_result("%s_2_defend" % id, e, n0, 0.35)
	return true


## Takes the defend shot right when the attack resolves on the player (or after `timeout`).
func _shot_on_result(name: String, e: EnemyBase, n0: int, timeout: float) -> void:
	var t := 0.0
	while t < timeout and _hits_on_player.size() <= n0:
		_face(e)
		await p.wait_game(DT)
		t += DT
	await _shot(name, e, 0.5)


func _dodge_side(e: EnemyBase) -> void:
	await _dodge_dir(&"move_left", e)


func _dodge_dir(dir_action: StringName, e: EnemyBase) -> void:
	_face(e)
	p.hold(dir_action)
	await p.wait_game(2 * DT)
	await p.tap(&"dodge", 0.05)
	await p.wait_game(0.12)
	p.release(dir_action)


# --- helpers ----------------------------------------------------------------------------------------------

func _lock(e: EnemyBase) -> void:
	_face(e)
	await p.tap(&"lock_on")
	if player.get_lock_target() != e:
		player.targeting.lock(e)


## Turns the player (and its camera) toward the enemy, as a player steering with the
## stick and camera would.
func _face(e: EnemyBase) -> void:
	if not is_instance_valid(e):
		return
	var to := e.global_position - player.global_position
	to.y = 0.0
	if to.length_squared() < 0.01:
		return
	player.rotation.y = atan2(-to.x, -to.z)
	if player.get_lock_target() == null:
		player.camera_rig.snap_behind(player)


## Walks toward the enemy until within `dist` (move_forward with the camera behind).
func _approach(e: EnemyBase, dist: float) -> void:
	var t := 0.0
	while is_instance_valid(e) and e.is_alive() and e.flat_distance_to(player) > dist and t < 3.0:
		_face(e)
		player.camera_rig.snap_behind(player)
		p.hold(&"move_forward")
		await p.wait_game(0.1)
		t += 0.1
	p.release(&"move_forward")
	# Too close for a charged heavy: step back a little.
	if is_instance_valid(e) and e.is_alive() and e.flat_distance_to(player) < dist - 2.0:
		p.hold(&"move_back")
		await p.wait_game(0.25)
		p.release(&"move_back")


## Waits until the enemy is not mid-attack (so the heavy is not traded into a strike).
func _wait_ready(e: EnemyBase) -> void:
	var t := 0.0
	while is_instance_valid(e) and e.is_alive() and e.actions.is_busy() and not e.actions.in_recover() and t < 3.0:
		_face(e)
		await p.wait_game(DT)
		t += DT


func _clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD | Layers.CONSTRUCT)
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Observer shot: a 3/4 side view framing both fighters (`bias` toward the enemy).
func _shot(name: String, e: EnemyBase, bias: float) -> void:
	if not is_instance_valid(e):
		await p.screenshot(name)
		return
	var a := player.global_position
	var b := e.global_position
	var d := b - a
	d.y = 0.0
	var sep := maxf(d.length(), 1.5)
	var fwd := d / sep
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var mid := a.lerp(b, bias) + Vector3.UP * 1.0
	var dist := 3.4 + sep * 0.8
	# First candidate with a clear view of both fighters (arena pillars / walls).
	var pos := mid + side * dist * 0.82 - fwd * dist * 0.5 + Vector3.UP * (1.2 + sep * 0.1)
	for c: Array in [[1.0, 0.5], [-1.0, 0.5], [1.0, -0.2], [-1.0, -0.2], [0.6, 0.9], [-0.6, 0.9]]:
		var q := mid + side * dist * 0.82 * float(c[0]) - fwd * dist * float(c[1]) + Vector3.UP * (1.2 + sep * 0.1)
		if _clear(q, a + Vector3.UP * 1.1) and _clear(q, b + Vector3.UP * 1.1):
			pos = q
			break
	cam.look_at_from_position(pos, mid, Vector3.UP)
	cam.make_current()
	await p.screenshot(name)
	player.camera_rig.make_current()
