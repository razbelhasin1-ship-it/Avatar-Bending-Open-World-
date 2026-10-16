class_name VegetationMaterials
extends RefCounted
## Shared vegetation materials (main thread). One material per (role, cap) so every cell's
## MultiMeshes share a handful of shaders/uniform sets:
##   roles: &"tree_near" (LOD0 + ink outline pass), &"tree_mid" (LOD1), &"tree_far" (impostors,
##          complementary distance band), &"small_near" (shrubs/rocks/logs + outline), &"small_mid",
##          &"grass" (ground cover).
##   caps:  &"none", &"snow", &"moss", &"ash", &"sand", &"ice" (glossy ice).
## Distance bands are updated for all materials by set_ranges() when Settings change.

const VEG_SHADER := preload("res://assets/shaders/content/vegetation.gdshader")
const OUTLINE_SHADER := preload("res://assets/shaders/content/vegetation_outline.gdshader")
const GRASS_SHADER := preload("res://assets/shaders/content/grass.gdshader")

const CAP_COLORS := {
	&"none": Color(0.6, 0.6, 0.6),
	&"snow": Color(0.92, 0.95, 1.0),
	&"moss": Color(0.30, 0.44, 0.16),
	&"ash": Color(0.32, 0.30, 0.30),
	&"sand": Color(0.86, 0.79, 0.60),
	&"ice": Color(0.85, 0.94, 1.0),
}

static var _cache: Dictionary = {}
static var _ranges := {"tree": 350.0, "tree_lod0": 90.0, "far": 1200.0, "small": 200.0, "small_lod0": 40.0, "grass": 60.0, "shadow": 110.0}


## Material for a role and cap (created once, then shared).
static func get_material(role: StringName, cap: StringName = &"none") -> ShaderMaterial:
	var key := "%s|%s" % [role, cap]
	if _cache.has(key):
		return _cache[key]
	WorldShaderGlobals.ensure()
	var m := ShaderMaterial.new()
	if role == &"grass":
		m.shader = GRASS_SHADER
	else:
		m.shader = VEG_SHADER
		m.set_shader_parameter(&"cap_color", CAP_COLORS.get(cap, CAP_COLORS[&"none"]))
		if cap == &"ice":
			m.set_shader_parameter(&"gloss", 0.8)
			m.set_shader_parameter(&"rim_strength", 0.5)
			m.set_shader_parameter(&"shade_tint", Color(0.55, 0.7, 0.95))
		if cap == &"snow":
			m.set_shader_parameter(&"snow_receptive", 0.6)
		if role == &"tree_far":
			m.set_shader_parameter(&"sway_amount", 0.0)
			m.set_shader_parameter(&"flutter", 0.0)
			m.set_shader_parameter(&"rim_strength", 0.12)
		if role == &"tree_mid" or role == &"small_mid":
			m.set_shader_parameter(&"shadow_ignores_fade_in", true)
		if role == &"tree_near" or role == &"small_near":
			var o := ShaderMaterial.new()
			o.shader = OUTLINE_SHADER
			o.set_shader_parameter(&"width", 0.9 if role == &"tree_near" else 0.8)
			o.set_shader_parameter(&"max_distance", 55.0 if role == &"tree_near" else 35.0)
			m.next_pass = o
	_cache[key] = m
	_apply_range(role, m)
	return m


## Distance bands (m): tree = mid trees end / impostors begin, tree_lod0 = LOD0 -> LOD1,
## far = impostors end, small = shrubs/rocks end, small_lod0, grass = ground cover end.
static func set_ranges(tree: float, far: float, small: float, grass: float, tree_lod0: float = -1.0, small_lod0: float = -1.0, shadow: float = 110.0) -> void:
	_ranges = {"tree": tree, "far": far, "small": small, "grass": grass, "shadow": shadow,
		"tree_lod0": tree_lod0 if tree_lod0 > 0.0 else tree * 0.28, "small_lod0": small_lod0 if small_lod0 > 0.0 else small * 0.22}
	for key: String in _cache:
		_apply_range(StringName(key.get_slice("|", 0)), _cache[key])


static func get_range(kind: String) -> float:
	return float(_ranges.get(kind, 0.0))


static func _apply_range(role: StringName, m: ShaderMaterial) -> void:
	var out := 100000.0
	var inn := 0.0
	var band := 24.0
	var band_in := 24.0
	var lod0_band := clampf(float(_ranges["tree_lod0"]) * 0.2, 6.0, 20.0)
	var tree_band := clampf(float(_ranges["tree"]) * 0.12, 12.0, 40.0)
	var small0_band := clampf(float(_ranges["small_lod0"]) * 0.2, 4.0, 12.0)
	match role:
		&"tree_near":
			out = _ranges["tree_lod0"]
			band = lod0_band
		&"tree_mid":
			inn = _ranges["tree_lod0"]
			band_in = lod0_band
			out = _ranges["tree"]
			band = tree_band
		&"tree_far":
			inn = _ranges["tree"]
			band_in = tree_band
			out = _ranges["far"]
			band = clampf(float(_ranges["far"]) * 0.15, 30.0, 200.0)
		&"small_near":
			out = _ranges["small_lod0"]
			band = small0_band
		&"small_mid":
			inn = _ranges["small_lod0"]
			band_in = small0_band
			out = _ranges["small"]
			band = clampf(float(_ranges["small"]) * 0.15, 8.0, 30.0)
		&"grass":
			out = _ranges["grass"]
			band = out * 0.45
	for mat: ShaderMaterial in [m, m.next_pass]:
		if mat == null:
			continue
		mat.set_shader_parameter(&"fade_out_end", out)
		mat.set_shader_parameter(&"fade_in_end", inn)
		mat.set_shader_parameter(&"fade_band", band)
		mat.set_shader_parameter(&"fade_in_band", band_in)
		mat.set_shader_parameter(&"shadow_max_distance", float(_ranges["shadow"]))
