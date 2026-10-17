extends RefCounted
## Air techniques in the combat arena (docs/modules/bending_air.md): every technique at
## its anticipation / active / impact frames from the player's camera and an observer
## camera. Core kit (palm, hook kick, double palm; tap + charged Air Blast; shield parry
## vs the bot; dash), aerial play (hang-time combo, double air dash, Gale Drop), Air
## Push, Wind Blade, Air Scooter (ride, wall run, pool, jump off), Vortex Ward catching
## fireballs, Air Tornado lifting sparring dummies, and the environment (a garden patch
## with real vegetation / grass / a banner / pots / torches, the snow patch).
## TECH=core,aerial,push,blade,scooter,ward,tornado,env (default: all).

const E := ElementDefs.Element

var p: Playtest
var arena: Node
var pl: PlayerCharacter
var cam: Camera3D
var hits: Array = []
var extra_dummies: Array[TrainingDummy] = []


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(E.AIR, true)
	arena = await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": E.AIR})
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
	for t in ["core", "aerial", "push", "blade", "scooter", "ward", "tornado", "env"]:
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
	# attack_in() wakes the bot; each section starts with it idle again.
	(arena.get("bot") as SparringBot).active = false
	if pl.get_lock_target() != null:
		pl.targeting.call("toggle_lock")
	pl.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos))
	pl.controller.reset_cooldowns()
	pl.health.heal(1000.0)
	pl.resources.set_focus(100.0)
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


func _sparring(pos: Vector3, preset: StringName = &"earth_soldier") -> TrainingDummy:
	var d := TrainingDummy.new()
	d.look = &"humanoid"
	d.preset = preset
	d.max_health = 5000.0
	arena.add_child(d)
	d.global_position = pos
	d.home = d.global_transform
	extra_dummies.append(d)
	return d


func _clear_extra() -> void:
	for d in extra_dummies:
		if is_instance_valid(d):
			d.queue_free()
	extra_dummies.clear()


# --- core kit --------------------------------------------------------------------------------------

func _core() -> void:
	await _place(Vector3(0, 0, -3.0))
	var names := ["palm", "hook_kick", "double_palm"]
	for i in 3:
		Input.action_press(&"attack_light")
		await p.wait_game(0.04)
		Input.action_release(&"attack_light")
		var ok := await _tick_until(func() -> bool:
			var c := pl.controller.current as ComboAbility
			return c != null and c.struck and c.step == i, 1.0)
		p.check(ok, "combo step %d struck" % (i + 1))
		await p.wait_game(0.05)
		await _obs("core_%d_%s" % [i + 1, names[i]], _dummy(1).global_position + Vector3.UP, 1.0, 5.5, 1.8)
		await _tick_until(func() -> bool:
			var c := pl.controller.current as ComboAbility
			return c == null or c.can_chain(), 1.0)
	await p.wait_game(0.3)
	p.check(_hits_of(&"air_combo") >= 3, "combo hits landed (%d)" % _hits_of(&"air_combo"))
	await p.screenshot("core_combo_player_view")
	# Air Blast: tap, then a full charge.
	await _place(Vector3(0, 0, -1.0))
	p.check(await _cast(&"attack_heavy", &"air_blast", 0.04), "tap blast")
	await p.wait_game(0.2)
	await _obs("core_blast_tap", _dummy(1).global_position + Vector3.UP, -1.0, 6.0, 2.0)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	await _place(Vector3(0, 0, -1.0))
	Input.action_press(&"attack_heavy")
	await p.wait_game(1.3)
	await _close("core_blast_charge", pl.global_position + Vector3.UP * 1.2, 3.0, 0.3, 30.0)
	Input.action_release(&"attack_heavy")
	await p.wait_game(0.22)
	await _obs("core_blast_release", _dummy(1).global_position + Vector3.UP, 1.0, 7.0, 2.2)
	await p.wait_game(0.6)
	# Shield parry vs the bot's fireball.
	var bot := arena.get("bot") as SparringBot
	await _place(Vector3(0, 0, -9.0))
	bot.attack_in(0.4, &"projectile")
	var parried := [false]  # lambdas capture locals by value: share an array
	var cb := func(hit: HitInfo, t: Node, r: int) -> void:
		if r == Combat.Result.DEFLECTED and t == pl:
			parried[0] = true
	Events.hit_landed.connect(cb)
	# Raise the guard ~0.07 s before the fireball arrives (the parry window is 0.15 s).
	for i in 200:
		await p.get_tree().physics_frame
		var inc := BendingProjectile.incoming(pl.get_aim_point(), 6.0, pl.team)
		if inc.size() > 0:
			var fb := inc[0]
			var eta := (fb.global_position.distance_to(pl.get_aim_point()) - 0.8) / maxf(fb.velocity.length(), 1.0)
			if eta < 0.07:
				Input.action_press(&"block")
				break
	await p.wait_game(0.08)
	await _obs("core_shield_parry", pl.global_position + Vector3(0, 1.2, -3.0), 1.0, 5.0, 1.6)
	await p.wait_game(0.4)
	Input.action_release(&"block")
	Events.hit_landed.disconnect(cb)
	p.check(parried[0], "shield parry turned the fireball")
	await p.wait_game(0.3)
	# Air Dash.
	await _place(Vector3(-4, 0, 6.0), 90.0)
	Input.action_press(&"move_left")
	await p.wait_game(0.05)
	await _cast(&"dodge", &"air_dash")
	await p.wait_game(0.1)
	await _obs("core_dash", pl.global_position + Vector3(-3, 1, 0), 1.0, 6.0, 1.8)
	Input.action_release(&"move_left")
	await p.wait_game(0.5)


