class_name HudQuestTracker
extends VBoxContainer
## Tracked-quest panel (right side): quest title and its objectives with progress.
##   tracker.show_quest({"title": "The Spirit Oasis", "objectives": [
##       {"text": "Speak to Master Pakku", "done": true},
##       {"text": "Collect spirit water", "count": 1, "target": 3}]})
## The HUD calls it from Events.quest_* using the bound quest provider.

var data: Dictionary = {}
var _title: Label
var _list: VBoxContainer
## The running slide-in (show_quest) and the layout position it slides to.
var _slide: Tween = null
var _slide_home := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 8)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 12)
	add_child(head)
	var icon := TextureRect.new()
	icon.texture = UiTheme.icon("icon_quest")
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.modulate = UiTheme.GOLD
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(icon)
	_title = UiTheme.make_label("", UiTheme.title_font(700, 3), UiTheme.SIZE_SMALL + 2, UiTheme.GOLD_HI)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(380, 0)
	_title.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	_title.add_theme_constant_override(&"shadow_outline_size", 6)
	head.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 6)
	add_child(_list)
	visible = false


func show_quest(d: Dictionary) -> void:
	var same := String(d.get("title", "")) == String(data.get("title", ""))
	data = d
	_title.text = String(d.get("title", ""))
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for o: Dictionary in d.get("objectives", []):
		_list.add_child(_objective_row(o))
	visible = not _title.text.is_empty()
	if visible and not same:
		settle()
		_slide_home = position
		_slide = UiFx.slide_in(self, Vector2(40, 0), 0.35)
	elif visible:
		UiFx.pop(self, 1.02, 0.18)


func clear_quest() -> void:
	settle()
	data = {}
	visible = false


## Ends a running slide-in at once: back at its layout position, fully opaque. The HUD calls
## it before moving the tracker (touch layout), and a new quest before its own slide: a
## running slide tweens `position` to where it started, so it would carry the tracker back
## to its old place (under the phone's touch buttons) or leave it 40 px off.
func settle() -> void:
	if _slide != null and _slide.is_valid():
		_slide.kill()
		position = _slide_home
		modulate.a = 1.0
	_slide = null


func _objective_row(o: Dictionary) -> Control:
	var done := bool(o.get("done", false))
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 10)
	var mark := TextureRect.new()
	mark.texture = UiTheme.icon("ui_check" if done else "ui_diamond")
	mark.custom_minimum_size = Vector2(16, 16)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mark.modulate = UiTheme.SUCCESS if done else Color(UiTheme.GOLD, 0.85)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(mark)
	var text := String(o.get("text", ""))
	if o.has("target") and int(o.get("target", 0)) > 1:
		text += "  (%d/%d)" % [int(o.get("count", 0)), int(o.get("target", 0))]
	var l := UiTheme.make_label(text, UiTheme.body_font(), UiTheme.SIZE_SMALL, Color(UiTheme.PARCHMENT, 0.5) if done else UiTheme.PARCHMENT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	l.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override(&"shadow_outline_size", 6)
	h.add_child(l)
	return h


func objective_count() -> int:
	return _list.get_child_count()
