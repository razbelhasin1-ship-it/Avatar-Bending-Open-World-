class_name NpcBrain
extends RefCounted
## What an NPC is doing: its scheduled activity (NpcRoutines by role and hour, or a named NPC's
## `idle`) and short reactions layered on top (flee + cower from combat, cheer / watch bending,
## talking with the player, following an escort, going home at dusk). Thinks at 5 Hz; every
## reaction has a timer, so nothing can stick.

const THINK := 0.2

var npc: NpcCharacter
var activity: StringName = &""
## Reaction on top of the activity: &"flee", &"cower", &"cheer", &"watch", &"converse", &"follow", &"go_home".
var override: StringName = &""
var rng := RandomNumberGenerator.new()
## Escort target (follow override).
var follow_target: Node3D = null

var _t := 0.0
var _o_t := 0.0
var _phase := 0
var _wait := 0.0
var _route_i := 0
var _route_dir := 1
var _threat := Vector3.ZERO
var _look := false
var _clip_t := 0.0
var _speaking_turn := false
var _posed: StringName = &""


func _init(p_npc: NpcCharacter) -> void:
	npc = p_npc
	rng.seed = hash(String(npc.key))
	_clip_t = rng.randf_range(0.5, 3.0)
	npc.arrived.connect(_on_arrived)


func tick(delta: float) -> void:
	_t += delta
	if _t < THINK:
		return
	var dt := _t
	_t = 0.0
	if override != &"":
		_tick_override(dt)
		return
	var want := scheduled()
	if want != activity:
		_enter(want)
	_tick_activity(dt)
	_tick_look()


## The activity the schedule asks for now.
func scheduled() -> StringName:
	if npc.npc_id != &"":
		return StringName(str(NpcRegistry.get_npc(npc.npc_id).get("idle", "stand")))
	return NpcRoutines.activity(npc.role, GameState.time_of_day, float(npc.record.get("offset", 0.0)))


func can_talk() -> bool:
	return override != &"flee" and override != &"cower" and override != &"go_home" and activity != &"home"


# --- activities -----------------------------------------------------------------------------------

func _enter(a: StringName) -> void:
	_leave_pose()
	activity = a
	_phase = 0
	_wait = rng.randf_range(0.5, 2.0)
	npc.stop_moving()
	npc.hold_props(_props_for(a))
	var night := NpcRoutines.is_night(GameState.time_of_day)
	npc.rig.set_combat_stance(a == &"guard" or a == &"train")
	if a == &"train":
		npc.rig.set_style(_bend_style())
	match a:
		&"home":
			override = &"go_home"
			npc.move_to(npc.door, NpcCharacter.WALK)
		&"patrol":
			var route: PackedVector3Array = npc.record.get("route", PackedVector3Array())
			_route_i = _closest_route_point(route)
			_route_dir = 1
			if night:
				npc.hold_props(["lantern@hand_l"])
		&"guard":
			if night:
				npc.hold_props(["lantern@hand_l"])


func _props_for(a: StringName) -> Array:
	match a:
		&"work":
			match npc.role:
				&"worker":
					var tags: Array = npc.record.get("tags", [])
					if tags.has("docks") or tags.has("cranes") or tags.has("tea") or tags.has("harbor"):
						return ["basket"]
					if tags.has("salt") or tags.has("salt_pans"):
						return ["broom"]
					return ["hammer"]
				&"gardener":
					return ["broom"]
		&"fish":
			return ["fishing_rod"]
		&"patrol", &"guard":
			if npc.nation == &"air":
				return ["staff"]
	var def_props: Array = NpcRegistry.get_npc(npc.npc_id).get("props", []) if npc.npc_id != &"" else []
	return def_props


func _tick_activity(dt: float) -> void:
	match activity:
		&"patrol":
			_tick_patrol(dt)
		&"wander", &"stroll":
			_tick_wander(dt, 2.6 if activity == &"stroll" else 1.0)
		&"play":
			_tick_play(dt)
		_:
			_tick_station(dt)


