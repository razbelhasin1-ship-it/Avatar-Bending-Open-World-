class_name QuestSystem
extends Node
## The quest system (autoload "Quests", docs/modules/quests_npcs.md).
##
## Quest definitions come from data/quests/*.gd (QuestDefs). The live state of every quest is
## stored in GameState.quests (so SaveSystem persists it with no extra code):
##   GameState.quests["wt_first_form"] = {"state": "active" | "completed" | "failed", "stage": 1,
##       "objectives": {"targets": 3}, "log": [0, 1], "started": play_time, "completed": play_time}
##
##   Quests.start(&"wt_first_form")              Quests.state(id) -> &"none" | &"active" | &"completed" | &"failed"
##   Quests.complete_objective(q, o)              Quests.report(&"talk", &"wt_siku")    # talk / interact / escort / challenge
##   Quests.track(id)                             Quests.get_quest_display(id)          # HUD provider contract
##   Quests.journal()                             Quests.journal_entry(id)              # journal UI data
##   Quests.npc_marker(npc_id) -> &"available" | &"turn_in" | &""
##
## Objective progress is driven by the global events (Events.ability_used / hit_landed /
## enemy_killed / item_collected / poi_discovered), the encounter director (site clears,
## surrenders) and a 4 Hz poll (go_to, collect). Emits Events.quest_started / quest_updated /
## objective_completed / quest_completed; rewards through QuestRewards.

## Any change of a quest (state, stage, progress, tracking). The journal UI can refresh on it.
signal quest_changed(quest_id: StringName)
## A challenge objective wants to run (the world hook's challenge host listens).
signal challenge_requested(quest_id: StringName, objective_id: StringName, spec: Dictionary)

const POLL_INTERVAL := 0.25
const STATE_NONE := &"none"
const STATE_ACTIVE := &"active"
const STATE_COMPLETED := &"completed"
const STATE_FAILED := &"failed"

## StringName id -> normalized quest Dictionary (QuestDefs.normalize).
var defs: Dictionary = {}
## Ids in data order (journal order for equal priority).
var order: Array[StringName] = []
## Set by the world hook: the PlayableScene (null outside the world).
var scene: Node = null
## False in the tutorial (nothing progresses, nothing starts).
var enabled := true

var _player: Node3D = null
var _poll := 0.0
var _counted: Dictionary = {}       # enemy instance id -> true (each defeat counts once)
var _director: EncounterDirector = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	reload_defs()
	Events.player_spawned.connect(func(p: Node3D) -> void: _player = p)
	Events.item_collected.connect(_on_item_collected)
	Events.poi_discovered.connect(_on_poi_discovered)
	Events.ability_used.connect(_on_ability_used)
	Events.hit_landed.connect(_on_hit_landed)
	Events.enemy_killed.connect(func(e: Node3D, _k: Node) -> void: _on_enemy_defeated(e, &"killed"))


## (Re)loads the data files. Runtime registrations (register_quest) are kept.
func reload_defs() -> void:
	for q in QuestDefs.load_all():
		_add_def(q)


## Adds or replaces a quest definition at runtime (tests, other modules).
func register_quest(def: Dictionary) -> void:
	_add_def(QuestDefs.normalize(def))


## Removes a runtime-registered quest definition (tests).
func unregister_quest(id: StringName) -> void:
	defs.erase(id)
	order.erase(id)


func _add_def(q: Dictionary) -> void:
	var id: StringName = q["id"]
	if id == &"":
		return
	if not defs.has(id):
		order.append(id)
	defs[id] = q


func get_def(id: StringName) -> Dictionary:
	return defs.get(id, {})


func has_quest(id: StringName) -> bool:
	return defs.has(id)


# --- state queries ---------------------------------------------------------------------------

func _rec(id: StringName) -> Dictionary:
	var r: Variant = GameState.quests.get(String(id))
	return r if r is Dictionary else {}


func state(id: StringName) -> StringName:
	var r := _rec(id)
	if r.is_empty():
		return STATE_NONE
	return StringName(str(r.get("state", "none")))


