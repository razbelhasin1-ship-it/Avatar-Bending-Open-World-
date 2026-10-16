extends RefCounted
## Fire techniques in the combat arena (docs/modules/bending_fire.md): every technique at
## its anticipation / active / impact frames from the player's camera and an observer
## camera; the core kit (jab-jab-kick-roundhouse, Blaze Charge stages + explosion, Flame
## Guard + parry counter, Fire Step); braziers lit by fire and put out by a waterbender's
## whip (the generic hit hook), an ice wall melting, the snow patch steaming, the marks left.
## TECH=core,defense,burst,ring,jet,whip,inferno,lightning,env (default: all).

const E := ElementDefs.Element

var p: Playtest
var arena: Node
var pl: PlayerCharacter
var cam: Camera3D
var hits: Array = []


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(E.FIRE, true)
	arena = await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": E.FIRE})
	await p.wait_game(0.5)
	pl = p.player() as PlayerCharacter
	p.check(pl != null, "player spawned")
	(arena.get("bot") as SparringBot).active = false
	pl.resources.infinite_chi = true
	pl.camera_rig.require_capture = false
	cam = Camera3D.new()
	cam.name = "ObserverCamera"
	cam.fov = 55.0
	arena.add_child(cam)
	Events.hit_landed.connect(func(hit: HitInfo, t: Node, r: int) -> void: hits.append([hit.ability_id, t, r, hit.reaction, hit.damage]))
	var only := OS.get_environment("TECH")
	for t in ["core", "defense", "burst", "ring", "jet", "whip", "inferno", "lightning", "env"]:
		if only == "" or only.split(",").has(t):
			p.note("--- %s ---" % t)
			await call("_" + t)
	_report()


# --- helpers ---------------------------------------------------------------------------------------

func _tick_until(cond: Callable, timeout: float = 5.0) -> bool:
	for i in int(timeout * 60.0):
		if cond.call():
			return true
		await p.get_tree().physics_frame
	return cond.call()


func _place(pos: Vector3, yaw_deg: float = 0.0) -> void:
	p.release_all()
	if pl.get_lock_target() != null:
		pl.targeting.call("toggle_lock")
	for c in BendingConstruct.live.duplicate():
		(c as BendingConstruct).crumble()
	pl.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos))
	pl.controller.reset_cooldowns()
	pl.health.heal(1000.0)
	await p.wait_game(0.05)
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.35)
	arena.call("reset_dummies")


func _equip(id: StringName, slot: StringName = &"technique_1") -> void:
	var d := AbilityRegistry.get_def(id)
	pl.controller.set_slot(&"signature" if d.slot == AbilityDef.Slot.SIGNATURE else slot, d)


## Observer shot from the side of the bender looking across the action.
func _obs(shot: String, focus: Vector3, side: float = 1.0, dist: float = 7.5, height: float = 2.4) -> void:
	var a := pl.global_position + Vector3.UP * 1.0
	var f := focus - a
	f.y = 0.0
	var fwd := f.normalized() if f.length() > 0.5 else -pl.global_basis.z
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var mid := a.lerp(focus, 0.45)
	var pos := mid + right * side * dist - fwd * dist * 0.35 + Vector3.UP * height
	cam.look_at_from_position(pos, mid, Vector3.UP)
	cam.make_current()
	await p.screenshot(shot)
	pl.camera_rig.make_current()


## Close-up of a point from a compass angle (deg, 0 = from +Z).
func _close(shot: String, focus: Vector3, dist: float = 3.5, height: float = 1.2, angle_deg: float = 35.0) -> void:
	var a := deg_to_rad(angle_deg)
	cam.look_at_from_position(focus + Vector3(sin(a), 0.0, cos(a)) * dist + Vector3.UP * height, focus, Vector3.UP)
	cam.make_current()
	await p.screenshot(shot)
	pl.camera_rig.make_current()


func _hits_of(id: StringName) -> int:
	var n := 0
	for h: Array in hits:
		if h[0] == id and (h[2] == Combat.Result.HIT or h[2] == Combat.Result.KILLED):
			n += 1
	return n


func _cur_id() -> StringName:
	return pl.controller.current.def.id if pl.controller.current != null else &""


