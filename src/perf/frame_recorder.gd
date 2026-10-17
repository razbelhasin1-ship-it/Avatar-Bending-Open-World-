class_name FrameRecorder
extends Node
## Per-frame timing + pipeline-compilation recorder (perf_polish, docs/qa/perf_polish.md).
##
##   var rec := FrameRecorder.attach(get_tree())       # child of the root, always processing
##   var mark := rec.mark()                            # frame index to measure from
##   ... cast a technique, wait ...
##   var s := rec.summary(mark)  # {frames, max_ms, p95_ms, avg_ms, compiles, compiles_draw}
##   rec.queue_free()
##
## Frame time is the wall-clock gap between consecutive process frames (what the player sees
## as a hitch). Pipeline compilations come from RenderingServer.get_rendering_info
## (RENDERING_INFO_PIPELINE_COMPILATIONS_*: cumulative counts by source); `compiles_draw` are
## the ones compiled at draw time, i.e. the frame waited for them (the hitch the warm-up removes).

## Wall-clock ms of every recorded frame.
var frame_ms: PackedFloat32Array = PackedFloat32Array()
## Cumulative pipeline compilations (all sources / draw-time only) after each frame.
var compiles_total: PackedInt32Array = PackedInt32Array()
var compiles_draw: PackedInt32Array = PackedInt32Array()

var _last := 0


static func attach(tree: SceneTree) -> FrameRecorder:
	var r := FrameRecorder.new()
	r.name = "FrameRecorder"
	r.process_mode = Node.PROCESS_MODE_ALWAYS
	r.process_priority = -1000
	tree.root.add_child(r)
	return r


## Cumulative pipeline compilations by source: {canvas, mesh, surface, draw, specialization, total}.
static func pipeline_compilations() -> Dictionary:
	var out := {
		"canvas": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS),
		"mesh": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		"surface": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		"draw": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		"specialization": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION),
	}
	out["total"] = int(out["mesh"]) + int(out["surface"]) + int(out["draw"]) + int(out["specialization"])
	return out


func _ready() -> void:
	_last = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	frame_ms.append((now - _last) / 1000.0)
	_last = now
	var pc := pipeline_compilations()
	compiles_total.append(int(pc["total"]))
	compiles_draw.append(int(pc["draw"]))


## Index of the next frame to be recorded (start of a measured span).
func mark() -> int:
	return frame_ms.size()


## Stats of the frames recorded since `from` (up to `to`, exclusive; -1 = now).
func summary(from: int, to: int = -1) -> Dictionary:
	var end := frame_ms.size() if to < 0 else mini(to, frame_ms.size())
	var span: Array[float] = []
	for i in range(maxi(from, 0), end):
		span.append(frame_ms[i])
	var out := {"frames": span.size(), "max_ms": 0.0, "p95_ms": 0.0, "avg_ms": 0.0, "compiles": 0, "compiles_draw": 0}
	if span.is_empty():
		return out
	var total := 0.0
	for f in span:
		total += f
	var sorted := span.duplicate()
	sorted.sort()
	out["max_ms"] = sorted[-1]
	out["p95_ms"] = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))]
	out["avg_ms"] = total / span.size()
	var base_t := compiles_total[from - 1] if from > 0 and from - 1 < compiles_total.size() else (compiles_total[0] if not compiles_total.is_empty() else 0)
	var base_d := compiles_draw[from - 1] if from > 0 and from - 1 < compiles_draw.size() else (compiles_draw[0] if not compiles_draw.is_empty() else 0)
	out["compiles"] = compiles_total[end - 1] - base_t
	out["compiles_draw"] = compiles_draw[end - 1] - base_d
	return out
