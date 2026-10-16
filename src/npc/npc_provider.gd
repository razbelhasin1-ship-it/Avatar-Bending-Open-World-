class_name NpcProvider
extends ContentProvider
## WorldContent provider of crowd NPC records (docs/modules/quests_npcs.md "NPC streaming").
## A main-thread index buckets the settlement anchors into 64 m cells once; the worker turns a
## cell's anchors into spawn records (NpcCrowd) and the cell hands them to the NpcDirector, which
## spawns the nearest few within the detail-level budget. Released cells withdraw their records.

const CELL := 64.0

var director: NpcDirector = null
## Anchor density multiplier (NpcDirector.budgets()["density"]), read by the worker.
var density := 1.0
var _index: Dictionary = {}          # Vector2i -> Array[Dictionary] anchors
var _claimed: Dictionary = {}        # anchor ids taken by named NPCs
var _indexed := false


func _init(p_director: NpcDirector = null) -> void:
	id = &"npc_crowds"
	cell_size = CELL
	priority = 1
	unload_margin = 40.0
	director = p_director


func configure() -> bool:
	var b := NpcDirector.budgets()
	var old_density := density
	range_m = float(b["crowd_range"]) + 30.0
	density = float(b["density"])
	_build_index()
	return old_density != density


## Indexes every crowd anchor kind (main thread; plans are built and cached by Settlements).
func _build_index() -> void:
	if _indexed:
		return
	_indexed = true
	_claimed = NpcDirector.claimed_anchor_ids()
	for a in Settlements.get_anchors():
		if not NpcCrowd.KINDS.has(a["kind"]):
			continue
		var p: Vector3 = a["position"]
		var c := coord_of(p.x, p.z)
		if not _index.has(c):
			_index[c] = []
		(_index[c] as Array).append(a)


func wants_cell(coord: Vector2i) -> bool:
	return _index.has(coord)


func build_cell(cell: ContentCell) -> void:
	var p := CellPayload.new()
	var recs := NpcCrowd.records_for(_index.get(cell.coord, []), density, _claimed)
	p.data["npc_records"] = recs
	var coord := cell.coord
	var dir := director
	p.add_call(func(_c: ContentCell) -> void:
		if dir != null and is_instance_valid(dir):
			dir.add_records(coord, recs))
	cell.payload = p


func release_cell(cell: ContentCell) -> void:
	if director != null and is_instance_valid(director):
		director.remove_records(cell.coord)


## Anchors indexed (tests / stats).
func anchor_count() -> int:
	var n := 0
	for c: Vector2i in _index:
		n += (_index[c] as Array).size()
	return n