## Presses `action` until the ability `want` runs (busy / buffered presses retried).
func _cast(action: StringName, want: StringName, hold: float = 0.06) -> bool:
	for attempt in 4:
		await _tick_until(func() -> bool: return pl.states.is_free() and not pl.controller.is_busy(), 3.0)
		Input.action_press(action)
		var ok := await _tick_until(func() -> bool: return _cur_id() == want, 0.4)
		if ok:
			await p.wait_game(hold)
			Input.action_release(action)
			return true
		Input.action_release(action)
		await p.wait_game(0.2)
	return false


func _dummy(i: int) -> TrainingDummy:
	return (arena.get("dummies") as Array)[i] as TrainingDummy


func _dummies_center() -> Vector3:
	return Vector3(0, 1.0, -6.4)


# --- core kit --------------------------------------------------------------------------------------

func _core() -> void:
	await _place(Vector3(0, 0, -3.4))
	for i in 4:
		Input.action_press(&"attack_light")
		await p.wait_game(0.05)
		Input.action_release(&"attack_light")
		var ok := await _tick_until(func() -> bool:
			var c := pl.controller.current as ComboAbility
			return c != null and c.struck and c.step == i, 1.0)
		p.check(ok, "fire strike %d struck" % (i + 1))
		await p.wait_game(0.03)
		await p.screenshot("core_%d_strike" % (i + 1))
		if i == 3:
			await p.wait_game(0.04)
			await _obs("core_4_roundhouse_obs", _dummies_center(), 1.0, 6.0, 2.0)
		await _tick_until(func() -> bool:
			var c := pl.controller.current as ComboAbility
			return c == null or c.can_chain(), 1.0)
	await p.wait_game(0.6)
	p.check(_hits_of(&"fire_combo") >= 4, "fire combo hit (%d)" % _hits_of(&"fire_combo"))
	# Blaze Charge: the stages of the build-up, then the blast.
	await _place(Vector3(0, 0, 2.0))
	Input.action_press(&"attack_heavy")
	await p.wait_game(0.4)
	await _obs("blaze_1_start", pl.global_position + Vector3.UP, 1.0, 3.6, 0.6)
	await p.wait_game(0.45)
	await _obs("blaze_2_half", pl.global_position + Vector3.UP, 1.0, 3.6, 0.6)
	await p.wait_game(0.45)
	var a := pl.controller.current as ChargeAbility
	p.check(a != null and a.charge >= 0.95, "blaze charge full (%.2f)" % (a.charge if a else -1.0))
	await _obs("blaze_3_full", pl.global_position + Vector3.UP, 1.0, 3.6, 0.6)
	Input.action_release(&"attack_heavy")
	await _tick_until(func() -> bool: return BendingProjectile.live.size() > 0, 1.0)
	await p.wait_game(0.05)
	await p.screenshot("blaze_4_release")
	await _tick_until(func() -> bool: return _hits_of(&"fire_blast") > 0, 2.0)
	await p.wait_game(0.06)
	await _obs("blaze_5_explosion", _dummies_center(), -1.0, 7.0, 2.4)
	await p.wait_game(0.5)
	await _obs("blaze_6_after", _dummies_center(), -1.0, 7.0, 3.0)
	p.check(_hits_of(&"fire_blast") >= 2, "blaze explosion hit (%d)" % _hits_of(&"fire_blast"))
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)


