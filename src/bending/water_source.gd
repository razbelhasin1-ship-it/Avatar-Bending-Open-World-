class_name WaterSource
extends RefCounted
## Water for waterbending (docs/GAME_DESIGN.md "Water sources"): abilities ask
## for water near the caster. With a source in range (sea, lake, canal,
## fountain, snow or ice underfoot) the water visibly streams from it to the
## hands; without one the bender uses the canteen / air moisture: reduced size
## and +30% chi cost.
##
##   var w := WaterSource.find(ctx)            # {"found", "position", "kind", "distance"}
##   var cost := WaterSource.chi_cost(ctx, def.chi_cost)
##   WaterSource.draw(ctx, w, 0.35)           # stream from the source to the hands

const RADIUS := 12.0
const NO_SOURCE_COST := 1.3
const NO_SOURCE_SIZE := 0.7

static var _cache_pos := Vector3.INF
static var _cache_frame := -1
static var _cache: Dictionary = {}


## Nearest source (cached per physics frame and position).
static func find(ctx: BendingContext, radius: float = RADIUS) -> Dictionary:
	var pos := ctx.origin()
	var f := Engine.get_physics_frames()
	if f == _cache_frame and pos.distance_to(_cache_pos) < 0.5:
		return _cache
	_cache_frame = f
	_cache_pos = pos
	_cache = GroundSampler.find_water_source(pos, radius)
	return _cache


static func has_source(ctx: BendingContext) -> bool:
	return bool(find(ctx).get("found", false))


## Chi cost with the no-source penalty.
static func chi_cost(ctx: BendingContext, base: float) -> float:
	return base if has_source(ctx) else base * NO_SOURCE_COST


## Size multiplier with the no-source penalty.
static func size_mult(ctx: BendingContext) -> float:
	return 1.0 if has_source(ctx) else NO_SOURCE_SIZE


## Streams water from the source to the caster's hands over `duration`
## seconds. Snow/ice under the feet rises from the ground right in front;
## without a source a small stream curls out of the canteen at the hip.
## Returns the WaterStream (already animating; it fades by itself).
static func draw(ctx: BendingContext, src: Dictionary, duration: float = 0.35, to_socket: StringName = &"hand_r") -> WaterStream:
	var s := WaterStream.spawn(ctx.caster)
	var drawer := WaterDraw.new()
	drawer.stream = s
	drawer.ctx = ctx
	drawer.duration = maxf(duration, 0.05)
	drawer.socket = to_socket
	var found := bool(src.get("found", false))
	var kind: StringName = src.get("kind", &"")
	var start: Vector3
	if not found:
		start = ctx.socket_pos(&"pelvis") + ctx.right() * 0.22
		drawer.radius = 0.035
	elif kind == &"snow" or kind == &"ice" or float(src.get("distance", 0.0)) < 1.0:
		start = ctx.ground_point(ctx.origin() + ctx.forward() * 1.2)
		FxBurst.spawn(ctx.caster, &"snow" if kind == &"snow" else &"spray", start, {"count": 0.7, "size": 0.7})
		drawer.radius = 0.07
	else:
		start = src["position"]
		IceFx.splash(ctx.caster, start, 0.6)
		drawer.radius = 0.08
	drawer.start = start
	drawer.set_meta(&"stream_driver", true)
	s.add_child(drawer)
	BendingFeedback.sound(ElementDefs.Element.WATER, &"draw", start, -3.0)
	return s


## Animates a stream from a fixed start to a moving hand socket.
class WaterDraw extends Node:
	var stream: WaterStream
	var ctx: BendingContext
	var start := Vector3.ZERO
	var duration := 0.35
	var socket: StringName = &"hand_r"
	var radius := 0.08
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		if ctx == null or not ctx.is_valid() or stream == null:
			queue_free()
			return
		var hand := ctx.socket_pos(socket)
		var u := clampf(t / duration, 0.0, 1.0)
		var head := start.lerp(hand, smoothstep(0.0, 1.0, u))
		var mid := start.lerp(head, 0.5) + Vector3.UP * (0.6 + start.distance_to(hand) * 0.12)
		var tail := start.lerp(head, clampf((u - 0.45) * 1.8, 0.0, 0.95))
		stream.set_points(PackedVector3Array([tail, tail.lerp(mid, 0.5), mid, head]), radius, radius * 0.7)
		stream.set_spray(u < 0.8)
		if u >= 1.0:
			stream.finish(0.12)
			queue_free()