func is_active(id: StringName) -> bool:
	return state(id) == STATE_ACTIVE


func is_completed(id: StringName) -> bool:
	return state(id) == STATE_COMPLETED


## Not started and its `requires` hold.
func is_available(id: StringName) -> bool:
	if not defs.has(id) or state(id) != STATE_NONE:
		return false
	return QuestConditions.check((defs[id] as Dictionary).get("requires"))


func current_stage(id: StringName) -> int:
	return int(_rec(id).get("stage", 0))


func stage_def(id: StringName, index: int = -1) -> Dictionary:
	var d := get_def(id)
	var stages: Array = d.get("stages", [])
	var i := current_stage(id) if index < 0 else index
	return stages[i] if i >= 0 and i < stages.size() else {}


func objective_def(q: StringName, o: StringName) -> Dictionary:
	for st: Dictionary in get_def(q).get("stages", []):
		for od: Dictionary in st["objectives"]:
			if od["id"] == o:
				return od
	return {}


func progress(q: StringName, o: StringName) -> int:
	var objs: Dictionary = _rec(q).get("objectives", {})
	return int(objs.get(String(o), 0))


func is_objective_done(q: StringName, o: StringName) -> bool:
	if is_completed(q):
		return true
	var od := objective_def(q, o)
	return not od.is_empty() and progress(q, o) >= int(od["count"])


## In the active quest's current stage and not done yet.
func is_objective_active(q: StringName, o: StringName) -> bool:
	if not is_active(q):
		return false
	for od: Dictionary in stage_def(q).get("objectives", []):
		if od["id"] == o:
			return progress(q, o) < int(od["count"])
	return false


func active_quests() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in order:
		if is_active(id):
			out.append(id)
	for k: Variant in GameState.quests:
		var id2 := StringName(str(k))
		if not out.has(id2) and is_active(id2) and defs.has(id2):
			out.append(id2)
	return out


## [{quest, objective (Dictionary)}] of every unfinished objective in an active stage.
func active_objectives(type: StringName = &"") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q in active_quests():
		for od: Dictionary in stage_def(q).get("objectives", []):
			if (type == &"" or od["type"] == type) and progress(q, od["id"]) < int(od["count"]):
				out.append({"quest": q, "objective": od})
	return out


func get_player() -> Node3D:
	if _player != null and is_instance_valid(_player) and _player.is_inside_tree():
		return _player
	var t := get_tree()
	_player = t.get_first_node_in_group(&"player") as Node3D if t else null
	return _player


# --- lifecycle --------------------------------------------------------------------------------

## Starts a quest (when it exists and was never started). Returns true when started.
func start(id: StringName, opts: Dictionary = {}) -> bool:
	if not enabled or not defs.has(id) or state(id) != STATE_NONE:
		return false
	var d: Dictionary = defs[id]
	GameState.quests[String(id)] = {"state": "active", "stage": 0, "objectives": {}, "log": [0], "started": GameState.play_time}
	QuestActions.run(d.get("on_start", []))
	Events.quest_started.emit(id)
	if not bool(opts.get("silent", false)):
		Events.notify.emit("New quest  ·  %s" % d["title"], &"quest")
	if GameState.tracked_quest == &"" or not is_active(GameState.tracked_quest) or d["kind"] == &"main" or bool(opts.get("track", false)):
		track(id)
	quest_changed.emit(id)
	_enter_stage(id)
	return true


## Completes an objective outright (dialogue actions, scripted events).
func complete_objective(q: StringName, o: StringName) -> void:
	var od := objective_def(q, o)
	if od.is_empty() or not is_objective_active(q, o):
		return
	_set_progress(q, o, int(od["count"]))


## Adds progress to an active objective.
func add_progress(q: StringName, o: StringName, amount: int = 1) -> void:
	if not is_objective_active(q, o):
		return
	_set_progress(q, o, progress(q, o) + amount)


