class_name HudBar
extends ColorRect
## Brushed resource bar (src/ui/shaders/hud_bar.gdshader) with a delayed "recent loss"
## trail: losses leave a pale segment that drains after `trail_delay`; gains fill at once.

const SHADER := preload("res://src/ui/shaders/hud_bar.gdshader")

var ratio := 1.0
var trail := 1.0
var trail_delay := 0.55
var _since := 0.0
var _flash := 0.0
var _mat: ShaderMaterial


func _init(fill_a: Color = Color(0.8, 0.2, 0.14), fill_b: Color = Color(0.98, 0.42, 0.26)) -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"fill_a", fill_a)
	_mat.set_shader_parameter(&"fill_b", fill_b)
	_mat.set_shader_parameter(&"trail_color", Color(fill_b.lightened(0.35), 0.6))
	_mat.set_shader_parameter(&"seed", randf() * 10.0)
	material = _mat
	color = Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_colors(fill_a: Color, fill_b: Color) -> void:
	_mat.set_shader_parameter(&"fill_a", fill_a)
	_mat.set_shader_parameter(&"fill_b", fill_b)
	_mat.set_shader_parameter(&"trail_color", Color(fill_b.lightened(0.35), 0.6))


## Sets the fill (0..1). Losses leave a trail; `instant` snaps the trail too.
func set_ratio(r: float, instant: bool = false) -> void:
	r = clampf(r, 0.0, 1.0)
	if r < ratio and not instant:
		_since = 0.0
		_flash = 1.0
	else:
		trail = maxf(trail, r)
	ratio = r
	if instant or trail < ratio:
		trail = ratio
	_push()


func set_pulse(amount: float) -> void:
	_mat.set_shader_parameter(&"pulse", amount)


func _process(delta: float) -> void:
	var dirty := false
	if trail > ratio:
		_since += delta
		if _since > trail_delay:
			trail = maxf(ratio, trail - delta * 0.6)
			dirty = true
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		dirty = true
	if dirty:
		_push()


func _push() -> void:
	_mat.set_shader_parameter(&"value", ratio)
	_mat.set_shader_parameter(&"trail", trail)
	_mat.set_shader_parameter(&"flash", _flash)
