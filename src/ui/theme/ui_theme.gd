class_name UiTheme
extends RefCounted
## Shared look of every menu and HUD: palette, fonts, sizes and the Godot `Theme`
## built in code (no .tres), so all UI scales from the 1920x1080 design base through
## the project's canvas_items stretch (720p .. 4K).
##
##   var root := Control.new()
##   root.theme = UiTheme.get_theme()        # once per UI root
##   label.theme_type_variation = &"TitleLabel"
##   UiTheme.title_font(700)                 # Cinzel at a given weight (cached)
##
## Type variations: TitleLabel, HeadingLabel, SubheadingLabel, MutedLabel, SmallLabel,
## BrushLabel, GhostButton, PrimaryButton, DangerButton, InkPanel, CardPanel, ToastPanel,
## RowPanel. Colors are design constants; element accents come from ElementDefs.

# --- Palette -------------------------------------------------------------------------------
const INK := Color("1b1512")
const INK_2 := Color("241c17")
const INK_3 := Color("33281f")
const INK_LINE := Color("4a3b2e")
const PARCHMENT := Color("efe3c8")
const PARCHMENT_DIM := Color("cbbd9f")
const PARCHMENT_MUTED := Color(0.937, 0.890, 0.784, 0.62)
const GOLD := Color("e7b552")
const GOLD_HI := Color("f7d993")
const GOLD_DEEP := Color("9c742e")
const SEAL := Color("b23a2c")
const DANGER := Color("de5a41")
const SUCCESS := Color("9cc46b")
const SHADOW := Color(0.0, 0.0, 0.0, 0.55)
## Translucent lacquer used behind HUD widgets and panels over 3D scenes.
const VEIL := Color(0.075, 0.058, 0.048, 0.86)

# --- Type scale (pixels at the 1080p design base) ---------------------------------------------
const SIZE_HERO := 168
const SIZE_H1 := 64
const SIZE_H2 := 44
const SIZE_H3 := 34
const SIZE_BODY := 26
const SIZE_SMALL := 22
const SIZE_TINY := 19
## Minimum touch target (px at 1080p) for tappable controls.
const TOUCH_TARGET := 88

const FONT_TITLE := "res://assets/fonts/Cinzel-Variable.ttf"
const FONT_BODY := "res://assets/fonts/Marcellus-Regular.ttf"
const FONT_BRUSH := "res://assets/fonts/MaShanZheng-Regular.ttf"
const FONT_BRUSH_ALT := "res://assets/fonts/ZhiMangXing-Regular.ttf"

static var _theme: Theme = null
static var _fonts: Dictionary = {}
static var _grain: Texture2D = null
static var _textures: Dictionary = {}


# --- Fonts ---------------------------------------------------------------------------------

## Cinzel (variable, wght 400..900) with optional extra letter spacing. Cached.
static func title_font(weight: int = 600, tracking: int = 0) -> Font:
	var key := "title_%d_%d" % [weight, tracking]
	if _fonts.has(key):
		return _fonts[key]
	var fv := FontVariation.new()
	fv.base_font = load(FONT_TITLE) as Font
	var ts := TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): clampi(weight, 400, 900)}
	fv.spacing_glyph = tracking
	_fonts[key] = fv
	return fv


## Marcellus (body text), optional tracking.
static func body_font(tracking: int = 0) -> Font:
	var key := "body_%d" % tracking
	if _fonts.has(key):
		return _fonts[key]
	var f: Font = load(FONT_BODY) as Font
	if tracking != 0:
		var fv := FontVariation.new()
		fv.base_font = f
		fv.spacing_glyph = tracking
		f = fv
	_fonts[key] = f
	return f


## Ma Shan Zheng brush calligraphy (CJK glyphs). `alt` selects Zhi Mang Xing (wilder strokes).
static func brush_font(alt: bool = false) -> Font:
	var key := "brush_%s" % alt
	if not _fonts.has(key):
		_fonts[key] = load(FONT_BRUSH_ALT if alt else FONT_BRUSH) as Font
	return _fonts[key]


# --- Colors ----------------------------------------------------------------------------------

static func element_color(element: int) -> Color:
	return ElementDefs.color_of(element) if ElementDefs.is_valid(element) else GOLD


