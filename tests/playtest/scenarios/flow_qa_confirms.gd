extends RefCounted
## flow_qa: the in-game confirmations answered with the keyboard / pad (ui_* actions) on a REAL
## rendered window (mouse pointer present, real fonts and layout): the world map's FAST TRAVEL
## (Enter on a place -> Enter on TRAVEL) and the settings' UNSAVED CHANGES (Back -> right ->
## DISCARD -> Enter). Quick: a fire journey without streamed content. docs/qa/flow_qa.md.

var p: Playtest
var w: WorldScene


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(ElementDefs.Element.FIRE)
	GameState.intro_done = true
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": true, "skip_intro": true, "no_content": true, "no_warmup": true}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.is_ready and w.playing, 240.0)
	if not p.check(ok, "world ready"):
		return
	w.player.camera_rig.require_capture = false
	await p.wait_game(0.5)
	await _settings()
	await _map()


func _ui(action: StringName) -> void:
	await p.tap(action, 0.05)
	await p.frames(2)


func _focus() -> Control:
	return p.get_tree().root.get_viewport().gui_get_focus_owner()


func _desc(c: Control) -> String:
	if c == null:
		return "none"
	return "%s '%s' %s" % [c.get_class(), (c as Button).text if c is Button else "", c.get_path()]


func _settings() -> void:
	await _ui(&"pause")
	await p.wait_until(func() -> bool: return w.pause_menu.is_open, 5.0)
	await _ui(&"ui_down")
	await _ui(&"ui_down")
	await _ui(&"ui_accept")
	await p.wait_until(func() -> bool: return w.pause_menu.settings_menu != null and w.pause_menu.settings_menu.is_open, 5.0)
	var sm := w.pause_menu.settings_menu
	sm.persist = false
	sm.show_tab("graphics")
	await p.wait(0.3)
	var before := Settings.snapshot()
	sm.set_option("graphics", "glow", not bool(Settings.get_value("graphics", "glow")), "graphics")
	await p.frames(2)
	await _ui(&"ui_cancel")
	await p.wait(0.4)
	p.check(sm.confirm != null and sm.confirm.is_open, "Back with a change asks UNSAVED CHANGES")
	p.note("focus after the question: %s" % _desc(_focus()))
	p.check(_focus() == sm.confirm.buttons.get(&"apply"), "APPLY focused")
	for step in 3:
		await _ui(&"ui_right")
		p.note("ui_right %d -> %s" % [step + 1, _desc(_focus())])
	p.check(_focus() == sm.confirm.buttons.get(&"apply"), "right x3 cycles APPLY -> DISCARD -> KEEP EDITING -> APPLY inside the dialog")
	await _ui(&"ui_down")
	p.check(_focus() == sm.confirm.buttons.get(&"apply"), "down stays in the dialog (%s)" % _desc(_focus()))
	await _ui(&"ui_right")
	p.check(_focus() == sm.confirm.buttons.get(&"discard"), "DISCARD focused")
	await p.screenshot("confirms_1_discard")
	await _ui(&"ui_accept")
	await p.wait(0.4)
	p.check(not sm.is_open and str(Settings.snapshot()) == str(before), "Enter on DISCARD closes the settings and restores")
	p.check(w.pause_menu.is_open, "back on the pause menu")
	await _ui(&"ui_cancel")
	await p.wait_until(func() -> bool: return not w.pause_menu.is_open, 3.0)


func _map() -> void:
	var book := p.get_tree().get_first_node_in_group(&"journey_book") as JourneyBook
	var home := MapModel.place_by_id(MapModel.home_city_id())
	MapModel.note_position(home["position"])
	w.player.teleport(Transform3D(Basis(), (home["position"] as Vector3) + Vector3(300, 0, 0)))
	await p.wait_game(0.5)
	var trips: Array = []
	MapModel.travel_override = func(xf: Transform3D, _o: Dictionary) -> bool:
		trips.append(xf)
		return true
	await _ui(&"open_map")
	await p.wait_until(func() -> bool: return book.is_open and book.page == &"map", 5.0)
	# pad / keys: the move actions put the map in reticle mode; centre the reticle on the city
	var c := (book.get_page(&"map") as WorldMapPage).canvas
	c.focus_on(home["position"], 3.0)
	await p.wait(0.6)
	p.hold(&"move_right", 0.25)
	await p.wait(0.15)
	p.release(&"move_right")
	await p.wait(0.3)
	c.focus_on(home["position"], 3.0)
	await p.wait(0.6)
	p.note("reticle mode %s, hover %s, travel block '%s'" % [c.cursor_mode, String(c.hover.get("id", "")), MapModel.travel_block_reason(home)])
	p.check(c.cursor_mode and c.hover.get("id", &"") == home["id"], "the reticle rests on the home city")
	await _ui(&"ui_accept")
	var asked := await p.wait_until(func() -> bool: return not book.root.find_children("*", "ConfirmDialog", true, false).is_empty(), 5.0)
	p.check(asked, "Enter on the selected city asks FAST TRAVEL")
	await p.wait(0.3)
	p.note("focus on the question: %s" % _desc(_focus()))
	await p.screenshot("confirms_2_fast_travel")
	await _ui(&"ui_accept")
	var went := await p.wait_until(func() -> bool: return not trips.is_empty(), 5.0)
	p.check(went and trips.size() == 1, "Enter on TRAVEL travels (%d trips, dialogs open %d)" % [trips.size(), book.root.find_children("*", "ConfirmDialog", true, false).size()])
	MapModel.travel_override = Callable()
	await p.wait(0.3)
	p.check(not book.is_open and not p.get_tree().paused, "book closed, game running")
