class_name FerryBoat
extends Node3D
## The ferry: a 16 m junk-style passenger boat built in code with the BuildingKit (lofted hull
## in the nation's colours, deck, stern cabin with a curved gable roof, mast with a battened
## sail that ripples in the world wind, lanterns, stern flag). Bow = -Z, waterline at y = 0.
##
##   var boat := FerryBoat.new(&"fire_nation")
##   add_child(boat)
##   boat.place(Vector3(x, 0, z), heading)      # heading: horizontal -Z direction
##   boat.set_deck_collision(true)              # passengers can stand on it (AnimatableBody3D)
##   player.teleport(boat.passenger_transform())
##
## Moored boats only bob (no collision); a sailing boat moves through `place()` every physics
## tick and its deck body carries whoever stands on it.

const LENGTH := 16.0
const HALF := LENGTH * 0.5
const BEAM := 4.8
const DECK_Y := 1.05
## Where the passenger stands (boat space): fore deck, facing the bow.
const PASSENGER := Vector3(0.0, DECK_Y, -4.3)

static var _meshes: Dictionary = {}       # nation -> ArrayMesh
static var _lights: Dictionary = {}       # nation -> Array[Dictionary]

var nation: StringName = &"neutral"
var bob := true
var visual: Node3D
var deck: AnimatableBody3D = null
var base_transform := Transform3D.IDENTITY

var _t := 0.0
var _seed := 0.0


func _init(p_nation: StringName = &"neutral") -> void:
	nation = p_nation
	_seed = randf() * 10.0


func _ready() -> void:
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh_for(nation)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.visibility_range_end = 900.0
	mi.visibility_range_end_margin = 40.0
	visual.add_child(mi)
	for l: Dictionary in (_lights.get(nation, []) as Array):
		visual.add_child(LightBudget.make_light(l))
	if base_transform == Transform3D.IDENTITY:
		base_transform = transform


## Shared hull mesh of a nation's ferry (built once).
static func mesh_for(p_nation: StringName) -> ArrayMesh:
	if _meshes.has(p_nation):
		return _meshes[p_nation]
	var res := build_kit(p_nation)
	var m := res.make_mesh()
	_meshes[p_nation] = m
	_lights[p_nation] = res.lights
	return m


## Positions the boat (waterline origin) facing `heading` (horizontal; -Z of the boat).
func place(pos: Vector3, heading: Vector3) -> void:
	var h := Vector3(heading.x, 0.0, heading.z)
	if h.length_squared() < 1e-6:
		h = -base_transform.basis.z
	var yaw := atan2(-h.x, -h.z)
	base_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	_apply()


## Adds / removes the walkable deck (AnimatableBody3D on Layers.WORLD, synced to physics).
func set_deck_collision(on: bool) -> void:
	if on and deck == null:
		deck = AnimatableBody3D.new()
		deck.name = "Deck"
		deck.sync_to_physics = true
		deck.collision_layer = Layers.WORLD
		deck.collision_mask = 0
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(BEAM * 0.82, 0.3, LENGTH * 0.8)
		cs.shape = b
		cs.position = Vector3(0, DECK_Y - 0.15, -0.4)
		deck.add_child(cs)
		# low bulwarks keep passengers aboard
		for sx in [-1.0, 1.0]:
			var w := CollisionShape3D.new()
			var wb := BoxShape3D.new()
			wb.size = Vector3(0.2, 1.4, LENGTH * 0.75)
			w.shape = wb
			w.position = Vector3(sx * BEAM * 0.43, DECK_Y + 0.6, -0.4)
			deck.add_child(w)
		add_child(deck)
	elif not on and deck != null:
		deck.queue_free()
		deck = null


## World transform where a passenger stands (facing the bow).
func passenger_transform() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, PASSENGER)


func _physics_process(delta: float) -> void:
	_t += delta
	_apply()


func _apply() -> void:
	var t := base_transform
	if bob:
		var y := sin(_t * 0.9 + _seed) * 0.07
		var roll := sin(_t * 0.7 + _seed * 1.3) * 0.025
		var pitch := sin(_t * 0.55 + _seed * 0.7) * 0.012
		t = Transform3D(t.basis * Basis.from_euler(Vector3(pitch, 0.0, roll)), t.origin + Vector3(0, y, 0))
	if is_inside_tree():
		global_transform = t
	else:
		transform = t


