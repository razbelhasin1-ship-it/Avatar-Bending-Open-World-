class_name JourneyBook
extends CanvasLayer
## The Journey Book: one full-screen, tabbed book for every progression screen - SKILLS
## (bending tree + loadout), MAP (world map + fast travel), JOURNAL (quests), INVENTORY
## (items + discoveries) and CHARACTER (level, stats, companion bond).
##
##   var book: JourneyBook = preload("res://scenes/ui/journey_book.tscn").instantiate()
##   scene.add_child(book)
##   book.open(&"map")                 # also: open_map (M / View), open_skills (K), open_journal (J)
##   book.open(&"skills", {"focus": &"ice_trap"})
##   book.close()
##
## * Opening pauses the tree (the world freezes behind a blurred, dimmed backdrop), shows the
##   mouse and releases every held gameplay action; closing restores all of it. Opened from the
##   pause menu, closing returns there.
## * Close: Esc / B / the platform back button (ui_cancel), the page's own key again (M on the
##   map), the CLOSE button, or a tap / click outside the sheet. Pages may consume Back first
##   (e.g. leaving "choose a slot").
## * Tabs: Q / E, LB / RB, or tap / click a tab. Pages navigate with arrows / d-pad / stick.
## * Joins the groups &"map_screen" and &"journal_screen" so the touch overlay's top bar offers
##   its Map and Journal buttons (docs/modules/mobile.md), and &"journey_book" (pause menu hook).
## * Never traps input: refuses to open during transitions, dialogue, cinematics, death or
##   travel; any of those starting while it is open closes it.

signal opened(page: StringName)
signal closed
signal page_changed(page: StringName)

const LAYER := 80
const PAGES: Array[Dictionary] = [
	{"id": &"skills", "label": "SKILLS", "icon": "icon_skills", "script": "res://src/ui/progression/skill_tree_page.gd", "action": &"open_skills"},
	{"id": &"map", "label": "MAP", "icon": "icon_map", "script": "res://src/ui/map/world_map_page.gd", "action": &"open_map"},
	{"id": &"journal", "label": "JOURNAL", "icon": "icon_journal", "script": "res://src/ui/journal/journal_page.gd", "action": &"open_journal"},
	{"id": &"inventory", "label": "INVENTORY", "icon": "icon_bag", "script": "res://src/ui/inventory/inventory_page.gd", "action": &""},
	{"id": &"character", "label": "CHARACTER", "icon": "icon_character", "script": "res://src/ui/progression/character_page.gd", "action": &""},
]

## False until the world hands control to the player (arrival cinematic, loading).
var enabled := true
var is_open := false
var page: StringName = &""
var pages: Dictionary = {}          # id -> JourneyPage
var root: Control
var sheet: Control
var content: Control
## Opened from the pause menu: closing re-opens it.
var return_to_pause := false
## Tests: skip the pause (the tree keeps running).
var pause_tree := true

var _tabs: Dictionary = {}          # id -> Button
var _tab_stroke: BrushStroke
var _hints: InputHintBar
var _status: Label
var _close: Button
var _glyph_l: PromptGlyph
var _glyph_r: PromptGlyph
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _paused_by_us := false
var _fade: Tween
var _busy_reason := ""
var _level_seal: Label
var _points_label: Label
var _return_menu: Node = null


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"journey_book")
	add_to_group(&"map_screen")
	add_to_group(&"journal_screen")
	UiInput.ensure(get_tree())
	_build()
	Events.dialogue_started.connect(func(_n: Node) -> void: _force_close())
	Events.player_died.connect(_force_close)
	Events.returning_to_menu.connect(_force_close)


func _exit_tree() -> void:
	if is_open:
		_restore_game()


# --- construction ---------------------------------------------------------------------------------

