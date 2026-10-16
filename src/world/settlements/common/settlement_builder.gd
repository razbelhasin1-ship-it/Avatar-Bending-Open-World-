class_name SettlementBuilder
extends RefCounted
## Recipe dispatcher of one settlement: turns plan pieces into BuildingKit geometry. Subclasses
## (NwtBuilder, SatBuilder) implement build_piece() with a `match piece["kind"]`. Thread-safe:
## called on WorldContent workers, read-only access to the plan and WorldData.
##
## The kit's current frame is the piece frame when build_piece runs: origin = piece "pos"
## (relative to the cell), rotated by piece "yaw" (-Z = front). `kit.lod` is 0 (full), 1
## (simplified mid-distance version) or 2 (far silhouette) — recipes skip details accordingly.
## Pieces with an "arch" key are built once per archetype and LOD at the origin and cached.

var plan: SettlementPlan
var nation: StringName = &"neutral"


func _init(p_plan: SettlementPlan = null) -> void:
	plan = p_plan
	if plan:
		nation = plan.nation


## Builds `piece` into `kit` (frame already pushed). Override.
func build_piece(_kit: BuildingKit, _piece: Dictionary) -> void:
	pass


## Main-thread extras of a piece built at LOD0 (world positions): Array of
##   {"type": &"particles", "kind": &"smoke"|&"motes"|&"steam"|&"embers", "position": Vector3}
##   {"type": &"sound", "name": StringName, "position": Vector3, "db": float}
##   {"type": &"node", "make": Callable(cell: ContentCell) -> Node3D}   (added under the cell root)
##   {"type": &"marker", "group": StringName, "position": Vector3, "yaw": float, "meta": Dictionary}
func piece_extras(_piece: Dictionary) -> Array:
	return []


## Night glows of a piece (lit lanterns, braziers, lit windows) in world space:
## [[Vector3 position, Color, float size multiplier], ...]. Thread-safe, deterministic. The far
## provider draws them as SettlementFx night glow sprites beyond lod1_end, so a lit city
## sparkles from kilometres away (approximate spots are fine there). Up to lod1_end the near
## provider draws glows exactly on the LOD0 kit's light records instead (lights + KitX.glow).
func piece_glows(_piece: Dictionary) -> Array:
	return []


## World position of a piece-local point.
static func at(piece: Dictionary, local: Vector3) -> Vector3:
	return (piece["pos"] as Vector3) + Basis(Vector3.UP, float(piece["yaw"])) * local


## Extra payload entries of a piece (special meshes with their own materials, e.g. animated
## water sheets), relative to the cell `origin`. WORKER THREAD. Materials must exist already
## (SettlementFx.prepare runs on the main thread before any cell builds).
func piece_payload(_piece: Dictionary, _payload: CellPayload, _origin: Vector3) -> void:
	pass


## Palette of the settlement nation.
func palette() -> NationPalette:
	return NationPalette.get_palette(nation)


## Cache key of an archetype at a LOD.
func arch_key(arch: String, lod: int) -> String:
	return "%s|%s|%d" % [nation, arch, lod]


## Builds (or fetches) the cached result of an archetype piece at `lod`.
func archetype(piece: Dictionary, lod: int) -> KitResult:
	var key := arch_key(piece["arch"], lod)
	return KitCache.fetch(key, func() -> KitResult:
		var kit := BuildingKit.new(palette(), lod, ContentHash.hash_name(key))
		var p := piece.duplicate()
		p["pos"] = Vector3.ZERO
		p["yaw"] = 0.0
		build_piece(kit, p)
		return kit.build())
