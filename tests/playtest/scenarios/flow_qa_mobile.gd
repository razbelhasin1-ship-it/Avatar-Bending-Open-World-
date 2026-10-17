extends RefCounted
## flow_qa on a (simulated) phone, TOUCH ONLY through the real Router (docs/qa/flow_qa.md):
## main menu (tap ENTER THE WORLD) -> element select (tap a card, tap BEGIN) -> the real new
## game load on the phone preset -> arrival skipped by a tap -> touch overlay: run with the stick,
## look with a drag, Strike + first technique -> top-bar pause -> tap RESUME -> the stick still
## drives the player (menu <-> game transitions keep touch input) -> pause -> tap RETURN TO MAIN
## MENU -> the menu answers taps again. Saves are backed up / restored.
## Run: MOBILE=1 RENDERER=mobile tools/playtest.sh flow_qa_mobile <out> 1600x720
## ELEMENT=water (default) | air | earth | fire.

const Util := preload("res://tests/playtest/scenarios/mobile_touch_util.gd")
const BACKUP := "user://saves_flow_qa_mobile_backup"

var p: Playtest
var t: Util
var e := ElementDefs.Element.WATER
var el := "water"
var used: Array[StringName] = []


func run(pt: Playtest) -> void:
	p = pt
	t = Util.new(pt)
	if OS.get_environment("ELEMENT") != "":
		e = ElementDefs.from_id(StringName(OS.get_environment("ELEMENT")))
	el = String(ElementDefs.id_of(e))
	var snap := Settings.snapshot()
	if Settings.is_mobile_device():
		Settings.apply_preset("mobile")
		Settings.set_value("display", "render_scale", 0.75)
		Settings.apply()
	if not Settings.touch_controls_enabled():
		p.note("run with MOBILE=1 for the phone state; forcing touch.controls=on")
		Settings.set_value("touch", "controls", "on")
		Settings.apply_controls()
	p.note("renderer %s, touch %s, preset %s" % [Settings.rendering_method(), Settings.touch_controls_enabled(), Settings.get_value("graphics", "preset")])
	_backup()
	Events.ability_used.connect(func(id: StringName) -> void: used.append(id))
	await p.goto_scene(Router.MAIN_MENU)
	await _flow()
	_restore()
	Settings.restore_snapshot(snap)
	Settings.apply()


func _backup() -> void:
	DirAccess.make_dir_recursive_absolute(BACKUP)
	for i in SaveSystem.MAX_SLOTS:
		if SaveSystem.has_save(i):
			DirAccess.copy_absolute(SaveSystem.slot_path(i), BACKUP.path_join("slot_%d.json" % i))
			SaveSystem.delete_save(i)


func _restore() -> void:
	for i in SaveSystem.MAX_SLOTS:
		SaveSystem.delete_save(i)
		var b := BACKUP.path_join("slot_%d.json" % i)
		if FileAccess.file_exists(b):
			DirAccess.copy_absolute(b, SaveSystem.slot_path(i))
			DirAccess.remove_absolute(b)


func _tap_control(c: Control, index: int = 0) -> void:
	var sp := t.to_screen(c, c.size * 0.5)
	t.down(index, sp)
	await p.frames(2)
	t.up(index)
	await p.frames(3)


func _tap_screen(frac: Vector2, index: int = 0) -> void:
	var vp_size := p.get_viewport().get_visible_rect().size
	t.down(index, p.get_viewport().get_screen_transform() * (vp_size * frac))
	await p.frames(2)
	t.up(index)
	await p.frames(3)


