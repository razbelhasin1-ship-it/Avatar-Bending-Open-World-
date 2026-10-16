extends RefCounted
## Diagnostic: vegetation MultiMeshes in the real world on the current renderer. Prints the
## CPU-side instance custom data of a few grass / tree MultiMeshes, then swaps their material
## for an unshaded INSTANCE_CUSTOM view and screenshots both.
## Run: RENDERER=gl_compatibility tools/playtest.sh mobile_veg_world_probe

const Follow := preload("res://tests/playtest/scenarios/companions_follow.gd")

var p: Playtest


func run(pt: Playtest) -> void:
	p = pt
	var e := ElementDefs.Element.AIR
	GameState.new_game(e)
	GameState.intro_done = true
	GameState.time_of_day = 10.5
	var spawn: Transform3D = Follow.route_start(WorldData.get_spawn(e).origin, 140.0, 22.0)
	var w := await p.load_scene("res://scenes/world/world.tscn", {"new_game": false, "spawn": spawn, "skip_intro": true}) as WorldScene
	await p.wait_until(func() -> bool: return w.playing, 240.0)
	await p.wait_game(3.0)
	await p.screenshot("vegw_%s_0" % Settings.rendering_method())
	var grass_code := (load("res://assets/shaders/content/grass.gdshader") as Shader).code
	var variants := {
		"custom": "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nvarying vec4 v_c;\nvoid vertex() { v_c = INSTANCE_CUSTOM; }\nvoid fragment() { ALBEDO = v_c.rgb * 0.5; }\n",
		"vcolor": "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nvarying vec4 v_c;\nvoid vertex() { v_c = COLOR; }\nvoid fragment() { ALBEDO = v_c.rgb; }\n",
		"grass_unshaded": grass_code.replace("render_mode blend_mix,", "render_mode unshaded, blend_mix,"),
		"grass_nolight": grass_code.substr(0, grass_code.find("void light()")),
	}
	var mmis: Array[MultiMeshInstance3D] = []
	var n := 0
	for node in p.get_tree().current_scene.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm == null or not mm.use_custom_data or mm.instance_count == 0:
			continue
		if n < 6:
			var vis := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			var cs: Array = []
			for i in mini(3, vis):
				cs.append(str(mm.get_instance_custom_data(i)))
			p.note("%s count %d visible %d colors %s mat %s custom %s" % [mmi.name, mm.instance_count, vis, mm.use_colors,
					mmi.material_override.resource_path if mmi.material_override else "-", ", ".join(cs)])
		n += 1
		if String(mmi.name).begins_with("grass") or String(mmi.name).begins_with("flowers") or String(mmi.name).begins_with("tuft"):
			mmis.append(mmi)
	p.note("%d MultiMeshes with custom data, %d ground cover" % [n, mmis.size()])
	var originals: Array = []
	for mmi in mmis:
		originals.append(mmi.material_override)
	# Fresh MultiMesh resources with the same data and the ORIGINAL materials: does a newly
	# created MultiMesh render the vertex colours right where a recycled / resized one fails?
	for mmi in mmis:
		var old := mmi.multimesh
		var nm := MultiMesh.new()
		nm.transform_format = MultiMesh.TRANSFORM_3D
		nm.use_custom_data = true
		nm.mesh = old.mesh
		nm.instance_count = old.instance_count
		nm.buffer = old.buffer
		nm.visible_instance_count = old.visible_instance_count
		nm.custom_aabb = old.custom_aabb
		mmi.multimesh = nm
	await p.frames(4)
	await p.screenshot("vegw_%s_fresh_mm" % Settings.rendering_method())
	# Same data with white instance colours added (stride 20).
	for mmi in mmis:
		var old := mmi.multimesh
		var src := old.buffer
		var cnt := old.instance_count
		var nb := PackedFloat32Array()
		nb.resize(cnt * 20)
		for i in cnt:
			for k in 12:
				nb[i * 20 + k] = src[i * 16 + k]
			for k in 4:
				nb[i * 20 + 12 + k] = 1.0
				nb[i * 20 + 16 + k] = src[i * 16 + 12 + k]
		var nm := MultiMesh.new()
		nm.transform_format = MultiMesh.TRANSFORM_3D
		nm.use_colors = true
		nm.use_custom_data = true
		nm.mesh = old.mesh
		nm.instance_count = cnt
		nm.buffer = nb
		nm.visible_instance_count = old.visible_instance_count
		nm.custom_aabb = old.custom_aabb
		mmi.multimesh = nm
	await p.frames(4)
	await p.screenshot("vegw_%s_with_colors" % Settings.rendering_method())
	# Scene features one at a time (with the original materials): which one corrupts COLOR?
	var we := p.get_tree().current_scene.find_children("*", "WorldEnvironment", true, false)
	var env: Environment = (we[0] as WorldEnvironment).environment if not we.is_empty() else null
	var steps := [
		["noglow", func() -> void: if env: env.glow_enabled = false],
		["nofog", func() -> void: if env: env.fog_enabled = false],
		["noshadow", func() -> void:
			for l in p.get_tree().current_scene.find_children("*", "DirectionalLight3D", true, false):
				(l as Light3D).shadow_enabled = false],
		["nolights", func() -> void:
			for l in p.get_tree().current_scene.find_children("*", "Light3D", true, false):
				if not (l is DirectionalLight3D):
					(l as Light3D).visible = false],
		["noparticles", func() -> void:
			for n2 in p.get_tree().current_scene.find_children("*", "GPUParticles3D", true, false):
				(n2 as GPUParticles3D).visible = false
			for n2 in p.get_tree().current_scene.find_children("*", "CPUParticles3D", true, false):
				(n2 as CPUParticles3D).visible = false],
	]
	for st: Array in steps:
		(st[1] as Callable).call()
		await p.frames(4)
		await p.screenshot("vegw_%s_step_%s" % [Settings.rendering_method(), st[0]])
	for key: String in variants:
		var sh := Shader.new()
		sh.code = variants[key]
		for i in mmis.size():
			var orig := originals[i] as ShaderMaterial
			var m := ShaderMaterial.new()
			m.shader = sh
			if orig and key.begins_with("grass"):
				for u in orig.shader.get_shader_uniform_list():
					m.set_shader_parameter(u["name"], orig.get_shader_parameter(u["name"]))
			mmis[i].material_override = m
		await p.frames(4)
		await p.screenshot("vegw_%s_%s" % [Settings.rendering_method(), key])
