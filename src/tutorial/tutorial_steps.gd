class_name TutorialSteps
extends RefCounted
## Step data of the training grounds (pure data; TutorialDirector evaluates the conditions).
##
## Step: {"id", "kind" (condition, see TutorialDirector), "title", "target": float (count /
##        seconds / degrees / metres), "unit": "" | "s" | "m" | "°",
##        "text": {"any": template, "kbm"/"pad"/"touch": overrides}, "actions": [glyphs shown],
##        "bot": &"off" | &"idle" | &"fire" | &"slow" (sparring partner), "only": element or -1,
##        "needs_companion": bool}
## Templates name actions in braces - "Hold {block} to defend" - and are filled with the live
## binding of the active device (rebinding-proof): "Hold Q ..." / "Hold LT ...".


static func build(e: int, light_steps: int, has_companion: bool, technique_name: String = "your technique") -> Array[Dictionary]:
	var elem := String(ElementDefs.get_data(e).get("element_name", "your element")).to_lower()
	var out: Array[Dictionary] = []
	var look := _s(&"look", "Look Around", 150.0, "°",
			{"kbm": "Move the mouse to look around the training grounds.",
			"pad": "Use the right stick to look around the training grounds.",
			"touch": "Drag on the right half of the screen to look around."}, [])
	# explicit glyphs: a mouse / the right stick (camera look has no rebindable key)
	look["glyphs"] = {"kbm": [{"type": "mouse", "button": 0}], "pad": [{"type": "joy_axis", "axis": JOY_AXIS_RIGHT_X, "value": 1.0}]}
	out.append(look)
	out.append(_s(&"move", "Find Your Footing", 12.0, "m",
			{"kbm": "Walk with {move_forward} {move_left} {move_back} {move_right} - the camera decides what forward means.",
			"pad": "Walk with the left stick: push gently to walk, fully to run.",
			"touch": "Touch the left half of the screen and drag to move."}, [&"move_forward", &"move_left", &"move_back", &"move_right"]))
	out.append(_s(&"sprint", "Sprint", 1.5, "s",
			{"any": "Hold {sprint} while moving to sprint.",
			"touch": "Push the stick to the edge of its ring to sprint."}, [&"sprint"]))
	out.append(_s(&"jump", "Jump", 2.0, "",
			{"any": "Press {jump} to jump. Jump twice.", "touch": "Tap the jump button. Jump twice."}, [&"jump"]))
	if e == ElementDefs.Element.AIR:
		out.append(_s(&"air_jump", "Air Jump", 1.0, "",
				{"any": "Press {jump} again in mid-air: the wind carries you higher.",
				"touch": "Tap jump again in mid-air: the wind carries you higher."}, [&"jump"], e))
		out.append(_s(&"glide", "Glide", 1.0, "s",
				{"any": "Hold {jump} while falling to glide on the wind.",
				"touch": "Hold the jump button while falling to glide on the wind."}, [&"jump"], e))
	out.append(_s(&"dodge", "Evade", 2.0, "",
			{"any": "Press {dodge} while moving to dodge. Dodge twice.",
			"touch": "Tap the dodge button while moving. Dodge twice."}, [&"dodge"]))
	out.append(_s(&"light", "Strike Combo", float(maxi(light_steps, 2)), "",
			{"any": "Press {attack_light} in rhythm to chain %d strikes into a training dummy." % light_steps,
			"touch": "Tap Strike in rhythm to chain %d strikes into a training dummy." % light_steps}, [&"attack_light"]))
	out.append(_s(&"heavy", "Heavy Strike", 1.0, "",
			{"any": "Tap {attack_heavy} for a quick, heavy %s strike." % elem,
			"touch": "Tap Heavy for a quick, heavy %s strike." % elem}, [&"attack_heavy"]))
	out.append(_s(&"charge", "Charged Strike", 1.0, "",
			{"any": "Hold {attack_heavy} to gather power and release it at its peak.",
			"touch": "Hold Heavy to gather power and release it at its peak."}, [&"attack_heavy"]))
	var lock := _s(&"lockon", "Lock On", 1.0, "",
			{"any": "Your sparring partner steps up. Press {lock_on} to lock on.",
			"touch": "Your sparring partner steps up. Tap the lock-on button."}, [&"lock_on"])
	lock["bot"] = &"idle"
	out.append(lock)
	var block := _s(&"block", "Defend", 1.0, "",
			{"any": "Hold {block} as the fireball comes to block it.",
			"touch": "Hold Defend as the fireball comes to block it."}, [&"block"])
	block["bot"] = &"fire"
	out.append(block)
	var parry := _s(&"parry", "Parry", 1.0, "",
			{"any": "Watch the glowing fist. Press {block} just before the fireball hits to parry it.",
			"touch": "Watch the glowing fist. Tap Defend just before the fireball hits to parry it."}, [&"block"])
	parry["bot"] = &"slow"
	out.append(parry)
	var tech := _s(&"technique", technique_name, 1.0, "",
			{"any": "Press {ability_1} to unleash %s." % technique_name,
			"touch": "Tap the first technique button to unleash %s." % technique_name}, [&"ability_1"])
	tech["bot"] = &"idle"
	out.append(tech)
	if has_companion:
		var call := _s(&"companion_call", "Call Your Companion", 1.0, "",
				{"any": "Press {companion_call} to call your companion.", "touch": "Tap the companion button."}, [&"companion_call"])
		call["needs_companion"] = true
		out.append(call)
		var mount := _s(&"mount", "Ride", 1.0, "",
				{"any": "Walk up to your companion and press {mount} to climb on.",
				"touch": "Walk up to your companion and tap the mount button."}, [&"mount"])
		mount["needs_companion"] = true
		out.append(mount)
	return out


static func _s(kind: StringName, title: String, target: float, unit: String, text: Dictionary, actions: Array, only: int = -1) -> Dictionary:
	return {"id": kind, "kind": kind, "title": title, "target": target, "unit": unit, "text": text, "actions": actions,
			"bot": &"off", "only": only, "needs_companion": false}


## Instruction for a device (&"kbm", &"pad", &"touch") with {action} placeholders filled from
## the live bindings.
static func text_for(step: Dictionary, device: StringName) -> String:
	var t: Dictionary = step.get("text", {})
	var s := String(t.get(String(device), t.get("any", t.get("kbm", ""))))
	var dev := &"kbm" if device == &"touch" else device
	var rx := RegEx.create_from_string("\\{([a-z0-9_]+)\\}")
	for m in rx.search_all(s):
		var label := UiInput.action_label(StringName(m.get_string(1)), dev)
		s = s.replace(m.get_string(0), label if label != "" else "-")
	return s
