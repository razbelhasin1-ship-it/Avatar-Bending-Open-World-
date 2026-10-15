class_name LoadingOverlay
extends CanvasLayer
## Loading screen with rotating tips, drawn above the Router fade (layer 125): ink
## background, an ensō brush circle that paints itself around the element emblem as
## progress advances, a status line and a tip that changes every few seconds.
##
##   Router.hold_fade()
##   var lo := LoadingOverlay.open(get_tree(), "Entering the Northern Water Tribe")
##   lo.set_progress(0.4)            # optional (indeterminate spin otherwise)
##   ... await world streaming ...
##   lo.close(); Router.release_fade()

const TIPS := [
	"Tap your defense just before an attack lands to parry — it builds Focus for your signature technique.",
	"Light strikes are free. Techniques, heavy strikes and holding a defense spend chi.",
	"Chi recovers quickly when you stop bending for a moment.",
	"Waterbenders draw from nearby water. Snow and ice always count as a source.",
	"Earthbenders shrug off knockback: let heavy hits land and answer with a boulder.",
	"Airbenders can jump twice and glide — hold jump while falling.",
	"Firebenders' dash cancels into strikes. Keep the pressure on.",
	"Lock on to frame your foe; abilities aim at your target automatically.",
	"Call your companion if it falls behind. Mount up to travel faster.",
	"Discovering places grants experience and reveals them on your map.",
]

var progress := -1.0
var element := ElementDefs.Element.NONE
var root: Control

var _status: Label
var _tip: Label
var _ring: Control
var _tip_i := 0
var _tip_t := 0.0
var _t := 0.0
var _shown := 0.0


## Creates and shows an overlay under the tree root.
static func open(tree: SceneTree, status: String = "Loading", p_element: int = -2) -> LoadingOverlay:
	var lo := LoadingOverlay.new()
	lo.element = GameState.element if p_element == -2 else p_element
	tree.root.add_child(lo)
	lo.set_status(status)
	return lo


func _ready() -> void:
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.028, 0.024)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var grain := TextureRect.new()
	grain.texture = UiTheme.grain_texture()
	grain.stretch_mode = TextureRect.STRETCH_TILE
	grain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grain.modulate = Color(1, 1, 1, 0.05)
	root.add_child(grain)
	_ring = Control.new()
	_ring.anchor_left = 0.5
	_ring.anchor_right = 0.5
	_ring.anchor_top = 0.5
	_ring.anchor_bottom = 0.5
	_ring.offset_left = -150
	_ring.offset_right = 150
	_ring.offset_top = -230
	_ring.offset_bottom = 70
	_ring.draw.connect(_draw_ring)
	root.add_child(_ring)
	_status = UiTheme.make_label("", UiTheme.title_font(600, 8), UiTheme.SIZE_SMALL + 2, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	_status.anchor_left = 0.5
	_status.anchor_right = 0.5
	_status.anchor_top = 0.5
	_status.anchor_bottom = 0.5
	_status.offset_left = -700
	_status.offset_right = 700
	_status.offset_top = 110
	_status.offset_bottom = 150
	root.add_child(_status)
	_tip = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_BODY - 2, UiTheme.PARCHMENT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.anchor_left = 0.5
	_tip.anchor_right = 0.5
	_tip.anchor_top = 1.0
	_tip.anchor_bottom = 1.0
	_tip.offset_left = -620
	_tip.offset_right = 620
	_tip.offset_top = -190
	_tip.offset_bottom = -90
	root.add_child(_tip)
	_tip_i = randi() % TIPS.size()
	_show_tip()
	UiFx.fade_in(root, 0.25)


func set_status(text: String) -> void:
	if _status:
		_status.text = text.to_upper()


## 0..1, or negative for an indeterminate spinner.
func set_progress(r: float) -> void:
	progress = r


func current_tip() -> String:
	return _tip.text.trim_prefix("TIP  ·  ") if _tip else ""


func _show_tip() -> void:
	_tip.text = "TIP  ·  " + String(TIPS[_tip_i % TIPS.size()])
	UiFx.fade_in(_tip, 0.4)


func _process(delta: float) -> void:
	_t += delta
	_tip_t += delta
	if _tip_t > 7.0:
		_tip_t = 0.0
		_tip_i += 1
		_show_tip()
	var target := progress if progress >= 0.0 else fposmod(_t * 0.35, 1.0)
	_shown = target if progress < 0.0 else move_toward(_shown, target, delta * 1.5)
	_ring.queue_redraw()


func _draw_ring() -> void:
	var c := _ring.size * 0.5
	var rad := 120.0
	var light := UiTheme.element_light(element)
	var em := UiTheme.emblem(element)
	if em:
		_ring.draw_texture_rect(em, Rect2(c - Vector2(66, 66), Vector2(132, 132)), false, Color(light, 0.85))
	# ensō: a brush circle whose width swells and thins, painted up to the progress
	var start := -PI * 0.62 + (_t * 0.6 if progress < 0.0 else 0.0)
	var span := TAU * 0.93 * (_shown if progress >= 0.0 else 0.75)
	var steps := 90
	for i in steps:
		var a0 := start + span * float(i) / steps
		var a1 := start + span * float(i + 1) / steps
		var k := float(i) / steps
		var w := lerpf(14.0, 3.0, k) * (1.0 + 0.15 * sin(k * 17.0))
		var col := Color(UiTheme.PARCHMENT, 0.9 - k * 0.35)
		_ring.draw_line(c + Vector2(cos(a0), sin(a0)) * rad, c + Vector2(cos(a1), sin(a1)) * rad, col, w, true)
	if progress >= 0.0:
		var f := UiTheme.title_font(600)
		var t := "%d%%" % roundi(_shown * 100.0)
		var ts := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		_ring.draw_string(f, c + Vector2(-ts.x * 0.5, rad + 46), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTheme.GOLD)


func close() -> void:
	var t := root.create_tween()
	t.tween_property(root, "modulate:a", 0.0, 0.3)
	t.tween_callback(queue_free)
