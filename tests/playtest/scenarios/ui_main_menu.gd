extends RefCounted
## Main menu: panorama at two moments of its drift, keyboard/controller navigation of the
## four options, settings overlay opened from option 03 and closed with Back.
## Env: SHOTS=quick only takes the two panorama shots.


func run(p: Playtest) -> void:
	var menu := await p.load_scene("res://scenes/ui/main_menu.tscn") as MainMenu
	if not p.check(menu != null, "main menu loads"):
		return
	var routes: Array = []
	menu.route_override = func(path: String, params: Dictionary) -> void: routes.append([path, params])
	menu.quit_override = func() -> void: routes.append(["quit", {}])
	# first frames compile shaders (software Vulkan): wait for the intro to settle
	await p.wait_until(func() -> bool: return menu.options[0].has_focus(), 60.0)
	await p.wait(1.5)
	p.check(menu.options.size() == 4, "exactly four primary options")
	p.check(menu.options[0].has_focus(), "option 01 focused after the intro")
	await p.screenshot("main_menu_a")
	menu.panorama.set_time(menu.panorama.time + 40.0)
	await p.wait(1.0)
	await p.screenshot("main_menu_b")
	if OS.get_environment("SHOTS") == "quick":
		return
	# navigate with the controller/keyboard actions
	await p.tap(&"ui_down")
	await p.wait(0.4)
	p.check(menu.options[1].has_focus(), "ui_down moves to 02 TUTORIAL")
	await p.tap(&"ui_down")
	await p.wait(0.5)
	p.check(menu.options[2].has_focus(), "ui_down moves to 03 SETTINGS")
	await p.screenshot("main_menu_focus_settings")
	await p.tap(&"ui_accept")
	await p.wait(0.8)
	p.check(menu.settings_menu != null and menu.settings_menu.is_open, "settings overlay opens")
	await p.screenshot("settings_display")
	for t in ["graphics", "audio", "controls", "gameplay"]:
		menu.settings_menu.show_tab(t)
		await p.wait(0.5)
		await p.screenshot("settings_%s" % t)
	await p.tap(&"ui_cancel")
	await p.wait(0.6)
	p.check(not menu.settings_menu.is_open, "Back closes settings")
	p.check(menu.options[2].has_focus(), "focus returns to 03 SETTINGS")
	await p.tap(&"ui_up")
	await p.tap(&"ui_up")
	await p.wait(0.3)
	await p.tap(&"ui_accept")
	await p.wait(0.5)
	p.check(routes.size() > 0 or menu.chooser.is_open, "ENTER THE WORLD routes or opens the chooser")
	await p.screenshot("main_menu_after_enter")
