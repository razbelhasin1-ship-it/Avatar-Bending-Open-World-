extends RefCounted
## Wave-4 integration fixes in the real world scene (a new Water game in the Northern Water
## Tribe at night, intro skipped):
##   1. onboarding + level-up: the HUD shows the starters and the locked signature (padlock +
##      level), R explains it, a level-up shows ONE presentation (the banner, no HUD toast),
##      a quest technique reward lands in the next free slot at once;
##   2. world fires: a settlement brazier near the spawn, lit at night with its glow; Water
##      Surge puts it out (flames gone, coals dark, no night glow, light off, steam); a
##      firebender's Fire Burst lights it again; an air blast blows it out; it relights by
##      itself after its timer; by day a cold brazier stands unlit and fire lights it.
## Observer-camera screenshots of every state (look at them). SKIP=levelup|fires.

const E := ElementDefs.Element

var p: Playtest
var w: WorldScene
var pl: PlayerCharacter
var cam: Camera3D


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(E.WATER)
	GameState.intro_done = true
	var t0 := Time.get_ticks_msec()
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": true, "element": E.WATER, "skip_intro": true, "time_of_day": 21.5}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.is_ready and w.playing, 300.0)
	p.check(ok, "world ready (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if not ok:
		return
	pl = w.player
	pl.resources.infinite_chi = true
	pl.camera_rig.require_capture = false
	cam = Camera3D.new()
	cam.fov = 55.0
	w.add_child(cam)
	await p.wait_game(2.0)
	var skip := OS.get_environment("SKIP")
	if skip != "levelup":
		await _levelup()
	if skip != "fires":
		await _fires()


# --- 1. onboarding + level-up ---------------------------------------------------------------------

func _hud() -> Hud:
	return w.find_children("*", "Hud", true, false)[0] as Hud if not w.find_children("*", "Hud", true, false).is_empty() else null


func _toasts(hud: Hud) -> Array:
	var out: Array = []
	for t in hud.toasts.get_children():
		if not t.is_queued_for_deletion():
			var ls := t.find_children("*", "Label", true, false)
			if not ls.is_empty():
				out.append((ls.back() as Label).text)
	return out


func _levelup() -> void:
	var hud := _hud()
	p.check(hud != null, "HUD present")
	if hud == null:
		return
	pl.camera_rig.make_current()
	await p.wait_game(4.0)   # region title fades
	var starters := AbilityRegistry.starter_techniques(E.WATER)
	var ids: Array = []
	for i in 4:
		ids.append(StringName(pl.get_ability_slot_info(i).get("id", &"")))
	p.note("new game slots: %s (starters %s)" % [str(ids), str(starters)])
	p.check(ids.slice(0, starters.size()) == Array(starters) and ids[3] == &"", "starters on slots 1-%d, slot 4 free" % starters.size())
	p.check(hud.abilities.signature.is_locked(), "the HUD signature slot shows the locked signature")
	await p.tap(&"ability_special")
	await p.wait_game(0.3)
	var t := _toasts(hud)
	p.note("toasts after R: %s" % str(t))
	p.check(t.any(func(s: String) -> bool: return s.contains("Tidal Torrent") and s.contains("level")), "R explains how to learn the signature")
	await p.screenshot("integration_fixes_hud_locked_signature")
	# Level-up: one presentation (the banner); no HUD toast about it.
	var n0 := _toasts(hud).filter(func(s: String) -> bool: return s.contains("Level")).size()
	GameState.add_xp(GameState.xp_for_level(1) + 10, "test")
	await p.wait_game(0.6)
	var banners := w.find_children("*", "LevelUpBanner", true, false)
	var banner: LevelUpBanner = banners[0] if not banners.is_empty() else null
	p.check(banner != null and banner.is_showing and banner.shown == 1, "the level-up banner shows")
	var lvl_toasts := _toasts(hud).filter(func(s: String) -> bool: return s.contains("Level")).size() - n0
	p.check(lvl_toasts == 0, "no second level-up message in the HUD toasts (%d)" % lvl_toasts)
	await p.screenshot("integration_fixes_levelup_banner")
	await p.wait_game(5.0)
	# A quest technique reward goes into the next free slot and the HUD shows it at once.
	var got := QuestRewards.unlock_first([&"water_surge", &"ice_wall", &"healing_waters"], "test")
	await p.wait_game(0.3)
	var slot4 := StringName(pl.get_ability_slot_info(3).get("id", &""))
	p.check(got == &"healing_waters" and slot4 == &"healing_waters", "reward %s on slot 4 (%s)" % [got, slot4])
	p.check(StringName(hud.abilities.slot(3).info.get("id", &"")) == &"healing_waters", "HUD slot 4 updated at once")
	await p.screenshot("integration_fixes_reward_slot4")


# --- 2. world fires ---------------------------------------------------------------------------------

func _fires() -> void:
	var m := WorldFires.ensure()
	await p.wait_until(func() -> bool: return WorldFires.spot_count() > 20, 30.0)
	p.note("world fires registered near the spawn: %d" % WorldFires.spot_count())
	var target := await _pick_brazier()
	p.check(not target.is_empty(), "a settlement brazier with a clear stand near the spawn")
	if target.is_empty():
		return
	var bid := int(target["id"])
	var bpos: Vector3 = target["pos"]
	var stand: Vector3 = target["stand"]
	var face := Vector3(bpos.x - stand.x, 0, bpos.z - stand.z).normalized()
	await w.travel.travel_to(Transform3D(Basis(Vector3.UP, atan2(-face.x, -face.z)), stand), {"fade": 0.1, "autosave": false, "text": ""})
	await p.wait_game(1.5)
	pl.motor.face(face)
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.5)
	m.update_now()
	p.note("brazier %d at %s (cold by day: %s), player %s, %.1f m" % [bid, bpos, target["cold"], pl.global_position, pl.global_position.distance_to(bpos)])
	p.check(WorldFires.is_lit(bid), "the brazier burns at night")
	p.check(m.proxies.has(bid), "it has a stand-in (hooks + hit proxy)")
	await _obs("integration_fixes_fire_1_lit_night", bpos)
	# Water Surge rolls over it.
	_equip(&"water_surge")
	await _face_to(bpos)
	await _tap1()
	await p.wait_until(func() -> bool: return not WorldFires.is_lit(bid), 4.0)
	p.check(not WorldFires.is_lit(bid), "Water Surge put the brazier out")
	await p.wait_game(0.15)
	await _obs("integration_fixes_fire_2_doused_steam", bpos)
	await p.wait_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	await p.wait_game(1.6)
	p.check(m.mask.size() >= 1, "masked: flames + night glow hidden (%d)" % m.mask.size())
	p.check(not bool(LightBudget.suppress.call(bpos + Vector3(4, 0.4, 0))) and bool(LightBudget.suppress.call(bpos + Vector3(0, 0.4, 0))),
			"its light is kept off, others are not")
	await _obs("integration_fixes_fire_3_out_night", bpos)
	# A firebender lights it again (Fire Burst next to it).
	pl.set_element(E.FIRE)
	pl.resources.infinite_chi = true
	await p.wait_game(0.3)
	_equip(&"fire_burst")
	await _face_to(bpos)
	var near_stand := bpos - face * 2.0
	near_stand.y = pl.global_position.y
	pl.teleport(Transform3D(pl.global_basis, near_stand))
	await p.wait_game(0.3)
	await _tap1()
	await p.wait_until(func() -> bool: return WorldFires.is_lit(bid), 3.0)
	p.check(WorldFires.is_lit(bid), "Fire Burst lit the brazier")
	await p.wait_game(0.1)
	await _obs("integration_fixes_fire_4_relit_by_fire", bpos)
	await p.wait_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	await p.wait_game(1.5)
	await _obs("integration_fixes_fire_5_burning_again", bpos)
	# An airbender's Air Push blows it out; then it relights by itself after its timer.
	pl.set_element(E.AIR)
	pl.resources.infinite_chi = true
	pl.teleport(Transform3D(pl.global_basis, stand))
	await p.wait_game(0.4)
	_equip(&"air_push")
	await _face_to(bpos)
	await _tap1()
	await p.wait_until(func() -> bool: return not WorldFires.is_lit(bid), 3.0)
	p.check(not WorldFires.is_lit(bid), "an Air Push blew it out")
	var o: Dictionary = m.overrides.get(bid, {})
	p.note("relights in %.0f s" % (float(o.get("until", 0.0)) - m.clock))
	await p.wait_game(1.5)
	await _obs("integration_fixes_fire_6_blown_out", bpos)
	m.clock = float(o.get("until", m.clock)) - 0.5
	await p.wait_until(func() -> bool: return WorldFires.is_lit(bid), 3.0)
	p.check(WorldFires.is_lit(bid), "relit by itself after its timer")
	await p.wait_game(0.6)
	await _obs("integration_fixes_fire_7_relit_timer", bpos)
	# By day a cold brazier stands unlit; fire lights it.
	w.renderer.set_time_of_day(12.5)
	await p.wait_game(1.0)
	m.update_now()
	var cold := {}
	for s: Dictionary in WorldFires.spots_near(pl.global_position, WorldFires.MASK_RANGE):
		if bool(s["cold"]) and not WorldFires.is_lit(int(s["id"])):
			cold = s
			break
	p.check(not cold.is_empty(), "a cold brazier stands unlit by day")
	if cold.is_empty():
		return
	var cpos: Vector3 = cold["pos"]
	var cst := await _stand_near(cpos)
	if cst.is_finite():
		var cf := Vector3(cpos.x - cst.x, 0, cpos.z - cst.z).normalized()
		await w.travel.travel_to(Transform3D(Basis(Vector3.UP, atan2(-cf.x, -cf.z)), cst), {"fade": 0.1, "autosave": false, "text": ""})
		await p.wait_game(1.2)
	pl.set_element(E.FIRE)
	pl.resources.infinite_chi = true
	await p.wait_game(0.3)
	await _obs("integration_fixes_fire_8_cold_by_day", cpos)
	_equip(&"fire_burst")
	await _face_to(cpos)
	var near2 := cpos - Vector3(cpos.x - pl.global_position.x, 0, cpos.z - pl.global_position.z).normalized() * 2.0
	near2.y = pl.global_position.y
	pl.teleport(Transform3D(pl.global_basis, near2))
	await p.wait_game(0.3)
	await _tap1()
	await p.wait_until(func() -> bool: return WorldFires.is_lit(int(cold["id"])), 3.0)
	p.check(WorldFires.is_lit(int(cold["id"])), "Fire Burst lit the cold brazier by day")
	await p.wait_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	await p.wait_game(1.2)
	await _obs("integration_fixes_fire_9_lit_by_day", cpos)


