extends RefCounted
## A real encounter in the open world (world.tscn, streamed terrain + WorldContent): the
## Fire Nation Scout Camp outpost ~0.9 km from the Earth Kingdom home spawn. The player
## arrives on foot 70 m from the gate and walks in (InputMap actions only):
##   1 approach   the outpost (EncounterProvider structure) with its garrison at rest
##   2 spotted    awareness builds, "!" marks + barks, allies called, combat music state
##   3 fight      group combat: at most 2 attack tokens, the rest circle and pressure;
##                the player blocks wind-ups it sees coming and fights back with combos /
##                heavies (invulnerable so the scripted fighter survives the whole camp)
##   4 cleared    every member defeated -> XP + loot toasts, "cleared" bonus, saved flag,
##                combat state off
## SITE=<encounter site id> ELEMENT=<element> override the defaults.

const E := ElementDefs.Element
const DT := 1.0 / 60.0

var p: Playtest
var w: WorldScene
var pl: PlayerCharacter
var cam: Camera3D
var director: EncounterDirector
var site: EncounterSite


func run(pt: Playtest) -> void:
	p = pt
	var site_id := StringName(OS.get_environment("SITE")) if OS.get_environment("SITE") != "" else &"ek_fire_scout_camp"
	var el := ElementDefs.from_id(StringName(OS.get_environment("ELEMENT"))) if OS.get_environment("ELEMENT") != "" else E.EARTH
	GameState.new_game(el)
	GameState.intro_done = true
	GameState.time_of_day = 15.6
	# Sites are deterministic data: find where this one stands before loading the world.
	var info: EncounterSite = null
	for s in EncounterSites.build_all():
		if s.id == site_id:
			info = s
	if not p.check(info != null, "site %s exists" % site_id):
		return
	# Start 65 m out on the gate side, on the most level spot (not on a hillside).
	var gate := Basis(Vector3.UP, info.yaw) * Vector3.FORWARD
	var start := info.center + gate * 65.0
	var best := INF
	for deg: float in [0.0, 15.0, -15.0, 30.0, -30.0, 45.0, -45.0]:
		var q := info.center + gate.rotated(Vector3.UP, deg_to_rad(deg)) * 65.0
		var h0 := WorldData.get_height(q.x, q.z)
		var spread := 0.0
		for k in 6:
			var a := TAU * k / 6.0
			spread = maxf(spread, absf(WorldData.get_height(q.x + 4.0 * cos(a), q.z + 4.0 * sin(a)) - h0))
		if spread < best - 0.2:
			best = spread
			start = q
	start.y = WorldData.get_height(start.x, start.z)
	var to := info.center - start
	var spawn := Transform3D(Basis(Vector3.UP, atan2(-to.x, -to.z)), start + Vector3.UP * 0.3)
	var home := WorldData.get_spawn(el)
	print("[camp] %s at %s, %.0f m from the %s home spawn" % [site_id, info.center, Vector2(info.center.x - home.origin.x, info.center.z - home.origin.z).length(),
			ElementDefs.id_of(el)])
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": false, "spawn": spawn}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.playing, 240.0)
	p.check(ok, "world ready %s" % str(w.load_report))
	pl = w.player
	pl.camera_rig.require_capture = false
	pl.resources.infinite_chi = true
	pl.health.invulnerable = true
	pl.camera_rig.pitch = deg_to_rad(6.0)
	cam = Camera3D.new()
	cam.fov = 50.0
	w.add_child(cam)
	director = EncounterDirector.instance()
	if not p.check(director != null, "encounter director installed by the world hook"):
		return
	site = director.get_site(site_id)
	ok = await p.wait_until(func() -> bool: return site != null and site.active and _members().size() == site.members.size(), 30.0)
	p.check(ok, "site activated near the player (%d members)" % (_members().size()))
	var xp0 := GameState.xp + 100000 * GameState.level
	var cur0 := GameState.currency
	var items0 := GameState.inventory.size()
	var combat_events: Array = []
	Events.combat_state_changed.connect(func(on: bool) -> void: combat_events.append(on))
	var alerted: Array = []
	Events.enemy_alerted.connect(func(e: Node3D) -> void: alerted.append(e))
	var toasts: Array = []
	Events.notify.connect(func(text: String, _k: StringName) -> void: toasts.append(text))
	# Let the "Region Discovered" card pass.
	await p.wait_game(5.0)
	await p.screenshot("camp_1_approach_view")
	await _overview("camp_1_approach")
	for e in _members():
		p.check(e.state in [EnemyBase.State.IDLE, EnemyBase.State.PATROL], "%s at rest before the player arrives (%s)" % [e.display_name, e.get_state_name()])

	# 2) Walk in until spotted.
	var t := 0.0
	pl.camera_rig.snap_behind(pl)
	while alerted.is_empty() and t < 40.0:
		_face_point(info.center)
		p.hold(&"move_forward")
		await p.wait_game(0.1)
		t += 0.1
	p.release(&"move_forward")
	p.check(not alerted.is_empty(), "spotted on the way in (%.1f s, %.0f m from the centre)" % [t, _flat(pl.global_position, site.center)])
	await p.wait_game(0.25)
	await p.screenshot("camp_2_spotted_view")
	await _group_shot("camp_2_spotted")
	ok = await p.wait_until(func() -> bool: return director.in_combat, 8.0)
	p.check(ok and combat_events.has(true), "combat state on (music)")
	ok = await p.wait_until(func() -> bool:
		var n := 0
		for e in _members():
			if e.perception.engaged:
				n += 1
		return n >= mini(3, _members().size()), 6.0)
	p.check(ok, "the garrison answered the call")

	# 3) Fight.
	var max_tokens := 0
	var max_attacking := 0
	var circling_seen := 0
	var shots := {"melee": false, "tokens": false}
	var blocks := 0
	t = 0.0
	while _alive().size() > 0 and t < 75.0:
		if t > 30.0:
			# Time saver after half a minute of real fighting: finish the camp quicker.
			for e in _alive():
				e.health.health = minf(e.health.health, e.health.max_health * 0.3)
		var tgt := _pick_target()
		if tgt == null:
			await p.wait_game(0.1)
			t += 0.1
			continue
		var attacking := 0
		var circling := 0
		for e in _alive():
			if e.state == EnemyBase.State.ATTACK:
				attacking += 1
			elif e.state == EnemyBase.State.STRAFE:
				circling += 1
		max_attacking = maxi(max_attacking, attacking)
		max_tokens = maxi(max_tokens, AttackTokens.count(pl))
		circling_seen = maxi(circling_seen, circling)
		if not shots["tokens"] and attacking >= 1 and circling >= 2:
			shots["tokens"] = true
			await _group_shot("camp_4_pressure")
		var threat := _incoming_melee()
		if threat != null:
			_face_point(threat.global_position)
			p.hold(&"block")
			blocks += 1
			await p.wait_game(0.45)
			p.release(&"block")
			t += 0.45
			continue
		var d := _flat(pl.global_position, tgt.global_position)
		if d > 5.0:
			_face_point(tgt.global_position)
			p.hold(&"move_forward")
			await p.wait_game(0.15)
			p.release(&"move_forward")
			t += 0.15
			continue
		_face_point(tgt.global_position)
		if int(t * 2.0) % 7 == 3:
			p.hold(&"attack_heavy")
			await p.wait_game(0.8)
			p.release(&"attack_heavy")
			t += 0.8
		else:
			await p.tap(&"attack_light")
			await p.wait_game(0.2)
			t += 0.25
		if not shots["melee"] and t > 4.0:
			shots["melee"] = true
			await _group_shot("camp_3_fight")
	p.release_all()
	print("[camp] fight %.1f s: max tokens %d, max attacking %d, max circling %d, blocks %d" % [t, max_tokens, max_attacking, circling_seen, blocks])
	p.check(max_tokens <= AttackTokens.max_tokens() and max_attacking <= AttackTokens.max_tokens(), "never more than %d attackers (%d)" % [AttackTokens.max_tokens(), max_attacking])
	p.check(circling_seen >= 1, "others circled while two attacked")
	p.check(_alive().is_empty(), "the camp was defeated")

	# 4) Cleared.
	await p.wait_game(1.2)
	await p.screenshot("camp_5_cleared_view")
	await _overview("camp_5_cleared")
	p.check(site.is_cleared() and (GameState.world_flags.get(EncounterDirector.FLAG_KEY, {}) as Dictionary).has(String(site_id)), "cleared flag saved")
	p.check(GameState.xp + 100000 * GameState.level > xp0, "XP granted")
	p.check(GameState.currency > cur0 or GameState.inventory.size() > items0, "loot granted (currency %d -> %d)" % [cur0, GameState.currency])
	p.check(toasts.any(func(s: String) -> bool: return s.contains("cleared")), "cleared toast %s" % str(toasts.slice(maxi(0, toasts.size() - 3))))
	ok = await p.wait_until(func() -> bool: return not director.in_combat, 10.0)
	p.check(ok and combat_events.back() == false, "combat state off after the fight")
	print("[camp] stats %s" % str(director.get_stats()))


