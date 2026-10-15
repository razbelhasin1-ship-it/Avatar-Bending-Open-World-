class_name CreatureMaterials
extends RefCounted
## Material factory for creatures (toon skin, shell fur, eyes, wing membranes) with a
## shared cache, so every instance of a species reuses the same materials. Per-creature
## effects (hit flash, status tint) are *instance uniforms* set on the MeshInstance3D
## (see CreatureRig.flash_hit / set_status), so sharing is safe.

const SKIN_SHADER := preload("res://assets/shaders/creatures/creature_skin.gdshader")
const FUR_SHADER := preload("res://assets/shaders/creatures/fur_shell.gdshader")
const EYE_SHADER := preload("res://assets/shaders/creatures/creature_eye.gdshader")
const MEMBRANE_SHADER := preload("res://assets/shaders/creatures/membrane.gdshader")
const OUTLINE_SHADER := preload("res://assets/shaders/creatures/creature_outline.gdshader")

enum Pattern { NONE, FUR, SCALES, FEATHERS, SHELL, SMOOTH }

const INK := Color(0.07, 0.055, 0.06)

static var _cache: Dictionary = {}


## Clears cached materials (tests / hot reload).
static func clear_cache() -> void:
	_cache.clear()


## Number of fur shells for a detail level (0..3) and LOD (0 = full).
static func shell_count(detail: int, lod: int = 0) -> int:
	if lod >= 2:
		return 0
	var n: int = [0, 4, 7, 10][clampi(detail, 0, 3)]
	return n if lod == 0 else n / 2


## Skin material with its pass chain: [fur shells] -> ink outline.
## `key` identifies the material in the cache (e.g. "sky_bison/fur").
## opts: pattern (Pattern), pattern_scale, pattern_strength, marks (Texture2D),
## mark_rows (int), mark_colors (Array[Color] x3), rim, rim_color, shade_tint, specular,
## specular_size, softness, emission, emission_energy, belly_shade, plate_spacing,
## plate_line, translucency, translucency_color,
## outline (bool, default true), outline_width (default 1.0),
## fur (Dictionary {length, density, comb, strand_width, tip_lighten, root_dark}),
## shells (int, number of fur shells; 0 = none).
static func skin(key: String, color: Color, opts: Dictionary = {}) -> ShaderMaterial:
	var shells: int = opts.get("shells", 0)
	var full_key := "%s|%d" % [key, shells]
	if _cache.has(full_key):
		return _cache[full_key]
	var m := ShaderMaterial.new()
	m.shader = SKIN_SHADER
	_apply_common(m, color, opts)
	m.set_shader_parameter(&"pattern", int(opts.get("pattern", Pattern.NONE)))
	m.set_shader_parameter(&"pattern_scale", float(opts.get("pattern_scale", 8.0)))
	m.set_shader_parameter(&"pattern_strength", float(opts.get("pattern_strength", 0.15)))
	m.set_shader_parameter(&"belly_shade", float(opts.get("belly_shade", 0.12)))
	if opts.has("plate_spacing"):
		m.set_shader_parameter(&"plate_spacing", float(opts["plate_spacing"]))
		m.set_shader_parameter(&"plate_line", opts.get("plate_line", Color(0.55, 0.32, 0.12)))
	var tail: Material = null
	var fur: Dictionary = opts.get("fur", {})
	if opts.get("outline", true):
		tail = outline(float(opts.get("outline_width", 1.0)), opts.get("outline_color", INK),
				float(fur.get("length", 0.0)) * float(opts.get("outline_push", 0.45)) if shells > 0 else 0.0)
	# Build the shell chain back to front so each shell's next_pass is the next shell.
	var chain := tail
	for i in range(shells, 0, -1):
		var sm := ShaderMaterial.new()
		sm.shader = FUR_SHADER
		_apply_common(sm, color, opts)
		sm.set_shader_parameter(&"shell", float(i) / float(shells))
		sm.set_shader_parameter(&"fur_length", float(fur.get("length", 0.06)))
		sm.set_shader_parameter(&"fur_density", float(fur.get("density", 70.0)))
		sm.set_shader_parameter(&"comb", fur.get("comb", Vector3(0.0, -0.35, 0.45)))
		sm.set_shader_parameter(&"strand_width", float(fur.get("strand_width", 0.62)))
		sm.set_shader_parameter(&"tip_lighten", float(fur.get("tip_lighten", 0.08)))
		sm.set_shader_parameter(&"root_dark", float(fur.get("root_dark", 0.22)))
		sm.next_pass = chain
		chain = sm
	m.next_pass = chain
	_cache[full_key] = m
	return m


## Plain toon material for hard parts (horns, claws, nose, teeth, mouth).
static func hard(key: String, color: Color, opts: Dictionary = {}) -> ShaderMaterial:
	var o := opts.duplicate()
	if not o.has("specular"):
		o["specular"] = 0.35
	if not o.has("rim"):
		o["rim"] = 0.25
	return skin(key, color, o)


