extends RefCounted
## Air on a phone (docs/modules/bending_air.md): the combat arena with the touch overlay,
## every Air technique cast from its touch button (4 technique slots + signature) by
## simulated screen touches, the slot info (get_ability_slot_info) the buttons show,
## plus a frame-time sample while the heaviest effects run (tornado + push + garden).
## Run: RENDERER=mobile MOBILE=1 tools/playtest.sh bending_air_mobile <dir> 1600x720

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
	GameState.new_game(E.AIR, true)
	arena = await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": E.AIR})
	await p.wait_game(0.8)
	pl = p.player() as PlayerCharacter
	(arena.get("bot") as SparringBot).active = false
	pl.resources.infinite_chi = true
	var hud := arena.get("hud") as Hud
	p.check(hud != null and hud.touch != null, "HUD owns a touch overlay")
	ov = hud.touch
	if not Settings.touch_controls_enabled():
		p.note("touch controls not enabled by settings (run with MOBILE=1); forcing the overlay on")
		ov.force_active = true
	for n: String in ["_help", "_info"]:
		var l: Variant = arena.get(n)
		if l is CanvasItem:
			(l as CanvasItem).visible = false
	p.note("renderer %s, mobile device %s, detail %d, effects %.2f" % [Settings.rendering_method(), Settings.is_mobile_device(),
			Settings.detail_level(), Settings.effects_scale()])
	var ids := [&"air_push", &"wind_blade", &"air_scooter", &"vortex_ward"]
	for i in 4:
		pl.controller.set_slot(StringName("technique_%d" % (i + 1)), AbilityRegistry.get_def(ids[i]))
	pl.controller.set_slot(&"signature", AbilityRegistry.get_def(&"air_tornado"))
	Events.ability_used.connect(func(id: StringName) -> void: used.append(id))
	await p.frames(3)
	p.check(ov.active and ov.visible, "overlay active")
	# The slot info the touch buttons (and the HUD bar) read.
	for i in 5:
		var info := pl.get_ability_slot_info(i)
		p.check(not info.is_empty() and info.has("icon") and info.has("cooldown_ratio"), "slot %d info: %s" % [i, str(info.get("id", ""))])
	await _place(Vector3(0, 0, -3.0))
	var idle := await _frame_time(1.0)
	p.note("frame time idle in the arena (mobile, baseline): %.1f ms avg, %.1f ms worst" % [idle.x, idle.y])
	await p.screenshot("mobile_air_idle")

	# Technique buttons 1-4 + signature, each from its own button.
	var buttons := [&"tech_0", &"tech_1", &"tech_2", &"tech_3", &"signature"]
	var want := [&"air_push", &"wind_blade", &"air_scooter", &"vortex_ward", &"air_tornado"]
	for i in 5:
		# The scooter starts in the open lane between the dummies and the pillars.
		var spots := [Vector3(0, 0, -2.5), Vector3(0, 0, -2.5), Vector3(-1.6, 0, 10.0), Vector3(0, 0, -2.5), Vector3(0, 0, 1.0)]
		await _place(spots[i])
		pl.resources.set_focus(100.0)
		var n0 := used.size()
		await t.tap_button(ov, buttons[i], 6, 0.08)
		var ok := await _until(func() -> bool: return used.slice(n0).has(want[i]), 0.6)
		p.check(ok, "%s cast from the %s button" % [want[i], buttons[i]])
		await p.wait_game(0.35 if i != 4 else 1.2)
		await p.screenshot("mobile_air_%s" % String(want[i]))
		if want[i] == &"air_scooter":
			# Ride: the stick steers the ball, the jump button launches off.
			var rest: Vector2 = ov.layout["stick_rest"]
			var r: float = ov.layout["stick_radius"]
			var from := t.overlay_point(ov, rest)
			await t.drag(0, from, t.overlay_point(ov, rest + Vector2(0, -r * 0.92)), 4, false)
			await p.wait_game(0.8)
			var spd := Vector2(pl.velocity.x, pl.velocity.z).length()
			p.check(spd > 10.0, "stick steers the scooter (%.1f m/s)" % spd)
			await p.screenshot("mobile_air_scooter_ride")
			await t.tap_button(ov, &"jump", 7, 0.06)
			await p.wait_game(0.2)
			t.up(0)
			await p.frames(1)
			p.check(pl.controller.current == null or pl.controller.current.def.id != &"air_scooter" or
					String(pl.controller.current.get("end_reason")) == "jump", "jump button launches off the ball")
		if want[i] == &"air_tornado":
			var ft := await _frame_time(1.0)
			p.note("frame time during the tornado (mobile): %.1f ms avg, %.1f ms worst" % [ft.x, ft.y])
		await _until(func() -> bool: return not pl.controller.is_busy(), 6.0)
		if want[i] == &"vortex_ward":
			await t.tap_button(ov, &"tech_3", 6, 0.06)
		await p.wait_game(0.4)
		ov.release_all()
		t.release_all_fingers()
	# Garden: vegetation / props / torches under a push on the mobile renderer.
	var garden := AirPlaytestGarden.build(arena, Vector3(0, 0, 14.0))
	await p.wait_game(0.5)
	await _place(Vector3(0, 0, 14.6))
	var calm := await _frame_time(0.8)
	p.note("frame time in the garden, calm (mobile, baseline): %.1f ms avg, %.1f ms worst" % [calm.x, calm.y])
	pl.controller.reset_cooldowns()
	await t.tap_button(ov, &"tech_0", 6, 0.06)
	await p.wait_game(0.15)
	var ft2 := await _frame_time(0.8)
	p.note("frame time in the garden under the push (mobile): %.1f ms avg, %.1f ms worst" % [ft2.x, ft2.y])
	await p.screenshot("mobile_air_garden_push")
	p.check(garden.torches_out() >= 1, "push blew out torches (%d)" % garden.torches_out())
	p.note("abilities used by touch: %s" % str(used))


func _until(cond: Callable, timeout: float) -> bool:
	for i in int(timeout * 60.0):
		if cond.call():
			return true
		await p.get_tree().physics_frame
	return cond.call()


func _place(pos: Vector3) -> void:
	ov.release_all()
	if pl.get_lock_target() != null:
		pl.targeting.call("toggle_lock")
	pl.teleport(Transform3D(Basis.IDENTITY, pos))
	await p.wait_game(0.1)
	pl.camera_rig.snap_behind(pl)
	pl.controller.reset_cooldowns()
	await p.wait_game(0.3)


func _px() -> float:
	return t.to_screen(ov, Vector2(100, 0)).x - t.to_screen(ov, Vector2.ZERO).x


func _frame_time(seconds: float) -> Vector2:
	var n := 0
	var sum := 0.0
	var worst := 0.0
	var t_end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < t_end:
		await p.get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000.0
		last = now
		sum += dt
		worst = maxf(worst, dt)
		n += 1
	return Vector2(sum / maxf(n, 1), worst)
