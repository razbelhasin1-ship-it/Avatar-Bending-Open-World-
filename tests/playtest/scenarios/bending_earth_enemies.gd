extends RefCounted
## Earth vs real enemies (enemy arena, the real player through InputMap
## actions): a combo string captured frame by frame on a bandit brawler (punch
## x3 -> Earth Stomp -> Earth Pillar launch -> Earth Spikes), then a Fire Nation
## squad (spearman with a shield, firebender, archer) meets Earth Spikes, Earth
## Grab, Earth Armor and the Earthquake, then an enemy earthbender (a runtime
## archetype using EarthKit.enemy_attacks) turns Pillar / Stomp / Spikes on the
## player. Observer-camera screenshots + a hit report.
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
	GameState.new_game(E.EARTH, true)
	arena = await p.load_scene("res://scenes/dev/enemy_arena.tscn", {"element": E.EARTH, "spawn": false})
	await p.wait_game(0.4)
	pl = p.player() as PlayerCharacter
	pl.camera_rig.require_capture = false
	pl.resources.infinite_chi = true
	cam = Camera3D.new()
	cam.fov = 55.0
	arena.add_child(cam)
	# Packed earth under the courtyard tiles: brown rock.
	GroundSampler.add_zone(&"earth_dirt", Rect2(-24.0, -30.0, 48.0, 40.0), &"dirt", 0.0)
	Events.hit_landed.connect(func(hit: HitInfo, t: Node, r: int) -> void:
		if t is EnemyBase:
			hits.append([hit.ability_id, t, r, hit.reaction]))
	Events.player_damaged.connect(func(amount: float, hit: HitInfo) -> void: taken.append([hit.ability_id, amount, hit.reaction]))
	var only := OS.get_environment("PART")
	for part in ["combo", "squad", "adept"]:
		if only == "" or only.split(",").has(part):
			p.note("--- %s ---" % part)
			await call("_" + part)
	_report()
	GroundSampler.remove_zone(&"earth_dirt")


# --- helpers ---------------------------------------------------------------------------------------

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


func _slots() -> void:
	pl.controller.set_slot(&"technique_1", AbilityRegistry.get_def(&"earth_pillar"))
	pl.controller.set_slot(&"technique_2", AbilityRegistry.get_def(&"earth_stomp"))
	pl.controller.set_slot(&"technique_3", AbilityRegistry.get_def(&"earth_spikes"))
	pl.controller.set_slot(&"technique_4", AbilityRegistry.get_def(&"earth_grab"))
	pl.controller.set_slot(&"signature", AbilityRegistry.get_def(&"earthquake"))
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


func _cast(action: StringName, want: StringName, hold: float = 0.06) -> bool:
	for attempt in 4:
		await _tick_until(func() -> bool: return pl.states.is_free() and not pl.controller.is_busy(), 3.0)
		if want == &"earthquake":
			pl.resources.mark_combat()
			pl.resources.set_focus(100.0)
		Input.action_press(action)
		var ok := await _tick_until(func() -> bool: return pl.controller.current != null and pl.controller.current.def.id == want, 0.4)
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
	return list.filter(func(h: Array) -> bool: return h[0] == id).size()


# --- combo string ----------------------------------------------------------------------------------