# --- aerial ----------------------------------------------------------------------------------------

func _aerial() -> void:
	await _place(Vector3(0, 0, -3.2))
	Input.action_press(&"jump")
	await p.wait_game(0.08)
	Input.action_release(&"jump")
	await _tick_until(func() -> bool: return pl.velocity.y < 1.5, 1.5)
	var y0 := pl.global_position.y
	for i in 3:
		Input.action_press(&"attack_light")
		await p.wait_game(0.04)
		Input.action_release(&"attack_light")
		await _tick_until(func() -> bool:
			var c := pl.controller.current as ComboAbility
			return c != null and c.struck and c.step == i, 1.0)
		if i == 1:
			await _obs("aerial_combo_hang", _dummy(1).global_position + Vector3.UP, 1.0, 6.0, 1.2)
		await _tick_until(func() -> bool:
			var c := pl.controller.current as ComboAbility
			return c == null or c.can_chain(), 1.0)
	p.check(pl.global_position.y > y0 - 0.8, "aerial strikes hang in the air (%.2f -> %.2f)" % [y0, pl.global_position.y])
	await _tick_until(func() -> bool: return pl.is_on_floor(), 3.0)
	# Jump, air jump, two air dashes, glide.
	await _place(Vector3(-8, 0, 8.0), 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	await p.wait_game(0.1)
	Input.action_release(&"jump")
	await p.wait_game(0.4)
	Input.action_press(&"jump")
	await p.wait_game(0.06)
	Input.action_release(&"jump")
	await p.wait_game(0.25)
	await _cast(&"dodge", &"air_dash")
	await p.wait_game(0.12)
	await _obs("aerial_dash_1", pl.global_position + Vector3(0, 0, -3), 1.0, 7.0, 0.5)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 1.0)
	await _cast(&"dodge", &"air_dash")
	await p.wait_game(0.15)
	Input.action_press(&"jump")
	p.check(await _tick_until(func() -> bool: return pl.motor.gliding, 1.5), "gliding after the air dashes")
	await p.wait_game(0.35)
	await _obs("aerial_glide", pl.global_position + Vector3(0, -0.5, -3), -1.0, 6.0, 1.0)
	Input.action_release(&"jump")
	Input.action_release(&"move_forward")
	await _tick_until(func() -> bool: return pl.is_on_floor(), 3.0)
	# Gale Drop onto the dummies.
	await _place(Vector3(0, 0, -3.0))
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 7.5, -4.5)))
	await p.wait_game(0.15)
	p.check(await _cast(&"attack_heavy", &"air_blast", 0.04), "gale drop")
	await p.wait_game(0.12)
	await _obs("aerial_drop_dive", pl.global_position + Vector3(0, -3, -1.0), 1.0, 8.0, 0.0)
	await _tick_until(func() -> bool: return pl.is_on_floor(), 2.0)
	await p.wait_game(0.08)
	await _obs("aerial_drop_slam", pl.global_position + Vector3(0, 0.5, -1.5), 1.0, 7.0, 2.6)
	await p.wait_game(0.8)


