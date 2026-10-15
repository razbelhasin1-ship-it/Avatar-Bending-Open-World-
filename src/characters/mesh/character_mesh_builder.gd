class_name CharacterMeshBuilder
extends RefCounted
## Builds the complete skinned character (skeleton layout + mesh) from a
## resolved outfit spec. Results are cached by appearance key so crowds share
## meshes and materials.
##
## Output dictionary:
##   "def": RigSkeletonDef (bones incl. secondary), "mesh": ArrayMesh,
##   "springs": Array of spring chain descriptors, "skirt": Dictionary or {}.

const SK = preload("res://src/characters/rig/rig_skeleton_def.gd")

static var _cache: Dictionary = {}
static var _body_material: Material = null
static var _flat_material: Material = null


static func body_material() -> Material:
	if _body_material == null:
		_body_material = ToonMaterials.make(Color.WHITE, {"vertex_color": true, "rim": 0.3, "specular": 0.025, "outline_width": 1.0})
	return _body_material


static func flat_material() -> Material:
	if _flat_material == null:
		_flat_material = ToonMaterials.make(Color.WHITE, {"vertex_color": true, "outline": false, "rim": 0.0, "specular": 0.0})
	return _flat_material


static func clear_cache() -> void:
	_cache.clear()


static func cache_size() -> int:
	return _cache.size()


## Builds (or fetches from cache) the character for a resolved spec.
static func build(spec: Dictionary) -> Dictionary:
	var key: String = spec.get("cache_key", "")
	if key != "" and _cache.has(key):
		return _cache[key]
	var props := RigSkeletonDef.make_proportions(spec.get("body", "male"), spec.get("age", "adult"), spec.get("bulk", 0.0))
	var d := RigSkeletonDef.new().build(props)
	var hs := RigHeadShape.from_def(d)
	var springs: Array = []
	springs.append_array(RigHairBuilder.add_bones(d, hs, spec))
	springs.append_array(RigGarmentBuilder.add_bones(d, spec))
	var outl := SkinMeshBuilder.new()
	var flat := SkinMeshBuilder.new()
	var detail: int = spec.get("detail", 2)
	var segs := 14 if detail <= 0 else (18 if detail == 1 else 22)
	var torso := RigBodyBuilder.build_torso(outl, d, spec, segs + 4)
	RigBodyBuilder.build_neck(outl, d, spec, segs - 4)
	var arms: Array[RigLoft] = []
	var legs: Array[RigLoft] = []
	for side in 2:
		arms.append(RigBodyBuilder.build_arm(outl, d, side, spec, segs - 6))
		RigBodyBuilder.build_hand(outl, d, side, spec)
		legs.append(RigBodyBuilder.build_leg(outl, d, side, spec, segs - 4))
		RigBodyBuilder.build_foot(outl, d, side, spec)
	RigHeadBuilder.build(outl, flat, d, spec, hs)
	RigHairBuilder.build(outl, d, hs, spec)
	var leg_infl := 0.0
	for band: Dictionary in spec.get("leg_bands", []):
		leg_infl = maxf(leg_infl, float(band.get("inflate", 0.0)))
	var ctx := {"torso": torso, "arms": arms, "legs": legs, "head": hs, "segs": segs,
		"torso_bands": spec.get("torso_bands", []), "leg_infl": leg_infl}
	RigGarmentBuilder.build(outl, flat, d, spec, ctx)
	var mesh := ArrayMesh.new()
	outl.commit(mesh, body_material())
	flat.commit(mesh, flat_material())
	var result := {"def": d, "mesh": mesh, "springs": springs, "vertex_count": outl.vertex_count() + flat.vertex_count()}
	if key != "":
		_cache[key] = result
	return result
