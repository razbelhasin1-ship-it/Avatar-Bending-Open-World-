extends RefCounted
## flow_qa: one element's journey through the REAL game like a QA lead (docs/qa/flow_qa.md),
## covering the brief's checklist items 4-10, 12, 13, 15-17 with input through the InputMap:
##   main menu -> ENTER THE WORLD -> element select (card by ui_right) -> BEGIN -> arrival
##   (skipped with a key press) -> home region + companion species -> walk to open ground ->
##   every core slot + every equipped starter technique against a real bandit (hits, health,
##   reactions) -> fight it until defeated (enemy_killed, XP) -> block and dodge a second bandit ->
##   camera look + lock-on consistency -> companion follows a sprint -> (Water) snow footprints ->
##   progress (XP, item, technique, POI, hour, companion health) -> pause -> SAVE GAME -> RETURN
##   TO MAIN MENU (clean state, no duplicates, no held input) -> CONTINUE -> everything restored.
## ELEMENT=air|earth|fire|water (default water). Real saves are backed up and restored.

const S := PlayerCharacter.State

var p: Playtest
var el := ""
var e := ElementDefs.Element.WATER
var w: WorldScene
var pl: PlayerCharacter
var used: Array[StringName] = []
var failed: Array = []
var hits: Array = []           # [ability_id, target, result]
var killed: Array = []
var xp_gained := 0


func run(pt: Playtest) -> void:
	p = pt
	var only := OS.get_environment("ELEMENT")
	e = ElementDefs.from_id(StringName(only)) if only != "" else ElementDefs.Element.WATER
	el = String(ElementDefs.id_of(e))
	if Settings.is_mobile_device():
		Settings.apply_preset("mobile")
		Settings.set_value("display", "render_scale", 0.75)
		Settings.apply()
	_backup_saves()
	Events.ability_used.connect(func(id: StringName) -> void: used.append(id))
	Events.ability_failed.connect(func(id: StringName, why: StringName) -> void: failed.append([id, why]))
	Events.hit_landed.connect(func(h: HitInfo, t: Node, r: int) -> void: hits.append([h.ability_id, t, r]))
	Events.enemy_killed.connect(func(en: Node3D, _k: Node) -> void: killed.append(en))
	Events.xp_gained.connect(func(a: int, _r: String) -> void: xp_gained += a)
	await p.goto_scene(Router.MAIN_MENU)
	await _new_journey()
	if w != null and w.playing:
		await _identity()
		if OS.get_environment("SKIP_QUEST") == "":
			await _quest_giver()
		await _combat()
		await _companion_follows()
		if e == ElementDefs.Element.WATER:
			await _footprints()
		await _save_menu_continue()
	_restore_saves()


# --- saves ----------------------------------------------------------------------------------------------

## The run's own save folder: user://saves_test is shared by every test run on the machine
## (other agents' playtests autosave into it), and a save appearing there mid-run turns
## ENTER THE WORLD into the Continue chooser. The developer's real saves are never touched.
var _prev_save_dir := ""


func _backup_saves() -> void:
	_prev_save_dir = SaveSystem.save_dir
	SaveSystem.save_dir = "user://saves_flow_qa_%s" % el
	DirAccess.make_dir_recursive_absolute(SaveSystem.save_dir)
	for i in SaveSystem.MAX_SLOTS:
		SaveSystem.delete_save(i)


func _restore_saves() -> void:
	for i in SaveSystem.MAX_SLOTS:
		SaveSystem.delete_save(i)
	SaveSystem.save_dir = _prev_save_dir


# --- helpers --------------------------------------------------------------------------------------------

func _ui(action: StringName) -> void:
	await p.tap(action, 0.05)
	await p.frames(2)


func _focus_owner() -> Control:
	return p.get_tree().root.get_viewport().gui_get_focus_owner()


func _world() -> WorldScene:
	return p.get_tree().get_first_node_in_group(&"world_scene") as WorldScene


func _ticks_until(cond: Callable, t: float) -> bool:
	for i in int(t * Engine.physics_ticks_per_second):
		if cond.call():
			return true
		await p.get_tree().physics_frame
	return cond.call()


func _press(action: StringName, hold: float = 0.06) -> void:
	Input.action_press(action)
	await p.wait_game(hold)
	Input.action_release(action)
	await p.get_tree().physics_frame


func _root_names() -> Dictionary:
	var counts := {}
	for c in p.get_tree().root.get_children():
		var key := String(c.name).rstrip("0123456789@")
		counts[key] = int(counts.get(key, 0)) + 1
	return counts


