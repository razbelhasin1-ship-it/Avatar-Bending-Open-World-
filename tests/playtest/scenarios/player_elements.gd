extends RefCounted
## Per-element combat walkthrough in the combat arena (docs/modules/player.md):
## run + jump + dodge (+ the element's movement trick), the light combo with a
## screenshot on every strike frame, heavy charge + release, defending the
## sparring bot's fireball, a parry, lock-on framing and the starter technique.
## ELEMENT=air|earth|fire|water runs one element (default: all four).

const S := PlayerCharacter.State
## Open lane on the arena's west side for the bot duels (no dummies in view).
const LANE_BOT := Vector3(-11.0, 0, -18.0)
const LANE_PLAYER := Vector3(-11.0, 0, -12.0)
const BOT_HOME := Vector3(0, 0, -15.0)

var p: Playtest
var arena: Node
var pl: PlayerCharacter
var player_results: Array = []


func run(pt: Playtest) -> void:
	p = pt
	var only := OS.get_environment("ELEMENT")
	var elements: Array[int] = []
	if only != "":
		elements.append(ElementDefs.from_id(StringName(only)))
	else:
		elements.assign(ElementDefs.ALL)
	arena = await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": elements[0]})
	await p.wait_game(0.6)
	pl = p.player() as PlayerCharacter
	p.check(pl != null, "player spawned")
	var bot := arena.get("bot") as SparringBot
	bot.active = false
	Events.hit_landed.connect(_on_hit)
	for e in elements:
		await _element(e)
	Events.hit_landed.disconnect(_on_hit)


func _on_hit(_hit: HitInfo, target: Node, result: int) -> void:
	# The Earth Shield slab stands in front of the player and takes projectiles.
	if target == pl or (target is BendingConstruct and (target as BendingConstruct).follow == pl):
		player_results.append(result)


## Input through the Input singleton only (one press per tap: Playtest.tap also
## queues an InputEventAction, which re-presses when it is flushed a render
## frame later under slow software rendering).
func _hold(action: StringName) -> void:
	Input.action_press(action)


func _release(action: StringName) -> void:
	Input.action_release(action)


func _tap(action: StringName, hold_time: float = 0.06) -> void:
	Input.action_press(action)
	await p.wait_game(hold_time)
	Input.action_release(action)
	await p.get_tree().physics_frame


## Polls every physics tick (render frames are slow under software rendering).
func _tick_until(cond: Callable, timeout: float = 5.0) -> bool:
	var n := int(timeout * 60.0)
	for i in n:
		if cond.call():
			return true
		await p.get_tree().physics_frame
	return cond.call()


func _place(pos: Vector3, yaw_deg: float = 0.0) -> void:
	p.release_all()
	pl.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos))
	await p.wait_game(0.05)
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.25)


func _dummy_hits() -> int:
	var n := 0
	for d in arena.get("dummies"):
		n += (d as TrainingDummy).hits_taken
	return n


