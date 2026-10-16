class_name NpcDirector
extends Node3D
## Spawns and budgets the townsfolk around the player (docs/modules/quests_npcs.md "NPCs").
##
## Sources: crowd records from NpcProvider cells (WorldContent streaming, worker-built from the
## settlement anchors) and the named NPCs of NpcRegistry (quest givers, trainers, merchants).
## At 4 Hz it ranks every present record (schedule by hour, `present` conditions) by distance —
## named NPCs first — keeps the nearest `max_npcs` alive within `crowd_range`, spawns at most one
## per frame (a new mesh variant at most every `variant_gap` s), switches the nearest `tier_a`
## to the full tier, and despawns with hysteresis. It also dispatches reactions to bending and
## combat, greetings, merchant calls, escorts and the talk interaction (DialogueRunner).

## Budgets by Settings.detail_level() (0 = mobile / low ... 3 = ultra).
const BUDGETS := [
	{"max_npcs": 10, "crowd_range": 55.0, "named_range": 70.0, "tier_a": 4, "density": 0.85},
	{"max_npcs": 18, "crowd_range": 66.0, "named_range": 90.0, "tier_a": 7, "density": 0.9},
	{"max_npcs": 28, "crowd_range": 80.0, "named_range": 110.0, "tier_a": 10, "density": 1.0},
	{"max_npcs": 40, "crowd_range": 100.0, "named_range": 130.0, "tier_a": 14, "density": 1.25},
]
const UPDATE := 0.25
const HYSTERESIS := 14.0

var player: Node3D = null
var runner: DialogueRunner = null
var max_npcs := 28
var crowd_range := 80.0
var named_range := 110.0
var tier_a := 10
## Seconds between two spawns that need a new mesh variant (keeps frame spikes rare).
var variant_gap := 0.35
## False while the world is not playing (cinematics); nothing spawns.
var active := true

var _records: Dictionary = {}       # key -> record
var _cells: Dictionary = {}         # Vector2i -> Array[StringName] keys
var _live: Dictionary = {}          # key -> NpcCharacter
var _queue: Array[StringName] = []
var _t := 0.0
var _variant_t := 0.0
var _known_variants: Dictionary = {}
var _neighbors: Dictionary = {}     # key -> Array[NpcCharacter]
var _bark_cd := 0.0
var _greeted: Dictionary = {}       # key -> play time of the last greeting
var _bend_cd := 0.0
var _rng := RandomNumberGenerator.new()
var _escorts: Dictionary = {}       # npc id -> true while following


static func budgets() -> Dictionary:
	return BUDGETS[clampi(Settings.detail_level(), 0, BUDGETS.size() - 1)]


## Anchor ids that named NPCs stand on (the crowd leaves them free).
static func claimed_anchor_ids() -> Dictionary:
	var out := {}
	for id in NpcRegistry.ids():
		var place: Dictionary = NpcRegistry.get_npc(id).get("place", {})
		if place.has("anchor"):
			var a := QuestTargets.find_anchor(place["anchor"])
			if not a.is_empty():
				out[String(a["id"])] = true
	return out


func _ready() -> void:
	name = "NpcDirector"
	_rng.seed = 7741
	configure()
	Events.graphics_settings_changed.connect(configure)
	Events.hit_landed.connect(_on_hit_landed)
	Events.ability_used.connect(_on_ability_used)
	Events.combat_state_changed.connect(_on_combat_state)
	Events.player_spawned.connect(func(p: Node3D) -> void: player = p)
	if runner == null:
		runner = DialogueRunner.new()
		add_child(runner)


func configure() -> void:
	var b := budgets()
	max_npcs = int(b["max_npcs"])
	crowd_range = float(b["crowd_range"])
	named_range = float(b["named_range"])
	tier_a = int(b["tier_a"])


# --- records -------------------------------------------------------------------------------------

func add_records(coord: Vector2i, recs: Array) -> void:
	var keys: Array[StringName] = []
	for r: Dictionary in recs:
		var k: StringName = r["key"]
		_records[k] = r
		keys.append(k)
	_cells[coord] = keys


func remove_records(coord: Vector2i) -> void:
	for k: StringName in _cells.get(coord, []):
		_records.erase(k)
		var n: NpcCharacter = _live.get(k)
		if n != null and is_instance_valid(n) and not n.in_conversation():
			n.queue_free()
			_live.erase(k)
	_cells.erase(coord)


## Adds a single record (tests, scripted scenes without WorldContent).
func add_record(r: Dictionary) -> void:
	_records[r["key"]] = r


func record_count() -> int:
	return _records.size()


func live_count() -> int:
	return _live.size()


func live_npcs() -> Array[NpcCharacter]:
	var out: Array[NpcCharacter] = []
	for k: StringName in _live:
		var n: NpcCharacter = _live[k]
		if is_instance_valid(n):
			out.append(n)
	return out


func live_npc(key: StringName) -> NpcCharacter:
	var n: Variant = _live.get(key)
	return n if n is NpcCharacter and is_instance_valid(n) else null


func neighbors(npc: NpcCharacter) -> Array:
	return _neighbors.get(npc.key, [])