## Singletons of a running world: exactly one each.
func _census() -> Dictionary:
	var t := p.get_tree()
	return {"player": t.get_nodes_in_group(&"player").size(), "companion": t.get_nodes_in_group(&"companion").size(),
			"world_scene": t.get_nodes_in_group(&"world_scene").size(), "playable_scene": t.get_nodes_in_group(&"playable_scene").size(),
			"journey_book": t.get_nodes_in_group(&"journey_book").size(), "level_up_banner": t.get_nodes_in_group(&"level_up_banner").size(),
			"cameras_current": _current_cameras()}


func _current_cameras() -> int:
	var n := 0
	for c in p.get_tree().root.find_children("*", "Camera3D", true, false):
		if (c as Camera3D).current and (c as Camera3D).is_visible_in_tree():
			n += 1
	return n


func _held() -> Array:
	var held := []
	for a in InputMap.get_actions():
		if Input.is_action_pressed(a) and not String(a).begins_with("ui_"):
			held.append(a)
	return held


## A walkable, flat point between r0 and r1 m from `near`, outside settlements, on land.
func _find_open(near: Vector3, r0: float, r1: float) -> Vector3:
	for r in range(int(r0), int(r1), 10):
		var n := 12 + r / 12
		for k in n:
			var a := TAU * float(k) / n + float(r) * 0.37
			var q := near + Vector3(cos(a), 0, sin(a)) * float(r)
			var h := WorldData.get_height(q.x, q.z)
			if h < WorldData.SEA_LEVEL + 1.0:
				continue
			var g := Vector3(q.x, h, q.z)
			if Settlements.settlement_at(g) != &"" or WorldData.get_normal(q.x, q.z).y < 0.96:
				continue
			if WorldData.get_water_height(q.x, q.z) > -INF:      # lakes / canals / sea (a lake floor is "flat" too)
				continue
			var flat := true
			for j in 8:
				var b := TAU * float(j) / 8.0
				for rr: float in [6.0, 14.0]:
					var o := g + Vector3(cos(b), 0, sin(b)) * rr
					if absf(WorldData.get_height(o.x, o.z) - h) > 1.6 or WorldData.get_water_height(o.x, o.z) > -INF:
						flat = false
			if flat:
				return g
	return Vector3.INF


func _spawn_enemy(archetype: StringName, at: Vector3, face: Vector3) -> EnemyBase:
	var yaw := atan2(-(face - at).x, -(face - at).z)
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, WorldData.get_height(at.x, at.z) + 0.05, at.z))
	var d := EncounterDirector.instance()
	var en: EnemyBase
	if d != null:
		en = d.spawn_enemy(archetype, xf, {"level": 1, "seed": 7})
	else:
		en = EnemyBase.create(archetype, {"home": xf, "level": 1, "seed": 7})
		w.add_child(en)
	return en


func _enemy_hits(en: Node) -> Array:
	return hits.filter(func(h: Array) -> bool: return h[1] == en)


func _keep_alive() -> void:
	if pl.health.ratio() < 0.35:
		p.note("harness: player healed at %.0f%% health (keeps the run going)" % (pl.health.ratio() * 100.0))
		pl.health.health = pl.health.max_health


# --- 2/4/5: menus -> element select -> new journey ---------------------------------------------------------

func _new_journey() -> void:
	for i in SaveSystem.MAX_SLOTS:
		SaveSystem.delete_save(i)
	var menu := p.scene() as MainMenu
	if not p.check(menu != null, "%s main menu up" % el):
		return
	await p.wait_until(func() -> bool: return _focus_owner() == menu.options[0], 30.0)
	await p.screenshot("%s_00_menu" % el)
	await _ui(&"ui_accept")
	await p.wait_until(func() -> bool: return p.scene() is ElementSelect and not Router.is_transitioning, 60.0)
	var sel := p.scene() as ElementSelect
	if not p.check(sel != null, "%s element select reached" % el):
		return
	await p.wait_until(func() -> bool: return sel.cards[0].has_focus(), 60.0)
	var guard := 0
	while sel.current != e and guard < 6:
		guard += 1
		await _ui(&"ui_right")
		await p.wait(0.2)
	p.check(sel.current == e, "%s card focused" % el)
	await _ui(&"ui_accept")
	await p.wait(0.4)
	await p.screenshot("%s_01_select" % el)
	await _ui(&"ui_accept")
	var t0 := Time.get_ticks_msec()
	await p.wait_until(func() -> bool: return _world() != null, 60.0)
	w = _world()
	if not p.check(w != null and w.new_game, "%s new journey world" % el):
		return
	await p.wait_until(func() -> bool: return w.is_ready and not Router.is_transitioning, 300.0)
	p.check(w.is_ready, "%s loaded in %.1f s %s" % [el, (Time.get_ticks_msec() - t0) / 1000.0, str(w.load_report)])
	p.check(GameState.element == e and not GameState.is_tutorial, "%s chosen element assigned to the journey (GameState %d)" % [el, GameState.element])
	p.check(w.arrival != null, "%s arrival cinematic plays" % el)
	var arr := w.arrival
	if arr:
		await p.wait_until(func() -> bool: return not is_instance_valid(arr) or arr.time > 1.2, 60.0)
		await p.screenshot("%s_02_arrival" % el)
		await _press(&"jump", 0.05)
	await p.wait_until(func() -> bool: return w.playing, 60.0)
	p.check(w.playing, "%s control returned after the skipped arrival" % el)
	pl = w.player
	pl.camera_rig.require_capture = false
	await p.wait_game(0.5)


