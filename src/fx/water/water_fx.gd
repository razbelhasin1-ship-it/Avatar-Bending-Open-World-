class_name WaterFx
extends RefCounted
## Water-technique visuals that are not tied to one ability:
##
##   WaterFx.pull(from, start, target_fn, 0.4, {"radius": 0.16, "strands": 2, "kind": &"water"})
##       thick streams pulled out of a source (sea, lake, snow ...) that arc to a
##       moving point (hands) over `duration`; snow sources come up as slush
##       with a snow burst, water sources splash and ring at the surface.
##   WaterFx.orb(from, center_fn, radius, glow)      a ball of water held at a point (looping)
##
## Everything is pooled (WaterStream) and stops by itself.


static func pull(from: Node, start: Vector3, target_fn: Callable, duration: float, opts: Dictionary = {}) -> Array[WaterStream]:
	var out: Array[WaterStream] = []
	var strands := clampi(int(opts.get("strands", 1)), 1, 4)
	if FxLib.tier() == 0:
		strands = mini(strands, 2)
	var radius := float(opts.get("radius", 0.12))
	var kind: StringName = opts.get("kind", &"water")
	var surface_y := float(opts.get("surface_y", start.y))
	match kind:
		&"snow", &"ice":
			FxBurst.spawn(from, &"snow", start + Vector3.UP * 0.2, {"count": 1.0 + radius * 3.0, "size": 0.9, "radius": 1.0 + strands * 0.4})
			FxBurst.spawn(from, &"dust_ring", Vector3(start.x, surface_y, start.z), {"color": FxLib.surface_color(&"snow"), "count": 0.8})
		&"canteen":
			pass
		_:
			IceFx.splash(from, start, 0.6 + radius * 3.0)
			FxRing.spawn(from, Vector3(start.x, surface_y + 0.03, start.z), 1.0 + radius * 6.0, Color(0.82, 0.94, 1.0), 0.6, {"opacity": 0.6, "fill": 0.25})
	for i in strands:
		var s := WaterStream.spawn(from)
		if kind == &"snow" or kind == &"ice":
			s.freeze = 0.35
		var d := PullDriver.new()
		d.set_meta(&"stream_driver", true)
		d.stream = s
		var side := (float(i) - (strands - 1) * 0.5)
		d.start = start + Vector3(side * 0.6, 0, side * 0.35)
		d.target_fn = target_fn
		d.duration = maxf(duration * (1.0 + 0.12 * i), 0.08)
		d.radius = radius * (1.0 - 0.15 * i)
		d.arc = float(opts.get("arc", 1.0)) * (1.0 + 0.25 * side)
		d.side = side
		s.add_child(d)
		out.append(s)
	return out


## Drives one pulled stream: the head rides an arc from the source to the
## target, the tail leaves the source once the head has arrived.
class PullDriver extends Node:
	var stream: WaterStream
	var start := Vector3.ZERO
	var target_fn: Callable
	var duration := 0.4
	var radius := 0.12
	var arc := 1.0
	var side := 0.0
	var t := 0.0
	var _last := Vector3.ZERO

	func _process(delta: float) -> void:
		t += delta
		if stream == null or not is_instance_valid(stream):
			queue_free()
			return
		var target := _last
		if target_fn.is_valid():
			var v: Variant = target_fn.call()
			if v is Vector3:
				target = v
		_last = target
		if target == Vector3.ZERO:
			stream.finish(0.1)
			queue_free()
			return
		var u := clampf(t / duration, 0.0, 1.0)
		var dist := start.distance_to(target)
		var head := start.lerp(target, smoothstep(0.0, 1.0, u))
		var right := (target - start).cross(Vector3.UP).normalized() if dist > 0.1 else Vector3.RIGHT
		var mid := start.lerp(head, 0.5) + Vector3.UP * (0.5 + dist * 0.18) * arc + right * side * 0.4
		var tail := start.lerp(head, clampf((u - 0.4) * 1.7, 0.0, 0.97))
		stream.set_points(PackedVector3Array([tail, tail.lerp(mid, 0.5), mid, mid.lerp(head, 0.6), head]), radius, radius * 0.75)
		stream.set_spray(u < 0.85)
		if u >= 1.0:
			stream.finish(0.12)
			queue_free()


## A held ball of water: a closed coil of stream turning around `center_fn()`.
## Returns the WaterStream (call finish() on it to drop it).
static func orb(from: Node, center_fn: Callable, radius: float = 0.3, glow: float = 0.0) -> WaterStream:
	var s := WaterStream.spawn(from)
	s.glow = glow
	var d := OrbDriver.new()
	d.set_meta(&"stream_driver", true)
	d.stream = s
	d.center_fn = center_fn
	d.radius = radius
	s.add_child(d)
	s.set_meta(&"orb_driver", d)
	return s


## Resizes a held orb (WaterFx.orb result).
static func set_orb_radius(s: WaterStream, radius: float) -> void:
	if s == null or not is_instance_valid(s):
		return
	var d: Variant = s.get_meta(&"orb_driver", null)
	if d is OrbDriver and is_instance_valid(d):
		(d as OrbDriver).radius = radius


class OrbDriver extends Node:
	var stream: WaterStream
	var center_fn: Callable
	var radius := 0.3
	var phase := randf() * TAU

	func _process(delta: float) -> void:
		if stream == null or not is_instance_valid(stream) or not center_fn.is_valid():
			queue_free()
			return
		var v: Variant = center_fn.call()
		if not (v is Vector3) or v == Vector3.ZERO:
			stream.finish(0.15)
			queue_free()
			return
		var c: Vector3 = v
		phase += delta * 7.0
		var pts := PackedVector3Array()
		for k in 10:
			var a := phase + float(k) / 9.0 * TAU * 1.1
			pts.append(c + Vector3(cos(a) * radius, sin(a * 2.0 + phase) * radius * 0.35, sin(a) * radius))
		stream.set_points(pts, radius * 0.42, radius * 0.3)