## Named NPC record (placement from NpcRegistry).
func _named_record(id: StringName) -> Dictionary:
	var d := NpcRegistry.get_npc(id)
	var xf := NpcRegistry.placement(id)
	var look: Dictionary = (d.get("look", {}) as Dictionary).duplicate()
	if not look.has("seed"):
		look["seed"] = absi(hash(String(id))) % 7 + 1
	return {"key": StringName("named_" + String(id)), "named": id, "nation": d.get("nation", &"earth"),
		"role": d.get("role", &"quest_giver"), "pos": xf.origin, "yaw": xf.basis.get_euler().y, "home": xf.origin,
		"look": look, "hash": hash(String(id)), "offset": 0.0, "wander": float(d.get("wander", 0.0)),
		"tags": [], "goods": String(d.get("goods", "")), "route": PackedVector3Array(), "pair": &""}


# --- main loop ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_bark_cd = maxf(0.0, _bark_cd - delta)
	_bend_cd = maxf(0.0, _bend_cd - delta)
	_variant_t = maxf(0.0, _variant_t - delta)
	_t -= delta
	if _t <= 0.0:
		_t = UPDATE
		_update()
	_spawn_step()


func _player_pos() -> Vector3:
	if player == null or not is_instance_valid(player):
		player = Quests.get_player()
	return player.global_position if player != null else Vector3.INF


func _update() -> void:
	var pp := _player_pos()
	for k: StringName in _live.keys():
		if not is_instance_valid(_live[k]):
			_live.erase(k)
	if not pp.is_finite() or not active:
		return
	var hour := GameState.time_of_day
	var cands: Array = []
	for k: StringName in _records:
		var r: Dictionary = _records[k]
		var d := pp.distance_to(r["pos"])
		if d > crowd_range + HYSTERESIS:
			continue
		if not NpcRoutines.is_present(r["role"], hour, float(r["offset"])):
			continue
		if d > crowd_range and not _live.has(k):
			continue
		cands.append([d, k, r])
	for id in NpcRegistry.ids():
		var nd := NpcRegistry.get_npc(id)
		if not QuestConditions.check(nd.get("present")):
			continue
		var xf := NpcRegistry.placement(id)
		if not xf.origin.is_finite():
			continue
		var key := StringName("named_" + String(id))
		var d2 := pp.distance_to(xf.origin)
		var live: NpcCharacter = _live.get(key)
		if live != null and is_instance_valid(live):
			d2 = minf(d2, pp.distance_to(live.global_position))
		if _escorts.has(id):
			d2 = 0.0
		if d2 > named_range + (HYSTERESIS if _live.has(key) else 0.0):
			continue
		if not _records.has(key):
			_records[key] = _named_record(id)
		cands.append([d2 - 10000.0, key, _records[key]])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var keep := {}
	for i in mini(cands.size(), max_npcs):
		keep[cands[i][1]] = true
	# despawn: out of budget / range (an NPC walking home is left to vanish at its door)
	for k: StringName in _live.keys():
		var n: NpcCharacter = _live[k]
		if keep.has(k) or n.in_conversation() or n.is_vanishing():
			continue
		var dn := pp.distance_to(n.global_position)
		if n.brain != null and n.brain.override == &"go_home" and dn < crowd_range + HYSTERESIS:
			continue
		if dn < 45.0:
			n.vanish(0.6)       # in view (a named NPC whose `present` stopped holding): fade out
		else:
			n.queue_free()
			_live.erase(k)
	_queue.clear()
	for c: Array in cands:
		if keep.has(c[1]) and not _live.has(c[1]):
			_queue.append(c[1])
	# tiers
	var order: Array = []
	for k3: StringName in _live:
		order.append([pp.distance_to((_live[k3] as Node3D).global_position), k3])
	order.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in order.size():
		(_live[order[i][1]] as NpcCharacter).set_full(i < tier_a and float(order[i][0]) < 40.0)
	_update_neighbors()
	_greetings(pp)
	_update_escorts()


func _spawn_step() -> void:
	if _queue.is_empty() or not active:
		return
	var k: StringName = _queue.pop_front()
	if _live.has(k) or not _records.has(k):
		return
	var r: Dictionary = _records[k]
	var vkey := str(r["look"])
	if not _known_variants.has(vkey):
		if _variant_t > 0.0:
			_queue.push_front(k)
			return
		_variant_t = variant_gap
		_known_variants[vkey] = true
	var n := NpcCharacter.create(r, self)
	add_child(n)
	_live[k] = n


func _update_neighbors() -> void:
	_neighbors.clear()
	var arr := live_npcs()
	for i in arr.size():
		var a := arr[i]
		if not a.is_moving():
			continue
		var list: Array = []
		for j in arr.size():
			if i != j and a.global_position.distance_squared_to(arr[j].global_position) < 9.0:
				list.append(arr[j])
		_neighbors[a.key] = list


# --- pre-warm ---------------------------------------------------------------------------------------

