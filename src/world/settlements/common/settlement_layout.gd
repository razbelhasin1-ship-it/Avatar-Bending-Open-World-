class_name SettlementLayout
extends RefCounted
## Layout helpers shared by the planners (static, thread-safe for read-only use): rotated
## footprint tests / reservations on a SettlementPlan occupancy grid, weighted picks, measured
## tier-step faces of a ring layout, chords along an arc.


## World position of a piece-local point.
static func world(pos: Vector3, yaw: float, local: Vector3) -> Vector3:
	return pos + Basis(Vector3.UP, yaw) * local


## Yaw whose local -Z faces direction (x, z).
static func yaw_dir(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


## True when the rotated footprint rectangle (fp = width x depth) is free in the plan (centre,
## corners and edge midpoints). `inside` (optional Callable(Vector3) -> bool) must accept every
## tested point (e.g. "still on this tier").
static func fits(plan: SettlementPlan, pos: Vector3, yaw: float, fp: Vector2, inside: Callable = Callable(), margin: float = 0.6) -> bool:
	var bs := Basis(Vector3.UP, yaw)
	var hx := fp.x * 0.5
	var hz := fp.y * 0.5
	for q: Vector3 in [Vector3.ZERO, Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz),
			Vector3(0, 0, -hz), Vector3(0, 0, hz), Vector3(-hx, 0, 0), Vector3(hx, 0, 0)]:
		var w := pos + bs * q
		if not plan.is_free(w.x, w.z, margin if q != Vector3.ZERO else minf(hx, hz) * 0.8):
			return false
		if inside.is_valid() and not inside.call(w):
			return false
	# long footprints: also the quarter points along the long axis
	if maxf(fp.x, fp.y) > minf(fp.x, fp.y) * 2.2:
		for t: float in [-0.25, 0.25]:
			var q := Vector3(t * fp.x, 0, 0) if fp.x >= fp.y else Vector3(0, 0, t * fp.y)
			var w := pos + bs * q
			if not plan.is_free(w.x, w.z, minf(hx, hz) * 0.8):
				return false
	return true


## Reserves a rotated rectangle as a row of circles along its long axis.
static func reserve_rect(plan: SettlementPlan, pos: Vector3, yaw: float, fp: Vector2, grow: float = 0.0) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var r := minf(fp.x, fp.y) * 0.5 + grow
	var n := maxi(int(ceil(maxf(fp.x, fp.y) / maxf(minf(fp.x, fp.y), 1.0))), 1)
	var long_x := fp.x >= fp.y
	for k in n:
		var t := (float(k) + 0.5) / n - 0.5
		var q := Vector3(t * fp.x, 0, 0) if long_x else Vector3(0, 0, t * fp.y)
		var w := pos + bs * q
		plan.reserve(w.x, w.z, r * 1.05)


## Weighted pick from {key: weight}.
static func pick(weights: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var total := 0.0
	for k: Variant in weights:
		total += float(weights[k])
	var x := rng.randf() * total
	for k: Variant in weights:
		x -= float(weights[k])
		if x <= 0.0:
			return k
	return weights.keys()[0]


## Measured face of a tier step along a bearing: the radius in [r0, r1] where the terrain
## crosses `y_mid` (binary search on WorldData heights; the generator blends steps, so the
## nominal tier radius is not where the slope is). Returns r1 when it never crosses.
static func face_r(L: RingLayout, bearing: float, r0: float, r1: float, y_mid: float) -> float:
	var a := r0
	var b := r1
	var ya := _h(L, a, bearing) - y_mid
	var yb := _h(L, b, bearing) - y_mid
	if signf(ya) == signf(yb):
		return r1
	for i in 18:
		var m := (a + b) * 0.5
		var ym := _h(L, m, bearing) - y_mid
		if signf(ym) == signf(ya):
			a = m
			ya = ym
		else:
			b = m
	return (a + b) * 0.5


static func _h(L: RingLayout, r: float, bearing: float) -> float:
	var p := L.xz(r, bearing)
	return WorldData.get_height(p.x, p.y)


## Lowest / highest terrain over a disc (9 samples).
static func ground_range(x: float, z: float, r: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for q: Vector2 in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r),
			Vector2(r, r) * 0.7, Vector2(-r, r) * 0.7, Vector2(r, -r) * 0.7, Vector2(-r, -r) * 0.7]:
		var y := WorldData.get_height(x + q.x, z + q.y)
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return Vector2(lo, hi)


## Chords along an arc of radius r from bearing b0 to b1, each about `chord` m long:
## [[Vector2 a, Vector2 b, Vector2 mid, float bearing_mid], ...] (x/z).
static func chords(L: RingLayout, r: float, b0: float, b1: float, chord: float) -> Array:
	var out: Array = []
	var len_m := RingLayout.arc_len(b1 - b0, r)
	if len_m < 0.5:
		return out
	var n := maxi(int(ceil(len_m / chord)), 1)
	for i in n:
		var ba := lerpf(b0, b1, float(i) / n)
		var bb := lerpf(b0, b1, float(i + 1) / n)
		var a := L.xz(r, ba)
		var b := L.xz(r, bb)
		out.append([a, b, (a + b) * 0.5, (ba + bb) * 0.5])
	return out