## Activities done at the home spot: walk back there, face the anchor's way, then pose / loop.
func _tick_station(dt: float) -> void:
	var spot := npc.home.origin
	if _phase == 0:
		if npc.global_position.distance_to(spot) > 0.7 and not npc.is_moving():
			npc.move_to(spot, NpcCharacter.WALK)
		elif not npc.is_moving():
			_phase = 1
			npc.face_yaw(npc.home.basis.get_euler().y)
			_begin_pose()
		return
	_clip_t -= dt
	match activity:
		&"talk":
			_tick_talk()
		&"train":
			if _clip_t <= 0.0:
				_clip_t = rng.randf_range(2.2, 3.6)
				npc.rig.play_action(StringName("combo_%s_%d" % [_bend_style(), rng.randi_range(1, 3)]))
		&"stand", &"guard", &"work":
			if _clip_t <= 0.0:
				_clip_t = rng.randf_range(6.0, 12.0)
				_fidget()
	if npc.full and _clip_t <= 0.0:
		_clip_t = rng.randf_range(5.0, 9.0)


func _begin_pose() -> void:
	match activity:
		&"sit":
			npc.rig.play_action(&"sit")
			_posed = &"sit"
		&"meditate":
			npc.rig.play_action(&"meditate")
			_posed = &"meditate"
		&"work":
			match npc.role:
				&"worker":
					var tags: Array = npc.record.get("tags", [])
					var clip := &"work_hammer"
					if tags.has("docks") or tags.has("cranes") or tags.has("tea") or tags.has("harbor"):
						clip = &"carry"
					elif tags.has("salt") or tags.has("salt_pans"):
						clip = &"sweep"
					npc.rig.play_action(clip)
					_posed = clip
				&"gardener":
					npc.rig.play_action(&"sweep")
					_posed = &"sweep"
				&"merchant", &"healer":
					pass
				_:
					var w := StringName(str(NpcRegistry.get_npc(npc.npc_id).get("work_clip", ""))) if npc.npc_id != &"" else &""
					if w != &"":
						npc.rig.play_action(w)
						_posed = w
		&"fish":
			npc.rig.play_action(&"fish")
			_posed = &"fish"
		&"talk":
			_speaking_turn = String(npc.key).ends_with("_a")


func _leave_pose() -> void:
	if _posed == &"sit" or _posed == &"meditate":
		npc.rig.set_pose_state(&"normal", 0.35)
	if _posed != &"":
		npc.rig.stop_action(0.3)
	_posed = &""
	npc.rig.set_talking(false)


func _tick_talk() -> void:
	var partner := _partner()
	if partner != null:
		npc.face_point(partner.global_position)
		npc.rig.look_at_point(partner.global_position + Vector3(0, 1.55, 0), 0.8)
	if _clip_t > 0.0:
		return
	_clip_t = rng.randf_range(3.5, 6.5)
	_speaking_turn = not _speaking_turn if partner != null else true
	if _speaking_turn:
		npc.rig.play_action(&"talk_1" if rng.randf() < 0.5 else &"talk_2")
		npc.rig.set_talking(true)
		_posed = &"talk_1"
	else:
		npc.rig.stop_action(0.4)
		npc.rig.set_talking(false)
		if rng.randf() < 0.3:
			npc.rig.play_action(&"talk_3")


func _partner() -> NpcCharacter:
	var pk: StringName = npc.record.get("pair", &"")
	if pk == &"" or npc.director == null:
		return null
	return (npc.director as NpcDirector).live_npc(pk)


func _fidget() -> void:
	if npc.rig.is_playing_action() and _posed != &"":
		return
	var r := rng.randf()
	if npc.role == &"merchant" and r < 0.45:
		npc.rig.play_action(&"point_r" if rng.randf() < 0.5 else &"wave_r")
		if npc.director != null:
			(npc.director as NpcDirector).merchant_call(npc)
	elif r < 0.25:
		npc.rig.play_action(&"talk_3")
	elif r < 0.5:
		var a := npc.rotation.y + rng.randf_range(-1.2, 1.2)
		npc.rig.look_at_point(npc.global_position + Vector3(-sin(a), 1.6, -cos(a)) * 6.0, 0.7)