## Builds the crowd mesh variants of `nation` one per frame (call during loading).
func prewarm(nation: StringName, max_frames: int = 64) -> void:
	var cfgs := NpcLooks.variant_configs(nation)
	var n := 0
	for c in cfgs:
		if n >= max_frames or not is_inside_tree():
			return
		CharacterMeshBuilder.build(CharacterOutfits.resolve(c))
		_known_variants[str(c)] = true
		n += 1
		await get_tree().process_frame


# --- talking ---------------------------------------------------------------------------------------

func talk_to(npc: NpcCharacter) -> void:
	if runner != null and not runner.busy:
		runner.talk(npc)


## A floating line from `npc` for a situation (global cooldown so crowds do not shout at once).
func bark(npc: NpcCharacter, situation: StringName, force: bool = false) -> void:
	if not force and _bark_cd > 0.0:
		return
	var text := NpcBarks.line(npc.nation, situation, _rng)
	if text.is_empty():
		return
	_bark_cd = 0.9
	npc.bark(text)


func merchant_call(npc: NpcCharacter) -> void:
	var pp := _player_pos()
	if not pp.is_finite() or pp.distance_to(npc.global_position) > 16.0 or _bark_cd > 0.0:
		return
	var goods := String(npc.record.get("goods", ""))
	var sit := StringName("merchant_" + goods) if goods != "" else &"merchant"
	if NpcBarks.line(npc.nation, sit, _rng).is_empty():
		sit = &"merchant"
	bark(npc, sit)
	_bark_cd = 4.0


func _greetings(pp: Vector3) -> void:
	if _bark_cd > 0.0 or (runner != null and runner.busy):
		return
	for n in live_npcs():
		if not n.full or n.in_conversation() or n.is_barking():
			continue
		var d := pp.distance_to(n.global_position)
		if d > 3.4:
			continue
		var last := float(_greeted.get(n.key, -999.0))
		if GameState.play_time - last < 45.0:
			continue
		_greeted[n.key] = GameState.play_time
		if n.npc_id != &"":
			var lines: Array = NpcRegistry.get_npc(n.npc_id).get("barks", [])
			if not lines.is_empty():
				n.bark(String(lines[_rng.randi_range(0, lines.size() - 1)]))
				_bark_cd = 2.5
			return
		bark(n, NpcBarks.greeting(n.nation, GameState.element))
		_bark_cd = 2.5
		return


# --- reactions ---------------------------------------------------------------------------------------

func _on_hit_landed(hit: HitInfo, target: Node, result: int) -> void:
	if result == Combat.Result.IGNORED or target == null or not is_instance_valid(target) or not (target is Node3D):
		return
	var at := (target as Node3D).global_position
	var training := target.is_in_group(&"training_dummy") or target.is_in_group(&"quest_target") or target.is_in_group(&"sparring")
	for n in live_npcs():
		var d := n.global_position.distance_to(at)
		if training:
			if d < 12.0 and _bend_cd <= 0.0:
				n.react_bending(at, GameState.element)
		elif d < 20.0:
			n.react_threat(at, 1.0)
	if training:
		_bend_cd = 1.2
	if hit != null and hit.source is Node3D and is_instance_valid(hit.source) and not training:
		var src := (hit.source as Node3D).global_position
		for n2 in live_npcs():
			if n2.global_position.distance_to(src) < 10.0:
				n2.react_threat(src, 1.0)


func _on_ability_used(_id: StringName) -> void:
	if _bend_cd > 0.0:
		return
	_bend_cd = 1.5
	var pp := _player_pos()
	if not pp.is_finite():
		return
	var in_combat := Audio.is_in_combat()
	for n in live_npcs():
		var d := n.global_position.distance_to(pp)
		if d < 11.0:
			if in_combat:
				n.react_threat(pp, 1.0)
			else:
				n.react_bending(pp, GameState.element)


func _on_combat_state(on: bool) -> void:
	if not on:
		return
	var pp := _player_pos()
	if not pp.is_finite():
		return
	for n in live_npcs():
		if n.global_position.distance_to(pp) < 35.0:
			n.react_threat(pp, 1.0)


# --- escorts -----------------------------------------------------------------------------------------

## Escort objectives: their NPC follows the player; arriving reports to the quest system.
func _update_escorts() -> void:
	var active_ids := {}
	for e in Quests.active_objectives(&"escort"):
		var od: Dictionary = e["objective"]
		var id: StringName = od["npc"]
		active_ids[id] = true
		var n := live_npc(StringName("named_" + String(id)))
		if n == null:
			continue
		if n.brain.override != &"follow" and n.brain.override != &"converse":
			n.brain.start_follow(player)
			_escorts[id] = true
		var dest := QuestTargets.resolve(od.get("to"))
		if dest.is_finite() and Vector2(n.global_position.x - dest.x, n.global_position.z - dest.z).length() <= float(od["radius"]):
			n.brain.stop_follow()
			n.home = Transform3D(n.home.basis, n.global_position)     # stays where it was brought
			_escorts.erase(id)
			Quests.report(&"escort", id, 1, {"quest": e["quest"]})
	for id2: StringName in _escorts.keys():
		if not active_ids.has(id2):
			var n2 := live_npc(StringName("named_" + String(id2)))
			if n2 != null:
				n2.brain.stop_follow()
			_escorts.erase(id2)
