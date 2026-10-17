extends RefCounted
## Air against real enemies (EnemyBase with brains, tokens, telegraphs) in the enemy
## arena, driven through InputMap actions (docs/modules/bending_air.md):
##   group    bandit brawler + skirmisher close in, a firebender hangs back:
##            Air Push when surrounded (knockdown / knockback ring), Wind Blade at the
##            firebender, the combo on the nearest, Vortex Ward catching fire bolts,
##            Air Tornado lifting the group, Air Scooter out + Gale Drop back in
##   sparring a Sparring Airbender (AirKit.enemy_archetype, AirKit.equip_enemy) fights the
##            player with the same Air techniques through the enemy brain
## Screenshots enemies_<step> come from an observer camera framing the fight.
## PART=group,sparring picks parts.

const E := ElementDefs.Element
const DT := 1.0 / 60.0

var p: Playtest
var arena: Node
var pl: PlayerCharacter
var cam: Camera3D
var hits: Array = []
var struck_ids: Array = []


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(E.AIR, true)
	arena = await p.load_scene("res://scenes/dev/enemy_arena.tscn", {"element": E.AIR, "spawn": false})
	await p.wait_game(0.4)
	pl = arena.get("player") as PlayerCharacter
	p.check(pl != null, "player spawned")
	pl.camera_rig.require_capture = false
	pl.resources.infinite_chi = true
	pl.health.invulnerable = true
	cam = Camera3D.new()
	cam.name = "ObserverCamera"
	cam.fov = 55.0
	arena.add_child(cam)
	for pair: Array in [[&"technique_1", &"air_push"], [&"technique_2", &"wind_blade"], [&"technique_3", &"air_scooter"],
			[&"technique_4", &"vortex_ward"], [&"signature", &"air_tornado"]]:
		pl.controller.set_slot(pair[0], AbilityRegistry.get_def(pair[1]))
	Events.hit_landed.connect(func(hit: HitInfo, t: Node, r: int) -> void:
		hits.append({"id": hit.ability_id, "t": t, "r": r, "reaction": hit.reaction, "team": hit.team}))
	var only := OS.get_environment("PART")
	for part in ["group", "sparring"]:
		if only == "" or only.split(",").has(part):
			p.note("--- %s ---" % part)
			await call("_" + part)
	var by := {}
	for h: Dictionary in hits:
		by[String(h["id"])] = int(by.get(String(h["id"]), 0)) + 1
	p.note("hits by ability: %s" % str(by))


# --- helpers -----------------------------------------------------------------------------------------

func _tick_until(cond: Callable, timeout: float) -> bool:
	for i in int(timeout * 60.0):
		if cond.call():
			return true
		await p.get_tree().physics_frame
	return cond.call()


func _cur_id() -> StringName:
	return pl.controller.current.def.id if pl.controller.current != null else &""


func _alive(group: Array) -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	for e: EnemyBase in group:
		if is_instance_valid(e) and e.is_alive():
			out.append(e)
	return out


