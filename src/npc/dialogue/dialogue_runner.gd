class_name DialogueRunner
extends Node
## Plays conversations with NPCs on the playable scene's DialogueBox (docs/modules/quests_npcs.md
## "Dialogue"): picks the NPC's tree (named: first `talk` entry whose condition holds; townsfolk:
## small talk, merchants: wares), holds the player in the Cinematic state, frames the two speakers
## with the player camera's cinematic mode, runs node actions, shows lines (typewriter, mouth
## flaps) and choices, then reports the talk to the quest system and runs the UI actions (shop,
## training, travel, challenge). Every wait has a timeout (no stuck states); B / Esc on a choice
## picks the last option.
##
##   runner.talk(npc)                         # NpcCharacter
##   await runner.run_tree(npc, tree)         # any tree dictionary
##   var i: int = await runner.ask(npc, "Which lesson?", ["Ice", "Water", "Not now"])

signal finished(npc: Node)

const LINE_TIMEOUT := 90.0
const MAX_NODES := 64

var busy := false
var current: NpcCharacter = null
var rng := RandomNumberGenerator.new()
## Last conversation's lines (tests / playtests): [[speaker, text], ...].
var transcript: Array = []

var _box: DialogueBox = null
var _scene: Node = null
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _framed := false
var _advanced := false
var _choice := -1


func _ready() -> void:
	name = "DialogueRunner"
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()


func _find_box() -> bool:
	_scene = get_tree().get_first_node_in_group(&"playable_scene")
	if _scene != null and _scene.get("dialogue") is DialogueBox:
		_box = _scene.get("dialogue")
	return _box != null and is_instance_valid(_box)


## Starts the conversation with `npc` (no-op while another one runs).
func talk(npc: NpcCharacter) -> void:
	if busy or npc == null or not _find_box():
		return
	if _scene.has_method("is_dialogue_open") and bool(_scene.call("is_dialogue_open")):
		return
	var tree := tree_for(npc)
	if tree.is_empty():
		return
	await run_tree(npc, tree)


## The tree an NPC talks with right now.
func tree_for(npc: NpcCharacter) -> Dictionary:
	if npc.npc_id != &"":
		var tid := NpcRegistry.pick_tree(npc.npc_id)
		return NpcRegistry.dialogue_tree(tid)
	return ambient_tree(npc)


## Townsfolk: a line of small talk; merchants offer their wares; guards a short word.
func ambient_tree(npc: NpcCharacter) -> Dictionary:
	var lines := NpcBarks.small_talk(npc.nation, npc.role)
	var text := lines[rng.randi_range(0, lines.size() - 1)] if not lines.is_empty() else "..."
	if npc.role == &"merchant":
		var greet := NpcBarks.line(npc.nation, StringName("merchant_" + String(npc.record.get("goods", ""))), rng)
		if greet.is_empty():
			greet = NpcBarks.line(npc.nation, &"merchant", rng)
		return DialogueTree.normalize(&"ambient_merchant", {"nodes": {
			"start": {"text": greet if greet != "" else "Have a look, have a look!", "choices": [
				{"text": "Show me your wares.", "do": [["shop", MerchantStock.shop_id_for(npc)]], "end": true},
				{"text": "What news?", "next": "news"},
				{"text": "Just looking.", "end": true}]},
			"news": {"text": text, "end": true}}})
	return DialogueTree.normalize(&"ambient", {"nodes": {"start": {"text": text, "end": true}}})


