class_name SettingsMenu
extends UiOverlay
## Settings overlay (scenes/ui/settings_menu.tscn), shared by the main menu and the pause
## menu. Tabs Display / Graphics / Audio / Controls / Gameplay expose every option in
## Settings; edits apply live (so the player sees and hears them), APPLY saves, CANCEL
## restores the snapshot taken when the menu opened, RESTORE DEFAULTS resets the tab.
## Q/E or LB/RB switch tabs. Unsupported options are disabled with an explanation.

signal applied

const TAB_ICONS := {"display": "icon_focus", "graphics": "icon_discovery", "audio": "icon_chi", "controls": "icon_lock", "gameplay": "icon_quest"}

var tab := 0
## Write user://settings.cfg on APPLY (tests turn this off).
var persist := true
## "section.key" -> SettingRow
var rows: Dictionary = {}
var tab_pages: Array[ScrollContainer] = []
var tab_buttons: Array[Button] = []
var key_binds: KeyBindList
var rebind_prompt: RebindPrompt
var confirm: ConfirmDialog
var apply_button: Button
var cancel_button: Button
var defaults_button: Button

var _snapshot: Dictionary = {}
var _help_title: Label
var _help_text: Label
var _help_warn: Label
var _tab_stroke: BrushStroke
var _tab_row: HBoxContainer
var _last_preview := 0


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 150)
	margin.add_theme_constant_override(&"margin_top", 70)
	margin.add_theme_constant_override(&"margin_bottom", 64)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InkPanel"
	margin.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 14)
	panel.add_child(root)
	root.add_child(_build_header())
	var sep := HSeparator.new()
	root.add_child(sep)
	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 40)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var pages := Control.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(pages)
	for t: String in SettingsSchema.TABS:
		var page := _build_page(t)
		pages.add_child(page)
		tab_pages.append(page)
	body.add_child(_build_help())
	root.add_child(HSeparator.new())
	root.add_child(_build_footer())
	rebind_prompt = RebindPrompt.new()
	add_child(rebind_prompt)
	rebind_prompt.finished.connect(_on_rebind_finished)
	confirm = ConfirmDialog.new()
	add_child(confirm)
	_select_tab(0, false)


func _build_header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 18)
	var title := UiTheme.make_label("SETTINGS", UiTheme.title_font(700, 10), UiTheme.SIZE_H2, UiTheme.GOLD)
	h.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	h.add_child(PromptGlyph.for_entries([{"type": "key", "code": KEY_Q}], [{"type": "joy_button", "button": JOY_BUTTON_LEFT_SHOULDER}], 34))
	var tabs_holder := Control.new()
	tabs_holder.custom_minimum_size = Vector2(980, 64)
	h.add_child(tabs_holder)
	_tab_stroke = BrushStroke.new(Color(UiTheme.SEAL, 0.9), 5.0)
	_tab_stroke.set_param(&"thickness", 0.7).set_param(&"tail", 0.3)
	tabs_holder.add_child(_tab_stroke)
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override(&"separation", 6)
	_tab_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs_holder.add_child(_tab_row)
	for i in SettingsSchema.TABS.size():
		var t: String = SettingsSchema.TABS[i]
		var b := Button.new()
		b.text = SettingsSchema.TAB_TITLES[t]
		b.theme_type_variation = &"GhostButton"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(186, 60)
		b.add_theme_font_override(&"font", UiTheme.title_font(700, 4))
		b.add_theme_font_size_override(&"font_size", UiTheme.SIZE_SMALL + 1)
		b.pressed.connect(func() -> void: _select_tab(i))
		b.mouse_entered.connect(func() -> void:
			if i != tab:
				UiFx.sound(UiFx.HOVER))
		_tab_row.add_child(b)
		tab_buttons.append(b)
	h.add_child(PromptGlyph.for_entries([{"type": "key", "code": KEY_E}], [{"type": "joy_button", "button": JOY_BUTTON_RIGHT_SHOULDER}], 34))
	return h


func _build_page(t: String) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.name = "Page_" + t
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	for spec: Dictionary in SettingsSchema.rows(t):
		match String(spec["kind"]):
			"header":
				var m := MarginContainer.new()
				m.add_theme_constant_override(&"margin_top", 26)
				m.add_theme_constant_override(&"margin_left", 20)
				m.add_theme_constant_override(&"margin_bottom", 6)
				m.add_child(UiTheme.make_label(String(spec["label"]), UiTheme.title_font(600, 8), UiTheme.SIZE_SMALL, UiTheme.GOLD))
				v.add_child(m)
			"bindings":
				var mk := MarginContainer.new()
				mk.add_theme_constant_override(&"margin_left", 20)
				mk.add_theme_constant_override(&"margin_right", 20)
				key_binds = KeyBindList.new()
				mk.add_child(key_binds)
				v.add_child(mk)
				key_binds.rebind_requested.connect(_on_rebind_requested)
				key_binds.reset_requested.connect(_on_reset_bindings)
				key_binds.cell_focused.connect(func(text: String) -> void: _show_help("Key Bindings", text, ""))
				if not Settings.is_feature_supported("rebinding"):
					key_binds.ready.connect(func() -> void: key_binds.set_disabled(true, SettingRow.unsupported_text("rebinding")))
			_:
				var row := SettingRow.new(spec)
				v.add_child(row)
				rows["%s.%s" % [spec["section"], spec["key"]]] = row
				row.edited.connect(_on_row_edited)
				row.row_focused.connect(func(r: SettingRow) -> void:
					_show_help(String(r.spec.get("label", "")), String(r.spec.get("help", "")), r.unsupported_reason))
	return sc


