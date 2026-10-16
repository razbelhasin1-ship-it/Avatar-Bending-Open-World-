extends RefCounted
## Renderer probe for MultiMesh per-instance custom data (INSTANCE_CUSTOM), which the
## vegetation shaders use for their tint. Four rows, all expected the SAME muted green
## (0.35, 0.55, 0.25): A buffer (custom only), B set_instance_custom_data, C buffer with
## colors + custom, D buffer (custom only) with a large instance_count and a smaller
## visible_instance_count (the vegetation subset path). Reads the pixels back and checks.
## Run on every renderer: RENDERER=gl_compatibility tools/playtest.sh mobile_compat_probe

const WANT := Color(0.35, 0.55, 0.25)

var p: Playtest


func run(pt: Playtest) -> void:
	p = pt
	var root := Node3D.new()
	p.get_tree().root.add_child(root)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 13)
	root.add_child(cam)
	cam.make_current()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.1, 0.1, 0.1)
	root.add_child(env)
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded;\nvarying vec4 v_custom;\nvoid vertex() { v_custom = INSTANCE_CUSTOM; }\nvoid fragment() { ALBEDO = v_custom.rgb; }\n"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.8, 0.8)
	var rows := [["A", 0, false, 8, -1], ["B", 1, false, 8, -1], ["C", 0, true, 8, -1], ["D", 0, false, 64, 8], ["E", 2, false, 8, -1], ["F", 3, false, 8, -1]]
	var y := 5.0
	for r: Array in rows:
		var mm := MultiMesh.new()
		if int(r[1]) == 3:
			# WorldContent's pool: a MultiMesh first used WITHOUT custom data, then recycled.
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = false
			mm.mesh = box
			mm.instance_count = 5
			var b0 := PackedFloat32Array()
			b0.resize(5 * 12)
			mm.buffer = b0
			mm.instance_count = 0
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = bool(r[2])
		mm.use_custom_data = true
		mm.mesh = box
		mm.instance_count = int(r[3])
		var stride := 12 + (4 if mm.use_colors else 0) + 4
		if int(r[1]) != 1:
			var buf := PackedFloat32Array()
			buf.resize(mm.instance_count * stride)
			for i in mm.instance_count:
				var x := -3.5 + i
				var o := i * stride
				var vals := [1.0, 0.0, 0.0, x, 0.0, 1.0, 0.0, y, 0.0, 0.0, 1.0, 0.0]
				for k in 12:
					buf[o + k] = vals[k]
				var c := 12
				if mm.use_colors:
					for k in 4:
						buf[o + c + k] = 1.0
					c += 4
				buf[o + c] = WANT.r
				buf[o + c + 1] = WANT.g
				buf[o + c + 2] = WANT.b
				buf[o + c + 3] = 0.5
			mm.buffer = buf
			if int(r[1]) == 2:
				# The vegetation path: the same MultiMesh gets a new buffer as the player moves.
				await p.frames(2)
				mm.buffer = buf.duplicate()
		else:
			for i in mm.instance_count:
				mm.set_instance_transform(i, Transform3D(Basis(), Vector3(-3.5 + i, y, 0)))
				mm.set_instance_custom_data(i, Color(WANT.r, WANT.g, WANT.b, 0.5))
		if int(r[4]) >= 0:
			mm.visible_instance_count = int(r[4])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		root.add_child(mmi)
		y -= 2.0
	await p.frames(6)
	var path := await p.screenshot("compat_probe_%s" % Settings.rendering_method())
	if path.is_empty():
		return
	var img := Image.load_from_file(path)
	var vp_rect := p.get_viewport().get_visible_rect().size
	for i in rows.size():
		var wy := 5.0 - 2.0 * i
		var sp := cam.unproject_position(Vector3(0.5, wy, 0.4))
		var px := Vector2i(int(sp.x / vp_rect.x * img.get_width()), int(sp.y / vp_rect.y * img.get_height()))
		var c := img.get_pixelv(px)
		var srgb := WANT.linear_to_srgb()
		var err := minf(absf(c.r - WANT.r) + absf(c.g - WANT.g) + absf(c.b - WANT.b), absf(c.r - srgb.r) + absf(c.g - srgb.g) + absf(c.b - srgb.b))
		p.check(err < 0.12, "row %s INSTANCE_CUSTOM on %s: got (%.2f, %.2f, %.2f)" % [rows[i][0], Settings.rendering_method(), c.r, c.g, c.b])
	root.queue_free()