## Punch x3 -> Stomp -> Pillar -> Spikes on one brawler, frame by frame.
func _combo() -> void:
	arena.call("spawn_group", [&"bandit_brawler"], [Vector3(0, 0, -0.5)])
	_slots()
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, 3.2)))
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.5)
	var e: EnemyBase = arena.get("enemies")[0]
	var frame := 0
	await _lock_nearest()
	for i in 3:
		Input.action_press(&"attack_light")
		await p.wait_game(0.05)
		Input.action_release(&"attack_light")
		for k in 2:
			await p.wait_game(0.06)
			await _obs("combo_%02d" % frame, e.global_position + Vector3.UP, 1.0, 6.0, 2.0)
			frame += 1
		await _tick_until(func() -> bool:
			var c := pl.controller.current as ComboAbility
			return c == null or c.can_chain(), 1.0)
	for step: Array in [[&"ability_2", &"earth_stomp", [0.22, 0.12, 0.15]], [&"ability_1", &"earth_pillar", [0.3, 0.1, 0.2, 0.25]],
			[&"ability_3", &"earth_spikes", [0.3, 0.12, 0.15, 0.2]]]:
		p.check(await _cast(step[0], step[1]), "%s cast in the string" % step[1])
		for dt: float in step[2]:
			await p.wait_game(dt)
			await _obs("combo_%02d" % frame, e.global_position + Vector3.UP, 1.0, 7.0, 2.4)
			frame += 1
	await p.wait_game(0.6)
	var kinds := {}
	for h: Array in hits:
		if h[2] == Combat.Result.HIT or h[2] == Combat.Result.KILLED:
			kinds[h[0]] = true
	p.check(hits.size() >= 5 and kinds.size() >= 3, "combo string landed (%d hits, %s)" % [hits.size(), str(kinds.keys())])
	_unlock()
	arena.call("clear_enemies")
	await p.wait_game(0.3)


# --- squad ---------------------------------------------------------------------------------------------

func _squad() -> void:
	arena.call("spawn_group", [&"fire_soldier", &"fire_shieldbearer", &"fire_archer"], [Vector3(-2.5, 0, -8), Vector3(1.5, 0, -7.5), Vector3(0, 0, -14)])
	_slots()
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, 3)))
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(1.4)
	await _obs("squad_0_engage", _center(), 1.0, 9.0, 3.5)
	# Earth Spikes through the front line (a shield cannot stop spikes from the ground).
	await _lock_nearest()
	p.check(await _cast(&"ability_3", &"earth_spikes"), "spikes cast")
	await p.wait_game(0.42)
	await _obs("squad_1_spikes", _center(), 1.0, 8.0, 2.6)
	await p.wait_game(0.4)
	p.check(_count(&"earth_spikes") >= 1, "spikes hit the squad (%d)" % _count(&"earth_spikes"))
	_keep_player_up()
	# Earth Grab the nearest.
	p.check(await _cast(&"ability_4", &"earth_grab"), "grab cast")
	var grabbed := await _tick_until(func() -> bool: return hits.any(func(h: Array) -> bool: return h[0] == &"earth_grab" and h[3] == HitInfo.Reaction.FREEZE), 2.0)
	await p.wait_game(0.15)
	var t := pl.get_lock_target()
	await _obs("squad_2_grabbed", (t.global_position if t else _center()) + Vector3.UP * 0.6, 1.0, 5.0, 1.4)
	p.check(grabbed, "grab rooted an enemy")
	_unlock()
	_keep_player_up()
	# Earth Armor: take their fire with 40 % less damage, then burst out.
	pl.controller.set_slot(&"technique_1", AbilityRegistry.get_def(&"earth_armor"))
	pl.controller.reset_cooldowns()
	p.check(await _cast(&"ability_1", &"earth_armor"), "armor cast")
	await _tick_until(func() -> bool: return EarthArmorState.is_worn(pl), 2.0)
	var n0 := taken.size()
	await p.wait_game(2.5)
	await _obs("squad_3_armored", pl.global_position + Vector3.UP, -1.0, 4.5, 1.2)
	p.check(EarthArmorState.is_worn(pl) and pl.ctx.damage_reduction >= 0.4, "armored under fire (%d hits taken meanwhile)" % (taken.size() - n0))
	_keep_player_up()
	await _close_in(2.2)
	p.check(await _cast(&"ability_1", &"earth_armor"), "armor shed")
	await p.wait_game(0.25)
	await _obs("squad_4_burst", pl.global_position + Vector3.UP, 1.0, 6.0, 2.0)
	_keep_player_up()
	# Earthquake on whoever is left.
	await _close_in(4.0)
	p.check(await _cast(&"ability_special", &"earthquake", 0.06), "earthquake cast")
	await _tick_until(func() -> bool: return not EarthShockwave.live.is_empty(), 2.0)
	await p.wait_game(0.15)
	await _obs("squad_5_quake", pl.global_position - pl.global_basis.z * 3.0, 1.0, 12.0, 4.5)
	await p.wait_game(0.5)
	await _obs("squad_6_after", pl.global_position - pl.global_basis.z * 3.0, -1.0, 11.0, 5.0)
	await p.wait_game(1.0)
	p.check(_count(&"earthquake") >= 2, "earthquake knocked the squad down (%d)" % _count(&"earthquake"))
	arena.call("clear_enemies")
	await p.wait_game(0.3)


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


