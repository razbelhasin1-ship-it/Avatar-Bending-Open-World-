extends RefCounted
## Settings over the main menu: key binding table (keyboard glyphs, then controller
## glyphs), press-to-bind capture with a conflict warning, graphics preset change, and
## Cancel restoring everything. Uses the real input path for the capture.


func run(p: Playtest) -> void:
	var menu := await p.load_scene("res://scenes/ui/main_menu.tscn") as MainMenu
	menu.route_override = func(_path: String, _params: Dictionary) -> void: pass
	await p.wait_until(func() -> bool: return menu.options[0].has_focus(), 60.0)
	var s := menu.open_settings()
	s.persist = false
	await p.wait(0.4)
	s.show_tab("controls")
	await p.wait(0.3)
	var cell := s.key_binds.get_button(&"jump", "kbm")
	cell.grab_focus()
	await p.wait(0.6)
	await p.screenshot("settings_bindings_kbm")
	UiInput.device = &"pad"
	UiInput.ensure(p.get_tree()).device_changed.emit(&"pad")
	s.key_binds.get_button(&"jump", "pad").grab_focus()
	await p.wait(0.5)
	await p.screenshot("settings_bindings_pad")
	UiInput.device = &"kbm"
	UiInput.ensure(p.get_tree()).device_changed.emit(&"kbm")
	# press-to-bind: activate the cell, then press E (already used by Interact)
	cell.grab_focus()
	await p.tap(&"ui_accept")
	# pace on state, not wall time: software rendering at 1080p can take longer per frame
	# than the prompt's guard window
	p.check(await p.wait_until(func() -> bool: return s.rebind_prompt.is_listening(), 20.0), "bind cell opens the capture prompt")
	await p.wait(0.4)
	await p.screenshot("settings_rebind_capture")
	var e := InputEventKey.new()
	e.physical_keycode = KEY_E
	e.keycode = KEY_E
	e.pressed = true
	Input.parse_input_event(e)
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await p.wait_until(func() -> bool: return not s.rebind_prompt.conflicts.is_empty(), 20.0)
	await p.wait(0.3)
	p.check(s.rebind_prompt.conflicts.has(&"interact"), "conflict with Interact detected")
	await p.screenshot("settings_rebind_conflict")
	s.rebind_prompt.swap_button.pressed.emit()
	await p.wait(0.3)
	var jump_e := false
	for ev in InputMap.action_get_events(&"jump"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_E:
			jump_e = true
	p.check(jump_e, "swap bound Jump to E in the InputMap")
	# graphics preset, then cancel everything
	s.show_tab("graphics")
	s.set_option("graphics", "preset", "low", "preset")
	await p.wait(0.4)
	await p.screenshot("settings_graphics_low")
	s.cancel()
	await p.wait(0.3)
	var jump_space := false
	for ev in InputMap.action_get_events(&"jump"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_SPACE:
			jump_space = true
	p.check(jump_space, "cancel restored the Jump binding")
	p.check(Settings.get_value("graphics", "preset") != "low" or Settings.DEFAULTS["graphics"]["preset"] == "low", "cancel restored the preset")
