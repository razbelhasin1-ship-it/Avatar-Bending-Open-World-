class_name InputDefaults
extends RefCounted
## Default input bindings. Actions are registered at runtime by Settings so
## they can be rebound and persisted; project.godot only keeps engine ui_* actions.
##
## Binding entry formats (also used for saved rebinds):
##   {"type": "key", "code": KEY_W}          (physical keycode)
##   {"type": "mouse", "button": MOUSE_BUTTON_LEFT}
##   {"type": "joy_button", "button": JOY_BUTTON_A}
##   {"type": "joy_axis", "axis": JOY_AXIS_LEFT_X, "value": -1.0}

const DEADZONE := 0.25

## action -> {"label": String, "group": String, "rebindable": bool, "events": Array}
const ACTIONS := {
	# Movement
	&"move_forward": {"label": "Move Forward", "group": "Movement", "events": [{"type": "key", "code": KEY_W}, {"type": "joy_axis", "axis": JOY_AXIS_LEFT_Y, "value": -1.0}]},
	&"move_back": {"label": "Move Back", "group": "Movement", "events": [{"type": "key", "code": KEY_S}, {"type": "joy_axis", "axis": JOY_AXIS_LEFT_Y, "value": 1.0}]},
	&"move_left": {"label": "Move Left", "group": "Movement", "events": [{"type": "key", "code": KEY_A}, {"type": "joy_axis", "axis": JOY_AXIS_LEFT_X, "value": -1.0}]},
	&"move_right": {"label": "Move Right", "group": "Movement", "events": [{"type": "key", "code": KEY_D}, {"type": "joy_axis", "axis": JOY_AXIS_LEFT_X, "value": 1.0}]},
	&"jump": {"label": "Jump / Ascend", "group": "Movement", "events": [{"type": "key", "code": KEY_SPACE}, {"type": "joy_button", "button": JOY_BUTTON_A}]},
	&"sprint": {"label": "Sprint", "group": "Movement", "events": [{"type": "key", "code": KEY_SHIFT}, {"type": "joy_button", "button": JOY_BUTTON_LEFT_STICK}]},
	&"dodge": {"label": "Dodge", "group": "Movement", "events": [{"type": "key", "code": KEY_C}, {"type": "joy_button", "button": JOY_BUTTON_B}]},
	&"descend": {"label": "Descend (flying)", "group": "Movement", "events": [{"type": "key", "code": KEY_CTRL}, {"type": "joy_button", "button": JOY_BUTTON_B}]},
	# Camera (mouse look is handled directly; these are for controllers / keys)
	&"look_left": {"label": "Look Left", "group": "Camera", "rebindable": false, "events": [{"type": "joy_axis", "axis": JOY_AXIS_RIGHT_X, "value": -1.0}]},
	&"look_right": {"label": "Look Right", "group": "Camera", "rebindable": false, "events": [{"type": "joy_axis", "axis": JOY_AXIS_RIGHT_X, "value": 1.0}]},
	&"look_up": {"label": "Look Up", "group": "Camera", "rebindable": false, "events": [{"type": "joy_axis", "axis": JOY_AXIS_RIGHT_Y, "value": -1.0}]},
	&"look_down": {"label": "Look Down", "group": "Camera", "rebindable": false, "events": [{"type": "joy_axis", "axis": JOY_AXIS_RIGHT_Y, "value": 1.0}]},
	&"lock_on": {"label": "Lock On", "group": "Camera", "events": [{"type": "key", "code": KEY_TAB}, {"type": "mouse", "button": MOUSE_BUTTON_MIDDLE}, {"type": "joy_button", "button": JOY_BUTTON_RIGHT_STICK}]},
	# Bending
	&"attack_light": {"label": "Light Strike", "group": "Bending", "events": [{"type": "mouse", "button": MOUSE_BUTTON_LEFT}, {"type": "joy_button", "button": JOY_BUTTON_X}]},
	&"attack_heavy": {"label": "Heavy Strike (hold to charge)", "group": "Bending", "events": [{"type": "mouse", "button": MOUSE_BUTTON_RIGHT}, {"type": "joy_axis", "axis": JOY_AXIS_TRIGGER_RIGHT, "value": 1.0}]},
	&"block": {"label": "Defend / Block", "group": "Bending", "events": [{"type": "key", "code": KEY_Q}, {"type": "joy_axis", "axis": JOY_AXIS_TRIGGER_LEFT, "value": 1.0}]},
	&"ability_1": {"label": "Technique 1", "group": "Bending", "events": [{"type": "key", "code": KEY_1}, {"type": "joy_button", "button": JOY_BUTTON_DPAD_UP}]},
	&"ability_2": {"label": "Technique 2", "group": "Bending", "events": [{"type": "key", "code": KEY_2}, {"type": "joy_button", "button": JOY_BUTTON_DPAD_RIGHT}]},
	&"ability_3": {"label": "Technique 3", "group": "Bending", "events": [{"type": "key", "code": KEY_3}, {"type": "joy_button", "button": JOY_BUTTON_DPAD_DOWN}]},
	&"ability_4": {"label": "Technique 4", "group": "Bending", "events": [{"type": "key", "code": KEY_4}, {"type": "joy_button", "button": JOY_BUTTON_DPAD_LEFT}]},
	&"ability_special": {"label": "Signature Technique", "group": "Bending", "events": [{"type": "key", "code": KEY_R}, {"type": "joy_button", "button": JOY_BUTTON_RIGHT_SHOULDER}]},
	# World
	&"interact": {"label": "Interact", "group": "World", "events": [{"type": "key", "code": KEY_E}, {"type": "joy_button", "button": JOY_BUTTON_Y}]},
	&"companion_call": {"label": "Call Companion", "group": "World", "events": [{"type": "key", "code": KEY_G}, {"type": "joy_button", "button": JOY_BUTTON_LEFT_SHOULDER}]},
	&"mount": {"label": "Mount / Dismount", "group": "World", "events": [{"type": "key", "code": KEY_F}]},
	# Menus
	&"pause": {"label": "Pause", "group": "Menus", "rebindable": false, "events": [{"type": "key", "code": KEY_ESCAPE}, {"type": "joy_button", "button": JOY_BUTTON_START}]},
	&"open_map": {"label": "Map", "group": "Menus", "events": [{"type": "key", "code": KEY_M}, {"type": "joy_button", "button": JOY_BUTTON_BACK}]},
	&"open_skills": {"label": "Bending Skills", "group": "Menus", "events": [{"type": "key", "code": KEY_K}]},
	&"open_journal": {"label": "Quest Journal", "group": "Menus", "events": [{"type": "key", "code": KEY_J}]},
}