# --- 4/5/6: element, region, companion ---------------------------------------------------------------------

func _identity() -> void:
	var home := StringName(ElementDefs.get_data(e)["home_region"])
	await p.wait_until(func() -> bool: return w.region_director.current_region == home, 15.0)
	p.check(pl.element == e and pl.profile == pl.profile and GameState.element == e, "%s player bends %s" % [el, el])
	p.check(w.region_director.current_region == home and GameState.region == home and WorldData.get_region(pl.global_position.x, pl.global_position.z) == home,
			"%s starts in the home region %s (%s)" % [el, home, w.region_director.current_region])
	var c := pl.get_companion() as Companion
	var want := StringName(ElementDefs.get_data(e)["companion"])
	p.check(c != null and c.species == want, "%s companion is the %s (%s)" % [el, want, c.species if c else &"none"])
	if c:
		p.check(c.global_position.distance_to(pl.global_position) < 25.0, "%s companion beside the player (%.1f m)" % [el, c.global_position.distance_to(pl.global_position)])
	var eq := GameState.equipped_abilities.filter(func(a: StringName) -> bool: return a != &"")
	p.check(eq.size() >= 2, "%s starter techniques equipped %s" % [el, str(GameState.equipped_abilities)])
	p.check(Quests.is_active(_opening_quest()), "%s opening quest %s active" % [el, _opening_quest()])
	await p.screenshot("%s_03_home" % el)


func _opening_quest() -> StringName:
	return {ElementDefs.Element.AIR: &"at_first_breath", ElementDefs.Element.EARTH: &"ek_stone_beneath_the_sky",
			ElementDefs.Element.FIRE: &"fn_a_spark_returns", ElementDefs.Element.WATER: &"wt_born_of_the_tide"}[e]


func _giver() -> StringName:
	return {ElementDefs.Element.AIR: &"at_pasang", ElementDefs.Element.EARTH: &"ek_lin",
			ElementDefs.Element.FIRE: &"fn_kaida", ElementDefs.Element.WATER: &"wt_anaaya"}[e]


func _npc_director() -> NpcDirector:
	for h in w.hooks:
		if h.get("director") is NpcDirector:
			return h.get("director")
	return null


func _face(q: Vector3) -> void:
	var to := q - pl.global_position
	to.y = 0.0
	if to.length_squared() > 0.01:
		pl.rotation.y = atan2(-to.x, -to.z)
		pl.camera_rig.snap_behind(pl)


