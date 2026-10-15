class_name ElementSelect
extends Node
## "BEGIN YOUR JOURNEY AS..." (scenes/ui/element_select.tscn).
## Four cards — EARTHBENDER, AIRBENDER, FIREBENDER, WATERBENDER — each with a live 3D
## preview and the element's data. The full-screen backdrop changes landscape, palette and
## particles with the focused card, and the show-intro motif (black bender silhouette and
## the brush glyph pair on a cinnabar swash) follows it.
## Choosing a card focuses BEGIN; confirming plays an ink wipe, then
##   normal:   GameState.new_game(e)       -> Router.goto(Router.WORLD, {"new_game": true, "element": e})
##   tutorial: GameState.new_game(e, true) -> Router.goto(Router.TUTORIAL, {"element": e})
## (Router.params.tutorial == true selects tutorial mode). Back returns to the main menu.

const ORDER := [ElementDefs.Element.EARTH, ElementDefs.Element.AIR, ElementDefs.Element.FIRE, ElementDefs.Element.WATER]
const GLYPH_SHADER := preload("res://src/ui/shaders/dry_brush_text.gdshader")

## Called as route_override.call(path, params) instead of Router.goto (tests).
var route_override: Callable
## Skip the ink wipe (tests).
var instant := false
var tutorial := false
var current := ElementDefs.Element.EARTH
var cards: Array[ElementCard] = []
var backdrops: Dictionary = {}       # element -> ElementBackdrop
var motifs: Dictionary = {}          # element -> ElementPreview (silhouette)
var begin_button: Button
var back_button: Button
var transition: InkTransition
var hint_bar: InputHintBar

var _ui: Control
var _layer: CanvasLayer
var _glyph_l: Label
var _glyph_r: Label
var _swash: BrushStroke
var _busy := false


func _ready() -> void:
	UiInput.ensure(get_tree())
	tutorial = bool(Router.params.get("tutorial", false))
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -5
	bg_layer.name = "Backdrop"
	add_child(bg_layer)
	var bg_root := Control.new()
	bg_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(bg_root)
	for e: int in ORDER:
		var b := ElementBackdrop.new()
		b.name = "Backdrop_%s" % ElementDefs.id_of(e)
		bg_root.add_child(b)
		b.setup(e)
		b.visible = false
		backdrops[e] = b
	_layer = CanvasLayer.new()
	_layer.name = "UI"
	_layer.layer = 5
	add_child(_layer)
	_ui = Control.new()
	_ui.name = "Root"
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UiTheme.get_theme()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_ui)
	_build_washes()
	_build_motif()
	_build_title()
	_build_cards()
	_build_footer()
	transition = InkTransition.new()
	_ui.add_child(transition)
	Audio.play_music(&"music_select")
	_show_element(ORDER[0], false)
	UiFx.focus_silently.call_deferred(cards[0])


# --- Build ----------------------------------------------------------------------------------

func _build_washes() -> void:
	# ink gradients behind the title and the footer keep text legible on every backdrop
	for top: bool in [true, false]:
		var band := TextureRect.new()
		var g := Gradient.new()
		g.set_color(0, Color(UiTheme.INK, 0.78 if top else 0.9))
		g.set_color(1, Color(UiTheme.INK, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0) if top else Vector2(0, 1)
		gt.fill_to = Vector2(0, 1) if top else Vector2(0, 0)
		gt.width = 4
		gt.height = 64
		band.texture = gt
		band.stretch_mode = TextureRect.STRETCH_SCALE
		band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		band.anchor_right = 1.0
		if top:
			band.offset_bottom = 120
		else:
			band.anchor_top = 1.0
			band.anchor_bottom = 1.0
			band.offset_top = -150
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui.add_child(band)


func _center_box(y: float, h: float) -> Control:
	var c := Control.new()
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.offset_left = -960
	c.offset_right = 960
	c.offset_top = y
	c.offset_bottom = y + h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(c)
	return c


func _build_title() -> void:
	var box := _center_box(26, 80)
	box.name = "Title"
	var t := UiTheme.make_label("BEGIN YOUR JOURNEY AS...", UiTheme.title_font(700, 12), 40, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	t.name = "TitleLabel"
	t.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.6))
	t.add_theme_constant_override(&"shadow_offset_y", 3)
	t.add_theme_constant_override(&"shadow_outline_size", 8)
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(t)
	if tutorial:
		var tag := UiTheme.make_label("TRAINING GROUNDS  ·  choose a discipline to practise — nothing is saved", UiTheme.title_font(600, 3),
				UiTheme.SIZE_SMALL, UiTheme.GOLD_HI, HORIZONTAL_ALIGNMENT_CENTER)
		tag.name = "TutorialTag"
		tag.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.7))
		tag.add_theme_constant_override(&"shadow_outline_size", 6)
		tag.position = Vector2(0, 54)
		tag.size = Vector2(1920, 30)
		box.add_child(tag)