func _members() -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	if site == null:
		return out
	for m in site.members:
		var e: EnemyBase = m["node"]
		if e != null and is_instance_valid(e):
			out.append(e)
	return out


func _alive() -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	for e in _members():
		if e.is_alive() and not e.surrendered:
			out.append(e)
	return out


func _pick_target() -> EnemyBase:
	var cur := pl.get_lock_target() as EnemyBase
	if cur != null and cur.is_alive() and not cur.surrendered:
		return cur
	var best: EnemyBase = null
	var bd := INF
	for e in _alive():
		var d := _flat(pl.global_position, e.global_position)
		if d < bd:
			bd = d
			best = e
	if best != null:
		pl.targeting.lock(best)
	return best


## An enemy close by about to strike (the scripted fighter reads telegraphs like a player).
func _incoming_melee() -> EnemyBase:
	for e in _alive():
		if e.actions.in_windup() and e.actions.windup_left() < 0.2 and _flat(pl.global_position, e.global_position) < 5.0:
			return e
	return null


func _face_point(q: Vector3) -> void:
	var to := q - pl.global_position
	to.y = 0.0
	if to.length_squared() > 0.01:
		pl.rotation.y = atan2(-to.x, -to.z)
		pl.camera_rig.snap_behind(pl)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Elevated establishing shot of the site with the player at the edge of the frame.
