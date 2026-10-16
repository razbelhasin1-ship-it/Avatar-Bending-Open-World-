class_name SettlementFx
extends RefCounted
## Main-thread resources and nodes shared by the settlement builders: materials that worker
## threads reference (waterfall sheets), garden plants from the VegetationLibrary as
## MultiMeshes (same toon shaders, wind sway and LOD fades as the open-world vegetation) and
## soft always-on lights.

## Species the gardens use (materials are created up front).
const PLANTS: Array[StringName] = [&"maple", &"blossom", &"bamboo", &"shrub", &"fern", &"grass", &"grass_tall",
	&"flowers_white", &"flowers_cool", &"flowers_warm", &"reeds", &"hedge", &"cypress", &"rock_moss"]
const NIGHT_GLOW_SHADER := preload("res://src/world/settlements/common/night_glow.gdshader")
## Glow colours of the builders' piece_glows().
const GLOW_LAMP := Color(1.0, 0.80, 0.52)
const GLOW_FIRE := Color(1.0, 0.55, 0.22)
const GLOW_WINDOW := Color(1.0, 0.70, 0.38)

static var _glow_mat: ShaderMaterial
static var _glow_mesh: QuadMesh


## Creates every shared material (call on the main thread before cells build).
static func prepare() -> void:
	NationPalette.prepare_materials()
	if _glow_mat == null:
		WorldShaderGlobals.ensure()
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = NIGHT_GLOW_SHADER
		_glow_mesh = QuadMesh.new()
		_glow_mesh.size = Vector2.ONE
	for layer in 2:
		WaterfallBuilder.sheet_material(layer, 14.2)
		WaterfallBuilder.sheet_material(layer, 3.0)
	WaterfallBuilder.foam_material()
	WaterfallBuilder.mist_material()
	for sp in PLANTS:
		for lod in VegetationLibrary.lod_count(sp):
			VegetationLibrary.get_material(sp, lod)


## Garden plants as MultiMeshes under one node: items = [[species, variant, Transform3D (world),
## Color(tint rgb, random a)], ...]. Every LOD of a species gets its own MultiMesh with the
## matching vegetation material; the shaders cross-fade them by distance per instance.
static func vegetation_node(items: Array, origin: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Garden"
	if items.is_empty():
		return root
	if not VegetationLibrary.is_ready():
		VegetationLibrary.ensure_ready()
	var groups := {}
	for it: Array in items:
		var key := "%s|%d" % [it[0], it[1]]
		if not groups.has(key):
			groups[key] = [it[0], it[1], PackedFloat32Array(), 0, Vector3.INF, -Vector3.INF]
		var g: Array = groups[key]
		var t: Transform3D = it[2]
		var local := Transform3D(t.basis, t.origin - origin)
		CellPayload.write_instance(g[2], local, it[3])
		g[3] = int(g[3]) + 1
		g[4] = (g[4] as Vector3).min(local.origin)
		g[5] = (g[5] as Vector3).max(local.origin)
	for key: String in groups:
		var g: Array = groups[key]
		var sp: StringName = g[0]
		var hgt := float(VegetationLibrary.SPECIES[sp].get("height", 2.0)) * 1.6
		var lo: Vector3 = g[4]
		var hi: Vector3 = g[5]
		var aabb := AABB(lo - Vector3(8, 2, 8), (hi - lo) + Vector3(16, hgt + 4, 16))
		for lod in VegetationLibrary.lod_count(sp):
			var mesh := VegetationLibrary.get_mesh(sp, int(g[1]), lod)
			if mesh == null:
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = mesh
			mm.instance_count = int(g[3])
			mm.custom_aabb = aabb
			mm.buffer = g[2]
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_lod%d" % [sp, lod]
			mmi.multimesh = mm
			mmi.material_override = VegetationLibrary.get_material(sp, lod)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (lod == 1 and VegetationLibrary.SPECIES[sp]["group"] == &"tree") \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)
	return root


## WORKER THREAD: night glows ([[Vector3 world, Color, size], ...]) of kit light records
## (positions relative to `origin`): every glow-only record (KitX.glow) and every light that is
## not an interior light, coloured by the light (normalised to its brightest channel).
static func glows_from_lights(lights: Array, origin: Vector3) -> Array:
	var out: Array = []
	for l: Dictionary in lights:
		if l.get("interior", false):
			continue
		var c: Color = l["color"]
		var m := maxf(maxf(c.r, c.g), maxf(c.b, 0.001))
		var size := float(l.get("glow", clampf(float(l.get("range", 9.0)) / 9.0, 0.7, 1.6)))
		out.append([(l["position"] as Vector3) + origin, Color(c.r / m, c.g / m, c.b / m), size])
	return out


## WORKER THREAD: appends the night glows `glows` ([[Vector3 world, Color, float size], ...]) as
## one MultiMesh of camera-facing additive sprites (night_glow.gdshader) to a payload, with a
## fixed AABB (relative to `origin`) so near and far providers hand over at the same distance.
## Needs prepare() to have run on the main thread.
static func add_glows(p: CellPayload, glows: Array, origin: Vector3, aabb: AABB, vis_begin: float, vis_end: float, tag: StringName) -> void:
	if glows.is_empty() or _glow_mat == null:
		return
	var buf := PackedFloat32Array()
	for gl: Array in glows:
		var c: Color = gl[1]
		CellPayload.write_instance(buf, Transform3D(Basis(), (gl[0] as Vector3) - origin), Color(c.r, c.g, c.b, float(gl[2])))
	p.add_multimesh(_glow_mesh, _glow_mat, buf, glows.size(), aabb.grow(8.0), {"vis_begin": vis_begin, "vis_end": vis_end,
		"margin": 0.0, "shadow": false, "tag": tag})


## A soft light that also shines by day (registered with LightBudget as an interior light).
static func warm_light(pos: Vector3, color: Color, range_m: float, energy: float) -> OmniLight3D:
	return LightBudget.make_light({"position": pos, "color": color, "range": range_m, "energy": energy, "priority": 4, "interior": true})
