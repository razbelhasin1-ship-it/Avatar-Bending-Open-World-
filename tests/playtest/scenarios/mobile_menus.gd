extends RefCounted
## Every menu by TAP only (simulated InputEventScreenTouch; the engine emulates the mouse
## from touch exactly like a phone): main menu (no keyboard hint bar on touch) -> SETTINGS
## -> CONTROLS tab (touch section first) -> toggle Left-Handed by tap -> a drag that starts
## on a selector must not change it -> CANCEL; element select: tap a card, tap BEGIN;
## dialogue: tap the panel to advance, tap a choice.
## Run: MOBILE=1 RENDERER=mobile tools/playtest.sh mobile_menus .playtest/mobile_menus 1600x720

const Util := preload("res://tests/playtest/scenarios/mobile_touch_util.gd")

var p: Playtest
var t: Util


func run(pt: Playtest) -> void:
	p = pt
	t = Util.new(pt)
	var snap := Settings.snapshot()
	if not Settings.touch_controls_enabled():
		p.note("run with MOBILE=1 for the touch device state; forcing touch.controls=on")
		Settings.set_value("touch", "controls", "on")
		Settings.apply_controls()
	await _main_menu()
	await _element_select()
	await _dialogue()
	Settings.restore_snapshot(snap)
	Settings.apply()


func _tap_control(c: Control, index: int = 0, at: Vector2 = Vector2(-1, -1)) -> void:
	var local := c.size * 0.5 if at.x < 0.0 else at
	var sp := t.to_screen(c, local)
	t.down(index, sp)
	await p.frames(2)
	t.up(index)
	await p.frames(3)


func _main_menu() -> void:
	var menu := await p.load_scene("res://scenes/ui/main_menu.tscn") as MainMenu
	var routed := {"path": ""}
	menu.route_override = func(path: String, _params: Dictionary) -> void: routed["path"] = path
	await p.wait(2.5)
	# A first tap on the empty panorama puts the UI in touch mode.
	var vp_size := p.get_viewport().get_visible_rect().size
	t.down(0, p.get_viewport().get_screen_transform() * (vp_size * Vector2(0.75, 0.5)))
	await p.frames(2)
	t.up(0)
	await p.frames(3)
	p.check(UiInput.device == &"touch", "a touch makes the UI touch-mode (device %s)" % UiInput.device)
	p.check(menu.hint_bar.modulate.a < 0.01, "keyboard hint bar hidden on touch")
	await p.screenshot("menus_01_main_menu_touch")
	await _tap_control(menu.options[2])
	await p.wait(1.0)
	var s := menu.settings_menu
	p.check(s != null and s.is_open, "SETTINGS opens by tap")
	var controls_i := SettingsSchema.TABS.find("controls")
	await _tap_control(s.tab_buttons[controls_i])
	await p.wait(0.6)
	p.check(s.tab == controls_i, "CONTROLS tab by tap")
	var first_row: SettingRow = null
	for r: SettingRow in s.rows.values():
		if r.is_visible_in_tree() and r.get_parent() and r.get_parent().get_parent() == s.tab_pages[controls_i]:
			if first_row == null or r.get_index() < first_row.get_index():
				first_row = r
	p.check(first_row != null and String(first_row.spec.get("section")) == "touch", "touch options listed first on a touch device (%s)" % (first_row.spec.get("key") if first_row else "-"))
	await p.screenshot("menus_02_settings_controls")
	var lh: SettingRow = s.rows.get("touch.left_handed")
	var before := bool(Settings.get_value("touch", "left_handed"))
	await _tap_control(lh.focus_target)
	await p.wait(0.4)
	p.check(bool(Settings.get_value("touch", "left_handed")) != before, "tap flips the Left-Handed toggle")
	await _tap_control(lh.focus_target)
	await p.wait(0.3)
	p.check(bool(Settings.get_value("touch", "left_handed")) == before, "and back")
	# A drag that starts on a selector scrolls the page, it must not change the value.
	var oc: SettingRow = s.rows.get("touch.controls")
	var v0: Variant = Settings.get_value("touch", "controls")
	var a := t.to_screen(oc.focus_target, oc.focus_target.size * Vector2(0.85, 0.5))
	await t.drag(1, a, a + Vector2(0, -160), 6)
	await p.wait(0.3)
	p.check(Settings.get_value("touch", "controls") == v0, "drag over a selector does not change it")
	# A tap on its right arrow does.
	await _tap_control(oc.focus_target, 0, oc.focus_target.size * Vector2(0.9, 0.5))
	await p.wait(0.3)
	p.check(Settings.get_value("touch", "controls") != v0, "tap on the selector's arrow changes it (%s -> %s)" % [str(v0), str(Settings.get_value("touch", "controls"))])
	await _tap_control(s.cancel_button)
	await p.wait(0.5)
	p.check(not s.is_open and Settings.get_value("touch", "controls") == v0, "CANCEL by tap closes and restores")
	await _tap_control(menu.options[1])
	await p.frames(3)
	p.check(routed["path"] == Router.ELEMENT_SELECT, "TUTORIAL by tap routes to element select")


func _element_select() -> void:
	Router.params = {}
	var sel := await p.load_scene("res://scenes/ui/element_select.tscn") as ElementSelect
	sel.instant = true
	var routed := {"path": ""}
	sel.route_override = func(path: String, _params: Dictionary) -> void: routed["path"] = path
	await p.wait(2.0)
	var fire: ElementCard = null
	for c in sel.cards:
		if c.element == ElementDefs.Element.FIRE:
			fire = c
	await _tap_control(fire)
	await p.wait(0.8)
	p.check(sel.current == ElementDefs.Element.FIRE, "tap on the Firebender card selects it")
	p.check(sel.hint_bar.modulate.a < 0.01, "no keyboard hints on touch")
	await p.screenshot("menus_03_element_select")
	await _tap_control(sel.begin_button)
	var ok := await p.wait_until(func() -> bool: return routed["path"] != "", 8.0)
	p.check(ok, "tap on BEGIN starts the journey (%s)" % routed["path"])


func _dialogue() -> void:
	var holder := await p.load_scene("res://scenes/ui/dialogue_box.tscn")
	var box := holder as DialogueBox
	await p.frames(2)
	var done := {"said": false, "choice": -1}
	var flow := func() -> void:
		await box.say("Master Pakku", "Again. Your form is sloppy - flow, do not push.", {"element": ElementDefs.Element.WATER})
		done["said"] = true
		done["choice"] = await box.ask("Katara", "Will you help us reach the North Pole?", ["Of course.", "Not yet."])
	flow.call()
	await p.wait(0.4)
	var panel: Control = box.get_child(1) as Control
	# First tap completes the line, the second advances.
	await _tap_control(panel)
	await p.wait(0.2)
	await p.screenshot("menus_04_dialogue")
	await _tap_control(panel)
	await p.wait(0.6)
	p.check(bool(done["said"]), "tapping the dialogue panel advances the line")
	await _tap_control(panel)
	await p.wait(0.4)
	var ok := await p.wait_until(func() -> bool: return box.choices.size() == 2, 5.0)
	p.check(ok, "choices shown")
	await p.screenshot("menus_05_dialogue_choices")
	if ok:
		await _tap_control(box.choices[0])
		await p.wait(0.3)
	p.check(int(done["choice"]) == 0, "tapping a choice picks it")
