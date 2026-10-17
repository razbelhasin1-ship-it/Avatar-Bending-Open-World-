class_name HudAbilitySlot
extends Control
## One technique slot: icon, key/button prompt badge, clockwise cooldown sweep with the
## seconds left, "insufficient chi" dimming, a red flash + shake when a cast fails and a
## gold glint when the technique becomes ready. The signature slot is round and shows the
## focus gauge filling around it.
##
## Fed every frame with the player's slot info dictionary:
##   {id, name, icon (Texture2D or resource path), element, cooldown_ratio (1 = just used,
##    0 = ready), cooldown_left (s, optional), available (bool), cost (chi)}

var index := 0
var signature := false
var action: StringName = &"ability_1"
var info: Dictionary = {}
## Signature only: 0..1 focus fill.
var focus_ratio := 0.0
## Key/button badge under the slot (off when the slot is a touch button: src/ui/touch).
var show_prompt := true

var _icon: Texture2D
var _icon_key := ""
var _flash := 0.0
var _glint := 0.0
var _was_cooling := false
var _prompt: PromptGlyph
var _t := 0.0


func _init(p_index: int = 0, p_signature: bool = false) -> void:
	index = p_index
	signature = p_signature
	action = &"ability_special" if signature else StringName("ability_%d" % (index + 1))
	custom_minimum_size = Vector2(104, 104) if signature else Vector2(86, 86)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	if not show_prompt:
		return
	_prompt = PromptGlyph.for_action(action, 30)
	add_child(_prompt)
	_place_prompt()
	resized.connect(_place_prompt)


func _place_prompt() -> void:
	if _prompt:
		_prompt.size = _prompt.get_combined_minimum_size()
		_prompt.position = Vector2((size.x - _prompt.size.x) * 0.5, size.y - _prompt.size.y * 0.45)


## Updates the slot from the player's info dictionary.
func set_info(d: Dictionary) -> void:
	var cooling := float(d.get("cooldown_ratio", 0.0)) > 0.001
	if _was_cooling and not cooling and not d.is_empty():
		_glint = 1.0
	_was_cooling = cooling
	info = d
	var icon_v: Variant = d.get("icon", null)
	var key := str(icon_v)
	if key != _icon_key:
		_icon_key = key
		_icon = null
		if icon_v is Texture2D:
			_icon = icon_v
		elif icon_v is String or icon_v is StringName:
			_icon = UiTheme.texture(String(icon_v))
		if _icon == null and ElementDefs.is_valid(int(d.get("element", -1))):
			_icon = UiTheme.emblem(int(d.get("element", -1)))
	queue_redraw()


func is_empty() -> bool:
	return StringName(info.get("id", &"")) == &""


## Signature only: the not-yet-learned signature ({id, name, icon, element, level}; {} = none).
## An empty signature slot with this set draws the technique dimmed under a padlock with the
## level it opens at, so a new player sees what R will become.
var locked: Dictionary = {}
var _locked_icon: Texture2D


func set_locked(d: Dictionary) -> void:
	if d.hash() == locked.hash():
		return
	locked = d
	_locked_icon = null
	if not d.is_empty():
		var icon_v: Variant = d.get("icon", null)
		if icon_v is Texture2D:
			_locked_icon = icon_v
		elif icon_v is String or icon_v is StringName:
			_locked_icon = UiTheme.texture(String(icon_v))
	queue_redraw()


func is_locked() -> bool:
	return is_empty() and not locked.is_empty()


## Toast text for a press of a locked signature.
static func locked_hint(d: Dictionary) -> String:
	if d.is_empty():
		return "No signature technique yet"
	return "%s is locked  ·  learn it in Bending Skills (level %d)" % [String(d.get("name", "Signature")), int(d.get("level", 1))]


## Red flash + shake (failed cast: on cooldown, insufficient chi, ...).
func flash_fail() -> void:
	_flash = 1.0
	UiFx.shake(self, 6.0, 0.28)
	queue_redraw()


func pulse_used() -> void:
	UiFx.pop(self, 1.08, 0.16)