# --- techniques --------------------------------------------------------------------------------------

func _push() -> void:
	await _place(Vector3(0, 0, -4.4))
	var s1 := _sparring(Vector3(-2.2, 0, -3.4))
	var s2 := _sparring(Vector3(2.0, 0, -5.8))
	await p.wait_game(0.3)
	_equip(&"air_push")
	Input.action_press(&"ability_1")
	await p.wait_game(0.7)
	await _close("push_gather", pl.global_position + Vector3.UP * 1.1, 3.2, 0.2, 20.0)
	Input.action_release(&"ability_1")
	await _tick_until(func() -> bool:
		var a := pl.controller.current as ChargeAbility
		return a != null and a.released, 1.0)
	await p.wait_game(0.06)
	await _obs("push_release", pl.global_position + Vector3(0, 0.5, -1.5), 1.0, 8.0, 3.6)
	await p.wait_game(0.12)
	await _obs("push_impact", pl.global_position + Vector3(0, 0.5, -1.5), -1.0, 8.5, 3.0)
	await p.wait_game(0.5)
	p.check(_hits_of(&"air_push") >= 3, "push hit the ring (%d)" % _hits_of(&"air_push"))
	await p.screenshot("push_player_view_after")
	await p.wait_game(1.2)
	_clear_extra()


func _blade() -> void:
	await _place(Vector3(0, 0, 2.0))
	var line := [_sparring(Vector3(0.4, 0, -4.0), &"bandit"), _sparring(Vector3(-0.6, 0, -8.0), &"bandit")]
	await p.wait_game(0.3)
	_equip(&"wind_blade")
	Input.action_press(&"ability_1")
	await _tick_until(func() -> bool: return _cur_id() == &"wind_blade", 0.5)
	Input.action_release(&"ability_1")
	await p.wait_game(0.12)
	await _obs("blade_kick_spin", pl.global_position + Vector3(0, 1.0, -2.0), 1.0, 5.0, 1.0)
	await _tick_until(func() -> bool:
		var a := pl.controller.current
		return a != null and bool(a.get("_fired")), 1.0)
	await p.wait_game(0.04)
	await _obs("blade_release", pl.global_position + Vector3(0, 1.0, -3.0), 1.0, 6.0, 1.6)
	await p.wait_game(0.08)
	await _obs("blade_flight", pl.global_position + Vector3(0, 1.0, -6.0), -1.0, 7.0, 2.2)
	await p.wait_game(0.6)
	p.check(_hits_of(&"wind_blade") >= 2, "blade cut through both (%d)" % _hits_of(&"wind_blade"))
	# Aerial blade.
	await _place(Vector3(0, 0, 2.0))
	Input.action_press(&"jump")
	await p.wait_game(0.08)
	Input.action_release(&"jump")
	await p.wait_game(0.35)
	p.check(await _cast(&"ability_1", &"wind_blade"), "aerial blade")
	await _tick_until(func() -> bool:
		var a := pl.controller.current
		return a != null and bool(a.get("_fired")), 1.0)
	await p.wait_game(0.03)
	await _obs("blade_air_axe", pl.global_position + Vector3(0, -0.2, -3.0), 1.0, 6.0, 0.6)
	await p.wait_game(1.0)
	_clear_extra()


