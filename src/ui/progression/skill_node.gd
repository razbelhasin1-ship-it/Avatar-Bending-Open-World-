class_name SkillNode
extends Button
## One technique on the skill tree: a lacquer medallion with the technique's icon and its
## name underneath. The ring tells the state at a glance - learned (element colour, filled),
## ready to learn (pulsing gold), locked (dim, a lock or a master's seal), equipped (slot
## number badge), signature (larger, double ring). Focus draws a gold halo.
##
## Desktop: drag a learned technique onto a loadout slot (Control drag & drop).
## Touch / mouse / controller: press = the page decides (learn, arm for equipping, explain).

signal drag_started(id: StringName)

const SIZE := 90.0
const SIZE_SIGNATURE := 106.0
const SIZE_SMALL := 64.0

var id: StringName = &""
var def: AbilityDef = null
var element := ElementDefs.Element.NONE
## &"learned" | &"available" | &"locked"
var state: StringName = &"locked"
## Technique slot it sits in (-1 none).
var slot_index := -1
## Signature node (larger, double ring).
var signature := false
## Foundations (core kit): small, always learned, not draggable.
var foundation := false
## A master teaches it (seal instead of a lock).
var trainer := false
## Armed for equipping (glows).
var armed := false

var _icon: Texture2D
var _t := 0.0
var _flash := 0.0
var _bloom := 0.0


func _init(p_def: AbilityDef = null, p_foundation: bool = false) -> void:
	def = p_def
	foundation = p_foundation
	if def:
		id = def.id
		element = def.element
		signature = def.slot == AbilityDef.Slot.SIGNATURE
	flat = true
	text = ""
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	var w := medallion_size() + 56.0
	custom_minimum_size = Vector2(maxf(w, 144.0), medallion_size() + (46.0 if not foundation else 38.0))
	size = custom_minimum_size


func _ready() -> void:
	var empty := StyleBoxEmpty.new()
	for s: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(s, empty)
	if def:
		_icon = UiTheme.texture(def.icon) if def.icon != "" else null
		if _icon == null:
			_icon = UiTheme.emblem(element)
		tooltip_text = ""
	UiFx.wire(self)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func medallion_size() -> float:
	if foundation:
		return SIZE_SMALL
	return SIZE_SIGNATURE if signature else SIZE


## Centre of the medallion in this control's local space (connectors attach here).
func medallion_center() -> Vector2:
	return Vector2(size.x * 0.5, medallion_size() * 0.5 + 2.0)


func set_state(p_state: StringName, p_slot: int, p_trainer: bool) -> void:
	var learned_now := p_state == &"learned" and state != &"learned" and is_inside_tree() and state != &""
	state = p_state
	slot_index = p_slot
	trainer = p_trainer
	if learned_now:
		_bloom = 1.0
	queue_redraw()


## Red flash (refused action).
func flash_fail() -> void:
	_flash = 1.0
	UiFx.shake(self, 7.0, 0.3)


## Ink bloom (just learned).
func bloom() -> void:
	_bloom = 1.0
	UiFx.pop(self, 1.12, 0.3)


