class_name LevelUpBanner
extends Control
## The level-up moment (Events.player_level_up): an element-coloured brush stroke sweeps
## across the upper screen with "LEVEL 6", the skill points to spend, the techniques that
## just became learnable, and a prompt to open the skill tree - the key glyph on keyboard,
## the pause-menu route on a controller, a tappable OPEN SKILLS button on touch. Several
## level-ups queue. Never blocks input (only the touch button takes taps) and stays out of
## the HUD's clear centre (it sits above it). Audio plays the level_up stinger itself.

const SHOW_TIME := 4.6

var book: JourneyBook = null
## Banners shown so far (tests).
var shown := 0
var is_showing := false

var _queue: Array[int] = []
var _panel: Control
var _stroke: BrushStroke
var _caption: Label
var _title: Label
var _points: Label
var _ready_line: Label
var _prompt: HBoxContainer
var _glyph: PromptGlyph
var _prompt_label: Label
var _button: Button
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiTheme.get_theme()
	_build()
	visible = false
	Events.player_level_up.connect(_on_level_up)


func _exit_tree() -> void:
	if Events.player_level_up.is_connected(_on_level_up):
		Events.player_level_up.disconnect(_on_level_up)


func _build() -> void:
	_panel = Control.new()
	_panel.name = "Panel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -560
	_panel.offset_right = 560
	_panel.offset_top = 112
	_panel.offset_bottom = 330
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_stroke = BrushStroke.new(Color(UiTheme.SEAL, 0.9), 5.5)
	_stroke.set_param(&"thickness", 0.78).set_param(&"tail", 0.35).set_param(&"dryness", 0.7).set_param(&"wobble", 0.05)
	_stroke.position = Vector2(60, 34)
	_stroke.size = Vector2(1000, 122)
	_panel.add_child(_stroke)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_BEGIN
	v.add_theme_constant_override(&"separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(v)
	_caption = UiTheme.make_label("YOUR BENDING GROWS", UiTheme.title_font(700, 8), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_caption)
	_title = UiTheme.make_label("", UiTheme.title_font(800, 14), UiTheme.SIZE_H1 + 8, UiTheme.GOLD_HI, HORIZONTAL_ALIGNMENT_CENTER)
	_title.add_theme_color_override(&"font_outline_color", Color(UiTheme.INK, 0.85))
	_title.add_theme_constant_override(&"outline_size", 10)
	v.add_child(_title)
	_points = UiTheme.make_label("", UiTheme.title_font(700, 3), UiTheme.SIZE_BODY, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	_points.add_theme_color_override(&"font_outline_color", Color(UiTheme.INK, 0.8))
	_points.add_theme_constant_override(&"outline_size", 6)
	v.add_child(_points)
	_ready_line = UiTheme.make_label("", UiTheme.body_font(1), UiTheme.SIZE_SMALL, UiTheme.GOLD_HI, HORIZONTAL_ALIGNMENT_CENTER)
	_ready_line.add_theme_color_override(&"font_outline_color", Color(UiTheme.INK, 0.8))
	_ready_line.add_theme_constant_override(&"outline_size", 6)
	v.add_child(_ready_line)
	_prompt = HBoxContainer.new()
	_prompt.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt.add_theme_constant_override(&"separation", 10)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_prompt)
	_glyph = PromptGlyph.for_action(&"open_skills", 32)
	_prompt.add_child(_glyph)
	_prompt_label = UiTheme.make_label("Open Bending Skills", UiTheme.title_font(600, 2), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_DIM)
	_prompt_label.add_theme_color_override(&"font_outline_color", Color(UiTheme.INK, 0.8))
	_prompt_label.add_theme_constant_override(&"outline_size", 5)
	_prompt.add_child(_prompt_label)
	_button = Button.new()
	_button.name = "OpenSkills"
	_button.text = "OPEN SKILLS"
	_button.theme_type_variation = &"PrimaryButton"
	_button.custom_minimum_size = Vector2(320, UiTheme.TOUCH_TARGET)
	_button.focus_mode = Control.FOCUS_NONE
	_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_button.pressed.connect(open_skills)
	_prompt.add_child(_button)


func _on_level_up(level: int) -> void:
	if GameState.is_tutorial:
		return
	_queue.append(level)
	if not is_showing and not _pending:
		# deferred: several level-ups from one reward arrive in the same frame and show as one
		_pending = true
		_start_deferred.call_deferred()


var _pending := false


func _start_deferred() -> void:
	_pending = false
	if not is_showing:
		_next()


func _next() -> void:
	if _queue.is_empty():
		is_showing = false
		visible = false
		return
	var level: int = _queue.pop_front()
	# several level-ups at once: show the highest
	while not _queue.is_empty() and _queue[0] > level:
		level = _queue.pop_front()
	is_showing = true
	shown += 1
	_t = SHOW_TIME
	var e := GameState.element
	_stroke.stroke_color = Color(UiTheme.element_color(e).darkened(0.15), 0.9) if ElementDefs.is_valid(e) else Color(UiTheme.SEAL, 0.9)
	_title.text = "LEVEL %d" % level
	var sp := GameState.skill_points
	_points.text = "+1 Skill Point  ·  %d to spend" % sp if sp > 1 else "+1 Skill Point"
	var ready := SkillTreeModel.learnable(e) if ElementDefs.is_valid(e) else ([] as Array[StringName])
	var names := PackedStringArray()
	for id in ready:
		names.append(SkillTreeModel.display_name(id))
	_ready_line.text = ("Ready to learn: %s" % ", ".join(names)) if not names.is_empty() else ""
	_ready_line.visible = not names.is_empty()
	_sync_prompt()
	visible = true
	modulate.a = 1.0
	_panel.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25)
	_stroke.sweep(0.45)
	_title.scale = Vector2(1.18, 1.18)
	_title.pivot_offset = Vector2(560, 40)
	tw.tween_property(_title, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _sync_prompt() -> void:
	var touch := UiInput.device == &"touch"
	_button.visible = touch and book != null
	_glyph.visible = not touch and UiInput.device != &"pad"
	_prompt_label.visible = not touch
	if UiInput.device == &"pad":
		_prompt_label.text = "Pause  ·  Skills to spend it"
	else:
		_prompt_label.text = "Open Bending Skills"
	_prompt.visible = book != null


func _process(delta: float) -> void:
	if not is_showing:
		return
	# The book opened (the prompt did its job): the banner steps aside for good.
	if book != null and book.is_open:
		is_showing = false
		_queue.clear()
		visible = false
		return
	if get_tree().paused:
		return
	_t -= delta
	if _t <= 0.0:
		is_showing = false
		var tw := create_tween()
		tw.tween_property(_panel, "modulate:a", 0.0, 0.35)
		_stroke.retract(0.3)
		tw.tween_callback(_next)


## Touch button: open the skill tree right away.
func open_skills() -> void:
	if book == null:
		return
	_t = 0.0
	book.open(&"skills")
