extends RefCounted
## Fire vs real enemies (enemy arena, the real player through InputMap actions):
## a combo string captured frame by frame on a bandit brawler (jab, jab, kick,
## roundhouse -> Fire Burst -> Fire Whip -> Blaze Charge), then an Earth Kingdom rogue
## squad meets Fire Ring, Jet Step, Lightning and the Inferno, then an enemy firebender
## (a runtime archetype using FireKit.enemy_attacks) turns Fire Burst / Fire Ring /
## Fire Whip on the player. Observer-camera screenshots + a hit report.
## PART=combo,squad,adept (default all).

const E := ElementDefs.Element

var p: Playtest
var arena: Node
var pl: PlayerCharacter
var cam: Camera3D
var hits: Array = []
var taken: Array = []


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(E.FIRE, true)
	arena = await p.load_scene("res://scenes/dev/enemy_arena.tscn", {"element": E.FIRE, "spawn": false})
	await p.wait_game(0.4)
	pl = p.player() as PlayerCharacter
	pl.camera_rig.require_capture = false
	pl.resources.infinite_chi = true
	cam = Camera3D.new()
	cam.fov = 55.0
	arena.add_child(cam)
	Events.hit_landed.connect(func(hit: HitInfo, t: Node, r: int) -> void:
		if t is EnemyBase:
			hits.append([hit.ability_id, t, r, hit.reaction, hit.damage]))
	Events.player_damaged.connect(func(amount: float, hit: HitInfo) -> void: taken.append([hit.ability_id, amount, hit.reaction]))
	var only := OS.get_environment("PART")
	for part in ["combo", "squad", "adept"]:
		if only == "" or only.split(",").has(part):
			p.note("--- %s ---" % part)
			await call("_" + part)
	_report()


# --- helpers ---------------------------------------------------------------------------------------

func _tick_until(cond: Callable, timeout: float = 5.0) -> bool:
	for i in int(timeout * 60.0):
		if cond.call():
			return true
		await p.get_tree().physics_frame
	return cond.call()


func _slots() -> void:
	pl.controller.set_slot(&"technique_1", AbilityRegistry.get_def(&"fire_burst"))
	pl.controller.set_slot(&"technique_2", AbilityRegistry.get_def(&"fire_ring"))
	pl.controller.set_slot(&"technique_3", AbilityRegistry.get_def(&"fire_whip"))
	pl.controller.set_slot(&"technique_4", AbilityRegistry.get_def(&"lightning"))
	pl.controller.set_slot(&"signature", AbilityRegistry.get_def(&"inferno"))
	pl.controller.reset_cooldowns()


func _obs(shot: String, focus: Vector3, side: float = 1.0, dist: float = 8.0, height: float = 3.0) -> void:
	var a := pl.global_position + Vector3.UP
	var f := focus - a
	f.y = 0.0
	var fwd := f.normalized() if f.length() > 0.5 else -pl.global_basis.z
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var mid := a.lerp(focus, 0.5)
	cam.look_at_from_position(mid + right * side * dist - fwd * dist * 0.3 + Vector3.UP * height, mid, Vector3.UP)
	cam.make_current()
	await p.screenshot(shot)
	pl.camera_rig.make_current()


func _alive() -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	for e: EnemyBase in arena.get("enemies"):
		if is_instance_valid(e) and e.is_alive():
			out.append(e)
	return out


func _center() -> Vector3:
	var c := Vector3.ZERO
	var es := _alive()
	for e in es:
		c += e.global_position
	return c / maxf(es.size(), 1) if not es.is_empty() else pl.global_position - pl.global_basis.z * 6.0


func _cur_id() -> StringName:
	return pl.controller.current.def.id if pl.controller.current != null else &""


func _cast(action: StringName, want: StringName, hold: float = 0.06) -> bool:
	for attempt in 4:
		await _tick_until(func() -> bool: return pl.states.is_free() and not pl.controller.is_busy(), 3.0)
		if want == &"inferno":
			pl.resources.mark_combat()
			pl.resources.set_focus(100.0)
		Input.action_press(action)
		var ok := await _tick_until(func() -> bool: return _cur_id() == want, 0.4)
		if ok:
			await p.wait_game(hold)
			Input.action_release(action)
			return true
		Input.action_release(action)
		await p.wait_game(0.2)
	return false


