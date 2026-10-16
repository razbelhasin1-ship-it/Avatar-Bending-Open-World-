extends RefCounted
## Water techniques in the combat arena (docs/modules/bending_water.md): every
## technique with screenshots at its anticipation / active / impact frames,
## from the player's camera and an observer camera framing bender + targets;
## water drawn from the pool and from the snow patch, an ice floe on the pool,
## a fire put out, the core kit (whip chain, torrent charge, shield, slide).
## TECH=core,defense,shards,surge,wall,trap,wave,jet,heal,tidal,env (default: all).

const E := ElementDefs.Element
const POOL_C := Vector3(12.5, 0, -0.5)

var p: Playtest
var arena: Node
var pl: PlayerCharacter
var cam: Camera3D
var hits: Array = []


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(E.WATER, true)
	arena = await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": E.WATER})
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
	Events.hit_landed.connect(func(hit: HitInfo, t: Node, r: int) -> void: hits.append([hit.ability_id, t, r]))
	var only := OS.get_environment("TECH")
	for t in ["core", "defense", "shards", "surge", "wall", "trap", "wave", "jet", "heal", "tidal", "env"]:
		if only == "" or only.split(",").has(t):
			p.note("--- %s ---" % t)
			await call("_" + t)


# --- helpers ---------------------------------------------------------------------------------------

func _tick_until(cond: Callable, timeout: float = 5.0) -> bool:
	for i in int(timeout * 60.0):
		if cond.call():
			return true
		await p.get_tree().physics_frame
	return cond.call()


func _place(pos: Vector3, yaw_deg: float = 0.0) -> void:
	p.release_all()
	for c in BendingConstruct.live.duplicate():
		(c as BendingConstruct).crumble()
	pl.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos))
	pl.controller.reset_cooldowns()
	await p.wait_game(0.05)
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.3)
	arena.call("reset_dummies")


func _equip(id: StringName) -> void:
	var d := AbilityRegistry.get_def(id)
	pl.controller.set_slot(&"signature" if d.slot == AbilityDef.Slot.SIGNATURE else &"technique_1", d)


## Observer shot: from the side of the bender, looking across the action.
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


func _hits_of(id: StringName) -> int:
	var n := 0
	for h: Array in hits:
		if h[0] == id and (h[2] == Combat.Result.HIT or h[2] == Combat.Result.KILLED):
			n += 1
	return n


func _cur() -> BendingAbility:
	return pl.controller.current


# --- core kit --------------------------------------------------------------------------------------

func _core() -> void:
	await _place(Vector3(0, 0, -1.8))
	for i in 3:
		Input.action_press(&"attack_light")
		await p.wait_game(0.05)
		Input.action_release(&"attack_light")
		var ok := await _tick_until(func() -> bool:
			var c := pl.controller.current as ComboAbility
			return c != null and c.struck and c.step == i, 1.0)
		p.check(ok, "whip lash %d struck" % (i + 1))
		await p.screenshot("core_whip_%d" % (i + 1))
		await _tick_until(func() -> bool:
			var c := pl.controller.current as ComboAbility
			return c == null or c.can_chain(), 1.0)
	await p.wait_game(0.5)
	p.check(_hits_of(&"water_whip") >= 3, "whip chain hit (%d)" % _hits_of(&"water_whip"))
	# Torrent: hold to gather (ring around the body), release.
	await _place(Vector3(0, 0, 0.5))
	Input.action_press(&"attack_heavy")
	await p.wait_game(0.9)
	await _obs("core_torrent_charge", Vector3(0, 1, -6), 1.0, 5.0, 1.6)
	await p.wait_game(0.45)
	await p.screenshot("core_torrent_full")
	Input.action_release(&"attack_heavy")
	await _tick_until(func() -> bool: return BendingProjectile.live.size() > 0, 1.0)
	await p.wait_game(0.08)
	await p.screenshot("core_torrent_release")
	await _obs("core_torrent_release_side", Vector3(0, 1, -6), 1.0, 7.0, 2.0)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)


