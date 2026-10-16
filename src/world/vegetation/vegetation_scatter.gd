class_name VegetationScatter
extends RefCounted
## Deterministic candidate evaluation on the global 4 m scatter grid (thread-safe).
##
## Every grid point (gx, gz) owns fixed random numbers (hash of VEG_SEED, gx, gz), so any provider
## can evaluate any point independently and get the same answer: the near vegetation cells
## (128 m) and the far impostor cells (512 m, a thinned subset) agree tree for tree.

const VEG_SEED := 0x5EED7
const GRID := 4.0
## Fraction of trees that also get a far impostor (the far layer scales them up to compensate).
const FAR_KEEP := 0.34
const FAR_SCALE := 1.38

## Result of an accepted candidate (reused per call site; plain fields for speed).
class Item:
	var species: StringName
	var variant := 0
	var layer := 0          # 0 tree, 1 small, 2 rock
	var pos := Vector3.ZERO
	var basis := Basis.IDENTITY
	var scale := 1.0
	var tint := Color(1, 1, 1, 0.5)


static func _u16(h: int) -> float:
	return float(h & 0xffff) / 65536.0


static func _u15(h: int) -> float:
	return float((h >> 16) & 0x7fff) / 32768.0


## True when the far layer keeps this grid point (cheap, no world sampling).
static func far_keeps(gx: int, gz: int) -> bool:
	return _u16(ContentHash.hash4(VEG_SEED, gx, gz, 101)) < FAR_KEEP


## Evaluates grid point (gx, gz). Returns accepted items (0..3: a tree or small plant, plus a rock).
## `layers` bitmask: 1 trees, 2 small, 4 rocks. Densities from cfg (VegetationSettings.current()).
static func evaluate(gx: int, gz: int, cfg: Dictionary, ex: ContentExclusions, layers: int = 7) -> Array[Item]:
	var out: Array[Item] = []
	var h := ContentHash.hash4(VEG_SEED, gx, gz, 11)
	var x := (float(gx) + _u16(h)) * GRID
	var z := (float(gz) + _u15(h)) * GRID
	var b := WorldData.get_biome(x, z)
	if b == VegetationRules.Bio.OCEAN or b == VegetationRules.Bio.CITY:
		return out
	var f_tree := 1.0
	var f_rock := 1.0
	if ex:
		f_tree = ex.factor(x, z, ContentExclusions.TAG_TREES)
		f_rock = ex.factor(x, z, ContentExclusions.TAG_ROCKS)
	if f_tree <= 0.0 and f_rock <= 0.0:
		return out
	var site := VegetationRules.sample(x, z)
	var eco := VegetationRules.ecology(site)
	var h2 := ContentHash.hash4(h, 3)
	var h3 := ContentHash.hash4(h, 5)
	var h4 := ContentHash.hash4(h, 7)
	var area := GRID * GRID / 100.0
	var p_tree := float(eco["tree"]) * area * float(cfg.get("tree_density", 1.0)) * f_tree
	var p_small := float(eco["small"]) * area * float(cfg.get("small_density", 1.0)) * f_tree
	var p_rock := float(eco["rock"]) * area * sqrt(float(cfg.get("small_density", 1.0))) * f_rock
	var ua := _u16(h2)
	if layers & 1 and ua < p_tree:
		var sp := VegetationRules.pick(eco["trees"], _u15(h2))
		if sp != &"":
			out.append(_make(sp, 0, site, h4, 0.8, 1.22))
	elif layers & 2 and ua - p_tree >= 0.0 and ua - p_tree < p_small:
		var sp := VegetationRules.pick(eco["smalls"], _u15(h2))
		if sp != &"":
			out.append(_make(sp, 1, site, h4, 0.75, 1.3))
	if layers & 4 and _u16(h3) < p_rock:
		var sp := VegetationRules.pick(eco["rocks"], _u15(h3))
		if sp != &"":
			out.append(_make(sp, 2, site, ContentHash.hash4(h4, 9), 0.0, 0.0))
	return out


static func _make(sp: StringName, layer: int, site: VegetationRules.Site, h: int, s0: float, s1: float) -> Item:
	var it := Item.new()
	it.species = sp
	it.layer = layer
	var spec: Dictionary = VegetationLibrary.SPECIES[sp]
	it.variant = (h >> 8) % int(spec["variants"])
	var u_s := _u16(h)
	var u_r := _u15(h)
	var h5 := ContentHash.hash4(h, 13)
	var u_t := _u16(h5)
	var u_t2 := _u15(h5)
	var yaw := u_r * TAU
	var sink := 0.12
	if layer == 2:
		# rocks: mostly small, few boulders; ice and seracs their own sizes
		match sp:
			&"serac": it.scale = lerpf(0.7, 1.5, u_s)
			&"ice_chunk": it.scale = lerpf(0.5, 2.6, u_s * u_s)
			&"driftwood": it.scale = lerpf(0.8, 1.2, u_s)
			&"lava_rock": it.scale = 0.3 + 1.5 * u_s * u_s
			_: it.scale = 0.3 + 2.6 * u_s * u_s * u_s
		var align := 0.0 if sp == &"serac" else 0.75
		var up := Vector3.UP.lerp(site.normal, align).normalized()
		it.basis = _up_basis(up, yaw).scaled(Vector3.ONE * it.scale)
		sink = 0.25 * it.scale if sp != &"driftwood" else 0.05
		if sp == &"serac":
			sink = 0.6
		it.tint = TerrainPatterns.rock_tint(site.region, u_t) if sp.begins_with("rock") or sp == &"lava_rock" else Color(1, 1, 1)
	else:
		it.scale = lerpf(s0, s1, u_s)
		if sp == &"palm" or sp == &"bamboo":
			it.scale *= lerpf(0.9, 1.15, u_t2)
		var tilt := Vector3.UP.lerp(site.normal, 0.08 if layer == 0 else 0.5).normalized()
		it.basis = _up_basis(tilt, yaw).scaled(Vector3.ONE * it.scale)
		var r: float = float(spec.get("radius", 0.2))
		sink = 0.1 + r * it.scale * tan(deg_to_rad(minf(site.slope, 40.0)))
		# colour variation: brightness + slight hue drift, stronger for broadleaf canopies
		var k := 0.86 + 0.28 * u_t
		var hue := (u_t2 - 0.5) * (0.16 if layer == 0 else 0.1)
		it.tint = Color(k * (1.0 + hue), k, k * (1.0 - hue))
	it.tint.a = _u15(h5 ^ 0x5bd1e995)
	it.pos = Vector3(site.x, site.h - sink, site.z)
	return it


static func _up_basis(up: Vector3, yaw: float) -> Basis:
	var b := Basis(Vector3.UP, yaw)
	if up.dot(Vector3.UP) > 0.9999:
		return b
	var axis := Vector3.UP.cross(up).normalized()
	return Basis(axis, Vector3.UP.angle_to(up)) * b