## The element's opening quest giver -> talk through the conversation -> the first objective done.
func _quest_giver() -> void:
	var q := _opening_quest()
	var id := _giver()
	var stage0 := Quests.current_stage(q)
	var dir := _npc_director()
	if not p.check(dir != null, "%s NPC director present" % el):
		return
	var xf := NpcRegistry.placement(id)
	p.note("%s giver %s placed %.0f m from the spawn" % [el, id, xf.origin.distance_to(pl.global_position)])
	if xf.origin.distance_to(pl.global_position) > 14.0:
		var front := xf.origin + (-xf.basis.z) * 2.4
		var d := xf.origin - front
		await w.travel.travel_to(Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), front + Vector3.UP * 0.1), {"text": "", "fade": 0.1, "autosave": false})
		await p.wait_game(1.0)
	await p.wait_until(func() -> bool: return NpcRegistry.live_npc(id) != null, 15.0)
	var n := NpcRegistry.live_npc(id) as Node3D
	if not p.check(n != null, "%s quest giver %s is there" % [el, id]):
		return
	var t := 0.0
	while t < 6.0 and Vector2(pl.global_position.x - n.global_position.x, pl.global_position.z - n.global_position.z).length() > 1.8:
		_face(n.global_position)
		Input.action_press(&"move_forward")
		await p.wait_game(0.1)
		t += 0.1
	Input.action_release(&"move_forward")
	_face(n.global_position)
	await p.wait_game(0.3)
	var runner := dir.runner
	var started := false
	for attempt in 4:
		await p.tap(&"interact", 0.08)
		started = await p.wait_until(func() -> bool: return runner.busy, 2.0)
		if started:
			break
	if not p.check(started, "%s conversation with %s started (interact)" % [el, id]):
		return
	await p.wait_game(1.2)
	await p.screenshot("%s_03b_quest_giver" % el)
	var guard := 0
	var box: DialogueBox = w.dialogue
	while runner.busy and guard < 60:
		guard += 1
		if box.choices.size() > 0:
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_1
			ev.keycode = KEY_1
			ev.pressed = true
			Input.parse_input_event(ev)
			var up := ev.duplicate() as InputEventKey
			up.pressed = false
			Input.parse_input_event(up)
		else:
			await p.tap(&"interact", 0.06)      # InputEventAction, like a key / pad press
		await p.wait_game(0.35)
	p.check(not runner.busy, "%s conversation ended (%d lines)" % [el, runner.transcript.size()])
	await p.wait_game(0.8)
	p.check(Quests.current_stage(q) > stage0 or Quests.is_completed(q), "%s first objective of %s done (stage %d -> %d)" % [el, q, stage0, Quests.current_stage(q)])
	p.check(pl.get_state() == S.LOCOMOTION, "%s control back after the conversation (%s)" % [el, pl.get_state_name()])
	await p.screenshot("%s_03c_objective" % el)


# --- 7/8/9/10: combat on open ground -------------------------------------------------------------------------

