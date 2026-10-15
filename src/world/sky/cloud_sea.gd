class_name CloudSea
extends MeshInstance3D
## The sea of clouds around the Southern Air Temple: a slab of ray-marched cloud
## (assets/shaders/world/cloud_sea.gdshader) between SLAB_BOTTOM and SLAB_TOP covering the
## south-eastern peaks, so the temple terraces (762-822 m) and summits rise above it.
## The plane sits on the slab face nearest to the camera; hidden when far away.

const SHADER := preload("res://assets/shaders/world/cloud_sea.gdshader")
const CLOUD_TEX := preload("res://assets/textures/world/clouds.png")
const CENTER := Vector2(2500.0, 3150.0)
const RADIUS := 2300.0
const SLAB_BOTTOM := 545.0
const SLAB_TOP := 625.0
## Beyond this distance from CENTER the layer is not drawn.
const VISIBLE_RANGE := 9000.0

var material: ShaderMaterial
## Turns the layer off entirely (cinematics, debugging); `update` keeps it hidden.
var enabled: bool = true


func _ready() -> void:
	name = "CloudSea"
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = 2
	WorldData.apply_height_uniforms(material)
	material.set_shader_parameter(&"cloud_tex", CLOUD_TEX)
	material.set_shader_parameter(&"slab_bottom", SLAB_BOTTOM)
	material.set_shader_parameter(&"slab_top", SLAB_TOP)
	material.set_shader_parameter(&"region_center", CENTER)
	material.set_shader_parameter(&"region_radius", RADIUS)
	var pm := PlaneMesh.new()
	pm.size = Vector2(RADIUS * 2.2, RADIUS * 2.2)
	mesh = pm
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position = Vector3(CENTER.x, SLAB_TOP, CENTER.y)
	visible = WorldData.has_world_data()


## Places the plane on the slab face facing the camera; `coverage` 0..1 (weather), `light`
## multiplies opacity at night so the layer does not glow.
func update(cam_pos: Vector3, coverage: float) -> void:
	if not WorldData.has_world_data():
		return
	var d := Vector2(cam_pos.x, cam_pos.z).distance_to(CENTER)
	visible = enabled and d < VISIBLE_RANGE
	if not visible:
		return
	var y := SLAB_TOP + 0.5 if cam_pos.y >= SLAB_BOTTOM else SLAB_BOTTOM - 0.5
	position = Vector3(CENTER.x, y, CENTER.y)
	material.set_shader_parameter(&"coverage", clampf(0.5 + coverage * 0.25, 0.4, 0.85))
