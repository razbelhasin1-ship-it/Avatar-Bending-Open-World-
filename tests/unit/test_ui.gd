extends TestCase
## UI module tests: theme/assets, main menu wiring, settings (live apply / cancel / presets /
## unsupported options), rebinding (InputMap, conflicts, swap, capture), element select
## routing in both modes, pause menu, HUD binding with a mock player, title card,
## dialogue box, loading overlay and input-device tracking.

var _nodes: Array[Node] = []
var _settings_snap: Dictionary = {}
var _saves_backup: Dictionary = {}


func before_each() -> void:
	_settings_snap = Settings.snapshot()
	_saves_backup = {}
	for i in SaveSystem.MAX_SLOTS:
		if SaveSystem.has_save(i):
			_saves_backup[i] = FileAccess.get_file_as_string(SaveSystem.slot_path(i))
	Router.params = {}
	GameState.reset()


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Settings.restore_snapshot(_settings_snap)
	Settings.apply()
	for i in SaveSystem.MAX_SLOTS:
		if _saves_backup.has(i):
			var f := FileAccess.open(SaveSystem.slot_path(i), FileAccess.WRITE)
			f.store_string(_saves_backup[i])
			f.close()
		elif SaveSystem.has_save(i):
			SaveSystem.delete_save(i)
	GameState.reset()
	await frames(2)


func _add(n: Node) -> Node:
	add_child(n)
	_nodes.append(n)
	return n


func _scene(path: String) -> Node:
	return _add((load(path) as PackedScene).instantiate())


# --- Theme & assets ---------------------------------------------------------------------------

func test_theme_builds_with_fonts_and_variations() -> void:
	var t := UiTheme.get_theme()
	expect(t != null, "theme")
	expect(t.default_font != null, "default font")
	expect(t.has_font(&"font", &"TitleLabel"), "TitleLabel font")
	expect(t.get_type_variation_base(&"PrimaryButton") == &"Button", "PrimaryButton variation")
	expect(t.get_stylebox(&"focus", &"Button") is UiFrameStyle, "focus style is the bracket frame")
	var f := UiTheme.title_font(700) as FontVariation
	expect(f != null and f.variation_opentype.values().has(700), "Cinzel weight variation")
	expect(UiTheme.brush_font().has_char("水".unicode_at(0)), "brush font has CJK")
	expect(UiTheme.title_font(600) == UiTheme.title_font(600), "fonts cached")


func test_emblems_and_icons_exist() -> void:
	for e: int in ElementDefs.ALL:
		var tex := UiTheme.emblem(e)
		expect(tex != null, "emblem %s" % ElementDefs.id_of(e))
		if tex:
			expect(tex.get_width() >= 256, "emblem resolution")
	for n in ["icon_health", "icon_chi", "icon_focus", "icon_quest", "icon_marker", "icon_discovery", "icon_unlock",
			"icon_warning", "icon_info", "icon_lock", "icon_paw", "ui_chevron", "ui_check", "ui_diamond", "ui_corner",
			"ability_blast", "ability_wall", "ability_wave", "ability_shield", "ability_flame", "ability_shards"]:
		expect(UiTheme.icon(n) != null, "icon %s" % n)
	expect(UiTheme.icon("icon_health") == UiTheme.icon("icon_health"), "textures cached (kept alive for draw calls)")


func test_element_colors_readable() -> void:
	for e: int in ElementDefs.ALL:
		expect(UiTheme.element_light(e).get_luminance() > ElementDefs.color_of(e).get_luminance() - 0.001, "light variant not darker")
	expect(UiTheme.element_color(ElementDefs.Element.NONE) == UiTheme.GOLD, "NONE falls back to gold")


# --- Input helpers ---------------------------------------------------------------------------

func test_input_device_tracking_and_labels() -> void:
	var ui := UiInput.ensure(get_tree())
	await frames(1)
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_A
	jb.pressed = true
	ui.note_event(jb)
	expect_eq(UiInput.device, &"pad", "joypad switches to pad")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_W
	k.pressed = true
	ui.note_event(k)
	expect_eq(UiInput.device, &"kbm", "key switches to kbm")
	expect_eq(UiInput.action_label(&"jump", &"kbm"), "Space")
	expect_eq(UiInput.action_label(&"jump", &"pad"), "A")
	expect_eq(UiInput.action_label(&"interact", &"kbm"), "E")
	expect_eq(UiInput.action_label(&"attack_heavy", &"pad"), "RT")
	var g := PromptGlyph.for_action(&"interact")
	g.forced_device = &"kbm"
	_add(g)
	expect_eq(g.get_label(), "E", "prompt glyph label")
	g.forced_device = &"pad"
	expect_eq(g.get_label(), "Y", "prompt glyph pad label")