## Element accent lifted for text/lines on dark lacquer (water blue and earth green are dark).
static func element_light(element: int) -> Color:
	if not ElementDefs.is_valid(element):
		return GOLD_HI
	var c := ElementDefs.color_of(element)
	var lift := 0.0
	match element:
		ElementDefs.Element.WATER: lift = 0.38
		ElementDefs.Element.EARTH: lift = 0.28
		ElementDefs.Element.FIRE: lift = 0.18
		_: lift = 0.08
	return c.lightened(lift)


static func element_secondary(element: int) -> Color:
	var d := ElementDefs.get_data(element)
	return d.get("color_secondary", GOLD) if not d.is_empty() else GOLD


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


# --- Textures --------------------------------------------------------------------------------

## Element emblem (white SVG, tint with modulate). Null for NONE. Cached.
static func emblem(element: int) -> Texture2D:
	if not ElementDefs.is_valid(element):
		return null
	return texture(ElementDefs.emblem_path(element))


## UI icon by base name, e.g. icon("icon_health"), icon("ability_blast"). Null if missing.
static func icon(icon_name: String) -> Texture2D:
	return texture("res://assets/ui/%s.svg" % icon_name)


## Loads and KEEPS a texture alive. Textures drawn with CanvasItem.draw_texture*() must
## outlive the draw call (the command buffer only stores the RID; a freed resource
## renders as a white square), so every UI texture goes through this cache.
static func texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var t: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_textures[path] = t
	return t


## Tileable paper/lacquer grain (generated once, 256x256, greyscale around 1.0).
static func grain_texture() -> Texture2D:
	if _grain:
		return _grain
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	noise.frequency = 0.11
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.55
	noise.seed = 17
	var img := noise.get_seamless_image(256, 256)
	img.convert(Image.FORMAT_RGBA8)
	_grain = ImageTexture.create_from_image(img)
	return _grain


# --- Theme -------------------------------------------------------------------------------------

## The shared Theme (built once). Assign to every UI root Control.
static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = SIZE_BODY
	_labels(t)
	_buttons(t)
	_panels(t)
	_ranges(t)
	_containers(t)
	_text_inputs(t)
	_popups(t)
	_theme = t
	return t


static func _labels(t: Theme) -> void:
	t.set_color(&"font_color", &"Label", PARCHMENT)
	t.set_color(&"font_shadow_color", &"Label", Color(0, 0, 0, 0.0))
	t.set_constant(&"line_spacing", &"Label", 4)
	_variation(t, &"TitleLabel", &"Label")
	t.set_font(&"font", &"TitleLabel", title_font(700, 6))
	t.set_font_size(&"font_size", &"TitleLabel", SIZE_H1)
	t.set_color(&"font_color", &"TitleLabel", PARCHMENT)
	_variation(t, &"HeadingLabel", &"Label")
	t.set_font(&"font", &"HeadingLabel", title_font(600, 3))
	t.set_font_size(&"font_size", &"HeadingLabel", SIZE_H2)
	t.set_color(&"font_color", &"HeadingLabel", GOLD)
	_variation(t, &"SubheadingLabel", &"Label")
	t.set_font(&"font", &"SubheadingLabel", title_font(600, 2))
	t.set_font_size(&"font_size", &"SubheadingLabel", SIZE_H3 - 4)
	t.set_color(&"font_color", &"SubheadingLabel", GOLD)
	_variation(t, &"MutedLabel", &"Label")
	t.set_color(&"font_color", &"MutedLabel", PARCHMENT_MUTED)
	t.set_font_size(&"font_size", &"MutedLabel", SIZE_SMALL)
	_variation(t, &"SmallLabel", &"Label")
	t.set_font_size(&"font_size", &"SmallLabel", SIZE_SMALL)
	_variation(t, &"BrushLabel", &"Label")
	t.set_font(&"font", &"BrushLabel", brush_font())
	t.set_font_size(&"font_size", &"BrushLabel", 120)
	t.set_color(&"font_color", &"BrushLabel", PARCHMENT)
	# RichTextLabel (dialogue, descriptions)
	t.set_font(&"normal_font", &"RichTextLabel", body_font())
	t.set_font(&"bold_font", &"RichTextLabel", title_font(700))
	t.set_font(&"italics_font", &"RichTextLabel", body_font())
	t.set_font_size(&"normal_font_size", &"RichTextLabel", SIZE_BODY)
	t.set_font_size(&"bold_font_size", &"RichTextLabel", SIZE_BODY)
	t.set_color(&"default_color", &"RichTextLabel", PARCHMENT)
	t.set_constant(&"line_separation", &"RichTextLabel", 6)