## Flame Guard vs the bot's fireball, a parry (Fire Burst counter) and Fire Step.
func _defense() -> void:
	var bot := arena.get("bot") as SparringBot
	bot.global_position = Vector3(0, 0, -15)
	await _place(Vector3(0, 0, -8.5))
	bot.mode = &"projectile"
	bot.active = true
	Input.action_press(&"block")
	await p.wait_game(0.3)
	bot.attack_in(0.2, &"projectile")
	await p.wait_game(0.8)
	await _obs("defense_1_guard", Vector3(0, 1, -13), -1.0, 5.0, 1.6)
	await p.wait_game(0.4)
	Input.action_release(&"block")
	# Parry a melee bot attack: the Fire Burst counter.
	bot.mode = &"melee"
	bot.global_position = Vector3(0, 0, -10.2)
	var landed := [false]
	var cb := func(_kind: StringName, _in: float) -> void: landed[0] = true
	bot.telegraphed.connect(cb)
	bot.attack_in(0.1, &"melee")
	await _tick_until(func() -> bool: return landed[0], 2.0)
	bot.telegraphed.disconnect(cb)
	var parried := [false]
	var pc := func(hit: HitInfo, t: Node, r: int) -> void:
		if t == pl and r == Combat.Result.DEFLECTED:
			parried[0] = true
	Events.hit_landed.connect(pc)
	for i in 120:
		await p.get_tree().physics_frame
		if i == 20:
			Input.action_press(&"block")
		if parried[0]:
			break
	await p.wait_game(0.08)
	await _obs("defense_2_parry_burst", pl.global_position + Vector3.UP, 1.0, 5.0, 1.8)
	Input.action_release(&"block")
	Events.hit_landed.disconnect(pc)
	p.note("parry: %s" % str(parried[0]))
	bot.active = false
	bot.global_position = Vector3(0, 0, -15)
	await _place(Vector3(-2, 0, 0.0), 90.0)
	Input.action_press(&"move_left")
	await p.wait_game(0.1)
	Input.action_press(&"dodge")
	await p.wait_game(0.05)
	Input.action_release(&"dodge")
	await p.wait_game(0.12)
	await _obs("defense_3_fire_step", pl.global_position, 1.0, 5.0, 1.8)
	Input.action_release(&"move_left")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 1.5)


# --- techniques ------------------------------------------------------------------------------------

func _burst() -> void:
	await _place(Vector3(0, 0, -4.4))
	_equip(&"fire_burst")
	p.check(await _cast(&"ability_1", &"fire_burst"), "fire burst cast")
	await p.wait_game(0.12)
	await _obs("burst_1_gather", pl.global_position + Vector3.UP, 1.0, 5.0, 1.4)
	await _tick_until(func() -> bool: return _hits_of(&"fire_burst") > 0, 1.0)
	await p.wait_game(0.02)
	await _obs("burst_2_release", pl.global_position + Vector3.UP * 0.8, 1.0, 7.0, 2.2)
	await p.wait_game(0.12)
	await p.screenshot("burst_3_player_cam")
	await p.wait_game(0.5)
	await _obs("burst_4_after", pl.global_position, -1.0, 6.0, 3.0)
	p.check(_hits_of(&"fire_burst") >= 3, "fire burst knocked the three posts away (%d)" % _hits_of(&"fire_burst"))
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)


func _ring() -> void:
	await _place(Vector3(0, 0, -3.2))
	_equip(&"fire_ring")
	p.check(await _cast(&"ability_1", &"fire_ring"), "fire ring cast")
	await p.wait_game(0.15)
	await _obs("ring_1_coil", pl.global_position + Vector3.UP, 1.0, 4.5, 1.2)
	await _tick_until(func() -> bool: return not FireRingWave.live.is_empty(), 1.0)
	await p.wait_game(0.06)
	await _obs("ring_2_launch", pl.global_position, 1.0, 9.0, 4.0)
	await p.wait_game(0.12)
	await _obs("ring_3_front", pl.global_position, -1.0, 10.0, 5.0)
	await p.wait_game(0.12)
	await p.screenshot("ring_4_player_cam")
	await p.wait_game(0.9)
	await _obs("ring_5_scorched", pl.global_position, 1.0, 9.0, 6.0)
	p.check(_hits_of(&"fire_ring") >= 3, "the ring hit the posts (%d)" % _hits_of(&"fire_ring"))
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)


func _jet() -> void:
	await _place(Vector3(0, 0, 3.0))
	_equip(&"jet_step")
	var y0 := pl.global_position.y
	p.check(await _cast(&"ability_1", &"jet_step", 0.04), "jet step cast")
	await p.wait_game(0.14)
	await _obs("jet_1_crouch", pl.global_position + Vector3.UP, 1.0, 5.0, 1.0)
	await _tick_until(func() -> bool: return pl.global_position.y > y0 + 0.6, 1.0)
	await _obs("jet_2_takeoff", pl.global_position, 1.0, 6.0, 0.6)
	var peak := y0
	for i in 40:
		await p.get_tree().physics_frame
		peak = maxf(peak, pl.global_position.y)
	await p.screenshot("jet_3_player_cam")
	p.check(peak > y0 + 2.0, "jet step leap height %.1f m" % (peak - y0))
	await _tick_until(func() -> bool: return pl.motor.on_floor and not pl.controller.is_busy(), 3.0)
	# Hold: hover on the jets.
	await _place(Vector3(0, 0, 3.0))
	Input.action_press(&"ability_1")
	await p.wait_game(0.75)
	await _obs("jet_4_hover", pl.global_position, -1.0, 5.5, 0.2)
	await _close("jet_5_hover_close", pl.global_position + Vector3.UP * 0.6, 3.2, -0.6, 150.0)
	p.check(_cur_id() == &"jet_step" and pl.global_position.y > y0 + 1.5, "hovering at %.1f m" % (pl.global_position.y - y0))
	Input.action_release(&"ability_1")
	await _tick_until(func() -> bool: return pl.motor.on_floor and not pl.controller.is_busy(), 4.0)