## Runs a tree with `npc` (null = narrator conversation) to its end.
func run_tree(npc: NpcCharacter, tree: Dictionary) -> void:
	if busy or not _find_box():
		return
	busy = true
	current = npc
	transcript.clear()
	var pl := Quests.get_player()
	await _settle_box()
	_begin(npc, pl)
	var deferred: Array = []
	var key := String(tree.get("start", "start"))
	var steps := 0
	while key != "" and steps < MAX_NODES and _alive():
		steps += 1
		var node := DialogueTree.get_node_data(tree, key)
		if node.is_empty():
			break
		deferred.append_array(QuestActions.run(node.get("do", [])))
		if node.has("branch") and not node.has("text") and not node.has("lines"):
			key = DialogueTree.route(node)
			continue
		if node.has("emote") and npc != null:
			npc.rig.play_action(StringName(str(node["emote"])))
		var speaker := String(node.get("speaker", npc.display_name() if npc != null else ""))
		var lines := DialogueTree.lines_of(node, rng)
		var choices := DialogueTree.visible_choices(node)
		for i in lines.size():
			var text := DialogueTree.format_line(lines[i])
			transcript.append([speaker, text])
			if i == lines.size() - 1 and not choices.is_empty():
				var labels: Array = choices.map(func(c: Dictionary) -> String: return DialogueTree.format_line(String(c["text"])))
				var idx := await _ask(npc, speaker, text, labels)
				var c: Dictionary = choices[clampi(idx, 0, choices.size() - 1)]
				transcript.append(["You", String(c["text"])])
				deferred.append_array(QuestActions.run(c.get("do", [])))
				key = "" if bool(c.get("end", false)) else String(c.get("next", ""))
				break
			await _say(npc, speaker, text)
		if choices.is_empty():
			if node.has("branch"):
				key = DialogueTree.route(node)
			else:
				key = "" if bool(node.get("end", false)) else String(node.get("next", ""))
		if not _alive():
			break
	_end(npc, pl)
	if npc != null and npc.npc_id != &"":
		Quests.report(&"talk", npc.npc_id)
	busy = false
	current = null
	finished.emit(npc)
	for a: Array in deferred:
		await _run_ui_action(a, npc)


## A one-off question outside a tree (trainer menus...). Returns the chosen index.
func ask(npc: NpcCharacter, text: String, options: Array) -> int:
	if busy or not _find_box():
		return options.size() - 1
	busy = true
	var pl := Quests.get_player()
	await _settle_box()
	_begin(npc, pl)
	var speaker := npc.display_name() if npc != null else ""
	var i := await _ask(npc, speaker, text, options)
	_end(npc, pl)
	busy = false
	return i


## Lines without choices (trainer results...).
func say_lines(npc: NpcCharacter, lines: Array) -> void:
	if busy or not _find_box():
		return
	busy = true
	var pl := Quests.get_player()
	await _settle_box()
	_begin(npc, pl)
	for l: Variant in lines:
		if not _alive():
			break
		await _say(npc, npc.display_name() if npc != null else "", DialogueTree.format_line(String(l)))
	_end(npc, pl)
	busy = false


## Waits out the box's closing fade: DialogueBox hides itself 0.15 s after close(), so opening it
## again inside that window (a trainer menu or a shop line right after a tree) would leave it open
## but invisible.
func _settle_box() -> void:
	var frames := 0
	while _box != null and is_instance_valid(_box) and _box.visible and not _box.is_open and frames < 40:
		frames += 1
		await get_tree().process_frame


func _alive() -> bool:
	return is_inside_tree() and _box != null and is_instance_valid(_box) and not (_scene != null and _scene.has_method("is_exiting") and bool(_scene.call("is_exiting")))


func _opts(npc: NpcCharacter) -> Dictionary:
	if npc == null:
		return {}
	return {"element": npc.element()} if ElementDefs.is_valid(npc.element()) else {}


