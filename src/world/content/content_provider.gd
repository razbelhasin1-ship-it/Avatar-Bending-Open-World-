class_name ContentProvider
extends RefCounted
## Base class for content streamed by WorldContent (vegetation, POI structures, settlements,
## NPC/enemy/wildlife spawners...). A provider declares a square grid (`cell_size`) and an
## activation `range_m` around the focus; WorldContent loads the cells in range nearest first
## (higher `priority` first), builds them with `build_cell` on WorkerThreadPool, instantiates the
## result on the main thread in small time-sliced steps and recycles cells that left the range.
##
## Minimal provider (see docs/modules/worldcontent.md for a complete example):
##
##   class_name LanternProvider extends ContentProvider
##   func _init() -> void:
##       id = &"lanterns"; cell_size = 128.0; range_m = 300.0
##   func build_cell(cell: ContentCell) -> void:          # WORKER THREAD - pure data only
##       var p := CellPayload.new()
##       var buf := PackedFloat32Array()
##       var rng := cell.rng()
##       for i in 8:
##           var x := cell.rect.position.x + rng.randf() * cell_size
##           var z := cell.rect.position.y + rng.randf() * cell_size
##           var t := Transform3D(Basis(), Vector3(x, WorldData.get_height(x, z), z) - cell.origin())
##           CellPayload.write_instance(buf, t)
##       p.add_multimesh(LANTERN_MESH, null, buf, 8, AABB(Vector3(-64, -50, -64), Vector3(128, 600, 128)))
##       cell.payload = p
##   # optional: instantiate_step(cell) for custom main-thread work, release_cell(cell), configure()
##
##   world_content.register_provider(LanternProvider.new())
##
## Rules for build_cell: deterministic from `cell.coord` / `cell.seed` / `cell.rng()` (the same
## cell must always produce the same content), thread-safe (WorldData queries, math, Packed arrays,
## pre-built shared Mesh/Material resources are fine; no nodes, no Settings, no RenderingServer),
## and reasonably bounded (a few ms). Read Settings in `configure()` on the main thread instead.

## Unique id (also mixed into cell seeds).
var id: StringName = &"provider"
## Cell edge length in metres. Cells are aligned to multiples of cell_size from the world origin.
var cell_size: float = 128.0
## Cells whose closest point lies within this distance of the focus are loaded.
var range_m: float = 256.0
## Hysteresis: loaded cells are released beyond range_m + unload_margin.
var unload_margin: float = 48.0
## Higher priorities load first; within a priority, nearer cells first.
var priority: int = 0
## Build on WorkerThreadPool (false: build on the main thread inside the frame budget).
var threaded: bool = true
## Distance includes the focus height above the cell's ground (no grass when flying high).
var use_height: bool = false
## Cap on loaded cells (0 = no cap); the farthest are released first when exceeded.
var max_cells: int = 0
## Seed mixed into every cell seed.
var seed: int = 1337
var enabled: bool = true
## Set by WorldContent.register_provider.
var content: WorldContent = null
## Bumped whenever cells must be rebuilt (configure() returned true, refresh()).
var generation: int = 0


## Main thread. Read Settings / world state here (on registration and on
## Events.graphics_settings_changed). Return true when already built cells are now stale.
func configure() -> bool:
	return false


## Main thread: called at every scan (~7 times a second) before cells are chosen — advance
## lazy setup (mesh uploads, data indexes) here.
func tick() -> void:
	pass


## Main thread, cheap: return false to skip a cell entirely (empty ocean, no features).
func wants_cell(_coord: Vector2i) -> bool:
	return true


## WORKER THREAD (or main thread when threaded = false): fill `cell.payload`.
func build_cell(_cell: ContentCell) -> void:
	pass


## Main thread: performs one step of instantiation; return true when the cell is complete.
## The default turns a CellPayload into nodes (multimeshes, meshes, static collision, calls) and
## registers its pooled colliders. Override for custom payloads (call super to keep the default).
func instantiate_step(cell: ContentCell) -> bool:
	return content.instantiate_payload_step(cell)


## Main thread: called every update for active cells with the current focus distance (optional
## distance-dependent tweaks: grass density, light toggles...).
func update_cell(_cell: ContentCell, _distance: float) -> void:
	pass


## Main thread: custom teardown before WorldContent recycles the cell's nodes.
func release_cell(_cell: ContentCell) -> void:
	pass


## World-space grid coordinate containing x/z.
func coord_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / cell_size)), int(floor(z / cell_size)))


## Rectangle of a cell coordinate.
func rect_of(coord: Vector2i) -> Rect2:
	return Rect2(coord.x * cell_size, coord.y * cell_size, cell_size, cell_size)
