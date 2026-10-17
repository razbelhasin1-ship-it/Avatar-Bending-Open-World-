extends RefCounted
## Water vs real enemies (enemy arena, the real player through InputMap
## actions): a firebender squad meets Water Surge, Ice Trap, Water Jet and the
## Tidal Torrent; a combo string is captured frame by frame (whip x3 -> surge);
## firebenders hit by water are doused. Observer-camera screenshots + a report.

const E := ElementDefs.Element

var p: Playtest
var arena: Node
var pl: PlayerCharacter
var cam: Camera3D
var hits: Array = []


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(E.WATER, true)
	arena = await p.load_scene("res://scenes/dev/enemy_arena.tscn", {"element": E.WATER, "spawn": false})
	await p.wait_game(0.4)
	pl = p.player() as PlayerCharacter
	pl.camera_rig.require_capture = false
	pl.resources.infinite_chi = true
	cam = Camera3D.new()
	cam.fov = 55.0
	arena.add_child(cam)
	Events.hit_landed.connect(func(hit: HitInfo, t: Node, r: int) -> void:
		if t is EnemyBase:
			hits.append([hit.ability_id, t, r, hit.reaction]))
	await _combo_string()
	await _squad()
	_report()


func _tick_until(cond: Callable, timeout: float = 5.0) -> bool:
	for i in int(timeout * 60.0):
		if cond.call():
			return true
		await p.get_tree().physics_frame
	return cond.call()


func _press(action: StringName, hold: float = 0.06) -> void:
	Input.action_press(action)
	await p.wait_game(hold)
	Input.action_release(action)


func _equip(id: StringName) -> void:
	var d := AbilityRegistry.get_def(id)
	pl.controller.set_slot(&"signature" if d.slot == AbilityDef.Slot.SIGNATURE else &"technique_1", d)
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


## Starts `slot_action` once the player is free to bend (retries a few times:
## enemy hits can stagger the player in between).
func _cast(action: StringName, hold: float, want: StringName) -> bool:
	for attempt in 4:
		await _tick_until(func() -> bool: return pl.states.is_free() and not pl.controller.is_busy(), 3.0)
		if want == &"tidal_torrent":
			pl.resources.mark_combat()
			pl.resources.set_focus(100.0)
		Input.action_press(action)
		var ok := await _tick_until(func() -> bool: return pl.controller.current != null and pl.controller.current.def.id == want, 0.4)
		if ok:
			# hold < 0: keep it pressed (the caller releases), 0: tap.
			if hold > 0.0:
				await p.wait_game(hold)
			if hold >= 0.0:
				Input.action_release(action)
			return true
		Input.action_release(action)
		await p.wait_game(0.2)
	return false


## Puts the player `dist` m from the nearest living enemy, facing it.
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


func _keep_player_up() -> void:
	if pl.health.health < pl.health.max_health * 0.5:
		pl.health.heal(pl.health.max_health)


## Light whip x3 into Water Surge, frame by frame from the observer.
func _combo_string() -> void:
	arena.call("spawn_group", [&"bandit_brawler"], [Vector3(0, 0, -1.5)])
	_equip(&"water_surge")
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, 4)))
	await p.wait_game(0.4)
	var e: EnemyBase = arena.get("enemies")[0]
	var frame := 0
	for i in 3:
		Input.action_press(&"attack_light")
		await p.wait_game(0.05)
		Input.action_release(&"attack_light")
		for k in 2:
			await p.wait_game(0.07)
			await _obs("combo_%02d" % frame, e.global_position + Vector3.UP, 1.0, 6.0, 2.0)
			frame += 1
		await _tick_until(func() -> bool:
			var c := pl.controller.current as ComboAbility
			return c == null or c.can_chain(), 1.0)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 1.0)
	await _press(&"ability_1")
	for k in 6:
		await p.wait_game(0.15)
		await _obs("combo_%02d" % frame, e.global_position + Vector3.UP, 1.0, 7.0, 2.4)
		frame += 1
	p.check(hits.size() >= 3, "combo string landed (%d hits)" % hits.size())
	await p.wait_game(1.0)
	arena.call("clear_enemies")
	await p.wait_game(0.3)