func _scooter() -> void:
	# A tall wall to run up (the arena's own walls are knee high).
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(10, 8, 1)
	cs.shape = bs
	wall.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	mi.material_override = ToonMaterials.make(Color(0.6, 0.55, 0.5))
	wall.add_child(mi)
	arena.add_child(wall)
	wall.global_position = Vector3(0, 4.0, -22.0)
	# Lane between the dummies and clear of the pillars.
	await _place(Vector3(-1.6, 0, 10.0), 0.0)
	_equip(&"air_scooter", &"technique_3")
	Input.action_press(&"move_forward")
	await p.wait_game(0.2)
	p.check(await _cast(&"ability_3", &"air_scooter"), "mounted the scooter")
	await p.wait_game(0.25)
	await _close("scooter_mount", pl.global_position + Vector3.UP * 0.9, 3.6, 0.4, 60.0)
	await p.wait_game(0.5)
	var spd := Vector2(pl.velocity.x, pl.velocity.z).length()
	p.check(spd > 14.0, "riding fast (%.1f m/s)" % spd)
	await _obs("scooter_ride", pl.global_position + Vector3(0, 0.8, -4.0), 1.0, 6.0, 1.4)
	# Carve toward the far wall and run up it.
	await _tick_until(func() -> bool:
		var a := pl.controller.current
		return a == null or int(a.get("phase")) == 1, 3.0)
	var wall_z := pl.global_position.z
	await p.wait_game(0.25)
	await _obs("scooter_wall_run", pl.global_position + Vector3(0, 0.5, -0.5), 1.0, 7.0, 0.0)
	var top_y := pl.global_position.y
	for i in 30:
		await p.get_tree().physics_frame
		top_y = maxf(top_y, pl.global_position.y)
	p.check(top_y > 3.0 and wall_z < -19.0, "ran up the wall (%.1f m, from z %.1f)" % [top_y, wall_z])
	Input.action_release(&"move_forward")
	# Coasting: the ball hovers in place until the technique is pressed again (hop down).
	await p.wait_game(0.6)
	if pl.controller.current != null and pl.controller.current.def.id == &"air_scooter":
		Input.action_press(&"ability_3")
		await p.wait_game(0.08)
		Input.action_release(&"ability_3")
	await _tick_until(func() -> bool: return pl.is_on_floor() and not pl.controller.is_busy(), 4.0)
	p.check(not pl.controller.is_busy(), "pressed again: hopped down")
	# Across the pool: skim the water, then jump off.
	await _place(Vector3(12.5, 0, 5.0), 0.0)
	await _cast(&"ability_3", &"air_scooter")
	Input.action_press(&"move_forward")
	await _tick_until(func() -> bool: return pl.global_position.z < 0.5, 2.0)
	await _obs("scooter_water", pl.global_position + Vector3(0, 0.3, -1.0), -1.0, 6.0, 1.2)
	var pp := pl.global_position
	p.check(pp.x > 9.0 and pp.x < 16.0 and pp.z > -4.0 and pp.z < 3.0 and absf(pp.y) < 0.3 and not pl.motor.swimming,
			"skimming the pool (at %s)" % pp)
	Input.action_press(&"jump")
	await p.wait_game(0.08)
	Input.action_release(&"jump")
	await p.wait_game(0.3)
	await _obs("scooter_jump_off", pl.global_position + Vector3(0, -0.5, -2.0), 1.0, 7.0, 0.5)
	Input.action_release(&"move_forward")
	await _tick_until(func() -> bool: return pl.is_on_floor(), 4.0)
	await p.wait_game(0.4)
	wall.queue_free()


func _ward() -> void:
	var bot := arena.get("bot") as SparringBot
	await _place(Vector3(0, 0, -8.0))
	_equip(&"vortex_ward", &"technique_4")
	p.check(await _cast(&"ability_4", &"vortex_ward"), "ward up")
	bot.attack_in(0.1, &"projectile")
	await p.wait_game(0.3)
	await _close("ward_up", pl.global_position + Vector3.UP * 1.0, 4.2, 0.8, 25.0)
	await _tick_until(func() -> bool:
		var a := pl.controller.current
		return a == null or (a.get("held") as Array).size() > 0, 2.5)
	await p.wait_game(0.25)
	await _obs("ward_caught", pl.global_position + Vector3(0, 1.0, -2.0), 1.0, 5.5, 1.2)
	await _tick_until(func() -> bool:
		var a := pl.controller.current
		return a == null or bool(a.get("bursted")), 4.0)
	await p.wait_game(0.06)
	await _obs("ward_burst", pl.global_position + Vector3(0, 1.0, -3.0), -1.0, 7.0, 2.0)
	await p.wait_game(0.6)
	p.note("ward: bot hits taken %d" % bot.hits_taken)


