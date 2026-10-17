class_name WorldFires
extends RefCounted
## Interactive world fires (docs/qa/integration_fixes.md "World fires"): the braziers,
## torches, lanterns and campfires built into settlement, outpost and POI cell meshes answer
## to bending - firebending lights an unlit one, water and strong wind put a lit one out, and
## a fire that was put out relights after a while.
##
## * **Spots** come from BuildingKit.add_fire (braziers and lanterns record themselves, fire-pit
##   recipes call it): KitResult / SettlementProvider register them here per streamed cell
##   (`register(cell_root, records)`), and they are forgotten when the cell is released.
## * **State**: every fire is lit as baked, except a share of braziers (COLD_SHARE, picked by
##   position) that stand cold by day and are lit at dusk. Runtime changes are overrides with a
##   timer: put out -> relights after 30-60 s; a cold brazier lit by day -> burns 60-90 s.
##   Overrides only exist near the player (MASK_RANGE); beyond it fires show their baked state.
## * **Look**: no extra meshes. A fire that is out is listed in the `fire_mask` uniform of the
##   shared kit_glow material (flames collapse into a dark coal bed, lantern paper goes dark)
##   and of the night-glow material (its night glow sprite collapses); its LightBudget light is
##   kept off; the cell's smoke / embers particles stop. So night glows always match the state.
## * **Interaction**: the nearest fires within INTERACT_RANGE (PROXIES by detail level) get a
##   pooled WorldFireSpot at the flame: the shared IGNITE / EXTINGUISH hooks (FireEnv.heat,
##   WaterEnv.extinguish, AirEnv / FireEnv.extinguish) plus a FireHitProxy (any bending hit).
##
##   WorldFires.register(root, [{"position": Vector3, "kind": &"brazier", "radius": 0.5}])
##   WorldFires.extinguish_at(p, 2.0, by); WorldFires.ignite_at(p, 2.0, by)    # scripts
##   WorldFires.spots_near(p, 30.0); WorldFires.is_lit(id)
##   WorldFires.ensure().fire_extinguished.connect(func(pos: Vector3, by: Node) -> void: ...)

const KINDS: Array[StringName] = [&"brazier", &"torch", &"lantern", &"campfire"]
const GRID := 32.0
## Fires with a stand-in (hooks + hit proxy) are the nearest ones within this distance.
const INTERACT_RANGE := 60.0
## Runtime state (and the shader mask) is kept for fires within this distance of the camera.
const MASK_RANGE := 90.0
## Size of the fire_mask uniform arrays (kit_glow / night_glow shaders).
const MASK_SIZE := 32
const UPDATE_INTERVAL := 0.2
## Share of braziers that stand cold by day (lit at dusk), so a firebender finds fires to light.
const COLD_SHARE := 0.35
## Stand-ins by Settings.detail_level() (0 = mobile preset .. 3 = ultra).
const PROXIES: Array[int] = [8, 12, 16, 24]

## id -> {"id", "pos" (world flame base), "kind", "radius", "owner" (instance id), "cold"}
static var _spots: Dictionary = {}
static var _grid: Dictionary = {}       # Vector2i -> Array[int]
static var _owners: Dictionary = {}     # owner instance id -> Array[int]
static var _next_id := 1
static var _mgr: WeakRef = null
## -1 follows the sky (LightBudget.darkness), 0 forces day, 1 forces night (tests, scripts).
static var time_override := -1
## Fires lit / put out since start (tests, docs).
static var lit_count := 0
static var doused_count := 0


# --- registry ---------------------------------------------------------------------------------

