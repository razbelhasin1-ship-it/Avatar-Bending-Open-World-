extends RefCounted
## Earth techniques in the combat arena (docs/modules/bending_earth.md): every
## technique at its anticipation / active / impact frames from the player's
## camera and an observer camera; the core kit (punch chain, boulder charge +
## crater, shield + parry, slide furrow); surfaces (stone, sand, ash, snow, ice
## refusal, the pool); the self-lift onto a pillar; persistent marks.
## TECH=core,defense,pillar,self,stomp,wall,spikes,grab,armor,quake,env (default: all).

const E := ElementDefs.Element

var p: Playtest
var arena: Node
var pl: PlayerCharacter
var cam: Camera3D
var hits: Array = []


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(E.EARTH, true)
	arena = await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": E.EARTH})
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
	# The courtyard is paved: bend stone there (the arena's flat world reads grass).
	GroundSampler.add_zone(&"earth_court", Rect2(-8.0, -13.0, 16.0, 19.0), &"stone", 0.0)
	Events.hit_landed.connect(func(hit: HitInfo, t: Node, r: int) -> void: hits.append([hit.ability_id, t, r, hit.reaction]))
	var only := OS.get_environment("TECH")
	for t in ["core", "defense", "pillar", "self", "stomp", "wall", "spikes", "grab", "armor", "quake", "env"]:
		if only == "" or only.split(",").has(t):
			p.note("--- %s ---" % t)
			await call("_" + t)
	GroundSampler.remove_zone(&"earth_court")


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
	var st := EarthArmorState.of(pl)
	if st != null:
		st.break_off(&"reset")
	await _tick_until(func() -> bool: return BendingConstruct.live.is_empty(), 1.5)
	pl.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos))
	pl.controller.reset_cooldowns()
	await p.wait_game(0.05)
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.4)
	arena.call("reset_dummies")


func _equip(id: StringName) -> void:
	var d := AbilityRegistry.get_def(id)
	pl.controller.set_slot(&"signature" if d.slot == AbilityDef.Slot.SIGNATURE else &"technique_1", d)


func _lock() -> void:
	pl.targeting.call("toggle_lock")
	await p.wait_game(0.25)


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


## Close-up of a point from a given compass angle (deg, 0 = from +Z).
func _close(shot: String, focus: Vector3, dist: float = 3.5, height: float = 1.2, angle_deg: float = 35.0) -> void:
	var a := deg_to_rad(angle_deg)
	var pos := focus + Vector3(sin(a), 0.0, cos(a)) * dist + Vector3.UP * height
	cam.look_at_from_position(pos, focus, Vector3.UP)
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


func _press(action: StringName) -> void:
	Input.action_press(action)
	await p.wait_game(0.05)
	Input.action_release(action)


func _dummy(i: int) -> TrainingDummy:
	return (arena.get("dummies") as Array)[i] as TrainingDummy


# --- core kit --------------------------------------------------------------------------------------

func _core() -> void:
	await _place(Vector3(0, 0, -1.6))
	for i in 3:
		Input.action_press(&"attack_light")
		await p.wait_game(0.05)
		Input.action_release(&"attack_light")
		var ok := await _tick_until(func() -> bool:
			var c := pl.controller.current as ComboAbility
			return c != null and c.struck and c.step == i, 1.0)
		p.check(ok, "earth punch %d struck" % (i + 1))
		await p.screenshot("core_punch_%d" % (i + 1))
		await _tick_until(func() -> bool:
			var c := pl.controller.current as ComboAbility
			return c == null or c.can_chain(), 1.0)
	await p.wait_game(0.5)
	p.check(_hits_of(&"earth_punch") >= 3, "punch chain hit (%d)" % _hits_of(&"earth_punch"))
	# Boulder: tap-hold to lift, hold to grow, release to hurl at the dummy -> crater.
	await _place(Vector3(0, 0, 1.0))
	Input.action_press(&"attack_heavy")
	await p.wait_game(0.25)
	await _obs("core_boulder_lift", Vector3(0, 1, -6), 1.0, 5.0, 1.6)
	await p.wait_game(0.9)
	await p.screenshot("core_boulder_hold")
	Input.action_release(&"attack_heavy")
	await _tick_until(func() -> bool: return BendingProjectile.live.size() > 0, 1.0)
	await p.wait_game(0.06)
	await p.screenshot("core_boulder_throw")
	await _tick_until(func() -> bool: return _hits_of(&"earth_boulder") > 0, 2.0)
	await p.wait_game(0.1)
	await _obs("core_boulder_impact", Vector3(0, 0.5, -7), -1.0, 6.0, 2.0)
	p.check(_hits_of(&"earth_boulder") > 0, "boulder hit")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)