func _tick_patrol(_dt: float) -> void:
	var route: PackedVector3Array = npc.record.get("route", PackedVector3Array())
	if route.size() < 2:
		_tick_station(_dt)
		return
	if npc.is_moving():
		return
	_wait -= THINK
	if _wait > 0.0:
		return
	npc.move_to(route[_route_i], NpcCharacter.WALK * 0.95)
	var last := route.size() - 1
	if bool(npc.record.get("loop", false)):
		_route_i = (_route_i + 1) % route.size()
	else:
		if _route_i + _route_dir > last or _route_i + _route_dir < 0:
			_route_dir = -_route_dir
			_wait = rng.randf_range(2.0, 5.0)
		_route_i = clampi(_route_i + _route_dir, 0, last)


func _closest_route_point(route: PackedVector3Array) -> int:
	var best := 0
	var bd := INF
	for i in route.size():
		var d := route[i].distance_to(npc.global_position)
		if d < bd:
			bd = d
			best = i
	return best


func _tick_wander(_dt: float, scale: float) -> void:
	if npc.is_moving():
		return
	_wait -= THINK
	if _wait > 0.0:
		return
	_wait = rng.randf_range(3.0, 8.0)
	if not npc.full:
		# far away: idle in place (cheap), no probes
		if rng.randf() < 0.3:
			_fidget()
		return
	var r := maxf(2.0, float(npc.record.get("wander", 4.0))) * scale
	for attempt in 4:
		var a := rng.randf() * TAU
		var p := npc.home.origin + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(r * 0.35, r)
		if NpcSteering.walkable(npc, npc.global_position, p):
			npc.move_to(p, NpcCharacter.WALK * rng.randf_range(0.85, 1.1))
			return
	_fidget()


func _tick_play(_dt: float) -> void:
	if npc.is_moving():
		return
	_wait -= THINK
	if _wait > 0.0:
		return
	if rng.randf() < 0.3:
		npc.rig.play_action(&"cheer")
		_wait = 1.4
		return
	_wait = rng.randf_range(0.2, 1.2)
	var a := rng.randf() * TAU
	var p := npc.home.origin + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(1.2, float(npc.record.get("wander", 4.0)))
	if not npc.full or NpcSteering.walkable(npc, npc.global_position, p, 0.6):
		npc.move_to(p, NpcCharacter.RUN * 0.75)


func _tick_look() -> void:
	var pl := Quests.get_player()
	var near := pl != null and npc.full and pl.global_position.distance_to(npc.global_position) < 4.5 \
		and activity != &"talk" and activity != &"meditate"
	if near:
		npc.rig.look_at_point(pl.global_position + Vector3(0, 1.55, 0), 0.9)
		_look = true
	elif _look:
		npc.rig.clear_look_at()
		_look = false


func _bend_style() -> StringName:
	var s: StringName = {&"water": &"water", &"earth": &"earth", &"fire": &"fire", &"air": &"air"}.get(npc.nation, &"earth")
	return s


func _on_arrived(_ok: bool) -> void:
	if override == &"go_home":
		npc.vanish(0.8)
	elif override == &"flee":
		_set_override(&"cower", rng.randf_range(3.0, 5.0))


# --- reactions ---------------------------------------------------------------------------------------

func _set_override(o: StringName, t: float) -> void:
	if override == &"converse" or override == &"go_home":
		return
	if override == &"" and o != &"":
		_leave_pose()
	override = o
	_o_t = t
	match o:
		&"cower":
			npc.stop_moving()
			npc.rig.play_action(&"kneel")
			_posed = &"kneel"
		&"cheer":
			npc.stop_moving()
			npc.rig.play_action(&"cheer")
		&"watch":
			npc.stop_moving()


func _tick_override(dt: float) -> void:
	_o_t -= dt
	match override:
		&"go_home":
			if not npc.is_moving() and not npc.is_vanishing():
				npc.vanish(0.8)
			return
		&"converse":
			return
		&"follow":
			_tick_follow()
			return
		&"watch", &"cheer":
			if _threat != Vector3.ZERO:
				npc.face_point(_threat)
				npc.rig.look_at_point(_threat + Vector3(0, 1.4, 0), 1.0)
	if _o_t <= 0.0:
		_clear_override()