func _process(delta: float) -> void:
	_t += delta
	var dirty := state == &"available" or armed
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.5)
		dirty = true
	if _bloom > 0.0:
		_bloom = maxf(0.0, _bloom - delta * 1.1)
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	var ms := medallion_size()
	var c := medallion_center()
	var r := ms * 0.5 - 3.0
	var light := UiTheme.element_light(element)
	var col_e := UiTheme.element_color(element)
	var hot := has_focus() or is_hovered()
	var learned := state == &"learned"
	var avail := state == &"available"
	# shadow + disc
	draw_circle(c + Vector2(0, 3), r + 2.0, Color(0, 0, 0, 0.35), true, -1.0, true)
	var fill := Color(UiTheme.INK, 0.94)
	if learned:
		fill = Color(UiTheme.INK_2, 1.0).lerp(col_e.darkened(0.45), 0.55)
	draw_circle(c, r, fill, true, -1.0, true)
	if learned:
		# soft inner glow toward the top
		draw_circle(c - Vector2(0, r * 0.25), r * 0.62, Color(light, 0.12), true, -1.0, true)
	# ring
	var ring := Color(UiTheme.PARCHMENT, 0.22)
	var width := 2.0
	if learned:
		ring = light
		width = 3.0
	elif avail:
		var pulse := 0.55 + 0.45 * sin(_t * 4.2)
		ring = UiTheme.GOLD_HI.lerp(UiTheme.GOLD, 1.0 - pulse)
		width = 3.0
		draw_arc(c, r + 5.0 + pulse * 3.0, 0, TAU, 64, Color(UiTheme.GOLD_HI, 0.18 + 0.22 * pulse), 3.0, true)
	ring = ring.lerp(UiTheme.DANGER, _flash)
	draw_arc(c, r, 0, TAU, 72, ring, width, true)
	if signature:
		draw_arc(c, r - 7.0, 0, TAU, 72, Color(ring, ring.a * 0.6), 1.5, true)
		for i in 8:
			var a := TAU * i / 8.0 + _t * 0.15
			var p := c + Vector2(cos(a), sin(a)) * (r + 0.5)
			draw_circle(p, 2.6, ring, true, -1.0, true)
	# icon
	if _icon:
		var isz := ms * (0.56 if not signature else 0.52)
		var ir := Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz))
		var icol := UiTheme.PARCHMENT
		if learned:
			icol = Color("fff6e2")
		elif avail:
			icol = UiTheme.GOLD_HI
		else:
			icol = Color(UiTheme.PARCHMENT, 0.3)
		draw_texture_rect(_icon, ir, false, icol)
	# lock / master seal
	if state == &"locked" and not foundation:
		var li := UiTheme.icon("icon_unlock" if trainer else "icon_padlock")
		var lr := Rect2(c + Vector2(r * 0.42, r * 0.38), Vector2(26, 26))
		draw_circle(lr.get_center(), 16.0, Color(UiTheme.INK, 0.95), true, -1.0, true)
		draw_arc(lr.get_center(), 16.0, 0, TAU, 32, Color(UiTheme.SEAL if trainer else UiTheme.PARCHMENT, 0.7), 1.5, true)
		if li:
			draw_texture_rect(li, lr.grow(-3.0), false, Color(UiTheme.SEAL.lightened(0.25) if trainer else UiTheme.PARCHMENT_DIM, 0.95))
	# equipped badge
	if slot_index >= 0:
		var bc := c + Vector2(r * 0.72, -r * 0.72)
		draw_circle(bc, 15.0, UiTheme.GOLD, true, -1.0, true)
		draw_arc(bc, 15.0, 0, TAU, 32, UiTheme.INK, 1.5, true)
		var f := UiTheme.title_font(800)
		var txt := str(slot_index + 1)
		var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		draw_string(f, bc + Vector2(-ts.x * 0.5, 7.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTheme.INK)
	# armed / focus halo
	if armed:
		var k := 0.5 + 0.5 * sin(_t * 6.0)
		draw_arc(c, r + 9.0, 0, TAU, 72, Color(UiTheme.GOLD_HI, 0.55 + 0.4 * k), 3.0, true)
	elif hot:
		draw_arc(c, r + 7.0, 0, TAU, 72, Color(UiTheme.GOLD_HI, 0.9), 2.5, true)
		for i in 4:
			var a := TAU * i / 4.0 + PI * 0.25
			var p0 := c + Vector2(cos(a), sin(a)) * (r + 11.0)
			var p1 := c + Vector2(cos(a), sin(a)) * (r + 19.0)
			draw_line(p0, p1, UiTheme.GOLD_HI, 2.5, true)
	if _bloom > 0.0:
		var b := 1.0 - _bloom
		draw_arc(c, r + 6.0 + b * 40.0, 0, TAU, 72, Color(light, _bloom * 0.9), 4.0 * _bloom + 1.0, true)
		draw_circle(c, r * (0.4 + b), Color(light, _bloom * 0.25), true, -1.0, true)
	# name (one line, or two when it does not fit)
	if def:
		var font := UiTheme.title_font(700 if hot else 600, 1)
		var fs := 16 if foundation else 17
		var ncol := UiTheme.PARCHMENT if learned else (UiTheme.GOLD_HI if avail else Color(UiTheme.PARCHMENT, 0.45))
		if hot:
			ncol = Color("fff6e2")
		var y := ms + fs + 6.0
		for ln in name_lines(font, fs, size.x + 16.0):
			var tw := font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pos := Vector2((size.x - tw) * 0.5, y)
			draw_string_outline(font, pos, ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(UiTheme.INK, 0.8))
			draw_string(font, pos, ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ncol)
			y += fs + 2.0


## The display name split into at most two lines that fit `maxw` at `fs`.
func name_lines(font: Font, fs: int, maxw: float) -> PackedStringArray:
	var t := def.display_name.to_upper() if def else ""
	if font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= maxw:
		return PackedStringArray([t])
	var words := t.replace(" / ", " /").split(" ")
	var best := PackedStringArray([t])
	var best_w := INF
	for i in range(1, words.size()):
		var a := " ".join(words.slice(0, i)).replace(" /", " / ")
		var b := " ".join(words.slice(i)).replace(" /", " / ")
		var w := maxf(font.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, font.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if w < best_w:
			best_w = w
			best = PackedStringArray([a, b])
	return best


# --- drag & drop (desktop) ------------------------------------------------------------------------

func _get_drag_data(_at: Vector2) -> Variant:
	if def == null or foundation or state != &"learned" or def.slot != AbilityDef.Slot.TECHNIQUE:
		return null
	if UiInput.device == &"touch":
		return null
	var pv := TextureRect.new()
	pv.texture = _icon
	pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pv.size = Vector2(70, 70)
	pv.position = -pv.size * 0.5
	pv.modulate = UiTheme.element_light(element)
	var holder := Control.new()
	holder.add_child(pv)
	set_drag_preview(holder)
	drag_started.emit(id)
	return {"kind": &"technique", "id": id}
