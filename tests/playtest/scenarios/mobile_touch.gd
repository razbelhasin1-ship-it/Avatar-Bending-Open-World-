extends RefCounted
## Touch controls end to end in the combat arena (docs/modules/mobile.md), driven ONLY by
## simulated screen touches (InputEventScreenTouch / ScreenDrag through the real GUI path):
## floating stick (walk, run, edge sprint), drag-to-look, Strike combo on a dummy, Heavy
## charge, Defend hold, a technique with its cooldown sweep, lock-on tap / cycle / hold,
## the contextual Interact button, multi-touch (run + strike + look at once), the pause
## button and RESUME by tap.
## Run: MOBILE=1 RENDERER=mobile tools/playtest.sh mobile_touch .playtest/mobile_touch 1600x720
## (ELEMENT=air|earth|fire|water, default fire). Without MOBILE=1 the overlay is forced on.

const Util := preload("res://tests/playtest/scenarios/mobile_touch_util.gd")
const S := PlayerCharacter.State

var p: Playtest
var t: Util
var arena: Node
var pl: PlayerCharacter
var ov: TouchOverlay
var hits := 0
var used: Array[StringName] = []


func run(pt: Playtest) -> void:
	p = pt
	t = Util.new(pt)
	var e := ElementDefs.Element.FIRE
	if OS.get_environment("ELEMENT") != "":
		e = ElementDefs.from_id(StringName(OS.get_environment("ELEMENT")))
	arena = await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": e})
	await p.wait_game(0.8)
	pl = p.player() as PlayerCharacter
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
	await p.frames(3)
	p.check(ov.active and ov.visible, "overlay active")
	p.check(not hud.abilities.visible, "HUD ability bar hidden on touch (the buttons are the slots)")
	Events.hit_landed.connect(_on_hit)
	Events.ability_used.connect(func(id: StringName) -> void: used.append(id))
	await p.screenshot("touch_01_idle")
	await _stick()
	await _look()
	await _strike()
	await _heavy_defend()
	await _technique()
	await _lock()
	await _interact()
	await _multitouch()
	await _pause()
	p.note("hits landed by touch: %d, abilities used: %s" % [hits, str(used)])


func _on_hit(hit: HitInfo, _target: Node, result: int) -> void:
	if hit.team == Combat.Team.PLAYER and (result == Combat.Result.HIT or result == Combat.Result.KILLED):
		hits += 1


func _place(pos: Vector3, yaw_deg: float = 0.0) -> void:
	ov.release_all()
	pl.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos))
	await p.wait_game(0.1)
	pl.camera_rig.snap_behind(pl)
	pl.resources.set_chi(PlayerResources.CHI_MAX)
	await p.wait_game(0.3)


func _stick() -> void:
	await _place(Vector3(0, 0, 10), 180.0)
	var rest: Vector2 = ov.layout["stick_rest"]
	var r: float = ov.layout["stick_radius"]
	var from := t.overlay_point(ov, rest)
	var walk_to := t.overlay_point(ov, rest + Vector2(0, -r * 0.4))
	var p0 := pl.global_position
	await t.drag(0, from, walk_to, 4, false)
	await p.wait_game(0.8)
	p.check(Input.is_action_pressed(&"move_forward"), "stick presses move_forward")
	var walk_v := Vector2(pl.velocity.x, pl.velocity.z).length()
	p.check(walk_v > 1.0 and walk_v < pl.profile.run_speed * 0.9, "half push walks (%.1f m/s)" % walk_v)
	t.move(0, t.overlay_point(ov, rest + Vector2(r * 0.25, -r * 0.92)))
	await p.frames(1)
	await p.wait_game(0.8)
	var run_v := Vector2(pl.velocity.x, pl.velocity.z).length()
	p.check(run_v > walk_v + 1.0 and not Input.is_action_pressed(&"sprint"), "full push runs (%.1f m/s), no sprint" % run_v)
	t.move(0, t.overlay_point(ov, rest + Vector2(0, -r * 1.3)))
	await p.frames(1)
	await p.wait_game(0.9)
	var sprint_v := Vector2(pl.velocity.x, pl.velocity.z).length()
	p.check(Input.is_action_pressed(&"sprint") and ov.stick.sprinting, "pushing past the ring sprints")
	p.check(sprint_v > run_v + 0.5, "sprint faster than run (%.1f > %.1f m/s)" % [sprint_v, run_v])
	await p.screenshot("touch_02_stick_sprint")
	t.up(0)
	await p.frames(2)
	await p.wait_game(0.1)
	p.check(not Input.is_action_pressed(&"move_forward") and not Input.is_action_pressed(&"sprint"), "lifting the thumb releases move + sprint")
	p.check(pl.global_position.distance_to(p0) > 4.0, "the stick moved the bender (%.1f m)" % pl.global_position.distance_to(p0))