func _combat() -> void:
	var spot := _find_open(pl.global_position, 70.0, 1200.0)
	if not p.check(spot.is_finite(), "%s open ground near the spawn" % el):
		return
	var ok: bool = await w.travel.travel_to(Transform3D(Basis(), spot + Vector3.UP * 0.1), {"fade": 0.1, "autosave": false})
	p.check(ok, "%s travelled to open ground %s" % [el, str(spot)])
	await p.wait_game(2.0)
	pl.camera_rig.snap_behind(pl)
	var fwd := -pl.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# --- every slot against a real bandit ---
	var en := _spawn_enemy(&"bandit_brawler", pl.global_position + fwd * 7.0, pl.global_position)
	var en_states := {}
	var en_attacks := [0]
	var en_defeat := [&""]
	en.defeated.connect(func(_e: EnemyBase, how: StringName) -> void: en_defeat[0] = how)
	en.state_changed.connect(func(ns: int, _os: int) -> void: en_states[EnemyBase.State.keys()[ns]] = true)
	en.attack_telegraphed.connect(func(_e: EnemyBase, _a: Dictionary, _s: float) -> void: en_attacks[0] += 1)
	await p.wait_game(0.6)
	await _press(&"lock_on")
	await p.wait_game(0.3)
	p.check(pl.targeting.lock_target == en, "%s locks on to the bandit" % el)
	var hp0 := en.health.health
	var report := {}
	for slot: StringName in [&"attack_light", &"attack_heavy", &"ability_1", &"ability_2", &"ability_3", &"ability_4"]:
		var sid := _slot_of(slot)
		var def := pl.controller.get_slot_def(sid)
		if def == null:
			continue
		await _ticks_until(func() -> bool: return not pl.controller.is_busy() and pl.get_state() == S.LOCOMOTION, 4.0)
		# Each technique on a bandit back on its feet: the previous one may have launched it
		# (Earth Pillar), and a ground shockwave (Earth Stomp) misses airborne targets by design.
		await _ticks_until(func() -> bool:
			return not is_instance_valid(en) or not en.is_alive() or (en.is_on_floor() and en.state != EnemyBase.State.KNOCKDOWN), 4.0)
		await _approach(en)
		_keep_alive()
		pl.resources.set_chi(PlayerResources.CHI_MAX)
		pl.controller.reset_cooldowns()
		var n_used := used.size()
		var n_hits := _enemy_hits(en).size()
		var n_cons := BendingConstruct.live.size()
		var hp := en.health.health if is_instance_valid(en) else 0.0
		if slot == &"attack_light":
			for k in 3:
				await _press(slot, 0.05)
				await _ticks_until(func() -> bool:
					var cmb := pl.controller.current as ComboAbility
					return cmb == null or cmb.can_chain(), 1.2)
		else:
			await _press(slot, 0.08)
		await p.wait_game(0.5)
		if slot == &"ability_1":
			await p.screenshot("%s_04_technique_1" % el)
		await _ticks_until(func() -> bool: return not pl.controller.is_busy(), 4.0)
		await p.wait_game(0.4)
		var cast := used.slice(n_used).has(def.id)
		var landed := _enemy_hits(en).size() - n_hits
		var dmg := hp - (en.health.health if is_instance_valid(en) and en.is_alive() else 0.0)
		var made := BendingConstruct.live.size() - n_cons
		var res := {}
		for h: Array in _enemy_hits(en).slice(n_hits):
			var rn: String = Combat.Result.keys()[int(h[2])] if int(h[2]) >= 0 and int(h[2]) < Combat.Result.size() else str(h[2])
			res[rn] = int(res.get(rn, 0)) + 1
		report[def.id] = {"cast": cast, "hits": landed, "results": res, "damage": snappedf(dmg, 0.1), "constructs": made}
		p.check(cast, "%s %s (%s) performed from %s" % [el, def.display_name, def.id, slot])
		p.check(landed > 0 or made > 0 or dmg > 0.0, "%s %s had a gameplay effect %s" % [el, def.id, str(report[def.id])])
		if not is_instance_valid(en) or not en.is_alive():
			break
	p.note("%s per-slot report: %s" % [el, str(report)])
	p.note("%s failures: %s" % [el, str(failed)])
	var sig := pl.controller.locked_signature_info() if pl.controller.has_method("locked_signature_info") else {}
	if not sig.is_empty():
		var nf := failed.size()
		await _press(&"ability_special")
		p.check(failed.size() > nf and failed[-1][1] == &"locked", "%s locked signature refuses with a hint (%s)" % [el, str(failed.slice(nf))])
	p.check(is_instance_valid(en) and en.health.health < hp0 or not is_instance_valid(en) or not en.is_alive(), "%s bandit took damage (%.0f -> %.0f)" % [el, hp0, en.health.health if is_instance_valid(en) else 0.0])
	# --- fight it out ---
	var xp0 := xp_gained
	var t := 0.0
	while is_instance_valid(en) and en.is_alive() and t < 45.0:
		_keep_alive()
		pl.resources.set_chi(PlayerResources.CHI_MAX)
		if pl.targeting.lock_target != en:
			await _press(&"lock_on")
		for k in 3:
			await _press(&"attack_light", 0.05)
			await p.wait_game(0.28)
		await p.wait_game(0.3)
		await _press(&"attack_heavy", 0.08)
		await _ticks_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
		t += 2.5
	p.check(not is_instance_valid(en) or not en.is_alive(), "%s bandit defeated in the fight (%.0f s)" % [el, t])
	p.check(en_defeat[0] != &"" and (en_defeat[0] != &"killed" or killed.has(en)), "%s defeat reported: %s (Events.enemy_killed on a kill; surrender / flight count as defeats for quests)" % [el, en_defeat[0]])
	p.note("%s bandit states seen: %s, attacks telegraphed: %d" % [el, str(en_states.keys()), en_attacks[0]])
	p.check(en_states.has("STAGGER") or en_states.has("KNOCKDOWN"), "%s the bandit reacted to hits (stagger / knockdown)" % el)
	p.check(en_attacks[0] > 0 and (en_states.has("CHASE") or en_states.has("STRAFE") or en_states.has("ATTACK")), "%s the bandit fought back (%d attacks)" % [el, en_attacks[0]])
	await p.wait_game(1.0)
	p.check(xp_gained > xp0, "%s defeat granted XP (+%d)" % [el, xp_gained - xp0])
	await p.screenshot("%s_05_defeated" % el)
	await _block_and_dodge(fwd)


## Closes in on the enemy like a player would before a close-range technique (stomp, sweep,
## burst reach ~4.5-5 m; a launch or knockback leaves the target farther away).
func _approach(en: EnemyBase, dist: float = 3.2, max_s: float = 3.0) -> void:
	var t := 0.0
	if pl.targeting.lock_target != en and is_instance_valid(en) and en.is_alive():
		await _press(&"lock_on")
	while is_instance_valid(en) and en.is_alive() and pl.global_position.distance_to(en.global_position) > dist and t < max_s:
		Input.action_press(&"move_forward")
		await p.wait_game(0.1)
		t += 0.1
	Input.action_release(&"move_forward")


func _slot_of(action: StringName) -> StringName:
	match action:
		&"attack_light": return &"light"
		&"attack_heavy": return &"heavy"
	return StringName("technique_%s" % String(action).trim_prefix("ability_"))