## The nearest brazier (not a lantern) within 150 m of the player with a walkable stand 3.5 m
## from it and a clear line to the flame. Streams the cell collision first.
func _pick_brazier() -> Dictionary:
	var cands: Array = WorldFires.spots_near(pl.global_position, 150.0).filter(func(s: Dictionary) -> bool:
		return StringName(s["kind"]) == &"brazier" and not bool(s["cold"]))
	p.note("lit braziers within 150 m: %d" % cands.size())
	for s: Dictionary in cands.slice(0, 6):
		var bpos: Vector3 = s["pos"]
		var ok: bool = await w.travel.travel_to(Transform3D(Basis(), Vector3(bpos.x + 6.0, WorldData.get_height(bpos.x + 6.0, bpos.z) + 0.5, bpos.z)),
				{"fade": 0.05, "autosave": false, "text": ""})
		if not ok:
			continue
		await p.wait_game(1.5)
		var st := await _stand_near(bpos)
		if st.is_finite():
			var d := s.duplicate()
			d["stand"] = st
			return d
	return {}


## A floor point 3.2-4.2 m from `bpos` at about the flame's base level, with a clear line.
func _stand_near(bpos: Vector3) -> Vector3:
	var space := pl.get_world_3d().direct_space_state
	for r: float in [3.4, 4.2, 2.8]:
		for k in 12:
			var a := TAU * k / 12.0
			var q := bpos + Vector3(cos(a), 0, sin(a)) * r
			var ray := PhysicsRayQueryParameters3D.create(q + Vector3.UP * 2.5, q - Vector3.UP * 4.0, Layers.WORLD)
			var hit := space.intersect_ray(ray)
			if hit.is_empty():
				continue
			var fl: Vector3 = hit["position"]
			if (hit["normal"] as Vector3).y < 0.85 or absf(fl.y - (bpos.y - 1.1)) > 1.6:
				continue
			var los := PhysicsRayQueryParameters3D.create(fl + Vector3.UP * 1.4, bpos + Vector3.UP * 0.3, Layers.WORLD)
			los.exclude = [pl.get_rid()]
			var lh := space.intersect_ray(los)
			if not lh.is_empty() and (lh["position"] as Vector3).distance_to(bpos) > 0.9:
				continue
			# room to stand
			var up := PhysicsRayQueryParameters3D.create(fl + Vector3.UP * 0.2, fl + Vector3.UP * 2.0, Layers.WORLD)
			if not space.intersect_ray(up).is_empty():
				continue
			return fl + Vector3.UP * 0.05
	return Vector3.INF