func _build_help() -> Control:
	var p := PanelContainer.new()
	var sb := UiFrameStyle.make(Color(UiTheme.INK, 0.6), Color(UiTheme.GOLD, 0.18), 1.0)
	sb.set_content_margin_all(26)
	p.add_theme_stylebox_override(&"panel", sb)
	p.custom_minimum_size = Vector2(430, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 14)
	p.add_child(v)
	_help_title = UiTheme.make_label("", UiTheme.title_font(700, 3), UiTheme.SIZE_H3 - 4, UiTheme.GOLD_HI)
	_help_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_help_title)
	_help_text = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_BODY - 2, UiTheme.PARCHMENT_DIM)
	_help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_help_text)
	_help_warn = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_SMALL, UiTheme.DANGER)
	_help_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_help_warn)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	var info := UiTheme.make_label("Renderer: %s" % _renderer_name(), UiTheme.body_font(1), UiTheme.SIZE_TINY, UiTheme.PARCHMENT_MUTED)
	v.add_child(info)
	return p


func _build_footer() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 16)
	defaults_button = _footer_button("RESTORE DEFAULTS", &"GhostButton")
	defaults_button.pressed.connect(restore_defaults)
	h.add_child(defaults_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	var hints := InputHintBar.new()
	hints.glyph_height = 30
	h.add_child(hints)
	hints.set_hints([{"action": &"ui_cancel", "text": "Back"}])
	cancel_button = _footer_button("CANCEL", &"")
	cancel_button.pressed.connect(cancel)
	h.add_child(cancel_button)
	apply_button = _footer_button("APPLY", &"PrimaryButton")
	apply_button.pressed.connect(apply_and_close)
	h.add_child(apply_button)
	return h


func _footer_button(text: String, variation: StringName) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(230, UiTheme.touch_height(66))
	if variation != &"":
		b.theme_type_variation = variation
	UiFx.wire(b, {"press_sound": UiFx.CONFIRM if text == "APPLY" else UiFx.CLICK})
	var help := {"APPLY": ["Apply", "Save these settings and close."], "CANCEL": ["Cancel", "Discard changes made since opening and close."]}
	var entry: Array = help.get(text, ["Restore Defaults", "Reset the options on this tab to their defaults."])
	b.focus_entered.connect(func() -> void: _show_help(entry[0], entry[1], ""))
	return b


# --- Open / close -------------------------------------------------------------------------------

func open() -> void:
	_snapshot = Settings.snapshot()
	refresh_all()
	super()


func _initial_focus() -> Control:
	return _first_focusable(tab)


func _on_back() -> void:
	if not is_dirty():
		cancel()
		return
	confirm.ask("UNSAVED CHANGES", "Keep the changes you made?", [[&"apply", "APPLY"], [&"discard", "DISCARD"], [&"cancel", "KEEP EDITING"]])
	var id: StringName = await confirm.answered
	match id:
		&"apply": apply_and_close()
		&"discard": cancel()


## True when settings differ from the snapshot taken on open.
func is_dirty() -> bool:
	return str(Settings.snapshot()) != str(_snapshot)


## Saves and closes.
func apply_and_close() -> void:
	Settings.apply()
	if persist:
		Settings.save()
	_snapshot = Settings.snapshot()
	applied.emit()
	close()


## Restores the snapshot taken on open and closes.
func cancel() -> void:
	if is_dirty():
		Settings.restore_snapshot(_snapshot)
		Settings.apply()
	close()


## Resets every option of the current tab to its default (live; still cancellable).
func restore_defaults() -> void:
	var t: String = SettingsSchema.TABS[tab]
	for section: String in SettingsSchema.TAB_SECTIONS[t]:
		Settings.restore_defaults(section)
	Settings.apply()
	refresh_all()
	UiFx.sound(UiFx.CONFIRM)


func refresh_all() -> void:
	for r: SettingRow in rows.values():
		if r.is_inside_tree():
			r.refresh()
	if key_binds and key_binds.is_inside_tree():
		key_binds.refresh()


# --- Tabs -----------------------------------------------------------------------------------------

func _select_tab(i: int, sound: bool = true) -> void:
	tab = posmod(i, SettingsSchema.TABS.size())
	for k in tab_pages.size():
		tab_pages[k].visible = k == tab
	for k in tab_buttons.size():
		tab_buttons[k].add_theme_color_override(&"font_color", Color("fff6e2") if k == tab else UiTheme.PARCHMENT_MUTED)
		tab_buttons[k].add_theme_color_override(&"font_hover_color", Color("fff6e2") if k == tab else UiTheme.PARCHMENT)
	if sound:
		UiFx.sound(UiFx.CLICK)
	_place_tab_stroke.call_deferred()
	var t: String = SettingsSchema.TABS[tab]
	_show_help(SettingsSchema.TAB_TITLES[t].capitalize(), "", "")
	if is_open:
		var f := _first_focusable(tab)
		if f:
			UiFx.focus_silently(f)


func _place_tab_stroke() -> void:
	if tab >= tab_buttons.size():
		return
	var b := tab_buttons[tab]
	_tab_stroke.position = _tab_row.position + b.position + Vector2(-4, 8)
	_tab_stroke.size = Vector2(b.size.x + 8, b.size.y - 16)
	_tab_stroke.sweep(0.25)


func _first_focusable(t: int) -> Control:
	if t >= tab_pages.size():
		return null
	for r: SettingRow in rows.values():
		if r.get_parent() and r.get_parent().get_parent() == tab_pages[t] and r.focus_target.focus_mode != Control.FOCUS_NONE:
			return r.focus_target
	if SettingsSchema.TABS[t] == "controls" and key_binds:
		return key_binds.reset_button
	return apply_button


func _unhandled_input(event: InputEvent) -> void:
	if not is_open or rebind_prompt.is_open or confirm.is_open:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).physical_keycode:
			KEY_Q:
				_select_tab(tab - 1)
				get_viewport().set_input_as_handled()
				return
			KEY_E:
				_select_tab(tab + 1)
				get_viewport().set_input_as_handled()
				return
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_LEFT_SHOULDER:
				_select_tab(tab - 1)
				get_viewport().set_input_as_handled()
				return
			JOY_BUTTON_RIGHT_SHOULDER:
				_select_tab(tab + 1)
				get_viewport().set_input_as_handled()
				return
	super(event)


