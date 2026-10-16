extends TestCase
## Mobile module (docs/modules/mobile.md): TouchActions (multi-source holds, minimum hold,
## menu actions as events, release_all), TouchStick maths (dead zone, edge sprint with
## hysteresis, base follow), TouchLayout (no overlaps / on screen for every scale, aspect
## and hand), TouchOverlay routing (stick + look + buttons on separate fingers at once,
## hold buttons, empty slots, contextual prompt, lock tap / cycle / hold, hide releases
## everything, mounted mode), the HUD hand-over (ability bar + prompt), haptics throttle,
## MobilePlatform back / background, PlatformInfo, export presets and the CI workflow.

const MOVE: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right"]

var _hud: Hud
var _mock: HudMockPlayer


func after_each() -> void:
	if _hud and is_instance_valid(_hud):
		_hud.touch.release_all()
		_hud.queue_free()
	_hud = null
	if _mock and is_instance_valid(_mock):
		_mock.queue_free()
	_mock = null
	for a in InputMap.get_actions():
		if Input.is_action_pressed(a):
			Input.action_release(a)


## A HUD bound to a mock player with the touch overlay forced on, laid out at 1920x1080.
func _overlay(mock: HudMockPlayer = null) -> TouchOverlay:
	_mock = mock if mock != null else HudMockPlayer.new()
	if _mock.slots.is_empty():
		_mock.setup_sample(ElementDefs.Element.FIRE)
	add_child(_mock)
	_hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child(_hud)
	_hud.bind_player(_mock)
	var ov := _hud.touch
	ov.force_active = true
	ov.haptics.vibrate = Callable()
	await frames(2)
	ov.size = Vector2(1920, 1080)
	ov._relayout()
	await frames(2)
	return ov


func _center(ov: TouchOverlay, id: StringName) -> Vector2:
	return (ov.buttons[id] as TouchButton).get_center()


# --- TouchActions ----------------------------------------------------------------------------

func test_actions_sources_and_min_hold() -> void:
	var acts := TouchActions.new()
	var clock := {"f": 100}
	acts.frame_source = func() -> int: return int(clock["f"])
	acts.press(&"jump", &"a")
	expect(Input.is_action_pressed(&"jump"), "press holds the action")
	acts.press(&"jump", &"b")
	acts.release(&"jump", &"a")
	expect(Input.is_action_pressed(&"jump"), "still held by the second source")
	acts.release(&"jump", &"b")
	expect(Input.is_action_pressed(&"jump"), "a 0-frame tap is kept for the minimum hold")
	clock["f"] = 101
	acts.flush()
	expect(Input.is_action_pressed(&"jump"), "still held after 1 tick")
	clock["f"] = 102
	acts.flush()
	expect(not Input.is_action_pressed(&"jump"), "released after MIN_HOLD_FRAMES ticks")
	# A long press releases at once.
	acts.press(&"dodge", &"x")
	clock["f"] = 140
	acts.release(&"dodge", &"x")
	expect(not Input.is_action_pressed(&"dodge"), "held long enough -> immediate release")
	expect(acts.history.has(&"jump") and acts.history.has(&"dodge"), "press edges logged")


func test_actions_analog_strength_and_release_all() -> void:
	var acts := TouchActions.new()
	acts.set_strength(&"move_forward", &"stick", 0.4)
	expect_near(Input.get_action_strength(&"move_forward"), 0.4, 0.01, "analog strength")
	acts.set_strength(&"move_forward", &"stick", 0.9)
	expect_near(Input.get_action_strength(&"move_forward"), 0.9, 0.01, "strength updates")
	acts.press(&"block", &"defend")
	acts.release_all()
	expect(not Input.is_action_pressed(&"move_forward") and not Input.is_action_pressed(&"block"), "release_all lets go of everything")
	expect(acts.held_actions().is_empty(), "nothing left held")


