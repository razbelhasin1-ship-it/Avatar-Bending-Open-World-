extends RefCounted
## flow_qa: the four main-menu buttons and the settings, through the REAL Router and the
## keyboard / pad UI actions (checklist items 1, 2, 3, 16, 17; docs/qa/flow_qa.md):
##   boot -> main menu (four options) -> 03 SETTINGS: the Graphics tab's quality preset changed with
##   ui_right changes the real viewport / sun / environment / shadow atlas, the render-scale row the
##   3D scale; CANCEL restores everything -> 01 ENTER THE WORLD (no save) -> element select ->
##   Back pressed DURING the fade-in (the Router used to drop it: stuck screen) -> main menu ->
##   02 TUTORIAL -> element select in tutorial mode -> PRACTISE AS FIREBENDER -> the real training
##   grounds (nothing saved) -> pause -> RETURN TO MAIN MENU (clean state) -> 04 EXIT GAME calls
##   quit. Settings and saves are restored afterwards.

var p: Playtest
var snapshot: Dictionary = {}


func run(pt: Playtest) -> void:
	p = pt
	snapshot = Settings.snapshot()
	_backup_saves()
	# The real launch path: boot.tscn (project main scene) routes to the main menu.
	await p.load_scene("res://scenes/boot.tscn")
	var menu := await _menu()
	if menu == null:
		return
	var labels := menu.options.filter(func(o: MenuOptionButton) -> bool: return o.visible).map(func(o: MenuOptionButton) -> String: return o.label_text)
	p.check(labels == ["ENTER THE WORLD", "TUTORIAL", "SETTINGS", "EXIT GAME"], "four main-menu options %s" % str(labels))
	await p.screenshot("menus_01_main")
	await _settings(menu)
	menu = await _menu()
	await _enter_world_and_back(menu)
	menu = await _menu()
	await _tutorial(menu)
	menu = await _menu()
	await _exit(menu)
	Settings.restore_snapshot(snapshot)
	Settings.apply()
	_restore_saves()


## The run's own (empty) save folder: user://saves_test is shared by every test run on the
## machine, and a save appearing there mid-run turns 01 into the Continue chooser.
var _prev_save_dir := ""


func _backup_saves() -> void:
	_prev_save_dir = SaveSystem.save_dir
	SaveSystem.save_dir = "user://saves_flow_qa_menus"
	DirAccess.make_dir_recursive_absolute(SaveSystem.save_dir)
	for i in SaveSystem.MAX_SLOTS:
		SaveSystem.delete_save(i)


func _restore_saves() -> void:
	SaveSystem.save_dir = _prev_save_dir


func _ui(action: StringName) -> void:
	await p.tap(action, 0.05)
	await p.frames(2)


func _focus_owner() -> Control:
	return p.get_tree().root.get_viewport().gui_get_focus_owner()


func _menu() -> MainMenu:
	await p.wait_until(func() -> bool: return p.scene() is MainMenu and not Router.is_transitioning, 90.0)
	var menu := p.scene() as MainMenu
	if not p.check(menu != null, "main menu up (%s)" % p.scene()):
		return null
	await p.wait_until(func() -> bool: return _focus_owner() is MenuOptionButton, 30.0)
	# back to 01 (focus returns to the option a sub-screen was opened from)
	var guard := 0
	while _focus_owner() != menu.options[0] and guard < 5:
		guard += 1
		await _ui(&"ui_up")
	p.check(_focus_owner() == menu.options[0], "01 ENTER THE WORLD focused")
	return menu


# --- 03 SETTINGS: options change the real renderer state --------------------------------------------------

