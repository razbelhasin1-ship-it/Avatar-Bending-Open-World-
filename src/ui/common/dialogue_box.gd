class_name DialogueBox
extends Control
## NPC dialogue presenter (scenes/ui/dialogue_box.tscn): speaker plate on a brush stroke,
## typewriter text reveal, advance prompt, and up to six choices navigable by mouse,
## keyboard (arrows, 1-6) and controller. Presentation only — the NPC/quest modules
## drive it and emit Events.dialogue_started/ended.
##
##   box.open()
##   await box.say("Master Pakku", "Again. Your form is sloppy.", {"element": ElementDefs.Element.WATER})
##   var i: int = await box.ask("Katara", "Will you help us?", ["Of course.", "Not yet."])
##   box.close()

signal line_finished
signal advanced
signal choice_made(index: int)
signal closed

## Characters revealed per second.
var reveal_speed := 48.0
var is_open := false
var choices: Array[Button] = []

var _panel: PanelContainer
var _name_stroke: BrushStroke
var _name: Label
var _text: RichTextLabel
var _next: PromptGlyph
var _choice_box: VBoxContainer
var _revealing := false
var _waiting := false
var _asking := false
var _chars := 0.0
var _t := 0.0
var _pending_choices: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(UiTheme.INK, 0.0))
	g.set_color(1, Color(UiTheme.INK, 0.75))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_top = 1.0
	shade.anchor_bottom = 1.0
	shade.anchor_right = 1.0
	shade.offset_top = -420
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"InkPanel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -660
	_panel.offset_right = 660
	_panel.offset_top = -270
	_panel.offset_bottom = -44
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var m := MarginContainer.new()
	m.add_theme_constant_override(&"margin_top", 22)
	m.add_theme_constant_override(&"margin_left", 18)
	m.add_theme_constant_override(&"margin_right", 18)
	_panel.add_child(m)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = false
	_text.scroll_active = false
	_text.add_theme_font_size_override(&"normal_font_size", UiTheme.SIZE_BODY + 2)
	_text.add_theme_constant_override(&"line_separation", 8)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(_text)
	_name_stroke = BrushStroke.new(UiTheme.SEAL, 8.1)
	_name_stroke.set_param(&"thickness", 0.74).set_param(&"tail", 0.35)
	_name_stroke.anchor_left = 0.5
	_name_stroke.anchor_right = 0.5
	_name_stroke.anchor_top = 1.0
	_name_stroke.anchor_bottom = 1.0
	_name_stroke.offset_left = -690
	_name_stroke.offset_right = -250
	_name_stroke.offset_top = -306
	_name_stroke.offset_bottom = -244
	add_child(_name_stroke)
	_name = UiTheme.make_label("", UiTheme.title_font(700, 5), UiTheme.SIZE_SMALL + 4, UiTheme.PARCHMENT)
	_name.anchor_left = 0.5
	_name.anchor_right = 0.5
	_name.anchor_top = 1.0
	_name.anchor_bottom = 1.0
	_name.offset_left = -650
	_name.offset_right = -260
	_name.offset_top = -296
	_name.offset_bottom = -254
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_name)
	_next = PromptGlyph.for_action(&"interact", 32)
	_next.anchor_left = 0.5
	_next.anchor_right = 0.5
	_next.anchor_top = 1.0
	_next.anchor_bottom = 1.0
	_next.offset_left = 590
	_next.offset_top = -92
	_next.offset_right = 640
	_next.offset_bottom = -60
	add_child(_next)
	_choice_box = VBoxContainer.new()
	_choice_box.anchor_left = 0.5
	_choice_box.anchor_right = 0.5
	_choice_box.anchor_top = 1.0
	_choice_box.anchor_bottom = 1.0
	_choice_box.offset_left = 120
	_choice_box.offset_right = 660
	_choice_box.offset_bottom = -290
	_choice_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_choice_box.alignment = BoxContainer.ALIGNMENT_END
	_choice_box.add_theme_constant_override(&"separation", 8)
	add_child(_choice_box)
	visible = false


func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	UiFx.fade_in(self, 0.18)
	UiFx.sound(UiFx.OPEN)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_clear_choices()
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.15)
	t.tween_callback(func() -> void: visible = false)
	closed.emit()


## Shows a line and waits for the player to advance. opts: {"element": int, "color": Color}.
func say(speaker: String, text: String, opts: Dictionary = {}) -> void:
	if not is_open:
		open()
	_show_line(speaker, text, opts)
	_waiting = true
	await advanced


## Shows a line with choices; returns the chosen index.
func ask(speaker: String, text: String, options: Array, opts: Dictionary = {}) -> int:
	if not is_open:
		open()
	_show_line(speaker, text, opts)
	_asking = true
	_pending_choices = options
	var idx: int = await choice_made
	return idx



func _show_line(speaker: String, text: String, opts: Dictionary) -> void:
	_clear_choices()
	var e := int(opts.get("element", ElementDefs.Element.NONE))
	var c: Color = opts.get("color", UiTheme.element_color(e).darkened(0.25) if ElementDefs.is_valid(e) else UiTheme.SEAL)
	_name.text = speaker.to_upper()
	_name_stroke.visible = not speaker.is_empty()
	_name_stroke.stroke_color = Color(c, 0.95)
	_name_stroke.sweep(0.3)
	_text.text = text
	_text.visible_characters = 0
	_chars = 0.0
	_revealing = true
	_next.visible = false
	_t = 0.0


func _process(delta: float) -> void:
	if not is_open:
		return
	_t += delta
	if _revealing:
		_chars += delta * reveal_speed
		var total := _text.get_total_character_count()
		_text.visible_characters = int(_chars)
		if _chars >= total:
			_finish_reveal()
	elif _waiting:
		_next.modulate.a = 0.55 + 0.45 * sin(_t * 5.0)


func _finish_reveal() -> void:
	_revealing = false
	_text.visible_characters = -1
	line_finished.emit()
	if _asking:
		_build_choices(_pending_choices)
	else:
		_next.visible = true


## Completes the reveal or advances (same as pressing interact / accept).
func advance() -> void:
	if _revealing:
		_finish_reveal()
		return
	if _waiting:
		_waiting = false
		_next.visible = false
		UiFx.sound(UiFx.CLICK)
		advanced.emit()


func _build_choices(options: Array) -> void:
	_clear_choices()
	for i in options.size():
		var b := Button.new()
		b.text = "%d.  %s" % [i + 1, String(options[i])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(540, 58)
		b.add_theme_font_override(&"font", UiTheme.body_font())
		b.add_theme_font_size_override(&"font_size", UiTheme.SIZE_BODY - 1)
		UiFx.wire(b, {"press_sound": UiFx.CONFIRM})
		b.pressed.connect(choose.bind(i))
		_choice_box.add_child(b)
		choices.append(b)
		# fade only: positions inside the VBox belong to the container
		UiFx.fade_in(b, 0.2, i * 0.05)
	if not choices.is_empty():
		UiFx.focus_silently(choices[0])


## Picks choice `i` (also bound to number keys).
func choose(i: int) -> void:
	if not _asking or i < 0 or i >= choices.size():
		return
	_asking = false
	_clear_choices()
	choice_made.emit(i)


func _clear_choices() -> void:
	for b in choices:
		if is_instance_valid(b):
			b.queue_free()
	choices.clear()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if _asking and not _revealing:
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
			var k := (event as InputEventKey).physical_keycode
			if k >= KEY_1 and k <= KEY_6:
				choose(k - KEY_1)
				get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept") \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		get_viewport().set_input_as_handled()
		advance()