func _squad() -> void:
	var group := [&"fire_soldier", &"fire_soldier", &"fire_archer"]
	arena.call("spawn_group", group, [Vector3(-2.5, 0, -9), Vector3(2.5, 0, -10), Vector3(0, 0, -15)])
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, 4)))
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(1.6)
	await _obs("squad_0_engage", _center(), 1.0, 9.0, 3.5)
	# Water Surge into the squad.
	_equip(&"water_surge")
	await _tick_until(func() -> bool: return _center().distance_to(pl.global_position) < 9.0, 3.0)
	await _press(&"ability_1")
	await _tick_until(func() -> bool: return pl.controller.current == null or pl.controller.current.get("runner") != null, 1.5)
	await p.wait_game(0.25)
	await _obs("squad_1_surge", _center(), 1.0, 9.0, 3.0)
	await p.wait_game(0.4)
	await _obs("squad_2_surge_after", _center(), -1.0, 9.0, 3.0)
	var surge_hits := hits.filter(func(h: Array) -> bool: return h[0] == &"water_surge" and h[2] == Combat.Result.HIT).size()
	p.check(surge_hits >= 1, "surge hit the squad (%d)" % surge_hits)
	_keep_player_up()
	# Ice Trap on the nearest firebender.
	_equip(&"ice_trap")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	if pl.get_lock_target() == null:
		pl.targeting.call("toggle_lock")
	await p.wait_game(0.2)
	await _press(&"ability_1")
	var froze := await _tick_until(func() -> bool: return hits.any(func(h: Array) -> bool: return h[0] == &"ice_trap" and h[3] == HitInfo.Reaction.FREEZE), 2.0)
	await p.wait_game(0.15)
	var t := pl.get_lock_target()
	await _obs("squad_3_frozen", (t.global_position if t else _center()) + Vector3.UP, 1.0, 6.0, 2.0)
	p.check(froze, "ice trap froze an enemy")
	_keep_player_up()
	# Water Jet: sweep the firebenders (water douses fire: longer stun, steam).
	_equip(&"water_jet")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	await _close_in(6.0)
	var started := await _cast(&"ability_1", -1.0, &"water_jet")
	await p.wait_game(0.8)
	await _obs("squad_4_jet", _center(), -1.0, 7.0, 2.4)
	await p.wait_game(0.6)
	Input.action_release(&"ability_1")
	p.check(started, "jet started")
	var jet_hits := hits.filter(func(h: Array) -> bool: return h[0] == &"water_jet").size()
	p.check(jet_hits >= 2, "jet kept hitting (%d)" % jet_hits)
	_keep_player_up()
	if pl.get_lock_target() != null:
		pl.targeting.call("toggle_lock")
	# Tidal Torrent on whoever is left (they are drawn in).
	_equip(&"tidal_torrent")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	await _close_in(4.5)
	p.check(await _cast(&"ability_special", 0.0, &"tidal_torrent"), "tidal torrent started")
	await _tick_until(func() -> bool: return pl.controller.current == null or pl.controller.current.get("phase") == 1, 2.0)
	await p.wait_game(0.7)
	await _obs("squad_5_vortex", pl.global_position - pl.global_basis.z * 4.0, 1.0, 12.0, 4.0)
	await _tick_until(func() -> bool: return pl.controller.current == null or pl.controller.current.get("phase") == 2, 2.0)
	await p.wait_game(0.2)
	await _obs("squad_6_crash", pl.global_position - pl.global_basis.z * 4.0, 1.0, 13.0, 4.5)
	await p.wait_game(1.5)
	var tidal_hits := hits.filter(func(h: Array) -> bool: return h[0] == &"tidal_torrent").size()
	p.check(tidal_hits >= 2, "tidal torrent hit the squad (%d)" % tidal_hits)
	await _obs("squad_7_after", _center(), 1.0, 9.0, 3.0)


func _report() -> void:
	var by := {}
	for h: Array in hits:
		var k := String(h[0])
		by[k] = int(by.get(k, 0)) + 1
	p.note("hits on enemies by ability: %s" % str(by))
	var down := 0
	for e: EnemyBase in arena.get("enemies"):
		if not is_instance_valid(e) or not e.is_alive():
			down += 1
	p.note("enemies defeated: %d" % down)
