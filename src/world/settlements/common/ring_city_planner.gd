class_name RingCityPlanner
extends RefCounted
## Shared planning of the ring-layout cities (Ba Sing Se, Omashu, the Fire Nation capital,
## Crimson Harbor) and terraced villages: polar helpers, avenue / ramp gaps, retaining walls on
## the measured faces of the tier steps, and rows of houses along the ring streets. Subclasses set
## L, plan, rng, cam and `avenues` (the bearings of the radial ramps / avenues) and implement the
## house hooks (footprint / height / piece / anchors) and `wall_kind` for their nation's recipes.
## Main thread, deterministic.

var L: RingLayout
var plan: SettlementPlan
var rng: RandomNumberGenerator
var cam: ArrivalClearance
## Bearings of the radial avenues / ramps (wrapped to [-180, 180)).
var avenues: Array[float] = []
## Piece kind of the retaining wall chords (the nation's builder recipe; spec: L, H, P, depth,
## bottom, style, v, end, banner, tone).
var wall_kind: StringName = &"ring_wall"
## Fallback house kind when a picked one does not fit the band depth.
var fallback_kind: StringName = &""
var _band_rng: RandomNumberGenerator


# --- house hooks (override per nation) ------------------------------------------------------------

func house_footprint(_kind: StringName, _v: int) -> Vector2:
	return Vector2(8.0, 8.0)


func house_height(_kind: StringName, _v: int) -> float:
	return 8.0


## [arch key, spec] of a house piece.
func house_piece(kind: StringName, v: int, style: int) -> Array:
	return ["%s:%d:%d" % [kind, v, style], {"v": v, "style": style}]


## NPC anchors of a placed house (door = in front of the door; facing out = yaw + PI).
func house_anchors(_kind: StringName, _v: int, _style: int, _tier: StringName, _pos: Vector3, _yaw: float, _fp: Vector2, _door: Vector3) -> void:
	pass


func ground(x: float, z: float) -> float:
	return WorldData.get_height(x, z)


func p3(r: float, b: float, y: float = NAN) -> Vector3:
	return L.point(r, b, y)


static func yaw_in(b: float) -> float:
	return RingLayout.yaw_of(b + 180.0)


static func yaw_out(b: float) -> float:
	return RingLayout.yaw_of(b)


## Gaps ([bearing, half width m]) of the avenues.
func avenue_gaps(half_m: float) -> Array:
	var out := []
	for b in avenues:
		out.append([b, half_m])
	return out


## True when bearing b at radius r lies within `half_m` metres of an avenue axis.
func on_avenue(b: float, r: float, half_m: float) -> bool:
	for a in avenues:
		if RingLayout.arc_len(RingLayout.bdiff(b, a), r) < half_m:
			return true
	return false


## Spans of a full ring between the gaps: [[b0, b1], ...] with b1 > b0 (may exceed 180).
static func ring_spans(r: float, gaps: Array) -> Array:
	var cuts := []
	for g: Array in gaps:
		var ha := RingLayout.half_angle(float(g[1]) * 2.0, r)
		cuts.append([wrapf(float(g[0]), 0.0, 360.0), ha])
	cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out := []
	if cuts.is_empty():
		return [[0.0, 360.0]]
	for i in cuts.size():
		var a: Array = cuts[i]
		var b: Array = cuts[(i + 1) % cuts.size()]
		var b0 := float(a[0]) + float(a[1])
		var b1 := float(b[0]) - float(b[1])
		if i == cuts.size() - 1:
			b1 += 360.0
		if b1 > b0 + 0.05:
			out.append([b0, b1])
	return out


