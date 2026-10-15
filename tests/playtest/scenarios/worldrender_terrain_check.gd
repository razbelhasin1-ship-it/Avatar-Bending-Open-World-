extends RefCounted
## GPU-side checks of the world renderer:
##  1. heights evaluated on the GPU by the shader include (the terrain vertex path) are read
##     back and compared with WorldData.get_height (CPU) at 4096 probe points;
##  2. physics raycasts on the streamed collision match WorldData under the camera;
##  3. a distant vista rendered normally and in wireframe (clipmap rings, no cracks).

const PROBE_SHADER := preload("res://assets/shaders/world/terrain_height_probe.gdshader")
const N := 64


func run(p: Playtest) -> void:
	var scene := await p.load_scene("res://scenes/dev/world_render_test.tscn")
	if scene == null:
		return
	var world: WorldRenderer = scene.world
	await p.wait_until(func() -> bool: return world.normal_baker.texture != null, 60.0)
	world.set_time_scale(0.0)
	await _gpu_heights(p, scene)
	await _collision_under_camera(p, scene, world)
	scene.set_view("vista")
	world.set_weather(&"clear", 0.0)
	await p.wait(1.0)
	await p.screenshot("worldrender_lod_vista")
	p.get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	await p.frames(3)
	await p.screenshot("worldrender_lod_wireframe")
	p.get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
	var tris := world.clipmap.triangle_budget()
	p.note("clipmap: %d levels, tile %d, base spacing %.3f m, %d pieces, %d triangles (all visible)" % [
			world.clipmap.level_count, world.clipmap.tile_res, world.clipmap.base_spacing, world.clipmap.piece_count(), tris])


func _gpu_heights(p: Playtest, scene: Node) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(N, N)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(N, N)
	var mat := ShaderMaterial.new()
	mat.shader = PROBE_SHADER
	WorldData.apply_height_uniforms(mat)
	var origin := Vector2(-3900.0, -3900.0)
	var step := 7800.0 / N
	mat.set_shader_parameter(&"probe_origin", origin)
	mat.set_shader_parameter(&"probe_step", step)
	mat.set_shader_parameter(&"probe_size", float(N))
	rect.material = mat
	vp.add_child(rect)
	scene.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if not p.check(img != null and not img.is_empty(), "GPU height probe rendered"):
		return
	var worst := 0.0
	for j in N:
		for i in N:
			var c := img.get_pixel(i, j)
			var mm := roundf(c.r * 255.0) + roundf(c.g * 255.0) * 256.0 + roundf(c.b * 255.0) * 65536.0
			var gpu_h := mm / 1000.0 - 300.0
			var pix := Vector2(i, j)
			var xz := origin + pix * step + Vector2(0.37, 0.71) * Vector2(fposmod(i * 0.61803, 1.0), fposmod(j * 0.61803, 1.0))
			worst = maxf(worst, absf(gpu_h - WorldData.get_height(xz.x, xz.y)))
	p.check(worst < 0.01, "GPU world_height == WorldData.get_height at %d probes (worst %.4f m)" % [N * N, worst])


func _collision_under_camera(p: Playtest, scene: Node, world: WorldRenderer) -> void:
	scene.set_view("ba_sing_se")
	await p.wait_until(func() -> bool: return world.is_collision_ready_at(world.camera.global_position), 10.0)
	await p.frames(30)
	var space := world.get_world_3d().direct_space_state
	var c := world.camera.global_position
	var worst := 0.0
	var hits := 0
	for k in 200:
		var x := c.x + randf_range(-120.0, 120.0)
		var z := c.z + randf_range(-120.0, 120.0)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 2000, z), Vector3(x, -500, z), Layers.WORLD)
		var r := space.intersect_ray(q)
		if not r.is_empty():
			hits += 1
			worst = maxf(worst, absf((r["position"] as Vector3).y - WorldData.get_height(x, z)))
	p.check(hits >= 190, "collision streamed around the focus (%d/200 rays hit)" % hits)
	p.check(worst < 0.15, "collision within %.3f m of WorldData (bilinear vs 1 m triangles)" % worst)