func test_actions_menu_actions_are_events() -> void:
	var acts := TouchActions.new()
	var seen: Array = []
	var probe := _EventProbe.new()
	probe.sink = seen
	add_child(probe)
	acts.tap(&"pause", &"pause")
	await frames(3)
	expect(seen.has("pause:true"), "pause delivered as a pressed InputEventAction (%s)" % str(seen))
	expect(seen.has("pause:false"), "and released right after (never waits for a paused tick)")
	expect(not acts.is_held(&"pause"), "nothing pending")
	probe.queue_free()


class _EventProbe extends Node:
	var sink: Array = []

	func _input(event: InputEvent) -> void:
		if event is InputEventAction and (event as InputEventAction).action == &"pause":
			sink.append("pause:%s" % str((event as InputEventAction).pressed))


# --- TouchStick ------------------------------------------------------------------------------

func test_stick_math() -> void:
	expect_eq(TouchStick.stick_vector(Vector2.ZERO, Vector2(5, 0), 100.0, 0.1), Vector2.ZERO, "inside the dead zone")
	var half := TouchStick.stick_vector(Vector2.ZERO, Vector2(0, -55), 100.0, 0.1)
	expect_near(half.length(), 0.5, 0.01, "half travel -> 0.5 (dead zone rescaled)")
	expect(half.y < 0.0 and absf(half.x) < 0.001, "up is -y (forward)")
	expect_near(TouchStick.stick_vector(Vector2.ZERO, Vector2(300, 0), 100.0, 0.1).length(), 1.0, 0.001, "clamped to 1")
	var b := TouchStick.follow_base(Vector2.ZERO, Vector2(300, 0), 145.0)
	expect_near(b.x, 155.0, 0.01, "base dragged after the thumb")
	expect_eq(TouchStick.follow_base(Vector2.ZERO, Vector2(100, 0), 145.0), Vector2.ZERO, "base stays when close")


func test_stick_edge_sprint_hysteresis() -> void:
	var s := TouchStick.new()
	add_child(s)
	s.radius = 100.0
	s.begin(0, Vector2(500, 500), Rect2(0, 0, 1920, 1080))
	s.move(Vector2(500, 420))
	expect(not s.sprinting, "0.8 R: no sprint")
	s.move(Vector2(500, 395))
	expect(s.sprinting, "past the ring: sprint")
	s.move(Vector2(500, 410))
	expect(s.sprinting, "hysteresis keeps sprinting at 0.9 R")
	s.move(Vector2(500, 430))
	expect(not s.sprinting, "back under 0.84 R: stop sprinting")
	s.auto_sprint = false
	s.move(Vector2(500, 300))
	expect(not s.sprinting, "auto sprint off")
	s.end()
	expect(s.vector == Vector2.ZERO and not s.is_active(), "end resets")
	s.begin(1, Vector2(5, 1075), Rect2(0, 0, 1920, 1080))
	expect(s.base.x >= 100.0 and s.base.y <= 980.0, "base kept on screen (%s)" % str(s.base))
	s.queue_free()


# --- TouchLayout -------------------------------------------------------------------------------

func test_layout_no_overlaps_on_screen() -> void:
	var ids: Array = [&"strike", &"heavy", &"dodge", &"defend", &"jump", &"tech_0", &"tech_1", &"tech_2", &"tech_3", &"signature", &"interact",
			&"pause", &"lock", &"call", &"map", &"journal"]
	var top: Array = [&"pause", &"lock", &"call", &"map", &"journal"]
	for size: Vector2 in [Vector2(1920, 1080), Vector2(2400, 1080), Vector2(2520, 1080), Vector2(1920, 1440), Vector2(1920, 1200), Vector2(1700, 1080)]:
		for sc: float in [0.6, 1.0, 1.3, 1.6]:
			for lh: bool in [false, true]:
				var l := TouchLayout.compute(Rect2(Vector2.ZERO, size), sc, lh, top)
				var bad := TouchLayout.overlaps(l, ids)
				expect(bad.is_empty(), "%s scale %.1f left %s: overlapping %s" % [str(size), sc, str(lh), str(bad)])
				for id: StringName in ids:
					var b: Dictionary = l["buttons"][id]
					var c: Vector2 = b["center"]
					var r: float = b["radius"]
					if not Rect2(Vector2.ZERO, size).grow(-2.0).encloses(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)):
						fail("%s off screen at %s scale %.1f left %s (%s r %.0f)" % [id, str(size), sc, str(lh), str(c), r])
				if sc >= 1.0:
					for id: StringName in [&"pause", &"lock", &"strike", &"jump", &"tech_0"]:
						expect(float(l["buttons"][id]["radius"]) * 2.0 >= 88.0, "%s >= 88 px touch target" % id)