func _build_motif() -> void:
	var box := _center_box(88, 292)
	box.name = "Motif"
	_swash = BrushStroke.new(Color(0.66, 0.11, 0.08, 0.93), 2.2)
	_swash.set_param(&"thickness", 0.92).set_param(&"tail", 0.35).set_param(&"head", 0.06).set_param(&"dryness", 0.55).set_param(&"wobble", 0.06)
	_swash.position = Vector2(570, 16)
	_swash.size = Vector2(780, 262)
	box.add_child(_swash)
	for e: int in ORDER:
		var m := ElementPreview.new()
		m.name = "Silhouette_%s" % ElementDefs.id_of(e)
		m.position = Vector2(805, -8)
		m.size = Vector2(310, 300)
		box.add_child(m)
		m.setup(e, true)
		m.max_scale = 1.25
		m.visible = false
		motifs[e] = m
	_glyph_l = _glyph_label()
	_glyph_l.position = Vector2(590, 6)
	box.add_child(_glyph_l)
	_glyph_r = _glyph_label()
	_glyph_r.position = Vector2(1110, 6)
	box.add_child(_glyph_r)


func _glyph_label() -> Label:
	var l := UiTheme.make_label("", UiTheme.brush_font(), 200, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	l.size = Vector2(220, 270)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var m := ShaderMaterial.new()
	m.shader = GLYPH_SHADER
	m.set_shader_parameter(&"glyph_height", 220.0)
	m.set_shader_parameter(&"seed", randf() * 10.0)
	l.material = m
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_cards() -> void:
	var box := _center_box(392, ElementCard.SIZE.y)
	box.name = "Cards"
	var row := HBoxContainer.new()
	row.name = "Row"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 22)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	for e: int in ORDER:
		var c := ElementCard.new(e)
		c.name = "Card_%s" % ElementDefs.id_of(e)
		row.add_child(c)
		cards.append(c)
		c.focus_entered.connect(_on_card_focused.bind(c))
		c.pressed.connect(_on_card_pressed.bind(c))