# --- Main menu ---------------------------------------------------------------------------------

func _menu() -> MainMenu:
	var m := _scene("res://scenes/ui/main_menu.tscn") as MainMenu
	return m


func test_main_menu_has_exactly_four_options() -> void:
	var m := _menu()
	await frames(2)
	expect_eq(m.options.size(), 4, "four options")
	var labels: Array = []
	for o in m.options:
		labels.append("%s — %s" % [o.number, o.label_text])
	expect_eq(labels, ["01 — ENTER THE WORLD", "02 — TUTORIAL", "03 — SETTINGS", "04 — EXIT GAME"], "labels")
	expect(m.panorama != null and m.panorama.ranges.size() >= 4, "panorama built")
	expect(m.panorama.landmarks.has("air_temple") and m.panorama.landmarks.has("volcano")
			and m.panorama.landmarks.has("great_wall") and m.panorama.landmarks.has("ice"), "four nation hints")


func test_main_menu_buttons_are_wired() -> void:
	for i in SaveSystem.MAX_SLOTS:
		SaveSystem.delete_save(i)
	var m := _menu()
	await frames(2)
	var routes: Array = []
	var quits := [0]
	m.route_override = func(path: String, params: Dictionary) -> void: routes.append([path, params])
	m.quit_override = func() -> void: quits[0] += 1
	# 01 without a save -> element select (normal)
	m.options[0].pressed.emit()
	expect_eq(routes.size(), 1, "enter routes")
	if routes.size() == 1:
		expect_eq(routes[0][0], Router.ELEMENT_SELECT)
		expect_eq(bool(routes[0][1].get("tutorial", true)), false, "not tutorial")
	# 02 -> element select in tutorial mode
	m.options[1].pressed.emit()
	expect_eq(routes.size(), 2, "tutorial routes")
	if routes.size() == 2:
		expect_eq(routes[1][0], Router.ELEMENT_SELECT)
		expect_eq(bool(routes[1][1].get("tutorial", false)), true, "tutorial flag")
	# 03 -> settings overlay
	m.options[2].pressed.emit()
	await frames(2)
	expect(m.settings_menu != null and m.settings_menu.is_open, "settings opens")
	m.settings_menu.cancel()
	await frames(2)
	# 04 -> quit (after the fade)
	m.options[3].pressed.emit()
	await seconds(0.5)
	expect_eq(quits[0], 1, "exit quits")


func test_main_menu_continue_and_new_journey_with_save() -> void:
	GameState.new_game(ElementDefs.Element.FIRE)
	GameState.level = 5
	expect(SaveSystem.save_game(3), "fixture save")
	GameState.reset()
	var m := _menu()
	await frames(2)
	var routes: Array = []
	m.route_override = func(path: String, params: Dictionary) -> void: routes.append([path, params])
	expect(m.options[0].caption.contains("Firebender"), "continue caption shows the save")
	m.options[0].pressed.emit()
	await frames(1)
	expect(m.chooser.is_open, "chooser opens when a save exists")
	expect(routes.is_empty(), "no route yet")
	m.chooser.continue_button.pressed.emit()
	await frames(1)
	expect_eq(routes.size(), 1, "continue routes")
	if routes.size() == 1:
		expect_eq(routes[0][0], Router.WORLD)
		expect_eq(bool(routes[0][1].get("new_game", true)), false, "continue is not a new game")
	expect_eq(GameState.element, ElementDefs.Element.FIRE, "save loaded")
	expect_eq(GameState.level, 5, "level loaded")
	# new journey asks for confirmation first
	m.chooser.close()
	m.options[0].pressed.emit()
	m.chooser.new_button.pressed.emit()
	expect_eq(routes.size(), 1, "new journey needs confirmation")
	m.chooser.confirm_button.pressed.emit()
	expect_eq(routes.size(), 2, "confirmed new journey routes")
	if routes.size() == 2:
		expect_eq(routes[1][0], Router.ELEMENT_SELECT)


# --- Settings ------------------------------------------------------------------------------------

func _settings() -> SettingsMenu:
	var s := _scene("res://scenes/ui/settings_menu.tscn") as SettingsMenu
	s.persist = false
	return s