func test_layout_left_handed_mirrors() -> void:
	var r := Rect2(0, 0, 1920, 1080)
	var a := TouchLayout.compute(r, 1.0, false, [&"pause"])
	var b := TouchLayout.compute(r, 1.0, true, [&"pause"])
	var sa: Vector2 = a["buttons"][&"strike"]["center"]
	var sb: Vector2 = b["buttons"][&"strike"]["center"]
	expect(sa.x > 1500.0 and sb.x < 420.0 and is_equal_approx(sa.x, 1920.0 - sb.x), "strike mirrored")
	expect((a["stick_zone"] as Rect2).position.x == 0.0 and (b["stick_zone"] as Rect2).end.x == 1920.0, "stick zone on the other side")
	expect_eq(a["buttons"][&"pause"]["center"], b["buttons"][&"pause"]["center"], "top bar stays top-right")


func test_layout_scales_and_fits_short_screens() -> void:
	var big := TouchLayout.compute(Rect2(0, 0, 1920, 1080), 1.4, false, [])
	var small := TouchLayout.compute(Rect2(0, 0, 1920, 1080), 0.8, false, [])
	expect(float(big["buttons"][&"strike"]["radius"]) > float(small["buttons"][&"strike"]["radius"]), "button_scale grows buttons")
	var squat := TouchLayout.compute(Rect2(0, 0, 1920, 640), 1.6, false, [])
	expect(float(squat["scale"]) < 1.0, "a short screen shrinks the cluster to fit (%.2f)" % float(squat["scale"]))


# --- TouchOverlay routing -------------------------------------------------------------------------

func test_overlay_hands_over_from_hud() -> void:
	var ov: TouchOverlay = await _overlay()
	expect(ov.active and ov.visible, "forced active")
	expect(not _hud.abilities.visible, "HUD ability bar hidden: the touch buttons are the slots")
	expect(ov.buttons[&"tech_0"].slot is HudAbilitySlot, "technique buttons embed the HUD slot")
	expect_eq(StringName((ov.buttons[&"tech_0"] as TouchButton).slot.info.get("id")), &"flame_sweep", "slot info polled from the player")
	Events.interaction_prompt.emit("[E] Talk to Iroh", true)
	await frames(2)
	expect(not _hud.prompt_panel.visible, "HUD prompt suppressed on touch")
	expect_eq(ov.prompt_text, "Talk to Iroh", "key prefix stripped")
	expect((ov.buttons[&"interact"] as TouchButton).visible, "contextual button shown")
	Events.interaction_prompt.emit("", false)
	await frames(2)
	expect(not (ov.buttons[&"interact"] as TouchButton).visible, "and hidden again")
	ov.force_active = false
	await frames(2)
	expect(not ov.active and _hud.abilities.visible, "touch off -> HUD bar back")


