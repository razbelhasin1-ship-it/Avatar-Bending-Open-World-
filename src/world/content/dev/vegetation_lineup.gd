extends Node3D
## Dev scene: every vegetation species at LOD 0/1/2 on a flat lawn under a simple sun/sky, plus
## a grass/flower patch. Used by the worldcontent_lineup playtest to judge the procedural meshes.
##   godot --path . -- --scene=res://scenes/dev/worldcontent_lineup.tscn

var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
## species id -> Vector3 position of its LOD0 instance
var spots: Dictionary = {}


func _ready() -> void:
	WorldShaderGlobals.ensure()
	VegetationLibrary.ensure_ready()
	VegetationMaterials.set_ranges(10000.0, 20000.0, 10000.0, 10000.0)
	_environment()
	_ground()
	var trees: Array[StringName] = []
	var small: Array[StringName] = []
	var ground: Array[StringName] = []
	for id: StringName in VegetationLibrary.SPECIES:
		match VegetationLibrary.SPECIES[id]["group"]:
			&"tree": trees.append(id)
			&"small": small.append(id)
			_: ground.append(id)
	for i in trees.size():
		var x := (i - trees.size() * 0.5) * 16.0
		for lod in 3:
			_place(trees[i], 0, lod, Vector3(x, 0, -lod * 26.0))
		if int(VegetationLibrary.SPECIES[trees[i]]["variants"]) > 1:
			_place(trees[i], 1, 0, Vector3(x + 7.0, 0, 9.0))
		spots[trees[i]] = Vector3(x, 0, 0)
	for i in small.size():
		var x := (i - small.size() * 0.5) * 5.0
		_place(small[i], 0, 0, Vector3(x, 0, 30.0))
		_place(small[i], 0, 1, Vector3(x, 0, 36.0))
		spots[small[i]] = Vector3(x, 0, 30.0)
	for i in ground.size():
		var x := (i - ground.size() * 0.5) * 3.0
		_patch(ground[i], Vector3(x, 0, 48.0), 1.4, 14)
		spots[ground[i]] = Vector3(x, 0, 48.0)
	# a lush meadow: grass + flowers mixed
	_meadow(Vector3(0, 0, 62.0), 12.0)
	cam = Camera3D.new()
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	look_from(Vector3(0, 9, 40), Vector3(0, 4, 0))


func look_from(pos: Vector3, at: Vector3, fov: float = 60.0) -> void:
	cam.global_position = pos
	cam.look_at(at, Vector3.UP)
	cam.fov = fov


func _environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.52, 0.85)
	sm.sky_horizon_color = Color(0.72, 0.80, 0.90)
	sm.ground_horizon_color = Color(0.6, 0.65, 0.6)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.0003
	env.fog_light_color = Color(0.72, 0.8, 0.9)
	Settings.configure_environment(env)
	env.volumetric_fog_density = 0.002
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	Settings.configure_sun(sun)
	add_child(sun)


func _ground() -> void:
	var g := GeoBuilder.new()
	g.flat_quad(Vector3(-300, 0, 300), Vector3(300, 0, 300), Vector3(300, 0, -300), Vector3(-300, 0, -300), TreeMeshes.col(0.36, 0.48, 0.20))
	var mi := MeshInstance3D.new()
	mi.mesh = g.to_mesh(ToonMaterials.make(Color.WHITE, {"vertex_color": true, "outline": false}))
	add_child(mi)


func _mm(id: StringName, variant: int, lod: int, xforms: Array, tints: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = VegetationLibrary.get_mesh(id, variant, lod)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, tints[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = VegetationLibrary.get_material(id, lod)
	add_child(mmi)
	return mmi


func _place(id: StringName, variant: int, lod: int, pos: Vector3) -> void:
	_mm(id, variant, lod, [Transform3D(Basis(), pos)], [Color(1, 1, 1, 0.5)])


func _patch(id: StringName, center: Vector3, radius: float, n: int) -> void:
	var rng := ContentHash.rng(ContentHash.hash_name(String(id)))
	var xs := []
	var ts := []
	var tint := TreeMeshes.col(0.36, 0.52, 0.18)
	for i in n:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius
		xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.2)), center + Vector3(cos(a) * d, 0, sin(a) * d)))
		ts.append(Color(tint.r, tint.g, tint.b, rng.randf()))
	_mm(id, 0, 0, xs, ts)


func _meadow(center: Vector3, radius: float) -> void:
	var rng := ContentHash.rng(99)
	var groups := {&"grass": [[], []], &"grass_tall": [[], []], &"flowers_warm": [[], []], &"flowers_cool": [[], []], &"flowers_white": [[], []]}
	var tint := TreeMeshes.col(0.36, 0.52, 0.18)
	for i in 1400:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius
		var r := rng.randf()
		var id: StringName = &"grass" if r < 0.7 else (&"grass_tall" if r < 0.85 else [&"flowers_warm", &"flowers_cool", &"flowers_white"][rng.randi() % 3])
		groups[id][0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.25)), center + Vector3(cos(a) * d, 0, sin(a) * d)))
		var k := rng.randf_range(0.85, 1.12)
		groups[id][1].append(Color(tint.r * k, tint.g * k, tint.b * k, rng.randf()))
	for id: StringName in groups:
		if not groups[id][0].is_empty():
			_mm(id, 0, 0, groups[id][0], groups[id][1])
