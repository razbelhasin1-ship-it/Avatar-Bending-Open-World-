class_name BrushStroke
extends ColorRect
## A procedural ink brush stroke (src/ui/shaders/brush_stroke.gdshader) filling this
## rect. `sweep()` animates it being painted left to right; `retract()` dries it away.
## Used for menu highlights, title underlines, banners and transitions.

const SHADER := preload("res://src/ui/shaders/brush_stroke.gdshader")

## Ink colour of the stroke.
var stroke_color := UiTheme.GOLD:
	set(v):
		stroke_color = v
		_mat.set_shader_parameter(&"tint", v)
## 0..1 painted length.
var progress := 1.0:
	set(v):
		progress = v
		_mat.set_shader_parameter(&"progress", v)

var _mat: ShaderMaterial
var _tween: Tween


func _init(p_color: Color = UiTheme.GOLD, p_seed: float = -1.0) -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	color = Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stroke_color = p_color
	set_param(&"seed", p_seed if p_seed >= 0.0 else randf() * 10.0)
	progress = 1.0


## Sets any shader parameter (thickness, head, tail, dryness, wobble, roughness, pooling, flip).
func set_param(param: StringName, value: Variant) -> BrushStroke:
	_mat.set_shader_parameter(param, value)
	return self


func get_param(param: StringName) -> Variant:
	return _mat.get_shader_parameter(param)


## Paints the stroke in over `time` seconds.
func sweep(time: float = 0.32, from: float = 0.0, to: float = 1.0, delay: float = 0.0) -> Tween:
	_kill()
	progress = from
	_tween = create_tween()
	_tween.tween_property(self, "progress", to, time).set_delay(delay).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	return _tween


## Withdraws the stroke (reverse sweep).
func retract(time: float = 0.18) -> Tween:
	_kill()
	_tween = create_tween()
	_tween.tween_property(self, "progress", 0.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	return _tween


func _kill() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
