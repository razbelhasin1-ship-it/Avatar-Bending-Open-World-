class_name SaveChooser
extends UiOverlay
## Compact Continue / New Journey chooser shown by ENTER THE WORLD when a save exists.
## Shows the latest journey (element emblem, level, region, play time, save date).
## NEW JOURNEY asks for confirmation because the new adventure's saves replace the old.

signal continue_requested(slot: int)
signal new_journey_requested

var slot := -1
var panel: PanelContainer
var continue_button: Button
var new_button: Button
var confirm_button: Button
var keep_button: Button

var _emblem: TextureRect
var _title: Label
var _details: Label
var _saved: Label
var _message: Label
var _main_row: HBoxContainer
var _confirm_row: HBoxContainer


func _init() -> void:
	super()
	dim = 0.35


func _build() -> void:
	panel = PanelContainer.new()
	panel.theme_type_variation = &"InkPanel"
	panel.position = Vector2(760, 470)
	panel.custom_minimum_size = Vector2(640, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 16)
	panel.add_child(v)
	var head := UiTheme.make_label("YOUR JOURNEY", UiTheme.title_font(600, 8), UiTheme.SIZE_SMALL, UiTheme.GOLD)
	v.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 22)
	v.add_child(row)
	_emblem = TextureRect.new()
	_emblem.custom_minimum_size = Vector2(96, 96)
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emblem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	row.add_child(_emblem)
	var info := VBoxContainer.new()
	info.add_theme_constant_override(&"separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	_title = UiTheme.make_label("", UiTheme.title_font(700, 3), UiTheme.SIZE_H3, UiTheme.PARCHMENT)
	_details = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_DIM)
	_saved = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_TINY, UiTheme.PARCHMENT_MUTED)
	info.add_child(_title)
	info.add_child(_details)
	info.add_child(_saved)
	_message = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(580, 0)
	_message.visible = false
	v.add_child(_message)
	_main_row = HBoxContainer.new()
	_main_row.add_theme_constant_override(&"separation", 16)
	v.add_child(_main_row)
	continue_button = _button("CONTINUE", &"PrimaryButton")
	new_button = _button("NEW JOURNEY", &"")
	_main_row.add_child(continue_button)
	_main_row.add_child(new_button)
	_confirm_row = HBoxContainer.new()
	_confirm_row.add_theme_constant_override(&"separation", 16)
	_confirm_row.visible = false
	v.add_child(_confirm_row)
	confirm_button = _button("BEGIN ANEW", &"DangerButton")
	keep_button = _button("KEEP JOURNEY", &"")
	_confirm_row.add_child(confirm_button)
	_confirm_row.add_child(keep_button)
	continue_button.pressed.connect(func() -> void:
		continue_requested.emit(slot))
	new_button.pressed.connect(_ask_confirm)
	confirm_button.pressed.connect(func() -> void:
		new_journey_requested.emit())
	keep_button.pressed.connect(_cancel_confirm)


func _button(text: String, variation: StringName) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(270, UiTheme.TOUCH_TARGET * 0.8)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != &"":
		b.theme_type_variation = variation
	UiFx.wire(b, {"press_sound": UiFx.CONFIRM})
	return b


## Shows the chooser for a save slot, next to `anchor` (the menu option).
func open_for(p_slot: int, anchor: Control = null) -> void:
	slot = p_slot
	var info := SaveSystem.get_save_info(slot)
	var e := int(info.get("element", ElementDefs.Element.NONE))
	_emblem.texture = UiTheme.emblem(e)
	_emblem.modulate = UiTheme.element_light(e)
	_title.text = "%s · Level %d" % [ElementDefs.display_name(e), int(info.get("level", 1))] if not info.is_empty() else "Unknown journey"
	var region := StringName(String(info.get("region", "")))
	_details.text = "%s   ·   %s played" % [WorldData.get_region_name(region) if region != &"" else "—", format_play_time(float(info.get("play_time", 0.0)))]
	_saved.text = "Saved %s" % String(info.get("saved_at", "")).replace("T", "  ") if info.has("saved_at") else ""
	_message.visible = false
	_confirm_row.visible = false
	_main_row.visible = true
	if anchor:
		panel.position = Vector2(anchor.global_position.x + 700.0, anchor.global_position.y - 40.0)
	open()
	UiFx.slide_in(panel, Vector2(-30, 0), 0.28)


func _initial_focus() -> Control:
	return continue_button


func _ask_confirm() -> void:
	_message.text = "Begin a new journey? Your current journey stays on disk until the new one is saved over it."
	_message.visible = true
	_main_row.visible = false
	_confirm_row.visible = true
	UiFx.focus_silently(keep_button)


func _cancel_confirm() -> void:
	_message.visible = false
	_confirm_row.visible = false
	_main_row.visible = true
	UiFx.focus_silently(new_button)


func show_error(text: String) -> void:
	_message.text = text
	_message.add_theme_color_override(&"font_color", UiTheme.DANGER)
	_message.visible = true
	UiFx.sound(UiFx.ERROR)


func _on_back() -> void:
	if _confirm_row.visible:
		_cancel_confirm()
		return
	close()


## "2h 14m" / "37m".
static func format_play_time(seconds: float) -> String:
	var m := int(seconds / 60.0)
	if m >= 60:
		return "%dh %02dm" % [m / 60, m % 60]
	return "%dm" % m