## Earth Shield vs the bot's fireball, a parry, and the slide furrow.
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
	await _obs("defense_1_shield", Vector3(0, 1, -13), -1.0, 5.0, 1.6)
	await p.wait_game(0.4)
	Input.action_release(&"block")
	var landed := [false]
	var cb := func(_kind: StringName, _in: float) -> void: landed[0] = true
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
	await _place(Vector3(-2, 0, 0.0), 90.0)
	Input.action_press(&"move_left")
	await p.wait_game(0.1)
	Input.action_press(&"dodge")
	await p.wait_game(0.05)
	Input.action_release(&"dodge")
	await p.wait_game(0.2)
	await _obs("defense_3_slide", pl.global_position, 1.0, 5.0, 1.8)
	Input.action_release(&"move_left")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 1.5)
	await p.wait_game(0.2)
	await _obs("defense_4_furrow", pl.global_position + Vector3(0, 0, 1.5), 1.0, 4.0, 2.6)


# --- techniques ------------------------------------------------------------------------------------

func _pillar() -> void:
	_equip(&"earth_pillar")
	await _place(Vector3(0, 0, 1.0))
	var target := _dummy(1)
	await _lock()
	await _press(&"ability_1")
	await p.wait_game(0.1)
	await _obs("pillar_1_chamber", target.global_position + Vector3.UP, 1.0, 6.0, 1.6)
	await _tick_until(func() -> bool: return _cur() != null and _cur().time_to_event(&"stomp") == INF, 1.0)
	await p.screenshot("pillar_2_stomp")
	await _tick_until(func() -> bool: return BendingConstruct.live.size() > 0, 1.0)
	await p.wait_game(0.08)
	await _obs("pillar_3_erupt", target.global_position + Vector3.UP, 1.0, 6.5, 1.8)
	await p.wait_game(0.25)
	await _obs("pillar_4_launch", target.global_position + Vector3.UP * 2.0, -1.0, 7.0, 2.2)
	p.check(_hits_of(&"earth_pillar") >= 1, "pillar launched the target (%d)" % _hits_of(&"earth_pillar"))
	await p.wait_game(1.0)
	await p.screenshot("pillar_5_column")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)


## Hold the button: the column rises under the bender.
func _self() -> void:
	_equip(&"earth_pillar")
	await _place(Vector3(-4, 0, 2.0))
	var y0 := pl.global_position.y
	Input.action_press(&"ability_1")
	await _tick_until(func() -> bool: return BendingConstruct.live.size() > 0, 1.5)
	await p.wait_game(0.15)
	await _obs("self_1_rising", pl.global_position + Vector3.UP * 1.5, 1.0, 6.5, 0.6)
	Input.action_release(&"ability_1")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	await p.wait_game(0.6)
	p.check(pl.global_position.y > y0 + 2.5 and pl.is_on_floor(), "standing on top of the column (%.2f m up, floor %s)" % [pl.global_position.y - y0, pl.is_on_floor()])
	await _obs("self_2_on_top", pl.global_position, -1.0, 7.0, 0.5)
	# Stomp down from up there into the crowd? Walk off instead: back on the ground.
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.2)
	await p.screenshot("self_3_view")


func _stomp() -> void:
	_equip(&"earth_stomp")
	await _place(Vector3(0, 0, -4.2))
	await _press(&"ability_1")
	await p.wait_game(0.12)
	await _obs("stomp_1_knee", Vector3(0, 1, -6.5), 1.0, 6.0, 1.4)
	await _tick_until(func() -> bool: return EarthShockwave.live.size() > 0, 1.0)
	await p.wait_game(0.08)
	await _obs("stomp_2_wave", Vector3(0, 0.5, -6.0), 1.0, 7.0, 2.6)
	await p.wait_game(0.15)
	await p.screenshot("stomp_3_front")
	await p.wait_game(0.4)
	p.check(_hits_of(&"earth_stomp") >= 2, "stomp staggered the dummies (%d)" % _hits_of(&"earth_stomp"))
	await _obs("stomp_4_crater", pl.global_position + Vector3(0, 0, -1.0), -1.0, 4.5, 3.0)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)


func _wall() -> void:
	_equip(&"earth_wall")
	await _place(Vector3(0, 0, 1.0))
	await _press(&"ability_1")
	await _tick_until(func() -> bool: return BendingConstruct.live.size() > 0, 1.5)
	await p.wait_game(0.15)
	await _obs("wall_1_rise", Vector3(0, 1, -3.5), 1.0, 7.0, 2.0)
	await p.wait_game(0.5)
	await p.screenshot("wall_2_standing")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)


