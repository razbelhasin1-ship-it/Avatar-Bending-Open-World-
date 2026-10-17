extends RefCounted
## Earth techniques on a phone (run with RENDERER=mobile MOBILE=1): the combat
## arena with the touch overlay; Earth Pillar, Earth Stomp and Earth Wall from
## the technique buttons, Earth Spikes from the 4th, the pillar held on its
## button to ride it up (self-lift), the Earthquake from the signature button -
## real InputEventScreenTouch through the overlay, so the same actions as
## keyboard / controller. Screenshots show the effects on the mobile renderer
## at the mobile quality preset (effects scale, decal caps); FX counts logged.

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
	GameState.new_game(E.EARTH, true)
	AbilityRegistry.grant_starters(E.EARTH)
	GameState.unlock_ability(&"earth_spikes", false)
	GameState.equip_ability(3, &"earth_spikes")
	GameState.unlock_ability(&"earthquake", false)
	arena = await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": E.EARTH})
	await p.wait_game(0.8)
	pl = p.player() as PlayerCharacter
	pl.controller.load_equipped()
	pl.resources.infinite_chi = true
	(arena.get("bot") as SparringBot).active = false
	GroundSampler.add_zone(&"earth_dirt", Rect2(-8.0, -13.0, 16.0, 19.0), &"dirt", 0.0)
	var hud := arena.get("hud") as Hud
	ov = hud.touch
	if not Settings.touch_controls_enabled():
		p.note("touch controls not enabled by settings (run with MOBILE=1); forcing the overlay on")
		ov.force_active = true
	for n: String in ["_help", "_info"]:
		var l: Variant = arena.get(n)
		if l is CanvasItem:
			(l as CanvasItem).visible = false
	p.note("effects scale %.2f, tier %d, detail %d, renderer %s, mark caps crater %d fissure %d" % [FxLib.scale(), FxLib.tier(), Settings.detail_level(),
			RenderingServer.get_current_rendering_method(), FxLib.cap_of(&"earth_mark_crater"), FxLib.cap_of(&"earth_mark_fissure")])
	Events.ability_used.connect(func(id: StringName) -> void: used.append(id))
	await p.frames(3)
	p.check(ov.active, "touch overlay active")
	var ids: Array = []
	for i in 5:
		ids.append(pl.get_ability_slot_info(i).get("id", &""))
	p.note("touch slots: %s" % str(ids))
	p.check(ids[0] == &"earth_pillar" and ids[1] == &"earth_stomp" and ids[2] == &"earth_wall" and ids[3] == &"earth_spikes", "techniques on the touch buttons")
	p.check(ids[4] == &"earthquake", "signature on the touch signature button")
	await p.screenshot("mobile_0_slots")
	# Each technique from its button (tap).
	for i in 4:
		var id: StringName = ids[i]
		await _place(Vector3(0, 0, 1.0))
		await t.tap_button(ov, StringName("tech_%d" % i), 6, 0.06)
		await p.wait_game(0.55 if id != &"earth_wall" else 0.8)
		await p.screenshot("mobile_%d_%s" % [i + 1, id])
		p.check(used.has(id), "%s cast from its touch button" % id)
		await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	# Hold the pillar button: ride the column up.
	await _place(Vector3(-3, 0, 2.0))
	var y0 := pl.global_position.y
	var at := t.button_center(ov, &"tech_0")
	t.down(6, at)
	await p.wait_game(0.6)
	t.up(6)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	await p.wait_game(0.5)
	p.check(pl.global_position.y > y0 + 2.5, "held pillar button: rode the column up (%.1f m)" % (pl.global_position.y - y0))
	await p.screenshot("mobile_5_on_the_pillar")
	# Signature.
	await _place(Vector3(0, 0, -2.0))
	pl.resources.mark_combat()
	pl.resources.set_focus(100.0)
	await p.frames(2)
	var t0 := Time.get_ticks_usec()
	var frames0 := Engine.get_process_frames()
	await t.tap_button(ov, &"signature", 7, 0.06)
	await _tick_until(func() -> bool: return not EarthShockwave.live.is_empty(), 2.5)
	await p.wait_game(0.2)
	await p.screenshot("mobile_6_earthquake")
	var dt := float(Time.get_ticks_usec() - t0) / 1e6
	p.note("frames during the earthquake: %d in %.2f s wall (software rendering, not a device measurement)" % [Engine.get_process_frames() - frames0, dt])
	p.check(used.has(&"earthquake"), "earthquake cast from the signature button")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	await p.wait_game(0.4)
	await p.screenshot("mobile_7_aftermath")
	p.note("live FX nodes after the techniques: %d (marks: crater %d, fissure %d; rubble %d)" % [FxLib.total_alive(), FxLib.alive_count(&"earth_mark_crater"),
			FxLib.alive_count(&"earth_mark_fissure"), FxLib.alive_count(&"earth_rubble")])
	p.check(FxLib.alive_count(&"earth_mark_fissure") <= FxLib.cap_of(&"earth_mark_fissure"), "marks stay within the mobile caps")
	GroundSampler.remove_zone(&"earth_dirt")


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
	await _tick_until(func() -> bool: return BendingConstruct.live.is_empty(), 1.5)
	pl.teleport(Transform3D(Basis.IDENTITY, pos))
	pl.controller.reset_cooldowns()
	await p.wait_game(0.05)
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.3)