func _lock_nearest() -> void:
	if pl.get_lock_target() == null:
		pl.targeting.call("toggle_lock")
	await p.wait_game(0.2)


func _unlock() -> void:
	if pl.get_lock_target() != null:
		pl.targeting.call("toggle_lock")


func _keep_player_up() -> void:
	if pl.health.health < pl.health.max_health * 0.5:
		pl.health.heal(pl.health.max_health)


func _count(id: StringName, list: Array = hits) -> int:
	return list.filter(func(h: Array) -> bool: return h[0] == id and (list != hits or h[2] == Combat.Result.HIT or h[2] == Combat.Result.KILLED)).size()


func _close_in(dist: float) -> void:
	var best: EnemyBase = null
	for e in _alive():
		if best == null or e.global_position.distance_to(pl.global_position) < best.global_position.distance_to(pl.global_position):
			best = e
	if best == null:
		return
	var d := pl.global_position - best.global_position
	d.y = 0.0
	d = d.normalized() if d.length() > 0.1 else Vector3.BACK
	var pos := best.global_position + d * dist
	pl.teleport(Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), Vector3(pos.x, 0.0, pos.z)))
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.1)


# --- combo string ----------------------------------------------------------------------------------

## Jab, jab, kick, roundhouse -> Fire Burst -> Fire Whip -> Blaze Charge on one brawler.
func _combo() -> void:
	arena.call("spawn_group", [&"bandit_brawler"], [Vector3(0, 0, -0.5)])
	_slots()
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, 3.0)))
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.5)
	var e: EnemyBase = arena.get("enemies")[0]
	e.health.set_max_health(400.0, true)
	var ticks0 := FireStatus.ticks_applied
	var burning_seen := false
	var frame := 0
	await _lock_nearest()
	for i in 4:
		Input.action_press(&"attack_light")
		await p.wait_game(0.05)
		Input.action_release(&"attack_light")
		for k in 2:
			await p.wait_game(0.05)
			await _obs("combo_%02d" % frame, e.global_position + Vector3.UP, 1.0, 6.0, 2.0)
			frame += 1
		await _tick_until(func() -> bool:
			var c := pl.controller.current as ComboAbility
			return c == null or c.can_chain(), 1.0)
	await _close_in(2.0)
	for step: Array in [[&"ability_1", &"fire_burst", [0.2, 0.1, 0.2]], [&"ability_3", &"fire_whip", [0.3, 0.12, 0.15]]]:
		p.check(await _cast(step[0], step[1]), "%s cast in the string" % step[1])
		for dt: float in step[2]:
			await p.wait_game(dt)
			burning_seen = burning_seen or FireStatus.is_burning(e)
			await _obs("combo_%02d" % frame, e.global_position + Vector3.UP, 1.0, 7.0, 2.4)
			frame += 1
	await _tick_until(func() -> bool: return pl.states.is_free() and not pl.controller.is_busy(), 2.0)
	Input.action_press(&"attack_heavy")
	await p.wait_game(1.3)
	await _obs("combo_%02d" % frame, pl.global_position + Vector3.UP, 1.0, 5.0, 1.4)
	frame += 1
	Input.action_release(&"attack_heavy")
	await _tick_until(func() -> bool: return _count(&"fire_blast") > 0, 2.0)
	await p.wait_game(0.05)
	await _obs("combo_%02d" % frame, e.global_position + Vector3.UP, -1.0, 7.0, 2.4)
	await p.wait_game(0.6)
	var kinds := {}
	for h: Array in hits:
		if h[2] == Combat.Result.HIT or h[2] == Combat.Result.KILLED:
			kinds[h[0]] = true
	p.note("combo kinds: %s" % str(kinds.keys()))
	p.check(kinds.has(&"fire_combo") and kinds.has(&"fire_burst") and kinds.size() >= 3, "combo string landed (%d hits, %s)" % [hits.size(), str(kinds.keys())])
	# Burn ticks are applied straight to the target (no hit-landed event): count them at the source.
	var ticks := FireStatus.ticks_applied - ticks0
	p.check(burning_seen and ticks >= 1, "the bandit burned between hits (%d ticks)" % ticks)
	_unlock()
	arena.call("clear_enemies")
	await p.wait_game(0.3)