## Retaining wall chords (EkWalls.ring_wall) on the measured, smoothed foot of a tier step
## between r_hi (upper side) and r_lo (lower side), over `spans` ([[b0, b1], ...]). `style_at`
## (optional Callable(bearing) -> [style, parapet]) overrides the style per chord. Returns the
## measured faces [[bearing, r], ...].
func step_wall(spans: Array, y_lo: float, y_hi: float, r_hi: float, r_lo: float, nominal: float, chord: float, P: float,
		style: StringName, tone: int = 0, style_at: Callable = Callable()) -> Array:
	var H := y_hi - y_lo
	var vi := 0
	var faces: Array = []
	# the lower side is outward (Ba Sing Se, Omashu: r_lo > r_hi) or inward (terraced villages)
	var out_sign := 1.0 if r_lo > r_hi else -1.0
	for span: Array in spans:
		var len_m := RingLayout.arc_len(float(span[1]) - float(span[0]), nominal)
		var n := maxi(int(ceil(len_m / chord)), 1)
		var rs: Array[float] = []
		for k in n + 1:
			var b := lerpf(float(span[0]), float(span[1]), float(k) / n)
			rs.append(SettlementLayout.face_r(L, b, r_hi, r_lo, y_lo + 0.35) + 0.6 * out_sign)
		var pts: Array[Vector2] = []
		for k in n + 1:
			var acc := 0.0
			var cnt := 0
			for j in range(maxi(k - 2, 0), mini(k + 3, rs.size())):
				acc += rs[j]
				cnt += 1
			pts.append(L.xz(acc / cnt, lerpf(float(span[0]), float(span[1]), float(k) / n)))
		for k in n:
			var a := pts[k]
			var b := pts[k + 1]
			var m := (a + b) * 0.5
			var pr := L.polar(m.x, m.y)
			var top_r := SettlementLayout.face_r(L, pr.y, r_hi, r_lo, y_hi - 0.35)
			var depth := snappedf(clampf((pr.x - top_r) * out_sign + 3.0, 4.0, 14.0), 0.5)
			var st := style
			var p_h := P
			if style_at.is_valid():
				var o: Array = style_at.call(pr.y)
				st = o[0]
				p_h = float(o[1])
			var spec := {"L": snappedf(a.distance_to(b) + 0.08, 0.1), "H": H, "P": p_h, "depth": depth, "bottom": -1.5, "style": st,
				"v": vi % 6, "end": k % 2 == 0, "banner": st == &"crenel" and vi % 9 == 4, "tone": tone}
			plan.add(wall_kind, Vector3(m.x, y_lo, m.y), SettlementLayout.yaw_dir((m - L.center).normalized() * out_sign), spec, 2, "", a.distance_to(b) * 0.5)
			plan.reserve(m.x, m.y, 3.5)
			faces.append([pr.y, pr.x])
			vi += 1
	return faces


## A row of houses along a ring street: fronts at radius rf facing the street (inward when
## facing_in), up to `depth` deep, gaps where lanes / plazas / avenues are reserved. `kinds` =
## {kind: weight} of the nation's house kinds. Returns the number of buildings placed.
func band(tier: StringName, y: float, rf: float, depth: float, facing_in: bool, kinds: Dictionary, style: int, b0: float = 0.0,
		b1: float = 360.0, inside_fn: Callable = Callable(), gap_range: Vector2 = Vector2(-1.0, -1.0)) -> int:
	if _band_rng == null:
		_band_rng = ContentHash.rng(ContentHash.hash_name("%s_bands" % plan.id))
	var brng := _band_rng
	var inside := inside_fn
	if not inside.is_valid():
		inside = func(w: Vector3) -> bool:
			var t := L.tier_at(w.x, w.z)
			return not t.is_empty() and StringName(t["id"]) == tier and absf(ground(w.x, w.z) - y) < 0.9
	var gaps := gap_range if gap_range.x >= 0.0 else Vector2(0.6, 2.0)
	var b := b0
	var since := 0
	var placed := 0
	while b < b1:
		var kind: StringName = SettlementLayout.pick(kinds, brng)
		var v := brng.randi() % 12
		var fp := house_footprint(kind, v)
		if fp.y > depth and fallback_kind != &"":
			kind = fallback_kind
			fp = house_footprint(kind, v)
			if fp.y > depth:
				v = 0
				fp = house_footprint(kind, v)
		var bc := b + RingLayout.half_angle(fp.x, rf)
		var rc := rf + fp.y * 0.5 if facing_in else rf - fp.y * 0.5
		var bw := wrapf(bc, -180.0, 180.0)
		var yaw := yaw_in(bw) if facing_in else yaw_out(bw)
		var pos := p3(rc, bw, y)
		var hgt := house_height(kind, v)
		if fp.y <= depth + 0.5 and SettlementLayout.fits(plan, pos, yaw, fp, inside) and cam.ok(pos.x, pos.z, maxf(fp.x, fp.y) * 0.5, y + hgt):
			SettlementLayout.reserve_rect(plan, pos, yaw, fp)
			var hp := house_piece(kind, v, style)
			plan.add(kind, pos, yaw, hp[1], 2, hp[0], maxf(fp.x, fp.y) * 0.5)
			house_anchors(kind, v, style, tier, pos, yaw, fp, SettlementLayout.world(pos, yaw, Vector3(0, 0, -fp.y * 0.5 - 1.2)))
			placed += 1
			since += 1
			var gap := brng.randf_range(gaps.x, gaps.y)
			if since >= 4 + brng.randi() % 3:
				gap = brng.randf_range(1.6, 3.0)
				since = 0
			b += RingLayout.half_angle((fp.x + gap) * 2.0, rf)
		else:
			b += RingLayout.half_angle(2.0 * 2.5, rf)
	return placed
