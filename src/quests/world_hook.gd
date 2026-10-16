extends Node
## Quests hook of the playable scenes (WorldHooks): binds the Quests autoload to the scene
## (HUD quest provider, compass target), adds the quest props manager, runs challenge
## objectives (BendingChallenge) and the auto-starting quests once play begins. In the training
## grounds the quest system is disabled (nothing is saved there).

var scene: Node = null
var props: QuestProps = null
var challenge: BendingChallenge = null


func world_setup(p_scene: Node) -> void:
	scene = p_scene
	Quests.scene = p_scene
	var tutorial := bool(p_scene.get("is_tutorial"))
	Quests.enabled = not tutorial
	if tutorial:
		return
	props = QuestProps.new()
	var root: Node = p_scene.get("props_root")
	(root if root != null else p_scene).add_child(props)
	if not Quests.challenge_requested.is_connected(_on_challenge):
		Quests.challenge_requested.connect(_on_challenge)
	if p_scene.has_method("set_quest_provider"):
		p_scene.call("set_quest_provider", Quests)


func player_spawned(player: Node3D) -> void:
	if props != null:
		props.player = player


func world_ready() -> void:
	if not Quests.enabled:
		return
	Quests.run_auto_starts()
	if GameState.tracked_quest != &"" and Quests.is_active(GameState.tracked_quest):
		Events.quest_updated.emit(GameState.tracked_quest)


func world_exit() -> void:
	if Quests.challenge_requested.is_connected(_on_challenge):
		Quests.challenge_requested.disconnect(_on_challenge)
	if Quests.scene == scene:
		Quests.scene = null
	Quests.enabled = true


var _poll := 0.0
var _armed: Dictionary = {}     # "q|o" -> false after a run until the player steps out of range


## Challenge objectives with an `at` place start by themselves when the player arrives there
## (trials away from any NPC): {"type": &"challenge", "at": {"poi": ...}, "radius": 14, "challenge": {...}}.
func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0 or not Quests.enabled or scene == null:
		return
	_poll = 0.5
	var pl := Quests.get_player()
	if pl == null:
		return
	for e in Quests.active_objectives(&"challenge"):
		var od: Dictionary = e["objective"]
		if not od.has("at"):
			continue
		var key := "%s|%s" % [e["quest"], od["id"]]
		var at := QuestTargets.resolve(od["at"])
		if not at.is_finite():
			continue
		var d := Vector2(pl.global_position.x - at.x, pl.global_position.z - at.z).length()
		var r := float(od.get("radius", 14.0))
		if d > r * 1.6:
			_armed[key] = true
		elif d <= r and bool(_armed.get(key, true)) and (challenge == null or not is_instance_valid(challenge) or not challenge.running):
			_armed[key] = false
			_on_challenge(e["quest"], od["id"], od.get("challenge", {}))


## A dialogue asked for a challenge objective: run it in front of the player.
func _on_challenge(q: StringName, o: StringName, spec: Dictionary) -> void:
	if challenge != null and is_instance_valid(challenge) and challenge.running:
		return
	var pl := Quests.get_player()
	if pl == null or scene == null:
		return
	challenge = BendingChallenge.begin(scene, spec, pl)
	var ok: bool = await challenge.finished
	if ok:
		Quests.report(&"challenge", o, 1, {"quest": q})
	else:
		Events.notify.emit("Challenge failed  ·  talk to them to try again", &"warning")
