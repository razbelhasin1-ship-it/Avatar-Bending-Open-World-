extends RefCounted
## Water techniques on a phone (run with RENDERER=mobile MOBILE=1): the combat
## arena with the touch overlay; Water Surge, Ice Wall and Ice Shards from the
## technique buttons, Water Jet held on its button, Tidal Torrent from the
## signature button - real InputEventScreenTouch through the overlay, so the
## same actions as keyboard / controller. Screenshots show the effects on the
## mobile renderer at the mobile quality preset; a frame-time sample is logged.

const Util := preload("res://tests/playtest/scenarios/mobile_touch_util.gd")
const E := ElementDefs.Element

var p: Playtest
var t: Util
var arena: Node
var pl: PlayerCharacter
var ov: TouchOverlay
var used: Array[StringName] = []


func run(pt: Playtest) -> void:
	p = pt
	t = Util.new(pt)
	GameState.new_game(E.WATER, true)
	AbilityRegistry.grant_starters(E.WATER)
	GameState.unlock_ability(&"water_jet", false)
	GameState.equip_ability(3, &"water_jet")
	GameState.unlock_ability(&"tidal_torrent", false)
	arena = await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": E.WATER})
	await p.wait_game(0.8)
	pl = p.player() as PlayerCharacter
	pl.controller.load_equipped()
	pl.resources.infinite_chi = true
	(arena.get("bot") as SparringBot).active = false
	var hud := arena.get("hud") as Hud
	ov = hud.touch
	if not Settings.touch_controls_enabled():
		p.note("touch controls not enabled by settings (run with MOBILE=1); forcing the overlay on")
		ov.force_active = true
	for n: String in ["_help", "_info"]:
		var l: Variant = arena.get(n)
		if l is CanvasItem:
			(l as CanvasItem).visible = false
	p.note("effects scale %.2f, tier %d, renderer %s" % [FxLib.scale(), FxLib.tier(), RenderingServer.get_current_rendering_method()])
	Events.ability_used.connect(func(id: StringName) -> void: used.append(id))
	await p.frames(3)
	p.check(ov.active, "touch overlay active")
	var ids: Array = []
	for i in 5:
		ids.append(pl.get_ability_slot_info(i).get("id", &""))
	p.note("touch slots: %s" % str(ids))
	p.check(ids[4] == &"tidal_torrent", "signature on the touch signature button")
	await p.screenshot("mobile_0_slots")
	# Each technique from its button.
	for i in 3:
		var id: StringName = ids[i]
		await _place(Vector3(0, 0, 1.0))
		await t.tap_button(ov, StringName("tech_%d" % i), 6, 0.06)
		await p.wait_game(0.5 if id != &"water_surge" else 0.95)
		await p.screenshot("mobile_%d_%s" % [i + 1, id])
		p.check(used.has(id), "%s cast from its touch button" % id)
		await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	# Hold the jet on its button.
	await _place(Vector3(0, 0, -1.0))
	var at := t.button_center(ov, &"tech_3")
	t.down(6, at)
	await p.wait_game(1.0)
	var jet := pl.controller.current
	p.check(jet != null and jet.def.id == &"water_jet" and jet.get("jetting"), "jet held from the touch button")
	await p.screenshot("mobile_4_water_jet")
	t.up(6)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	p.check(not pl.controller.is_busy(), "jet ends when the finger lifts")
	# Signature.
	await _place(Vector3(0, 0, -2.0))
	pl.resources.mark_combat()
	pl.resources.set_focus(100.0)
	await p.frames(2)
	await t.tap_button(ov, &"signature", 7, 0.06)
	await _tick_until(func() -> bool: return pl.controller.current == null or pl.controller.current.get("phase") == 1, 2.0)
	await p.wait_game(0.6)
	await p.screenshot("mobile_5_tidal_vortex")
	var t0 := Time.get_ticks_usec()
	var frames0 := Engine.get_process_frames()
	await _tick_until(func() -> bool: return pl.controller.current == null or pl.controller.current.get("phase") == 2, 2.0)
	await p.wait_game(0.25)
	await p.screenshot("mobile_6_tidal_crash")
	var dt := float(Time.get_ticks_usec() - t0) / 1e6
	p.note("frames during the vortex/crash: %d in %.2f s wall (software rendering, not a device measurement)" % [Engine.get_process_frames() - frames0, dt])
	p.check(used.has(&"tidal_torrent"), "tidal torrent cast from the signature button")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	p.note("live FX nodes after the techniques: %d" % FxLib.total_alive())


func _tick_until(cond: Callable, timeout: float = 5.0) -> bool:
	for i in int(timeout * 60.0):
		if cond.call():
			return true
		await p.get_tree().physics_frame
	return cond.call()


func _place(pos: Vector3) -> void:
	t.release_all_fingers()
	for c in BendingConstruct.live.duplicate():
		(c as BendingConstruct).crumble()
	pl.teleport(Transform3D(Basis.IDENTITY, pos))
	pl.controller.reset_cooldowns()
	await p.wait_game(0.05)
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.3)