func _look() -> void:
	var y0 := pl.camera_rig.get_yaw()
	var a := t.overlay_point(ov, Vector2(ov.size.x * 0.62, ov.size.y * 0.35))
	await t.drag(1, a, a + Vector2(-260, 0) * _px(), 8)
	var dy := absf(wrapf(pl.camera_rig.get_yaw() - y0, -PI, PI))
	p.check(dy > 0.3, "drag on the right half turns the camera (%.0f deg)" % rad_to_deg(dy))


## Design px -> window px factor (the playtest window is smaller than 1920x1080).
func _px() -> float:
	return t.to_screen(ov, Vector2(100, 0)).x - t.to_screen(ov, Vector2.ZERO).x


func _strike() -> void:
	await _place(Vector3(0, 0, -4.4), 0.0)
	var h0 := hits
	for i in 3:
		await t.tap_button(ov, &"strike", 2, 0.05)
		if i == 1:
			await p.screenshot("touch_03_strike")
		await p.wait_game(0.28)
	await p.wait_game(0.5)
	p.check(hits > h0, "Strike taps land hits on the dummy (%d)" % (hits - h0))


func _heavy_defend() -> void:
	var at := t.button_center(ov, &"defend")
	t.down(4, at)
	await p.frames(1)
	await p.wait_game(0.3)
	p.check(pl.get_state() == S.DEFEND, "holding Defend guards (state %s)" % pl.get_state_name())
	await p.screenshot("touch_04_defend")
	t.up(4)
	await p.frames(1)
	await p.wait_game(0.4)
	p.check(pl.get_state() != S.DEFEND, "lifting Defend drops the guard")
	pl.resources.set_chi(PlayerResources.CHI_MAX)
	var n0 := used.size()
	var hb := t.button_center(ov, &"heavy")
	t.down(5, hb)
	await p.frames(1)
	await p.wait_game(0.9)
	await p.screenshot("touch_05_heavy_charge")
	t.up(5)
	await p.frames(1)
	await p.wait_game(0.8)
	p.check(used.size() > n0 or hits > 0, "Heavy hold + release casts (%s)" % str(used.slice(n0)))


func _technique() -> void:
	await _place(Vector3(0, 0, -3.0), 0.0)
	var info := pl.get_ability_slot_info(0)
	p.check(not info.is_empty(), "technique slot 1 equipped (%s)" % str(info.get("id", "")))
	await t.tap_button(ov, &"tech_0", 6, 0.06)
	await p.wait_game(0.5)
	var ratio := float(pl.get_ability_slot_info(0).get("cooldown_ratio", 0.0))
	p.check(ratio > 0.0, "technique cast from its button (cooldown %.2f)" % ratio)
	var b: TouchButton = ov.buttons[&"tech_0"]
	p.check(float(b.slot.info.get("cooldown_ratio", 0.0)) > 0.0, "the touch slot shows the cooldown sweep")
	await p.wait_game(0.4)
	await p.screenshot("touch_06_technique_cooldown")


