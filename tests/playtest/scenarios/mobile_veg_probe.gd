extends RefCounted
## Vegetation on the current renderer: real VegetationLibrary meshes + materials in
## MultiMeshes with a known instance tint, in a lit test stage, plus three rows of an oak with
## an unshaded "show vertex COLOR" shader (MultiMesh with custom data / without / plain mesh)
## to isolate vertex-colour handling. Run per renderer and compare the shots:
##   RENDERER=gl_compatibility tools/playtest.sh mobile_veg_probe

var p: Playtest


func run(pt: Playtest) -> void:
	p = pt
	WorldShaderGlobals.ensure()
	VegetationLibrary.ensure_ready()
	var root := Node3D.new()
	p.get_tree().root.add_child(root)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.2, 7)
	cam.rotation_degrees = Vector3(-12, 0, 0)
	root.add_child(cam)
	cam.make_current()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = OS.get_environment("SHADOWS") != ""
	root.add_child(sun)
	if OS.get_environment("GLOW") != "":
		pass
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.6, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.6)
	root.add_child(env)
	var x := -4.5
	for id: StringName in [&"grass", &"grass_tall", &"flowers_warm", &"shrub", &"oak", &"maple"]:
		_row(root, VegetationLibrary.get_mesh(id, 0, 0), VegetationLibrary.get_material(id, 0), x, 0.0,
				0.35 if VegetationLibrary.SPECIES[id]["group"] == &"tree" else 1.0, true)
		x += 1.8
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nvarying vec4 v_col;\nvoid vertex() { v_col = COLOR; }\nvoid fragment() { ALBEDO = v_col.rgb; }\n"
	var show := ShaderMaterial.new()
	show.shader = sh
	var oak := VegetationLibrary.get_mesh(&"oak", 0, 0)
	_row(root, oak, show, -3.0, 3.2, 0.2, true)
	_row(root, oak, show, -1.0, 3.2, 0.2, false)
	var mi := MeshInstance3D.new()
	mi.mesh = oak
	mi.material_override = show
	mi.scale = Vector3.ONE * 0.2
	mi.position = Vector3(1.0, 3.2, 0)
	root.add_child(mi)
	await p.frames(8)
	await p.screenshot("veg_probe_%s" % Settings.rendering_method())
	root.queue_free()


func _row(root: Node3D, mesh: Mesh, mat: Material, x: float, y: float, s: float, custom: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = 3
	var stride := 16 if custom else 12
	var buf := PackedFloat32Array()
	buf.resize(3 * stride)
	for i in 3:
		var o := i * stride
		var vals := [s, 0.0, 0.0, x + (0.6 * i if y > 0.0 else 0.0), 0.0, s, 0.0, y, 0.0, 0.0, s, -float(i) * 1.2]
		for k in 12:
			buf[o + k] = vals[k]
		if custom:
			buf[o + 12] = 0.55
			buf[o + 13] = 0.75
			buf[o + 14] = 0.4
			buf[o + 15] = 0.37 * (i + 1)
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.custom_aabb = AABB(Vector3(-50, -5, -50), Vector3(100, 30, 100))
	root.add_child(mmi)