## Water Shield blocking the bot's fireball, a parry, and Flow Slide spraying snow.
func _defense() -> void:
	var bot := arena.get("bot") as SparringBot
	bot.global_position = Vector3(-11, 0, -18)
	await _place(Vector3(-11, 0, -11))
	bot.mode = &"projectile"
	bot.active = true
	Input.action_press(&"block")
	await p.wait_game(0.3)
	bot.attack_in(0.2, &"projectile")
	await p.wait_game(0.75)
	await _obs("defense_1_shield", Vector3(-11, 1, -15), -1.0, 5.0, 1.6)
	await p.wait_game(0.5)
	Input.action_release(&"block")
	# Parry: raise the shield just before the bolt lands.
	var landed := [false]
	var cb := func(kind: StringName, _in: float) -> void: landed[0] = true
	bot.telegraphed.connect(cb)
	bot.attack_in(0.1, &"projectile")
	await _tick_until(func() -> bool: return landed[0], 2.0)
	bot.telegraphed.disconnect(cb)
	await p.wait_game(0.55)
	Input.action_press(&"block")
	await p.wait_game(0.25)
	await p.screenshot("defense_2_parry")
	Input.action_release(&"block")
	bot.active = false
	bot.global_position = Vector3(0, 0, -15)
	# Flow Slide across the snow patch.
	await _place(Vector3(-12, 0, -1.0), 90.0)
	Input.action_press(&"move_left")
	await p.wait_game(0.1)
	Input.action_press(&"dodge")
	await p.wait_game(0.05)
	Input.action_release(&"dodge")
	await p.wait_game(0.15)
	await _obs("defense_3_slide_snow", pl.global_position, 1.0, 5.0, 1.6)
	Input.action_release(&"move_left")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 1.5)


## Ice Shards: drawn from the pool, frozen into daggers, thrown; a soaked dummy flash-freezes.
func _shards() -> void:
	_equip(&"ice_shards")
	await _place(Vector3(6.5, 0, -4.5))
	var target := arena.get("dummies")[3] as TrainingDummy
	WaterStatus.soak(target, 20.0)
	var froze := [false]
	var on_hit := func(hit: HitInfo, _r: int) -> void:
		if hit.reaction == HitInfo.Reaction.FREEZE:
			froze[0] = true
	target.hit_received.connect(on_hit)
	pl.targeting.call("toggle_lock")
	await p.wait_game(0.2)
	Input.action_press(&"ability_1")
	await p.wait_game(0.05)
	Input.action_release(&"ability_1")
	await p.wait_game(0.3)
	await _obs("shards_1_form", target.global_position + Vector3.UP, 1.0, 4.0, 1.4)
	await _tick_until(func() -> bool: return BendingProjectile.live.size() > 0, 1.0)
	await p.wait_game(0.05)
	await _obs("shards_2_flight", target.global_position + Vector3.UP, 1.0, 5.0, 1.6)
	await _tick_until(func() -> bool: return froze[0], 1.5)
	await p.wait_game(0.05)
	await _obs("shards_3_flash_freeze", target.global_position + Vector3.UP, -1.0, 3.5, 1.2)
	p.check(froze[0], "soaked dummy flash-frozen by the shards")
	target.hit_received.disconnect(on_hit)
	if pl.get_lock_target() != null:
		pl.targeting.call("toggle_lock")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)


# --- techniques ------------------------------------------------------------------------------------

func _surge() -> void:
	_equip(&"water_surge")
	await _place(Vector3(0, 0, 1.5))
	Input.action_press(&"ability_1")
	await p.wait_game(0.06)
	Input.action_release(&"ability_1")
	await _tick_until(func() -> bool: return _cur() != null and _cur().time > 0.18, 1.0)
	await _obs("surge_1_scoop", Vector3(0, 1, -5), 1.0, 6.0, 1.6)
	await _tick_until(func() -> bool: return _cur() == null or _cur().get("_mass") != null, 1.5)
	await p.wait_game(0.18)
	await _obs("surge_2_overhead", Vector3(0, 1, -5), 1.0, 6.0, 1.8)
	await p.screenshot("surge_2_overhead_player")
	await _tick_until(func() -> bool: return _cur() == null or _cur().get("runner") != null, 1.5)
	await p.wait_game(0.12)
	await p.screenshot("surge_3_wave")
	await _obs("surge_3_wave_side", Vector3(0, 1, -6), 1.0, 8.0, 2.4)
	await p.wait_game(0.18)
	await p.screenshot("surge_4_impact")
	await p.wait_game(0.6)
	p.check(_hits_of(&"water_surge") >= 1, "surge hit the post in its path (%d)" % _hits_of(&"water_surge"))
	await p.screenshot("surge_5_after")