func _lock() -> void:
	await _place(Vector3(0, 0, 0.5), 0.0)
	await t.tap_button(ov, &"lock", 7, 0.06)
	await p.wait_game(0.2)
	var first := pl.get_lock_target()
	p.check(first != null, "tap lock-on locks a target")
	await p.screenshot("touch_07_locked")
	await t.tap_button(ov, &"lock", 7, 0.06)
	await p.wait_game(0.4)
	var second := pl.get_lock_target()
	p.check(second != null and second != first, "tap again cycles to the next target")
	# Swipe on the look pad while locked switches target too (PlayerTargeting flick).
	var a := t.overlay_point(ov, Vector2(ov.size.x * 0.6, ov.size.y * 0.3))
	await t.drag(1, a, a + Vector2(220, 0) * _px(), 2)
	await p.wait_game(0.4)
	p.note("after swipe: %s (was %s)" % [str(pl.get_lock_target()), str(second)])
	var lb := t.button_center(ov, &"lock")
	t.down(7, lb)
	await p.frames(1)
	await p.wait_game(0.6)
	t.up(7)
	await p.frames(1)
	await p.wait_game(0.2)
	p.check(pl.get_lock_target() == null, "holding lock-on releases the lock")


func _interact() -> void:
	await _place(Vector3(10, 0, 2), 90.0)
	var it := Interactable.new()
	it.prompt = "Read the training scroll"
	it.radius = 2.5
	it.lock_time = 0.3
	var fired := {"n": 0}
	it.interacted.connect(func(_pl: Node3D) -> void: fired["n"] += 1)
	arena.add_child(it)
	it.global_position = pl.global_position + (-pl.global_basis.z) * 1.4 + Vector3.UP * 0.9
	await p.wait_game(0.5)
	var b: TouchButton = ov.buttons[&"interact"]
	p.check(b.visible and ov.prompt_text == "Read the training scroll", "contextual button shows the prompt (%s)" % ov.prompt_text)
	p.check(not ov.hud.prompt_panel.visible, "no duplicate HUD prompt on touch")
	await p.screenshot("touch_08_interact")
	await t.tap_button(ov, &"interact", 8, 0.06)
	await p.wait_game(0.4)
	p.check(int(fired["n"]) == 1, "tapping it interacts")
	it.queue_free()
	await p.wait_game(0.3)
	p.check(not b.visible, "button hides when the prompt goes")


func _multitouch() -> void:
	await _place(Vector3(0, 0, 4.0), 0.0)
	var rest: Vector2 = ov.layout["stick_rest"]
	var r: float = ov.layout["stick_radius"]
	var h0 := hits
	var y0 := pl.camera_rig.get_yaw()
	await t.drag(0, t.overlay_point(ov, rest), t.overlay_point(ov, rest + Vector2(0, -r * 0.9)), 3, false)
	var a := t.overlay_point(ov, Vector2(ov.size.x * 0.6, ov.size.y * 0.3))
	t.down(1, a)
	await p.frames(1)
	var sb := t.button_center(ov, &"strike")
	for i in 3:
		t.down(2, sb)
		t.move(1, a + Vector2(-30.0 * (i + 1), 0) * _px())
		await p.frames(1)
		await p.wait_game(0.06)
		t.up(2)
		await p.frames(1)
		await p.wait_game(0.25)
		if i == 1:
			await p.screenshot("touch_09_multitouch")
	p.check(Input.is_action_pressed(&"move_forward"), "stick still held while striking and looking")
	p.check(absf(wrapf(pl.camera_rig.get_yaw() - y0, -PI, PI)) > 0.05, "look finger worked at the same time")
	t.up(1)
	t.up(0)
	await p.frames(2)
	await p.wait_game(0.6)
	p.check(hits > h0 or used.size() > 0, "strikes fired while moving (%d hits)" % (hits - h0))
	p.check(not Input.is_action_pressed(&"move_forward") and not Input.is_action_pressed(&"attack_light"), "all fingers up -> nothing held")


func _pause() -> void:
	var pm := PauseMenu.new()
	arena.add_child(pm)
	await p.frames(2)
	await t.tap_button(ov, &"pause", 9, 0.05)
	await p.frames(3)
	p.check(p.get_tree().paused and pm.is_open, "pause button opens the pause menu")
	await p.screenshot("touch_10_pause")
	# RESUME by tap (emulated mouse click from the touch, like a phone).
	var resume := pm.options[0]
	var at := t.to_screen(resume, resume.size * 0.5)
	t.down(0, at)
	await p.frames(2)
	t.up(0)
	await p.frames(4)
	p.check(not p.get_tree().paused and not pm.is_open, "tapping RESUME resumes")
	pm.queue_free()