func _set_progress(q: StringName, o: StringName, value: int) -> void:
	var od := objective_def(q, o)
	if od.is_empty():
		return
	var target := int(od["count"])
	var r := _rec(q)
	var objs: Dictionary = r.get("objectives", {})
	var before := int(objs.get(String(o), 0))
	var v := clampi(value, 0, target)
	if v == before:
		return
	objs[String(o)] = v
	r["objectives"] = objs
	GameState.quests[String(q)] = r
	if v >= target and before < target:
		Events.objective_completed.emit(q, o)
		if not String(od["text"]).is_empty():
			Events.notify.emit(_objective_text(od, v) + "  ·  done", &"info")
	Events.quest_updated.emit(q)
	quest_changed.emit(q)
	_check_stage(q)


func _check_stage(q: StringName) -> void:
	if not is_active(q):
		return
	var st := stage_def(q)
	for od: Dictionary in st.get("objectives", []):
		if not bool(od["optional"]) and progress(q, od["id"]) < int(od["count"]):
			return
	QuestActions.run(st.get("on_complete", []))
	if not is_active(q):
		return
	var stages: Array = get_def(q)["stages"]
	var next_i := current_stage(q) + 1
	if next_i >= stages.size():
		_complete(q)
		return
	var r := _rec(q)
	r["stage"] = next_i
	var log: Array = r.get("log", [])
	log.append(next_i)
	r["log"] = log
	GameState.quests[String(q)] = r
	Events.quest_updated.emit(q)
	quest_changed.emit(q)
	_enter_stage(q)


## A stage became current: objectives that are already satisfied complete at once.
func _enter_stage(q: StringName) -> void:
	for od: Dictionary in stage_def(q).get("objectives", []):
		if is_active(q):
			_evaluate(q, od, true)


func _complete(q: StringName) -> void:
	var d := get_def(q)
	var r := _rec(q)
	r["state"] = "completed"
	r["completed"] = GameState.play_time
	GameState.quests[String(q)] = r
	QuestActions.run(d.get("on_complete", []))
	var parts := QuestRewards.grant(d.get("rewards", {}), "Quest: %s" % d["title"])
	var toast := "Quest complete  ·  %s" % d["title"]
	if not parts.is_empty():
		toast += "  ·  " + "  ·  ".join(parts)
	Events.notify.emit(toast, &"quest")
	GameState.incr_stat("quests_completed")
	Events.quest_completed.emit(q)
	quest_changed.emit(q)
	var nxt: StringName = d.get("next", &"")
	if nxt != &"" and state(nxt) == STATE_NONE:
		start(nxt, {"track": GameState.tracked_quest == q})
	if GameState.tracked_quest == q or not is_active(GameState.tracked_quest):
		_track_fallback()


## Force-completes a quest (debug, tests): every objective, stage actions and rewards.
func force_complete(q: StringName) -> void:
	if state(q) == STATE_NONE:
		start(q, {"silent": true})
	var guard := 0
	while is_active(q) and guard < 64:
		guard += 1
		for od: Dictionary in stage_def(q).get("objectives", []):
			if is_active(q):
				_set_progress(q, od["id"], int(od["count"]))


func fail(q: StringName, reason: String = "") -> void:
	if not is_active(q):
		return
	var r := _rec(q)
	r["state"] = "failed"
	GameState.quests[String(q)] = r
	Events.notify.emit("Quest failed  ·  %s%s" % [get_def(q).get("title", q), ("  ·  " + reason) if reason != "" else ""], &"warning")
	Events.quest_updated.emit(q)
	quest_changed.emit(q)
	if GameState.tracked_quest == q:
		_track_fallback()


## Drops a side quest back to "not started" (main quests cannot be abandoned).
func abandon(q: StringName) -> bool:
	if not is_active(q) or get_def(q).get("kind", &"side") == &"main":
		return false
	GameState.quests.erase(String(q))
	if GameState.tracked_quest == q:
		_track_fallback()
	quest_changed.emit(q)
	return true