func _tornado() -> void:
	await _place(Vector3(0, 0, 4.0))
	var ring := [_sparring(Vector3(-1.2, 0, -2.5), &"bandit"), _sparring(Vector3(2.4, 0, -1.0), &"fire_soldier"),
		_sparring(Vector3(0.8, 0, -4.6), &"earth_soldier")]
	await p.wait_game(0.4)
	_equip(&"air_tornado")
	pl.resources.set_focus(100.0)
	p.check(await _cast(&"ability_special", &"air_tornado"), "tornado cast")
	await p.wait_game(0.25)
	await _obs("tornado_spin_up", pl.global_position + Vector3(0, 1.0, -3.0), 1.0, 7.0, 1.6)
	await p.wait_game(0.5)
	await _obs("tornado_pull", Vector3(0, 2.5, -2.0), 1.0, 11.0, 2.5)
	await p.wait_game(0.6)
	await _obs("tornado_lift", Vector3(0, 3.0, -2.0), -1.0, 11.0, 1.5)
	await p.screenshot("tornado_player_view")
	var top := 0.0
	for d in ring:
		top = maxf(top, (d as Node3D).global_position.y)
	p.check(top > 2.0, "lifted up the funnel (%.1f m)" % top)
	await _tick_until(func() -> bool:
		var a := pl.controller.current
		return a == null or bool(a.get("blown")), 2.5)
	await p.wait_game(0.15)
	await _obs("tornado_release", Vector3(0, 3.0, -2.0), 1.0, 12.0, 3.0)
	await p.wait_game(1.6)
	await _obs("tornado_after", Vector3(0, 0.5, -2.0), 1.0, 12.0, 4.0)
	p.check(_hits_of(&"air_tornado") >= 6, "tornado pulses + release landed (%d)" % _hits_of(&"air_tornado"))
	await p.wait_game(1.0)
	_clear_extra()


# --- environment -------------------------------------------------------------------------------------

func _env() -> void:
	var garden := AirPlaytestGarden.build(arena, Vector3(0, 0, 14.0))
	await p.wait_game(0.5)
	await _place(Vector3(0, 0, 18.5), 0.0)
	await _obs("env_garden_before", Vector3(0, 0.8, 13.0), 1.0, 9.0, 3.0)
	# Air Blast gust through the grass toward the torches.
	await _cast(&"attack_heavy", &"air_blast", 0.04)
	await p.wait_game(0.2)
	await _obs("env_gust_grass", Vector3(0, 0.6, 14.5), 1.0, 8.0, 2.4)
	await p.wait_game(0.5)
	# Air Push in the middle of the garden: ring through the grass, bushes bend, pots fly, torches out.
	await _place(Vector3(0, 0, 14.6), 0.0)
	_equip(&"air_push")
	await _cast(&"ability_1", &"air_push", 0.04)
	await _tick_until(func() -> bool:
		var a := pl.controller.current as ChargeAbility
		return a != null and a.released, 1.0)
	await p.wait_game(0.1)
	await _close("env_push_garden", Vector3(0, 0.3, 14.0), 7.0, 5.0, 10.0)
	await p.wait_game(0.25)
	await _obs("env_push_after", Vector3(0, 0.5, 13.0), 1.0, 9.0, 3.0)
	p.check(garden.torches_out() >= 1, "torches blown out (%d)" % garden.torches_out())
	p.check(garden.props_moved() >= 2, "props knocked about (%d)" % garden.props_moved())
	await p.wait_game(1.5)
	# Snow patch: the sweep scours a ring of snow.
	await _place(Vector3(-12, 0, -2.0), 0.0)
	_equip(&"air_sweep", &"technique_2")
	await _cast(&"ability_2", &"air_sweep")
	await p.wait_game(0.42)
	await _obs("env_snow_sweep", pl.global_position + Vector3(0, 0.3, -1.0), 1.0, 7.0, 2.6)
	await p.wait_game(0.6)
	# Gliding low over the garden leaves a wake.
	await _place(Vector3(0, 0, 24.0), 0.0)
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 4.2, 22.0)))
	await p.wait_game(0.3)
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	await _tick_until(func() -> bool: return pl.motor.gliding, 1.5)
	await p.wait_game(0.3)
	await _close("env_glide_wake", pl.global_position + Vector3(0, -1.2, 0.5), 7.5, 2.5, 160.0)
	Input.action_release(&"jump")
	Input.action_release(&"move_forward")
	await _tick_until(func() -> bool: return pl.is_on_floor(), 3.0)
	await p.wait_game(0.5)


func _report() -> void:
	var by := {}
	for h: Array in hits:
		var k := String(h[0])
		by[k] = int(by.get(k, 0)) + 1
	p.note("hits by ability: %s" % str(by))