## Registers the open fires of `owner` (records in owner-local space: {"position", "kind",
## "radius"}); they are forgotten when the owner leaves the tree. Registration waits for the
## owner to enter the tree when it is not inside yet (its transform is read then).
static func register(owner: Node, records: Array) -> void:
	if owner == null or not is_instance_valid(owner) or records.is_empty():
		return
	if not owner.is_inside_tree():
		owner.tree_entered.connect(register.bind(owner, records), CONNECT_ONE_SHOT)
		return
	var xf := (owner as Node3D).global_transform if owner is Node3D else Transform3D.IDENTITY
	var oid := owner.get_instance_id()
	var fresh := not _owners.has(oid)
	var ids: Array = _owners.get(oid, [])
	for r: Dictionary in records:
		var kind := StringName(r.get("kind", &"campfire"))
		var pos: Vector3 = xf * (r["position"] as Vector3)
		var id := _next_id
		_next_id += 1
		_spots[id] = {"id": id, "pos": pos, "kind": kind, "radius": float(r.get("radius", 0.5)), "owner": oid,
			"cold": kind == &"brazier" and _unit(pos) < COLD_SHARE}
		var c := _cell(pos)
		if not _grid.has(c):
			_grid[c] = []
		(_grid[c] as Array).append(id)
		ids.append(id)
	_owners[oid] = ids
	if fresh:
		owner.tree_exiting.connect(_forget_owner.bind(oid), CONNECT_ONE_SHOT)
	ensure()


static func _forget_owner(oid: int) -> void:
	var ids: Array = _owners.get(oid, [])
	_owners.erase(oid)
	for id: int in ids:
		var s: Dictionary = _spots.get(id, {})
		if s.is_empty():
			continue
		var c := _cell(s["pos"])
		if _grid.has(c):
			(_grid[c] as Array).erase(id)
			if (_grid[c] as Array).is_empty():
				_grid.erase(c)
		_spots.erase(id)


## Forgets everything (tests).
static func clear() -> void:
	_spots.clear()
	_grid.clear()
	_owners.clear()
	var m := manager()
	if m:
		m.reset()


static func spot_count() -> int:
	return _spots.size()


static func get_spot(id: int) -> Dictionary:
	return _spots.get(id, {})


## Spots within `r` of `p`, nearest first.
static func spots_near(p: Vector3, r: float) -> Array:
	var out: Array = []
	var c0 := _cell(p - Vector3(r, 0, r))
	var c1 := _cell(p + Vector3(r, 0, r))
	var r2 := r * r
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for id: int in _grid.get(Vector2i(cx, cz), []):
				var s: Dictionary = _spots[id]
				var d2 := (s["pos"] as Vector3).distance_squared_to(p)
				if d2 <= r2:
					out.append([d2, s])
	out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	return out.map(func(e: Array) -> Dictionary: return e[1])


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / GRID), floori(p.z / GRID))


static func _unit(p: Vector3) -> float:
	return ContentHash.unit(ContentHash.hash4(int(round(p.x * 4.0)), int(round(p.z * 4.0)), 0x5F17E))


# --- state --------------------------------------------------------------------------------------

static func is_day() -> bool:
	if time_override >= 0:
		return time_override == 0
	return LightBudget.darkness() < 0.4


## Lit as baked / by the time of day, before any runtime change.
static func default_lit(s: Dictionary) -> bool:
	return not (bool(s.get("cold", false)) and is_day())


static func is_lit(id: int) -> bool:
	var s: Dictionary = _spots.get(id, {})
	if s.is_empty():
		return false
	var m := manager()
	if m != null and m.overrides.has(id):
		return bool((m.overrides[id] as Dictionary)["lit"])
	return default_lit(s)


## Puts fire `id` out (water, wind, scripts). True if it was burning.
static func extinguish(id: int, by: Node = null) -> bool:
	if not _spots.has(id) or not is_lit(id):
		return false
	var m := ensure()
	if m == null:
		return false
	var s: Dictionary = _spots[id]
	m.set_override(id, false, m.clock + relight_time(s))
	doused_count += 1
	m.feedback(s, false, true)
	m.fire_extinguished.emit(s["pos"], by)
	return true