## Erases a quest's state (tests / debug).
func reset_quest(q: StringName) -> void:
	GameState.quests.erase(String(q))
	quest_changed.emit(q)


# --- tracking + HUD ----------------------------------------------------------------------------

func track(q: StringName) -> void:
	if q != &"" and not is_active(q):
		return
	GameState.tracked_quest = q
	if q != &"":
		Events.quest_updated.emit(q)
	quest_changed.emit(q)


func _track_fallback() -> void:
	var pick: StringName = &""
	for id in active_quests():
		if pick == &"" or (get_def(id)["kind"] == &"main" and get_def(pick)["kind"] != &"main"):
			pick = id
	GameState.tracked_quest = pick
	if pick != &"":
		Events.quest_updated.emit(pick)


## HUD quest provider contract (docs/modules/ui.md): title, current objectives, target.
func get_quest_display(q: StringName) -> Dictionary:
	if not is_active(q):
		return {}
	var d := get_def(q)
	var objs: Array = []
	var target := Vector3.INF
	for od: Dictionary in stage_def(q).get("objectives", []):
		var p := progress(q, od["id"])
		var n := int(od["count"])
		var e := {"text": _objective_text(od, p), "done": p >= n}
		if n > 1:
			e["count"] = p
			e["target"] = n
		objs.append(e)
		if p < n and not target.is_finite():
			target = objective_position(q, od)
	var out := {"id": q, "title": String(d["title"]), "objectives": objs}
	if target.is_finite():
		out["target"] = target
	return out


func _objective_text(od: Dictionary, _p: int) -> String:
	return String(od["text"])


## World position of an objective (compass / map marker); INF when it has none.
func objective_position(q: StringName, od: Dictionary) -> Vector3:
	match od["type"]:
		&"go_to":
			return QuestTargets.resolve(od.get("target"))
		&"talk_to":
			return NpcRegistry.position_of(od["npc"])
		&"escort":
			return QuestTargets.resolve(od.get("to"))
		&"discover":
			return QuestTargets.resolve({"poi": od["poi"]})
		&"defeat":
			if od["site"] != &"":
				return QuestTargets.site_center(od["site"])
			return QuestTargets.resolve(od.get("near"))
		&"challenge":
			if od.has("at"):
				return QuestTargets.resolve(od["at"])
			if od.has("npc"):
				return NpcRegistry.position_of(StringName(str(od["npc"])))
	if od.has("target"):
		return QuestTargets.resolve(od["target"])
	if od.has("near"):
		return QuestTargets.resolve(od["near"])
	var props: Array = od.get("props", [])
	if not props.is_empty():
		var pl := get_player()
		var best := Vector3.INF
		for i in props.size():
			if QuestProps.is_taken(q, od["id"], i):
				continue
			var pp := QuestTargets.resolve((props[i] as Dictionary).get("at"))
			if pl == null or not best.is_finite() or pl.global_position.distance_to(pp) < pl.global_position.distance_to(best):
				best = pp
		return best
	return Vector3.INF


## &"turn_in" when an active objective needs this NPC, &"available" when it offers a quest.
func npc_marker(npc_id: StringName) -> StringName:
	if npc_id == &"":
		return &""
	for e in active_objectives():
		var od: Dictionary = e["objective"]
		if (od["type"] == &"talk_to" or od["type"] == &"challenge") and StringName(str(od.get("npc", ""))) == npc_id:
			return &"turn_in"
	for id in order:
		if get_def(id)["giver"] == npc_id and is_available(id) and get_def(id).get("auto_start") == null:
			return &"available"
	return &""


