extends RefCounted
## Renderer probe for visibility-range fades (perf_polish): two overlapping "LOD" meshes of a
## merged-building look (a red near LOD and a blue far LOD of the same block, toon material with
## the ink outline) hand over at 60 m with VISIBILITY_RANGE_FADE_SELF and a 10 m margin; the
## camera is placed in front of, inside and behind the fade band. The screenshots show how the
## renderer blends (alpha / dither / sorting) - the decision record for the settlement fades.
## Run: tools/playtest.sh perf_polish_fade_probe out 960x540 (RENDERER=mobile / gl_compatibility)

var p: Playtest


func run(pt: Playtest) -> void:
	p = pt
	var root := Node3D.new()
	root.name = "FadeProbe"
	p.get_tree().root.add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.7, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	ground.material_override = ToonMaterials.make(Color(0.5, 0.48, 0.42), {"outline": false})
	root.add_child(ground)
	for mode in [GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED, GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF]:
		var x := -12.0 if mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED else 12.0
		var near := _block(Color(0.85, 0.3, 0.25), 0)
		near.position = Vector3(x, 0, 0)
		near.visibility_range_end = 60.0
		near.visibility_range_end_margin = 10.0
		near.visibility_range_fade_mode = mode
		root.add_child(near)
		var far := _block(Color(0.25, 0.4, 0.85), 1)
		far.position = Vector3(x, 0, 0)
		far.visibility_range_begin = 60.0
		far.visibility_range_begin_margin = 10.0
		far.visibility_range_fade_mode = mode
		root.add_child(far)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	for d in [45.0, 56.0, 60.0, 64.0, 75.0]:
		cam.position = Vector3(0, 8, d)
		cam.look_at(Vector3(0, 4, 0), Vector3.UP)
		await p.frames(4)
		await p.screenshot("fade_probe_%s_%d" % [RenderingServer.get_current_rendering_method(), int(d)])
	root.queue_free()


## A merged "house block" mesh: boxes with roofs, overlapping parts, single material + outline.
func _block(color: Color, lod: int) -> MeshInstance3D:
	var g := GeoBuilder.new()
	for i in 4:
		var h := 6.0 + i * 2.0
		g.box(Transform3D(Basis(), Vector3(-6.0 + i * 4.0, h * 0.5, sin(i) * 2.0)), Vector3(3.6, h, 6.0 - i * 0.6), color)
		if lod == 0:
			g.box(Transform3D(Basis(Vector3.UP, 0.4), Vector3(-6.0 + i * 4.0, h + 0.6, sin(i) * 2.0)), Vector3(4.2, 1.2, 4.2), color.darkened(0.3))
	var mi := MeshInstance3D.new()
	mi.mesh = g.to_mesh()
	mi.material_override = ToonMaterials.make(Color.WHITE, {"vertex_color": true, "outline": true})
	return mi
