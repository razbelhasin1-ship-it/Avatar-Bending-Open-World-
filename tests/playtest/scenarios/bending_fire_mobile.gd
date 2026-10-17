extends RefCounted
## Fire techniques on a phone (run with RENDERER=mobile MOBILE=1): the combat arena with
## the touch overlay; Fire Burst, Flame Sweep and Fire Ring from the technique buttons,
## Lightning held on its button (the charge runs while the finger stays down and the bolt
## goes when it lifts), the Inferno from the signature button - real
## InputEventScreenTouch through the overlay, so the same actions as keyboard /
## controller. Screenshots show the effects on the Mobile renderer at the mobile quality
## preset (decal caps, no heat shimmer); live FX counts and a frame-time sample are logged.

const Util := preload("res://tests/playtest/scenarios/mobile_touch_util.gd")
const E := ElementDefs.Element

var p: Playtest
var t: Util
var arena: Node
var pl: PlayerCharacter
var ov: TouchOverlay
var used: Array[StringName] = []
var hits := {}


func run(pt: Playtest) -> void:
	p = pt
	t = Util.new(pt)
	GameState.new_game(E.FIRE, true)
	AbilityRegistry.grant_starters(E.FIRE)
	GameState.unlock_ability(&"fire_ring", false)
	GameState.equip_ability(2, &"fire_ring")
	GameState.unlock_ability(&"lightning", false)
	GameState.equip_ability(3, &"lightning")
	GameState.unlock_ability(&"inferno", false)
	arena = await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": E.FIRE})
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
	p.note("effects scale %.2f, tier %d, renderer %s, mobile renderer %s, heat shimmer %s, mark caps %d / %d" % [FxLib.scale(), FxLib.tier(),
			RenderingServer.get_current_rendering_method(), str(Settings.is_mobile_renderer()), str(HeatShimmer.supported()),
			FireMarks.cap(&"burn"), FireMarks.cap(&"ring")])
	Events.ability_used.connect(func(id: StringName) -> void: used.append(id))
	Events.hit_landed.connect(func(hit: HitInfo, _t: Node, r: int) -> void:
		if r == Combat.Result.HIT or r == Combat.Result.KILLED:
			hits[hit.ability_id] = int(hits.get(hit.ability_id, 0)) + 1)
	await p.frames(3)
	p.check(ov.active, "touch overlay active")
	var ids: Array = []
	for i in 5:
		ids.append(pl.get_ability_slot_info(i).get("id", &""))
	p.note("touch slots: %s" % str(ids))
	p.check(ids.has(&"fire_burst") and ids.has(&"flame_sweep") and ids[2] == &"fire_ring" and ids[3] == &"lightning",
			"the four technique buttons carry the equipped techniques")
	p.check(ids[4] == &"inferno", "the Inferno on the touch signature button")
	await p.screenshot("mobile_0_slots")
	# Each technique from its button, at the posts.
	for i in 3:
		var id: StringName = ids[i]
		# In reach of the posts (they stand ~7.5 m north of the origin).
		var z := {&"fire_burst": -4.4, &"flame_sweep": -1.5, &"fire_ring": -3.2}
		await _place(Vector3(0, 0, float(z.get(id, 0.0))))
		await t.tap_button(ov, StringName("tech_%d" % i), 6, 0.06)
		await p.wait_game(0.45 if id == &"fire_burst" else 0.62)
		await p.screenshot("mobile_%d_%s" % [i + 1, id])
		p.check(used.has(id), "%s cast from its touch button" % id)
		await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
		p.check(int(hits.get(id, 0)) > 0, "%s hit the posts (%d)" % [id, int(hits.get(id, 0))])
	# Lightning: hold the button through the charge, lift to strike.
	await _place(Vector3(0, 0, 4.0))
	var at := t.button_center(ov, &"tech_3")
	t.down(6, at)
	await p.wait_game(1.75)
	var cur := pl.controller.current
	p.check(cur != null and cur.def.id == &"lightning" and bool(cur.get("charging")), "lightning charging while the finger is down")
	await p.screenshot("mobile_4_lightning_charge")
	var bolts0 := FireLightning.bolts
	t.up(6)
	await _tick_until(func() -> bool: return FireLightning.bolts > bolts0, 1.0)
	await p.wait_game(0.04)
	await p.screenshot("mobile_5_lightning_bolt")
	p.check(FireLightning.bolts > bolts0, "the bolt goes when the finger lifts")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	# Signature.
	await _place(Vector3(0, 0, 0.5))
	pl.resources.mark_combat()
	pl.resources.set_focus(100.0)
	await p.frames(2)
	await t.tap_button(ov, &"signature", 7, 0.06)
	await p.wait_game(0.75)
	await p.screenshot("mobile_6_inferno_vortex")
	var t0 := Time.get_ticks_usec()
	var frames0 := Engine.get_process_frames()
	await _tick_until(func() -> bool: return not FireRingWave.live.is_empty(), 2.0)
	await p.wait_game(0.25)
	await p.screenshot("mobile_7_inferno_ring")
	var dt := float(Time.get_ticks_usec() - t0) / 1e6
	p.note("frames during the inferno release: %d in %.2f s wall (software rendering, not a device measurement)" % [Engine.get_process_frames() - frames0, dt])
	p.check(used.has(&"inferno"), "inferno cast from the signature button")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	await p.wait_game(0.5)
	await p.screenshot("mobile_8_after")
	p.note("hits by ability: %s" % str(hits))
	p.note("live FX nodes after the techniques: %d, burn marks %d" % [FxLib.total_alive(), FireMarks.spawned])


func _tick_until(cond: Callable, timeout: float = 5.0) -> bool:
	for i in int(timeout * 60.0):
		if cond.call():
			return true
		await p.get_tree().physics_frame
	return cond.call()


func _place(pos: Vector3) -> void:
	t.release_all_fingers()
	pl.teleport(Transform3D(Basis.IDENTITY, pos))
	pl.controller.reset_cooldowns()
	await p.wait_game(0.05)
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.3)