## Quests this NPC can offer right now.
func available_from(npc_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in order:
		if get_def(id)["giver"] == npc_id and is_available(id):
			out.append(id)
	return out


## Starts every quest whose `auto_start` condition holds (new game openings, cross-nation hooks).
func run_auto_starts() -> void:
	if not enabled:
		return
	for id in order:
		var d: Dictionary = defs[id]
		if d.get("auto_start") != null and state(id) == STATE_NONE and QuestConditions.check(d["auto_start"]) and is_available(id):
			start(id)


# --- journal API ---------------------------------------------------------------------------------

## Journal entries (docs/modules/quests_npcs.md "Journal API"). filter: &"all", &"active",
## &"completed". Active first (tracked, main, side), then completed (most recent first).
func journal(filter: StringName = &"all") -> Array[Dictionary]:
	var act: Array[Dictionary] = []
	var done: Array[Dictionary] = []
	for k: Variant in GameState.quests:
		var id := StringName(str(k))
		if not defs.has(id):
			continue
		var s := state(id)
		if s == STATE_ACTIVE and filter != &"completed":
			act.append(journal_entry(id))
		elif (s == STATE_COMPLETED or s == STATE_FAILED) and filter != &"active":
			done.append(journal_entry(id))
	act.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["tracked"]) != bool(b["tracked"]):
			return bool(a["tracked"])
		if (a["kind"] == &"main") != (b["kind"] == &"main"):
			return a["kind"] == &"main"
		return float(a["started"]) < float(b["started"]))
	done.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["completed"]) > float(b["completed"]))
	act.append_array(done)
	return act


## Everything the journal shows for one quest (works for any state, also "none").
func journal_entry(q: StringName) -> Dictionary:
	var d := get_def(q)
	if d.is_empty():
		return {}
	var r := _rec(q)
	var s := state(q)
	var cur := current_stage(q)
	var stages: Array = []
	var log_lines: Array[String] = []
	var reached: Array = r.get("log", [])
	var i := 0
	for st: Dictionary in d["stages"]:
		var visible_stage := s == STATE_COMPLETED or reached.has(i) or (s == STATE_ACTIVE and i <= cur)
		if visible_stage:
			var objs: Array = []
			for od: Dictionary in st["objectives"]:
				var p := progress(q, od["id"]) if s != STATE_COMPLETED else int(od["count"])
				objs.append({"id": od["id"], "text": String(od["text"]), "done": p >= int(od["count"]),
					"count": p, "target": int(od["count"]), "optional": bool(od["optional"])})
			stages.append({"id": st["id"], "text": String(st["text"]), "current": s == STATE_ACTIVE and i == cur,
				"done": s == STATE_COMPLETED or i < cur, "objectives": objs})
			if not String(st["text"]).is_empty():
				log_lines.append(String(st["text"]))
		i += 1
	var giver: StringName = d["giver"]
	return {
		"id": q, "title": String(d["title"]), "kind": d["kind"], "nation": d["nation"], "state": s,
		"tracked": GameState.tracked_quest == q, "summary": String(d["summary"]),
		"description": String(d["description"]), "location": String(d.get("location", "")),
		"giver": giver, "giver_name": NpcRegistry.display_name(giver) if giver != &"" else "",
		"stage": cur, "stages": stages, "log": log_lines, "rewards": d.get("rewards", {}),
		"rewards_text": rewards_text(d.get("rewards", {})),
		"started": float(r.get("started", 0.0)), "completed": float(r.get("completed", 0.0)),
		"target": get_quest_display(q).get("target", Vector3.INF),
	}


static func rewards_text(r: Dictionary) -> String:
	var parts := PackedStringArray()
	if int(r.get("xp", 0)) > 0:
		parts.append("%d XP" % int(r["xp"]))
	if int(r.get("currency", 0)) > 0:
		parts.append("%d coins" % int(r["currency"]))
	var items: Dictionary = r.get("items", {})
	for id: Variant in items:
		parts.append("%s ×%d" % [TradeGoods.display_name(StringName(str(id))), int(items[id])])
	if not (r.get("techniques", []) as Array).is_empty():
		parts.append("a new technique")
	if int(r.get("skill_points", 0)) > 0:
		parts.append("%d skill point(s)" % int(r["skill_points"]))
	return ", ".join(parts)


