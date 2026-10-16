class_name AirPlaytestGarden
extends Node3D
## Dev patch for checking Air's environment reactions outside the streamed world:
## real vegetation (grass, flowers, shrubs, two trees, drawn with the world's
## vegetation shaders), a cloth banner (world cloth shader), loose props (AirProp)
## and three test torches implementing the shared EXTINGUISH hook.
##
##   var g := AirPlaytestGarden.build(arena, Vector3(0, 0, 14))
##   g.torches_out(); g.props_moved()

var torches: Array[GardenTorch] = []
var props: Array[AirProp] = []
var _prop_start: Dictionary = {}


static func build(parent: Node, center: Vector3, size: Vector2 = Vector2(12.0, 9.0)) -> AirPlaytestGarden:
	WorldShaderGlobals.ensure()
	VegetationLibrary.ensure_ready()
	var g := AirPlaytestGarden.new()
	g.name = "AirGarden"
	parent.add_child(g)
	g.global_position = center
	g._grass(size)
	g._plants(size)
	g._banner(Vector3(-size.x * 0.5 + 0.8, 0, -size.y * 0.5 + 1.0))
	g.props = AirProp.scatter(parent, center + Vector3(1.5, 0, 0.5), 2.6, 6, [&"pot", &"pot", &"basket", &"crate", &"pot", &"barrel"], 11)
	for pr in g.props:
		g._prop_start[pr.get_instance_id()] = pr.global_position
	for tp: Vector3 in [Vector3(-2.6, 0, -2.6), Vector3(0.6, 0, -3.1), Vector3(3.1, 0, -2.3)]:
		var t := GardenTorch.new()
		g.add_child(t)
		t.position = tp
		g.torches.append(t)
	return g


func torches_out() -> int:
	var n := 0
	for t in torches:
		if is_instance_valid(t) and not t.lit:
			n += 1
	return n


func props_moved() -> int:
	var n := 0
	for pr in props:
		if not is_instance_valid(pr):
			n += 1
			continue
		var p0: Vector3 = _prop_start.get(pr.get_instance_id(), pr.global_position)
		if pr.global_position.distance_to(p0) > 0.3:
			n += 1
	return n


func _mm(id: StringName, variant: int, xforms: Array, tints: Array) -> void:
	var mesh := VegetationLibrary.get_mesh(id, variant, 0)
	if mesh == null or xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, tints[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = VegetationLibrary.get_material(id, 0)
	add_child(mmi)


func _grass(size: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var groups := {&"grass": [[], []], &"grass_tall": [[], []], &"flowers_warm": [[], []], &"flowers_white": [[], []]}
	var tint := TreeMeshes.col(0.4, 0.56, 0.2)
	var n := int(size.x * size.y * 9.0)
	for i in n:
		var p := Vector3(rng.randf_range(-size.x, size.x) * 0.5, 0.0, rng.randf_range(-size.y, size.y) * 0.5)
		var r := rng.randf()
		var id: StringName = &"grass" if r < 0.68 else (&"grass_tall" if r < 0.9 else (&"flowers_warm" if r < 0.96 else &"flowers_white"))
		groups[id][0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.3)), p))
		var k := rng.randf_range(0.85, 1.12)
		groups[id][1].append(Color(tint.r * k, tint.g * k, tint.b * k, rng.randf()))
	for id: StringName in groups:
		_mm(id, 0, groups[id][0], groups[id][1])


func _plants(size: Vector2) -> void:
	var o := Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var shrubs := []
	var stints := []
	for i in 7:
		var p := Vector3(rng.randf_range(-size.x, size.x) * 0.45, 0, rng.randf_range(-size.y, size.y) * 0.4)
		shrubs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.25)), o + p))
		stints.append(Color(1, 1, 1, rng.randf()))
	_mm(&"shrub", 0, shrubs, stints)
	_mm(&"maple", 0, [Transform3D(Basis(), o + Vector3(-size.x * 0.5 - 1.5, 0, -1.0))], [Color(1, 1, 1, 0.3)])
	_mm(&"blossom", 0, [Transform3D(Basis(), o + Vector3(size.x * 0.5 + 1.5, 0, -2.0))], [Color(1, 1, 1, 0.7)])


func _banner(at: Vector3) -> void:
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.06
	cm.height = 3.4
	pole.mesh = cm
	pole.material_override = ToonMaterials.make(Color(0.42, 0.3, 0.2))
	pole.position = at + Vector3(0, 1.7, 0)
	add_child(pole)
	# Cloth strip hanging from the top of the pole: UV.x = distance from the pole (0 pinned .. 1 free).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 1.3
	var h := 2.0
	var nx := 10
	var ny := 8
	var orange := Color(0.93, 0.5, 0.12).srgb_to_linear()
	var gold := Color(0.98, 0.8, 0.3).srgb_to_linear()
	for j in ny:
		for i in nx:
			var quad := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]
			for q: Array in quad:
				var u := float(q[0]) / nx
				var v := float(q[1]) / ny
				st.set_uv(Vector2(u, v))
				st.set_normal(Vector3(0, 0, 1))
				st.set_color(gold if v > 0.82 or v < 0.08 else orange)
				st.add_vertex(Vector3(u * w, -v * h, 0.0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/content/cloth.gdshader")
	mi.material_override = mat
	mi.position = at + Vector3(0.05, 3.3, 0)
	add_child(mi)


## A test torch: pole, flame and light; the wind puts it out (EXTINGUISH hook).
class GardenTorch extends Node3D:
	var lit := true
	var extinguish_radius := 0.4
	var flame: MeshInstance3D
	var light: OmniLight3D

	func _ready() -> void:
		add_to_group(&"extinguishable")
		var pole := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.04
		cm.bottom_radius = 0.05
		cm.height = 1.4
		pole.mesh = cm
		pole.material_override = ToonMaterials.make(Color(0.3, 0.22, 0.16))
		pole.position = Vector3(0, 0.7, 0)
		add_child(pole)
		var cup := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.14
		cyl.bottom_radius = 0.08
		cyl.height = 0.16
		cup.mesh = cyl
		cup.material_override = ToonMaterials.make(Color(0.36, 0.32, 0.28))
		cup.position = Vector3(0, 1.45, 0)
		add_child(cup)
		flame = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.36, 0.6)
		flame.mesh = q
		flame.material_override = FireFx.flame_material(randf(), 0.55)
		flame.position = Vector3(0, 1.78, 0)
		add_child(flame)
		light = OmniLight3D.new()
		light.light_color = Color(1.0, 0.62, 0.25)
		light.light_energy = 1.2
		light.omni_range = 4.0
		light.position = Vector3(0, 1.9, 0)
		add_child(light)

	func extinguish(_by: Node, _at: Vector3) -> bool:
		if not lit:
			return false
		lit = false
		flame.visible = false
		light.visible = false
		FxBurst.spawn(self, &"smoke", global_position + Vector3.UP * 1.75, {"count": 0.8})
		Audio.play_bending(ElementDefs.Element.FIRE, &"extinguish", global_position + Vector3.UP * 1.7, -4.0)
		return true
