class_name AirWindField
extends Node
## Short-lived airbending wind impulses for the world shaders: grass flattens,
## shrubs and trees bend away and spring back, banners and awnings snap out.
## Four slots are written every frame into the global uniforms
## `air_impulse_a` / `air_impulse_b` / `air_impulse_on` (WorldShaderGlobals),
## read by src/fx/air/air_wind.gdshaderinc (vegetation, grass, cloth shaders).
##
##   var id := AirWindField.add(self, pos, 4.0, 22.0, AirWindField.RADIAL)   # one-shot burst
##   var g := AirWindField.add(self, head, 2.5, 18.0, AirWindField.DIRECTIONAL, dir, INF)
##   AirWindField.move(g, proj.global_position)      # moving gust head (held: INF)
##   AirWindField.release(g)                          # let it spring back and fade
##
## Strength is an extra wind speed (m/s): it rises in 0.06 s, holds, then decays as
## a damped spring (the plants swing back past rest before settling).

enum { DIRECTIONAL, RADIAL, VORTEX }

const SLOTS := 4
const RISE := 0.07
const DECAY := 0.32
const SPRING_HZ := 1.5
const LIFE_AFTER := 1.6
## A held impulse is released by itself after this long (safety).
const MAX_HOLD := 8.0

static var _ref: WeakRef = null
static var _next_id := 1
## Impulses started (tests / stats).
static var started := 0

## Each slot: {id, pos, radius, dir, mode, peak, t, hold, spin} or {} when free.
var slots: Array[Dictionary] = []


static func instance(from: Node) -> AirWindField:
	var f: AirWindField = _ref.get_ref() as AirWindField if _ref != null else null
	if f != null and is_instance_valid(f) and f.is_inside_tree():
		return f
	if from == null or not from.is_inside_tree():
		return null
	var root := FxLib.root(from)
	f = root.get_node_or_null("AirWindField") as AirWindField
	if f == null:
		f = AirWindField.new()
		f.name = "AirWindField"
		root.add_child(f)
	_ref = weakref(f)
	return f


## Starts an impulse. mode: DIRECTIONAL (along `dir`), RADIAL (out from `pos`), VORTEX
## (swirl + draw in; dir.x sign = spin). hold: seconds at full strength (INF = until
## release()). Returns the impulse id (0 when there is no scene).
static func add(from: Node, pos: Vector3, radius: float, strength: float, mode: int = RADIAL, dir: Vector3 = Vector3.ZERO,
		hold: float = 0.12) -> int:
	var f := instance(from)
	if f == null:
		return 0
	return f._add(pos, radius, strength, mode, dir, hold, from)


static func move(id: int, pos: Vector3, dir: Vector3 = Vector3.ZERO) -> void:
	var f: AirWindField = _ref.get_ref() as AirWindField if _ref != null else null
	if f == null or id == 0:
		return
	for s in f.slots:
		if int(s.get("id", -1)) == id:
			s["pos"] = pos
			if dir != Vector3.ZERO:
				s["dir"] = Vector2(dir.x, dir.z).normalized()
			return


## Ends the hold of `id`: the impulse springs back and fades.
static func release(id: int) -> void:
	var f: AirWindField = _ref.get_ref() as AirWindField if _ref != null else null
	if f == null or id == 0:
		return
	for s in f.slots:
		if int(s.get("id", -1)) == id and float(s["hold"]) == INF:
			s["hold"] = maxf(0.0, float(s["t"]) - RISE)


## Current shader strength of an impulse (0 if gone).
static func strength_of(id: int) -> float:
	var f: AirWindField = _ref.get_ref() as AirWindField if _ref != null else null
	if f == null:
		return 0.0
	for s in f.slots:
		if int(s.get("id", -1)) == id:
			return _envelope(s)
	return 0.0


static func live_count() -> int:
	var f: AirWindField = _ref.get_ref() as AirWindField if _ref != null else null
	if f == null:
		return 0
	var n := 0
	for s in f.slots:
		if not s.is_empty():
			n += 1
	return n


func _ready() -> void:
	WorldShaderGlobals.ensure()
	slots.resize(SLOTS)
	for i in SLOTS:
		slots[i] = {}
	process_priority = 100


func _add(pos: Vector3, radius: float, strength: float, mode: int, dir: Vector3, hold: float, owner_node: Node = null) -> int:
	if slots.size() < SLOTS:
		_ready()
	var best := -1
	var weakest := INF
	for i in SLOTS:
		if slots[i].is_empty():
			best = i
			break
		var e := absf(_envelope(slots[i])) * (0.5 if float(slots[i]["hold"]) != INF else 1.0)
		if e < weakest:
			weakest = e
			best = i
	var id := _next_id
	_next_id += 1
	started += 1
	var d2 := Vector2(dir.x, dir.z)
	slots[best] = {"id": id, "pos": pos, "radius": maxf(radius, 0.3), "dir": d2.normalized() if d2.length() > 0.01 else Vector2.ZERO,
		"mode": mode, "peak": strength, "t": 0.0, "hold": hold, "spin": signf(dir.x) if mode == VORTEX and dir.x != 0.0 else 1.0,
		"owner": weakref(owner_node) if owner_node != null else null}
	_write()
	return id


static func _envelope(s: Dictionary) -> float:
	if s.is_empty():
		return 0.0
	var t := float(s["t"])
	var peak := float(s["peak"])
	if t < RISE:
		return peak * smoothstep(0.0, RISE, t)
	var u := t - RISE - float(s["hold"])
	if u <= 0.0:
		return peak
	return peak * exp(-u / DECAY) * cos(TAU * SPRING_HZ * u)


func _process(delta: float) -> void:
	var any := false
	for i in SLOTS:
		var s := slots[i]
		if s.is_empty():
			continue
		s["t"] = float(s["t"]) + delta
		var hold := float(s["hold"])
		var own: Variant = s.get("owner")
		var gone: bool = own != null and not is_instance_valid((own as WeakRef).get_ref())
		if hold == INF and (float(s["t"]) > MAX_HOLD or gone):
			# Its owner never released it (freed mid-gust): let it go.
			hold = maxf(0.0, float(s["t"]) - RISE)
			s["hold"] = hold
		if hold != INF and float(s["t"]) > RISE + hold + LIFE_AFTER:
			slots[i] = {}
			continue
		any = true
	_write()
	if not any:
		set_process(false)


func _write() -> void:
	var a: Array[Vector4] = []
	var b: Array[Vector4] = []
	var on := false
	for i in SLOTS:
		var s: Dictionary = slots[i] if i < slots.size() else {}
		if s.is_empty():
			a.append(Vector4.ZERO)
			b.append(Vector4.ZERO)
			continue
		on = true
		var p: Vector3 = s["pos"]
		var d: Vector2 = s["dir"]
		var mode := int(s["mode"])
		if mode == VORTEX:
			d = Vector2(float(s["spin"]), 0.0)
		a.append(Vector4(p.x, p.y, p.z, float(s["radius"])))
		b.append(Vector4(d.x, d.y, float(mode), _envelope(s)))
	if on:
		set_process(true)
	RenderingServer.global_shader_parameter_set(&"air_impulse_a", Projection(a[0], a[1], a[2], a[3]))
	RenderingServer.global_shader_parameter_set(&"air_impulse_b", Projection(b[0], b[1], b[2], b[3]))
	RenderingServer.global_shader_parameter_set(&"air_impulse_on", 1.0 if on else 0.0)


func _exit_tree() -> void:
	# Never leave a gust frozen in the shaders after a scene change.
	RenderingServer.global_shader_parameter_set(&"air_impulse_on", 0.0)
