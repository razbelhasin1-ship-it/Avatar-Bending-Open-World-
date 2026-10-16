class_name UiInput
extends Node
## Tracks which input device the player is using (keyboard/mouse, controller or touch)
## so prompts and hint bars show the right glyphs, and maps bindings to readable labels.
## Self-registering helper node (created under the tree root on first use); never an
## autoload, so the UI module stays self-contained.
##
##   UiInput.ensure(get_tree()).device_changed.connect(_refresh)
##   UiInput.device            # &"kbm", &"pad" or &"touch"
##   UiInput.action_label(&"jump", &"pad")   # "A"

signal device_changed(device: StringName)

static var device: StringName = &"kbm"
static var _inst: UiInput = null


static func ensure(tree: SceneTree) -> UiInput:
	if is_instance_valid(_inst):
		return _inst
	install_pad_menu_buttons()
	# Back button / app-background handling for phones and browsers (src/platform).
	MobilePlatform.ensure(tree)
	_inst = UiInput.new()
	_inst.name = "UiInput"
	_inst.process_mode = Node.PROCESS_MODE_ALWAYS
	if Settings.touch_controls_enabled():
		device = &"touch"
	tree.root.add_child.call_deferred(_inst)
	return _inst


## Godot's built-in ui_accept / ui_cancel carry no controller buttons (the d-pad and left
## stick already drive ui_up/down/left/right), so menus could be browsed but not confirmed
## with a pad. Adds A = accept and B = back unless the project already maps a pad button.
## Runtime-only: ui_* actions are not part of the rebindable set and are never saved.
static func install_pad_menu_buttons() -> void:
	for pair: Array in [[&"ui_accept", JOY_BUTTON_A], [&"ui_cancel", JOY_BUTTON_B]]:
		var action: StringName = pair[0]
		if not InputMap.has_action(action):
			continue
		var has_pad := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton:
				has_pad = true
		if not has_pad:
			var jb := InputEventJoypadButton.new()
			jb.button_index = pair[1]
			jb.device = -1
			InputMap.action_add_event(action, jb)


func _input(event: InputEvent) -> void:
	note_event(event)


## Updates the active device from an input event (also called by tests).
func note_event(event: InputEvent) -> void:
	var d := device
	if event is InputEventJoypadButton:
		d = &"pad"
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		d = &"pad"
	elif event is InputEventKey or event is InputEventMouseButton:
		d = &"kbm"
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 3.0 \
			and (event as InputEventMouseMotion).device != InputEvent.DEVICE_ID_EMULATION:
		d = &"kbm"
	elif event is InputEventScreenTouch:
		d = &"touch"
	if d != device:
		device = d
		device_changed.emit(d)


# --- Labels -------------------------------------------------------------------------------

const PAD_BUTTONS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_START: "Menu", JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Home",
	JOY_BUTTON_DPAD_UP: "D-Up", JOY_BUTTON_DPAD_DOWN: "D-Down", JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right",
}


## Readable label of one binding entry (InputDefaults format).
static func entry_label(e: Dictionary) -> String:
	match String(e.get("type", "")):
		"key":
			var code := int(e.get("code", 0)) as Key
			var label := OS.get_keycode_string(code)
			match code:
				KEY_ESCAPE: return "Esc"
				KEY_SPACE: return "Space"
				KEY_CTRL: return "Ctrl"
				KEY_SHIFT: return "Shift"
				KEY_ENTER: return "Enter"
				KEY_BACKSPACE: return "Bksp"
			return label if not label.is_empty() else "?"
		"mouse":
			return InputDefaults.describe(e)
		"joy_button":
			return PAD_BUTTONS.get(int(e.get("button", -1)), "Btn %d" % int(e.get("button", 0)))
		"joy_axis":
			var axis := int(e.get("axis", 0))
			var positive := float(e.get("value", 1.0)) > 0.0
			match axis:
				JOY_AXIS_TRIGGER_LEFT: return "LT"
				JOY_AXIS_TRIGGER_RIGHT: return "RT"
				JOY_AXIS_LEFT_X: return "LS Right" if positive else "LS Left"
				JOY_AXIS_LEFT_Y: return "LS Down" if positive else "LS Up"
				JOY_AXIS_RIGHT_X: return "RS Right" if positive else "RS Left"
				JOY_AXIS_RIGHT_Y: return "RS Down" if positive else "RS Up"
			return "Axis %d" % axis
	return "—"


static func is_kbm_entry(e: Dictionary) -> bool:
	return String(e.get("type", "")) in ["key", "mouse"]


## First binding of `action` for a device (&"kbm" or &"pad"), from the live InputMap.
static func action_entry(action: StringName, dev: StringName) -> Dictionary:
	if not InputMap.has_action(action):
		return {}
	for ev in InputMap.action_get_events(action):
		var d := InputDefaults.event_to_dict(ev)
		if d.is_empty():
			continue
		if (dev == &"pad") != is_kbm_entry(d):
			return d
	return {}


## Short label for an action on a device ("E", "Space", "A", "RT"); "" if unbound.
static func action_label(action: StringName, dev: StringName = &"") -> String:
	var dv := device if dev == &"" else dev
	if dv == &"touch":
		dv = &"kbm"
	var e := action_entry(action, dv)
	return entry_label(e) if not e.is_empty() else ""