func _whip() -> void:
	await _place(Vector3(1.0, 0, -1.5))
	_equip(&"fire_whip")
	p.check(await _cast(&"ability_1", &"fire_whip"), "fire whip cast")
	await p.wait_game(0.16)
	await _obs("whip_1_windup", pl.global_position + Vector3.UP * 1.4, 1.0, 4.5, 1.2)
	var a := pl.controller.current
	await _tick_until(func() -> bool: return a.time_to_event(&"release") == INF, 1.0)
	await p.wait_game(0.06)
	await _obs("whip_2_lash", _dummies_center(), 1.0, 7.0, 3.0)
	await _tick_until(func() -> bool: return a.time_to_event(&"impact") == INF, 1.0)
	await p.wait_game(0.02)
	await _obs("whip_3_crack", _dummies_center(), -1.0, 7.0, 2.6)
	await p.screenshot("whip_4_player_cam")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	p.check(_hits_of(&"fire_whip") >= 2, "the whip cut through the posts (%d)" % _hits_of(&"fire_whip"))


func _inferno() -> void:
	await _place(Vector3(0, 0, -3.5))
	_equip(&"inferno")
	pl.resources.mark_combat()
	pl.resources.set_focus(100.0)
	p.check(await _cast(&"ability_special", &"inferno"), "inferno cast")
	await p.wait_game(0.2)
	await _obs("inferno_1_gather", pl.global_position + Vector3.UP, 1.0, 6.0, 1.6)
	await p.wait_game(0.4)
	await _obs("inferno_2_vortex", pl.global_position + Vector3.UP * 1.6, 1.0, 9.0, 2.0)
	await p.wait_game(0.35)
	await p.screenshot("inferno_3_player_cam")
	await _tick_until(func() -> bool: return not FireRingWave.live.is_empty(), 2.0)
	await p.wait_game(0.12)
	await _obs("inferno_4_release", pl.global_position, 1.0, 14.0, 6.0)
	await p.wait_game(0.25)
	await _obs("inferno_5_ring", pl.global_position, -1.0, 15.0, 7.0)
	await p.wait_game(1.0)
	await _obs("inferno_6_after", pl.global_position, 1.0, 12.0, 8.0)
	p.check(_hits_of(&"inferno") >= 3, "the inferno launched the posts (%d)" % _hits_of(&"inferno"))
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)


func _lightning() -> void:
	await _place(Vector3(0, 0, 4.0))
	_equip(&"lightning")
	pl.targeting.call("toggle_lock")
	await p.wait_game(0.2)
	await _tick_until(func() -> bool: return pl.states.is_free(), 2.0)
	Input.action_press(&"ability_1")
	await p.wait_game(0.5)
	await _close("lightning_1_kata", pl.global_position + Vector3.UP * 1.2, 3.4, 0.4, 40.0)
	await p.wait_game(1.2)
	await _close("lightning_2_charged", pl.global_position + Vector3.UP * 1.2, 3.4, 0.4, 40.0)
	Input.action_release(&"ability_1")
	await _tick_until(func() -> bool: return _hits_of(&"lightning") > 0, 1.5)
	await p.wait_game(0.02)
	await _obs("lightning_3_bolt", _dummies_center(), 1.0, 8.0, 2.4)
	await p.screenshot("lightning_4_player_cam")
	p.check(_hits_of(&"lightning") >= 1, "lightning struck (%d)" % _hits_of(&"lightning"))
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	if pl.get_lock_target() != null:
		pl.targeting.call("toggle_lock")