# --- squad ---------------------------------------------------------------------------------------------

func _squad() -> void:
	arena.call("spawn_group", [&"earth_rogue", &"bandit_brawler", &"bandit_skirmisher", &"bandit_archer"],
			[Vector3(-2.5, 0, -7), Vector3(1.5, 0, -6.5), Vector3(3.0, 0, -9.0), Vector3(0, 0, -15)])
	_slots()
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, 3)))
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(1.2)
	await _obs("squad_0_engage", _center(), 1.0, 9.0, 3.5)
	# Let them close in, then the Fire Ring.
	await _close_in(2.5)
	p.check(await _cast(&"ability_2", &"fire_ring"), "fire ring cast")
	await _tick_until(func() -> bool: return not FireRingWave.live.is_empty(), 1.5)
	await p.wait_game(0.15)
	await _obs("squad_1_ring", pl.global_position, 1.0, 10.0, 4.5)
	await p.wait_game(0.4)
	p.check(_count(&"fire_ring") >= 1, "the ring knocked them back (%d)" % _count(&"fire_ring"))
	_keep_player_up()
	# Jet Step over them and Lightning at the archer.
	pl.controller.set_slot(&"technique_1", AbilityRegistry.get_def(&"jet_step"))
	pl.controller.reset_cooldowns()
	Input.action_press(&"move_forward")
	p.check(await _cast(&"ability_1", &"jet_step", 0.04), "jet step cast")
	await p.wait_game(0.35)
	await _obs("squad_2_jet", pl.global_position, -1.0, 7.0, 0.8)
	Input.action_release(&"move_forward")
	await _tick_until(func() -> bool: return pl.motor.on_floor and pl.states.is_free(), 3.0)
	_keep_player_up()
	# Lightning needs 1.6 s of concentration and any hit breaks it: disengage first (as a
	# player would after the Jet Step), then charge at range. A broken charge is retried.
	var tries := 0
	var interrupts0 := FireLightning.interrupts
	while tries < 3 and _count(&"lightning") == 0 and not _alive().is_empty():
		tries += 1
		var c := _center()
		var away := pl.global_position - c
		away.y = 0.0
		away = away.normalized() if away.length() > 0.5 else Vector3.BACK
		var pos := c + away * 11.0
		pl.teleport(Transform3D(Basis(Vector3.UP, atan2(away.x, away.z)), Vector3(pos.x, 0.0, pos.z)))
		pl.camera_rig.snap_behind(pl)
		pl.controller.reset_cooldowns()
		await p.wait_game(0.15)
		_unlock()
		await _lock_nearest()
		await _tick_until(func() -> bool: return pl.states.is_free() and not pl.controller.is_busy(), 2.0)
		Input.action_press(&"ability_4")
		await _tick_until(func() -> bool: return _cur_id() == &"lightning", 1.0)
		await p.wait_game(1.65)
		if tries == 1 or _cur_id() == &"lightning":
			await _obs("squad_3_lightning_charge", pl.global_position + Vector3.UP, 1.0, 4.5, 0.8)
		Input.action_release(&"ability_4")
		await _tick_until(func() -> bool: return _count(&"lightning") > 0 or not pl.controller.is_busy(), 1.5)
		await p.wait_game(0.03)
		if _count(&"lightning") > 0:
			var t := pl.get_lock_target()
			await _obs("squad_4_lightning", (t.global_position if t else _center()) + Vector3.UP, 1.0, 8.0, 2.4)
	p.note("lightning: tries %d, hits %d, charges broken by hits %d, backfires %d" % [tries, _count(&"lightning"),
			FireLightning.interrupts - interrupts0, FireLightning.backfires])
	p.check(_count(&"lightning") >= 1, "lightning struck the squad")
	_unlock()
	_keep_player_up()
	# The Inferno on whoever is left.
	await _close_in(3.0)
	p.check(await _cast(&"ability_special", &"inferno"), "inferno cast")
	await p.wait_game(0.6)
	await _obs("squad_5_vortex", pl.global_position + Vector3.UP * 1.5, 1.0, 9.0, 2.0)
	await _tick_until(func() -> bool: return not FireRingWave.live.is_empty(), 2.0)
	await p.wait_game(0.2)
	await _obs("squad_6_inferno", pl.global_position, 1.0, 14.0, 6.0)
	await p.wait_game(1.0)
	await _obs("squad_7_after", pl.global_position, -1.0, 12.0, 6.0)
	p.check(_count(&"inferno") >= 1, "the inferno launched the squad (%d)" % _count(&"inferno"))
	arena.call("clear_enemies")
	await p.wait_game(0.3)