func test_overlay_multitouch_stick_look_buttons() -> void:
	var ov: TouchOverlay = await _overlay()
	var looks: Array = []
	var on_look := func(d: Vector2) -> void: looks.append(d)
	Events.look_input.connect(on_look)
	var rest: Vector2 = ov.layout["stick_rest"]
	var r: float = ov.layout["stick_radius"]
	ov.touch_down(0, rest)
	ov.touch_move(0, rest + Vector2(0, -r * 0.6), Vector2(0, -r * 0.6))
	expect(Input.is_action_pressed(&"move_forward") and Input.get_action_strength(&"move_forward") > 0.4, "stick finger -> move_forward")
	ov.touch_down(1, Vector2(1100, 300))
	ov.touch_move(1, Vector2(1060, 300), Vector2(-40, 0))
	expect(looks.size() == 1 and (looks[0] as Vector2).x < 0.0, "look finger -> Events.look_input")
	ov.touch_down(2, _center(ov, &"defend"))
	expect(Input.is_action_pressed(&"block"), "defend finger holds block")
	ov.touch_down(3, _center(ov, &"strike"))
	expect(Input.is_action_pressed(&"attack_light") and Input.is_action_pressed(&"block"), "two buttons at once")
	ov.touch_move(0, rest + Vector2(0, -r * 1.3), Vector2(0, -r * 0.7))
	expect(Input.is_action_pressed(&"sprint"), "stick past the ring sprints")
	ov.touch_up(2)
	await physics_frames(3)
	expect(not Input.is_action_pressed(&"block") and Input.is_action_pressed(&"attack_light"), "only the lifted finger's action releases")
	ov.touch_up(0)
	await physics_frames(3)
	for a in MOVE:
		expect(not Input.is_action_pressed(a), "%s released with the thumb" % a)
	expect(not Input.is_action_pressed(&"sprint"), "sprint released")
	# A second finger landing in the stick zone while the stick is busy looks instead.
	ov.touch_down(4, rest)
	ov.touch_down(5, rest + Vector2(40, 0))
	expect_eq(StringName(ov._owners[5]["kind"]), &"none", "look already owned by finger 1 -> ignored")
	ov.touch_up(1)
	ov.touch_up(3)
	ov.touch_up(4)
	ov.touch_up(5)
	await physics_frames(3)
	expect(not Input.is_action_pressed(&"attack_light"), "strike released")
	Events.look_input.disconnect(on_look)


func test_overlay_gui_events_route_by_index() -> void:
	var ov: TouchOverlay = await _overlay()
	var t := InputEventScreenTouch.new()
	t.index = 7
	t.pressed = true
	t.position = _center(ov, &"jump")
	ov._gui_input(t)
	expect(Input.is_action_pressed(&"jump"), "ScreenTouch on Jump presses jump")
	var m := InputEventMouseButton.new()
	m.device = InputEvent.DEVICE_ID_EMULATION
	m.button_index = MOUSE_BUTTON_LEFT
	m.pressed = true
	m.position = _center(ov, &"strike")
	ov._gui_input(m)
	expect(not Input.is_action_pressed(&"attack_light"), "mouse emulated from touch is ignored (no double press)")
	t.pressed = false
	ov._gui_input(t)
	await physics_frames(3)
	expect(not Input.is_action_pressed(&"jump"), "release by index")


func test_overlay_empty_slots_hidden_and_hide_releases() -> void:
	var mock := HudMockPlayer.new()
	mock.setup_sample(ElementDefs.Element.WATER)
	mock.slots[2] = {}
	var ov: TouchOverlay = await _overlay(mock)
	await frames(2)
	expect(not (ov.buttons[&"tech_2"] as TouchButton).visible, "empty technique slot is not a button")
	expect((ov.buttons[&"tech_1"] as TouchButton).visible, "equipped slot shown")
	ov.touch_down(0, _center(ov, &"defend"))
	ov.touch_down(1, ov.layout["stick_rest"])
	ov.touch_move(1, (ov.layout["stick_rest"] as Vector2) + Vector2(80, 0), Vector2(80, 0))
	expect(Input.is_action_pressed(&"block") and Input.is_action_pressed(&"move_right"), "held")
	Events.dialogue_started.emit(null)
	await frames(2)
	expect(not ov.active, "dialogue hides the overlay")
	expect(not Input.is_action_pressed(&"block") and not Input.is_action_pressed(&"move_right"), "hiding releases every held action")
	Events.dialogue_ended.emit(null)
	await frames(2)
	expect(ov.active, "back after the dialogue")


