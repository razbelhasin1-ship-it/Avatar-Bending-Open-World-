extends RefCounted
## The real world on a (simulated) phone, touch only: the HUD + touch overlay over streamed
## terrain, run with the stick, look with a drag, strike, call the companion with the top-bar
## button, ride it through the contextual button (mounted layout: Ascend / Descend /
## Dismount, no combat buttons), take off and land a flyer, dismount by tap.
## Run: MOBILE=1 RENDERER=mobile tools/playtest.sh mobile_world .playtest/mobile_world 1600x720
## ELEMENT=air (sky bison, default) | water (polar bear dog) | earth | fire.

const Util := preload("res://tests/playtest/scenarios/mobile_touch_util.gd")
const Follow := preload("res://tests/playtest/scenarios/companions_follow.gd")
const S := PlayerCharacter.State

var p: Playtest
var t: Util
var w: WorldScene
var pl: PlayerCharacter
var ov: TouchOverlay


func run(pt: Playtest) -> void:
	p = pt
	t = Util.new(pt)
	if Settings.is_mobile_device():
		Settings.apply_preset("mobile")
		Settings.set_value("display", "render_scale", 0.75)
		Settings.apply()
	var e := ElementDefs.Element.AIR
	if OS.get_environment("ELEMENT") != "":
		e = ElementDefs.from_id(StringName(OS.get_environment("ELEMENT")))
	GameState.new_game(e)
	GameState.intro_done = true
	GameState.time_of_day = 10.5
	var spawn: Transform3D = Follow.route_start(WorldData.get_spawn(e).origin, 140.0, 22.0)
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": false, "spawn": spawn, "skip_intro": true}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.playing, 240.0)
	if not p.check(ok, "world ready"):
		return
	pl = w.player
	ov = w.hud.touch
	if not Settings.touch_controls_enabled():
		ov.force_active = true
	await p.wait_game(2.0)
	p.check(ov.active, "touch overlay active in the world")
	await p.screenshot("world_01_touch_hud")
	await _move_and_look()
	await _strike()
	await _companion()


func _move_and_look() -> void:
	var rest: Vector2 = ov.layout["stick_rest"]
	var r: float = ov.layout["stick_radius"]
	var p0 := pl.global_position
	await t.drag(0, t.overlay_point(ov, rest), t.overlay_point(ov, rest + Vector2(0, -r * 1.2)), 4, false)
	await p.wait_game(2.0)
	var look_from := t.overlay_point(ov, Vector2(ov.size.x * 0.6, ov.size.y * 0.3))
	await t.drag(1, look_from, look_from + Vector2(-140, 0), 6)
	await p.wait_game(1.0)
	await p.screenshot("world_02_running")
	t.up(0)
	await p.frames(2)
	await p.wait_game(0.5)
	p.check(pl.global_position.distance_to(p0) > 8.0, "ran %.0f m with the stick" % pl.global_position.distance_to(p0))


func _strike() -> void:
	var n := {"used": 0}
	var cb := func(_id: StringName) -> void: n["used"] += 1
	Events.ability_used.connect(cb)
	for i in 3:
		await t.tap_button(ov, &"strike", 2, 0.05)
		await p.wait_game(0.3)
		if i == 2:
			await p.screenshot("world_03_strike")
	await t.tap_button(ov, &"tech_0", 3, 0.06)
	await p.wait_game(0.6)
	Events.ability_used.disconnect(cb)
	p.check(int(n["used"]) >= 3, "strikes / technique by touch in the world (%d)" % n["used"])


func _companion() -> void:
	var c := pl.get_companion() as Companion
	if not p.check(c != null, "companion present"):
		return
	p.check((ov.buttons[&"call"] as TouchButton).visible, "call-companion button in the top bar")
	await t.tap_button(ov, &"call", 4, 0.06)
	# A called flyer arrives by air and lands: wait until it stands on the ground.
	var grounded := await p.wait_until(func() -> bool: return not c.is_airborne() and c.mode != Companion.Mode.CALLED, 40.0)
	p.note("companion after the call: %s (grounded %s)" % [c.get_mode_name(), str(grounded)])
	await p.wait_game(0.5)
	# Stand at its flank so the Ride prompt shows (the contextual button).
	var fwd := CompanionNav.dir_of(c.motor.yaw)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var stand := c.global_position - right * (c.prof.radius() + 1.2)
	stand.y = WorldData.get_height(stand.x, stand.z) + 0.1
	pl.teleport(Transform3D(Basis(Vector3.UP, CompanionNav.yaw_of(CompanionNav.flat_dir(c.global_position - stand))), stand))
	var shown := await p.wait_until(func() -> bool: return (ov.buttons[&"interact"] as TouchButton).visible, 3.0)
	p.check(shown, "contextual button for the companion (%s)" % ov.prompt_text)
	await p.screenshot("world_04_ride_prompt")
	if not shown:
		return
	await t.tap_button(ov, &"interact", 5, 0.06)
	var seated := await p.wait_until(func() -> bool: return c.mode == Companion.Mode.RIDDEN, 8.0)
	p.check(seated, "tap -> riding")
	await p.wait_game(0.8)
	p.check(ov.mode == &"mounted", "overlay in mounted mode")
	p.check(not (ov.buttons[&"strike"] as TouchButton).visible and (ov.buttons[&"jump"] as TouchButton).visible, "combat buttons hidden, ascend kept")
	p.check((ov.buttons[&"interact"] as TouchButton).visible and (ov.buttons[&"interact"] as TouchButton).action == &"mount", "dismount button")
	await p.screenshot("world_05_mounted")
	if c.flight != null:
		pl.camera_rig.set_yaw(c.motor.yaw)
		var jb := t.button_center(ov, &"jump")
		t.down(6, jb)
		await p.frames(1)
		var flew := await p.wait_until(func() -> bool: return c.is_flying(), 10.0)
		await p.wait_game(1.5)
		t.up(6)
		await p.frames(1)
		p.check(flew, "hold Ascend: the flyer takes off")
		await p.wait_game(1.0)
		await p.screenshot("world_06_flying")
		p.check((ov.buttons[&"descend"] as TouchButton).visible, "descend button while riding a flyer")
		var db := t.button_center(ov, &"descend")
		t.down(6, db)
		await p.frames(1)
		var landed := await p.wait_until(func() -> bool: return not c.is_flying(), 25.0)
		t.up(6)
		await p.frames(1)
		p.check(landed, "hold Descend: lands")
		await p.wait_game(1.0)
	await t.tap_button(ov, &"interact", 7, 0.06)
	var off := await p.wait_until(func() -> bool: return pl.get_state() == S.LOCOMOTION or pl.get_state() == S.AIRBORNE, 8.0)
	p.check(off, "tap Dismount -> on foot (%s)" % pl.get_state_name())
	await p.wait_game(1.0)
	p.check(ov.mode == &"normal" and (ov.buttons[&"strike"] as TouchButton).visible, "combat layout back")
	await p.screenshot("world_07_dismounted")