func _say(npc: NpcCharacter, speaker: String, text: String) -> void:
	_advanced = false
	_keep_frame(npc)
	if npc != null:
		npc.set_speaking(true)
	var cb := func() -> void: _advanced = true
	_box.advanced.connect(cb)
	_box.say(speaker, text, _opts(npc))
	var t0 := Time.get_ticks_msec()
	var spoke_until := t0 + int(text.length() / maxf(1.0, _box.reveal_speed) * 1000.0) + 300
	while not _advanced and _alive():
		if Time.get_ticks_msec() > spoke_until and npc != null:
			npc.set_speaking(false)
		if Time.get_ticks_msec() - t0 > int(LINE_TIMEOUT * 1000.0):
			_box.advance()
			_box.advance()
			break
		await get_tree().process_frame
	if _box.advanced.is_connected(cb):
		_box.advanced.disconnect(cb)
	if npc != null and is_instance_valid(npc):
		npc.set_speaking(false)


func _ask(npc: NpcCharacter, speaker: String, text: String, labels: Array) -> int:
	_choice = -1
	_keep_frame(npc)
	if npc != null:
		npc.set_speaking(true)
	var cb := func(i: int) -> void: _choice = i
	_box.choice_made.connect(cb)
	_box.ask(speaker, text, labels, _opts(npc))
	var t0 := Time.get_ticks_msec()
	var spoke_until := t0 + int(text.length() / maxf(1.0, _box.reveal_speed) * 1000.0) + 300
	while _choice < 0 and _alive():
		if Time.get_ticks_msec() > spoke_until and npc != null and is_instance_valid(npc):
			npc.set_speaking(false)
		if Time.get_ticks_msec() - t0 > int(LINE_TIMEOUT * 1000.0):
			_box.advance()
			_box.choose(labels.size() - 1)
			if _choice < 0:
				_choice = labels.size() - 1
			break
		await get_tree().process_frame
	if _box.choice_made.is_connected(cb):
		_box.choice_made.disconnect(cb)
	if npc != null and is_instance_valid(npc):
		npc.set_speaking(false)
	return maxi(_choice, 0)


func _unhandled_input(event: InputEvent) -> void:
	if not busy or _box == null or not is_instance_valid(_box):
		return
	if _box.choices.size() > 0 and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_box.choose(_box.choices.size() - 1)


# --- framing -------------------------------------------------------------------------------------

func _begin(npc: NpcCharacter, pl: Node3D) -> void:
	_mouse_before = Input.mouse_mode
	if not Settings.touch_controls_enabled():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if pl is PlayerCharacter:
		(pl as PlayerCharacter).enter_cinematic(LINE_TIMEOUT * 4.0)
	if npc != null and pl != null:
		npc.begin_conversation(pl)
		_face(pl, npc.global_position)
		_frame(npc, pl)
	Events.dialogue_started.emit(npc)
	_box.open()


func _end(npc: NpcCharacter, pl: Node3D) -> void:
	if _box != null and is_instance_valid(_box):
		_box.close()
	if npc != null and is_instance_valid(npc):
		npc.end_conversation()
	if _framed and pl is PlayerCharacter and is_instance_valid(pl):
		var cam: PlayerCamera = (pl as PlayerCharacter).camera_rig
		if cam != null:
			cam.set_mode(&"default")
	_framed = false
	if pl is PlayerCharacter and is_instance_valid(pl):
		(pl as PlayerCharacter).exit_cinematic()
	Events.dialogue_ended.emit(npc)
	if _mouse_before == Input.MOUSE_MODE_CAPTURED and _scene != null and _scene.has_method("capture_mouse"):
		_scene.call("capture_mouse")


func _face(pl: Node3D, at: Vector3) -> void:
	var d := at - pl.global_position
	if Vector2(d.x, d.z).length() > 0.1:
		pl.rotation.y = atan2(-d.x, -d.z)


## Over-the-shoulder two-shot: behind the player's right shoulder, looking at the NPC's face.
func _frame(npc: NpcCharacter, pl: Node3D) -> void:
	if not (pl is PlayerCharacter):
		return
	var cam: PlayerCamera = (pl as PlayerCharacter).camera_rig
	if cam == null:
		return
	var xf := shot(npc, pl)
	cam.set_mode(&"cinematic", {"transform": xf, "fov": 44.0, "blend": 0.55})
	_framed = true


