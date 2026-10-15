class_name TerrainNormalBaker
extends Node
## Bakes the world terrain normal map once on the GPU (canvas pass over the RG8 heightmap,
## central differences = WorldData.get_normal), reads it back and uploads a mipmapped RG8
## texture so distant terrain shading stays smooth and alias-free.
##
## Headless/dummy renderers cannot render: `finished` then fires with null and the terrain
## shader keeps computing normals from the heightmap (identical result, more texture reads).

signal finished(texture: Texture2D)

const BAKE_SHADER := preload("res://assets/shaders/world/terrain_normal_bake.gdshader")

var size: int = 4096
var texture: ImageTexture = null
var bake_time_sec: float = 0.0
var _viewport: SubViewport
var _task: int = -1
var _image: Image = null


## Starts the bake (call after adding the node to the tree). `out_size` 2048 or 4096.
func bake(out_size: int) -> void:
	size = out_size
	var hm := WorldData.get_height_texture()
	if hm == null or DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		_finish(null)
		return
	var t0 := Time.get_ticks_usec()
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(size, size)
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(size, size)
	var mat := ShaderMaterial.new()
	mat.shader = BAKE_SHADER
	mat.set_shader_parameter(&"world_height_map", hm)
	mat.set_shader_parameter(&"out_size", float(size))
	rect.material = mat
	_viewport.add_child(rect)
	add_child(_viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _viewport.get_texture().get_image()
	_viewport.queue_free()
	_viewport = null
	if img == null or img.is_empty():
		_finish(null)
		return
	# conversion + mipmaps off the main thread
	_image = img
	_task = WorkerThreadPool.add_task(_process_image, false, "TerrainNormalBaker")
	while not WorkerThreadPool.is_task_completed(_task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	texture = ImageTexture.create_from_image(_image)
	_image = null
	bake_time_sec = (Time.get_ticks_usec() - t0) / 1000000.0
	_finish(texture)


func _process_image() -> void:
	_image.convert(Image.FORMAT_RG8)
	_image.generate_mipmaps()


func _finish(tex: Texture2D) -> void:
	finished.emit(tex)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
