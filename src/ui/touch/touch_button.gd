class_name TouchButton
extends Control
## One round on-screen button of the touch overlay. It is drawn, not a GUI Button: the
## overlay routes every finger itself (per touch index), so buttons never steal focus
## and several can be held at once (Defend + Strike, stick + Jump ...).
##
## A technique button embeds the HUD's own `HudAbilitySlot` (icon, clockwise cooldown
## sweep with seconds, insufficient-chi marker, fail flash, ready glint), so on touch the
## buttons ARE the HUD ability slots (the HUD hides its bar).
##
##   var b := TouchButton.new(&"jump", &"jump", 58.0, "res://src/ui/touch/icons/touch_jump.svg")
##   overlay.add_child(b); b.set_center(Vector2(1800, 700))

const ICON_DIR := "res://src/ui/touch/icons/"

## Overlay id (strike, heavy, jump, dodge, defend, tech_0..3, signature, pause, lock,
## call, map, journal, interact, descend).
var id: StringName = &""
## InputMap action pressed while a finger holds the button.
var action: StringName = &""
## Radius in design px (already scaled by touch.button_scale).
var radius := 56.0
## Texture drawn in the disc (white SVG, tinted); null = none.
var icon: Texture2D = null
var icon_scale := 0.6
## Short caption under the icon (rare; most buttons are icon-only).
var caption := ""
## Accent (element colour) for the ring and the press glow.
var accent := UiTheme.GOLD
## Base alpha of the idle button (touch.opacity); pressed buttons go fully opaque.
var opacity := 0.7
## Small disc style for the top bar (no thick ring).
var flat := false
## Highlighted state (lock-on active, sprinting ...).
var active := false
## Embedded HUD slot for technique / signature buttons.
var slot: HudAbilitySlot = null
## True while at least one finger holds the button.
var pressed := false
## Seconds the current press has lasted (overlay feeds it; drives the hold glow).
var hold_time := 0.0

var _flash := 0.0
var _pop := 0.0


func _init(p_id: StringName = &"", p_action: StringName = &"", p_radius: float = 56.0, icon_path: String = "") -> void:
	id = p_id
	action = p_action
	radius = p_radius
	name = "Btn_" + String(p_id)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not icon_path.is_empty():
		icon = UiTheme.texture(icon_path)
	_resize()


## Builds the embedded HUD ability slot (techniques 0..3, signature 4).
func make_ability_slot(index: int) -> HudAbilitySlot:
	slot = HudAbilitySlot.new(index, index == 4)
	slot.show_prompt = false
	slot.name = "Slot"
	add_child(slot)
	_place_slot()
	return slot


func set_radius(r: float) -> void:
	radius = r
	_resize()


func set_center(c: Vector2) -> void:
	position = c - Vector2(radius, radius)


func get_center() -> Vector2:
	return position + Vector2(radius, radius)


## Hit test in the parent's coordinates (generous: fingers are not pixels).
func hit_distance(p: Vector2) -> float:
	return p.distance_to(get_center())


func hit(p: Vector2, slack: float = 1.18) -> bool:
	return is_visible_in_tree() and hit_distance(p) <= radius * slack


func set_pressed(on: bool) -> void:
	if on == pressed:
		return
	pressed = on
	if on:
		_pop = 1.0
		hold_time = 0.0
	queue_redraw()


## Red flash (failed cast while the slot has no own flash, e.g. not enough chi on Heavy).
func flash() -> void:
	_flash = 1.0
	queue_redraw()


func _resize() -> void:
	custom_minimum_size = Vector2(radius, radius) * 2.0
	size = custom_minimum_size
	pivot_offset = size * 0.5
	_place_slot()
	queue_redraw()


func _place_slot() -> void:
	if slot == null:
		return
	# The slot draws a rounded square (techniques) or a disc (signature) inside our rect.
	var inset := radius * (0.14 if slot.signature else 0.2)
	slot.position = Vector2(inset, inset)
	slot.size = size - Vector2(inset, inset) * 2.0
	slot.custom_minimum_size = slot.size


func _process(delta: float) -> void:
	var dirty := false
	if pressed:
		hold_time += delta
		dirty = true
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.0)
		dirty = true
	if _pop > 0.0:
		_pop = maxf(0.0, _pop - delta * 6.0)
		dirty = true
	var want := 1.0 if pressed else opacity
	if not is_equal_approx(modulate.a, want):
		modulate.a = move_toward(modulate.a, want, delta * 8.0)
	if slot:
		slot.scale = Vector2.ONE * (0.93 if pressed else 1.0)
		slot.pivot_offset = slot.size * 0.5
	if dirty:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := radius * (0.94 if pressed else 1.0)
	var glow := 0.0
	if pressed:
		glow = 0.55 + 0.25 * sin(hold_time * 9.0) if hold_time > 0.25 else 0.8
	if slot != null:
		# The HUD slot paints the face; we add the press halo and the finger target ring.
		if pressed or _pop > 0.0:
			draw_arc(c, radius - 2.0, 0.0, TAU, 56, Color(accent, 0.55 * maxf(glow, _pop)), 4.0, true)
		return
	# Soft drop shadow + dark rim so the disc reads on snow, sand and sky alike.
	draw_circle(c + Vector2(0, r * 0.05 + 1.5), r + 1.0, Color(0, 0, 0, 0.22), true, -1.0, true)
	var fill := Color(UiTheme.INK, 0.86)
	if pressed:
		fill = Color(UiTheme.INK_3, 0.92).lerp(Color(accent.darkened(0.55), 0.92), 0.4)
	draw_circle(c, r, fill, true, -1.0, true)
	# Lacquer depth: a slightly lighter inner field and a sheen on the upper half.
	draw_circle(c, r * 0.8, Color(UiTheme.INK_2, 0.55), true, -1.0, true)
	draw_arc(c, r * 0.8, PI * 1.12, PI * 1.88, 32, Color(1, 1, 1, 0.06), r * 0.2, true)
	draw_arc(c, r + 0.5, 0.0, TAU, 64, Color(0, 0, 0, 0.4), 2.0, true)
	var ring := Color(UiTheme.GOLD, 0.82)
	if active:
		ring = accent
	ring = ring.lerp(accent.lightened(0.2), glow)
	ring = ring.lerp(UiTheme.DANGER, _flash)
	draw_arc(c, r - 1.5, 0.0, TAU, 64, ring, 2.5 if flat else 3.2, true)
	if not flat:
		draw_arc(c, r * 0.86, 0.0, TAU, 64, Color(UiTheme.GOLD, 0.22), 1.3, true)
	if pressed or _pop > 0.0:
		draw_arc(c, r + 5.0 + 6.0 * _pop, 0.0, TAU, 64, Color(accent, 0.5 * maxf(glow, _pop)), 3.0, true)
	if icon:
		var isz := r * 2.0 * icon_scale
		var ic := Color(UiTheme.PARCHMENT)
		if active:
			ic = accent.lightened(0.25)
		if pressed:
			ic = Color.WHITE
		var off := Vector2(0, -r * 0.08) if not caption.is_empty() else Vector2.ZERO
		draw_texture_rect(icon, Rect2(c - Vector2(isz, isz) * 0.5 + off, Vector2(isz, isz)), false, ic)
	if not caption.is_empty():
		var f := UiTheme.title_font(700, 2)
		var fs := int(clampf(r * 0.24, 13.0, 24.0))
		var ts := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := c + Vector2(-ts.x * 0.5, r * 0.62)
		draw_string_outline(f, pos, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.6))
		draw_string(f, pos, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiTheme.PARCHMENT, 0.9))
