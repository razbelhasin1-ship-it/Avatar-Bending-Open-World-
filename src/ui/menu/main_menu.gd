class_name MainMenu
extends Node
## Main menu (scenes/ui/main_menu.tscn): the living panorama behind an ink-and-gold title
## lockup and exactly four options:
##   01 ENTER THE WORLD -> Continue / New Journey chooser if a save exists, else element select
##   02 TUTORIAL        -> element select in tutorial mode
##   03 SETTINGS        -> settings overlay
##   04 EXIT GAME       -> quit
## Scene changes go through `route()` and quitting through `quit()`, both overridable
## (route_override / quit_override) so tests can verify wiring without leaving the scene.

const SETTINGS_SCENE := "res://scenes/ui/settings_menu.tscn"
const TITLE_SHADER := preload("res://src/ui/shaders/text_gradient.gdshader")
const OPTION_LABELS := ["ENTER THE WORLD", "TUTORIAL", "SETTINGS", "EXIT GAME"]
## Show-intro order of the emblems under the title.
const EMBLEM_ORDER := [ElementDefs.Element.WATER, ElementDefs.Element.EARTH, ElementDefs.Element.FIRE, ElementDefs.Element.AIR]

## When set, called as route_override.call(path, params) instead of Router.goto.
var route_override: Callable
## When set, called instead of get_tree().quit().
var quit_override: Callable

var panorama: MenuPanorama
var ui: Control
var options: Array[MenuOptionButton] = []
var chooser: SaveChooser
var settings_menu: SettingsMenu
var hint_bar: InputHintBar
var title_label: Label

var _layer: CanvasLayer
var _title_block: Control
var _options_box: VBoxContainer
var _busy := false


func _ready() -> void:
	UiInput.ensure(get_tree())
	panorama = MenuPanorama.new()
	panorama.name = "Panorama"
	add_child(panorama)
	_layer = CanvasLayer.new()
	_layer.name = "UI"
	_layer.layer = 5
	add_child(_layer)
	ui = Control.new()
	ui.name = "Root"
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = UiTheme.get_theme()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(ui)
	UiTheme.apply_safe_area(ui)
	_build_washes()
	_build_title()
	_build_options()
	_build_footer()
	chooser = SaveChooser.new()
	chooser.name = "SaveChooser"
	ui.add_child(chooser)
	chooser.continue_requested.connect(_on_continue)
	chooser.new_journey_requested.connect(_on_new_journey)
	chooser.closed.connect(func() -> void: UiFx.focus_silently(options[0]))
	Audio.play_music(&"music_menu")
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_intro()


# --- Build ----------------------------------------------------------------------------------