## Map / compass markers: [{quest, objective, position, kind: &"objective" | &"giver", text}].
func map_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in active_objectives():
		var p := objective_position(e["quest"], e["objective"])
		if p.is_finite():
			out.append({"quest": e["quest"], "objective": (e["objective"] as Dictionary)["id"], "position": p,
				"kind": &"objective", "text": String((e["objective"] as Dictionary)["text"]), "tracked": GameState.tracked_quest == e["quest"]})
	for id in order:
		var g: StringName = get_def(id)["giver"]
		if g != &"" and is_available(id) and get_def(id).get("auto_start") == null:
			var gp := NpcRegistry.position_of(g)
			if gp.is_finite():
				out.append({"quest": id, "objective": &"", "position": gp, "kind": &"giver", "text": String(get_def(id)["title"]), "tracked": false})
	return out


# --- reports from NPCs, props, challenges -----------------------------------------------------

## Reports an event for objectives: kind &"talk" (key = npc id), &"interact" (key = prop key),
## &"escort" (key = npc id: arrived), &"challenge" (key = objective id, data.quest), &"custom".
func report(kind: StringName, key: StringName, amount: int = 1, data: Dictionary = {}) -> void:
	if not enabled:
		return
	var type: StringName = {&"talk": &"talk_to", &"interact": &"interact", &"escort": &"escort",
		&"challenge": &"challenge", &"collect": &"collect"}.get(kind, kind)
	for e in active_objectives(type):
		var q: StringName = e["quest"]
		var od: Dictionary = e["objective"]
		if data.has("quest") and StringName(str(data["quest"])) != q:
			continue
		match type:
			&"talk_to", &"escort":
				if od["npc"] == key:
					complete_objective(q, od["id"])
			&"interact":
				if od["key"] == key:
					add_progress(q, od["id"], amount)
			&"challenge":
				if od["id"] == key:
					complete_objective(q, od["id"])
			_:
				if StringName(str(od.get("key", ""))) == key:
					add_progress(q, od["id"], amount)


## Starts a challenge objective (dialogue action) through the world's challenge host.
func request_challenge(q: StringName, o: StringName) -> bool:
	var od := objective_def(q, o)
	if od.is_empty() or not is_objective_active(q, o):
		return false
	challenge_requested.emit(q, o, od.get("challenge", {}))
	return true


# --- event driven progress ----------------------------------------------------------------------

func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0 or not enabled:
		return
	_poll = POLL_INTERVAL
	_bind_director()
	for e in active_objectives():
		_evaluate(e["quest"], e["objective"], false)


func _evaluate(q: StringName, od: Dictionary, entering: bool) -> void:
	if not is_objective_active(q, od["id"]):
		return
	match od["type"]:
		&"go_to":
			var pl := get_player()
			var t := QuestTargets.resolve(od.get("target"))
			if pl != null and t.is_finite():
				var dv := pl.global_position - t
				if Vector2(dv.x, dv.z).length() <= float(od["radius"]) and absf(dv.y) < maxf(25.0, float(od["radius"])):
					complete_objective(q, od["id"])
		&"collect":
			var have := GameState.item_count(od["item"])
			if have > progress(q, od["id"]):
				_set_progress(q, od["id"], have)
				if have >= int(od["count"]) and bool(od.get("take", false)):
					GameState.add_item(od["item"], -int(od["count"]))
		&"discover":
			if GameState.discovered_pois.has(String(od["poi"])):
				complete_objective(q, od["id"])
		&"defeat":
			if entering and od["site"] != &"" and _director != null:
				var s := _director.get_site(od["site"])
				if s != null and s.alive_members() == 0:
					Events.notify.emit("%s already lies quiet." % s.display_name, &"info")
					complete_objective(q, od["id"])


func _on_item_collected(item: StringName, _count: int) -> void:
	for e in active_objectives(&"collect"):
		if (e["objective"] as Dictionary)["item"] == item:
			_evaluate(e["quest"], e["objective"], false)


func _on_poi_discovered(poi: StringName) -> void:
	for e in active_objectives(&"discover"):
		if (e["objective"] as Dictionary)["poi"] == poi:
			complete_objective(e["quest"], (e["objective"] as Dictionary)["id"])