func test_settings_exposes_every_option() -> void:
	var s := _settings()
	await frames(1)
	s.open()
	for key in ["display.mode", "display.resolution", "display.vsync", "display.fps_limit", "display.render_scale", "display.upscaler", "display.fov",
			"graphics.preset", "graphics.antialiasing", "graphics.shadows", "graphics.ssao", "graphics.ssil", "graphics.glow", "graphics.volumetric_fog",
			"graphics.sdfgi", "graphics.view_distance", "graphics.vegetation", "graphics.effects", "graphics.detail",
			"audio.master", "audio.music", "audio.sfx", "audio.ambience", "audio.ui", "audio.voice",
			"controls.mouse_sensitivity", "controls.controller_sensitivity", "controls.invert_y", "controls.camera_distance",
			"controls.camera_shake", "controls.toggle_sprint", "touch.controls", "touch.button_scale", "touch.opacity",
			"touch.left_handed", "touch.camera_sensitivity", "touch.auto_sprint", "touch.haptics",
			"gameplay.difficulty", "gameplay.hints", "gameplay.damage_numbers", "gameplay.subtitles"]:
		expect(s.rows.has(key), "row %s" % key)
	expect(s.key_binds != null, "key binding table")
	var n := 0
	for a: StringName in InputDefaults.ACTIONS:
		if RebindLogic.is_rebindable(a):
			n += 1
			expect(s.key_binds.get_button(a, "kbm") != null and s.key_binds.get_button(a, "pad") != null, "bind cells for %s" % a)
	expect(n >= 20, "rebindable actions listed")


func test_settings_live_apply_changes_real_configuration() -> void:
	var s := _settings()
	await frames(1)
	s.open()
	var vp := get_viewport()
	s.set_option("display", "render_scale", 0.75, "graphics")
	expect_near(vp.scaling_3d_scale, 0.75, 0.001, "render scale applied to the viewport")
	s.set_option("graphics", "antialiasing", "msaa4", "graphics")
	expect_eq(vp.msaa_3d, Viewport.MSAA_4X, "MSAA applied")
	s.set_option("graphics", "glow", false, "graphics")
	var env := Environment.new()
	Settings.configure_environment(env)
	expect(not env.glow_enabled, "glow off reaches environments")
	s.set_option("audio", "music", 0.3, "audio")
	var bus := AudioServer.get_bus_index("Music")
	expect_near(AudioServer.get_bus_volume_db(bus), linear_to_db(0.3), 0.01, "music bus volume")
	s.set_option("audio", "sfx", 0.0, "audio")
	expect(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "zero volume mutes the bus")
	s.set_option("controls", "invert_y", true, "controls")
	expect(Settings.invert_y(), "invert y")
	expect(s.is_dirty(), "dirty after edits")


func test_settings_cancel_restores_snapshot() -> void:
	var s := _settings()
	await frames(1)
	var vp := get_viewport()
	var scale0 := vp.scaling_3d_scale
	var music0 := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	s.open()
	s.set_option("display", "render_scale", 0.6, "graphics")
	s.set_option("audio", "music", 0.1, "audio")
	RebindLogic.bind(&"jump", {"type": "key", "code": KEY_J})
	s.cancel()
	expect_near(vp.scaling_3d_scale, scale0, 0.001, "render scale restored")
	expect_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), music0, 0.01, "music volume restored")
	expect(not _has_key(&"jump", KEY_J), "binding restored on cancel")
	expect(not s.is_open, "cancel closes")


func test_settings_apply_keeps_changes() -> void:
	var s := _settings()
	await frames(1)
	s.open()
	var applied := [false]
	s.applied.connect(func() -> void: applied[0] = true)
	s.set_option("gameplay", "difficulty", "hard", "gameplay")
	s.apply_and_close()
	expect(applied[0], "applied signal")
	expect_eq(Settings.get_value("gameplay", "difficulty"), "hard", "kept")
	expect_near(Settings.difficulty_damage_scale(), 1.5, 0.001, "difficulty in effect")


func test_settings_presets_and_custom() -> void:
	var s := _settings()
	await frames(1)
	s.open()
	s.set_option("graphics", "preset", "low", "preset")
	expect_eq(int(Settings.get_value("graphics", "shadows")), 1, "low preset shadows")
	expect_eq((s.rows["graphics.shadows"] as SettingRow).get_widget_value(), 1, "row refreshed")
	expect_eq((s.rows["graphics.preset"] as SettingRow).get_widget_value(), "low", "preset row")
	s.set_option("graphics", "shadows", 4, "graphics")
	expect_eq(Settings.get_value("graphics", "preset"), "custom", "manual change -> custom")
	expect_eq((s.rows["graphics.preset"] as SettingRow).get_widget_value(), "custom", "preset row shows custom")
	s.restore_defaults()
	s.show_tab("graphics")
	s.restore_defaults()
	expect_eq(Settings.get_value("graphics", "preset"), Settings.DEFAULTS["graphics"]["preset"], "restore defaults (graphics tab)")