static func _buttons(t: Theme) -> void:
	var normal := UiFrameStyle.make(Color(INK_2, 0.78), Color(GOLD, 0.35), 1.5)
	var hover := UiFrameStyle.make(Color(INK_3, 0.92), Color(GOLD, 0.75), 1.5)
	var pressed := UiFrameStyle.make(Color(GOLD_DEEP, 0.55), GOLD, 2.0)
	var disabled := UiFrameStyle.make(Color(INK, 0.5), Color(PARCHMENT, 0.12), 1.0)
	var focus := UiFrameStyle.make_focus(GOLD_HI)
	for cls: StringName in [&"Button", &"OptionButton", &"MenuButton", &"CheckBox", &"CheckButton"]:
		t.set_stylebox(&"normal", cls, normal)
		t.set_stylebox(&"hover", cls, hover)
		t.set_stylebox(&"pressed", cls, pressed)
		t.set_stylebox(&"hover_pressed", cls, pressed)
		t.set_stylebox(&"disabled", cls, disabled)
		t.set_stylebox(&"focus", cls, focus)
		t.set_font(&"font", cls, title_font(600, 2))
		t.set_font_size(&"font_size", cls, SIZE_SMALL + 2)
		t.set_color(&"font_color", cls, PARCHMENT)
		t.set_color(&"font_hover_color", cls, GOLD_HI)
		t.set_color(&"font_pressed_color", cls, INK)
		t.set_color(&"font_hover_pressed_color", cls, INK)
		t.set_color(&"font_focus_color", cls, GOLD_HI)
		t.set_color(&"font_disabled_color", cls, Color(PARCHMENT, 0.3))
		t.set_color(&"icon_normal_color", cls, PARCHMENT)
		t.set_color(&"icon_hover_color", cls, GOLD_HI)
		t.set_color(&"icon_focus_color", cls, GOLD_HI)
		t.set_color(&"icon_pressed_color", cls, INK)
		t.set_constant(&"h_separation", cls, 12)
	# Ghost: text-only buttons (bottom bars, tabs)
	_variation(t, &"GhostButton", &"Button")
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 18
	empty.content_margin_right = 18
	empty.content_margin_top = 10
	empty.content_margin_bottom = 10
	for s: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		t.set_stylebox(s, &"GhostButton", empty)
	t.set_stylebox(&"focus", &"GhostButton", UiFrameStyle.make_focus(GOLD_HI, 0.0))
	t.set_color(&"font_color", &"GhostButton", PARCHMENT_DIM)
	t.set_color(&"font_pressed_color", &"GhostButton", GOLD)
	t.set_color(&"font_hover_pressed_color", &"GhostButton", GOLD)
	# Primary: gold filled call to action
	_variation(t, &"PrimaryButton", &"Button")
	t.set_stylebox(&"normal", &"PrimaryButton", UiFrameStyle.make(Color(GOLD_DEEP, 0.85), GOLD, 2.0))
	t.set_stylebox(&"hover", &"PrimaryButton", UiFrameStyle.make(Color(GOLD, 0.95), GOLD_HI, 2.0))
	t.set_stylebox(&"pressed", &"PrimaryButton", UiFrameStyle.make(GOLD_HI, GOLD_HI, 2.0))
	t.set_color(&"font_color", &"PrimaryButton", INK)
	t.set_color(&"font_hover_color", &"PrimaryButton", INK)
	t.set_color(&"font_focus_color", &"PrimaryButton", INK)
	_variation(t, &"DangerButton", &"Button")
	t.set_stylebox(&"hover", &"DangerButton", UiFrameStyle.make(Color(SEAL, 0.85), DANGER, 2.0))
	t.set_color(&"font_hover_color", &"DangerButton", PARCHMENT)
	# Check boxes use drawn toggles (UiToggle); keep CheckBox icons readable anyway.
	t.set_icon(&"checked", &"CheckBox", icon("ui_check"))
	t.set_icon(&"unchecked", &"CheckBox", _empty_icon(28))
	t.set_icon(&"arrow", &"OptionButton", icon("ui_chevron"))