func test_overlay_lock_tap_cycle_hold() -> void:
	var mock := _LockMock.new()
	var ov: TouchOverlay = await _overlay(mock)
	var lockb := _center(ov, &"lock")
	expect((ov.buttons[&"lock"] as TouchButton).visible, "lock button in the top bar")
	ov.touch_down(0, lockb)
	ov.touch_up(0)
	expect(ov.actions.history.has(&"lock_on"), "tap while free presses lock_on (lock)")
	await physics_frames(3)
	mock.lock_target = mock.targets[0]
	ov.touch_down(0, lockb)
	ov.touch_up(0)
	expect(mock.lock_target == mock.targets[1], "tap while locked cycles to the next target")
	var n_before := ov.actions.history.count(&"lock_on")
	ov.touch_down(0, lockb)
	for i in 40:
		await get_tree().physics_frame
	ov.touch_up(0)
	expect(ov.actions.history.count(&"lock_on") == n_before + 1, "holding the lock button presses lock_on once (release)")
	expect(mock.lock_target == mock.targets[1], "hold did not cycle")


class _Targeting extends RefCounted:
	var owner_mock: Object

	func cycle(dir: float) -> void:
		var list: Array = owner_mock.get("targets")
		var cur: Variant = owner_mock.get("lock_target")
		var i := list.find(cur)
		if i >= 0 and dir > 0.0 and i + 1 < list.size():
			owner_mock.set("lock_target", list[i + 1])


class _LockMock extends HudMockPlayer:
	var targets: Array = []
	var targeting: _Targeting

	func _init() -> void:
		super()
		targeting = _Targeting.new()
		targeting.owner_mock = self
		for i in 2:
			var t := HudMockPlayer.make_target("Bandit %d" % i)
			add_child(t)
			targets.append(t)


func test_overlay_mounted_mode() -> void:
	var mock := _MountMock.new()
	var ov: TouchOverlay = await _overlay(mock)
	mock.state = PlayerCharacter.State.MOUNTED
	await frames(3)
	expect_eq(ov.mode, &"mounted", "mounted mode")
	expect((ov.buttons[&"jump"] as TouchButton).visible and not (ov.buttons[&"strike"] as TouchButton).visible, "ascend kept, combat hidden")
	expect((ov.buttons[&"descend"] as TouchButton).visible, "flyer -> descend button")
	var it: TouchButton = ov.buttons[&"interact"]
	expect(it.visible and it.action == &"mount", "dismount button presses mount")
	ov.touch_down(0, it.get_center())
	expect(Input.is_action_pressed(&"mount"), "tap dismount")
	ov.touch_up(0)
	mock.state = PlayerCharacter.State.LOCOMOTION
	await frames(3)
	expect(ov.mode == &"normal" and (ov.buttons[&"strike"] as TouchButton).visible, "back to combat buttons")
	await physics_frames(3)
	expect(not Input.is_action_pressed(&"mount"), "mount released")


class _FlyerMount extends Node3D:
	var flight: Object = RefCounted.new()
	var burrow: Object = null


class _MountMock extends HudMockPlayer:
	var state: int = PlayerCharacter.State.LOCOMOTION
	var mount_node: Node3D

	func _init() -> void:
		super()
		mount_node = _FlyerMount.new()
		add_child(mount_node)

	func get_state() -> int:
		return state

	func is_alive() -> bool:
		return true


func test_overlay_drives_real_player_input() -> void:
	WorldData.use_flat_world(true)
	var ground := PlayerSim.ground(self)
	var pl := PlayerSim.player(self, ElementDefs.Element.AIR, Vector3.ZERO)
	pl.input.virtual_mode = false
	await PlayerSim.step(pl, 3)
	_hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child(_hud)
	_hud.bind_player(pl)
	var ov := _hud.touch
	ov.force_active = true
	await frames(2)
	ov.size = Vector2(1920, 1080)
	ov._relayout()
	var rest: Vector2 = ov.layout["stick_rest"]
	var r: float = ov.layout["stick_radius"]
	var p0 := pl.global_position
	ov.touch_down(0, rest)
	ov.touch_move(0, rest + Vector2(0, -r), Vector2(0, -r))
	await PlayerSim.step(pl, 60)
	expect(pl.global_position.distance_to(p0) > 3.0, "the stick moves a real PlayerCharacter (%.1f m)" % pl.global_position.distance_to(p0))
	ov.touch_up(0)
	ov.touch_down(1, _center(ov, &"jump"))
	ov.touch_up(1)
	await PlayerSim.step(pl, 4)
	expect(pl.velocity.y > 1.0 or not pl.is_on_floor(), "a quick tap on Jump jumps (min hold reaches PlayerInput)")
	await PlayerSim.step(pl, 90)
	ov.release_all()
	pl.queue_free()
	ground.queue_free()
	WorldData.use_flat_world(false)