## Eye material. opts: iris, iris_inner, sclera, iris_size, pupil_size, pupil_slit,
## glow, outline_width.
static func eye(key: String, opts: Dictionary = {}) -> ShaderMaterial:
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = EYE_SHADER
	for p: String in ["iris", "iris_inner", "sclera", "iris_size", "pupil_size", "pupil_slit", "glow", "catchlight"]:
		if opts.has(p):
			m.set_shader_parameter(StringName(p), opts[p])
	m.next_pass = outline(float(opts.get("outline_width", 0.8)), INK)
	_cache[key] = m
	return m


## Double-sided translucent wing membrane.
static func membrane(key: String, color: Color, opts: Dictionary = {}) -> ShaderMaterial:
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = MEMBRANE_SHADER
	_apply_common(m, color, opts)
	m.set_shader_parameter(&"translucency", float(opts.get("translucency", 0.8)))
	m.set_shader_parameter(&"translucency_color", opts.get("translucency_color", Color(1.0, 0.42, 0.16)))
	if opts.has("vein_color"):
		m.set_shader_parameter(&"vein_color", opts["vein_color"])
	_cache[key] = m
	return m


static func outline(width: float = 1.0, color: Color = INK, push: float = 0.0) -> ShaderMaterial:
	var key := "outline|%f|%s|%f" % [width, color.to_html(), push]
	if _cache.has(key):
		return _cache[key]
	var o := ShaderMaterial.new()
	o.shader = OUTLINE_SHADER
	o.set_shader_parameter(&"width", width)
	o.set_shader_parameter(&"outline_color", color)
	o.set_shader_parameter(&"push", push)
	_cache[key] = o
	return o


## Builds the marking texture. `rows[i]` describes MeshKit part row i:
## {dorsal: [[v, half_width], ...], ventral: [...], lateral: [...],
##  lateral_center: [[v, u_from_top], ...]} (piecewise linear over v in 0..1,
## half widths in u units where 0.5 = all the way around).
static func mark_texture(rows: Array) -> ImageTexture:
	const W := 256
	var img := Image.create_empty(W, maxi(rows.size(), 1), false, Image.FORMAT_RGBAF)
	for r in rows.size():
		var row: Dictionary = rows[r]
		for x in W:
			var v := (float(x) + 0.5) / W
			img.set_pixel(x, r, Color(
					_pl(row.get("dorsal", []), v), _pl(row.get("ventral", []), v),
					_pl(row.get("lateral", []), v), _pl(row.get("lateral_center", []), v, 0.25)))
	return ImageTexture.create_from_image(img)


## Piecewise-linear lookup in [[x, y], ...] (sorted by x).
static func _pl(keys: Array, x: float, fallback: float = 0.0) -> float:
	if keys.is_empty():
		return fallback
	if x <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(1, keys.size()):
		var k1: Array = keys[i]
		if x <= float(k1[0]):
			var k0: Array = keys[i - 1]
			var t := (x - float(k0[0])) / maxf(1e-5, float(k1[0]) - float(k0[0]))
			return lerpf(float(k0[1]), float(k1[1]), t)
	return float(keys[keys.size() - 1][1])


static func _apply_common(m: ShaderMaterial, color: Color, opts: Dictionary) -> void:
	m.set_shader_parameter(&"albedo", color)
	if opts.has("shade_tint"):
		m.set_shader_parameter(&"shade_tint", opts["shade_tint"])
	if opts.has("rim"):
		m.set_shader_parameter(&"rim_strength", float(opts["rim"]))
	if opts.has("rim_color"):
		m.set_shader_parameter(&"rim_color", opts["rim_color"])
	if opts.has("softness"):
		m.set_shader_parameter(&"band_softness", float(opts["softness"]))
	if opts.has("specular"):
		m.set_shader_parameter(&"specular_strength", float(opts["specular"]))
	if opts.has("specular_size"):
		m.set_shader_parameter(&"specular_size", float(opts["specular_size"]))
	if opts.has("emission"):
		m.set_shader_parameter(&"emission", opts["emission"])
		m.set_shader_parameter(&"emission_energy", float(opts.get("emission_energy", 1.0)))
	if opts.has("translucency"):
		m.set_shader_parameter(&"translucency", float(opts["translucency"]))
		m.set_shader_parameter(&"translucency_color", opts.get("translucency_color", Color(1.0, 0.45, 0.2)))
	if opts.has("marks"):
		m.set_shader_parameter(&"mark_tex", opts["marks"])
		m.set_shader_parameter(&"mark_rows", float(opts.get("mark_rows", 1)))
		var mc: Array = opts.get("mark_colors", [])
		for i in mini(mc.size(), 3):
			m.set_shader_parameter(StringName("mark_color%d" % i), mc[i])