func _wall() -> void:
	_equip(&"ice_wall")
	var bot := arena.get("bot") as SparringBot
	bot.global_position = Vector3(-11, 0, -18)
	await _place(Vector3(-11, 0, -8))
	Input.action_press(&"ability_1")
	await p.wait_game(0.05)
	Input.action_release(&"ability_1")
	await _tick_until(func() -> bool: return _cur() == null or _cur().time > 0.2, 1.0)
	await _obs("wall_1_lift", Vector3(-11, 1, -12), -1.0, 6.0, 1.8)
	await _tick_until(func() -> bool: return _cur() == null or _cur().get("wall") != null, 1.5)
	await p.wait_game(0.08)
	await p.screenshot("wall_2_rising")
	await p.wait_game(0.3)
	await _obs("wall_3_standing", Vector3(-11, 1, -12), -1.0, 7.0, 2.2)
	var w: BendingConstruct = BendingConstruct.live.back() if not BendingConstruct.live.is_empty() else null
	p.check(w != null and w.kind == &"ice", "ice wall stands")
	# The bot's fireball melts into the wall.
	bot.active = true
	bot.mode = &"projectile"
	bot.attack_in(0.1, &"projectile")
	await p.wait_game(1.0)
	bot.active = false
	await p.screenshot("wall_4_fireball_blocked")
	if w != null and w.is_alive():
		var h := bot.get_bending_context().make_hit({"damage": 500.0, "heavy": true}, Vector3.BACK, HitInfo.new_attack_id(), &"test")
		Combat.deal(w, h)
		await p.wait_game(0.08)
		await _obs("wall_5_shatter", Vector3(-11, 1, -12), -1.0, 7.0, 2.0)
	bot.global_position = Vector3(0, 0, -15)


func _trap() -> void:
	_equip(&"ice_trap")
	await _place(Vector3(6.5, 0, -1.0))
	var target := arena.get("dummies")[3] as TrainingDummy
	pl.targeting.call("toggle_lock")
	await p.wait_game(0.3)
	Input.action_press(&"ability_1")
	await p.wait_game(0.05)
	Input.action_release(&"ability_1")
	await _tick_until(func() -> bool: return _cur() == null or _cur().get("_released"), 1.0)
	await p.wait_game(0.1)
	await _obs("trap_1_snake", target.global_position + Vector3.UP, 1.0, 6.5, 2.2)
	await _tick_until(func() -> bool: return target.hits_taken > 0, 1.5)
	await p.wait_game(0.1)
	await p.screenshot("trap_2_frozen")
	await _obs("trap_2_frozen_side", target.global_position + Vector3.UP, -1.0, 4.0, 1.6)
	p.check(target.last_hit != null and target.last_hit.reaction == HitInfo.Reaction.FREEZE, "dummy frozen")
	if pl.get_lock_target() != null:
		pl.targeting.call("toggle_lock")


func _wave() -> void:
	_equip(&"water_wave")
	# Ride east across the courtyard and out over the pool.
	await _place(Vector3(0.0, 0, -0.5), -90.0)
	Input.action_press(&"ability_1")
	await p.wait_game(0.3)
	await _obs("wave_1_ride", pl.global_position + Vector3(3, 0, 0), 1.0, 6.0, 1.6)
	await p.wait_game(0.2)
	await p.screenshot("wave_2_ride_player")
	await p.wait_game(0.35)
	await _obs("wave_3_over_water", pl.global_position + Vector3(2, 0, 0), -1.0, 6.5, 2.0)
	Input.action_release(&"ability_1")
	await _tick_until(func() -> bool: return _cur() == null or _cur().get("_released"), 1.0)
	await p.wait_game(0.15)
	await p.screenshot("wave_4_crash")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	await p.wait_game(0.5)
	await _obs("wave_5_floe", pl.global_position, 1.0, 6.0, 3.0)
	p.check(not pl.motor.swimming, "landed dry after the ride (y %.2f)" % pl.global_position.y)


func _jet() -> void:
	_equip(&"water_jet")
	await _place(Vector3(6.5, 0, -2.5))
	Input.action_press(&"ability_1")
	await _tick_until(func() -> bool: return _cur() == null or _cur().get("jetting"), 1.0)
	await p.wait_game(0.4)
	await p.screenshot("jet_1_player")
	await _obs("jet_2_side", Vector3(6.5, 1.2, -9), -1.0, 6.0, 1.8)
	await p.wait_game(0.6)
	Input.action_release(&"ability_1")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	p.check(_hits_of(&"water_jet") >= 3, "jet hit repeatedly (%d)" % _hits_of(&"water_jet"))


