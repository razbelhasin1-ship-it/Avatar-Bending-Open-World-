extends RefCounted
## Renders toon-shaded primitives to verify the shared shaders compile and look right.
func run(p: Playtest) -> void:
	var root := Node3D.new()
	p.get_tree().root.add_child(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 1.6, 5)
	cam.look_at(Vector3(0, 0.8, 0))
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.shadow_enabled = true
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	root.add_child(we)
	var colors := [Color(0.86, 0.22, 0.12), Color(0.18, 0.42, 0.82), Color(0.36, 0.62, 0.30), Color(0.96, 0.72, 0.30)]
	for i in 4:
		var m := MeshInstance3D.new()
		m.mesh = CapsuleMesh.new() if i % 2 == 0 else SphereMesh.new()
		m.material_override = ToonMaterials.make(colors[i])
		m.position = Vector3(-2.4 + i * 1.6, 1.0, 0)
		root.add_child(m)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(20, 20)
	ground.mesh = pm
	ground.material_override = ToonMaterials.make(Color(0.75, 0.7, 0.6), {"outline": false})
	root.add_child(ground)
	await p.wait(0.5)
	await p.screenshot("toon_primitives")
	p.check(true, "rendered")
