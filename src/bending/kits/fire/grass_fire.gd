class_name GrassFire
extends Node3D
## Grass and brush fires with a strict budget (docs/modules/bending_fire.md
## "Grass fires"). Fire reaching dry grass (FireEnv.is_burnable) lights a cell of a
## 1.6 m grid; burning cells spread to neighbours (downwind first) for a few
## generations, burn 4.5-7 s with sustained flames and smoke, then leave a charred
## mark and stay burnt (cannot re-ignite) for a while. Never a runaway fire:
##
## * MAX_CELLS burning at once per effects tier (8 / 14 / 20 / 24), PER_FIRE cells per
##   ignition, GENERATIONS rings of spread, a cooldown on burnt ground, nothing in rain.
## * One MultiMesh draws every flame (one draw call), smoke is one small emitter per cell,
##   at most two flickering lights for the biggest fires.
## * Each cell is in group &"extinguishable" (WaterEnv / FireEnv.extinguish) and carries a
##   FireHitProxy: water hits, strong gusts and heavy earth blows put it out.
## * Standing in it sets you alight (FireStatus) unless it is your own team's fire.
##
##   GrassFire.ignite(ctx, ground_point, 1.0)     # FireEnv.heat() calls this
##   GrassFire.burning_count(); GrassFire.instance(self).clear()

const CELL := 1.6
const MAX_CELLS: Array[int] = [8, 14, 20, 24]
const PER_FIRE := 12
const GENERATIONS := 3
const BURN_TIME := Vector2(4.5, 7.0)
const SPREAD_EVERY := 0.85
const SPREAD_CHANCE := 0.45
const BURNT_COOLDOWN := 90.0
const FLAMES_PER_CELL := 4
const HURT_EVERY := 0.5
const BURN_SECONDS := 2.5
const MAX_LIGHTS := 2

## Cells lit since start (tests).
static var cells_lit := 0
static var _inst: WeakRef = null

var cells: Dictionary = {}         # Vector2i -> GrassFireCell
var burnt: Dictionary = {}         # Vector2i -> clock when it may burn again
var fires: Dictionary = {}         # fire id -> {"cells": int, "team": int, "source": WeakRef}
var clock := 0.0
var mm_inst: MultiMeshInstance3D
var mm: MultiMesh
var lights: Array[OmniLight3D] = []
var _next_fire := 1
var _capacity := 0


static func instance(from: Node) -> GrassFire:
	var g: GrassFire = _inst.get_ref() as GrassFire if _inst != null else null
	if g != null and is_instance_valid(g) and g.is_inside_tree():
		return g
	if from == null or not from.is_inside_tree():
		return null
	g = GrassFire.new()
	g.name = "GrassFire"
	FxLib.root(from).add_child(g)
	_inst = weakref(g)
	return g


## The scene's grass-fire manager if one exists (null otherwise; never creates one).
static func current() -> GrassFire:
	var g: GrassFire = _inst.get_ref() as GrassFire if _inst != null else null
	return g if g != null and is_instance_valid(g) and g.is_inside_tree() else null


static func max_cells() -> int:
	return MAX_CELLS[FxLib.tier()]


static func burning_count() -> int:
	var g: GrassFire = _inst.get_ref() as GrassFire if _inst != null else null
	return g.cells.size() if g != null and is_instance_valid(g) else 0


static func key_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


static func center_of(k: Vector2i) -> Vector2:
	return Vector2((k.x + 0.5) * CELL, (k.y + 0.5) * CELL)


## Lights the grass at ground point `p` (a new fire). Returns true if a cell caught.
static func ignite(ctx: BendingContext, p: Vector3, power: float = 1.0) -> bool:
	if ctx == null or not ctx.is_valid():
		return false
	var g := instance(ctx.caster)
	if g == null:
		return false
	var id := g._next_fire
	g._next_fire += 1
	g.fires[id] = {"cells": 0, "team": ctx.team, "source": weakref(ctx.caster), "budget": int(round(PER_FIRE * clampf(power, 0.4, 1.5)))}
	return g._light(key_of(p), p.y, id, 0)


