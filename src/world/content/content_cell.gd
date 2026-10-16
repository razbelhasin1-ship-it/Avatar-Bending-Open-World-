class_name ContentCell
extends RefCounted
## One cell of a ContentProvider's grid. Created and owned by WorldContent.
##
## Lifecycle: QUEUED -> BUILDING (worker thread: provider.build_cell fills `payload`) -> BUILT ->
## INSTANTIATING (main thread, time-sliced provider.instantiate_step calls) -> ACTIVE ->
## released (nodes recycled/freed). A cell that leaves the range while building is discarded
## when its job finishes; a provider reconfiguration bumps `generation` so stale builds are dropped.

enum State { QUEUED, BUILDING, BUILT, INSTANTIATING, ACTIVE, RELEASED }

var provider: ContentProvider
var coord: Vector2i
## Deterministic seed: hash(provider seed, coord).
var seed: int = 0
## World x/z rectangle covered by the cell.
var rect: Rect2
var state: int = State.QUEUED
var generation: int = 0
## Built by provider.build_cell (worker thread). A CellPayload unless the provider overrides
## instantiate_step.
var payload: Variant = null
## Exclusion snapshot captured when the cell was queued (read-only on the worker).
var exclusions: ContentExclusions = null
## Main-thread state created on instantiation: the cell's root node (child of WorldContent,
## positioned at `origin()`), pooled nodes to recycle, sound loops, lights...
var root: Node3D = null
var pooled: Array = []
var loops: Array[int] = []
var user: Dictionary = {}
## Instantiate progress counter (steps done).
var step: int = 0
var task_id: int = -1
## Distance from the focus (m) at the last update; drives priorities.
var distance: float = 0.0
var build_usec: int = 0
var instance_count: int = 0
## Ground height estimate at the cell centre (for 3D range checks).
var ground_y: float = 0.0


func _init(p_provider: ContentProvider = null, p_coord: Vector2i = Vector2i.ZERO) -> void:
	provider = p_provider
	coord = p_coord
	if provider:
		var s := provider.cell_size
		rect = Rect2(coord.x * s, coord.y * s, s, s)
		seed = ContentHash.hash4(provider.seed, coord.x, coord.y, ContentHash.hash_name(String(provider.id)))


## World x/z centre.
func center() -> Vector2:
	return rect.get_center()


## World position of the cell root (centre at y = 0). Payload transforms are relative to it.
func origin() -> Vector3:
	var c := rect.get_center()
	return Vector3(c.x, 0.0, c.y)


## A fresh RNG seeded with the cell seed (+ salt for independent streams).
func rng(salt: int = 0) -> RandomNumberGenerator:
	return ContentHash.rng(ContentHash.hash4(seed, salt))


func is_active() -> bool:
	return state == State.ACTIVE