func _process(delta: float) -> void:
	_t += delta
	var dirty := false
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.0)
		dirty = true
	if _glint > 0.0:
		_glint = maxf(0.0, _glint - delta * 2.2)
		dirty = true
	if signature and focus_ratio >= 1.0:
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var c := r.get_center()
	var e := int(info.get("element", GameState.element))
	var light := UiTheme.element_light(e)
	var empty := is_empty()
	var cd := clampf(float(info.get("cooldown_ratio", 0.0)), 0.0, 1.0)
	var available := bool(info.get("available", true)) and cd <= 0.001
	var border := Color(UiTheme.GOLD, 0.55)
	if not empty and available:
		border = light
	border = border.lerp(UiTheme.DANGER, _flash)
	if signature:
		var rad := size.x * 0.5 - 4.0
		draw_circle(c, rad, Color(UiTheme.INK, 0.86), true, -1.0, true)
		var full := focus_ratio >= 1.0
		var glow := (0.5 + 0.5 * sin(_t * 5.0)) if full else 0.0
		draw_arc(c, rad, 0, TAU, 64, Color(UiTheme.GOLD, 0.35), 2.0, true)
		if focus_ratio > 0.0:
			draw_arc(c, rad, -PI * 0.5, -PI * 0.5 + TAU * clampf(focus_ratio, 0.0, 1.0), 64, UiTheme.GOLD_HI.lerp(Color.WHITE, glow * 0.4), 4.0, true)
		if full:
			draw_arc(c, rad + 5.0, 0, TAU, 64, Color(UiTheme.GOLD_HI, 0.3 + 0.3 * glow), 3.0, true)
		if _flash > 0.0:
			draw_arc(c, rad, 0, TAU, 64, Color(UiTheme.DANGER, _flash), 3.0, true)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiTheme.INK, 0.86)
		sb.border_color = border
		sb.set_border_width_all(2 if available and not empty else 1)
		sb.set_corner_radius_all(14)
		sb.anti_aliasing = true
		if empty:
			sb.bg_color = Color(UiTheme.INK, 0.45)
			sb.border_color = Color(UiTheme.PARCHMENT, 0.2)
		draw_style_box(sb, r)
	if empty:
		if signature and not locked.is_empty():
			_draw_locked(c)
		return
	# icon
	var isz := size.x * (0.6 if signature else 0.62)
	var icon_rect := Rect2(c - Vector2(isz, isz) * 0.5 - Vector2(0, 4), Vector2(isz, isz))
	var icol := UiTheme.PARCHMENT if available else Color(UiTheme.PARCHMENT, 0.38)
	if signature:
		icol = light if focus_ratio >= 1.0 else Color(light, 0.45)
	if _icon:
		draw_texture_rect(_icon, icon_rect, false, icol)
	# cooldown sweep (dark pie, clockwise from the top) + bright sweep edge
	if cd > 0.001:
		var pts := PackedVector2Array([c])
		var steps := 40
		var a0 := -PI * 0.5
		var span := TAU * cd
		var rad2 := size.length() * 0.55
		for i in steps + 1:
			var a := a0 + span * float(i) / steps
			pts.append(c + Vector2(cos(a), sin(a)) * rad2)
		var clip_r := r.grow(-2.0)
		var clipped := Geometry2D.intersect_polygons(pts, PackedVector2Array([clip_r.position, Vector2(clip_r.end.x, clip_r.position.y), clip_r.end, Vector2(clip_r.position.x, clip_r.end.y)]))
		for poly: PackedVector2Array in clipped:
			draw_colored_polygon(poly, Color(0.02, 0.015, 0.012, 0.72))
		var ea := a0 + span
		draw_line(c, c + Vector2(cos(ea), sin(ea)) * size.x * 0.48, Color(UiTheme.GOLD_HI, 0.8), 2.0, true)
		var left := float(info.get("cooldown_left", 0.0))
		if left > 0.05:
			var f := UiTheme.title_font(700)
			var txt := ("%.1f" % left) if left < 3.0 else str(ceili(left))
			var fs := 26 if not signature else 30
			var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string_outline(f, c + Vector2(-ts.x * 0.5, fs * 0.36 - 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.8))
			draw_string(f, c + Vector2(-ts.x * 0.5, fs * 0.36 - 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.PARCHMENT)
	elif not bool(info.get("available", true)):
		# insufficient chi marker
		var ci := UiTheme.icon("icon_chi")
		if ci:
			draw_texture_rect(ci, Rect2(Vector2(size.x - 26, 6), Vector2(20, 20)), false, Color(0.55, 0.8, 1.0, 0.9))
	if _glint > 0.0:
		var g := Color(UiTheme.GOLD_HI, _glint)
		if signature:
			draw_arc(c, size.x * 0.5 - 2.0 + (1.0 - _glint) * 8.0, 0, TAU, 48, g, 3.0, true)
		else:
			var gr := r.grow((1.0 - _glint) * 7.0)
			draw_rect(gr, g, false, 2.5)


## Locked signature: the technique's icon faint, a padlock over it and "LV n" underneath.
func _draw_locked(c: Vector2) -> void:
	var isz := size.x * 0.52
	if _locked_icon:
		draw_texture_rect(_locked_icon, Rect2(c - Vector2(isz, isz) * 0.5 - Vector2(0, 6), Vector2(isz, isz)), false,
				Color(UiTheme.PARCHMENT, 0.22))
	var lock := UiTheme.icon("icon_padlock")
	if lock:
		var lsz := size.x * 0.34
		draw_texture_rect(lock, Rect2(c - Vector2(lsz, lsz) * 0.5 - Vector2(0, 4), Vector2(lsz, lsz)), false,
				Color(UiTheme.GOLD_HI, 0.9).lerp(UiTheme.DANGER, _flash))
	var f := UiTheme.title_font(700)
	var txt := "LV %d" % int(locked.get("level", 1))
	var fs := 18
	var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var at := c + Vector2(-ts.x * 0.5, size.y * 0.28)
	draw_string_outline(f, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
	draw_string(f, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiTheme.PARCHMENT, 0.85))