func _clear_override() -> void:
	if _posed == &"kneel":
		npc.rig.stop_action(0.4)
	_posed = &""
	override = &""
	activity = &""        # re-enter the scheduled activity
	npc.rig.clear_look_at()


## Combat / danger near `from`: civilians flee then cower, guards face it.
func react_threat(from: Vector3, severity: float) -> void:
	if override == &"converse" or override == &"go_home" or override == &"follow":
		return
	_threat = from
	if npc.role == &"guard" or npc.role == &"patrol" or npc.npc_id != &"":
		if override != &"watch":
			_set_override(&"watch", 4.0)
			_bark(&"guard_combat")
		return
	if severity < 0.5:
		if override == &"":
			_set_override(&"watch", 2.5)
		return
	if override == &"flee" or override == &"cower":
		_o_t = maxf(_o_t, 3.0)
		return
	var away := npc.global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3(1, 0, 0)
	for k in 5:
		var ang := float(k + 1) / 2.0 * (1.0 if k % 2 == 0 else -1.0) * 0.6 if k > 0 else 0.0
		var dirv := away.rotated(Vector3.UP, ang)
		var p := npc.global_position + dirv * rng.randf_range(10.0, 16.0)
		if not npc.full or NpcSteering.walkable(npc, npc.global_position, p, 1.5):
			_set_override(&"flee", 7.0)
			npc.move_to(p, NpcCharacter.RUN)
			_bark(&"flee")
			return
	_set_override(&"cower", rng.randf_range(3.5, 5.0))
	_bark(&"flee")


## The player bends nearby without danger: friendly folk cheer or watch, wary folk back off.
func react_bending(from: Vector3, player_element: int) -> void:
	if override != &"" or activity == &"meditate" or npc.npc_id != &"":
		return
	_threat = from
	var att := NpcBarks.attitude(npc.nation, player_element)
	if att == &"wary":
		_set_override(&"watch", 3.0)
		_bark(&"wary_bending")
		return
	if npc.role == &"child" or (npc.role == &"idler" and rng.randf() < 0.5):
		_set_override(&"cheer", 2.6)
		_bark(&"cheer")
	else:
		_set_override(&"watch", 2.2)


func begin_conversation(with: Node3D) -> void:
	if override == &"flee" or override == &"cower":
		_clear_override()
	override = &"converse"
	npc.stop_moving()
	if _posed != &"sit" and _posed != &"meditate":
		npc.rig.stop_action(0.3)
		npc.face_point(with.global_position)
	npc.rig.look_at_point(with.global_position + Vector3(0, 1.55, 0), 1.0)


func end_conversation() -> void:
	if override == &"converse":
		override = &""
		npc.set_speaking(false)
		if _posed != &"sit" and _posed != &"meditate":
			activity = &""


## Escort: follow `target` (the player) until cleared.
func start_follow(target: Node3D) -> void:
	_leave_pose()
	override = &"follow"
	follow_target = target


func stop_follow() -> void:
	if override == &"follow":
		override = &""
		activity = &""
		follow_target = null
		npc.stop_moving()


func _tick_follow() -> void:
	if follow_target == null or not is_instance_valid(follow_target):
		stop_follow()
		return
	var d := npc.global_position.distance_to(follow_target.global_position)
	if d > 45.0:
		npc.stop_moving()
		_o_t -= THINK
		if _o_t <= 0.0:
			_o_t = 8.0
			_bark(&"escort_wait")
	elif d > 3.0:
		var behind := follow_target.global_position + (npc.global_position - follow_target.global_position).normalized() * 2.2
		npc.move_to(behind, NpcCharacter.RUN * 0.8 if d > 8.0 else NpcCharacter.BRISK)
	else:
		npc.stop_moving()
		npc.face_point(follow_target.global_position)


func _bark(situation: StringName) -> void:
	if npc.director != null:
		(npc.director as NpcDirector).bark(npc, situation)