# --- environment -----------------------------------------------------------------------------------

func _env() -> void:
	# Braziers and a torch, unlit, along the left of the courtyard.
	var props: Array[FireBrazier] = []
	for k: Array in [[&"brazier", Vector3(-4.5, 0, 6.0)], [&"torch", Vector3(-2.0, 0, 7.5)], [&"lantern", Vector3(0.6, 0, 7.5)], [&"brazier", Vector3(3.0, 0, 6.5)]]:
		var b := FireBrazier.new()
		b.kind = k[0]
		arena.add_child(b)
		b.global_position = k[1]
		props.append(b)
	await _place(Vector3(-0.6, 0, 1.0), 180.0)
	await _obs("env_1_unlit", Vector3(-0.6, 1.0, 6.8), 1.0, 6.0, 1.6)
	# Fire Ring lights every one within reach.
	_equip(&"fire_ring")
	p.check(await _cast(&"ability_1", &"fire_ring"), "ring cast")
	await p.wait_game(1.2)
	var lit := props.filter(func(b: FireBrazier) -> bool: return b.is_burning()).size()
	await _obs("env_2_lit", Vector3(-0.6, 1.0, 6.8), 1.0, 6.0, 1.8)
	p.check(lit >= 3, "fire lit the braziers (%d / %d)" % [lit, props.size()])
	# A waterbender's whip puts one out (generic hit hook, no change to the water kit).
	arena.call("switch_element", E.WATER)
	await p.wait_game(0.4)
	pl = p.player() as PlayerCharacter
	pl.resources.infinite_chi = true
	await _place(props[0].global_position + Vector3(0, 0, -3.4), 180.0)
	Input.action_press(&"attack_light")
	await p.wait_game(0.05)
	Input.action_release(&"attack_light")
	await _tick_until(func() -> bool: return not props[0].is_burning(), 1.5)
	await p.wait_game(0.1)
	await _close("env_3_doused", props[0].flame_point(), 3.0, 0.6, 200.0)
	p.check(not props[0].is_burning(), "the water whip put the brazier out")
	arena.call("switch_element", E.FIRE)
	await p.wait_game(0.4)
	pl = p.player() as PlayerCharacter
	pl.resources.infinite_chi = true
	# An enemy's ice wall melts under a Blaze Charge; the snow patch steams.
	var foe := BendingContext.new(arena.get("bot"), null, E.WATER, Combat.Team.ENEMY)
	var wall := BendingConstruct.raise(foe, Vector3(-12.0, 0, -10.0), Vector3(0, 0, 1), {"kind": &"ice", "size": Vector3(4.0, 2.6, 0.9), "hp": 220.0, "lifetime": 30.0})
	await _place(Vector3(-12.0, 0, -2.0), 0.0)
	await p.wait_game(0.4)
	Input.action_press(&"attack_heavy")
	await p.wait_game(1.4)
	Input.action_release(&"attack_heavy")
	await p.wait_game(0.6)
	await _obs("env_4_ice_melting", wall.global_position + Vector3.UP * 1.3, -1.0, 6.0, 1.8)
	p.check(not is_instance_valid(wall) or wall.hp < 220.0, "the ice wall melts (%.0f)" % (wall.hp if is_instance_valid(wall) else 0.0))
	await _place(Vector3(-12.0, 0, 1.0), 0.0)
	_equip(&"fire_burst")
	p.check(await _cast(&"ability_1", &"fire_burst"), "burst on the snow")
	await p.wait_game(0.5)
	await _obs("env_5_snow_steam", pl.global_position, 1.0, 6.0, 2.0)
	await p.wait_game(0.6)
	await _obs("env_6_marks", Vector3(-1, 0, -4), -1.0, 10.0, 7.0)


func _report() -> void:
	var by := {}
	for h: Array in hits:
		if h[2] == Combat.Result.HIT or h[2] == Combat.Result.KILLED:
			var k := String(h[0])
			by[k] = int(by.get(k, 0)) + 1
	p.note("hits by ability: %s" % str(by))
	p.note("fire env: ignited %d, extinguished %d, melted %d, steamed %d, marks %d, grass cells %d" % [FireEnv.ignited, FireEnv.extinguished,
			FireEnv.melted, FireEnv.steamed, FireMarks.spawned, GrassFire.cells_lit])
