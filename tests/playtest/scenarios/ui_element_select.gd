extends RefCounted
## Element selection: each element focused in turn (backdrop, motif, live previews),
## navigated with ui_left/ui_right, then a card chosen and BEGIN confirmed with the
## real ink wipe (routing intercepted). Env TUTORIAL=1 opens it in tutorial mode.


func run(p: Playtest) -> void:
	var tutorial := OS.get_environment("TUTORIAL") == "1"
	var sel := await p.load_scene("res://scenes/ui/element_select.tscn", {"tutorial": tutorial}) as ElementSelect
	if not p.check(sel != null, "element select loads"):
		return
	var routes: Array = []
	sel.route_override = func(path: String, params: Dictionary) -> void: routes.append([path, params])
	await p.wait_until(func() -> bool: return sel.cards[0].has_focus(), 90.0)
	await p.wait(2.0)
	p.check(sel.cards.size() == 4, "four element cards")
	var names: Array = []
	for c in sel.cards:
		names.append(ElementDefs.display_name(c.element).to_upper())
	p.check(names == ["EARTHBENDER", "AIRBENDER", "FIREBENDER", "WATERBENDER"], "card order %s" % [names])
	var shots := ["earth", "air", "fire", "water"]
	for i in 4:
		if i > 0:
			await p.tap(&"ui_right")
		await p.wait(2.6)
		p.check(sel.current == sel.cards[i].element, "focus on %s" % shots[i])
		await p.screenshot("select_%s%s" % [shots[i], "_tutorial" if tutorial else ""])
	# choose fire and confirm with the keyboard/controller flow
	await p.tap(&"ui_left")
	await p.wait(0.6)
	await p.tap(&"ui_accept")
	await p.wait(0.4)
	p.check(sel.begin_button.has_focus(), "choosing a card focuses BEGIN")
	await p.tap(&"ui_accept")
	await p.wait(0.55)
	await p.screenshot("select_transition")
	await p.wait_until(func() -> bool: return not routes.is_empty(), 10.0)
	p.check(routes.size() == 1, "confirm routes once")
	if routes.size() == 1:
		var want := Router.TUTORIAL if tutorial else Router.WORLD
		p.check(routes[0][0] == want, "routes to %s" % want)
		p.check(int(routes[0][1].get("element", -1)) == ElementDefs.Element.FIRE, "element param is fire")
		p.check(GameState.element == ElementDefs.Element.FIRE, "GameState element is fire")
		p.check(GameState.is_tutorial == tutorial, "tutorial flag")