func _spikes() -> void:
	_equip(&"earth_spikes")
	await _place(Vector3(0, 0, 3.0))
	var target := _dummy(1)
	await _lock()
	await _press(&"ability_1")
	await p.wait_game(0.15)
	await _obs("spikes_1_coil", target.global_position, 1.0, 6.0, 1.4)
	await _tick_until(func() -> bool: return EarthSpikeLine.live.size() > 0, 1.0)
	await p.wait_game(0.18)
	await _obs("spikes_2_line", target.global_position, 1.0, 8.0, 2.4)
	await p.wait_game(0.2)
	await p.screenshot("spikes_3_impact")
	p.check(_hits_of(&"earth_spikes") >= 1, "spikes launched the target (%d)" % _hits_of(&"earth_spikes"))
	await p.wait_game(0.3)
	await _obs("spikes_4_after", target.global_position, -1.0, 7.0, 2.6)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)


func _grab() -> void:
	_equip(&"earth_grab")
	var target := _dummy(3)
	await _place(target.global_position + Vector3(-1.5, 0, 7.0))
	await _lock()
	await _press(&"ability_1")
	await p.wait_game(0.1)
	await p.screenshot("grab_1_reach")
	await _tick_until(func() -> bool: return _cur() != null and _cur().time_to_event(&"release") == INF, 1.0)
	await p.wait_game(0.08)
	await _obs("grab_2_ripple", target.global_position, 1.0, 6.0, 1.6)
	await _tick_until(func() -> bool: return _hits_of(&"earth_grab") > 0, 1.5)
	await p.wait_game(0.12)
	await _close("grab_3_clamped", target.global_position + Vector3.UP * 0.7, 3.2, 0.6, 60.0)
	p.check(_hits_of(&"earth_grab") >= 1, "grab rooted the target")
	await p.wait_game(1.0)
	await p.screenshot("grab_4_held")
	await _close("grab_5_held_close", target.global_position + Vector3.UP * 0.7, 3.0, 1.0, -40.0)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)


func _armor() -> void:
	_equip(&"earth_armor")
	await _place(Vector3(0, 0, -3.0))
	pl.resources.infinite_chi = false
	pl.resources.set_chi(100.0)
	await _press(&"ability_1")
	await p.wait_game(0.3)
	await _obs("armor_1_gather", pl.global_position + Vector3.UP, 1.0, 4.0, 0.8)
	await _tick_until(func() -> bool: return EarthArmorState.is_worn(pl), 2.0)
	await p.wait_game(0.15)
	await _close("armor_2_locked", pl.global_position + Vector3.UP * 1.0, 3.0, 0.4, 200.0)
	p.check(EarthArmorState.is_worn(pl), "armor on")
	p.check(pl.ctx.base_damage_reduction > 0.3 and pl.motor.speed_scale < 0.9, "armor modifiers (dr %.2f, speed %.2f)" % [pl.ctx.base_damage_reduction, pl.motor.speed_scale])
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	# Walk in it.
	Input.action_press(&"move_forward")
	await p.wait_game(0.8)
	await _close("armor_3_walk", pl.global_position + Vector3.UP * 1.0, 3.2, 0.5, 140.0)
	Input.action_release(&"move_forward")
	var chi_before := pl.resources.chi
	await p.wait_game(1.0)
	p.check(pl.resources.chi < chi_before - 3.0, "armor drains chi (%.1f -> %.1f)" % [chi_before, pl.resources.chi])
	# Shed: burst outward.
	arena.call("reset_dummies")
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, -4.8)))
	await p.wait_game(0.2)
	await _press(&"ability_1")
	await _tick_until(func() -> bool: return not EarthArmorState.is_worn(pl), 1.5)
	await p.wait_game(0.05)
	await _obs("armor_4_burst", pl.global_position + Vector3.UP, 1.0, 5.0, 1.2)
	p.check(not EarthArmorState.is_worn(pl) and pl.motor.speed_scale == 1.0 and pl.ctx.base_damage_reduction == 0.0, "armor shed, modifiers cleared")
	pl.resources.infinite_chi = true
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)


