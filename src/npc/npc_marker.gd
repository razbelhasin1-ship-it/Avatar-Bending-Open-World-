class_name NpcMarker
extends Node3D
## Above a named NPC: a floating quest glyph (gold seal when the NPC offers a quest, a pale
## blue diamond when an active objective needs them, a coin for merchants, a fist for trainers)
## that bobs gently and reads from afar, and a name plate ("MASTER SIKU · Waterbending Master")
## that fades in within a few metres. Refreshes at 2 Hz from Quests.npc_marker().

const NAME_RANGE := 11.0

var npc: NpcCharacter = null
var state: StringName = &""

var _icon: Sprite3D
var _name: Label3D
var _t := 0.0
var _bob := 0.0
var _icon_color := Color.WHITE


func _ready() -> void:
	_icon = Sprite3D.new()
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_icon.pixel_size = 0.0055
	_icon.no_depth_test = true
	_icon.shaded = false
	_icon.render_priority = 10
	_icon.visibility_range_end = 70.0
	_icon.visible = false
	add_child(_icon)
	_name = Label3D.new()
	_name.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name.font = UiTheme.title_font(700, 3)
	_name.font_size = 40
	_name.pixel_size = 0.0040
	_name.outline_size = 10
	_name.outline_modulate = Color(0.08, 0.05, 0.04, 0.85)
	_name.modulate = Color(UiTheme.PARCHMENT, 0.0)
	_name.position = Vector3(0, -0.28, 0)
	_name.visibility_range_end = NAME_RANGE + 2.0
	add_child(_name)
	if npc != null and npc.npc_id != &"":
		var d := NpcRegistry.get_npc(npc.npc_id)
		var title := String(d.get("title", ""))
		_name.text = String(d.get("name", "")).to_upper() + (("\n" + title) if title != "" else "")


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.5
		_refresh()
	_bob += delta
	_icon.position.y = 0.2 + sin(_bob * 2.2) * 0.06
	var pl := Quests.get_player()
	var a := 0.0
	# both fade out when the camera is right behind / beside the NPC (no screen-filling plates)
	var near := 1.0
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		near = clampf((cam.global_position.distance_to(global_position) - 2.6) / 2.0, 0.0, 1.0)
	if pl != null:
		var d := pl.global_position.distance_to(global_position)
		a = clampf((NAME_RANGE - d) / 3.0, 0.0, 1.0) * near
		if npc != null and npc.in_conversation():
			a = 0.0
	_name.modulate.a = a
	_name.visible = a > 0.01
	var talking := npc != null and npc.in_conversation()
	_icon.modulate = Color(_icon_color, _icon_color.a * near)
	_icon.visible = state != &"" and not talking and near > 0.01


func _refresh() -> void:
	if npc == null:
		return
	var s := Quests.npc_marker(npc.npc_id)
	if s == &"":
		var role: StringName = NpcRegistry.get_npc(npc.npc_id).get("role", &"")
		if role == &"merchant":
			s = &"merchant"
		elif role == &"trainer" and not TrainerLessons.lessons_for(npc.npc_id).is_empty():
			s = &"trainer"
	if s == state:
		return
	state = s
	match s:
		&"available":
			_icon.texture = UiTheme.icon("icon_quest")
			_icon_color = UiTheme.GOLD
			_icon.pixel_size = 0.0034
		&"turn_in":
			_icon.texture = UiTheme.icon("ui_diamond")
			_icon_color = Color(0.62, 0.86, 1.0)
			_icon.pixel_size = 0.0028
		&"trainer":
			_icon.texture = UiTheme.emblem(npc.element())
			_icon_color = Color(UiTheme.element_light(npc.element()), 0.95)
			_icon.pixel_size = 0.00085
		&"merchant":
			_icon.texture = UiTheme.icon("icon_marker")
			_icon_color = Color(UiTheme.GOLD_HI, 0.75)
			_icon.pixel_size = 0.0024
	_icon.modulate = _icon_color
	_icon.visible = s != &"" and not npc.in_conversation()


## Current marker state (&"available", &"turn_in", &"trainer", &"merchant", &"").
func get_state() -> StringName:
	return state
