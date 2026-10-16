class_name TutorialCompleteScreen
extends CanvasLayer
## End of the training grounds: "TRAINING COMPLETE" over the blurred arena with the element's
## emblem, lessons mastered / skipped, and two choices - ENTER THE WORLD (a new journey as that
## element) or MAIN MENU. Mouse, keyboard, controller and touch (88 px+ targets).

signal enter_world
signal main_menu

var root: Control
var options: Array[MenuOptionButton] = []
var title: Label
var body: Label
var emblem: TextureRect
var element: int = ElementDefs.Element.WATER

var _busy := false


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiInput.ensure(get_tree())
	root = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	UiTheme.apply_safe_area(root)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bm := ShaderMaterial.new()
	bm.shader = UiOverlay.BLUR_SHADER
	bm.set_shader_parameter(&"dim", 0.45)
	bg.material = bm
	root.add_child(bg)
	var stroke := BrushStroke.new(Color(UiTheme.INK, 0.88), 5.1)
	stroke.set_param(&"thickness", 0.95).set_param(&"tail", 0.3).set_param(&"dryness", 0.5)
	stroke.anchor_left = 0.5
	stroke.anchor_right = 0.5
	stroke.offset_left = -820
	stroke.offset_right = 820
	stroke.offset_top = 150
	stroke.offset_bottom = 520
	root.add_child(stroke)
	emblem = TextureRect.new()
	emblem.anchor_left = 0.5
	emblem.anchor_right = 0.5
	emblem.offset_left = -70
	emblem.offset_right = 70
	emblem.offset_top = 170
	emblem.offset_bottom = 310
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(emblem)
	title = UiTheme.make_label("TRAINING COMPLETE", UiTheme.title_font(700, 16), UiTheme.SIZE_H1, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.offset_left = -900
	title.offset_right = 900
	title.offset_top = 318
	title.offset_bottom = 400
	root.add_child(title)
	body = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_BODY, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.anchor_left = 0.5
	body.anchor_right = 0.5
	body.offset_left = -640
	body.offset_right = 640
	body.offset_top = 404
	body.offset_bottom = 500
	root.add_child(body)
	var col := VBoxContainer.new()
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.offset_left = -330
	col.offset_right = 330
	col.offset_top = 560
	col.offset_bottom = 800
	col.add_theme_constant_override(&"separation", 8)
	root.add_child(col)
	var labels := ["ENTER THE WORLD", "MAIN MENU"]
	for i in labels.size():
		var b := MenuOptionButton.new("%02d" % (i + 1), labels[i], UiTheme.SEAL)
		b.name = "Option%d" % (i + 1)
		b.custom_minimum_size = Vector2(660, maxf(MenuOptionButton.HEIGHT, UiTheme.touch_height(88)))
		col.add_child(b)
		options.append(b)
	options[0].pressed.connect(_on_enter)
	options[1].pressed.connect(_on_menu)
	options[0].focus_neighbor_bottom = options[0].get_path_to(options[1])
	options[1].focus_neighbor_top = options[1].get_path_to(options[0])
	var hints := InputHintBar.new()
	hints.anchor_left = 0.5
	hints.anchor_right = 0.5
	hints.anchor_top = 1.0
	hints.anchor_bottom = 1.0
	hints.offset_left = -400
	hints.offset_right = 400
	hints.offset_top = -110
	hints.offset_bottom = -60
	hints.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(hints)
	hints.set_hints(InputHintBar.navigate_select_back(false))
	root.visible = false


## Shows the screen for an element with the lesson summary from TutorialDirector.finished.
func show_summary(p_element: int, summary: Dictionary) -> void:
	element = p_element
	emblem.texture = UiTheme.emblem(element)
	emblem.modulate = UiTheme.element_light(element)
	var total := int(summary.get("total", 0))
	var n_skip := (summary.get("skipped", []) as Array).size()
	var n_done := (summary.get("completed", []) as Array).size()
	var who := String(ElementDefs.get_data(element).get("name", "bender"))
	var line := "You have learned the ways of the %s." % who
	if total > 0:
		line += "\n%d of %d lessons mastered" % [n_done, total]
		if n_skip > 0:
			line += "  ·  %d skipped" % n_skip
	body.text = line
	root.visible = true
	root.modulate.a = 0.0
	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 1.0, 0.4)
	UiFx.sound(&"ui_levelup")
	UiFx.focus_silently(options[0])


func _on_enter() -> void:
	if _busy:
		return
	_busy = true
	enter_world.emit()


func _on_menu() -> void:
	if _busy:
		return
	_busy = true
	main_menu.emit()