static func _panels(t: Theme) -> void:
	var panel := UiFrameStyle.make(VEIL, Color(GOLD, 0.45), 1.5)
	panel.grain = 0.35
	panel.corner_ornaments = true
	panel.set_content_margin_all(28)
	t.set_stylebox(&"panel", &"Panel", panel)
	t.set_stylebox(&"panel", &"PanelContainer", panel)
	_variation(t, &"InkPanel", &"PanelContainer")
	t.set_stylebox(&"panel", &"InkPanel", panel)
	_variation(t, &"CardPanel", &"PanelContainer")
	var card := UiFrameStyle.make(Color(INK, 0.9), Color(GOLD, 0.3), 1.5)
	card.grain = 0.3
	card.set_content_margin_all(0)
	t.set_stylebox(&"panel", &"CardPanel", card)
	_variation(t, &"ToastPanel", &"PanelContainer")
	var toast := UiFrameStyle.make(Color(INK, 0.88), Color(GOLD, 0.0), 0.0)
	toast.accent_left = 4.0
	toast.accent_color = GOLD
	toast.content_margin_left = 22
	toast.content_margin_right = 22
	toast.content_margin_top = 12
	toast.content_margin_bottom = 12
	t.set_stylebox(&"panel", &"ToastPanel", toast)
	_variation(t, &"RowPanel", &"PanelContainer")
	var row := StyleBoxEmpty.new()
	row.content_margin_left = 20
	row.content_margin_right = 20
	t.set_stylebox(&"panel", &"RowPanel", row)
	var tip := UiFrameStyle.make(Color(INK, 0.96), Color(GOLD, 0.6), 1.0)
	tip.set_content_margin_all(12)
	t.set_stylebox(&"panel", &"TooltipPanel", tip)
	t.set_color(&"font_color", &"TooltipLabel", PARCHMENT)
	t.set_font(&"font", &"TooltipLabel", body_font())
	t.set_font_size(&"font_size", &"TooltipLabel", SIZE_SMALL)


static func _ranges(t: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(PARCHMENT, 0.16)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	track.corner_radius_top_left = 2
	track.corner_radius_top_right = 2
	track.corner_radius_bottom_left = 2
	track.corner_radius_bottom_right = 2
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = GOLD
	var fill_hi := track.duplicate() as StyleBoxFlat
	fill_hi.bg_color = GOLD_HI
	t.set_stylebox(&"slider", &"HSlider", track)
	t.set_stylebox(&"grabber_area", &"HSlider", fill)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", fill_hi)
	var grab := _diamond_icon(30, GOLD_HI)
	t.set_icon(&"grabber", &"HSlider", grab)
	t.set_icon(&"grabber_highlight", &"HSlider", _diamond_icon(34, Color.WHITE))
	t.set_icon(&"grabber_disabled", &"HSlider", _diamond_icon(26, Color(PARCHMENT, 0.3)))
	t.set_constant(&"center_grabber", &"HSlider", 1)
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(INK, 0.8)
	pb_bg.border_color = Color(GOLD, 0.35)
	pb_bg.set_border_width_all(1)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = GOLD
	t.set_stylebox(&"background", &"ProgressBar", pb_bg)
	t.set_stylebox(&"fill", &"ProgressBar", pb_fill)
	t.set_color(&"font_color", &"ProgressBar", PARCHMENT)
	# scroll bars: slim gold rail
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PARCHMENT, 0.06)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(GOLD, 0.55)
	grabber.set_corner_radius_all(4)
	var grabber_hi := grabber.duplicate() as StyleBoxFlat
	grabber_hi.bg_color = GOLD
	for cls: StringName in [&"VScrollBar", &"HScrollBar"]:
		t.set_stylebox(&"scroll", cls, sb)
		t.set_stylebox(&"grabber", cls, grabber)
		t.set_stylebox(&"grabber_highlight", cls, grabber_hi)
		t.set_stylebox(&"grabber_pressed", cls, grabber_hi)