# --- enemy firebender ---------------------------------------------------------------------------------

## A runtime archetype casting the Fire techniques through its controller.
func _adept() -> void:
	var a: Dictionary = EnemyArchetypes.get_archetype(&"fire_soldier").duplicate(true)
	a["display_name"] = "Firebender Adept"
	var atk: Array = a["attacks"]
	for at: Dictionary in atk:
		at["weight"] = 0.25
	var extra := FireKit.enemy_attacks()
	for k: StringName in [&"fire_burst", &"fire_ring", &"fire_whip"]:
		var d: Dictionary = (extra[k] as Dictionary).duplicate(true)
		d["weight"] = 2.0
		d["cooldown"] = 3.0
		atk.append(d)
	EnemyArchetypes.register(&"fire_adept_test", a)
	pl.set_element(E.WATER)
	await p.wait_game(0.3)
	var es: Array = arena.call("spawn_group", [&"fire_adept_test"], [Vector3(0, 0, -6)])
	var e: EnemyBase = es[0]
	e.controller.set_slot(&"technique_2", AbilityRegistry.get_def(&"fire_burst"))
	e.controller.set_slot(&"technique_3", AbilityRegistry.get_def(&"fire_ring"))
	e.controller.set_slot(&"technique_4", AbilityRegistry.get_def(&"fire_whip"))
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	pl.camera_rig.snap_behind(pl)
	var cast_ids := {}
	e.controller.ability_started.connect(func(ab: BendingAbility) -> void: cast_ids[ab.def.id] = true)
	var tm := 0.0
	var snap := 0
	while tm < 18.0 and cast_ids.size() < 3:
		await p.wait_game(0.1)
		tm += 0.1
		_keep_player_up()
		# Stay close so every technique is in range.
		if pl.global_position.distance_to(e.global_position) > 3.5:
			await _close_in(2.6)
		var cur := e.controller.current
		var ring_up := cur == null or cur.def.id != &"fire_ring" or not FireRingWave.live.is_empty()
		if cur != null and cur.def.id in [&"fire_burst", &"fire_ring", &"fire_whip"] and snap < 6 and cur.time > 0.25 and ring_up:
			await _obs("adept_%d_%s" % [snap, cur.def.id], e.global_position + Vector3.UP, 1.0, 7.0, 2.4)
			snap += 1
	p.note("adept cast: %s" % str(cast_ids.keys()))
	p.check(cast_ids.size() >= 2, "the enemy firebender used the Fire techniques (%s)" % str(cast_ids.keys()))
	var mine := taken.filter(func(h: Array) -> bool: return h[0] in [&"fire_burst", &"fire_ring", &"fire_whip"])
	p.note("player hit by: %s" % str(mine.map(func(h: Array) -> String: return "%s %.0f" % [h[0], h[1]])))
	p.check(mine.size() >= 1, "they landed on the player (%d)" % mine.size())
	arena.call("clear_enemies")


func _report() -> void:
	var by := {}
	for h: Array in hits:
		if h[2] == Combat.Result.HIT or h[2] == Combat.Result.KILLED:
			var k := String(h[0])
			by[k] = int(by.get(k, 0)) + 1
	p.note("hits on enemies by ability: %s" % str(by))
	var tk := {}
	for h: Array in taken:
		var k := String(h[0])
		tk[k] = int(tk.get(k, 0)) + 1
	p.note("hits taken by ability: %s" % str(tk))