# --- geometry -------------------------------------------------------------------------------------

static func _half_beam(z: float) -> float:
	var u := z / HALF
	if u < 0.0:
		return BEAM * 0.5 * (1.0 - pow(-u, 2.1) * 0.62)
	return BEAM * 0.5 * (1.0 - pow(u, 3.0) * 0.3)


static func _sheer(z: float) -> float:
	var u := z / HALF
	return 1.45 + 0.85 * pow(maxf(-u, 0.0), 2.0) + 0.75 * pow(maxf(u, 0.0), 2.4)


static func _keel(z: float) -> float:
	var u := absf(z) / HALF
	return -0.85 * (1.0 - pow(u, 4.0) * 0.55)


## Full ferry in a BuildingKit (thread-safe geometry).
static func build_kit(p_nation: StringName) -> KitResult:
	var kit := BuildingKit.new(NationPalette.get_palette(p_nation), 0, 4242)
	kit.color_jitter = 0.0
	var g := kit.g()
	var trim := kit.col(&"trim")
	var wood := kit.col(&"wood")
	var dark := kit.col(&"wood_dark")
	var bottom := Color(0.22, 0.09, 0.07).srgb_to_linear()
	# Hull: lofted stations, five section points per side (gunwale -> keel).
	var stations := 15
	var rings: Array = []
	for i in stations:
		var z := lerpf(-HALF, HALF, float(i) / (stations - 1))
		var b := _half_beam(z)
		var s := _sheer(z)
		var k := _keel(z)
		rings.append([Vector3(b, s, z), Vector3(b * 1.0, 0.55, z), Vector3(b * 0.86, 0.0, z), Vector3(b * 0.52, k * 0.72, z), Vector3(0.0, k, z)])
	var cols := [trim, wood, bottom, bottom]
	for side in [-1.0, 1.0]:
		for i in stations - 1:
			var r0: Array = rings[i]
			var r1: Array = rings[i + 1]
			for j in 4:
				var a: Vector3 = r0[j]
				var b2: Vector3 = r0[j + 1]
				var c: Vector3 = r1[j + 1]
				var d: Vector3 = r1[j]
				a.x *= side
				b2.x *= side
				c.x *= side
				d.x *= side
				if side > 0.0:
					g.flat_quad(a, d, c, b2, cols[j])
				else:
					g.flat_quad(a, b2, c, d, cols[j])
	# Bow and stern transoms.
	for end in [0, stations - 1]:
		var r: Array = rings[end]
		var pts := PackedVector3Array()
		for j in 5:
			pts.append(r[j])
		for j in range(3, -1, -1):
			var p: Vector3 = r[j]
			pts.append(Vector3(-p.x, p.y, p.z))
		var ctr := Vector3(0, 0.4, (r[0] as Vector3).z)
		for j in pts.size():
			var p0 := pts[j]
			var p1 := pts[(j + 1) % pts.size()]
			if end == 0:
				g.flat_tri(ctr, p0, p1, dark)     # faces -Z (bow)
			else:
				g.flat_tri(ctr, p1, p0, dark)     # faces +Z (stern)
	# Gunwale cap.
	for side in [-1.0, 1.0]:
		for i in stations - 1:
			var a: Vector3 = rings[i][0]
			var b3: Vector3 = rings[i + 1][0]
			kit.beam(Vector3(a.x * side, a.y + 0.04, a.z), Vector3(b3.x * side, b3.y + 0.04, b3.z), 0.16, 0.1, &"wood_dark")
	# Deck planks.
	var poly := PackedVector2Array()
	for i in stations:
		var z2 := lerpf(-HALF + 0.6, HALF - 0.4, float(i) / (stations - 1))
		poly.append(Vector2(_half_beam(z2) * 0.93, z2))
	for i in range(stations - 1, -1, -1):
		var z3 := lerpf(-HALF + 0.6, HALF - 0.4, float(i) / (stations - 1))
		poly.append(Vector2(-_half_beam(z3) * 0.93, z3))
	kit.slab(poly, DECK_Y - 0.12, DECK_Y, &"floor", false)
	for k in 7:
		var x := -1.5 + k * 0.5
		kit.box(Vector3(x, DECK_Y + 0.005, -0.4), Vector3(0.02, 0.01, LENGTH * 0.78), &"wood_dark", false)
	# Stern cabin with a curved gable roof.
	var cz := 4.1
	kit.box(Vector3(0, DECK_Y + 0.95, cz), Vector3(3.2, 1.9, 3.4), &"wall", false)
	for sx in [-1.0, 1.0]:
		kit.box(Vector3(sx * 1.62, DECK_Y + 1.05, cz - 0.5), Vector3(0.06, 0.6, 0.9), &"window", false)
		kit.column(Vector3(sx * 1.55, DECK_Y, cz - 1.75), 2.0, 0.09, &"wood_dark")
	kit.box(Vector3(0, DECK_Y + 0.85, cz - 1.71), Vector3(0.9, 1.6, 0.06), &"door", false)
	KitRoofs.gable(kit, Vector3(0, DECK_Y + 1.9, cz), 3.2, 3.4, 1.15, {"overhang": 0.45, "curve": 0.3})
	# Raised bow platform + rail.
	kit.box(Vector3(0, DECK_Y + 0.18, -6.0), Vector3(2.4, 0.36, 2.0), &"floor", false)
	kit.railing(PackedVector3Array([Vector3(-1.4, DECK_Y + 0.36, -5.0), Vector3(-0.9, DECK_Y + 0.36, -6.9),
			Vector3(0.9, DECK_Y + 0.36, -6.9), Vector3(1.4, DECK_Y + 0.36, -5.0)]), 0.8, {"role": &"wood_dark", "collide": false})
	# Mast, yard and a battened junk sail (cloth slot: ripples with the wind).
	var mz := -1.6
	kit.cylinder(Vector3(0, DECK_Y, mz), 9.4, 0.17, &"wood_dark", 8, false, 0.1)
	var sail_bottom := DECK_Y + 2.4
	var sail_top := DECK_Y + 8.6
	var sail_len := 5.6
	var panels := 5
	var cb := kit.g(&"cloth")
	var sail_a := kit.col(&"cloth", false)
	var sail_b := kit.col(&"cloth_alt", false)
	var base := cb.vertex_count()
	var nx := 6
	for j in panels + 1:
		var v := float(j) / panels
		var y := lerpf(sail_bottom, sail_top, v)
		# the leech fans out: lower battens are longer
		var len_j := sail_len * (1.05 - v * 0.25)
		for i in nx + 1:
			var u := float(i) / nx
			var c := sail_a if (j % 2 == 0) else sail_a.lerp(sail_b, 0.25)
			if u > 0.82:
				c = sail_b
			cb.vertex(Vector3(0.05, y, mz + 0.2 + u * len_j), Vector3(1, 0, 0), c, Vector2(u * 0.35, v))
	for j in panels:
		for i in nx:
			var q := base + j * (nx + 1) + i
			cb.quad(q, q + 1, q + nx + 2, q + nx + 1)
	for j in panels + 1:
		var v2 := float(j) / panels
		var y2 := lerpf(sail_bottom, sail_top, v2)
		kit.beam(Vector3(0.12, y2, mz + 0.15), Vector3(0.12, y2, mz + 0.2 + sail_len * (1.05 - v2 * 0.25)), 0.07, 0.07, &"wood_dark")
	# Lanterns at the cabin and the bow, a stern flag.
	for sx in [-1.0, 1.0]:
		kit.lantern(Vector3(sx * 1.7, DECK_Y + 2.15, cz - 1.95), {"style": &"paper", "range": 10.0, "energy": 1.2})
	kit.lantern(Vector3(0, DECK_Y + 1.9, -6.7), {"style": &"post", "height": 1.5, "light": false})
	kit.flag(Transform3D(Basis.IDENTITY, Vector3(0, DECK_Y + 1.9 + 1.2, 5.9)), 2.6, 1.3, 0.8)
	# Crates and a coiled rope on deck.
	kit.box(Vector3(1.2, DECK_Y + 0.3, 0.9), Vector3(0.7, 0.6, 0.7), &"wood", false)
	kit.box(Vector3(1.1, DECK_Y + 0.75, 0.95), Vector3(0.5, 0.3, 0.5), &"wood_dark", false)
	kit.g().cylinder(Vector3(-1.2, DECK_Y, 1.2), Vector3(-1.2, DECK_Y + 0.22, 1.2), 0.38, 0.36, 10, kit.col(&"cloth_alt").darkened(0.35), 1)
	return kit.build()