func _ready() -> void:
	_capacity = MAX_CELLS[3] * FLAMES_PER_CELL
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = FireFx.quad()
	mm.instance_count = _capacity
	mm.visible_instance_count = 0
	mm_inst = MultiMeshInstance3D.new()
	mm_inst.name = "Flames"
	mm_inst.multimesh = mm
	mm_inst.material_override = FireFx.flame_material(0.37, 0.8)
	mm_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mm_inst)
	for i in MAX_LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.2)
		l.omni_range = 9.0
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		l.light_energy = 0.0
		l.visible = false
		add_child(l)
		lights.append(l)


func _light(k: Vector2i, y_hint: float, fire_id: int, gen: int) -> bool:
	if cells.has(k) or cells.size() >= max_cells():
		return false
	if burnt.has(k) and clock < float(burnt[k]):
		return false
	var f: Dictionary = fires.get(fire_id, {})
	if f.is_empty() or int(f["cells"]) >= int(f["budget"]):
		return false
	var c2 := center_of(k)
	var probe := Vector3(c2.x, y_hint, c2.y)
	var gy := _ground_y(probe)
	var gp := Vector3(c2.x, gy, c2.y)
	if not FireEnv.is_burnable(gp):
		return false
	var cell := GrassFireCell.new()
	cell.key = k
	cell.fire_id = fire_id
	cell.gen = gen
	cell.life = randf_range(BURN_TIME.x, BURN_TIME.y)
	cell.next_spread = SPREAD_EVERY * randf_range(0.7, 1.2)
	cell.next_hurt = randf() * HURT_EVERY
	cell.manager = self
	cell.seed_v = randf()
	add_child(cell)
	cell.global_position = gp
	cell.setup()
	cells[k] = cell
	f["cells"] = int(f["cells"]) + 1
	cells_lit += 1
	return true


func _ground_y(p: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 6.0, Layers.WORLD)
	var r := space.intersect_ray(q)
	if not r.is_empty():
		return (r["position"] as Vector3).y
	return WorldData.get_height(p.x, p.z)


## A cell burnt out or was put out: leave the mark, start the burnt cooldown.
func _cell_done(cell: GrassFireCell, doused: bool) -> void:
	cells.erase(cell.key)
	burnt[cell.key] = clock + BURNT_COOLDOWN
	FireMarks.burn(self, cell.global_position, CELL * 0.62, {"glow": 0.2 if doused else 1.0})
	if doused:
		FireEnv.steam(self, cell.global_position + Vector3.UP * 0.3, 0.8)
	else:
		FxBurst.spawn(self, &"smoke", cell.global_position + Vector3.UP * 0.4, {"count": 0.5, "size": 0.8})
	cell.queue_free()


func clear() -> void:
	for k: Vector2i in cells.keys():
		(cells[k] as GrassFireCell).queue_free()
	cells.clear()
	burnt.clear()
	fires.clear()
	mm.visible_instance_count = 0


func _physics_process(delta: float) -> void:
	clock += delta
	if cells.is_empty():
		return
	var wind := _wind()
	for k: Vector2i in cells.keys():
		var cell: GrassFireCell = cells.get(k)
		if cell == null or not is_instance_valid(cell):
			cells.erase(k)
			continue
		cell.age += delta
		if cell.age >= cell.life:
			_cell_done(cell, false)
			continue
		cell.next_spread -= delta
		if cell.next_spread <= 0.0:
			cell.next_spread = SPREAD_EVERY * randf_range(0.8, 1.25)
			_spread(cell, wind)
		cell.next_hurt -= delta
		if cell.next_hurt <= 0.0:
			cell.next_hurt = HURT_EVERY
			_hurt(cell)