func _build() -> void:
	root = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	add_child(root)
	UiTheme.apply_safe_area(root)
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	var bm := ShaderMaterial.new()
	bm.shader = UiOverlay.BLUR_SHADER
	bm.set_shader_parameter(&"dim", 0.62)
	bg.material = bm
	bg.gui_input.connect(_on_backdrop_input)
	root.add_child(bg)
	sheet = Control.new()
	sheet.name = "Sheet"
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.offset_left = 34
	sheet.offset_right = -34
	sheet.offset_top = 20
	sheet.offset_bottom = -18
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(sheet)
	var frame := Panel.new()
	frame.name = "Frame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := UiFrameStyle.make(Color(UiTheme.INK, 0.9), Color(UiTheme.GOLD, 0.5), 1.5)
	fs.grain = 0.45
	fs.corner_ornaments = true
	fs.ornament_size = 56.0
	frame.add_theme_stylebox_override(&"panel", fs)
	sheet.add_child(frame)
	var v := VBoxContainer.new()
	v.name = "Layout"
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 40
	v.offset_right = -40
	v.offset_top = 14
	v.offset_bottom = -12
	v.add_theme_constant_override(&"separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(v)
	_build_header(v)
	content = Control.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(content)
	var foot := HBoxContainer.new()
	foot.custom_minimum_size = Vector2(0, 46)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(foot)
	_status = UiTheme.make_label("", UiTheme.body_font(1), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	foot.add_child(_status)
	_hints = InputHintBar.new()
	_hints.glyph_height = 30.0
	_hints.alignment = BoxContainer.ALIGNMENT_END
	_hints.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_hints)


func _build_header(v: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.name = "Header"
	head.custom_minimum_size = Vector2(0, UiTheme.touch_height(84))
	head.add_theme_constant_override(&"separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	# left: element seal + level
	var who := HBoxContainer.new()
	who.add_theme_constant_override(&"separation", 12)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(who)
	var em := TextureRect.new()
	em.name = "Emblem"
	em.custom_minimum_size = Vector2(54, 54)
	em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	em.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(em)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override(&"separation", -4)
	wv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(wv)
	_level_seal = UiTheme.make_label("", UiTheme.title_font(700, 3), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT)
	wv.add_child(_level_seal)
	_points_label = UiTheme.make_label("", UiTheme.body_font(1), UiTheme.SIZE_TINY - 1, UiTheme.PARCHMENT_MUTED)
	wv.add_child(_points_label)
	# centre: tabs
	var mid := HBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override(&"separation", 6)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(mid)
	_glyph_l = PromptGlyph.for_entries([{"type": "key", "code": KEY_Q}], [{"type": "joy_button", "button": JOY_BUTTON_LEFT_SHOULDER}], 32)
	_glyph_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(_glyph_l)
	# The brush underline sits behind the tab row: a plain Control (not a container) holds both.
	var wrap := Control.new()
	wrap.name = "TabWrap"
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(wrap)
	_tab_stroke = BrushStroke.new(Color(UiTheme.SEAL, 0.92), 3.3)
	_tab_stroke.set_param(&"thickness", 0.55).set_param(&"tail", 0.45).set_param(&"dryness", 0.6)
	wrap.add_child(_tab_stroke)
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override(&"separation", 4)
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(tabs)
	var fit := func() -> void:
		var m := tabs.get_combined_minimum_size()
		wrap.custom_minimum_size = m
		tabs.size = m
		_place_tab_stroke(false)
	tabs.minimum_size_changed.connect(fit)
	for spec: Dictionary in PAGES:
		var b := Button.new()
		b.name = "Tab_%s" % String(spec["id"])
		b.text = String(spec["label"])
		b.theme_type_variation = &"GhostButton"
		b.focus_mode = Control.FOCUS_NONE
		b.icon = UiTheme.icon(String(spec["icon"]))
		b.expand_icon = false
		b.add_theme_constant_override(&"icon_max_width", 28)
		b.add_theme_constant_override(&"h_separation", 10)
		b.add_theme_font_override(&"font", UiTheme.title_font(700, 3))
		b.add_theme_font_size_override(&"font_size", UiTheme.SIZE_SMALL)
		b.custom_minimum_size = Vector2(0, UiTheme.touch_height(64))
		var id: StringName = spec["id"]
		b.pressed.connect(func() -> void:
			if page != id:
				UiFx.sound(UiFx.CLICK)
				show_page(id))
		b.mouse_entered.connect(func() -> void:
			if page != id:
				UiFx.sound(UiFx.HOVER))
		tabs.add_child(b)
		_tabs[id] = b
	fit.call()
	_glyph_r = PromptGlyph.for_entries([{"type": "key", "code": KEY_E}], [{"type": "joy_button", "button": JOY_BUTTON_RIGHT_SHOULDER}], 32)
	_glyph_r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(_glyph_r)
	# right: close
	var right := HBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(right)
	_close = Button.new()
	_close.name = "Close"
	_close.text = "CLOSE"
	_close.theme_type_variation = &"GhostButton"
	_close.focus_mode = Control.FOCUS_NONE
	_close.icon = UiTheme.icon("ui_close")
	_close.add_theme_constant_override(&"icon_max_width", 26)
	_close.custom_minimum_size = Vector2(UiTheme.touch_height(150), UiTheme.touch_height(64))
	_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close.pressed.connect(func() -> void:
		UiFx.sound(UiFx.BACK)
		close())
	right.add_child(_close)
	var rule := BrushStroke.new(Color(UiTheme.GOLD, 0.55), 7.1)
	rule.set_param(&"thickness", 0.25).set_param(&"tail", 0.5).set_param(&"dryness", 0.7)
	rule.custom_minimum_size = Vector2(0, 10)
	v.add_child(rule)


# --- open / close --------------------------------------------------------------------------------

## Why the book cannot open right now ("" = it can).
func blocked_reason() -> String:
	if not enabled:
		return "not ready"
	if Router.is_transitioning:
		return "transition"
	if not GameState.has_element():
		return "no journey"
	var p := get_tree().get_first_node_in_group(&"player")
	if p != null:
		if p.has_method("is_alive") and not bool(p.call("is_alive")):
			return "dead"
		if p.has_method("get_state") and int(p.call("get_state")) == PlayerCharacter.State.CINEMATIC:
			return "cinematic"
	var w := get_tree().get_first_node_in_group(&"world_scene")
	if w != null:
		var tr: Variant = w.get("travel")
		if tr is TravelSystem and (tr as TravelSystem).busy:
			return "travelling"
		if w.has_method("is_dialogue_open") and bool(w.call("is_dialogue_open")):
			return "dialogue"
	if get_tree().get_first_node_in_group(&"shop_panel") != null:
		return "shop"
	if get_tree().paused and not is_open:
		return "paused"
	return ""


## Opens the book on `page_id` (&"" = the last page, or skills). Returns false when refused.
func open(page_id: StringName = &"", args: Dictionary = {}) -> bool:
	if is_open:
		show_page(page_id if page_id != &"" else page, args)
		return true
	var why := blocked_reason()
	if why != "" and not bool(args.get("force", false)):
		_busy_reason = why
		return false
	is_open = true
	return_to_pause = bool(args.get("from_pause", false))
	_return_menu = args.get("pause_menu") as Node if args.get("pause_menu") is Node else null
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_release_gameplay_actions()
	if pause_tree and not get_tree().paused:
		get_tree().paused = true
		_paused_by_us = true
	_refresh_header()
	root.visible = true
	_kill_fade()
	root.modulate.a = 0.0
	sheet.scale = Vector2(0.985, 0.985)
	sheet.pivot_offset = sheet.size * 0.5
	_fade = root.create_tween().set_parallel(true)
	_fade.tween_property(root, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE)
	_fade.tween_property(sheet, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	UiFx.sound(UiFx.OPEN)
	Events.pause_changed.emit(true)
	var target := page_id if page_id != &"" else (page if page != &"" else &"skills")
	page = &""
	show_page(target, args)
	opened.emit(page)
	return true


func close() -> void:
	if not is_open:
		return
	if pages.has(page):
		(pages[page] as JourneyPage).on_close()
	is_open = false
	_restore_game()
	_kill_fade()
	_fade = root.create_tween()
	_fade.tween_property(root, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_SINE)
	_fade.tween_callback(func() -> void:
		if not is_open:
			root.visible = false)
	UiFx.sound(UiFx.CLOSE)
	closed.emit()
	if return_to_pause:
		return_to_pause = false
		var pm := _return_menu if is_instance_valid(_return_menu) else _pause_menu()
		if pm != null and not bool(pm.get("is_open")):
			pm.call_deferred(&"open")
	_return_menu = null


func toggle(page_id: StringName) -> void:
	if is_open and page == page_id:
		close()
	else:
		open(page_id)


func _restore_game() -> void:
	if _paused_by_us:
		_paused_by_us = false
		get_tree().paused = false
	if _prev_mouse == Input.MOUSE_MODE_CAPTURED:
		var sc := get_tree().get_first_node_in_group(&"playable_scene")
		if sc != null and sc.has_method("capture_mouse"):
			sc.call("capture_mouse")
	else:
		Input.mouse_mode = _prev_mouse
	Events.pause_changed.emit(false)


## Closes at once without returning to the pause menu (dialogue / death / leaving).
func _force_close(_a: Variant = null) -> void:
	if is_open:
		return_to_pause = false
		close()


func _release_gameplay_actions() -> void:
	for a in InputMap.get_actions():
		if String(a).begins_with("ui_"):
			continue
		if Input.is_action_pressed(a):
			Input.action_release(a)


func _pause_menu() -> Node:
	var sc := get_tree().get_first_node_in_group(&"playable_scene")
	if sc != null:
		var pm: Variant = sc.get("pause_menu")
		if pm is Node and is_instance_valid(pm):
			return pm
	return null


func _kill_fade() -> void:
	if _fade and _fade.is_valid():
		_fade.kill()


# --- pages ---------------------------------------------------------------------------------------

func page_spec(id: StringName) -> Dictionary:
	for s: Dictionary in PAGES:
		if s["id"] == id:
			return s
	return {}


## The page instance (built on first use).
func get_page(id: StringName) -> JourneyPage:
	if pages.has(id):
		return pages[id]
	var spec := page_spec(id)
	if spec.is_empty():
		return null
	var script := load(String(spec["script"])) as GDScript
	if script == null:
		return null
	var p := script.new() as JourneyPage
	p.name = "Page_%s" % String(id)
	p.book = self
	p.page_id = id
	p.visible = false
	content.add_child(p)
	pages[id] = p
	return p


func show_page(id: StringName, args: Dictionary = {}) -> void:
	if page_spec(id).is_empty():
		id = &"skills"
	var prev := page
	if prev == id:
		var same := get_page(id)
		if same and not args.is_empty():
			same.on_open(args)
		return
	if pages.has(prev):
		var old: JourneyPage = pages[prev]
		old.on_close()
		old.visible = false
	page = id
	set_status("")
	var p := get_page(id)
	if p == null:
		return
	p.ensure_built()
	p.visible = true
	p.modulate.a = 0.0
	var t := p.create_tween()
	t.tween_property(p, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE)
	p.on_open(args)
	_style_tabs()
	refresh_hints()
	var f := p.initial_focus()
	if f:
		UiFx.focus_silently(f)
	else:
		var owner_focus := root.get_viewport().gui_get_focus_owner() if root.is_inside_tree() else null
		if owner_focus:
			owner_focus.release_focus()
	page_changed.emit(id)


## Next / previous tab.
func cycle_page(step: int) -> void:
	var idx := 0
	for i in PAGES.size():
		if PAGES[i]["id"] == page:
			idx = i
	idx = posmod(idx + step, PAGES.size())
	UiFx.sound(UiFx.CLICK)
	show_page(PAGES[idx]["id"])


func current_page() -> JourneyPage:
	return pages.get(page, null)


func _style_tabs() -> void:
	for id: StringName in _tabs:
		var b: Button = _tabs[id]
		var on := id == page
		b.add_theme_color_override(&"font_color", UiTheme.GOLD_HI if on else UiTheme.PARCHMENT_DIM)
		b.add_theme_color_override(&"font_hover_color", UiTheme.GOLD_HI if on else UiTheme.PARCHMENT)
		b.add_theme_color_override(&"icon_normal_color", UiTheme.GOLD_HI if on else UiTheme.PARCHMENT_MUTED)
		b.add_theme_color_override(&"icon_hover_color", UiTheme.GOLD_HI)
	_place_tab_stroke.call_deferred(true)


func _place_tab_stroke(animate: bool) -> void:
	if not _tabs.has(page):
		return
	var b: Button = _tabs[page]
	_tab_stroke.position = Vector2(b.position.x - 10, b.size.y * 0.5 - 22)
	_tab_stroke.size = Vector2(b.size.x + 20, 44)
	_tab_stroke.modulate.a = 0.85
	if animate:
		_tab_stroke.sweep(0.3)


## Rebuilds the footer hints from the current page (+ the book's own tab / close hints).
func refresh_hints() -> void:
	var p := current_page()
	var hs: Array = p.hints() if p else []
	hs = hs.duplicate()
	hs.append({"action": &"ui_cancel", "text": "Close"})
	_hints.set_hints(hs)


## Footer status line (pages report what just happened).
func set_status(text: String, color: Color = UiTheme.PARCHMENT_DIM) -> void:
	_status.text = text
	_status.add_theme_color_override(&"font_color", color)
	_status.modulate.a = 1.0


func _refresh_header() -> void:
	var e := GameState.element
	var em := root.find_child("Emblem", true, false) as TextureRect
	if em:
		em.texture = UiTheme.emblem(e)
		em.modulate = UiTheme.element_light(e)
	_level_seal.text = ("%s  ·  LEVEL %d" % [ElementDefs.display_name(e).to_upper(), GameState.level]) if ElementDefs.is_valid(e) else "WANDERER"
	var sp := GameState.skill_points
	_points_label.text = "%d skill point%s  ·  %d coins" % [sp, "" if sp == 1 else "s", GameState.currency]
	var touch := UiInput.device == &"touch"
	_glyph_l.visible = not touch
	_glyph_r.visible = not touch


func _process(delta: float) -> void:
	if not is_open:
		return
	# Something else took over (cinematic, travel, a scene change): never trap the player.
	if Router.is_transitioning:
		_force_close()
		return
	_refresh_header()
	var p := current_page()
	if p:
		p.page_process(delta)


# --- input ---------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if is_open or not enabled:
		return
	for spec: Dictionary in PAGES:
		var a: StringName = spec["action"]
		if a != &"" and InputMap.has_action(a) and event.is_action_pressed(a) and not event.is_echo():
			if open(spec["id"]):
				get_viewport().set_input_as_handled()
			return


## While open the book sees input first (the pause menu also listens to `pause`): Back closes
## (after the page had a chance to undo a local mode), tab keys switch pages, open_* keys switch
## to / toggle their page. A modal dialog of a page gets its own Back.
func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if _modal_open():
		return
	var p := current_page()
	if p and p.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		if p and p.handle_back():
			return
		UiFx.sound(UiFx.BACK)
		close()
		return
	for spec: Dictionary in PAGES:
		var a: StringName = spec["action"]
		if a != &"" and InputMap.has_action(a) and event.is_action_pressed(a):
			get_viewport().set_input_as_handled()
			toggle(spec["id"])
			return
	var step := _tab_step(event)
	if step != 0:
		get_viewport().set_input_as_handled()
		cycle_page(step)


static func _tab_step(event: InputEvent) -> int:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).physical_keycode:
			KEY_Q: return -1
			KEY_E: return 1
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_LEFT_SHOULDER: return -1
			JOY_BUTTON_RIGHT_SHOULDER: return 1
	return 0


func _modal_open() -> bool:
	for n in root.find_children("*", "UiOverlay", true, false):
		if (n as UiOverlay).is_open:
			return true
	return false


func _on_backdrop_input(event: InputEvent) -> void:
	# A tap / click on the dimmed margin outside the sheet closes the book.
	var tap := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		tap = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tap = (event as InputEventScreenTouch).pressed
	if tap and is_open and not _modal_open():
		UiFx.sound(UiFx.BACK)
		close()


## Shows a confirmation over the book; returns the answer id (&"cancel" on Back).
func confirm(title: String, text: String, choices: Array) -> StringName:
	var d := ConfirmDialog.new()
	d.name = "Confirm"
	root.add_child(d)
	d.ask(title, text, choices)
	var id: StringName = await d.answered
	d.queue_free()
	return id