func _build_footer() -> void:
	var foot := HBoxContainer.new()
	foot.name = "Footer"
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.anchor_right = 1.0
	foot.offset_left = 110
	foot.offset_right = -110
	foot.offset_top = -86
	foot.offset_bottom = -16
	foot.add_theme_constant_override(&"separation", 24)
	_ui.add_child(foot)
	back_button = Button.new()
	back_button.text = "BACK"
	back_button.theme_type_variation = &"GhostButton"
	back_button.custom_minimum_size = Vector2(180, 64)
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.pressed.connect(go_back)
	UiFx.wire(back_button, {"press_sound": UiFx.BACK})
	foot.add_child(back_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(spacer)
	begin_button = Button.new()
	begin_button.name = "Begin"
	begin_button.theme_type_variation = &"PrimaryButton"
	begin_button.custom_minimum_size = Vector2(560, 66)
	begin_button.add_theme_font_override(&"font", UiTheme.title_font(700, 6))
	begin_button.add_theme_font_size_override(&"font_size", 26)
	UiFx.wire(begin_button, {"press_sound": UiFx.CONFIRM})
	begin_button.pressed.connect(func() -> void: confirm(current))
	foot.add_child(begin_button)
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(spacer2)
	hint_bar = InputHintBar.new()
	hint_bar.glyph_height = 32
	foot.add_child(hint_bar)
	hint_bar.set_hints([
		{"kbm": [{"type": "key", "code": KEY_LEFT}, {"type": "key", "code": KEY_RIGHT}],
			"pad": [{"type": "joy_button", "button": JOY_BUTTON_DPAD_LEFT}, {"type": "joy_button", "button": JOY_BUTTON_DPAD_RIGHT}], "text": "Choose"},
		{"action": &"ui_accept", "text": "Select"}, {"action": &"ui_cancel", "text": "Back"},
	])
	# focus graph: cards <-> begin
	for i in cards.size():
		var c := cards[i]
		c.focus_neighbor_left = c.get_path_to(cards[(i - 1 + cards.size()) % cards.size()])
		c.focus_neighbor_right = c.get_path_to(cards[(i + 1) % cards.size()])
		c.focus_neighbor_bottom = c.get_path_to(begin_button)
		c.focus_neighbor_top = c.get_path()
	begin_button.focus_neighbor_left = begin_button.get_path()
	begin_button.focus_neighbor_right = begin_button.get_path()
	begin_button.focus_neighbor_bottom = begin_button.get_path()


# --- Behaviour --------------------------------------------------------------------------------

func _on_card_focused(card: ElementCard) -> void:
	_show_element(card.element)
	begin_button.focus_neighbor_top = begin_button.get_path_to(card)
	for c in cards:
		c.set_dimmed(c != card)


func _on_card_pressed(card: ElementCard) -> void:
	for c in cards:
		c.chosen = c == card
	_show_element(card.element)
	UiFx.focus_silently(begin_button)
	UiFx.pop(begin_button, 1.05)


## Switches the backdrop, motif and BEGIN label to `e`.
func _show_element(e: int, animate: bool = true) -> void:
	var prev := current
	current = e
	var d := ElementDefs.get_data(e)
	begin_button.text = ("PRACTISE AS %s" if tutorial else "BEGIN AS %s") % String(d.get("name", "")).to_upper()
	for k: int in backdrops:
		var b: ElementBackdrop = backdrops[k]
		if k == e:
			b.visible = true
			if animate and prev != e:
				b.modulate.a = 0.0
				b.get_parent().move_child(b, -1)
				create_tween().tween_property(b, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE)
			else:
				b.modulate.a = 1.0
		elif not animate or prev != k:
			b.visible = false
	if animate and prev != e and backdrops.has(prev):
		var old: ElementBackdrop = backdrops[prev]
		var t := create_tween()
		t.tween_interval(0.46)
		t.tween_callback(func() -> void:
			if current != prev:
				old.visible = false)
	for k: int in motifs:
		var m: ElementPreview = motifs[k]
		m.visible = k == e
		m.active = k == e
	_glyph_l.text = String(d.get("glyph", ""))
	_glyph_r.text = String(d.get("virtue", ""))
	if animate and prev != e:
		for g: Label in [_glyph_l, _glyph_r]:
			var gm := g.material as ShaderMaterial
			var tw := create_tween()
			tw.tween_method(func(v: float) -> void: gm.set_shader_parameter(&"reveal", v), 0.0, 1.0, 0.5).set_trans(Tween.TRANS_SINE)
		_swash.sweep(0.4, 0.15, 1.0)


## Commits the choice: wipe, new game, route to the world (or the tutorial).
func confirm(e: int) -> void:
	if _busy or not ElementDefs.is_valid(e):
		return
	_busy = true
	Events.element_selected.emit(e)
	UiFx.sound(UiFx.SELECT_ELEMENT)
	if not instant:
		await transition.play(e)
	if tutorial:
		GameState.new_game(e, true)
		route(Router.TUTORIAL, {"element": e})
	else:
		GameState.new_game(e)
		route(Router.WORLD, {"new_game": true, "element": e})


func go_back() -> void:
	if _busy:
		return
	_busy = true
	route(Router.MAIN_MENU, {})


func route(path: String, params: Dictionary) -> void:
	if route_override.is_valid():
		route_override.call(path, params)
		_busy = false
		return
	Router.goto(path, params, 0.35)


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		UiFx.sound(UiFx.BACK)
		if begin_button.has_focus():
			var idx := ORDER.find(current)
			UiFx.focus_silently(cards[maxi(idx, 0)])
		else:
			go_back()


## Card for an element (tests).
func card_for(e: int) -> ElementCard:
	for c in cards:
		if c.element == e:
			return c
	return null
