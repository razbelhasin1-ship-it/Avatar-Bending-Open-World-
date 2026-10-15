class_name HudToasts
extends VBoxContainer
## Notification stack (top right) for Events.notify(text, kind):
## info, quest, warning, discovery, unlock — each with its icon, accent and sound.
## At most `max_visible` at once; each slides in, waits, and fades out.

const KINDS := {
	&"info": {"icon": "icon_info", "color": Color("efe3c8"), "sound": &"ui_notify", "time": 4.0, "title": ""},
	&"quest": {"icon": "icon_quest", "color": Color("f7d993"), "sound": &"ui_quest", "time": 6.0, "title": "QUEST"},
	&"warning": {"icon": "icon_warning", "color": Color("de5a41"), "sound": &"ui_error", "time": 4.0, "title": ""},
	&"discovery": {"icon": "icon_discovery", "color": Color("9fd7e8"), "sound": &"ui_discovery", "time": 5.5, "title": "DISCOVERED"},
	&"unlock": {"icon": "icon_unlock", "color": Color("f7d993"), "sound": &"ui_levelup", "time": 6.0, "title": "UNLOCKED"},
}

var max_visible := 4


func _ready() -> void:
	add_theme_constant_override(&"separation", 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN


## Shows a toast. Returns the toast node.
func push(text: String, kind: StringName = &"info") -> Control:
	var spec: Dictionary = KINDS.get(kind, KINDS[&"info"])
	while get_child_count() >= max_visible:
		var old := get_child(0)
		remove_child(old)
		old.queue_free()
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ToastPanel"
	var sb := (panel.get_theme_stylebox(&"panel", &"ToastPanel") as StyleBox)
	if sb is UiFrameStyle:
		var custom := (sb as UiFrameStyle).duplicate() as UiFrameStyle
		custom.accent_color = spec["color"]
		panel.add_theme_stylebox_override(&"panel", custom)
	panel.custom_minimum_size = Vector2(500, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_meta(&"kind", kind)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 16)
	panel.add_child(h)
	var icon := TextureRect.new()
	icon.texture = UiTheme.icon(spec["icon"])
	icon.custom_minimum_size = Vector2(38, 38)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.modulate = spec["color"]
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	if String(spec["title"]) != "":
		v.add_child(UiTheme.make_label(spec["title"], UiTheme.title_font(600, 6), UiTheme.SIZE_TINY - 2, Color(spec["color"], 0.9)))
	var l := UiTheme.make_label(text, UiTheme.body_font(), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(400, 0)
	v.add_child(l)
	add_child(panel)
	UiFx.sound(spec["sound"])
	panel.modulate.a = 0.0
	var t := panel.create_tween()
	t.tween_property(panel, "modulate:a", 1.0, 0.22)
	t.tween_interval(float(spec["time"]))
	t.tween_property(panel, "modulate:a", 0.0, 0.4)
	t.tween_callback(panel.queue_free)
	return panel


func count() -> int:
	var n := 0
	for c in get_children():
		if not c.is_queued_for_deletion():
			n += 1
	return n
