class_name PauseMenu
extends CanvasLayer
## In-game pause menu (scenes/ui/pause_menu.tscn) — add one instance to the world or
## tutorial scene. Esc / controller Start toggles it. Opening pauses the tree, shows the
## mouse and blurs the game; resuming restores the previous mouse mode.
##   RESUME · SAVE GAME (SaveSystem.save_game; disabled in the tutorial) · SETTINGS (overlay)
##   RETURN TO MAIN MENU (saves first unless tutorial) · QUIT TO DESKTOP (saves first)
## Leaving goes through route_override / quit_override when set (tests).

signal pause_toggled(paused: bool)

const SETTINGS_SCENE := "res://scenes/ui/settings_menu.tscn"
const LABELS := ["RESUME", "SAVE GAME", "SETTINGS", "RETURN TO MAIN MENU", "QUIT TO DESKTOP"]

var route_override: Callable
var quit_override: Callable
## When set, called instead of SaveSystem.save_game() and must return bool (tests).
var save_override: Callable
var is_open := false
var options: Array[MenuOptionButton] = []
var settings_menu: SettingsMenu
var root: Control

var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _status: Label
var _info_title: Label
var _info_body: Label
var _emblem: TextureRect
var _fade: Tween
var _leaving := false


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiInput.ensure(get_tree())
	root = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	add_child(root)
	UiTheme.apply_safe_area(root)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bm := ShaderMaterial.new()
	bm.shader = UiOverlay.BLUR_SHADER
	bm.set_shader_parameter(&"dim", 0.5)
	bg.material = bm
	root.add_child(bg)
	_build_column()
	_build_info()
	var hints := InputHintBar.new()
	hints.anchor_left = 1.0
	hints.anchor_right = 1.0
	hints.anchor_top = 1.0
	hints.anchor_bottom = 1.0
	hints.offset_left = -760
	hints.offset_right = -110
	hints.offset_top = -92
	hints.offset_bottom = -40
	hints.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(hints)
	hints.set_hints(InputHintBar.navigate_select_back(true))


func _build_column() -> void:
	var stroke := BrushStroke.new(Color(UiTheme.INK, 0.86), 6.6)
	stroke.set_param(&"thickness", 0.98).set_param(&"tail", 0.25).set_param(&"dryness", 0.45).set_param(&"wobble", 0.04)
	stroke.rotation = deg_to_rad(90)
	stroke.position = Vector2(820, -30)
	stroke.size = Vector2(1140, 780)
	root.add_child(stroke)
	var title := UiTheme.make_label("PAUSED", UiTheme.title_font(700, 18), UiTheme.SIZE_H1, UiTheme.GOLD)
	title.position = Vector2(120, 110)
	root.add_child(title)
	var rule := BrushStroke.new(Color(UiTheme.SEAL, 0.9), 1.3)
	rule.set_param(&"thickness", 0.5).set_param(&"tail", 0.5)
	rule.position = Vector2(112, 196)
	rule.size = Vector2(420, 22)
	root.add_child(rule)
	var col := VBoxContainer.new()
	col.position = Vector2(84, 270)
	col.add_theme_constant_override(&"separation", 4)
	root.add_child(col)
	for i in LABELS.size():
		var b := MenuOptionButton.new("%02d" % (i + 1), LABELS[i], UiTheme.SEAL)
		b.name = "Pause%d" % (i + 1)
		b.custom_minimum_size = Vector2(700, 84)
		col.add_child(b)
		options.append(b)
	options[0].pressed.connect(resume)
	options[1].pressed.connect(save_game)
	options[2].pressed.connect(open_settings)
	options[3].pressed.connect(return_to_menu)
	options[4].pressed.connect(quit_to_desktop)
	# No QUIT in browsers / on iOS (src/platform): quitting cannot work there.
	if not PlatformInfo.can_quit():
		options[4].visible = false
	var nav: Array[MenuOptionButton] = []
	for o in options:
		if o.visible:
			nav.append(o)
	for i in nav.size():
		var b := nav[i]
		b.focus_neighbor_top = b.get_path_to(nav[(i - 1 + nav.size()) % nav.size()])
		b.focus_neighbor_bottom = b.get_path_to(nav[(i + 1) % nav.size()])
	_status = UiTheme.make_label("", UiTheme.body_font(1), UiTheme.SIZE_SMALL, UiTheme.SUCCESS)
	_status.position = Vector2(126, 720)
	root.add_child(_status)


