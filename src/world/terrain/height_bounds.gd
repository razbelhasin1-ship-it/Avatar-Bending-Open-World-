class_name HeightBounds
extends RefCounted
## Min/max terrain height pyramid for culling AABBs of clipmap pieces and collision patches.
##
## Level 0 holds min/max per BLOCK x BLOCK texel block of the 4096^2 heightmap (64 m blocks);
## each further level halves the resolution. Built once on a worker thread (`build_async`);
## until it is ready `range_for_rect` answers with the full world height range (safe).

const BLOCK := 32
const GRID := WorldConstants.HEIGHTMAP_SIZE / BLOCK

var ready: bool = false
## Seconds the build took (diagnostics).
var build_time_sec: float = 0.0
var _mins: Array[PackedFloat32Array] = []
var _maxs: Array[PackedFloat32Array] = []
var _task: int = -1


## Starts the build on the WorkerThreadPool (no-op without world data).
func build_async() -> void:
	if _task >= 0 or ready or not WorldData.has_world_data():
		return
	_task = WorkerThreadPool.add_task(_build, false, "HeightBounds")


## Builds synchronously (tests).
func build_now() -> void:
	if ready or not WorldData.has_world_data():
		return
	if _task >= 0:
		wait()
		return
	_build()


func wait() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _build() -> void:
	var t0 := Time.get_ticks_usec()
	var img := WorldData.get_height_image()
	if img == null:
		return
	var raw := img.get_data()
	var n := WorldConstants.HEIGHTMAP_SIZE
	var mins := PackedInt32Array()
	var maxs := PackedInt32Array()
	mins.resize(GRID * GRID)
	maxs.resize(GRID * GRID)
	mins.fill(65535)
	maxs.fill(0)
	# row-wise scan: one decode per texel, block index changes every BLOCK texels
	for j in n:
		var brow := (j / BLOCK) * GRID
		var off := j * n * 2
		for bx in GRID:
			var lo := mins[brow + bx]
			var hi := maxs[brow + bx]
			var o := off + bx * BLOCK * 2
			for k in BLOCK:
				var v := raw.decode_u16(o + k * 2)
				if v < lo:
					lo = v
				if v > hi:
					hi = v
			mins[brow + bx] = lo
			maxs[brow + bx] = hi
	var l0min := PackedFloat32Array()
	var l0max := PackedFloat32Array()
	l0min.resize(GRID * GRID)
	l0max.resize(GRID * GRID)
	for k in GRID * GRID:
		l0min[k] = mins[k] * WorldConstants.HEIGHT_SCALE + WorldConstants.HEIGHT_MIN
		l0max[k] = maxs[k] * WorldConstants.HEIGHT_SCALE + WorldConstants.HEIGHT_MIN
	var lmins: Array[PackedFloat32Array] = [l0min]
	var lmaxs: Array[PackedFloat32Array] = [l0max]
	var size := GRID
	while size > 1:
		var half := size / 2
		var pmin := lmins[lmins.size() - 1]
		var pmax := lmaxs[lmaxs.size() - 1]
		var cmin := PackedFloat32Array()
		var cmax := PackedFloat32Array()
		cmin.resize(half * half)
		cmax.resize(half * half)
		for j in half:
			for i in half:
				var a := (j * 2) * size + i * 2
				cmin[j * half + i] = minf(minf(pmin[a], pmin[a + 1]), minf(pmin[a + size], pmin[a + size + 1]))
				cmax[j * half + i] = maxf(maxf(pmax[a], pmax[a + 1]), maxf(pmax[a + size], pmax[a + size + 1]))
		lmins.append(cmin)
		lmaxs.append(cmax)
		size = half
	_mins = lmins
	_maxs = lmaxs
	build_time_sec = (Time.get_ticks_usec() - t0) / 1000000.0
	ready = true


## Vector2(min, max) terrain height over the world-space rect (x/z). Conservative.
func range_for_rect(rect: Rect2) -> Vector2:
	if not ready:
		return Vector2(WorldConstants.HEIGHT_MIN, WorldConstants.HEIGHT_MAX)
	var world := Rect2(WorldConstants.WORLD_MIN, WorldConstants.WORLD_MIN, WorldConstants.WORLD_SIZE, WorldConstants.WORLD_SIZE)
	var r := rect.intersection(world)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		# outside the baked square the sea floor continues from the edge texels
		r = Rect2(rect.position.clamp(world.position, world.end - Vector2.ONE), Vector2.ONE)
	var block_m := BLOCK * WorldConstants.TEXEL_SIZE
	var level := 0
	var extent := maxf(r.size.x, r.size.y)
	while level < _mins.size() - 1 and block_m * float(1 << level) * 2.0 < extent:
		level += 1
	var size := GRID >> level
	var cell := block_m * float(1 << level)
	var i0 := clampi(int(floor((r.position.x - WorldConstants.WORLD_MIN) / cell)), 0, size - 1)
	var j0 := clampi(int(floor((r.position.y - WorldConstants.WORLD_MIN) / cell)), 0, size - 1)
	var i1 := clampi(int(floor((r.end.x - WorldConstants.WORLD_MIN) / cell)), 0, size - 1)
	var j1 := clampi(int(floor((r.end.y - WorldConstants.WORLD_MIN) / cell)), 0, size - 1)
	var lo := INF
	var hi := -INF
	var mins := _mins[level]
	var maxs := _maxs[level]
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			lo = minf(lo, mins[j * size + i])
			hi = maxf(hi, maxs[j * size + i])
	return Vector2(lo, hi)
