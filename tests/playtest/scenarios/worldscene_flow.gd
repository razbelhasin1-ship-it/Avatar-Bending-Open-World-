extends RefCounted
## Full flow through the real Router and menus, per element:
## boot -> main menu -> ENTER THE WORLD -> element select (keyboard/controller navigation)
## -> arrival cinematic (screenshots) -> first gameplay frame in the home region -> move and
## attack -> pause -> SAVE GAME -> RETURN TO MAIN MENU (no duplicated singletons / nodes, no
## held input) -> ENTER THE WORLD -> CONTINUE -> same place, element, abilities and hour.
## ELEMENT=air|earth|fire|water or a comma list (default: all four). Existing saves are backed up and restored.

const BACKUP := "user://saves_playtest_backup"

var p: Playtest
var frame_ms: Array = []


func run(pt: Playtest) -> void:
	p = pt
	_backup_saves()
	var only := OS.get_environment("ELEMENT")
	var elements: Array[int] = []
	if only != "":
		for id in only.split(","):
			elements.append(ElementDefs.from_id(StringName(id.strip_edges())))
	else:
		elements.assign(ElementDefs.ALL)
	await p.goto_scene(Router.MAIN_MENU)
	for e in elements:
		await _flow(e)
	p.note("gameplay frame time per element (ms): %s" % str(frame_ms))
	_restore_saves()


# --- saves --------------------------------------------------------------------------------------------

func _backup_saves() -> void:
	DirAccess.make_dir_recursive_absolute(BACKUP)
	for i in SaveSystem.MAX_SLOTS:
		if SaveSystem.has_save(i):
			DirAccess.copy_absolute(SaveSystem.slot_path(i), BACKUP.path_join("slot_%d.json" % i))
			SaveSystem.delete_save(i)


func _restore_saves() -> void:
	for i in SaveSystem.MAX_SLOTS:
		SaveSystem.delete_save(i)
		var b := BACKUP.path_join("slot_%d.json" % i)
		if FileAccess.file_exists(b):
			DirAccess.copy_absolute(b, SaveSystem.slot_path(i))
			DirAccess.remove_absolute(b)


# --- helpers ------------------------------------------------------------------------------------------

func _ui(action: StringName) -> void:
	await p.tap(action, 0.05)
	await p.frames(2)


func _focus_owner() -> Control:
	return p.get_tree().root.get_viewport().gui_get_focus_owner()


func _world() -> WorldScene:
	return p.get_tree().get_first_node_in_group(&"world_scene") as WorldScene


func _root_names() -> Dictionary:
	var counts := {}
	for c in p.get_tree().root.get_children():
		var key := String(c.name).rstrip("0123456789@")
		counts[key] = int(counts.get(key, 0)) + 1
	return counts


