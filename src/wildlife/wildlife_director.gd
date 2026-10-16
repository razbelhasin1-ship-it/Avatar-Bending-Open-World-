class_name WildlifeDirector
extends Node3D
## Keeps the nearest herds and bird flocks alive around the player within the detail-level
## budget (records from WildlifeProvider cells). Herds spawn one animal per frame, despawn with
## hysteresis; combat and bending near animals startle them; flocks startle when the player
## runs at them. docs/modules/quests_npcs.md "Wildlife".

const BUDGETS := [
	{"animals": 5, "range": 70.0, "flocks": 1, "bison": 1},
	{"animals": 9, "range": 100.0, "flocks": 2, "bison": 2},
	{"animals": 14, "range": 140.0, "flocks": 3, "bison": 2},
	{"animals": 20, "range": 180.0, "flocks": 4, "bison": 3},
]
const UPDATE := 0.5

var player: Node3D = null
var max_animals := 14
var range_m := 140.0
var max_flocks := 3
var max_bison := 2

var _records: Dictionary = {}       # key -> record
var _cells: Dictionary = {}         # coord -> [keys]
var _herds: Dictionary = {}         # key -> Array[WildlifeAnimal]
var _flocks: Dictionary = {}        # key -> BirdFlock
var _queue: Array = []              # [key, index]
var _t := 0.0


static func budgets() -> Dictionary:
	return BUDGETS[clampi(Settings.detail_level(), 0, BUDGETS.size() - 1)]


func _ready() -> void:
	name = "Wildlife"
	configure()
	Events.graphics_settings_changed.connect(configure)
	Events.hit_landed.connect(_on_hit)
	Events.ability_used.connect(func(_id: StringName) -> void:
		var pp := _player_pos()
		if pp.is_finite():
			_startle_near(pp, 14.0))


func configure() -> void:
	var b := budgets()
	max_animals = int(b["animals"])
	range_m = float(b["range"])
	max_flocks = int(b["flocks"])
	max_bison = int(b["bison"])


func add_records(coord: Vector2i, recs: Array) -> void:
	var keys: Array = []
	for r: Dictionary in recs:
		_records[r["key"]] = r
		keys.append(r["key"])
	_cells[coord] = keys


func remove_records(coord: Vector2i) -> void:
	for k: Variant in _cells.get(coord, []):
		_records.erase(k)
		_despawn(k)
	_cells.erase(coord)


func add_record(r: Dictionary) -> void:
	_records[r["key"]] = r


func animal_count() -> int:
	var n := 0
	for k: Variant in _herds:
		for a: Variant in _herds[k]:
			if is_instance_valid(a):
				n += 1
	return n


func flock_count() -> int:
	return _flocks.size()


func animals() -> Array[WildlifeAnimal]:
	var out: Array[WildlifeAnimal] = []
	for k: Variant in _herds:
		for a: Variant in _herds[k]:
			if is_instance_valid(a):
				out.append(a)
	return out


func _player_pos() -> Vector3:
	if player == null or not is_instance_valid(player):
		player = Quests.get_player()
	return player.global_position if player != null else Vector3.INF


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = UPDATE
		_update()
	if not _queue.is_empty():
		var q: Array = _queue.pop_front()
		_spawn_one(q[0], int(q[1]))


func _update() -> void:
	var pp := _player_pos()
	if not pp.is_finite():
		return
	var herds: Array = []
	var flocks: Array = []
	for k: Variant in _records:
		var r: Dictionary = _records[k]
		var d := pp.distance_to(r["pos"])
		if r.has("flock"):
			if d < range_m * 1.6:
				flocks.append([d, k])
		elif d < range_m + (20.0 if _herds.has(k) else 0.0):
			herds.append([d, k])
	herds.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	flocks.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var keep := {}
	var budget := max_animals
	var bison := 0
	for h: Array in herds:
		var r2: Dictionary = _records[h[1]]
		var n := int(r2["count"])
		if r2["species"] == &"sky_bison":
			if bison >= max_bison:
				continue
			bison += 1
		if n > budget:
			continue
		budget -= n
		keep[h[1]] = n
	for i in mini(flocks.size(), max_flocks):
		keep[flocks[i][1]] = 1
	for k2: Variant in _herds.keys():
		if not keep.has(k2):
			_despawn(k2)
	for k3: Variant in _flocks.keys():
		if not keep.has(k3):
			_despawn(k3)
	_queue.clear()
	for k4: Variant in keep:
		var r3: Dictionary = _records[k4]
		if r3.has("flock"):
			if not _flocks.has(k4):
				_queue.append([k4, 0])
			continue
		var have: Array = _herds.get(k4, [])
		for i2 in int(keep[k4]):
			if i2 >= have.size() or not is_instance_valid(have[i2]):
				_queue.append([k4, i2])
	# flocks startle when the player runs into them
	for k5: Variant in _flocks:
		var f: BirdFlock = _flocks[k5]
		if is_instance_valid(f) and pp.distance_to((_records[k5]["pos"] as Vector3)) < 30.0 and player is CharacterBody3D \
				and (player as CharacterBody3D).velocity.length() > 6.0:
			f.startle(pp)


func _spawn_one(key: Variant, index: int) -> void:
	if not _records.has(key):
		return
	var r: Dictionary = _records[key]
	if r.has("flock"):
		var c: Vector3 = r["pos"]
		var f := BirdFlock.create(r["flock"], int(r["count"]), c, float(r["radius"]), float(r["altitude"]), absi(hash(String(key))) % 997 + 1)
		add_child(f)
		_flocks[key] = f
		return
	var list: Array = _herds.get(key, [])
	while list.size() <= index:
		list.append(null)
	if list[index] != null and is_instance_valid(list[index]):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(key)) + index * 7919
	var center: Vector3 = r["pos"]
	var a := rng.randf() * TAU
	var rr := 0.0 if index == 0 else rng.randf_range(1.0, float(r["radius"]) * 0.6)
	var p := center + Vector3(cos(a), 0, sin(a)) * rr
	var sc := 1.0
	var sr: Variant = r.get("scale", 1.0)
	if sr is Array:
		sc = float(sr[1]) if index == 0 else rng.randf_range(float(sr[0]), float(sr[1]))
	else:
		sc = float(sr)
	var animal := WildlifeAnimal.create(r["species"], p, float(r["yaw"]) + rng.randf_range(-0.6, 0.6), rng.seed, sc)
	animal.herd_center = center
	animal.herd_radius = float(r["radius"])
	animal.swim_level = float(r.get("swim", -INF))
	animal.resting = bool(r.get("rest", false))
	add_child(animal)
	list[index] = animal
	_herds[key] = list


func _despawn(key: Variant) -> void:
	if _herds.has(key):
		for a: Variant in _herds[key]:
			if a != null and is_instance_valid(a):
				(a as Node).queue_free()
		_herds.erase(key)
	if _flocks.has(key):
		var f: Variant = _flocks[key]
		if is_instance_valid(f):
			(f as Node).queue_free()
		_flocks.erase(key)


func _on_hit(_hit: HitInfo, target: Node, _r: int) -> void:
	if target is Node3D and is_instance_valid(target):
		_startle_near((target as Node3D).global_position, 25.0)


func _startle_near(p: Vector3, radius: float) -> void:
	for a in animals():
		if a.global_position.distance_to(p) < radius:
			a.startle(p)
	for k: Variant in _flocks:
		var f: BirdFlock = _flocks[k]
		if is_instance_valid(f) and (_records[k]["pos"] as Vector3).distance_to(p) < radius * 2.0:
			f.startle(p)