func _build_washes() -> void:
	# ink wash on the left for legibility, soft letterbox top/bottom
	var left := TextureRect.new()
	left.name = "InkWash"
	var g := Gradient.new()
	g.set_color(0, Color(UiTheme.INK, 0.82))
	g.add_point(0.55, Color(UiTheme.INK, 0.42))
	g.set_color(g.get_point_count() - 1, Color(UiTheme.INK, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	left.texture = gt
	left.stretch_mode = TextureRect.STRETCH_SCALE
	left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	left.anchor_bottom = 1.0
	left.anchor_right = 0.62
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(left)
	for top: bool in [true, false]:
		var band := TextureRect.new()
		var bg := Gradient.new()
		bg.set_color(0, Color(0, 0, 0, 0.55))
		bg.set_color(1, Color(0, 0, 0, 0.0))
		var bt := GradientTexture2D.new()
		bt.gradient = bg
		bt.fill_from = Vector2(0, 0) if top else Vector2(0, 1)
		bt.fill_to = Vector2(0, 1) if top else Vector2(0, 0)
		bt.width = 4
		bt.height = 128
		band.texture = bt
		band.stretch_mode = TextureRect.STRETCH_SCALE
		band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		band.anchor_right = 1.0
		if top:
			band.anchor_bottom = 0.0
			band.offset_bottom = 150
		else:
			band.anchor_top = 1.0
			band.anchor_bottom = 1.0
			band.offset_top = -190
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.add_child(band)


func _build_title() -> void:
	_title_block = VBoxContainer.new()
	_title_block.name = "Title"
	_title_block.position = Vector2(118, 70)
	_title_block.add_theme_constant_override(&"separation", 0)
	_title_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_title_block)
	# drop shadow + gilded title
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(900, 190)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_block.add_child(stack)
	var title_font := UiTheme.title_font(800, 26)
	var shadow := UiTheme.make_label("AVATAR", title_font, UiTheme.SIZE_HERO, Color(0, 0, 0, 0.55))
	shadow.position = Vector2(6, 10)
	shadow.add_theme_constant_override(&"outline_size", 18)
	shadow.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.25))
	stack.add_child(shadow)
	title_label = UiTheme.make_label("AVATAR", title_font, UiTheme.SIZE_HERO, Color.WHITE)
	title_label.name = "TitleText"
	var tm := ShaderMaterial.new()
	tm.shader = TITLE_SHADER
	tm.set_shader_parameter(&"y0", 40.0)
	tm.set_shader_parameter(&"height", 150.0)
	title_label.material = tm
	stack.add_child(title_label)
	# subtitle on a cinnabar brush stroke (the show intro's red)
	var sub_row := Control.new()
	sub_row.custom_minimum_size = Vector2(900, 78)
	sub_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_block.add_child(sub_row)
	var stroke := BrushStroke.new(Color(UiTheme.SEAL, 0.92), 3.3)
	stroke.name = "SubtitleStroke"
	stroke.set_param(&"thickness", 0.78).set_param(&"tail", 0.38).set_param(&"head", 0.05)
	stroke.position = Vector2(-6, 6)
	stroke.size = Vector2(700, 68)
	sub_row.add_child(stroke)
	var sub := UiTheme.make_label("THE FOUR NATIONS", UiTheme.title_font(600, 16), 36, UiTheme.PARCHMENT)
	sub.name = "Subtitle"
	sub.position = Vector2(30, 14)
	sub_row.add_child(sub)
	# four emblems in the show-intro order
	var emblems := HBoxContainer.new()
	emblems.name = "Emblems"
	emblems.add_theme_constant_override(&"separation", 26)
	emblems.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 26)
	_title_block.add_child(pad)
	_title_block.add_child(emblems)
	for i in EMBLEM_ORDER.size():
		var e: int = EMBLEM_ORDER[i]
		var tr := TextureRect.new()
		tr.texture = UiTheme.emblem(e)
		tr.custom_minimum_size = Vector2(58, 58)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.modulate = UiTheme.element_light(e)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.tooltip_text = ElementDefs.get_data(e).get("nation", "")
		emblems.add_child(tr)
		if i < EMBLEM_ORDER.size() - 1:
			var dot := TextureRect.new()
			dot.texture = UiTheme.icon("ui_diamond")
			dot.custom_minimum_size = Vector2(9, 9)
			dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			dot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dot.modulate = Color(UiTheme.GOLD, 0.7)
			dot.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			emblems.add_child(dot)


func _build_options() -> void:
	_options_box = VBoxContainer.new()
	_options_box.name = "Options"
	_options_box.position = Vector2(92, 560)
	_options_box.add_theme_constant_override(&"separation", 8)
	ui.add_child(_options_box)
	var accents := [UiTheme.SEAL, UiTheme.element_color(ElementDefs.Element.EARTH),
			UiTheme.element_color(ElementDefs.Element.WATER), Color("5a4a3c")]
	for i in OPTION_LABELS.size():
		var b := MenuOptionButton.new("%02d" % (i + 1), OPTION_LABELS[i], accents[i])
		b.name = "Option%d" % (i + 1)
		_options_box.add_child(b)
		options.append(b)
	options[0].pressed.connect(_on_enter_world)
	options[1].pressed.connect(_on_tutorial)
	options[2].pressed.connect(_on_settings)
	options[3].pressed.connect(_on_exit)
	for i in options.size():
		var b := options[i]
		b.focus_neighbor_top = b.get_path_to(options[(i - 1 + options.size()) % options.size()])
		b.focus_neighbor_bottom = b.get_path_to(options[(i + 1) % options.size()])
		b.focus_neighbor_left = b.get_path()
		b.focus_neighbor_right = b.get_path()
	_refresh_continue_caption()