func _measure_frames(n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		await p.get_tree().process_frame
	return float(Time.get_ticks_usec() - t0) / 1000.0 / n


# --- the flow -----------------------------------------------------------------------------------------

func _flow(e: int) -> void:
	var el := String(ElementDefs.id_of(e))
	p.note("=== %s ===" % el)
	for i in SaveSystem.MAX_SLOTS:
		SaveSystem.delete_save(i)
	var menu := p.scene() as MainMenu
	p.check(menu != null, "%s main menu up" % el)
	await p.wait_until(func() -> bool: return _focus_owner() == menu.options[0], 30.0)
	await _ui(&"ui_accept")                       # 01 ENTER THE WORLD (no save -> element select)
	await p.wait_until(func() -> bool: return p.scene() is ElementSelect and not Router.is_transitioning, 60.0)
	var sel := p.scene() as ElementSelect
	p.check(sel != null, "%s element select reached" % el)
	await p.wait_until(func() -> bool: return sel.cards[0].has_focus(), 60.0)
	var guard := 0
	while sel.current != e and guard < 6:
		guard += 1
		await _ui(&"ui_right")
		await p.wait(0.2)
	p.check(sel.current == e, "%s card focused" % el)
	await _ui(&"ui_accept")                       # choose -> BEGIN
	await p.wait(0.3)
	await _ui(&"ui_accept")                       # BEGIN -> ink wipe -> Router.WORLD
	var t0 := Time.get_ticks_msec()
	await p.wait_until(func() -> bool: return _world() != null, 60.0)
	var w := _world()
	p.check(w != null and w.new_game, "%s new journey world" % el)
	if w == null:
		return
	await p.wait_until(func() -> bool: return w.is_ready and not Router.is_transitioning, 240.0)
	p.check(w.is_ready, "%s loaded behind the fade in %.1f s %s" % [el, (Time.get_ticks_msec() - t0) / 1000.0, str(w.load_report)])
	p.check(w.load_report.get("collision_ready", false) and not w.load_report.get("safety_floor", true), "%s spawned on real ground" % el)
	p.check(w.arrival != null, "%s arrival cinematic" % el)
	var arr := w.arrival
	if arr:
		await p.wait_until(func() -> bool: return not is_instance_valid(arr) or arr.time > arr.duration * 0.3, 60.0)
		await p.screenshot("%s_1_arrival" % el)
	await p.wait_until(func() -> bool: return w.playing, 60.0)
	p.check(w.playing, "%s control returned" % el)
	await p.wait_game(0.4)
	var pl := w.player
	var home := StringName(ElementDefs.get_data(e)["home_region"])
	p.check(w.region_director.current_region == home and GameState.region == home, "%s home region %s (%s)" % [el, home, w.region_director.current_region])
	p.check(pl.element == e and GameState.element == e, "%s player element" % el)
	await p.screenshot("%s_2_gameplay" % el)
	frame_ms.append(snappedf(await _measure_frames(30), 0.1))
	# move + attack
	Input.action_press(&"move_forward")
	await p.wait_game(1.0)
	Input.action_release(&"move_forward")
	for i in 2:
		Input.action_press(&"attack_light")
		await p.wait_game(0.06)
		Input.action_release(&"attack_light")
		await p.wait_game(0.3)
	await p.screenshot("%s_3_attack" % el)
	await p.wait_game(0.8)
	# pause -> save -> main menu
	await _ui(&"pause")
	await p.wait_until(func() -> bool: return w.pause_menu.is_open, 5.0)
	p.check(w.pause_menu.is_open and p.get_tree().paused, "%s pause menu open, tree paused" % el)
	await p.wait(0.3)
	await p.screenshot("%s_4_pause" % el)
	await _ui(&"ui_down")
	p.check(_focus_owner() == w.pause_menu.options[1], "%s SAVE GAME focused" % el)
	await _ui(&"ui_accept")
	await p.wait(0.2)
	p.check(SaveSystem.has_save(SaveSystem.AUTOSAVE_SLOT), "%s journey saved" % el)
	var saved_pos := GameState.player_position
	var saved_hour := GameState.time_of_day
	var saved_abilities := GameState.equipped_abilities.duplicate()
	p.check(saved_pos.distance_to(pl.global_position) < 0.5, "%s saved where the player stands" % el)
	await _ui(&"ui_down")
	await _ui(&"ui_down")
	p.check(_focus_owner() == w.pause_menu.options[3], "%s RETURN TO MAIN MENU focused" % el)
	await _ui(&"ui_accept")
	await p.wait_until(func() -> bool: return p.scene() is MainMenu and not Router.is_transitioning, 60.0)
	await p.frames(5)
	p.check(_world() == null and p.get_tree().get_nodes_in_group(&"player").is_empty(), "%s world and player gone" % el)
	var names := _root_names()
	var dup := []
	for k: String in names:
		if int(names[k]) > 1:
			dup.append(k)
	p.check(dup.is_empty(), "%s no duplicated root nodes %s" % [el, str(names)])
	p.check(not names.has("LoadingOverlay") and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not p.get_tree().paused, "%s clean menu state" % el)
	var held := []
	for a in InputMap.get_actions():
		if Input.is_action_pressed(a):
			held.append(a)
	p.check(held.is_empty(), "%s no held input %s" % [el, str(held)])
	# continue
	menu = p.scene() as MainMenu
	await p.wait_until(func() -> bool: return _focus_owner() == menu.options[0], 30.0)
	await _ui(&"ui_accept")                       # ENTER THE WORLD -> save chooser
	await p.wait_until(func() -> bool: return menu.chooser.visible and _focus_owner() == menu.chooser.continue_button, 10.0)
	await p.screenshot("%s_5_chooser" % el)
	await _ui(&"ui_accept")                       # CONTINUE
	await p.wait_until(func() -> bool: return _world() != null and _world().is_ready and not Router.is_transitioning, 240.0)
	w = _world()
	p.check(w != null and not w.new_game and w.arrival == null, "%s continued (no cinematic)" % el)
	if w == null:
		return
	await p.wait_until(func() -> bool: return w.playing, 30.0)
	await p.wait_game(0.4)
	pl = w.player
	var d := pl.global_position.distance_to(saved_pos)
	p.check(d < 1.0, "%s same place after continue (%.2f m)" % [el, d])
	p.check(pl.element == e and GameState.equipped_abilities == saved_abilities, "%s same element + abilities" % el)
	p.check(absf(w.renderer.get_time_of_day() - saved_hour) < 0.2, "%s same hour (%.2f vs %.2f)" % [el, w.renderer.get_time_of_day(), saved_hour])
	await p.screenshot("%s_6_continued" % el)
	# back to the menu for the next element
	await _ui(&"pause")
	await p.wait_until(func() -> bool: return w.pause_menu.is_open, 5.0)
	w.pause_menu.return_to_menu()
	await p.wait_until(func() -> bool: return p.scene() is MainMenu and not Router.is_transitioning, 60.0)
	await p.frames(3)