## Lights fire `id` (firebending, scripts). True if it caught.
static func ignite(id: int, by: Node = null) -> bool:
	if not _spots.has(id) or is_lit(id):
		return false
	var m := ensure()
	if m == null:
		return false
	var s: Dictionary = _spots[id]
	if default_lit(s):
		m.clear_override(id)                      # a fire that was put out, relit
	else:
		m.set_override(id, true, m.clock + burn_time(s))   # a cold brazier lit by day
	lit_count += 1
	m.feedback(s, true, true)
	m.fire_ignited.emit(s["pos"], by)
	return true


## Puts out every fire within `radius` of `center` (no stand-in needed). Returns how many.
static func extinguish_at(center: Vector3, radius: float, by: Node = null) -> int:
	var n := 0
	for s: Dictionary in spots_near(center, radius + 1.0):
		if (s["pos"] as Vector3).distance_to(center) <= radius + float(s["radius"]) and extinguish(s["id"], by):
			n += 1
	return n


## Lights every unlit fire within `radius` of `center`. Returns how many.
static func ignite_at(center: Vector3, radius: float, by: Node = null) -> int:
	var n := 0
	for s: Dictionary in spots_near(center, radius + 1.0):
		if (s["pos"] as Vector3).distance_to(center) <= radius + float(s["radius"]) and ignite(s["id"], by):
			n += 1
	return n


## Seconds until a fire that was put out burns again.
static func relight_time(s: Dictionary) -> float:
	var u := _unit((s["pos"] as Vector3) + Vector3(7.0, 0, 3.0))
	match StringName(s["kind"]):
		&"campfire":
			return lerpf(45.0, 60.0, u)
		&"lantern":
			return lerpf(25.0, 35.0, u)
	return lerpf(30.0, 45.0, u)


## Seconds a cold brazier lit by day keeps burning.
static func burn_time(s: Dictionary) -> float:
	return lerpf(60.0, 90.0, _unit((s["pos"] as Vector3) + Vector3(-5.0, 0, 11.0)))


# --- manager ------------------------------------------------------------------------------------

static func manager() -> Manager:
	var m: Manager = _mgr.get_ref() as Manager if _mgr != null else null
	return m if m != null and is_instance_valid(m) and not m.is_queued_for_deletion() else null


## The manager node (created on first use under the tree root, like LightBudget / FireStatus).
static func ensure() -> Manager:
	var m := manager()
	if m != null:
		return m
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	m = Manager.new()
	m.name = "WorldFires"
	tree.root.add_child.call_deferred(m)
	_mgr = weakref(m)
	return m


