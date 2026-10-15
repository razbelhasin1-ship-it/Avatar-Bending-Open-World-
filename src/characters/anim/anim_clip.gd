class_name AnimClip
extends RefCounted
## A compiled keyframed pose clip (see AnimLibrary for the authoring format).
##
## Each animated channel has its own key track. A clip only overrides the
## channels it keys; everything else passes through from the layer below. For
## non-looping clips the layer below acts as an implicit key at t = 0 and t = 1
## unless the clip keys those times explicitly, so clips blend in from and back
## to the current stance/locomotion pose automatically.

const P = preload("res://src/characters/anim/rig_pose.gd")

var name: StringName = &""
## Seconds at speed 1.
var length := 1.0
var loop := false
var mask_name: StringName = &"full"
var mask: Array = []
## Sorted [[t_norm, StringName], ...].
var events: Array = []
## Foot plants [[t_norm, side(0/1), weight]] -> Events.footstep.
var plants: Array = []
## Root motion [[t_norm, Vector3 (right, up, forward) meters]].
var root: Array = []
var blend_in := 0.08
var blend_out := 0.15
## Clip to continue with when this one ends (e.g. knockdown -> down_loop).
var next: StringName = &""
## Pose state to enter after finishing (e.g. &"knocked_down").
var then_state: StringName = &""
## Optional loop clip overriding that state's default clip (e.g. a prone death).
var state_clip: StringName = &""
## Arbitrary metadata (style, tags, signature...).
var meta: Dictionary = {}
## channel -> {"t": PackedFloat32Array, "v": Array (null = base), "e": Array[StringName]}
var tracks: Dictionary = {}


static func ease_u(kind: StringName, u: float) -> float:
	match kind:
		&"in":
			return u * u
		&"out":
			return 1.0 - (1.0 - u) * (1.0 - u)
		&"inout":
			return u * u * (3.0 - 2.0 * u)
		&"snap":
			return 1.0 - pow(1.0 - u, 3.0)
		&"slow":
			return u * u * u
		&"hold":
			return 0.0
	return u


## Compiles an authoring Dictionary. Returns null and warns on invalid data.
static func compile(clip_name: StringName, d: Dictionary) -> AnimClip:
	var c := AnimClip.new()
	c.name = clip_name
	c.length = maxf(float(d.get("length", 1.0)), 0.01)
	c.loop = bool(d.get("loop", false))
	c.mask_name = StringName(d.get("mask", &"full"))
	c.mask = P.MASKS.get(c.mask_name, [])
	c.blend_in = float(d.get("blend_in", 0.08))
	c.blend_out = float(d.get("blend_out", 0.15))
	c.next = StringName(d.get("next", &""))
	c.then_state = StringName(d.get("then_state", &""))
	c.state_clip = StringName(d.get("state_clip", &""))
	c.meta = d.get("meta", {})
	var ev: Variant = d.get("events", [])
	if ev is Dictionary:
		for k: Variant in ev:
			c.events.append([float(ev[k]), StringName(k)])
	elif ev is Array:
		for e: Array in ev:
			c.events.append([float(e[0]), StringName(e[1])])
	c.events.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for pl: Array in d.get("plants", []):
		c.plants.append([float(pl[0]), 0 if String(pl[1]) in ["l", "left", "0"] else 1, float(pl[2]) if pl.size() > 2 else 1.0])
	for r: Array in d.get("root", []):
		c.root.append([float(r[0]), r[1] as Vector3])
	var keys: Array = d.get("keys", [])
	if keys.is_empty():
		push_warning("AnimClip '%s' has no keys" % clip_name)
	# Gather per-channel keys.
	var raw := {}
	for k: Array in keys:
		var t: float = clampf(float(k[0]), 0.0, 1.0)
		var pose: Dictionary = k[1]
		var e: StringName = StringName(k[2]) if k.size() > 2 else &"linear"
		for ch_name: String in pose:
			var ci := P.NAMES.find(ch_name)
			if ci < 0:
				push_warning("AnimClip '%s': unknown channel '%s'" % [clip_name, ch_name])
				continue
			var val: Variant = pose[ch_name]
			if P.is_float_channel(ci):
				val = float(val)
			elif not (val is Vector3):
				push_warning("AnimClip '%s': channel '%s' needs a Vector3" % [clip_name, ch_name])
				continue
			if not raw.has(ci):
				raw[ci] = []
			(raw[ci] as Array).append([t, val, e])
	for ci: int in raw:
		var lst: Array = raw[ci]
		lst.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var ts := PackedFloat32Array()
		var vs: Array = []
		var es: Array = []
		if not c.loop and lst[0][0] > 0.0001:
			ts.append(0.0)
			vs.append(null)
			es.append(&"linear")
		for item: Array in lst:
			ts.append(item[0])
			vs.append(item[1])
			es.append(item[2])
		if not c.loop and lst[lst.size() - 1][0] < 0.9999 and not d.get("hold", false):
			ts.append(1.0)
			vs.append(null)
			es.append(StringName(d.get("recover_ease", &"inout")))
		if c.loop:
			# Unroll periodic keys so evaluation never needs to wrap.
			var m := ts.size()
			var ts2 := PackedFloat32Array()
			var vs2: Array = []
			var es2: Array = []
			for k in range(maxi(m - 2, 0), m):
				ts2.append(ts[k] - 1.0)
				vs2.append(vs[k])
				es2.append(es[k])
			for k in m:
				ts2.append(ts[k])
				vs2.append(vs[k])
				es2.append(es[k])
			for k in mini(2, m):
				ts2.append(ts[k] + 1.0)
				vs2.append(vs[k])
				es2.append(es[k])
			ts = ts2
			vs = vs2
			es = es2
		c.tracks[ci] = {"t": ts, "v": vs, "e": es}
	return c