func _on_ability_used(id: StringName) -> void:
	for e in active_objectives(&"use_ability"):
		var od: Dictionary = e["objective"]
		if od["mode"] == &"use" and _ability_matches(od, id) and _near_ok(od):
			add_progress(e["quest"], od["id"])


func _on_hit_landed(hit: HitInfo, target: Node, result: int) -> void:
	if hit == null or result == Combat.Result.IGNORED or result == Combat.Result.DODGED:
		return
	if hit.source == null or not is_instance_valid(hit.source) or not (hit.source as Node).is_in_group(&"player"):
		return
	for e in active_objectives(&"use_ability"):
		var od: Dictionary = e["objective"]
		if od["mode"] != &"hit" or not _ability_matches(od, hit.ability_id) or not _near_ok(od):
			continue
		match od["on"]:
			&"dummy":
				if not (target is Node and ((target as Node).is_in_group(&"training_dummy") or (target as Node).is_in_group(&"quest_target"))):
					continue
			&"enemy":
				if not (target is Node and (target as Node).is_in_group(&"enemy")):
					continue
		add_progress(e["quest"], od["id"])


func _ability_matches(od: Dictionary, id: StringName) -> bool:
	if od["ability"] != &"":
		return od["ability"] == id
	var slot: StringName = od["slot"]
	if slot == &"any" or slot == &"":
		return true
	var d := AbilityRegistry.get_def(id)
	return d != null and AbilityDef.SLOT_NAMES.get(d.slot, &"") == slot


func _near_ok(od: Dictionary) -> bool:
	if not od.has("near"):
		return true
	var pl := get_player()
	var p := QuestTargets.resolve(od["near"])
	return pl != null and p.is_finite() and pl.global_position.distance_to(p) <= float(od.get("radius", 40.0))


func _bind_director() -> void:
	var d := EncounterDirector.instance()
	if d == _director:
		return
	_director = d
	if d != null:
		d.enemy_spawned.connect(func(e: EnemyBase) -> void:
			if not e.defeated.is_connected(_on_enemy_defeated):
				e.defeated.connect(_on_enemy_defeated))
		d.site_cleared.connect(_on_site_cleared)
		for e2 in d.enemies:
			if is_instance_valid(e2) and not e2.defeated.is_connected(_on_enemy_defeated):
				e2.defeated.connect(_on_enemy_defeated)


## Hook for enemies created outside the director (challenges, scripted fights).
func watch_enemy(e: EnemyBase) -> void:
	if e != null and not e.defeated.is_connected(_on_enemy_defeated):
		e.defeated.connect(_on_enemy_defeated)


func _on_enemy_defeated(enemy: Node3D, _how: StringName) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var iid := enemy.get_instance_id()
	if _counted.has(iid):
		return
	_counted[iid] = true
	if _counted.size() > 512:
		_counted.clear()
		_counted[iid] = true
	var site := StringName(str(enemy.get("site_id"))) if "site_id" in enemy else &""
	var arch := StringName(str(enemy.get("archetype_id"))) if "archetype_id" in enemy else &""
	var fac := StringName(str(enemy.get("faction"))) if "faction" in enemy else &""
	for e in active_objectives(&"defeat"):
		var od: Dictionary = e["objective"]
		if od["site"] != &"" and od["site"] != site:
			continue
		if od["archetype"] != &"" and od["archetype"] != arch:
			continue
		if od["faction"] != &"" and od["faction"] != fac:
			continue
		if od.has("near") and QuestTargets.resolve(od["near"]).distance_to(enemy.global_position) > float(od.get("radius", 60.0)):
			continue
		add_progress(e["quest"], od["id"])


func _on_site_cleared(site: EncounterSite) -> void:
	for e in active_objectives(&"defeat"):
		var od: Dictionary = e["objective"]
		if od["site"] == site.id and bool(od.get("clear", true)):
			complete_objective(e["quest"], od["id"])