func _block_and_dodge(fwd: Vector3) -> void:
	var en := _spawn_enemy(&"bandit_brawler", pl.global_position + fwd * 5.0, pl.global_position)
	await p.wait_game(0.4)
	if pl.targeting.lock_target != en:
		await _press(&"lock_on")
	pl.health.health = pl.health.max_health
	var results: Array = []
	var cb := func(_h: HitInfo, t: Node, r: int) -> void:
		if t == pl or (t is BendingConstruct and (t as BendingConstruct).follow == pl):
			results.append(r)
	Events.hit_landed.connect(cb)
	Input.action_press(&"block")
	var blocked := await _ticks_until(func() -> bool: return results.has(Combat.Result.BLOCKED) or results.has(Combat.Result.DEFLECTED), 14.0)
	await p.screenshot("%s_06_block" % el)
	Input.action_release(&"block")
	p.check(blocked, "%s defense blocks the bandit's attack %s" % [el, str(results)])
	await _ticks_until(func() -> bool: return pl.get_state() == S.LOCOMOTION, 3.0)
	# dodge sideways
	var at := pl.global_position
	Input.action_press(&"move_left")
	await p.wait_game(0.1)
	var states: Array = []
	var sc := func(ns: int, _os: int) -> void: states.append(ns)
	pl.state_changed.connect(sc)
	await _press(&"dodge")
	await _ticks_until(func() -> bool: return pl.get_state() == S.LOCOMOTION and not pl.controller.is_busy(), 3.0)
	Input.action_release(&"move_left")
	pl.state_changed.disconnect(sc)
	var moved := Vector2(pl.global_position.x - at.x, pl.global_position.z - at.z).length()
	p.check(used.has(pl.controller.get_slot_def(&"dodge").id) and moved > 1.5, "%s dodge moved %.1f m (states %s)" % [el, moved, str(states)])
	p.check(pl.get_state() == S.LOCOMOTION, "%s back in control after the dodge (%s)" % [el, pl.get_state_name()])
	# camera: mouse look turns, lock-on keeps framing the target
	if pl.targeting.lock_target != null:
		await _press(&"lock_on")   # unlock (lock-on frames the target and owns the camera)
	await p.wait_game(0.2)
	var yaw0 := pl.camera_rig.yaw
	for i in 10:
		p.look(30.0, 0.0)
		await p.frames(1)
	await p.wait_game(0.2)
	var dyaw := absf(wrapf(pl.camera_rig.yaw - yaw0, -PI, PI))
	p.check(dyaw > 0.2, "%s mouse look turns the camera (%.2f rad)" % [el, dyaw])
	var cam := pl.camera_rig.get_viewport().get_camera_3d()
	p.check(cam != null and cam.global_position.distance_to(pl.global_position) < 12.0, "%s camera stays with the player" % el)
	Events.hit_landed.disconnect(cb)
	# finish the second bandit so it does not follow us around
	var t := 0.0
	while is_instance_valid(en) and en.is_alive() and t < 40.0:
		_keep_alive()
		pl.resources.set_chi(PlayerResources.CHI_MAX)
		if pl.targeting.lock_target != en:
			await _press(&"lock_on")
		for k in 3:
			await _press(&"attack_light", 0.05)
			await p.wait_game(0.28)
		await _press(&"attack_heavy", 0.08)
		await _ticks_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
		t += 2.2
	p.check(not is_instance_valid(en) or not en.is_alive(), "%s second bandit defeated" % el)
	if pl.targeting.lock_target != null:
		await _press(&"lock_on")


# --- 13: companion follows -----------------------------------------------------------------------------------

func _companion_follows() -> void:
	var c := pl.get_companion() as Companion
	if not p.check(c != null, "%s companion present after the fight" % el):
		return
	await p.wait_game(2.0)
	var d0 := c.global_position.distance_to(pl.global_position)
	Input.action_press(&"sprint")
	Input.action_press(&"move_forward")
	await p.wait_game(3.5)
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	var d1 := c.global_position.distance_to(pl.global_position)
	# Ground distance: a flyer escorting overhead counts as with the player. The slot is up to
	# ~8 m to the side (bison 7.5, dragon 10); a flyer that took off to catch up lands first.
	var flat := func() -> float:
		return Vector2(c.global_position.x - pl.global_position.x, c.global_position.z - pl.global_position.z).length()
	var f0 := Engine.get_physics_frames()
	await _ticks_until(func() -> bool: return flat.call() < 12.0, 20.0)
	var took := float(Engine.get_physics_frames() - f0) / Engine.physics_ticks_per_second
	var d2: float = flat.call()
	p.note("%s companion distance: before %.1f, after the sprint %.1f, settled %.1f m on the ground after %.1f game s (mode %s)" % [el, d0, d1, d2, took, c.MODE_NAMES[c.mode]])
	p.check(d2 < 12.0, "%s companion caught up (%.1f m)" % [el, d2])
	await p.screenshot("%s_07_companion" % el)