func test_settings_unsupported_options_disabled_with_tooltip() -> void:
	var s := _settings()
	await frames(1)
	s.open()
	var row: SettingRow = s.rows["display.mode"]
	if not Settings.is_feature_supported("display_mode"):
		expect(row.unsupported, "display mode unsupported here")
		expect(not row.tooltip_text.is_empty(), "tooltip explains why")
		expect((row.widget as UiChoice).disabled, "widget disabled")
	var aa: SettingRow = s.rows["graphics.antialiasing"]
	for it: Dictionary in (aa.widget as UiChoice).items:
		if it["value"] == "taa":
			expect_eq(bool(it.get("disabled", false)), not Settings.is_feature_supported("taa"), "TAA availability follows the renderer")


func test_settings_tabs_cycle() -> void:
	var s := _settings()
	await frames(1)
	s.open()
	expect_eq(s.tab, 0)
	var e := InputEventKey.new()
	e.physical_keycode = KEY_E
	e.pressed = true
	s._unhandled_input(e)
	expect_eq(s.tab, 1, "E -> next tab")
	var lb := InputEventJoypadButton.new()
	lb.button_index = JOY_BUTTON_LEFT_SHOULDER
	lb.pressed = true
	s._unhandled_input(lb)
	expect_eq(s.tab, 0, "LB -> previous tab")
	s.show_tab("gameplay")
	expect(s.tab_pages[4].visible and not s.tab_pages[0].visible, "only the current page visible")


# --- Rebinding -------------------------------------------------------------------------------------