func _settings(menu: MainMenu) -> void:
	await _ui(&"ui_down")
	await _ui(&"ui_down")
	p.check(_focus_owner() == menu.options[2], "03 SETTINGS focused")
	await _ui(&"ui_accept")
	await p.wait_until(func() -> bool: return menu.settings_menu != null and menu.settings_menu.is_open, 10.0)
	var sm := menu.settings_menu
	if not p.check(sm != null and sm.is_open, "settings overlay opened by 03 SETTINGS"):
		return
	sm.persist = false          # never write the developer's settings.cfg from a test
	sm.show_tab("graphics")
	await p.wait(0.4)
	var vp := p.get_tree().root.get_viewport()
	var pano := menu.panorama
	var before := _render_state(vp, pano)
	p.note("render state before: %s" % str(before))
	# Quality preset row: focus it and step with ui_left until "low"
	var row: SettingRow = sm.rows.get("graphics.preset")
	if p.check(row != null, "graphics preset row exists"):
		row.widget.grab_focus()
		await p.frames(2)
		var guard := 0
		while String(Settings.get_value("graphics", "preset")) != "low" and guard < 8:
			guard += 1
			await _ui(&"ui_left")
		p.check(String(Settings.get_value("graphics", "preset")) == "low", "ui_left on the preset row selects Low (%s)" % Settings.get_value("graphics", "preset"))
	await p.wait(0.3)
	var low := _render_state(vp, pano)
	p.note("render state with Low: %s" % str(low))
	p.check(int(Settings.get_value("graphics", "shadows")) == 1 and not bool(Settings.get_value("graphics", "glow")), "Low preset values set (shadows 1, glow off)")
	p.check(low["msaa"] == Viewport.MSAA_DISABLED and low["ssaa"] == Viewport.SCREEN_SPACE_AA_DISABLED, "anti-aliasing off on the real viewport")
	p.check(low["glow"] == false and low["sun_mode"] != before["sun_mode"] and low["mesh_lod"] > before["mesh_lod"], "the menu scene's environment glow, sun shadow cascades and mesh LOD follow the preset")
	p.check(low["pos_atlas"] < before["pos_atlas"], "positional shadow atlas shrinks (%d -> %d)" % [before["pos_atlas"], low["pos_atlas"]])
	await p.screenshot("menus_02_settings_low")
	# Render scale on the Display tab
	sm.show_tab("display")
	await p.wait(0.3)
	sm.set_option("display", "render_scale", 0.7, "graphics")
	await p.frames(2)
	p.check(absf(vp.scaling_3d_scale - 0.7) < 0.01, "render scale 70%% applied to the viewport (%.2f)" % vp.scaling_3d_scale)
	# Cancel restores everything
	sm.cancel()
	await p.wait(0.4)
	var after := _render_state(vp, pano)
	p.check(not sm.is_open and str(after) == str(before), "CANCEL restores the renderer state (%s)" % str(after))
	p.check(_focus_owner() == menu.options[2], "focus back on 03 SETTINGS")


func _render_state(vp: Viewport, pano: Node) -> Dictionary:
	var env: Environment = pano.get("environment")
	var sun: DirectionalLight3D = pano.get("sun")
	return {"msaa": vp.msaa_3d, "ssaa": vp.screen_space_aa, "taa": vp.use_taa, "scale": snappedf(vp.scaling_3d_scale, 0.01),
			"mesh_lod": vp.mesh_lod_threshold, "pos_atlas": vp.positional_shadow_atlas_size,
			"glow": env.glow_enabled if env else null, "ssao": env.ssao_enabled if env else null,
			"sun_shadow": sun.shadow_enabled if sun else null, "sun_mode": sun.directional_shadow_mode if sun else -1}


# --- 01 ENTER THE WORLD -> element select -> Back during the fade-in -------------------------------------

func _enter_world_and_back(menu: MainMenu) -> void:
	var had_save := SaveSystem.has_any_save()
	await _ui(&"ui_accept")
	if had_save:
		await p.wait_until(func() -> bool: return menu.chooser.visible, 5.0)
		p.check(menu.chooser.visible, "01 ENTER THE WORLD with a save opens the Continue / New Journey chooser")
		await _ui(&"ui_right")
		await _ui(&"ui_accept")
	var swapped := await p.wait_until(func() -> bool: return p.scene() is ElementSelect, 60.0)
	p.check(swapped, "01 ENTER THE WORLD routes to the element select")
	p.check(Router.is_transitioning, "(element select still fading in when Back is pressed)")
	await _ui(&"ui_cancel")       # Back while the Router fades the screen in
	var back := await p.wait_until(func() -> bool: return p.scene() is MainMenu and not Router.is_transitioning, 60.0)
	p.check(back, "Back pressed during the fade-in returns to the main menu (was a dead screen)")