# --- 12: footprints in the snow (Water Tribe) ---------------------------------------------------------------

func _footprints() -> void:
	var snow := w.renderer.snow
	if not p.check(snow != null, "water: snow trails exist"):
		return
	p.check(SnowTrails.has_snow(pl.global_position), "water: standing on snow (%s)" % GroundSampler.surface(pl.global_position + Vector3.UP * 0.05))
	var n0 := snow.stamp_count()
	var start := pl.global_position
	Input.action_press(&"move_forward")
	await p.wait_game(2.2)
	Input.action_release(&"move_forward")
	await p.wait_game(0.6)
	var n1 := snow.stamp_count()
	p.check(n1 - n0 >= 4, "water: footprints stamped while walking (%d -> %d)" % [n0, n1])
	p.check(snow.get_sink_depth(start.lerp(pl.global_position, 0.5)) > 0.0 or n1 > n0, "water: the trail is under the walked path")
	# look back along the trail (the prints follow the player)
	var cam := Camera3D.new()
	w.add_child(cam)
	var back := (start - pl.global_position)
	back.y = 0.0
	var side := back.normalized().cross(Vector3.UP)
	cam.global_position = pl.global_position - back.normalized() * 2.5 + side * 1.5 + Vector3.UP * 2.6
	cam.look_at(start.lerp(pl.global_position, 0.6), Vector3.UP)
	cam.make_current()
	await p.wait(0.4)
	await p.screenshot("water_08_footprints")
	cam.queue_free()
	pl.camera_rig.camera.make_current()


# --- 15/16/17: save -> main menu -> continue ------------------------------------------------------------------

