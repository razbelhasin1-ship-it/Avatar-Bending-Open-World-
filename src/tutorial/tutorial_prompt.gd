class_name TutorialPrompt
extends Control
## On-screen instruction card of the training grounds (right side, where the quest tracker
## sits in the world): step counter, title, instruction with the live bindings of the active
## device (keycaps / controller glyphs / touch wording - it re-renders when the player
## switches device), a progress bar and the "hold to skip" line.

const WIDTH := 540.0

var panel: PanelContainer
var header: Label
var title: Label
var body: Label
var glyph_row: HBoxContainer
var bar_back: ColorRect
var bar_fill: ColorRect
var count: Label
var skip_row: HBoxContainer
var skip_label: Label
var done_label: Label
var stroke: BrushStroke
var step: Dictionary = {}
var progress := 0.0
var target := 1.0

var _index := 0
var _total := 1
var _skip_ratio := 0.0
var _element: int = ElementDefs.Element.NONE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	panel = PanelContainer.new()
	panel.theme_type_variation = &"InkPanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -WIDTH - 40.0
	panel.offset_right = -40.0
	panel.offset_top = 300.0
	panel.offset_bottom = 300.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	panel.add_child(v)
	header = UiTheme.make_label("", UiTheme.title_font(600, 6), UiTheme.SIZE_TINY, UiTheme.GOLD)
	v.add_child(header)
	stroke = BrushStroke.new(Color(UiTheme.SEAL, 0.9), 2.7)
	stroke.custom_minimum_size = Vector2(260, 12)
	stroke.set_param(&"thickness", 0.5).set_param(&"tail", 0.5)
	v.add_child(stroke)
	title = UiTheme.make_label("", UiTheme.title_font(700, 3), UiTheme.SIZE_H3 - 4, UiTheme.PARCHMENT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)
	glyph_row = HBoxContainer.new()
	glyph_row.add_theme_constant_override(&"separation", 8)
	glyph_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(glyph_row)
	body = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(WIDTH - 40.0, 0)
	v.add_child(body)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override(&"separation", 14)
	v.add_child(prow)
	var bar_box := Control.new()
	bar_box.custom_minimum_size = Vector2(WIDTH - 150.0, 12)
	bar_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prow.add_child(bar_box)
	bar_back = ColorRect.new()
	bar_back.color = Color(UiTheme.PARCHMENT, 0.12)
	bar_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_box.add_child(bar_back)
	bar_fill = ColorRect.new()
	bar_fill.color = UiTheme.GOLD
	bar_fill.anchor_bottom = 1.0
	bar_fill.anchor_right = 0.0
	bar_box.add_child(bar_fill)
	count = UiTheme.make_label("", UiTheme.title_font(700, 2), UiTheme.SIZE_SMALL, UiTheme.GOLD_HI)
	prow.add_child(count)
	skip_row = HBoxContainer.new()
	skip_row.add_theme_constant_override(&"separation", 10)
	skip_row.modulate.a = 0.6
	v.add_child(skip_row)
	var sg := PromptGlyph.for_action(&"interact", 26)
	skip_row.add_child(sg)
	skip_label = UiTheme.make_label("Hold to skip this lesson", UiTheme.body_font(), UiTheme.SIZE_TINY, UiTheme.PARCHMENT_DIM)
	skip_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	skip_row.add_child(skip_label)
	done_label = UiTheme.make_label("", UiTheme.title_font(700, 10), UiTheme.SIZE_H3, UiTheme.GOLD_HI, HORIZONTAL_ALIGNMENT_CENTER)
	done_label.anchor_left = 0.5
	done_label.anchor_right = 0.5
	done_label.offset_left = -500
	done_label.offset_right = 500
	done_label.offset_top = 236
	done_label.offset_bottom = 290
	done_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.7))
	done_label.add_theme_constant_override(&"shadow_outline_size", 10)
	done_label.modulate.a = 0.0
	add_child(done_label)
	UiInput.ensure(get_tree()).device_changed.connect(func(_d: StringName) -> void: refresh())
	Events.controls_changed.connect(refresh)
	visible = false


func set_element(e: int) -> void:
	_element = e
	bar_fill.color = UiTheme.element_light(e)


## Shows a step card ("index" is 0-based).
func show_step(p_step: Dictionary, index: int, total: int) -> void:
	step = p_step
	_index = index
	_total = total
	progress = 0.0
	target = maxf(float(step.get("target", 1.0)), 0.0001)
	_skip_ratio = 0.0
	visible = true
	refresh()
	stroke.sweep(0.35)
	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.3)


## Re-renders texts and glyphs for the active device.
func refresh() -> void:
	if step.is_empty():
		return
	var dev := UiInput.device
	header.text = "TRAINING  ·  %d / %d" % [_index + 1, _total]
	title.text = String(step.get("title", "")).to_upper()
	body.text = TutorialSteps.text_for(step, dev)
	for c in glyph_row.get_children():
		c.queue_free()
	glyph_row.visible = dev != &"touch"
	if dev != &"touch":
		var explicit: Dictionary = step.get("glyphs", {})
		if not explicit.is_empty():
			glyph_row.add_child(PromptGlyph.for_entries(explicit.get("kbm", []), explicit.get("pad", []), 40))
		for a: StringName in step.get("actions", []):
			if InputMap.has_action(a):
				glyph_row.add_child(PromptGlyph.for_action(a, 40))
	skip_row.visible = true
	_update_bar()


func set_progress(value: float) -> void:
	progress = value
	_update_bar()


## 0..1 while the skip button is held.
func set_skip_progress(r: float) -> void:
	_skip_ratio = r
	skip_row.modulate.a = 0.6 + 0.4 * r
	skip_label.text = "Hold to skip this lesson" if r <= 0.0 else "Skipping..."


func _update_bar() -> void:
	var r := clampf(progress / target, 0.0, 1.0)
	bar_fill.anchor_right = r
	bar_fill.offset_right = 0.0
	var unit := String(step.get("unit", ""))
	match unit:
		"s": count.text = "%.1f / %.1f s" % [minf(progress, target), target]
		"m": count.text = "%d / %d m" % [int(minf(progress, target)), int(target)]
		"°": count.text = "%d%%" % int(r * 100.0)
		_: count.text = "%d / %d" % [int(minf(progress, target)), int(target)]


## "WELL DONE" flash in the upper centre when a step completes.
func flash_done(skipped: bool) -> void:
	done_label.text = "LESSON SKIPPED" if skipped else "WELL DONE"
	done_label.modulate = Color(1, 1, 1, 0) if not skipped else Color(0.8, 0.78, 0.72, 0)
	var tw := create_tween()
	tw.tween_property(done_label, "modulate:a", 1.0, 0.15)
	tw.tween_interval(0.6)
	tw.tween_property(done_label, "modulate:a", 0.0, 0.4)
	progress = target
	_update_bar()


func hide_card() -> void:
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void: visible = false)