func _spread(cell: GrassFireCell, wind: Vector2) -> void:
	if cell.gen >= GENERATIONS or cell.age > cell.life * 0.75:
		return
	var f: Dictionary = fires.get(cell.fire_id, {})
	if f.is_empty() or int(f["cells"]) >= int(f["budget"]):
		return
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var chance := SPREAD_CHANCE * (0.7 if d.x != 0 and d.y != 0 else 1.0)
		if wind.length_squared() > 0.01:
			chance *= 1.0 + 0.8 * Vector2(d).normalized().dot(wind.normalized())
		if randf() < chance:
			_light(cell.key + d, cell.global_position.y, cell.fire_id, cell.gen + 1)


func _hurt(cell: GrassFireCell) -> void:
	var f: Dictionary = fires.get(cell.fire_id, {})
	var team := int(f.get("team", Combat.Team.NEUTRAL))
	var src_ref: Variant = f.get("source")
	var src: Node = (src_ref as WeakRef).get_ref() as Node if src_ref is WeakRef else null
	var mask := (Layers.PLAYER | Layers.ENEMY | Layers.COMPANION | Layers.WILDLIFE)
	for t in Combat.query_sphere(get_world_3d(), cell.global_position + Vector3.UP * 0.5, CELL * 0.55, mask):
		if "team" in t and int(t.get("team")) == team and team != Combat.Team.NEUTRAL:
			continue
		FireStatus.ignite(t, BURN_SECONDS, src, team)


func _wind() -> Vector2:
	var r := FireEnv.renderer(self)
	if r != null and r.has_method("get_wind"):
		var w: Variant = r.call("get_wind")
		if w is Vector2:
			return w
	return Vector2.ZERO


func _process(_delta: float) -> void:
	_update_flames()


## Rewrites the flame instances (transform, white colour, custom = (seed, age)).
func _update_flames() -> void:
	if cells.is_empty():
		mm.visible_instance_count = 0
		for l in lights:
			l.visible = false
		return
	var buf := PackedFloat32Array()
	buf.resize(_capacity * 20)
	var n := 0
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var best: Array = []
	for k: Vector2i in cells:
		var cell: GrassFireCell = cells[k]
		if not is_instance_valid(cell):
			continue
		var grow := clampf(cell.age / 0.45, 0.0, 1.0)
		var die := clampf((cell.life - cell.age) / 1.3, 0.0, 1.0)
		var size_k := grow * die
		var age := 1.0 - die
		for i in FLAMES_PER_CELL:
			if n >= _capacity:
				break
			var o: Vector3 = cell.offsets[i]
			var h := (0.7 + 0.55 * o.y) * (0.35 + 0.65 * size_k) * (0.9 + 0.12 * sin(clock * 7.0 + float(i) * 1.7 + cell.seed_v * 9.0))
			var w := h * 0.62
			var p := cell.global_position + Vector3(o.x, h * 0.42, o.z)
			var base := n * 20
			buf[base + 0] = w
			buf[base + 1] = 0.0
			buf[base + 2] = 0.0
			buf[base + 3] = p.x
			buf[base + 4] = 0.0
			buf[base + 5] = h
			buf[base + 6] = 0.0
			buf[base + 7] = p.y
			buf[base + 8] = 0.0
			buf[base + 9] = 0.0
			buf[base + 10] = w
			buf[base + 11] = p.z
			buf[base + 12] = 1.0
			buf[base + 13] = 1.0
			buf[base + 14] = 1.0
			buf[base + 15] = 1.0
			buf[base + 16] = cell.seed_v + float(i) * 0.21
			buf[base + 17] = age * 0.85
			buf[base + 18] = 0.0
			buf[base + 19] = cell.seed_v
			lo = lo.min(p - Vector3(w, h, w))
			hi = hi.max(p + Vector3(w, h, w))
			n += 1
		best.append([size_k, cell.global_position])
	mm.buffer = buf
	mm.visible_instance_count = n
	if n > 0:
		mm_inst.custom_aabb = AABB(lo - global_position, hi - lo)
	# Lights at the brightest cells (spread apart).
	best.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var used: Array[Vector3] = []
	var li := 0
	var allowed := MAX_LIGHTS if FxLib.tier() >= 1 else 1
	for e: Array in best:
		if li >= allowed:
			break
		var pos: Vector3 = e[1]
		var far := true
		for u in used:
			if u.distance_to(pos) < 5.0:
				far = false
		if not far:
			continue
		used.append(pos)
		var l := lights[li]
		l.visible = true
		l.global_position = pos + Vector3.UP * 1.0
		l.light_energy = 1.4 * float(e[0]) * (0.85 + 0.15 * sin(clock * 13.0 + li * 2.0))
		li += 1
	for j in range(li, lights.size()):
		lights[j].visible = false


