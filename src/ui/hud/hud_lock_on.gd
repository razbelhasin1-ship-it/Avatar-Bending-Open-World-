class_name HudLockOn
extends Control
## Lock-on feedback: a name plate with the target's health at the top centre (under the
## compass) and slim rotating brackets around the target on screen. Reads the target's
## HealthComponent (child or `health` property) and its display name
## (`display_name` property, `get_display_name()`, or the node name).

var target: Node3D = null
var camera: Camera3D = null

var _panel: Control
var _name: Label
var _bar: HudBar
var _health: HealthComponent = null
var _t := 0.0
var _vis := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = Control.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -270
	_panel.offset_right = 270
	_panel.offset_top = 126
	_panel.offset_bottom = 186
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_name = UiTheme.make_label("", UiTheme.title_font(700, 4), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	_name.size = Vector2(540, 28)
	_name.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	_name.add_theme_constant_override(&"shadow_outline_size", 6)
	_panel.add_child(_name)
	_bar = HudBar.new(Color(0.55, 0.08, 0.06), Color(0.85, 0.22, 0.16))
	_bar.position = Vector2(40, 32)
	_bar.size = Vector2(460, 11)
	_panel.add_child(_bar)
	_panel.modulate.a = 0.0


func set_target(t: Node3D) -> void:
	if t == target:
		return
	target = t
	_health = find_health(t) if t else null
	if t:
		_name.text = display_name_of(t).to_upper()
		if _health:
			_bar.set_ratio(_health.ratio(), true)
		_bar.visible = _health != null


static func find_health(n: Node) -> HealthComponent:
	if n == null:
		return null
	var h: Variant = n.get("health")
	if h is HealthComponent:
		return h
	for c in n.get_children():
		if c is HealthComponent:
			return c
	return null


static func display_name_of(n: Node) -> String:
	if n.has_method("get_display_name"):
		return String(n.call("get_display_name"))
	var dn: Variant = n.get("display_name")
	if dn != null and String(dn) != "":
		return String(dn)
	if n.has_meta(&"display_name"):
		return String(n.get_meta(&"display_name"))
	return String(n.name).capitalize()


func _process(delta: float) -> void:
	_t += delta
	var alive := target != null and is_instance_valid(target) and target.is_inside_tree()
	if not alive and target != null:
		target = null
	_vis = move_toward(_vis, 1.0 if target else 0.0, delta * 6.0)
	_panel.modulate.a = _vis
	if target and _health:
		_bar.set_ratio(_health.ratio())
	queue_redraw()


func _draw() -> void:
	if target == null or _vis <= 0.01:
		return
	var cam := camera if camera else get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := target.global_position + Vector3.UP * 1.1
	if cam.is_position_behind(p):
		return
	var sp := cam.unproject_position(p)
	var dist := cam.global_position.distance_to(p)
	var s := clampf(900.0 / maxf(dist, 1.0), 26.0, 70.0)
	var col := Color(UiTheme.GOLD_HI, 0.9 * _vis)
	var rot := _t * 0.8
	for k in 4:
		var a := rot + k * PI * 0.5
		var dir := Vector2(cos(a), sin(a))
		var side := Vector2(-dir.y, dir.x)
		var corner := sp + (dir + side) * s * 0.55
		draw_line(corner, corner - dir * s * 0.32, col, 2.5, true)
		draw_line(corner, corner - side * s * 0.32, col, 2.5, true)
	draw_circle(sp, 3.0, col, true, -1.0, true)