func _heal() -> void:
	_equip(&"healing_waters")
	await _place(Vector3(8.0, 0, 0.0), 90.0)
	pl.health.apply_damage(60.0)
	var h0 := pl.health.health
	Input.action_press(&"ability_1")
	await _tick_until(func() -> bool: return _cur() == null or _cur().get("glowing"), 1.5)
	await p.wait_game(0.6)
	# From the front: the glowing water in the hands.
	var front := pl.global_position - pl.global_basis.z * 2.4 + pl.global_basis.x * 0.9 + Vector3.UP * 1.5
	cam.look_at_from_position(front, pl.global_position + Vector3.UP * 1.05, Vector3.UP)
	cam.make_current()
	await p.screenshot("heal_1_glow")
	pl.camera_rig.make_current()
	await p.wait_game(2.0)
	await p.screenshot("heal_2_player")
	Input.action_release(&"ability_1")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	p.check(pl.health.health > h0 + 15.0, "healed %.0f" % (pl.health.health - h0))


func _tidal() -> void:
	_equip(&"tidal_torrent")
	await _place(Vector3(0, 0, -2.0))
	pl.resources.mark_combat()
	pl.resources.set_focus(100.0)
	Input.action_press(&"ability_special")
	await p.wait_game(0.05)
	Input.action_release(&"ability_special")
	await _tick_until(func() -> bool: return _cur() != null and _cur().time > 0.3, 1.0)
	await _obs("tidal_1_gather", Vector3(0, 1, -6), 1.0, 9.0, 2.4)
	await _tick_until(func() -> bool: return _cur() == null or _cur().get("phase") == 1, 2.0)
	await p.wait_game(0.6)
	await _obs("tidal_2_vortex", Vector3(0, 2, -6), 1.0, 11.0, 3.0)
	await p.screenshot("tidal_2_vortex_player")
	await _tick_until(func() -> bool: return _cur() == null or _cur().get("phase") == 2, 2.0)
	await p.wait_game(0.15)
	await _obs("tidal_3_crash", Vector3(0, 1, -7), 1.0, 12.0, 4.0)
	await p.wait_game(0.25)
	await p.screenshot("tidal_4_crash_player")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	p.check(_hits_of(&"tidal_torrent") >= 3, "tidal torrent hit the dummies (%d)" % _hits_of(&"tidal_torrent"))


## Environment: water pulled from the pool, snow pulled up on the snow patch,
## an ice floe frozen on the pool, a brazier put out.
func _env() -> void:
	_equip(&"water_surge")
	await _place(Vector3(7.0, 0, 6.0), 180.0)
	Input.action_press(&"ability_1")
	await p.wait_game(0.05)
	Input.action_release(&"ability_1")
	await p.wait_game(0.22)
	await _obs("env_1_pool_draw", POOL_C + Vector3(0, 1, 0), -1.0, 8.0, 3.0)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	await _place(Vector3(-12, 0, -1.0), 0.0)
	pl.controller.reset_cooldowns()
	Input.action_press(&"ability_1")
	await p.wait_game(0.05)
	Input.action_release(&"ability_1")
	await p.wait_game(0.25)
	await _obs("env_2_snow_draw", Vector3(-12, 1, -4), 1.0, 6.0, 2.0)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	# Brazier put out by the wave.
	var fire := ExtinguishableFire.new()
	fire.relight_time = 0.0
	fire.size = 0.45
	arena.add_child(fire)
	fire.global_position = Vector3(1.5, 1.0, -4.5)
	await _place(Vector3(0, 0, 2.0))
	await p.wait_game(0.3)
	await _obs("env_3_fire_before", fire.global_position, 1.0, 6.0, 1.6)
	Input.action_press(&"ability_1")
	await p.wait_game(0.05)
	Input.action_release(&"ability_1")
	await _tick_until(func() -> bool: return not fire.is_burning(), 3.0)
	await p.wait_game(0.1)
	await _obs("env_4_fire_out", fire.global_position, 1.0, 6.0, 1.6)
	p.check(not fire.is_burning(), "the wave put the fire out")
	# Ice floe on the pool.
	_equip(&"ice_trap")
	await _place(Vector3(8.0, 0, 6.0), 210.0)
	var ctx := pl.get_bending_context()
	var floe := WaterEnv.freeze_floe(ctx, POOL_C, 2.4, 20.0)
	await p.wait_game(0.6)
	p.check(floe != null, "floe frozen on the pool")
	pl.teleport(Transform3D(Basis.IDENTITY, POOL_C + Vector3.UP * 0.6))
	await p.wait_game(0.8)
	await _obs("env_5_floe", POOL_C, 1.0, 6.0, 3.0)
	p.check(not pl.motor.swimming and pl.motor.on_floor, "standing on the floe")
