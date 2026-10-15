extends RefCounted
## In-game UI over a small 3D stage with a mock player: HUD in combat (techniques on
## cooldown, insufficient chi, lock-on, toasts, quest tracker, interaction prompt,
## damage numbers), low-health vignette, region title card, dialogue with choices,
## loading overlay and the pause menu (navigated with ui actions). Env ELEMENT=fire|...


func run(p: Playtest) -> void:
	var element := ElementDefs.from_id(StringName(OS.get_environment("ELEMENT")))
	if not ElementDefs.is_valid(element):
		element = ElementDefs.Element.WATER
	GameState.new_game(element)
	GameState.level = 7
	var root := Node3D.new()
	root.name = "HudPlaytest"
	p.get_tree().root.add_child(root)
	p.get_tree().current_scene = root
	var stage := HudPreviewStage.new()
	root.add_child(stage)
	stage.build(element)
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as Hud
	root.add_child(hud)
	var mock := stage.mock
	hud.bind_player(mock)
	var quests := QuestProviderStub.new()
	hud.bind_quest_provider(quests)
	await p.wait(2.0)
	# combat state
	mock.health.apply_damage(46.0)
	mock.set_chi(34.0)
	mock.set_focus(100.0)
	mock.set_cooldown(0, 0.62, 5.4)
	mock.set_cooldown(2, 0.25, 1.6)
	mock.set_available(1, false)
	GameState.tracked_quest = &"spirit_oasis"
	Events.quest_started.emit(&"spirit_oasis")
	Events.notify.emit("Discovered: the Spirit Oasis", &"discovery")
	Events.notify.emit("New quest: Moon and Ocean", &"quest")
	Events.interaction_prompt.emit("Talk to Master Pakku", true)
	Events.target_locked.emit(stage.enemy)
	(stage.enemy.get_node("HealthComponent") as HealthComponent).apply_damage(52.0)
	await p.wait(1.0)
	hud.damage_numbers.spawn(stage.enemy.global_position + Vector3(-0.5, 1.7, 0), 24.0, false, element)
	await p.wait(0.3)
	hud.damage_numbers.spawn(stage.enemy.global_position + Vector3(0.5, 2.0, 0), 58.0, true, element)
	await p.wait(0.15)
	var clear := hud.center_clear_rect()
	var ok := true
	for c: Control in [hud.vitals, hud.abilities, hud.compass, hud.toasts, hud.quest, hud.companion_panel, hud.prompt_panel]:
		if c.visible and c.get_global_rect().intersects(clear):
			ok = false
			p.note("%s overlaps the centre: %s" % [c.name, c.get_global_rect()])
	p.check(ok, "HUD widgets keep the centre of the screen clear")
	p.check(hud.abilities.slot(0).info.get("cooldown_ratio", 0.0) > 0.5, "slot 1 shows its cooldown")
	await p.screenshot("hud_combat_%s" % ElementDefs.id_of(element))
	Events.ability_failed.emit(&"water_surge" if element == ElementDefs.Element.WATER else StringName(mock.slots[1]["id"]), &"no_chi")
	await p.wait(0.08)
	await p.screenshot("hud_ability_failed")
	# low health vignette
	mock.health.apply_damage(mock.health.health - 18.0)
	Events.player_damaged.emit(10.0, null)
	await p.wait(0.6)
	await p.screenshot("hud_low_health")
	mock.health.heal(200.0)
	Events.interaction_prompt.emit("", false)
	# region title card
	hud.title_card.show_title("The Northern Water Tribe", "Arrival", ElementDefs.Element.WATER)
	await p.wait_until(func() -> bool: return hud.title_card._seal.modulate.a >= 0.99 and hud.title_card._title.visible_ratio >= 1.0, 20.0)
	await p.wait(0.4)
	await p.screenshot("title_card")
	hud.title_card.skip()
	# dialogue with choices
	var dlg := (load("res://scenes/ui/dialogue_box.tscn") as PackedScene).instantiate() as DialogueBox
	hud.root.add_child(dlg)
	hud.set_combat_hud_visible(false)
	var answer := [-1]
	var flow := func() -> void:
		await dlg.say("Master Pakku", "Again. Your form is sloppy, and the water can feel it. [i]Breathe[/i] — then push.", {"element": ElementDefs.Element.WATER})
		answer[0] = await dlg.ask("Katara", "The spirits are restless tonight. Will you walk with me to the Oasis?", ["I'll come with you.", "Tell me more about the spirits.", "Not tonight."], {"element": ElementDefs.Element.WATER})
	flow.call()
	await p.wait(0.6)
	await p.screenshot("dialogue_line")
	await p.tap(&"ui_accept")
	await p.wait(0.2)
	await p.tap(&"ui_accept")
	# software rendering caps game time per frame: wait on state, not wall-clock
	await p.wait_until(func() -> bool: return dlg.choices.size() == 3, 20.0)
	await p.wait(0.5)
	p.check(dlg.choices.size() == 3, "dialogue shows three choices")
	await p.tap(&"ui_down")
	await p.wait(0.2)
	await p.screenshot("dialogue_choices")
	await p.tap(&"ui_accept")
	await p.wait(0.3)
	p.check(answer[0] == 1, "choice picked with the keyboard (%d)" % answer[0])
	dlg.close()
	hud.set_combat_hud_visible(true)
	# loading overlay
	var lo := LoadingOverlay.open(p.get_tree(), "Entering the Northern Water Tribe", element)
	lo.set_progress(0.62)
	await p.wait(1.6)
	await p.screenshot("loading_overlay")
	lo.close()
	await p.wait(0.4)
	# pause menu
	var pm := (load("res://scenes/ui/pause_menu.tscn") as PackedScene).instantiate() as PauseMenu
	root.add_child(pm)
	var routes: Array = []
	pm.route_override = func(path: String, params: Dictionary) -> void: routes.append(path)
	pm.quit_override = func() -> void: routes.append("quit")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await p.tap(&"pause")
	await p.wait(0.5)
	p.check(pm.is_open and p.get_tree().paused, "pause action opens the menu and pauses the tree")
	p.check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse visible while paused")
	await p.tap(&"ui_down")
	await p.wait(0.3)
	await p.screenshot("pause_menu")
	await p.tap(&"pause")
	await p.wait(0.4)
	p.check(not pm.is_open and not p.get_tree().paused, "pause action resumes")
	p.check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "mouse capture restored on resume")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


class QuestProviderStub:
	extends RefCounted

	func get_quest_display(quest_id: StringName) -> Dictionary:
		if quest_id != &"spirit_oasis":
			return {}
		return {"id": quest_id, "title": "Moon and Ocean", "target": Vector3(120, 0, -300), "objectives": [
			{"text": "Speak with Master Pakku", "done": true},
			{"text": "Gather spirit water at the Oasis", "count": 1, "target": 3},
			{"text": "Return before moonrise", "done": false},
		]}