func _equip(id: StringName) -> void:
	pl.controller.set_slot(&"technique_1", AbilityRegistry.get_def(id))
	pl.controller.reset_cooldowns()


func _tap1() -> void:
	Input.action_press(&"ability_1")
	await p.wait_game(0.06)
	Input.action_release(&"ability_1")


func _face_to(at: Vector3) -> void:
	var d := Vector3(at.x - pl.global_position.x, 0, at.z - pl.global_position.z)
	if d.length() > 0.1:
		pl.motor.face(d.normalized())
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.2)


## Observer shot of the brazier from the side, the player in frame.
func _obs(shot: String, focus: Vector3) -> void:
	var a := pl.global_position + Vector3.UP
	var f := focus - a
	f.y = 0.0
	var fwd := f.normalized() if f.length() > 0.3 else -pl.global_basis.z
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var mid := a.lerp(focus, 0.6)
	var pos := mid + right * 4.2 - fwd * 2.2 + Vector3.UP * 1.6
	var q := PhysicsRayQueryParameters3D.create(mid, pos, Layers.WORLD)
	q.exclude = [pl.get_rid()]
	var hit := pl.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		pos = mid.lerp(hit["position"], 0.85)
	cam.look_at_from_position(pos, mid, Vector3.UP)
	cam.make_current()
	var comp := pl.get_companion()
	if comp:
		comp.visible = false
	await p.wait_game(0.05)
	await p.screenshot(shot)
	pl.camera_rig.make_current()