func _nearest(group: Array) -> EnemyBase:
	var best: EnemyBase = null
	var bd := INF
	for e in _alive(group):
		var d := e.global_position.distance_to(pl.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func _face(e: Node3D) -> void:
	if e == null or not is_instance_valid(e):
		return
	var to := e.global_position - pl.global_position
	to.y = 0.0
	if to.length_squared() > 0.01:
		pl.rotation.y = atan2(-to.x, -to.z)


func _lock(e: EnemyBase) -> void:
	_face(e)
	if pl.get_lock_target() != e:
		pl.targeting.lock(e)


## Enemy hits (by the player's team) of `id` since index `from`.
func _hits_on_enemies(id: StringName, from: int = 0) -> Array:
	var out: Array = []
	for i in range(from, hits.size()):
		var h: Dictionary = hits[i]
		if h["id"] == id and h["t"] is EnemyBase and (h["r"] == Combat.Result.HIT or h["r"] == Combat.Result.KILLED):
			out.append(h)
	return out


## Presses `action` until the ability `want` runs (busy / buffered presses retried).
func _cast(action: StringName, want: StringName, hold: float = 0.06) -> bool:
	for attempt in 6:
		await _tick_until(func() -> bool: return not pl.controller.is_busy() and pl.states.is_free(), 3.0)
		p.hold(action)
		var ok := await _tick_until(func() -> bool: return _cur_id() == want, 0.4)
		if ok:
			await p.wait_game(hold)
			p.release(action)
			return true
		p.release(action)
		await p.wait_game(0.15)
	return false


## Observer shot framing the player and a point of interest (pillars avoided).
func _shot(name: String, focus: Vector3, side: float = 1.0, dist: float = 8.0, height: float = 2.6) -> void:
	var a := pl.global_position + Vector3.UP
	var f := focus - a
	f.y = 0.0
	var fwd := f.normalized() if f.length() > 0.5 else -pl.global_basis.z
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var mid := a.lerp(focus, 0.45)
	var space := arena.get_viewport().get_world_3d().direct_space_state
	var pos := mid + right * side * dist - fwd * dist * 0.35 + Vector3.UP * height
	for c: Array in [[side, 0.35], [-side, 0.35], [side, 0.9], [-side, 0.9], [0.3, 1.2]]:
		var q: Vector3 = mid + right * float(c[0]) * dist - fwd * dist * float(c[1]) + Vector3.UP * height
		var rq := PhysicsRayQueryParameters3D.create(q, mid, Layers.WORLD)
		if space.intersect_ray(rq).is_empty():
			pos = q
			break
	cam.look_at_from_position(pos, mid, Vector3.UP)
	cam.make_current()
	await p.screenshot(name)
	pl.camera_rig.make_current()


func _spawn(ids: Array, spots: Array) -> Array:
	var group: Array = arena.call("spawn_group", ids, spots)
	for e: EnemyBase in group:
		e.low_health_mode = &""
	return group


# --- the group fight ---------------------------------------------------------------------------------

func _group() -> void:
	p.release_all()
	pl.respawn_at(Transform3D(Basis(), Vector3(0, 0, 4)), 1.0)
	pl.resources.set_focus(100.0)
	await p.wait_game(0.2)
	pl.camera_rig.snap_behind(pl)
	var group := _spawn([&"bandit_brawler", &"bandit_skirmisher", &"fire_soldier"], [Vector3(-1.6, 0, -1.5), Vector3(1.8, 0, -2.0), Vector3(0.5, 0, -10.0)])
	await p.wait_game(0.3)
	for e: EnemyBase in group:
		e.brain.engage(pl)
	var brawler := group[0] as EnemyBase
	var skirm := group[1] as EnemyBase
	var soldier := group[2] as EnemyBase

	# 1) Surrounded: Air Push clears the space.
	var closing := await _tick_until(func() -> bool:
		_face(brawler)
		var n := 0
		for e in _alive([brawler, skirm]):
			if e.global_position.distance_to(pl.global_position) < 3.4:
				n += 1
		return n >= 2, 8.0)
	p.check(closing, "brawler and skirmisher closed in")
	await _shot("enemies_closing", (brawler.global_position + skirm.global_position) * 0.5 + Vector3.UP, 1.0, 7.5, 2.2)
	var h0 := hits.size()
	p.check(await _cast(&"ability_1", &"air_push", 0.04), "air push")
	await _tick_until(func() -> bool:
		var a := pl.controller.current as ChargeAbility
		return a == null or a.released, 1.0)
	await p.wait_game(0.12)
	await _shot("enemies_push", pl.global_position + Vector3(0, 0.5, -2.0), -1.0, 8.5, 3.4)
	await p.wait_game(0.35)
	var pushed := _hits_on_enemies(&"air_push", h0)
	var downs := 0
	var dodged := 0
	for i in range(h0, hits.size()):
		var h: Dictionary = hits[i]
		if h["id"] != &"air_push" or not (h["t"] is EnemyBase):
			continue
		if h["r"] == Combat.Result.DODGED:
			dodged += 1
		elif h["reaction"] == HitInfo.Reaction.KNOCKDOWN:
			downs += 1
	var dist_after := minf(brawler.global_position.distance_to(pl.global_position), skirm.global_position.distance_to(pl.global_position))
	p.note("push: %d hits (%d knockdowns), %d dodged (skirmishers dodge on reaction); closest melee enemy now %.1f m" % [pushed.size(), downs, dodged, dist_after])
	p.check(pushed.size() + dodged >= 2, "push met both melee enemies (%d hit, %d dodged)" % [pushed.size(), dodged])
	await _shot("enemies_push_after", pl.global_position + Vector3(0, 0.5, -2.0), 1.0, 9.0, 3.0)

	# 2) Wind Blade at the firebender hanging back.
	h0 = hits.size()
	_lock(soldier)
	await p.wait_game(0.1)
	p.check(await _cast(&"ability_2", &"wind_blade", 0.04), "wind blade")
	await _tick_until(func() -> bool:
		var a := pl.controller.current
		return a == null or bool(a.get("_fired")), 1.0)
	await p.wait_game(0.1)
	await _shot("enemies_blade", soldier.global_position + Vector3.UP, 1.0, 7.0, 2.0)
	await _tick_until(func() -> bool: return _hits_on_enemies(&"wind_blade", h0).size() > 0, 1.0)
	p.check(_hits_on_enemies(&"wind_blade", h0).size() > 0 or not soldier.is_alive(), "blade reached the firebender")

	# 3) Combo on whoever comes back first.
	h0 = hits.size()
	var tgt := _nearest([brawler, skirm])
	if tgt:
		_lock(tgt)
		await _tick_until(func() -> bool: return tgt.global_position.distance_to(pl.global_position) < 4.5 or not tgt.is_alive(), 5.0)
		for i in 3:
			_face(tgt)
			await p.tap(&"attack_light", 0.04)
			await _tick_until(func() -> bool:
				var c := pl.controller.current as ComboAbility
				return c != null and c.struck, 0.8)
			if i == 1:
				await _shot("enemies_combo", tgt.global_position + Vector3.UP, 1.0, 6.0, 1.8)
			await _tick_until(func() -> bool:
				var c := pl.controller.current as ComboAbility
				return c == null or c.can_chain(), 1.0)
		await p.wait_game(0.3)
	p.check(_hits_on_enemies(&"air_combo", h0).size() >= 1, "combo connected (%d)" % _hits_on_enemies(&"air_combo", h0).size())

	# 4) Vortex Ward vs the firebender's bolts.
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	_lock(soldier)
	p.check(await _cast(&"ability_4", &"vortex_ward"), "vortex ward up")
	var ward := pl.controller.current
	var caught := await _tick_until(func() -> bool:
		_face(soldier)
		return ward == null or pl.controller.current != ward or (ward.get("held") as Array).size() > 0, 3.2)
	if ward != null and pl.controller.current == ward:
		await _shot("enemies_ward", pl.global_position + Vector3(0, 1.0, -1.5), 1.0, 5.5, 1.4)
		p.note("ward holding %d projectiles" % (ward.get("held") as Array).size())
	p.note("ward caught a bolt: %s" % caught)
	await _tick_until(func() -> bool: return pl.controller.current != ward, 4.0)

	# 5) Air Tornado on the group.
	await _tick_until(func() -> bool: return not pl.controller.is_busy() and pl.states.is_free(), 3.0)
	pl.resources.set_focus(100.0)
	var alive := _alive(group)
	if not alive.is_empty():
		_lock(_nearest(alive))
	h0 = hits.size()
	p.check(await _cast(&"ability_special", &"air_tornado"), "tornado cast")
	var torn := pl.controller.current
	var lifted := await _tick_until(func() -> bool:
		for e in _alive(group):
			if e.global_position.y > 1.6:
				return true
		return torn == null or pl.controller.current != torn, 3.5)
	var c := Vector3(torn.get("center")) if torn != null else pl.global_position
	await _shot("enemies_tornado", c + Vector3.UP * 3.0, 1.0, 12.0, 2.2)
	p.check(lifted, "the tornado lifted an enemy")
	await _tick_until(func() -> bool: return pl.controller.current != torn, 4.0)
	await p.wait_game(0.15)
	await _shot("enemies_tornado_release", c + Vector3.UP * 1.5, -1.0, 12.0, 3.0)
	p.check(_hits_on_enemies(&"air_tornado", h0).size() >= 2, "tornado hits (%d)" % _hits_on_enemies(&"air_tornado", h0).size())

	# 6) Scooter out, swing back in, jump off and Gale Drop onto them.
	await _tick_until(func() -> bool: return not pl.controller.is_busy() and pl.states.is_free(), 3.0)
	p.check(await _cast(&"ability_3", &"air_scooter"), "scooter")
	p.hold(&"move_back")
	await p.wait_game(0.45)
	await _shot("enemies_scooter", pl.global_position + Vector3(0, 0.6, -2.0), 1.0, 6.0, 1.2)
	p.release(&"move_back")
	var foe := _nearest(group)
	if foe:
		_lock(foe)
		p.hold(&"move_forward")
		await _tick_until(func() -> bool: return not is_instance_valid(foe) or foe.global_position.distance_to(pl.global_position) < 6.5, 4.0)
		p.release(&"move_forward")
		p.note("jumping off %.1f m from %s" % [foe.global_position.distance_to(pl.global_position), foe.display_name])
	await p.tap(&"jump", 0.08)
	await _tick_until(func() -> bool: return pl.velocity.y < 1.0, 1.2)
	h0 = hits.size()
	p.check(await _cast(&"attack_heavy", &"air_blast", 0.04), "gale drop")
	await _tick_until(func() -> bool: return pl.is_on_floor(), 2.5)
	await p.wait_game(0.06)
	await _shot("enemies_gale_drop", pl.global_position + Vector3(0, 0.5, -1.5), -1.0, 7.5, 2.6)
	await p.wait_game(0.3)
	p.note("gale drop hits: %d" % _hits_on_enemies(&"air_blast", h0).size())
	await p.wait_game(1.0)
	var taken := 0
	for h: Dictionary in hits:
		if h["t"] == pl and h["r"] == Combat.Result.HIT:
			taken += 1
	p.note("hits the player took in the group fight: %d" % taken)
	arena.call("clear_enemies")
	if pl.get_lock_target() != null:
		pl.targeting.call("toggle_lock")
	await p.wait_game(0.4)


# --- an air-bending enemy ----------------------------------------------------------------------------

func _sparring() -> void:
	p.release_all()
	EnemyArchetypes.register(&"air_sparring_monk", AirKit.enemy_archetype())
	pl.respawn_at(Transform3D(Basis(), Vector3(0, 0, 4)), 1.0)
	await p.wait_game(0.2)
	pl.camera_rig.snap_behind(pl)
	var group := _spawn([&"air_sparring_monk"], [Vector3(0, 0, -4.0)])
	var monk := group[0] as EnemyBase
	await p.wait_game(0.1)
	p.check(monk.controller != null and monk.element == E.AIR, "air enemy has a bending controller")
	AirKit.equip_enemy(monk.controller)
	var t1 := monk.controller.get_slot_def(&"technique_1")
	p.check(t1 != null and t1.id == &"enemy_air_push",
			"enemy-tuned Air Push in technique_1")
	monk.attack_struck.connect(func(_e: EnemyBase, a: Dictionary) -> void: struck_ids.append(a.get("id")))
	monk.brain.engage(pl)
	var h0 := hits.size()
	# The player alternates keeping its distance (9 m) and closing in (2.5 m) while
	# strafing: the monk has to use the whole kit (blade / blast far, jabs / push close).
	var shot_done := {}
	var t := 0.0
	while t < 20.0:
		_face(monk)
		var d := monk.global_position.distance_to(pl.global_position)
		var want := 9.0 if int(t / 4.0) % 2 == 0 else 2.5
		p.release(&"move_back")
		p.release(&"move_forward")
		if d < want - 1.0:
			p.hold(&"move_back")
		elif d > want + 1.0:
			p.hold(&"move_forward")
		if int(t / 2.0) % 2 == 0:
			p.hold(&"move_left")
		else:
			p.release(&"move_left")
		var cur := monk.controller.current
		if cur != null and not shot_done.has(cur.def.id):
			shot_done[cur.def.id] = true
			await p.wait_game(0.18)
			await _shot("enemies_monk_%s" % String(cur.def.id).trim_prefix("enemy_"), monk.global_position + Vector3.UP, 1.0, 7.0, 1.8)
			t += 0.18
		await p.wait_game(DT)
		t += DT
	p.release_all()
	var used := {}
	for id in struck_ids:
		used[id] = true
	var on_player := 0
	for i in range(h0, hits.size()):
		var h: Dictionary = hits[i]
		if h["t"] == pl and String(h["id"]).begins_with("enemy_air"):
			on_player += 1
	p.note("air enemy struck with: %s" % str(used.keys()))
	p.check(used.size() >= 2, "air enemy used %d different techniques" % used.size())
	p.check(on_player >= 1, "air enemy landed hits on the player (%d)" % on_player)
	arena.call("clear_enemies")
	await p.wait_game(0.3)