func _flow() -> void:
	await p.wait_until(func() -> bool: return p.scene() is MainMenu and not Router.is_transitioning, 60.0)
	var menu := p.scene() as MainMenu
	if not p.check(menu != null, "main menu up"):
		return
	await p.wait(2.0)
	await _tap_screen(Vector2(0.75, 0.5))
	p.check(UiInput.device == &"touch", "UI in touch mode (%s)" % UiInput.device)
	await p.screenshot("mobile_01_menu")
	await _tap_control(menu.options[0])
	var ok := await p.wait_until(func() -> bool: return p.scene() is ElementSelect and not Router.is_transitioning, 60.0)
	if not p.check(ok, "tap ENTER THE WORLD -> element select"):
		return
	var sel := p.scene() as ElementSelect
	await p.wait(1.5)
	await _tap_control(sel.card_for(e))
	await p.wait(0.6)
	p.check(sel.current == e, "tap selects the %s card" % el)
	await p.screenshot("mobile_02_select")
	await _tap_control(sel.begin_button)
	ok = await p.wait_until(func() -> bool: return p.get_tree().get_first_node_in_group(&"world_scene") != null, 60.0)
	var w := p.get_tree().get_first_node_in_group(&"world_scene") as WorldScene
	if not p.check(ok and w != null, "tap BEGIN -> new journey"):
		return
	var t0 := Time.get_ticks_msec()
	await p.wait_until(func() -> bool: return w.is_ready and not Router.is_transitioning, 400.0)
	p.check(w.is_ready, "phone load %.1f s %s" % [(Time.get_ticks_msec() - t0) / 1000.0, str(w.load_report)])
	if w.arrival:
		var arr := w.arrival
		await p.wait_until(func() -> bool: return not is_instance_valid(arr) or arr.time > 1.2, 60.0)
		await p.screenshot("mobile_03_arrival")
		await _tap_screen(Vector2(0.5, 0.5), 1)
	ok = await p.wait_until(func() -> bool: return w.playing, 60.0)
	p.check(ok, "a tap skips the arrival, control returned")
	var pl := w.player
	var ov := w.hud.touch
	if not p.check(ov != null and ov.active, "touch overlay active"):
		return
	await p.wait_game(1.0)
	await p.screenshot("mobile_04_gameplay")
	# stick + look + strike + technique
	var d := await _run_with_stick(ov, pl, 1.6)
	p.check(d > 4.0, "the stick runs (%.1f m)" % d)
	var yaw0 := pl.camera_rig.yaw
	var look_from := t.overlay_point(ov, Vector2(ov.size.x * 0.62, ov.size.y * 0.3))
	await t.drag(1, look_from, look_from + Vector2(-160, 0), 6)
	await p.wait_game(0.3)
	p.check(absf(wrapf(pl.camera_rig.yaw - yaw0, -PI, PI)) > 0.1, "a drag turns the camera")
	var n := used.size()
	for i in 3:
		await t.tap_button(ov, &"strike", 2, 0.05)
		await p.wait_game(0.3)
	await p.wait_game(0.6)
	await t.tap_button(ov, &"tech_0", 3, 0.06)
	await p.wait_game(0.8)
	await p.screenshot("mobile_05_bending")
	p.check(used.size() - n >= 2, "Strike and the first technique by tap %s" % str(used.slice(n)))
	# pause by the top bar -> RESUME by tap
	await t.tap_button(ov, &"pause", 4, 0.06)
	ok = await p.wait_until(func() -> bool: return w.pause_menu.is_open, 5.0)
	p.check(ok and p.get_tree().paused, "top-bar pause opens the pause menu")
	await p.wait(0.4)
	await p.screenshot("mobile_06_pause")
	await _tap_control(w.pause_menu.options[0])
	ok = await p.wait_until(func() -> bool: return not w.pause_menu.is_open and not p.get_tree().paused, 5.0)
	p.check(ok, "tap RESUME")
	await p.wait_game(0.4)
	d = await _run_with_stick(ov, pl, 1.2)
	p.check(d > 3.0, "the stick still drives the player after the pause menu (%.1f m)" % d)
	# pause -> RETURN TO MAIN MENU -> the menu takes taps
	await t.tap_button(ov, &"pause", 4, 0.06)
	await p.wait_until(func() -> bool: return w.pause_menu.is_open, 5.0)
	await _tap_control(w.pause_menu.options[3])
	ok = await p.wait_until(func() -> bool: return p.scene() is MainMenu and not Router.is_transitioning, 60.0)
	p.check(ok and p.get_tree().get_nodes_in_group(&"player").is_empty(), "tap RETURN TO MAIN MENU")
	t.release_all_fingers()
	var held := []
	for a in InputMap.get_actions():
		if Input.is_action_pressed(a):
			held.append(a)
	p.check(held.is_empty(), "no action held after leaving %s" % str(held))
	menu = p.scene() as MainMenu
	await p.wait(1.5)
	await _tap_control(menu.options[2])
	ok = await p.wait_until(func() -> bool: return menu.settings_menu != null and menu.settings_menu.is_open, 5.0)
	p.check(ok, "the menu answers taps after the round trip (SETTINGS opens)")
	await p.screenshot("mobile_07_menu_again")
	if ok:
		menu.settings_menu.cancel()


func _run_with_stick(ov: TouchOverlay, pl: PlayerCharacter, secs: float) -> float:
	var rest: Vector2 = ov.layout["stick_rest"]
	var r: float = ov.layout["stick_radius"]
	var p0 := pl.global_position
	await t.drag(0, t.overlay_point(ov, rest), t.overlay_point(ov, rest + Vector2(0, -r * 0.9)), 4, false)
	await p.wait_game(secs)
	t.up(0)
	await p.frames(2)
	await p.wait_game(0.3)
	return Vector2(pl.global_position.x - p0.x, pl.global_position.z - p0.z).length()