func _element(e: int) -> void:
	var el := String(ElementDefs.id_of(e))
	arena.call("switch_element", e)
	arena.call("reset_dummies")
	# Walls from the previous element would block this one's attacks.
	for c in BendingConstruct.live.duplicate():
		(c as BendingConstruct).crumble()
	pl.resources.infinite_chi = true
	var bot := arena.get("bot") as SparringBot
	bot.active = false
	await p.wait_game(0.3)
	p.note("--- %s ---" % el)

	# Run + jump + dodge.
	await _place(Vector3(0, 0, 10))
	_hold(&"move_forward")
	_hold(&"sprint")
	await p.wait_game(0.9)
	var v := Vector2(pl.velocity.x, pl.velocity.z).length()
	p.check(v > pl.motor.profile.run_speed * 0.95, "%s sprints (%.1f m/s)" % [el, v])
	await p.screenshot("%s_01_sprint" % el)
	_release(&"sprint")
	await _tap(&"jump", 0.12)
	await _tick_until(func() -> bool: return pl.velocity.y < 1.5, 1.0)
	p.check(pl.get_state() == S.AIRBORNE, "%s airborne" % el)
	await p.screenshot("%s_02_jump" % el)
	if e == ElementDefs.Element.AIR:
		await _tap(&"jump", 0.06)
		p.check(pl.motor.air_jumps_used == 1, "air double jump")
		await p.wait_game(0.2)
		_hold(&"jump")
		var glid := await _tick_until(func() -> bool: return pl.motor.gliding, 1.5)
		await p.wait_game(0.25)
		p.check(glid, "air glides (vy %.1f)" % pl.velocity.y)
		await p.screenshot("%s_02b_glide" % el)
		_release(&"jump")
	await _tick_until(func() -> bool: return pl.get_state() == S.LOCOMOTION, 3.0)
	_release(&"move_forward")
	_hold(&"move_left")
	await p.wait_game(0.1)
	await _tap(&"dodge")
	var dodged := await _tick_until(func() -> bool: return pl.get_state() == S.DODGE, 0.4)
	await p.wait_game(0.06)
	p.check(dodged, "%s dodges" % el)
	await p.screenshot("%s_03_dodge" % el)
	_release(&"move_left")
	await _tick_until(func() -> bool: return pl.get_state() == S.LOCOMOTION, 2.0)

	# Element movement trick: water skates on ice, earth wades through deep snow.
	if e == ElementDefs.Element.WATER:
		await _place(Vector3(-12, 0, 12.5))
		_hold(&"move_forward")
		_hold(&"sprint")
		await p.wait_game(1.0)
		p.check(pl.motor.skating, "water skates on ice (%.1f m/s)" % Vector2(pl.velocity.x, pl.velocity.z).length())
		await p.screenshot("%s_03b_skate" % el)
		p.release_all()
	elif e == ElementDefs.Element.EARTH:
		await _place(Vector3(-12, 0, 2.5))
		_hold(&"move_forward")
		await p.wait_game(0.8)
		await p.screenshot("%s_03b_snow" % el)
		p.release_all()

	# Light combo, a screenshot on every strike.
	await _place(Vector3(0, 0, -4.3))
	var h0 := _dummy_hits()
	var n_steps := (pl.controller.get_slot_def(&"light").params["steps"] as Array).size()
	var struck := 0
	for i in n_steps:
		await _tap(&"attack_light", 0.05)
		var ok := await _tick_until(func() -> bool:
			var c := pl.controller.current as ComboAbility
			return c != null and c.struck and c.step == i, 1.0)
		if ok:
			struck += 1
			await p.screenshot("%s_04_light_%d" % [el, i])
		await _tick_until(func() -> bool:
			var c := pl.controller.current as ComboAbility
			return c == null or c.can_chain(), 1.0)
	p.check(struck == n_steps, "%s light chain struck %d/%d" % [el, struck, n_steps])
	await p.wait_game(0.6)
	p.check(_dummy_hits() > h0, "%s light combo hit the dummies (%d)" % [el, _dummy_hits() - h0])

	# Heavy: charge + release.
	await _place(Vector3(0, 0, -2.5))
	h0 = _dummy_hits()
	_hold(&"attack_heavy")
	await p.wait_game(0.85)
	await p.screenshot("%s_05_charge" % el)
	_release(&"attack_heavy")
	# Shot while the released attack flies (or just after the release event).
	var flying := await _tick_until(func() -> bool: return _own_projectile(), 1.2)
	if not flying:
		await p.wait_game(0.1)
	await p.screenshot("%s_06_release" % el)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	await p.wait_game(0.6)
	p.check(_dummy_hits() > h0, "%s charged heavy hit (%d)" % [el, _dummy_hits() - h0])

	# Lock-on framing in an open lane (camera turned away first: the lock must
	# swing it around). The lock stays on for the duel below.
	bot.global_position = LANE_BOT
	await _place(LANE_PLAYER + Vector3(2.5, 0, 1.0), -20.0)
	await _tap(&"lock_on")
	await p.wait_game(0.9)
	var t := pl.get_lock_target()
	p.check(t == bot, "%s locks on the bot (%s)" % [el, t.name if t else "none"])
	if t != null:
		var cam := pl.camera_rig.get_camera()
		var vp := cam.get_viewport().get_visible_rect().size
		var safe := Rect2(vp * 0.05, vp * 0.9)
		var sp := cam.unproject_position(BendingContext.target_point(t))
		var pp := cam.unproject_position(pl.global_position + Vector3.UP * 1.0)
		p.check(not cam.is_position_behind(BendingContext.target_point(t)) and safe.has_point(sp) and safe.has_point(pp)
				and sp.distance_to(pp) > vp.y * 0.08,
				"%s lock-on frames player %s and target %s apart in %s" % [el, str(pp.round()), str(sp.round()), str(vp)])
	await p.screenshot("%s_07_lockon" % el)
	_hold(&"move_left")
	await p.wait_game(0.7)
	p.check(pl.get_lock_target() == bot, "%s keeps the lock while strafing" % el)
	await p.screenshot("%s_08_strafe" % el)
	_release(&"move_left")
	await _place(LANE_PLAYER + Vector3(1.2, 0, 0), -12.0)
	p.check(pl.get_lock_target() == bot, "%s lock survives a teleport" % el)
	await p.wait_game(0.5)

	# Defend against the bot's fireball (hold early -> block).
	player_results.clear()
	bot.attack_in(0.2, &"projectile")
	_hold(&"block")
	await _tick_until(func() -> bool: return bot.attacks_made > 0 and not BendingProjectile.live.is_empty(), 3.0)
	await _tick_until(func() -> bool: return _incoming_dist() < 6.5, 1.0)
	await p.screenshot("%s_09_defend" % el)
	await _tick_until(func() -> bool: return not player_results.is_empty(), 1.0)
	p.check(player_results.has(Combat.Result.BLOCKED), "%s blocks the fireball %s" % [el, str(player_results)])
	await p.wait_game(0.3)
	_release(&"block")
	bot.active = false
	await _tick_until(func() -> bool: return pl.get_state() == S.LOCOMOTION, 2.0)

	# Parry: raise the guard right before the impact (inside 0.15 s).
	await p.wait_game(0.4)
	player_results.clear()
	pl.resources.set_focus(20.0)
	var focus0 := pl.resources.focus
	var made := bot.attacks_made
	bot.attack_in(0.2, &"projectile")
	await _tick_until(func() -> bool: return bot.attacks_made > made, 3.0)
	await _tick_until(func() -> bool: return _incoming_dist() < 2.6, 1.5)
	_hold(&"block")
	await _tick_until(func() -> bool: return not player_results.is_empty(), 0.6)
	await p.screenshot("%s_10_parry" % el)
	p.check(player_results.has(Combat.Result.DEFLECTED), "%s parries %s" % [el, str(player_results)])
	p.check(pl.resources.focus >= minf(focus0 + 14.9, 99.9), "%s parry grants focus (%.0f -> %.0f)" % [el, focus0, pl.resources.focus])
	await p.wait_game(0.3)
	_release(&"block")
	bot.active = false
	await _tick_until(func() -> bool: return pl.get_state() == S.LOCOMOTION, 2.0)
	await _tap(&"lock_on")
	await p.wait_game(0.2)
	p.check(pl.get_lock_target() == null, "%s releases the lock" % el)
	bot.global_position = BOT_HOME

	# Starter technique (Air Sweep is a 4.6 m circle, the Earth Wall rises 4.5 m ahead).
	var tz := {ElementDefs.Element.AIR: -4.0, ElementDefs.Element.EARTH: -2.5}
	await _place(Vector3(0, 0, float(tz.get(e, -1.5))))
	h0 = _dummy_hits()
	await _tap(&"ability_1")
	var started := await _tick_until(func() -> bool: return pl.controller.current != null and pl.controller.current.def.slot == AbilityDef.Slot.TECHNIQUE, 0.5)
	p.check(started, "%s starter technique starts" % el)
	var shot := await _tick_until(func() -> bool: return _own_projectile(), 1.5)
	if not shot:
		await _tick_until(func() -> bool: return pl.controller.current == null or pl.controller.current.time_to_event(&"release") == INF, 1.5)
		await p.wait_game(0.15)
	await p.screenshot("%s_11_technique" % el)
	await p.wait_game(0.5)
	await p.screenshot("%s_12_technique_after" % el)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	await p.wait_game(0.5)
	p.check(_dummy_hits() > h0, "%s technique landed (%d hits)" % [el, _dummy_hits() - h0])
	p.check(pl.get_state() == S.LOCOMOTION, "%s back to locomotion (%s)" % [el, pl.get_state_name()])


func _own_projectile() -> bool:
	for proj in BendingProjectile.live:
		if is_instance_valid(proj) and proj.alive and proj.team == Combat.Team.PLAYER and proj.age > 0.04:
			return true
	return false


func _incoming_dist() -> float:
	var best := INF
	for proj in BendingProjectile.live:
		if is_instance_valid(proj) and proj.alive and proj.team != Combat.Team.PLAYER:
			best = minf(best, proj.global_position.distance_to(pl.global_position + Vector3.UP * 1.1))
	return best