func _quake() -> void:
	_equip(&"earthquake")
	await _place(Vector3(0, 0, -2.5))
	pl.resources.add_focus(100.0)
	await _press(&"ability_special")
	await p.wait_game(0.2)
	await _obs("quake_1_gather", pl.global_position + Vector3.UP * 0.5, 1.0, 5.0, 1.2)
	await _tick_until(func() -> bool: return _cur() != null and _cur().time_to_event(&"lift") == INF, 1.5)
	await p.wait_game(0.1)
	await _obs("quake_2_lift", pl.global_position + Vector3.UP * 1.5, -1.0, 6.0, 1.2)
	await _tick_until(func() -> bool: return EarthShockwave.live.size() > 0, 1.5)
	await p.wait_game(0.1)
	await _obs("quake_3_slam", pl.global_position + Vector3(0, 0, -3), 1.0, 9.0, 3.2)
	await p.wait_game(0.25)
	await p.screenshot("quake_4_wave")
	await p.wait_game(0.5)
	p.check(_hits_of(&"earthquake") >= 3, "earthquake knocked everyone down (%d)" % _hits_of(&"earthquake"))
	await _obs("quake_5_aftermath", pl.global_position + Vector3(0, 0, -2), -1.0, 9.0, 4.0)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	await p.wait_game(0.5)
	cam.look_at_from_position(pl.global_position + Vector3(0, 9.0, 6.0), pl.global_position + Vector3(0, 0, -2), Vector3.UP)
	cam.make_current()
	await p.screenshot("quake_6_marks_top")
	pl.camera_rig.make_current()


## Surfaces: the same stomp / punch on sand, ash and snow; refused on the ice rink.
func _env() -> void:
	var patches := {&"sand": [Rect2(-23.0, -24.0, 9.0, 9.0), Color(0.82, 0.71, 0.5)], &"ash": [Rect2(14.0, -24.0, 9.0, 9.0), Color(0.27, 0.25, 0.25)]}
	var nodes: Array[Node] = []
	for k: StringName in patches:
		var r: Rect2 = patches[k][0]
		GroundSampler.add_zone(StringName("earth_" + String(k)), r, k, 0.0)
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = r.size
		mi.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = patches[k][1]
		mat.roughness = 1.0
		mi.material_override = mat
		arena.add_child(mi)
		mi.global_position = Vector3(r.get_center().x, 0.012, r.get_center().y)
		nodes.append(mi)
	_equip(&"earth_stomp")
	for k: StringName in [&"sand", &"ash"]:
		var r: Rect2 = patches[k][0]
		await _place(Vector3(r.get_center().x, 0, r.get_center().y + 2.0))
		await _press(&"ability_1")
		await _tick_until(func() -> bool: return EarthShockwave.live.size() > 0, 1.0)
		await p.wait_game(0.1)
		await _obs("env_%s_stomp" % k, pl.global_position + Vector3(0, 0, -1), 1.0, 6.0, 2.8)
		await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
		_equip(&"earth_pillar")
		await _press(&"ability_1")
		await _tick_until(func() -> bool: return BendingConstruct.live.size() > 0, 1.0)
		await p.wait_game(0.35)
		await _obs("env_%s_pillar" % k, pl.global_position + Vector3(0, 1, -3), -1.0, 6.0, 1.6)
		await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
		_equip(&"earth_stomp")
	# Snow patch: rock under the snow (weaker), snow-capped rocks.
	await _place(Vector3(-12.0, 0, 0.5))
	_equip(&"earth_pillar")
	await _press(&"ability_1")
	await _tick_until(func() -> bool: return BendingConstruct.live.size() > 0, 1.0)
	await p.wait_game(0.35)
	await _obs("env_snow_pillar", pl.global_position + Vector3(0, 1, -3), 1.0, 6.0, 1.6)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	# Ice rink: nothing to bend (stomp: under the feet; pillar: at the aim point on the ice).
	await _place(Vector3(-12.0, 0, 12.0))
	_equip(&"earth_stomp")
	var fails: Array = []
	var cb := func(id: StringName, reason: StringName) -> void: fails.append([id, reason])
	Events.ability_failed.connect(cb)
	await _press(&"ability_1")
	await p.wait_game(0.1)
	await p.screenshot("env_ice_refused")
	p.check(fails.size() > 0 and fails[fails.size() - 1][1] == &"no_earth", "stomp refused on ice: %s" % str(fails))
	_equip(&"earth_pillar")
	pl.controller.reset_cooldowns()
	await p.wait_game(0.3)
	await _press(&"ability_1")
	await p.wait_game(0.1)
	Events.ability_failed.disconnect(cb)
	p.check(fails.size() > 1 and fails[fails.size() - 1][1] == &"no_earth", "pillar refused on ice: %s" % str(fails))
	for n in nodes:
		n.queue_free()
	GroundSampler.remove_zone(&"earth_sand")
	GroundSampler.remove_zone(&"earth_ash")