## Selects a tab by id ("display", "graphics", ...).
func show_tab(id: String) -> void:
	_select_tab(SettingsSchema.TABS.find(id), false)


# --- Editing ----------------------------------------------------------------------------------

func _on_row_edited(row: SettingRow, value: Variant) -> void:
	var spec := row.spec
	var section := String(spec.get("section", ""))
	var key := String(spec.get("key", ""))
	set_option(section, key, value, String(spec.get("apply", "")))


## Changes one option and applies it live (used by the rows and by tests).
func set_option(section: String, key: String, value: Variant, apply_group: String = "") -> void:
	if apply_group == "preset":
		Settings.apply_preset(String(value))
		Settings.apply_graphics()
		_refresh_section("graphics")
		return
	Settings.set_value(section, key, value)
	match apply_group:
		"display": Settings.apply_display()
		"graphics": Settings.apply_graphics()
		"audio":
			Settings.apply_audio()
			_preview_audio(key)
		"controls": Settings.apply_controls()
	Events.settings_applied.emit()
	if section == "graphics":
		var pr: SettingRow = rows.get("graphics.preset")
		if pr:
			pr.refresh()


func _refresh_section(section: String) -> void:
	for k: String in rows:
		if k.begins_with(section + "."):
			(rows[k] as SettingRow).refresh()


func _preview_audio(key: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_preview < 140:
		return
	_last_preview = now
	match key:
		"ui", "master": Audio.play_ui(&"ui_click")
		"sfx": Audio.play_2d(&"ui_click", 0.0, &"SFX")
		"voice": Audio.play_2d(&"ui_click", 0.0, &"Voice")


func _show_help(title: String, text: String, warn: String) -> void:
	if _help_title == null:
		return
	_help_title.text = title
	_help_text.text = text
	_help_warn.text = warn
	_help_warn.visible = not warn.is_empty()


# --- Rebinding --------------------------------------------------------------------------------

func _on_rebind_requested(action: StringName, device: String) -> void:
	rebind_prompt.begin(action, device)


func _on_rebind_finished(_applied: bool) -> void:
	key_binds.refresh()


func _on_reset_bindings() -> void:
	confirm.ask("RESET BINDINGS", "Restore every key and button to its default?", [[&"reset", "RESET"], [&"cancel", "CANCEL"]])
	var id: StringName = await confirm.answered
	if id == &"reset":
		RebindLogic.reset_all()
		key_binds.refresh()


static func _renderer_name() -> String:
	match Settings.rendering_method():
		"forward_plus": return "Forward+"
		"mobile": return "Mobile"
		"gl_compatibility": return "Compatibility (OpenGL)"
	return Settings.rendering_method()
