extends TestCase
## quests_npcs in the real world scene (headless, no WorldContent: named NPCs only): the hooks
## install the NPC director and bind the quest system, the Water opening quest auto-starts, Elder
## Anaaya stands near the spawn, a conversation through the real DialogueRunner + DialogueBox
## advances the quest, the HUD tracker shows the next objective with a compass target, and a
## save / load round trip keeps the progress.

const WORLD := "res://scenes/world/world.tscn"

var _slots: Dictionary = {}


func before_each() -> void:
	WorldData.load_world()
	GameState.reset()
	_slots.clear()
	for i in SaveSystem.MAX_SLOTS:
		if SaveSystem.has_save(i):
			_slots[i] = FileAccess.get_file_as_string(SaveSystem.slot_path(i))
			SaveSystem.delete_save(i)


func after_each() -> void:
	for i in SaveSystem.MAX_SLOTS:
		SaveSystem.delete_save(i)
		if _slots.has(i):
			var f := FileAccess.open(SaveSystem.slot_path(i), FileAccess.WRITE)
			f.store_string(String(_slots[i]))
			f.close()
	GameState.reset()
	Engine.time_scale = 1.0
	for a in InputMap.get_actions():
		if Input.is_action_pressed(a):
			Input.action_release(a)


func _world(e: int) -> WorldScene:
	GameState.new_game(e)
	GameState.intro_done = true
	var w := (load(WORLD) as PackedScene).instantiate() as WorldScene
	w.options = {"new_game": true, "skip_intro": true, "no_content": true, "time_of_day": 11.0}
	add_child(w)
	var t0 := Time.get_ticks_msec()
	while not w.playing and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
	return w


func _director(w: WorldScene) -> NpcDirector:
	for h in w.hooks:
		if h.get("director") is NpcDirector:
			return h.get("director")
	return null


func test_water_opening_in_the_world() -> void:
	if not WorldData.has_world_data():
		return
	var w := await _world(ElementDefs.Element.WATER)
	if not expect(w.playing, "world playing"):
		w.queue_free()
		return
	var dir := _director(w)
	expect(dir != null, "NPC hook installed the director")
	expect(Quests.scene == w and Quests.enabled, "quest system bound to the world")
	expect_eq(Quests.state(&"wt_born_of_the_tide"), &"active", "the Water opening quest auto-started")
	expect_eq(GameState.tracked_quest, &"wt_born_of_the_tide", "and is tracked")
	expect_eq(String(w.hud.quest.data.get("title", "")), "Born of the Tide", "HUD tracker shows it")
	var t0 := Time.get_ticks_msec()
	while NpcRegistry.live_npc(&"wt_anaaya") == null and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	var anaaya := NpcRegistry.live_npc(&"wt_anaaya") as NpcCharacter
	if not expect(anaaya != null, "Elder Anaaya spawned near the spawn"):
		w.queue_free()
		return
	expect(anaaya.global_position.distance_to(w.player.global_position) < 12.0, "she stands by the arrival spot")
	# talk through the real runner + dialogue box
	var box := w.dialogue
	var drive := func() -> void:
		for i in 900:
			await get_tree().process_frame
			if not is_instance_valid(dir) or not is_instance_valid(box) or (not dir.runner.busy and i > 3):
				return
			if box.choices.size() > 0:
				box.choose(0)
			else:
				box.advance()
	drive.call()
	await dir.runner.talk(anaaya)
	expect(dir.runner.transcript.size() >= 4, "a real conversation (%d lines)" % dir.runner.transcript.size())
	expect(Quests.is_objective_done(&"wt_born_of_the_tide", &"meet_anaaya"), "talking completed the objective")
	expect_eq(Quests.current_stage(&"wt_born_of_the_tide"), 1, "next stage")
	expect(w.player.get_state() != PlayerCharacter.State.CINEMATIC, "player released after the conversation")
	var d := Quests.get_quest_display(&"wt_born_of_the_tide")
	expect(d.get("target", Vector3.INF) is Vector3 and (d["target"] as Vector3).is_finite(), "compass target for the hall")
	expect_eq(String(w.hud.quest.data.get("objectives", [{}])[0].get("text", "")), "Find the training hall on the upper tier", "HUD shows the next objective")
	# save + load keeps the quest
	expect(SaveSystem.save_game(1), "saved")
	var saved := SaveSystem.read_slot(1)
	GameState.reset()
	expect(GameState.from_dict(saved), "loaded")
	expect_eq(Quests.current_stage(&"wt_born_of_the_tide"), 1, "stage kept through save / load")
	w.queue_free()
	await frames(3)