# --- Haptics ------------------------------------------------------------------------------------

func test_haptics_throttle_and_routing() -> void:
	var h := TouchHaptics.new()
	var clock := {"t": 1000}
	var calls: Array = []
	h.clock = func() -> int: return int(clock["t"])
	h.vibrate = func(ms: int, amp: float) -> void: calls.append([ms, amp])
	var player := Node3D.new()
	player.add_to_group(&"player")
	add_child(player)
	var enemy := Node3D.new()
	add_child(enemy)
	var hit := HitInfo.new()
	hit.team = Combat.Team.PLAYER
	h.on_hit_landed(hit, enemy, Combat.Result.HIT)
	expect(calls.size() == 1 and int(calls[0][0]) == 16, "light hit -> short pulse")
	clock["t"] = 1020
	h.on_hit_landed(hit, enemy, Combat.Result.HIT)
	expect(calls.size() == 1, "throttled inside the gap")
	hit.is_heavy = true
	h.on_hit_landed(hit, enemy, Combat.Result.HIT)
	expect(calls.size() == 2 and int(calls[1][0]) == 34, "a stronger pulse may cut in")
	var enemy_hit := HitInfo.new()
	enemy_hit.team = Combat.Team.ENEMY
	clock["t"] = 2000
	h.on_hit_landed(enemy_hit, player, Combat.Result.DEFLECTED)
	expect(calls.size() == 3 and int(calls[2][0]) == 30, "parry pulse")
	clock["t"] = 3000
	h.on_hit_landed(enemy_hit, enemy, Combat.Result.HIT)
	expect(calls.size() == 3, "enemy hits on others never buzz")
	h.enabled = false
	h.on_player_damaged(10.0, enemy_hit)
	expect(calls.size() == 3, "disabled by the setting")
	player.queue_free()
	enemy.queue_free()


# --- Platform ----------------------------------------------------------------------------------

func test_platform_back_and_background() -> void:
	var mp := MobilePlatform.ensure(get_tree())
	await frames(2)
	expect(is_instance_valid(mp) and mp.is_inside_tree(), "platform node installed")
	expect(not get_tree().quit_on_go_back, "back never quits the app")
	expect_eq(mp.back_pressed(), &"ui_cancel", "back in menus = ui_cancel")
	var fake := Node.new()
	fake.add_to_group(&"playable_scene")
	add_child(fake)
	var paused := {"n": 0}
	var probe := _PauseProbe.new()
	probe.sink = paused
	add_child(probe)
	expect_eq(mp.back_pressed(), &"pause", "back in gameplay = pause")
	await frames(3)
	expect(int(paused["n"]) >= 1, "pause event delivered")
	Input.action_press(&"block")
	mp.went_to_background()
	expect(not Input.is_action_pressed(&"block"), "background releases held actions")
	await frames(3)
	expect(int(paused["n"]) >= 2, "and pauses the game")
	fake.queue_free()
	probe.queue_free()


class _PauseProbe extends Node:
	var sink: Dictionary

	func _input(event: InputEvent) -> void:
		if event is InputEventAction and (event as InputEventAction).action == &"pause" and event.is_pressed():
			sink["n"] = int(sink["n"]) + 1


func test_platform_info() -> void:
	expect(PlatformInfo.can_quit() == (not OS.has_feature("web") and OS.get_name() != "iOS"), "can_quit")
	expect(not PlatformInfo.describe().is_empty(), "describe")
	expect(PlatformInfo.has_threads(), "desktop build has threads")


