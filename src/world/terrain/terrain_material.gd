class_name TerrainMaterial
extends RefCounted
## Builds the clipmap terrain ShaderMaterial (assets/shaders/world/terrain.gdshader) and binds
## every world map and tiling texture it needs.

const SHADER := preload("res://assets/shaders/world/terrain.gdshader")
const NOISE_TEX := preload("res://assets/textures/world/noise.png")
const DETAIL_TEX := preload("res://assets/textures/world/detail.png")
const DETAIL_NRM_A := preload("res://assets/textures/world/detail_nrm_a.png")
const DETAIL_NRM_B := preload("res://assets/textures/world/detail_nrm_b.png")


static func make() -> ShaderMaterial:
	WorldShaderGlobals.ensure()
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var real := WorldData.has_world_data()
	m.set_shader_parameter(&"has_world", real)
	if real:
		WorldData.apply_height_uniforms(m)
		m.set_shader_parameter(&"splat_map", WorldData.get_splat_texture())
		m.set_shader_parameter(&"biome_map", WorldData.get_biome_texture())
		m.set_shader_parameter(&"region_map", WorldData.get_region_texture())
		m.set_shader_parameter(&"ground_map", WorldData.get_ground_texture())
		m.set_shader_parameter(&"road_map", WorldData.get_road_texture())
	m.set_shader_parameter(&"noise_tex", NOISE_TEX)
	m.set_shader_parameter(&"detail_tex", DETAIL_TEX)
	m.set_shader_parameter(&"detail_nrm_a", DETAIL_NRM_A)
	m.set_shader_parameter(&"detail_nrm_b", DETAIL_NRM_B)
	apply_quality(m)
	return m


## Detail-dependent shading parameters (Settings.detail_level()).
static func apply_quality(m: ShaderMaterial) -> void:
	var detail := Settings.detail_level()
	m.set_shader_parameter(&"detail_distance", [70.0, 110.0, 150.0, 220.0][detail])


## Switches shading to a baked normal map (TerrainNormalBaker); null restores the fallback.
static func set_normal_map(m: ShaderMaterial, tex: Texture2D) -> void:
	m.set_shader_parameter(&"world_normal_map", tex)
	m.set_shader_parameter(&"use_normal_map", tex != null)
