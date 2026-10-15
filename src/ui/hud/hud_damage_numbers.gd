class_name HudDamageNumbers
extends Control
## Floating damage numbers over targets (Events.hit_landed), pooled labels that rise and
## fade; heavy hits are larger and gold, element-tinted otherwise. Only shown when
## Settings gameplay.damage_numbers is on.

const POOL := 24

var camera: Camera3D = null
var _pool: Array[Label] = []
var _next := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in POOL:
		var l := UiTheme.make_label("", UiTheme.title_font(800, 1), 30, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
		l.size = Vector2(160, 44)
		l.add_theme_color_override(&"font_outline_color", Color(0.05, 0.03, 0.02, 0.9))
		l.add_theme_constant_override(&"outline_size", 8)
		l.visible = false
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		_pool.append(l)


func enabled() -> bool:
	return bool(Settings.get_value("gameplay", "damage_numbers", true))


## Spawns a number at a world position. Returns the label (or null when hidden/off).
func spawn(world_pos: Vector3, amount: float, heavy: bool = false, element: int = -1, heal: bool = false) -> Label:
	if not enabled() or amount <= 0.0:
		return null
	var cam := camera if camera else get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(world_pos):
		return null
	var sp := cam.unproject_position(world_pos)
	var l := _pool[_next]
	_next = (_next + 1) % POOL
	l.text = ("+%d" if heal else "%d") % roundi(amount)
	var col := UiTheme.PARCHMENT
	if heal:
		col = UiTheme.SUCCESS
	elif heavy:
		col = UiTheme.GOLD_HI
	elif ElementDefs.is_valid(element):
		col = UiTheme.element_light(element).lerp(UiTheme.PARCHMENT, 0.35)
	l.add_theme_color_override(&"font_color", col)
	l.add_theme_font_size_override(&"font_size", 42 if heavy else 30)
	l.visible = true
	l.modulate.a = 1.0
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2.ONE * (1.35 if heavy else 1.1)
	var jitter := Vector2(randf_range(-26, 26), randf_range(-10, 10))
	l.position = sp - l.size * 0.5 + jitter
	var t := l.create_tween().set_parallel(true)
	t.tween_property(l, "position:y", l.position.y - 70.0, 0.9).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	t.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.6)
	t.chain().tween_callback(func() -> void: l.visible = false)
	return l


func on_hit_landed(hit: HitInfo, target: Node, result: int) -> void:
	if hit == null or not (target is Node3D):
		return
	if result != Combat.Result.HIT and result != Combat.Result.KILLED:
		return
	if target.is_in_group(&"player"):
		return
	var pos := (target as Node3D).global_position + Vector3.UP * 1.9
	spawn(pos, hit.damage, hit.is_heavy, hit.element)


func active_count() -> int:
	var n := 0
	for l in _pool:
		if l.visible:
			n += 1
	return n
