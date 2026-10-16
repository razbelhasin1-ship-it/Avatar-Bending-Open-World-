class_name AttackTokens
extends RefCounted
## Attack tokens (docs/GAME_DESIGN.md §5): at most N enemies attack the same target
## at once (story 1, normal 2, hard 3); the others circle and pressure. A short
## stagger between two attack starts on the same target keeps hits readable even
## when two enemies hold tokens.
##
##   if AttackTokens.request(self, player): start_attack()   # held while attacking
##   AttackTokens.release(self, player)                       # attack over / interrupted / dead
##
## Holders are kept as instance ids and validated on every query, so a freed enemy
## can never keep a token. Tokens also expire after HOLD_TIMEOUT (no stuck tokens).

const HOLD_TIMEOUT := 6.0
## Overrides the minimum seconds between two attack starts on one target (>= 0; tests).
static var start_spacing := -1.0

## target instance id -> {enemy instance id: grant time (s)}
static var _holders: Dictionary = {}
## target instance id -> time of the last granted start
static var _last_start: Dictionary = {}
## Overrides the difficulty-based limit when >= 0 (tests).
static var limit_override := -1


## Game clock (physics ticks), so hitstop / slow frames never distort token timing.
## Tests that step enemies manually may set `clock` (() -> float seconds).
static var clock: Callable = Callable()


static func now() -> float:
	if clock.is_valid():
		return float(clock.call())
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


## Minimum seconds between two attack starts against the same target (difficulty).
static func spacing() -> float:
	if start_spacing >= 0.0:
		return start_spacing
	match String(Settings.get_value("gameplay", "difficulty", "normal")):
		"story": return 1.1
		"hard": return 0.45
	return 0.75


static func max_tokens() -> int:
	if limit_override >= 0:
		return limit_override
	match String(Settings.get_value("gameplay", "difficulty", "normal")):
		"story": return 1
		"hard": return 3
	return 2


## Tries to take a token. `priority` (captains) ignores the start spacing.
static func request(enemy: Node, target: Node, priority: bool = false) -> bool:
	if enemy == null or target == null:
		return false
	var tid := target.get_instance_id()
	var eid := enemy.get_instance_id()
	_prune(tid)
	var h: Dictionary = _holders.get(tid, {})
	if h.has(eid):
		h[eid] = now()
		return true
	if h.size() >= max_tokens():
		return false
	var t := now()
	if not priority and t - float(_last_start.get(tid, -100.0)) < spacing():
		return false
	h[eid] = t
	_holders[tid] = h
	_last_start[tid] = t
	return true


static func release(enemy: Node, target: Node) -> void:
	if enemy == null or target == null:
		return
	var tid := target.get_instance_id()
	if _holders.has(tid):
		(_holders[tid] as Dictionary).erase(enemy.get_instance_id())


## Releases every token `enemy` holds (death, despawn).
static func release_all(enemy: Node) -> void:
	if enemy == null:
		return
	var eid := enemy.get_instance_id()
	for tid: int in _holders:
		(_holders[tid] as Dictionary).erase(eid)


static func holds(enemy: Node, target: Node) -> bool:
	if enemy == null or target == null:
		return false
	var tid := target.get_instance_id()
	_prune(tid)
	return (_holders.get(tid, {}) as Dictionary).has(enemy.get_instance_id())


static func count(target: Node) -> int:
	if target == null:
		return 0
	var tid := target.get_instance_id()
	_prune(tid)
	return (_holders.get(tid, {}) as Dictionary).size()


static func reset() -> void:
	_holders.clear()
	_last_start.clear()


static func _prune(tid: int) -> void:
	if not _holders.has(tid):
		return
	var h: Dictionary = _holders[tid]
	var t := now()
	for eid: int in h.keys():
		var o := instance_from_id(eid)
		var alive := o != null and is_instance_valid(o) and (o as Node).is_inside_tree()
		if alive and o.has_method("is_alive"):
			alive = bool(o.call("is_alive"))
		if not alive or t - float(h[eid]) > HOLD_TIMEOUT:
			h.erase(eid)