func _build_footer() -> void:
	var foot := HBoxContainer.new()
	foot.name = "Footer"
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.anchor_right = 1.0
	foot.offset_left = 120
	foot.offset_right = -110
	foot.offset_top = -92
	foot.offset_bottom = -40
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(foot)
	var ver := UiTheme.make_label("v%s  ·  a fan-made adventure" % ProjectSettings.get_setting("application/config/version", "0.1"),
			UiTheme.body_font(1), UiTheme.SIZE_TINY, Color(UiTheme.PARCHMENT, 0.45))
	ver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ver.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(ver)
	hint_bar = InputHintBar.new()
	foot.add_child(hint_bar)
	hint_bar.set_hints(InputHintBar.navigate_select_back(false))


func _intro() -> void:
	_title_block.modulate.a = 0.0
	var t := create_tween()
	t.tween_interval(0.25)
	t.tween_property(_title_block, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	var stroke := _title_block.find_child("SubtitleStroke", true, false) as BrushStroke
	if stroke:
		stroke.sweep(0.7, 0.0, 1.0, 0.55)
	for i in options.size():
		var b := options[i]
		b.modulate.a = 0.0
		var bt := create_tween()
		bt.tween_interval(0.7 + i * 0.09)
		bt.tween_property(b, "modulate:a", 1.0, 0.35)
	var ft := create_tween()
	ft.tween_interval(1.05)
	ft.tween_callback(func() -> void:
		if not _busy and get_viewport().gui_get_focus_owner() == null:
			UiFx.focus_silently(options[0]))


func _refresh_continue_caption() -> void:
	if SaveSystem.has_any_save():
		var info := SaveSystem.get_save_info(SaveSystem.latest_slot())
		if not info.is_empty():
			options[0].caption = "Continue as %s · Level %d" % [ElementDefs.display_name(int(info["element"])), int(info["level"])]
			return
	options[0].caption = ""


# --- Actions --------------------------------------------------------------------------------

func _on_enter_world() -> void:
	if _busy:
		return
	if SaveSystem.has_any_save():
		chooser.open_for(SaveSystem.latest_slot(), options[0])
	else:
		route(Router.ELEMENT_SELECT, {"tutorial": false})


func _on_tutorial() -> void:
	route(Router.ELEMENT_SELECT, {"tutorial": true})


func _on_settings() -> void:
	open_settings()


func _on_exit() -> void:
	if _busy:
		return
	_busy = true
	var t := create_tween()
	t.tween_property(ui, "modulate:a", 0.0, 0.3)
	t.tween_callback(quit)


func _on_continue(slot: int) -> void:
	if not SaveSystem.load_game(slot):
		chooser.show_error("This journey could not be read.")
		return
	route(Router.WORLD, {"new_game": false})


func _on_new_journey() -> void:
	route(Router.ELEMENT_SELECT, {"tutorial": false})


## Opens the settings overlay (instanced on first use).
func open_settings() -> SettingsMenu:
	if settings_menu == null:
		settings_menu = (load(SETTINGS_SCENE) as PackedScene).instantiate() as SettingsMenu
		ui.add_child(settings_menu)
		settings_menu.closed.connect(func() -> void: UiFx.focus_silently(options[2]))
	settings_menu.open()
	return settings_menu


## Leaves the menu (Router.goto unless overridden).
func route(path: String, params: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	if route_override.is_valid():
		route_override.call(path, params)
		_busy = false
		return
	Router.goto(path, params)


func quit() -> void:
	if quit_override.is_valid():
		quit_override.call()
		_busy = false
		return
	get_tree().quit()