func _overview(name: String) -> void:
	var c := site.center + Vector3.UP * 1.5
	var dir := pl.global_position - site.center
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.01 else Vector3.BACK
	var side := Vector3(-dir.z, 0, dir.x)
	var pos := site.center + dir * 21.0 + side * 9.0 + Vector3.UP * 15.0
	pos.y = maxf(pos.y, WorldData.get_height(pos.x, pos.z) + 12.0)
	cam.look_at_from_position(pos, c, Vector3.UP)
	cam.make_current()
	await p.screenshot(name)
	pl.camera_rig.make_current()


## Observer shot framing the player and the engaged enemies.
func _group_shot(name: String) -> void:
	var pts: Array[Vector3] = [pl.global_position]
	for e in _alive():
		if e.perception.engaged and _flat(e.global_position, pl.global_position) < 11.0:
			pts.append(e.global_position)
	var c := Vector3.ZERO
	for q in pts:
		c += q
	c /= float(pts.size())
	var r := 3.0
	for q in pts:
		r = maxf(r, _flat(q, c))
	# From above the camp interior (trees are kept out of it), looking at the group.
	var inward := site.center - c
	inward.y = 0.0
	if inward.length_squared() < 4.0:
		inward = -pl.global_basis.z
	inward = inward.normalized()
	var side := Vector3(-inward.z, 0, inward.x)
	var dist := 5.0 + r * 1.3
	var pos := c + inward * dist * 0.75 + side * dist * 0.45 + Vector3.UP * (6.0 + r * 0.5)
	pos.y = maxf(pos.y, WorldData.get_height(pos.x, pos.z) + 5.0)
	cam.look_at_from_position(pos, c + Vector3.UP * 1.0, Vector3.UP)
	cam.make_current()
	await p.screenshot(name)
	pl.camera_rig.make_current()