# --- enemy earthbender ---------------------------------------------------------------------------------

## A runtime archetype casting the Earth techniques through its controller.
func _adept() -> void:
	var a: Dictionary = EnemyArchetypes.get_archetype(&"earth_rogue").duplicate(true)
	a["display_name"] = "Earthbender Adept"
	var atk: Array = a["attacks"]
	for at: Dictionary in atk:
		at["weight"] = 0.25
	var extra := EarthKit.enemy_attacks()
	for k: StringName in [&"earth_pillar", &"earth_stomp", &"earth_spikes"]:
		var d: Dictionary = (extra[k] as Dictionary).duplicate(true)
		d["weight"] = 2.0
		d["cooldown"] = 3.0
		atk.append(d)
	EnemyArchetypes.register(&"earth_adept_test", a)
	var es: Array = arena.call("spawn_group", [&"earth_adept_test"], [Vector3(0, 0, -8)])
	var e: EnemyBase = es[0]
	e.controller.set_slot(&"technique_2", AbilityRegistry.get_def(&"earth_pillar"))
	e.controller.set_slot(&"technique_3", AbilityRegistry.get_def(&"earth_stomp"))
	e.controller.set_slot(&"technique_4", AbilityRegistry.get_def(&"earth_spikes"))
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	pl.camera_rig.snap_behind(pl)
	var shots := [0]
	var tele := func(_en: EnemyBase, attack: Dictionary, _secs: float) -> void:
		var id: StringName = attack.get("id", &"")
		if id in [&"earth_pillar", &"earth_stomp", &"earth_spikes"]:
			shots[0] += 1
			p.note("adept telegraphs %s" % id)
	e.attack_telegraphed.connect(tele)
	var cast_ids := {}
	e.controller.ability_started.connect(func(ab: BendingAbility) -> void: cast_ids[ab.def.id] = true)
	var t := 0.0
	var snap := 0
	while t < 16.0 and cast_ids.size() < 3:
		await p.wait_game(0.25)
		t += 0.25
		_keep_player_up()
		var cur := e.controller.current
		if cur != null and cur.def.id in [&"earth_pillar", &"earth_stomp", &"earth_spikes"] and snap < 6 and cur.time > 0.2:
			await _obs("adept_%d_%s" % [snap, cur.def.id], e.global_position + Vector3.UP, 1.0, 7.0, 2.4)
			snap += 1
	e.attack_telegraphed.disconnect(tele)
	p.note("adept cast: %s" % str(cast_ids.keys()))
	p.check(cast_ids.size() >= 2, "the enemy earthbender used the Earth techniques (%s)" % str(cast_ids.keys()))
	var mine := taken.filter(func(h: Array) -> bool: return h[0] in [&"earth_pillar", &"earth_stomp", &"earth_spikes"])
	p.note("player hit by: %s" % str(mine.map(func(h: Array) -> String: return "%s %.0f" % [h[0], h[1]])))
	p.check(mine.size() >= 1, "they landed on the player (%d)" % mine.size())
	arena.call("clear_enemies")


func _report() -> void:
	var by := {}
	for h: Array in hits:
		var k := String(h[0])
		by[k] = int(by.get(k, 0)) + 1
	p.note("hits on enemies by ability: %s" % str(by))
	var tk := {}
	for h: Array in taken:
		var k := String(h[0])
		tk[k] = int(tk.get(k, 0)) + 1
	p.note("hits taken by ability: %s" % str(tk))