static func _containers(t: Theme) -> void:
	t.set_constant(&"separation", &"VBoxContainer", 10)
	t.set_constant(&"separation", &"HBoxContainer", 12)
	var sep := StyleBoxLine.new()
	sep.color = Color(GOLD, 0.25)
	sep.thickness = 1
	t.set_stylebox(&"separator", &"HSeparator", sep)
	t.set_constant(&"separation", &"HSeparator", 18)
	# Tabs (settings): gold underline on the selected tab
	var tab_sel := UiFrameStyle.make(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0.0)
	tab_sel.underline = 3.0
	tab_sel.underline_color = GOLD
	tab_sel.content_margin_left = 26
	tab_sel.content_margin_right = 26
	tab_sel.content_margin_top = 12
	tab_sel.content_margin_bottom = 14
	var tab_un := tab_sel.duplicate() as UiFrameStyle
	tab_un.underline_color = Color(GOLD, 0.0)
	var tab_hover := tab_sel.duplicate() as UiFrameStyle
	tab_hover.underline_color = Color(GOLD, 0.4)
	t.set_stylebox(&"tab_selected", &"TabBar", tab_sel)
	t.set_stylebox(&"tab_unselected", &"TabBar", tab_un)
	t.set_stylebox(&"tab_hovered", &"TabBar", tab_hover)
	t.set_stylebox(&"tab_focus", &"TabBar", UiFrameStyle.make_focus(GOLD_HI, 0.0))
	t.set_font(&"font", &"TabBar", title_font(600, 3))
	t.set_font_size(&"font_size", &"TabBar", SIZE_SMALL + 2)
	t.set_color(&"font_selected_color", &"TabBar", GOLD_HI)
	t.set_color(&"font_unselected_color", &"TabBar", PARCHMENT_MUTED)
	t.set_color(&"font_hovered_color", &"TabBar", PARCHMENT)


static func _text_inputs(t: Theme) -> void:
	var le := UiFrameStyle.make(Color(INK, 0.85), Color(GOLD, 0.35), 1.0)
	le.content_margin_left = 14
	le.content_margin_right = 14
	t.set_stylebox(&"normal", &"LineEdit", le)
	t.set_stylebox(&"focus", &"LineEdit", UiFrameStyle.make_focus(GOLD_HI))
	t.set_color(&"font_color", &"LineEdit", PARCHMENT)
	t.set_color(&"caret_color", &"LineEdit", GOLD_HI)


static func _popups(t: Theme) -> void:
	var pm := UiFrameStyle.make(Color(INK, 0.97), Color(GOLD, 0.5), 1.0)
	pm.set_content_margin_all(8)
	t.set_stylebox(&"panel", &"PopupMenu", pm)
	var hov := StyleBoxFlat.new()
	hov.bg_color = Color(GOLD, 0.22)
	t.set_stylebox(&"hover", &"PopupMenu", hov)
	t.set_color(&"font_color", &"PopupMenu", PARCHMENT)
	t.set_color(&"font_hover_color", &"PopupMenu", GOLD_HI)
	t.set_font(&"font", &"PopupMenu", body_font())
	t.set_font_size(&"font_size", &"PopupMenu", SIZE_SMALL)


static func _variation(t: Theme, variation: StringName, base: StringName) -> void:
	t.set_type_variation(variation, base)


static func _diamond_icon(size: int, color: Color) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := (absf(x - c) + absf(y - c)) / c
			var a := clampf((1.0 - d) * c * 0.9, 0.0, 1.0)
			var edge := clampf((d - 0.62) * 6.0, 0.0, 1.0)
			var col := color.lerp(Color(INK, 1.0), edge * 0.0)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a * col.a))
	return ImageTexture.create_from_image(img)


static func _empty_icon(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


# --- Layout helpers --------------------------------------------------------------------------

## Margins (design px) that keep content inside the display safe area (phones with
## notches). Zero on desktop. Apply to full-screen roots' MarginContainers.
static func safe_area_margins(vp: Viewport) -> Vector4:
	if not Settings.is_mobile_device() or Settings.is_headless():
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if safe.size.x <= 0 or screen.x <= 0:
		return Vector4.ZERO
	var vis := vp.get_visible_rect().size
	var sx := vis.x / float(screen.x)
	var sy := vis.y / float(screen.y)
	return Vector4(safe.position.x * sx, safe.position.y * sy,
			(screen.x - safe.end.x) * sx, (screen.y - safe.end.y) * sy)


## Configures a Label quickly (font, size, color, alignment).
static func style_label(l: Label, font: Font, size: int, color: Color = PARCHMENT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.horizontal_alignment = align
	return l


static func make_label(text: String, font: Font = null, size: int = SIZE_BODY, color: Color = PARCHMENT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	return style_label(l, font if font else body_font(), size, color, align)