func _build_info() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InkPanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -780
	panel.offset_right = -110
	panel.offset_top = 270
	panel.offset_bottom = 560
	root.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 26)
	panel.add_child(h)
	_emblem = TextureRect.new()
	_emblem.custom_minimum_size = Vector2(120, 120)
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emblem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_emblem)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	_info_title = UiTheme.make_label("", UiTheme.title_font(700, 3), UiTheme.SIZE_H3 - 6, UiTheme.PARCHMENT)
	_info_body = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_DIM)
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_info_title)
	v.add_child(_info_body)
	_build_journey_row()


# --- Journey Book hook (progression_ui): shown only when the scene has a JourneyBook --------------

const JOURNEY_PAGES := [["skills", "SKILLS", "icon_skills"], ["map", "MAP", "icon_map"], ["journal", "JOURNAL", "icon_journal"],
	["inventory", "INVENTORY", "icon_bag"], ["character", "CHARACTER", "icon_character"]]
var journey_buttons: Array[Button] = []
var _journey_row: HBoxContainer


func _build_journey_row() -> void:
	_journey_row = HBoxContainer.new()
	_journey_row.name = "JourneyRow"
	_journey_row.anchor_left = 1.0
	_journey_row.anchor_right = 1.0
	_journey_row.offset_left = -780
	_journey_row.offset_right = -110
	_journey_row.offset_top = 590
	_journey_row.offset_bottom = 590 + UiTheme.touch_height(104)
	_journey_row.add_theme_constant_override(&"separation", 8)
	_journey_row.visible = false
	root.add_child(_journey_row)
	for spec: Array in JOURNEY_PAGES:
		var b := Button.new()
		b.name = "Journey_%s" % spec[0]
		b.text = spec[1]
		b.icon = UiTheme.icon(spec[2])
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.expand_icon = false
		b.add_theme_constant_override(&"icon_max_width", 34)
		b.add_theme_font_size_override(&"font_size", UiTheme.SIZE_TINY - 2)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, UiTheme.touch_height(104))
		UiFx.wire(b, {"press_sound": UiFx.CONFIRM})
		var page := StringName(spec[0])
		b.pressed.connect(func() -> void: open_journey(page))
		_journey_row.add_child(b)
		journey_buttons.append(b)
	# same width as the info panel above, five equal buttons: shrink the label size to fit
	var fs := UiTheme.SIZE_TINY - 2
	var width := _journey_row.offset_right - _journey_row.offset_left
	var sep := 8.0 * (JOURNEY_PAGES.size() - 1)
	while fs > 13:
		var widest := 0.0
		for b in journey_buttons:
			widest = maxf(widest, b.get_combined_minimum_size().x)
		if widest * JOURNEY_PAGES.size() + sep <= width:
			break
		fs -= 1
		for b in journey_buttons:
			b.add_theme_font_size_override(&"font_size", fs)


func _journey_book() -> Node:
	var b := get_tree().get_first_node_in_group(&"journey_book") if is_inside_tree() else null
	return b if b != null and bool(b.get("enabled")) else null


## Leaves the pause menu for a Journey Book page; closing the book comes back here.
func open_journey(page: StringName) -> void:
	var book := _journey_book()
	if book == null or _leaving:
		return
	resume()
	book.call(&"open", page, {"from_pause": true, "pause_menu": self})