## Copy of this clip under another name (tracks are shared, read-only).
func duplicate_as(new_name: StringName) -> AnimClip:
	var c := AnimClip.new()
	c.name = new_name
	c.length = length
	c.loop = loop
	c.mask_name = mask_name
	c.mask = mask
	c.events = events
	c.plants = plants
	c.root = root
	c.blend_in = blend_in
	c.blend_out = blend_out
	c.next = next
	c.then_state = then_state
	c.state_clip = state_clip
	c.meta = meta
	c.tracks = tracks
	return c


## Writes the clip pose at normalized time `t` into `out` (base = layer below).
func evaluate(t: float, base: RigPose, out: RigPose) -> void:
	out.copy_from(base)
	for ci: int in tracks:
		out.v[ci] = _eval_track(tracks[ci], t, base.v[ci], P.EULER_CHANNELS.has(ci))


func _eval_track(tr: Dictionary, t: float, base_val: Variant, euler: bool = false) -> Variant:
	var ts: PackedFloat32Array = tr["t"]
	var vs: Array = tr["v"]
	var es: Array = tr["e"]
	var n := ts.size()
	if n == 1:
		return vs[0] if vs[0] != null else base_val
	if loop:
		t = fposmod(t, 1.0)
	if t <= ts[0]:
		return _val(vs, 0, base_val)
	if t >= ts[n - 1]:
		return _val(vs, n - 1, base_val)
	var j := 0
	while j < n - 2 and t >= ts[j + 1]:
		j += 1
	var u2 := (t - ts[j]) / maxf(ts[j + 1] - ts[j], 1e-5)
	u2 = ease_u(es[j + 1], clampf(u2, 0.0, 1.0))
	var j0 := maxi(j - 1, 0)
	var j3 := mini(j + 2, n - 1)
	var tt0 := ts[j0] if j0 < j else ts[j] - (ts[j + 1] - ts[j])
	var tt3 := ts[j3] if j3 > j + 1 else ts[j + 1] + (ts[j + 1] - ts[j])
	var p0: Variant = _val(vs, j0, base_val)
	var p3: Variant = _val(vs, j3, base_val)
	if j0 == j:
		p0 = _val(vs, j, base_val)
	if j3 == j + 1:
		p3 = _val(vs, j + 1, base_val)
	var p1: Variant = _val(vs, j, base_val)
	var p2: Variant = _val(vs, j + 1, base_val)
	if euler and (vs[j] == null or vs[j + 1] == null):
		# Blending between the base pose and a (possibly multi-turn) key: take
		# the shortest arc so spins never unwind.
		var a: Vector3 = p1
		var b: Vector3 = p2
		if vs[j] == null:
			a = b + _wrap3(a - b)
		else:
			b = a + _wrap3(b - a)
		p1 = a
		p2 = b
		p0 = a
		p3 = b
	return _hermite(p0, p1, p2, p3, tt0, ts[j], ts[j + 1], tt3, u2)


static func _wrap3(d: Vector3) -> Vector3:
	return Vector3(wrapf(d.x, -180.0, 180.0), wrapf(d.y, -180.0, 180.0), wrapf(d.z, -180.0, 180.0))


static func _val(vs: Array, i: int, base_val: Variant) -> Variant:
	var x: Variant = vs[i]
	return base_val if x == null else x


## Non-uniform Catmull-Rom (Hermite with time-scaled tangents).
static func _hermite(p0: Variant, p1: Variant, p2: Variant, p3: Variant, t0: float, t1: float, t2: float, t3: float, u: float) -> Variant:
	var seg := maxf(t2 - t1, 1e-5)
	var m1: Variant = (p2 - p0) * (seg / maxf(t2 - t0, 1e-5))
	var m2: Variant = (p3 - p1) * (seg / maxf(t3 - t1, 1e-5))
	var u2 := u * u
	var u3 := u2 * u
	return p1 * (2.0 * u3 - 3.0 * u2 + 1.0) + m1 * (u3 - 2.0 * u2 + u) + p2 * (-2.0 * u3 + 3.0 * u2) + m2 * (u3 - u2)


## Root motion offset (meters, right/up/forward) at normalized time t.
func root_at(t: float) -> Vector3:
	if root.is_empty():
		return Vector3.ZERO
	if t <= root[0][0]:
		return root[0][1]
	for i in range(1, root.size()):
		if t <= root[i][0]:
			var a: Array = root[i - 1]
			var b: Array = root[i]
			var u := (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-5)
			u = u * u * (3.0 - 2.0 * u)
			return (a[1] as Vector3).lerp(b[1], u)
	return root[root.size() - 1][1]


func duration(speed: float = 1.0) -> float:
	return length / maxf(speed, 0.01)


func has_event(event_name: StringName) -> bool:
	for e: Array in events:
		if e[1] == event_name:
			return true
	return false


## Normalized time of the first event with this name (-1 if none).
func event_time(event_name: StringName) -> float:
	for e: Array in events:
		if e[1] == event_name:
			return e[0]
	return -1.0