## One burning cell of grass: its smoke, its hit proxy and the extinguish hook.
class GrassFireCell extends Node3D:
	var key := Vector2i.ZERO
	var fire_id := 0
	var gen := 0
	var age := 0.0
	var life := 5.0
	var next_spread := 0.0
	var next_hurt := 0.0
	var seed_v := 0.0
	var manager: GrassFire = null
	var offsets: Array[Vector3] = []
	var extinguish_radius := GrassFire.CELL * 0.6
	var _out := false

	func setup() -> void:
		add_to_group(FireEnv.EXTINGUISHABLE)
		for i in GrassFire.FLAMES_PER_CELL:
			var a := randf() * TAU
			var r := sqrt(randf()) * GrassFire.CELL * 0.4
			offsets.append(Vector3(cos(a) * r, randf(), sin(a) * r))
		var proxy := FireHitProxy.make(GrassFire.CELL * 0.6, _on_hit)
		proxy.position = Vector3.UP * 0.5
		add_child(proxy)
		if FxLib.scale() > 0.3:
			add_child(_smoke())

	func _on_hit(hit: HitInfo) -> void:
		if FireHitProxy.reaction(hit) == &"douse":
			extinguish(hit.source, hit.position)

	func is_burning() -> bool:
		return not _out

	## Extinguish hook (WaterEnv / FireEnv): put out, leaves a cold mark.
	func extinguish(_by: Node = null, _at: Vector3 = Vector3.ZERO) -> bool:
		if _out or manager == null or not is_instance_valid(manager):
			return false
		_out = true
		FireEnv.extinguished += 1
		manager._cell_done(self, true)
		return true

	func _smoke() -> GPUParticles3D:
		var p := GPUParticles3D.new()
		p.amount = FxLib.amount(5)
		p.lifetime = 2.2
		p.local_coords = false
		p.position = Vector3.UP * 0.9
		p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 8, 6))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.5
		pm.direction = Vector3.UP
		pm.spread = 15.0
		pm.initial_velocity_min = 0.8
		pm.initial_velocity_max = 1.4
		pm.gravity = Vector3(0.3, 0.6, 0.0)
		pm.damping_min = 0.3
		pm.damping_max = 0.6
		pm.scale_min = 0.7
		pm.scale_max = 1.1
		var sc := Curve.new()
		sc.add_point(Vector2(0.0, 0.5))
		sc.add_point(Vector2(1.0, 1.6))
		var ct := CurveTexture.new()
		ct.curve = sc
		pm.scale_curve = ct
		var g := Gradient.new()
		g.set_color(0, Color(0.22, 0.19, 0.17, 0.0))
		g.add_point(0.15, Color(0.22, 0.19, 0.17, 0.42))
		g.set_color(g.get_point_count() - 1, Color(0.36, 0.34, 0.33, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
		p.process_material = pm
		p.draw_pass_1 = FireFx.quad()
		var s := StandardMaterial3D.new()
		s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		s.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		s.billboard_keep_scale = true
		s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		s.vertex_color_use_as_albedo = true
		s.albedo_texture = FxLib.soft_dot()
		p.material_override = s
		p.emitting = true
		return p