func _refresh_info() -> void:
	var e := GameState.element
	_emblem.texture = UiTheme.emblem(e)
	_emblem.modulate = UiTheme.element_light(e)
	var region := GameState.region
	if GameState.has_element():
		_info_title.text = "%s · Level %d" % [ElementDefs.display_name(e), GameState.level]
	else:
		_info_title.text = "Wanderer"
	var lines: PackedStringArray = []
	lines.append(WorldData.get_region_name(region) if region != &"" else "The Wilds")
	lines.append("Time travelled  %s" % SaveChooser.format_play_time(GameState.play_time))
	if GameState.is_tutorial:
		lines.append("Training grounds — progress here is not saved.")
	elif SaveSystem.has_any_save():
		var info := SaveSystem.get_save_info(SaveSystem.latest_slot())
		if not info.is_empty():
			lines.append("Last saved  %s" % String(info.get("saved_at", "")).replace("T", "  "))
	_info_body.text = "\n".join(lines)
	if _journey_row:
		_journey_row.visible = _journey_book() != null
	options[1].disabled = not can_save()
	options[1].modulate.a = 0.4 if options[1].disabled else 1.0
	options[1].tooltip_text = "Progress is not saved in the training grounds." if GameState.is_tutorial else ""


## Saving is offered in a live adventure only (not in the tutorial).
func can_save() -> bool:
	return GameState.has_element() and not GameState.is_tutorial


func _unhandled_input(event: InputEvent) -> void:
	if _leaving:
		return
	if event.is_action_pressed(&"pause") and not event.is_echo():
		get_viewport().set_input_as_handled()
		toggle()
	elif is_open and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		UiFx.sound(UiFx.BACK)
		resume()


func toggle() -> void:
	if is_open:
		resume()
	else:
		open()


func open() -> void:
	if is_open or Router.is_transitioning:
		return
	is_open = true
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_refresh_info()
	_status.text = ""
	root.visible = true
	_kill()
	root.modulate.a = 0.0
	_fade = root.create_tween()
	_fade.tween_property(root, "modulate:a", 1.0, 0.16)
	UiFx.sound(UiFx.OPEN)
	UiFx.focus_silently(options[0])
	Events.pause_changed.emit(true)
	pause_toggled.emit(true)


func resume() -> void:
	if not is_open:
		return
	if settings_menu and settings_menu.is_open:
		settings_menu.cancel()
	is_open = false
	get_tree().paused = false
	Input.mouse_mode = _prev_mouse
	_kill()
	_fade = root.create_tween()
	_fade.tween_property(root, "modulate:a", 0.0, 0.12)
	_fade.tween_callback(func() -> void: root.visible = false)
	UiFx.sound(UiFx.CLOSE)
	Events.pause_changed.emit(false)
	pause_toggled.emit(false)


func _kill() -> void:
	if _fade and _fade.is_valid():
		_fade.kill()


## Saves to the autosave slot. Returns success.
func save_game() -> bool:
	if not can_save():
		UiFx.sound(UiFx.ERROR)
		_show_status("Progress is not saved in the training grounds.", UiTheme.DANGER)
		return false
	var ok := _save()
	_show_status("Journey saved." if ok else "The journey could not be saved.", UiTheme.SUCCESS if ok else UiTheme.DANGER)
	if ok:
		_refresh_info()
	return ok


func _save() -> bool:
	if save_override.is_valid():
		return bool(save_override.call())
	return SaveSystem.save_game()


func _show_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override(&"font_color", color)
	_status.modulate.a = 1.0


func open_settings() -> SettingsMenu:
	if settings_menu == null:
		settings_menu = (load(SETTINGS_SCENE) as PackedScene).instantiate() as SettingsMenu
		root.add_child(settings_menu)
		settings_menu.closed.connect(func() -> void: UiFx.focus_silently(options[2]))
	settings_menu.open()
	return settings_menu


func return_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	if can_save():
		_save()
	get_tree().paused = false
	is_open = false
	Events.pause_changed.emit(false)
	if route_override.is_valid():
		route_override.call(Router.MAIN_MENU, {})
		_leaving = false
		return
	Router.goto_main_menu()


func quit_to_desktop() -> void:
	if _leaving:
		return
	_leaving = true
	if can_save():
		_save()
	if quit_override.is_valid():
		quit_override.call()
		_leaving = false
		return
	get_tree().quit()