func _has_key(action: StringName, code: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == code:
			return true
	return false


func _has_pad(action: StringName, button: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == button:
			return true
	return false


func test_rebinding_updates_input_map() -> void:
	RebindLogic.bind(&"jump", {"type": "key", "code": KEY_J})
	expect(_has_key(&"jump", KEY_J), "jump now on J")
	expect(not _has_key(&"jump", KEY_SPACE), "old key replaced")
	expect(_has_pad(&"jump", JOY_BUTTON_A), "pad binding untouched")
	RebindLogic.bind(&"dodge", {"type": "joy_button", "button": JOY_BUTTON_X})
	expect(_has_pad(&"dodge", JOY_BUTTON_X), "pad rebind")
	expect(_has_key(&"dodge", KEY_C), "kbm binding untouched")
	RebindLogic.reset_all()
	expect(_has_key(&"jump", KEY_SPACE), "reset restores defaults")


func test_rebinding_conflict_and_swap() -> void:
	var e := {"type": "key", "code": KEY_E}
	var c := RebindLogic.find_conflicts(&"jump", e)
	expect(c.has(&"interact"), "E conflicts with interact")
	RebindLogic.bind(&"jump", e, true)
	expect(_has_key(&"jump", KEY_E), "jump on E")
	expect(_has_key(&"interact", KEY_SPACE), "interact received jump's old key (swap)")
	expect(not _has_key(&"interact", KEY_E), "conflict removed from interact")
	RebindLogic.reset_all()
	RebindLogic.bind(&"jump", e, false)
	expect(_has_key(&"jump", KEY_E) and _has_key(&"interact", KEY_E), "bind anyway keeps both")
	RebindLogic.reset_all()


func test_rebind_prompt_capture_cancel_and_conflict() -> void:
	var p := RebindPrompt.new()
	_add(p)
	await frames(1)
	var results: Array = []
	p.finished.connect(func(ok: bool) -> void: results.append(ok))
	# capture a key
	p.begin(&"dodge", "kbm")
	var v := InputEventKey.new()
	v.physical_keycode = KEY_V
	v.pressed = true
	expect(p.capture(v), "key captured")
	expect(_has_key(&"dodge", KEY_V), "dodge bound to V")
	expect_eq(results, [true], "finished ok")
	# Esc cancels
	p.begin(&"dodge", "kbm")
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	p.capture(esc)
	expect(_has_key(&"dodge", KEY_V), "cancel leaves binding")
	expect_eq(results, [true, false], "cancel reported")
	# kbm capture ignores pad input and vice versa
	p.begin(&"dodge", "kbm")
	var pad_b := InputEventJoypadButton.new()
	pad_b.button_index = JOY_BUTTON_Y
	pad_b.pressed = true
	expect(not p.capture(pad_b), "pad ignored in kbm capture")
	p.cancel()
	# pad conflict -> swap
	p.begin(&"dodge", "pad")
	p.capture(pad_b)
	expect(p.conflicts.has(&"interact"), "Y conflicts with interact")
	expect(not _has_pad(&"dodge", JOY_BUTTON_Y), "not bound before resolving")
	p.swap_button.pressed.emit()
	expect(_has_pad(&"dodge", JOY_BUTTON_Y), "swap binds")
	expect(_has_pad(&"interact", JOY_BUTTON_B), "interact gets dodge's old button")
	# timeout never leaves the player stuck
	p.timeout = 0.05
	p.begin(&"jump", "kbm")
	await seconds(0.4)
	expect(not p.is_open, "capture times out")
	RebindLogic.reset_all()


# --- Element select ---------------------------------------------------------------------------------

func _select(tutorial: bool) -> ElementSelect:
	Router.params = {"tutorial": tutorial}
	var s := _scene("res://scenes/ui/element_select.tscn") as ElementSelect
	s.instant = true
	return s


func test_element_select_cards_order_and_data() -> void:
	var s := _select(false)
	await frames(2)
	var order: Array = []
	for c in s.cards:
		order.append(c.element)
	expect_eq(order, [ElementDefs.Element.EARTH, ElementDefs.Element.AIR, ElementDefs.Element.FIRE, ElementDefs.Element.WATER], "card order")
	for c in s.cards:
		var d := ElementDefs.get_data(c.element)
		expect_eq(c._tagline.text, d["tagline"], "tagline exact for %s" % d["name"])
		expect_eq(c._name.text, String(d["name"]).to_upper(), "name")
		expect(c.preview != null and c.preview.rig != null, "live character preview")
		expect(c.preview.companion != null, "companion preview")
	expect_eq(s.motifs.size(), 4, "silhouette motifs")
	expect_eq(s.backdrops.size(), 4, "backdrops")


func test_element_select_hover_changes_backdrop_and_glyphs() -> void:
	var s := _select(false)
	await frames(2)
	s.card_for(ElementDefs.Element.FIRE).grab_focus()
	await frames(2)
	expect_eq(s.current, ElementDefs.Element.FIRE, "focus selects fire")
	expect_eq(s._glyph_l.text, "火", "fire glyph")
	expect_eq(s._glyph_r.text, "烈", "fire virtue")
	expect(s.backdrops[ElementDefs.Element.FIRE].visible, "fire backdrop visible")
	expect(s.begin_button.text.contains("FIREBENDER"), "begin label")
	s.card_for(ElementDefs.Element.WATER).grab_focus()
	await frames(2)
	expect_eq(s._glyph_l.text + s._glyph_r.text, "水善", "water glyph pair")


func test_element_select_routes_new_game() -> void:
	var s := _select(false)
	await frames(2)
	var routes: Array = []
	s.route_override = func(path: String, params: Dictionary) -> void: routes.append([path, params])
	var picked := [-1]
	Events.element_selected.connect(func(e: int) -> void: picked[0] = e, CONNECT_ONE_SHOT)
	s.card_for(ElementDefs.Element.EARTH).pressed.emit()
	await frames(1)
	expect(s.begin_button.has_focus(), "choosing focuses BEGIN")
	s.begin_button.pressed.emit()
	await frames(1)
	expect_eq(routes.size(), 1, "routed once")
	if routes.size() == 1:
		expect_eq(routes[0][0], Router.WORLD)
		expect_eq(routes[0][1], {"new_game": true, "element": ElementDefs.Element.EARTH})
	expect_eq(GameState.element, ElementDefs.Element.EARTH, "GameState element")
	expect(not GameState.is_tutorial, "not tutorial")
	expect_eq(String(GameState.companion["type"]), "badgermole", "companion assigned by new_game")
	expect_eq(picked[0], ElementDefs.Element.EARTH, "element_selected emitted")


func test_element_select_tutorial_mode_routes_to_tutorial() -> void:
	var s := _select(true)
	await frames(2)
	var routes: Array = []
	s.route_override = func(path: String, params: Dictionary) -> void: routes.append([path, params])
	expect(s.tutorial, "tutorial mode from Router.params")
	s.confirm(ElementDefs.Element.AIR)
	await frames(1)
	expect_eq(routes.size(), 1)
	if routes.size() == 1:
		expect_eq(routes[0][0], Router.TUTORIAL)
		expect_eq(routes[0][1], {"element": ElementDefs.Element.AIR})
	expect(GameState.is_tutorial, "tutorial game state")
	expect_eq(GameState.element, ElementDefs.Element.AIR)


func test_element_select_back_returns_to_menu() -> void:
	var s := _select(false)
	await frames(2)
	var routes: Array = []
	s.route_override = func(path: String, params: Dictionary) -> void: routes.append(path)
	s.go_back()
	expect_eq(routes, [Router.MAIN_MENU], "back to menu")


func test_preview_plays_bending_sequence() -> void:
	var p := ElementPreview.new()
	p.size = Vector2(200, 150)
	_add(p)
	p.setup(ElementDefs.Element.FIRE)
	await seconds(0.8)
	expect(p.clips_played() >= 1, "preview started a bending clip")
	expect(p.fx is FirePreviewFx, "fire effect")
	expect(p.viewport.own_world_3d and p.viewport.transparent_bg, "isolated transparent stage")


# --- Pause menu -------------------------------------------------------------------------------------

func _pause() -> PauseMenu:
	return _scene("res://scenes/ui/pause_menu.tscn") as PauseMenu


func test_pause_menu_pauses_and_resumes() -> void:
	GameState.new_game(ElementDefs.Element.WATER)
	var p := _pause()
	await frames(1)
	var states: Array = []
	Events.pause_changed.connect(func(v: bool) -> void: states.append(v))
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var before := Input.mouse_mode   # headless display servers may ignore the request
	p.toggle()
	expect(get_tree().paused, "tree paused")
	expect(p.is_open, "open")
	expect_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "mouse shown")
	expect(p.process_mode == Node.PROCESS_MODE_ALWAYS, "runs while paused")
	p.toggle()
	expect(not get_tree().paused, "unpaused")
	expect_eq(Input.mouse_mode, before, "previous mouse mode restored")
	expect_eq(states, [true, false], "pause_changed events")
	for c in Events.pause_changed.get_connections():
		if c["callable"].get_object() == self:
			Events.pause_changed.disconnect(c["callable"])


func test_pause_menu_save_return_and_quit() -> void:
	GameState.new_game(ElementDefs.Element.EARTH)
	var p := _pause()
	await frames(1)
	var saves := [0]
	var routes: Array = []
	p.save_override = func() -> bool:
		saves[0] += 1
		return true
	p.route_override = func(path: String, _params: Dictionary) -> void: routes.append(path)
	p.quit_override = func() -> void: routes.append("quit")
	p.open()
	expect(not p.options[1].disabled, "save available in the adventure")
	expect(p.save_game(), "save game")
	expect_eq(saves[0], 1, "saved once")
	p.return_to_menu()
	expect_eq(saves[0], 2, "returning to menu saves first")
	expect_eq(routes, [Router.MAIN_MENU], "returns to main menu")
	expect(not get_tree().paused, "unpaused when leaving")
	p.quit_to_desktop()
	expect_eq(saves[0], 3, "quitting saves first")
	expect_eq(routes[-1], "quit", "quit")


func test_pause_menu_tutorial_never_saves() -> void:
	GameState.new_game(ElementDefs.Element.FIRE, true)
	var p := _pause()
	await frames(1)
	var saves := [0]
	p.save_override = func() -> bool:
		saves[0] += 1
		return true
	p.route_override = func(_path: String, _params: Dictionary) -> void: pass
	p.open()
	expect(p.options[1].disabled, "save disabled in tutorial")
	expect(not p.save_game(), "save refused")
	p.return_to_menu()
	expect_eq(saves[0], 0, "no save from the tutorial")


func test_pause_menu_opens_settings_overlay() -> void:
	GameState.new_game(ElementDefs.Element.WATER)
	var p := _pause()
	await frames(1)
	p.open()
	var s := p.open_settings()
	s.persist = false
	await frames(1)
	expect(s.is_open, "settings overlay from pause")
	p.resume()
	expect(not s.is_open, "resume closes settings")
	expect(not get_tree().paused, "resumed")


# --- HUD ----------------------------------------------------------------------------------------------

func _hud() -> Array:
	GameState.new_game(ElementDefs.Element.WATER)
	var hud := _scene("res://scenes/ui/hud.tscn") as Hud
	var mock := HudMockPlayer.new()
	_add(mock)
	mock.setup_sample(ElementDefs.Element.WATER)
	hud.bind_player(mock)
	return [hud, mock]


func test_hud_binds_mock_player_resources() -> void:
	var hm := _hud()
	var hud: Hud = hm[0]
	var mock: HudMockPlayer = hm[1]
	await frames(1)
	expect_near(hud.vitals.health_bar.ratio, 1.0, 0.001, "full health")
	mock.health.apply_damage(40.0)
	expect_near(hud.vitals.health_bar.ratio, 120.0 / 160.0, 0.001, "health follows HealthComponent")
	expect(hud.vitals.health_bar.trail > hud.vitals.health_bar.ratio, "loss leaves a trail")
	mock.set_chi(25.0)
	expect_near(hud.vitals.chi_bar.ratio, 0.25, 0.001, "chi from resource_changed")
	Events.player_resource_changed.emit(&"focus", 100.0, 100.0)
	expect_near(hud.abilities.signature.focus_ratio, 1.0, 0.001, "focus fills the signature slot")


func test_hud_ability_slots_cooldowns_and_failures() -> void:
	var hm := _hud()
	var hud: Hud = hm[0]
	var mock: HudMockPlayer = hm[1]
	mock.set_cooldown(0, 0.5, 3.0)
	mock.set_available(1, false)
	await frames(2)
	expect_eq(StringName(hud.abilities.slot(0).info.get("id")), &"ice_shards", "slot info polled")
	expect_near(float(hud.abilities.slot(0).info.get("cooldown_ratio")), 0.5, 0.001, "cooldown shown")
	expect(not bool(hud.abilities.slot(1).info.get("available")), "unavailable shown")
	Events.ability_failed.emit(&"water_surge", &"no_chi")
	expect(hud.abilities.slot(1)._flash > 0.9, "failure flash on the right slot")
	mock.set_cooldown(0, 0.0, 0.0)
	await frames(2)
	expect(hud.abilities.slot(0)._glint > 0.0, "ready glint when the cooldown ends")


func test_hud_events_notify_prompt_lock_quest() -> void:
	var hm := _hud()
	var hud: Hud = hm[0]
	var mock: HudMockPlayer = hm[1]
	await frames(1)
	Events.notify.emit("Hello", &"info")
	Events.notify.emit("Quest!", &"quest")
	expect_eq(hud.toasts.count(), 2, "two toasts")
	for i in 5:
		Events.notify.emit("spam %d" % i, &"warning")
	expect(hud.toasts.count() <= hud.toasts.max_visible, "toast stack capped")
	Events.interaction_prompt.emit("Talk", true)
	expect(hud.prompt_panel.visible, "prompt shown")
	expect_eq(hud._prompt_label.text, "Talk")
	Events.interaction_prompt.emit("", false)
	expect(not hud.prompt_panel.visible, "prompt hidden")
	var target := HudMockPlayer.make_target("Fire Nation Soldier", 100.0)
	_add(target)
	mock.lock_target = target
	await frames(2)
	expect_eq(hud.lock_on.target, target, "lock-on target polled from the player")
	expect_eq(hud.lock_on._name.text, "FIRE NATION SOLDIER", "target name")
	(target.get_node("HealthComponent") as HealthComponent).apply_damage(50.0)
	await frames(2)
	expect_near(hud.lock_on._bar.ratio, 0.5, 0.01, "target health bar")
	mock.lock_target = null
	await frames(2)
	expect(hud.lock_on.target == null, "lock released")
	var provider := _QuestStub.new()
	GameState.tracked_quest = &"q1"
	hud.bind_quest_provider(provider)
	expect(hud.quest.visible, "quest tracker visible")
	expect_eq(hud.quest.objective_count(), 2, "objectives listed")
	Events.quest_completed.emit(&"q1")
	expect(not hud.quest.visible, "tracker cleared on completion")


func test_hud_damage_numbers_respect_setting() -> void:
	var hm := _hud()
	var hud: Hud = hm[0]
	await frames(1)
	var cam := Camera3D.new()
	_add(cam)
	cam.make_current()
	await frames(1)
	Settings.set_value("gameplay", "damage_numbers", false)
	expect(hud.damage_numbers.spawn(Vector3(0, 1, -5), 20.0) == null, "off -> no number")
	Settings.set_value("gameplay", "damage_numbers", true)
	expect(hud.damage_numbers.spawn(Vector3(0, 1, -5), 20.0) != null, "on -> number")
	expect(hud.damage_numbers.spawn(Vector3(0, 1, 5), 20.0) == null, "behind the camera -> none")


func test_hud_region_title_and_compass() -> void:
	var hm := _hud()
	var hud: Hud = hm[0]
	await frames(1)
	Events.region_entered.emit(&"fire_nation")
	expect_eq(hud.compass.region_text, "The Fire Nation", "compass region")
	expect(hud.title_card.showing, "title card on region discovery")
	expect_eq(hud.title_card.current_title, "The Fire Nation")
	hud.compass.heading = 90.0
	expect_near(hud.compass.x_for_bearing(90.0), hud.compass.size.x * 0.5, 0.5, "bearing ahead is centred")
	expect(is_nan(hud.compass.x_for_bearing(270.0)), "bearing behind is off the strip")
	expect_near(HudCompass.bearing(Vector3.ZERO, Vector3(0, 0, -10)), 0.0, 0.01, "north is -Z")
	expect_near(HudCompass.bearing(Vector3.ZERO, Vector3(10, 0, 0)), 90.0, 0.01, "east is +X")


class _QuestStub:
	extends RefCounted

	func get_quest_display(quest_id: StringName) -> Dictionary:
		return {"id": quest_id, "title": "Moon and Ocean", "objectives": [{"text": "A", "done": true}, {"text": "B", "count": 1, "target": 3}]}


# --- Title card, dialogue, loading ------------------------------------------------------------------

func test_title_card_queue_and_skip() -> void:
	var t := TitleCard.new()
	_add(t)
	await frames(1)
	var done := [0]
	t.finished.connect(func() -> void: done[0] += 1)
	t.show_title("The Northern Water Tribe", "Arrival", ElementDefs.Element.WATER)
	t.show_title("Spirit Oasis", "Discovered")
	expect(t.showing and t.current_title == "The Northern Water Tribe", "first title shows")
	t.skip()
	expect_eq(done[0], 1, "skip finishes")
	expect_eq(t.current_title, "Spirit Oasis", "queued title follows")
	t.skip()
	expect(not t.showing, "queue drained")
	expect_eq(TitleCard.region_title(&"air_temple"), "The Southern Air Temple")


func test_dialogue_say_and_ask() -> void:
	var d := _scene("res://scenes/ui/dialogue_box.tscn") as DialogueBox
	await frames(1)
	var log: Array = []
	var flow := func() -> void:
		await d.say("Pakku", "Again.")
		log.append("said")
		var i: int = await d.ask("Katara", "Will you help?", ["Yes", "Tell me more", "No"])
		log.append(i)
	flow.call()
	await frames(1)
	expect(d.is_open, "opens on say")
	d.advance()   # finish reveal
	d.advance()   # next line
	await frames(1)
	expect_eq(log, ["said"], "say resolved after advancing")
	d.advance()   # finish reveal of the question -> choices
	await frames(1)
	expect_eq(d.choices.size(), 3, "choices built")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_3
	k.pressed = true
	d._unhandled_input(k)
	await frames(1)
	expect_eq(log, ["said", 2], "number key picks a choice")
	d.close()
	expect(not d.is_open, "closed")


func test_loading_overlay() -> void:
	var lo := LoadingOverlay.open(get_tree(), "Entering the world", ElementDefs.Element.EARTH)
	_nodes.append(lo)
	await frames(1)
	expect(lo.layer > 120, "above the Router fade")
	expect(not lo.current_tip().is_empty(), "a tip is shown")
	lo.set_progress(0.5)
	expect_near(lo.progress, 0.5, 0.001)
	lo.close()
	await seconds(0.45)
	expect(not is_instance_valid(lo) or lo.is_queued_for_deletion(), "closes")


# --- Widgets ----------------------------------------------------------------------------------------

func test_choice_widget_skips_disabled_and_wraps() -> void:
	var c := UiChoice.new()
	_add(c)
	c.set_items([{"value": "a", "label": "A"}, {"value": "b", "label": "B", "disabled": true}, {"value": "c", "label": "C"}])
	c.select_value("a")
	var got: Array = []
	c.value_changed.connect(func(v: Variant) -> void: got.append(v))
	c.step(1)
	expect_eq(c.get_value(), "c", "skips disabled")
	c.step(1)
	expect_eq(c.get_value(), "a", "wraps")
	expect_eq(got, ["c", "a"])


func test_menu_option_highlight_follows_focus() -> void:
	var b := MenuOptionButton.new("01", "TEST")
	_add(b)
	await frames(1)
	b.grab_focus()
	expect(b.is_hot(), "focus lights the option")
	b.release_focus()
	expect(not b.is_hot(), "blur clears it")
	expect(UiFx.history.has(UiFx.HOVER), "hover tick requested")