func test_render_compat_multimesh_colours() -> void:
	var buf := PackedFloat32Array()
	for i in 2:
		for k in 16:
			buf.append(float(i * 100 + k))
	var out := RenderCompat.add_white(buf, 2)
	expect_eq(out.size(), 40, "stride 20")
	expect(out[12] == 1.0 and out[15] == 1.0 and out[32] == 1.0, "white colours inserted")
	expect(out[16] == 12.0 and out[19] == 15.0 and out[36] == 112.0 and out[39] == 115.0, "custom data after the colour")
	expect(out[0] == 0.0 and out[11] == 11.0 and out[20] == 100.0 and out[31] == 111.0, "transforms kept")
	# (The GPU side is verified by mobile_veg_world_probe / mobile_world on the Compatibility
	# renderer; the headless dummy renderer stores no MultiMesh data.)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.instance_count = 2
	expect_eq(RenderCompat.buffer_for(mm, buf).size(), 40, "buffer_for converts for a coloured MultiMesh")
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.use_custom_data = true
	mm2.instance_count = 2
	expect_eq(RenderCompat.buffer_for(mm2, buf), buf, "and leaves others alone")
	var plain := MultiMesh.new()
	plain.transform_format = MultiMesh.TRANSFORM_3D
	RenderCompat.configure(plain, true)
	expect(plain.use_colors == RenderCompat.multimesh_colors_needed(), "colours only where the renderer needs them")


func test_mobile_renderer_feature_flags() -> void:
	# FSR 1.0 3D scaling is Forward+ only in 4.7 (the Mobile renderer warns and falls back).
	if Settings.is_mobile_renderer() or Settings.is_compatibility_renderer():
		expect(not Settings.is_feature_supported("fsr1"), "no FSR on mobile / compatibility")
	else:
		expect(Settings.is_feature_supported("fsr1"), "FSR on Forward+")


# --- Export presets / CI ---------------------------------------------------------------------------

func test_export_presets() -> void:
	var cfg := ConfigFile.new()
	expect_eq(cfg.load("res://export_presets.cfg"), OK, "export_presets.cfg present")
	var by_platform := {}
	for s in cfg.get_sections():
		if s.begins_with("preset.") and not s.ends_with(".options"):
			by_platform[String(cfg.get_value(s, "platform", ""))] = s
	for plat: String in ["Android", "iOS", "Web", "Linux", "Windows Desktop"]:
		expect(by_platform.has(plat), "preset for %s" % plat)
		# The heightmap (.r16.zlib) is not a resource type Godot knows: without the include
		# filter every exported build silently falls back to the flat world.
		if by_platform.has(plat):
			expect(String(cfg.get_value(by_platform[plat], "include_filter", "")).contains("assets/world/*"), "%s exports the raw world data" % plat)
	if by_platform.has("Android"):
		var o := String(by_platform["Android"]) + ".options"
		expect(bool(cfg.get_value(o, "architectures/arm64-v8a", false)), "Android arm64-v8a")
		# Godot 4 takes the orientation from the project (sensor landscape) and keeps the screen on.
		expect(int(ProjectSettings.get_setting("display/window/handheld/orientation", -1)) in [0, 4], "landscape orientation")
		expect(bool(ProjectSettings.get_setting("display/window/energy_saving/keep_screen_on", false)), "keep screen on")
		expect(bool(cfg.get_value(o, "permissions/vibrate", false)), "vibrate permission (haptics)")
		expect(bool(cfg.get_value(o, "screen/immersive_mode", false)), "immersive")
		expect(String(cfg.get_value(o, "package/unique_name", "")).begins_with("com."), "package id")
	if by_platform.has("Web"):
		var w := String(by_platform["Web"]) + ".options"
		expect(not bool(cfg.get_value(w, "variant/thread_support", true)), "web: threads off")


func test_ci_workflow() -> void:
	var f := FileAccess.open("res://.github/workflows/build.yml", FileAccess.READ)
	expect(f != null, "workflow present")
	if f == null:
		return
	var y := f.get_as_text()
	for needle: String in ["4.7.2", "tools/test.sh", "export_web.sh", "export_android.sh", "Windows Desktop", "upload-artifact", "deploy-pages", "workflow_dispatch", "continue-on-error"]:
		expect(y.contains(needle), "workflow mentions %s" % needle)