func _save_menu_continue() -> void:
	# progress worth keeping
	GameState.add_xp(GameState.xp_for_level(GameState.level) + 15, "flow_qa")
	GameState.add_item(&"ginseng_tea", 2)
	var extra := _a_learnable_technique()
	if extra != &"":
		GameState.unlock_ability(extra, true)
	var poi := WorldData.get_nearest_poi(pl.global_position)
	if not poi.is_empty():
		GameState.discover_poi(StringName(poi.get("id", "")))
	w.renderer.set_time_of_day(17.25)
	var c := pl.get_companion() as Companion
	if c:
		c.health.health = c.health.max_health * 0.6
	await p.wait_game(1.0)
	await _ui(&"pause")
	await p.wait_until(func() -> bool: return w.pause_menu.is_open, 5.0)
	p.check(w.pause_menu.is_open and p.get_tree().paused, "%s pause menu open, tree paused" % el)
	await _ui(&"ui_down")
	await _ui(&"ui_accept")
	await p.wait(0.2)
	p.check(SaveSystem.has_save(SaveSystem.AUTOSAVE_SLOT), "%s journey saved from the pause menu" % el)
	var want := GameState.to_dict()
	await p.screenshot("%s_09_saved" % el)
	await _ui(&"ui_down")
	await _ui(&"ui_down")
	p.check(_focus_owner() == w.pause_menu.options[3], "%s RETURN TO MAIN MENU focused" % el)
	await _ui(&"ui_accept")
	await p.wait_until(func() -> bool: return p.scene() is MainMenu and not Router.is_transitioning, 60.0)
	await p.frames(5)
	var cen := _census()
	p.check(_world() == null and cen["player"] == 0 and cen["companion"] == 0 and cen["playable_scene"] == 0, "%s world, player and companion gone %s" % [el, str(cen)])
	var names := _root_names()
	var dup := []
	for k: String in names:
		if int(names[k]) > 1:
			dup.append(k)
	p.check(dup.is_empty(), "%s no duplicated root nodes %s" % [el, str(names)])
	p.check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not p.get_tree().paused and Engine.time_scale == 1.0, "%s clean menu state" % el)
	p.check(_held().is_empty(), "%s no held input %s" % [el, str(_held())])
	# continue
	var menu := p.scene() as MainMenu
	await p.wait_until(func() -> bool: return _focus_owner() == menu.options[0], 30.0)
	p.check(menu.options[0].caption.contains("Level"), "%s menu offers the saved journey (%s)" % [el, menu.options[0].caption])
	await _ui(&"ui_accept")
	await p.wait_until(func() -> bool: return menu.chooser.visible and _focus_owner() == menu.chooser.continue_button, 10.0)
	await _ui(&"ui_accept")
	await p.wait_until(func() -> bool: return _world() != null and _world().is_ready and not Router.is_transitioning, 300.0)
	w = _world()
	if not p.check(w != null and not w.new_game, "%s continued" % el):
		return
	await p.wait_until(func() -> bool: return w.playing, 30.0)
	await p.wait_game(1.0)
	pl = w.player
	var got: Dictionary = _json(GameState.to_dict())
	want = _json(want)
	var pos := Vector3(want["player_position"][0], want["player_position"][1], want["player_position"][2])
	p.check(pl.global_position.distance_to(pos) < 1.0, "%s position restored (%.2f m)" % [el, pl.global_position.distance_to(pos)])
	p.check(pl.element == e and got["element"] == want["element"], "%s element restored" % el)
	p.check(got["level"] == want["level"] and got["xp"] == want["xp"] and got["skill_points"] == want["skill_points"], "%s level %d / xp %d / points %d restored" % [el, got["level"], got["xp"], got["skill_points"]])
	p.check(got["unlocked_abilities"] == want["unlocked_abilities"] and got["equipped_abilities"] == want["equipped_abilities"], "%s abilities + loadout restored %s" % [el, str(got["equipped_abilities"])])
	var live_slots: Array = []
	for i in 4:
		var d := pl.controller.get_slot_def(StringName("technique_%d" % (i + 1)))
		live_slots.append(String(d.id) if d else "")
	p.check(live_slots == want["equipped_abilities"], "%s the player's live slots match the save %s" % [el, str(live_slots)])
	p.check(str(got["quests"]) == str(want["quests"]) and got["tracked_quest"] == want["tracked_quest"], "%s quests restored" % el)
	p.check(str(got["inventory"]) == str(want["inventory"]) and GameState.item_count(&"ginseng_tea") >= 2 and GameState.inventory["ginseng_tea"] is int, "%s inventory restored %s" % [el, str(GameState.inventory)])
	p.check(str(got["discovered_pois"]) == str(want["discovered_pois"]), "%s discovered POIs restored (%d)" % [el, got["discovered_pois"].size()])
	p.check(absf(w.renderer.get_time_of_day() - float(want["time_of_day"])) < 0.25, "%s hour restored (%.2f vs %.2f)" % [el, w.renderer.get_time_of_day(), want["time_of_day"]])
	var c2 := pl.get_companion() as Companion
	p.check(c2 != null and String(c2.species) == String(want["companion"]["type"]), "%s companion restored (%s)" % [el, c2.species if c2 else &"none"])
	if c2:
		p.check(absf(c2.health.ratio() - float(want["companion"]["health_ratio"])) < 0.05, "%s companion health restored (%.2f vs %.2f)" % [el, c2.health.ratio(), want["companion"]["health_ratio"]])
	var cen2 := _census()
	p.check(cen2["player"] == 1 and cen2["companion"] == 1 and cen2["world_scene"] == 1 and cen2["journey_book"] <= 1 and cen2["cameras_current"] == 1, "%s one of each after the round trip %s" % [el, str(cen2)])
	p.check(_held().is_empty(), "%s no held input after continue" % el)
	# input works after the round trip: walk and strike
	var at := pl.global_position
	Input.action_press(&"move_forward")
	await p.wait_game(1.0)
	Input.action_release(&"move_forward")
	var nu := used.size()
	await _press(&"attack_light")
	await p.wait_game(0.4)
	p.check(pl.global_position.distance_to(at) > 1.5 and used.size() > nu, "%s movement and bending answer after continue (%.1f m)" % [el, pl.global_position.distance_to(at)])
	await p.screenshot("%s_10_continued" % el)
	await _ui(&"pause")
	await p.wait_until(func() -> bool: return w.pause_menu.is_open, 5.0)
	w.pause_menu.return_to_menu()
	await p.wait_until(func() -> bool: return p.scene() is MainMenu and not Router.is_transitioning, 60.0)
	await p.frames(3)


## Through JSON (one number type) so a saved and a live record compare by value.
func _json(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v))


func _a_learnable_technique() -> StringName:
	for d in AbilityRegistry.for_element(e):
		if d.slot == AbilityDef.Slot.TECHNIQUE and not GameState.is_unlocked(d.id) and not d.script_path.is_empty():
			return d.id
	return &""