# --- 02 TUTORIAL -> tutorial-mode select -> training grounds -> pause -> menu -------------------------------

func _tutorial(menu: MainMenu) -> void:
	await _ui(&"ui_down")
	p.check(_focus_owner() == menu.options[1], "02 TUTORIAL focused")
	await _ui(&"ui_accept")
	await p.wait_until(func() -> bool: return p.scene() is ElementSelect and not Router.is_transitioning, 60.0)
	var sel := p.scene() as ElementSelect
	if not p.check(sel != null and sel.tutorial, "02 TUTORIAL opens the element select in tutorial mode"):
		return
	await p.wait_until(func() -> bool: return sel.cards[0].has_focus(), 60.0)
	var guard := 0
	while sel.current != ElementDefs.Element.FIRE and guard < 6:
		guard += 1
		await _ui(&"ui_right")
		await p.wait(0.2)
	await _ui(&"ui_accept")
	await p.wait(0.3)
	p.check(sel.begin_button.text.begins_with("PRACTISE AS"), "begin button reads %s" % sel.begin_button.text)
	await p.screenshot("menus_03_tutorial_select")
	await _ui(&"ui_accept")
	await p.wait_until(func() -> bool: return p.scene() is TutorialScene, 60.0)
	var t := p.scene() as TutorialScene
	if not p.check(t != null, "the training grounds load"):
		return
	await p.wait_until(func() -> bool: return t.is_ready and not Router.is_transitioning, 300.0)
	p.check(GameState.is_tutorial and GameState.element == ElementDefs.Element.FIRE and t.player.element == ElementDefs.Element.FIRE, "tutorial as a firebender (GameState.is_tutorial)")
	p.check(not SaveSystem.can_save() and not SaveSystem.save_game(SaveSystem.MAX_SLOTS - 1), "nothing can be saved in the training grounds")
	await p.wait_until(func() -> bool: return t.director != null and t.director.running, 30.0)
	await p.wait_game(0.5)
	await p.screenshot("menus_04_training_grounds")
	await _ui(&"pause")
	await p.wait_until(func() -> bool: return t.pause_menu.is_open, 5.0)
	p.check(t.pause_menu.is_open and t.pause_menu.options[1].disabled, "pause in the tutorial: SAVE GAME disabled")
	await p.screenshot("menus_05_tutorial_pause")
	await _ui(&"ui_down")
	await _ui(&"ui_down")
	await _ui(&"ui_down")
	p.check(_focus_owner() == t.pause_menu.options[3], "RETURN TO MAIN MENU focused (disabled SAVE skipped or focusable)")
	await _ui(&"ui_accept")
	var back := await p.wait_until(func() -> bool: return p.scene() is MainMenu and not Router.is_transitioning, 60.0)
	p.check(back and p.get_tree().get_nodes_in_group(&"player").is_empty() and not p.get_tree().paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
			"back at the main menu: no player, not paused, mouse visible")


# --- 04 EXIT GAME --------------------------------------------------------------------------------------------

func _exit(menu: MainMenu) -> void:
	var quits := []
	menu.quit_override = func() -> void: quits.append(true)
	await _ui(&"ui_up")          # wraps from 01 to 04
	p.check(_focus_owner() == menu.options[3], "ui_up from 01 wraps to 04 EXIT GAME")
	await _ui(&"ui_accept")
	await p.wait_until(func() -> bool: return not quits.is_empty(), 5.0)
	p.check(quits.size() == 1, "04 EXIT GAME quits the game")