## Keeps the runtime state near the camera: timers, the shader mask, the lights, the
## stand-ins. Runs at 5 Hz, a few dozen spots each time.
class Manager extends Node:
	signal fire_ignited(position: Vector3, by: Node)
	signal fire_extinguished(position: Vector3, by: Node)

	## spot id -> {"lit": bool, "until": clock}
	var overrides: Dictionary = {}
	var clock := 0.0
	## The fires currently masked out (world flame base + signed radius), nearest first.
	var mask: PackedVector4Array = PackedVector4Array()
	## spot id -> WorldFireSpot
	var proxies: Dictionary = {}
	## Camera / player position used last update (tests can set `focus_override`).
	var focus := Vector3.INF
	var focus_override := Vector3.INF
	var _pool: Array[WorldFireSpot] = []
	var _t := 0.0
	var _was_day := true
	var _masked_ids: Dictionary = {}

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_PAUSABLE
		_was_day = WorldFires.is_day()
		LightBudget.suppress = _light_suppressed

	func _exit_tree() -> void:
		if LightBudget.suppress == Callable(self, &"_light_suppressed"):
			LightBudget.suppress = Callable()
		_apply_mask(PackedVector4Array())
		# pooled stand-ins live outside the tree: free them with the manager
		for sp in _pool:
			if is_instance_valid(sp):
				sp.free()
		_pool.clear()

	func reset() -> void:
		overrides.clear()
		for id: int in proxies.keys():
			_release_proxy(id)
		_masked_ids.clear()
		mask = PackedVector4Array()
		_apply_mask(mask)

	func set_override(id: int, lit: bool, until: float) -> void:
		overrides[id] = {"lit": lit, "until": until}
		_queue_update()

	func clear_override(id: int) -> void:
		overrides.erase(id)
		_queue_update()

	## State changes arrive from hit callbacks inside physics queries: the mask / stand-ins
	## update at the end of the frame (never add / remove areas while the space is queried).
	func _queue_update() -> void:
		if _queued:
			return
		_queued = true
		_flush.call_deferred()

	var _queued := false

	func _flush() -> void:
		_queued = false
		update_now()

	func _process(delta: float) -> void:
		clock += delta
		_t -= delta
		if _t > 0.0:
			return
		_t = WorldFires.UPDATE_INTERVAL
		update_now()

	## Re-evaluates everything now (also called on every state change and by tests).
	func update_now() -> void:
		focus = _focus()
		var day := WorldFires.is_day()
		if day != _was_day:
			_was_day = day
			_time_changed(day)
		if not focus.is_finite():
			if not mask.is_empty():
				mask = PackedVector4Array()
				_apply_mask(mask)
			return
		_expire()
		var near := WorldFires.spots_near(focus, WorldFires.MASK_RANGE)
		var new_mask := PackedVector4Array()
		var masked := {}
		for s: Dictionary in near:
			if new_mask.size() >= WorldFires.MASK_SIZE:
				break
			if not WorldFires.is_lit(int(s["id"])):
				var p: Vector3 = s["pos"]
				var r := float(s["radius"])
				new_mask.append(Vector4(p.x, p.y, p.z, -r if StringName(s["kind"]) == &"lantern" else r))
				masked[int(s["id"])] = true
		if new_mask != mask:
			_particles_follow(masked)
			mask = new_mask
			_masked_ids = masked
			_apply_mask(mask)
		_assign_proxies(near)

	func _focus() -> Vector3:
		if focus_override.is_finite():
			return focus_override
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam != null:
			return cam.global_position
		var p := get_tree().get_first_node_in_group(&"player") as Node3D if is_inside_tree() else null
		return p.global_position if p != null else Vector3.INF

	## Timers run out (a doused fire relights, a lit cold brazier burns out); far overrides drop.
	func _expire() -> void:
		for id: int in overrides.keys():
			var o: Dictionary = overrides[id]
			var s: Dictionary = WorldFires.get_spot(id)
			if s.is_empty():
				overrides.erase(id)
				continue
			var far := (s["pos"] as Vector3).distance_to(focus) > WorldFires.MASK_RANGE + 25.0
			if clock >= float(o["until"]) or far:
				overrides.erase(id)
				var now := WorldFires.default_lit(s)
				if not far and now != bool(o["lit"]):
					feedback(s, now, false)

	## Dusk lights the cold braziers near the camera (and dawn puts them out) with a little flare.
	func _time_changed(day: bool) -> void:
		if not focus.is_finite():
			return
		var n := 0
		for s: Dictionary in WorldFires.spots_near(focus, 40.0):
			if bool(s["cold"]) and not overrides.has(int(s["id"])) and n < 6:
				feedback(s, not day, false)
				n += 1

	func _assign_proxies(near: Array) -> void:
		var budget: int = WorldFires.PROXIES[clampi(Settings.detail_level(), 0, 3)]
		var want := {}
		for s: Dictionary in near:
			if want.size() >= budget:
				break
			if (s["pos"] as Vector3).distance_to(focus) <= WorldFires.INTERACT_RANGE:
				want[int(s["id"])] = s
		for id: int in proxies.keys():
			if not want.has(id):
				_release_proxy(id)
		for id: int in want:
			if proxies.has(id):
				continue
			var sp: WorldFireSpot = _pool.pop_back() if not _pool.is_empty() else WorldFireSpot.new()
			sp.name = "Fire_%d" % id
			if sp.get_parent() == null:
				add_child(sp)
			var s: Dictionary = want[id]
			sp.bind(id, s["pos"], float(s["radius"]))
			proxies[id] = sp

	func _release_proxy(id: int) -> void:
		var sp: WorldFireSpot = proxies.get(id)
		proxies.erase(id)
		if sp == null or not is_instance_valid(sp):
			return
		sp.release()
		remove_child(sp)
		_pool.append(sp)

	## Shared materials: the kit glow (flames / coals / lantern paper) and the night glows.
	func _apply_mask(m: PackedVector4Array) -> void:
		var arr := m.duplicate()
		arr.resize(WorldFires.MASK_SIZE)
		var mats: Array = [NationPalette.material(&"glow")]
		var ng := SettlementFx.glow_material()
		if ng != null:
			mats.append(ng)
		for mat: Variant in mats:
			if mat is ShaderMaterial:
				(mat as ShaderMaterial).set_shader_parameter(&"fire_mask", arr)
				(mat as ShaderMaterial).set_shader_parameter(&"fire_mask_count", m.size())
		LightBudget.refresh()

	## LightBudget filter: the light of a fire that is out stays off.
	func _light_suppressed(p: Vector3) -> bool:
		for m: Vector4 in mask:
			var reach := absf(m.w) + (0.9 if m.w > 0.0 else 0.3)
			if Vector3(m.x, m.y, m.z).distance_to(p) < reach:
				return true
		return false

	## Smoke / embers particles (PropFx group &"fire_fx") of fires that went out stop, and
	## start again when they are lit.
	func _particles_follow(masked: Dictionary) -> void:
		var changed: Array = []
		for id: int in masked:
			if not _masked_ids.has(id):
				changed.append([id, false])
		for id: int in _masked_ids:
			if not masked.has(id):
				changed.append([id, true])
		if changed.is_empty() or not is_inside_tree():
			return
		var fx := get_tree().get_nodes_in_group(&"fire_fx")
		if fx.is_empty():
			return
		for c: Array in changed:
			var s: Dictionary = WorldFires.get_spot(int(c[0]))
			if s.is_empty() or StringName(s["kind"]) != &"campfire":
				continue
			var p: Vector3 = s["pos"]
			for n in fx:
				var gp := n as GPUParticles3D
				if gp != null and Vector2(gp.global_position.x - p.x, gp.global_position.z - p.z).length() < 1.6 \
						and absf(gp.global_position.y - p.y) < 2.5:
					gp.emitting = bool(c[1])

	## Visible + audible change of state. `loud`: caused by bending (full burst); otherwise a
	## timer / dusk (a quieter flare or puff).
	func feedback(s: Dictionary, lit: bool, loud: bool) -> void:
		if not is_inside_tree():
			return
		var p: Vector3 = s["pos"]
		if focus.is_finite() and p.distance_to(focus) > WorldFires.INTERACT_RANGE:
			return
		var big := StringName(s["kind"]) == &"campfire" or StringName(s["kind"]) == &"brazier"
		var size := float(s["radius"]) * (1.6 if big else 1.0)
		if lit:
			FireFx.burst(self, p + Vector3.UP * 0.25, clampf(size, 0.35, 0.9) * (1.0 if loud else 0.6))
			FxBurst.spawn(self, &"embers", p + Vector3.UP * 0.3, {"count": 0.8 if loud else 0.4})
			Audio.play_bending(ElementDefs.Element.FIRE, &"ignite", p, -2.0 if loud else -9.0)
		else:
			if loud:
				FireEnv.steam(self, p + Vector3.UP * 0.2, clampf(size, 0.4, 1.0))
			FxBurst.spawn(self, &"smoke", p + Vector3.UP * 0.35, {"count": 0.7 if loud else 0.35, "size": 0.6})
