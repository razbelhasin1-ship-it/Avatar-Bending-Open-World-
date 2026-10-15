class_name ToonMaterials
extends RefCounted
## Factory + cache for the shared toon look (characters, creatures, props).
##
##   mesh_instance.material_override = ToonMaterials.make(Color(0.8, 0.2, 0.1))
##   ToonMaterials.make(color, {"outline": false, "rim": 0.5, "vertex_color": true})
##
## Options: outline (bool, default true), outline_width (float), outline_color (Color),
## rim (float), shade_tint (Color), softness (float), specular (float),
## vertex_color (bool), texture (Texture2D), emission (Color), emission_energy (float),
## unique (bool: never share; needed if you animate per-instance uniforms like hit_flash).

const TOON_SHADER := preload("res://assets/shaders/toon.gdshader")
const OUTLINE_SHADER := preload("res://assets/shaders/outline.gdshader")

static var _cache: Dictionary = {}
static var _outline_cache: Dictionary = {}


static func make(color: Color, opts: Dictionary = {}) -> ShaderMaterial:
	var unique: bool = opts.get("unique", false)
	var key := ""
	if not unique:
		key = "%s|%s" % [color.to_html(), str(opts)]
		if _cache.has(key):
			return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter(&"albedo", color)
	if opts.has("shade_tint"):
		m.set_shader_parameter(&"shade_tint", opts["shade_tint"])
	if opts.has("rim"):
		m.set_shader_parameter(&"rim_strength", float(opts["rim"]))
	if opts.has("softness"):
		m.set_shader_parameter(&"band_softness", float(opts["softness"]))
	if opts.has("specular"):
		m.set_shader_parameter(&"specular_strength", float(opts["specular"]))
	if opts.get("vertex_color", false):
		m.set_shader_parameter(&"use_vertex_color", true)
	if opts.has("texture") and opts["texture"] is Texture2D:
		m.set_shader_parameter(&"use_texture", true)
		m.set_shader_parameter(&"albedo_texture", opts["texture"])
	if opts.has("emission"):
		m.set_shader_parameter(&"emission", opts["emission"])
		m.set_shader_parameter(&"emission_energy", float(opts.get("emission_energy", 1.0)))
	if opts.get("outline", true):
		m.next_pass = outline(float(opts.get("outline_width", 1.0)), opts.get("outline_color", Color(0.07, 0.055, 0.06)))
	if not unique:
		_cache[key] = m
	return m


static func outline(width: float = 1.0, color: Color = Color(0.07, 0.055, 0.06)) -> ShaderMaterial:
	var key := "%f|%s" % [width, color.to_html()]
	if _outline_cache.has(key):
		return _outline_cache[key]
	var o := ShaderMaterial.new()
	o.shader = OUTLINE_SHADER
	o.set_shader_parameter(&"width", width)
	o.set_shader_parameter(&"outline_color", color)
	_outline_cache[key] = o
	return o