## The conversation camera transform: over the player's right shoulder (left when something
## stands there: a companion, a passer-by), pulled in when a wall is in the way.
static func shot(npc: Node3D, pl: Node3D) -> Transform3D:
	var hn := npc.global_position + Vector3(0, 1.6, 0)
	var hp := pl.global_position + Vector3(0, 1.6, 0)
	var back := hp - hn
	back.y = 0.0
	if back.length() < 0.2:
		back = pl.global_basis.z
	back = back.normalized()
	var right := Vector3.UP.cross(back).normalized()
	var sep := Vector2(hn.x - hp.x, hn.z - hp.z).length()
	var dist := clampf(1.15 + sep * 0.2, 1.3, 2.0)
	var space := pl.get_world_3d().direct_space_state
	var best := Vector3.INF
	# (side, height, distance behind): right shoulder, left shoulder, then higher and tighter
	for c: Vector3 in [Vector3(1.05, 0.02, dist), Vector3(-1.05, 0.02, dist), Vector3(0.8, 0.5, dist * 0.75),
			Vector3(-0.8, 0.5, dist * 0.75), Vector3(0.55, 0.95, dist * 0.55)]:
		var want := hp + back * c.z + right * c.x + Vector3(0, c.y, 0)
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(hp, want, Layers.CAMERA_BLOCKERS))
		if not r.is_empty():
			want = hp.lerp(r["position"], 0.8)
		if not best.is_finite():
			best = want
		if not occupied(npc, pl, want):
			best = want
			break
	# aim below the NPC's face so it sits in the upper half, clear of the dialogue panel
	var look := hp.lerp(hn, 0.86) + Vector3(0, -0.42, 0)
	return Transform3D(Basis.looking_at(look - best, Vector3.UP), best)


## True when a body (companion, NPC, enemy, animal) other than the two talking fills `at`.
static func occupied(npc: Node3D, pl: Node3D, at: Vector3) -> bool:
	var sh := SphereShape3D.new()
	sh.radius = 0.75
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = Layers.COMPANION | Layers.NPC | Layers.ENEMY | Layers.WILDLIFE
	var ex: Array[RID] = []
	for n: Node3D in [npc, pl]:
		if n is CollisionObject3D:
			ex.append((n as CollisionObject3D).get_rid())
	q.exclude = ex
	return not pl.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Re-frames when something walked into the camera's spot since the last line (a companion
## catching up behind the player).
func _keep_frame(npc: NpcCharacter) -> void:
	if not _framed or npc == null or not is_instance_valid(npc):
		return
	var pl := Quests.get_player()
	if not (pl is PlayerCharacter):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or not occupied(npc, pl, cam.global_position):
		return
	(pl as PlayerCharacter).camera_rig.set_mode(&"cinematic", {"transform": shot(npc, pl), "fov": 44.0, "blend": 0.4})


# --- UI actions after the conversation ------------------------------------------------------------

func _run_ui_action(a: Array, npc: NpcCharacter) -> void:
	var verb := StringName(str(a[0]))
	match verb:
		&"shop":
			var id := StringName(str(a[1])) if a.size() > 1 else MerchantStock.shop_id_for(npc)
			ShopPanel.open_for(get_tree(), id, npc)
		&"train":
			await TrainerLessons.open(self, npc)
		&"challenge":
			Quests.request_challenge(StringName(str(a[1])), StringName(str(a[2])))
		&"travel":
			var to := QuestTargets.resolve(a[1])
			var w := get_tree().get_first_node_in_group(&"world_scene")
			if to.is_finite() and w != null and w.get("travel") != null:
				var ground := Vector3(to.x, WorldData.get_height(to.x, to.z), to.z) if not (a[1] as Dictionary).has("pos") else to
				await (w.get("travel") as TravelSystem).travel_to(Transform3D(Basis(), ground), {"text": String(a[2]) if a.size() > 2 else "Travelling"})