## Re-registers every action with its default events.
static func apply_defaults() -> void:
	for action: StringName in ACTIONS:
		set_action_events(action, ACTIONS[action]["events"])


static func set_action_events(action: StringName, entries: Array) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action, DEADZONE)
	for entry: Dictionary in entries:
		var ev := event_from_dict(entry)
		if ev != null:
			InputMap.action_add_event(action, ev)


static func event_from_dict(d: Dictionary) -> InputEvent:
	match String(d.get("type", "")):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.get("code", 0)) as Key
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(d.get("button", 1)) as MouseButton
			return m
		"joy_button":
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(d.get("button", 0)) as JoyButton
			return jb
		"joy_axis":
			var ja := InputEventJoypadMotion.new()
			ja.axis = int(d.get("axis", 0)) as JoyAxis
			ja.axis_value = float(d.get("value", 1.0))
			return ja
	return null


static func event_to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return {"type": "key", "code": int(code)}
	if ev is InputEventMouseButton:
		return {"type": "mouse", "button": int((ev as InputEventMouseButton).button_index)}
	if ev is InputEventJoypadButton:
		return {"type": "joy_button", "button": int((ev as InputEventJoypadButton).button_index)}
	if ev is InputEventJoypadMotion:
		var ja := ev as InputEventJoypadMotion
		return {"type": "joy_axis", "axis": int(ja.axis), "value": signf(ja.axis_value)}
	return {}


## Human-readable name for a binding entry (for menus and HUD prompts).
static func describe(d: Dictionary) -> String:
	match String(d.get("type", "")):
		"key":
			return OS.get_keycode_string(int(d.get("code", 0)) as Key)
		"mouse":
			match int(d.get("button", 0)):
				MOUSE_BUTTON_LEFT: return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				MOUSE_BUTTON_MIDDLE: return "MMB"
				MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
				MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
			return "Mouse %d" % int(d.get("button", 0))
		"joy_button":
			return "Pad %d" % int(d.get("button", 0))
		"joy_axis":
			return "Axis %d%s" % [int(d.get("axis", 0)), "+" if float(d.get("value", 1.0)) > 0.0 else "-"]
	return "?"


## First keyboard/mouse binding of an action, for on-screen prompts like "[E] Talk".
static func prompt_for(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey or ev is InputEventMouseButton:
			return describe(event_to_dict(ev))
	return "?"
