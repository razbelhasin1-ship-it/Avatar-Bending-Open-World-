class_name RebindLogic
extends RefCounted
## Pure rebinding rules used by the controls tab (testable without UI):
## which actions are rebindable, how captured events become binding entries, conflict
## detection per device class, and binding with an optional swap. Writes go through
## Settings.set_binding()/set_value() and InputMap is refreshed with Settings.apply_controls().

const GROUP_ORDER := ["Movement", "Camera", "Bending", "World", "Menus"]


## Rebindable actions grouped in display order: [{"group": String, "actions": Array[StringName]}].
static func grouped_actions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g: String in GROUP_ORDER:
		var list: Array[StringName] = []
		for a: StringName in InputDefaults.ACTIONS:
			var d: Dictionary = InputDefaults.ACTIONS[a]
			if String(d.get("group", "")) == g and bool(d.get("rebindable", true)):
				list.append(a)
		if not list.is_empty():
			out.append({"group": g, "actions": list})
	return out


static func is_rebindable(action: StringName) -> bool:
	return InputDefaults.ACTIONS.has(action) and bool(InputDefaults.ACTIONS[action].get("rebindable", true))


static func device_of(entry: Dictionary) -> String:
	return "kbm" if UiInput.is_kbm_entry(entry) else "pad"


## Binding entry for a captured event on `device`, or {} if it does not qualify.
static func entry_from_event(ev: InputEvent, device: String) -> Dictionary:
	if device == "kbm":
		if ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo:
			var k := ev as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			if code == KEY_NONE or code == KEY_ESCAPE:
				return {}
			return {"type": "key", "code": int(code)}
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			var b := (ev as InputEventMouseButton).button_index
			if b in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
				return {}
			return {"type": "mouse", "button": int(b)}
	else:
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).pressed:
			var jb := (ev as InputEventJoypadButton).button_index
			if jb == JOY_BUTTON_START or jb == JOY_BUTTON_GUIDE:
				return {}
			return {"type": "joy_button", "button": int(jb)}
		if ev is InputEventJoypadMotion and absf((ev as InputEventJoypadMotion).axis_value) > 0.6:
			var jm := ev as InputEventJoypadMotion
			return {"type": "joy_axis", "axis": int(jm.axis), "value": signf(jm.axis_value)}
	return {}


static func same_input(a: Dictionary, b: Dictionary) -> bool:
	var t := String(a.get("type", ""))
	if t != String(b.get("type", "")):
		return false
	match t:
		"key": return int(a.get("code", -1)) == int(b.get("code", -2))
		"mouse", "joy_button": return int(a.get("button", -1)) == int(b.get("button", -2))
		"joy_axis": return int(a.get("axis", -1)) == int(b.get("axis", -2)) and signf(float(a.get("value", 1))) == signf(float(b.get("value", 1)))
	return false


## Current entry of `action` for `device` ("kbm"/"pad") from Settings, or {}.
static func current_entry(action: StringName, device: String) -> Dictionary:
	for e: Dictionary in Settings.get_bindings(action):
		if device_of(e) == device:
			return e
	return {}


## Other rebindable actions already using `entry` (same device class).
static func find_conflicts(action: StringName, entry: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for a: StringName in InputDefaults.ACTIONS:
		if a == action or not is_rebindable(a):
			continue
		for e: Dictionary in Settings.get_bindings(a):
			if same_input(e, entry):
				out.append(a)
				break
	return out


## Binds `entry` to `action`. With `swap`, each conflicting action receives the binding
## `action` had before (or loses the conflicting entry if it had none). Applies InputMap.
static func bind(action: StringName, entry: Dictionary, swap: bool = false) -> void:
	var device := device_of(entry)
	var previous := current_entry(action, device)
	if swap:
		for other: StringName in find_conflicts(action, entry):
			if previous.is_empty():
				_remove_entry(other, entry)
			else:
				_replace_entry(other, entry, previous)
	Settings.set_binding(action, device, entry)
	Settings.apply_controls()


static func _replace_entry(action: StringName, old_entry: Dictionary, new_entry: Dictionary) -> void:
	var list := Settings.get_bindings(action)
	for i in list.size():
		if same_input(list[i], old_entry):
			list[i] = new_entry
	_store(action, list)


static func _remove_entry(action: StringName, entry: Dictionary) -> void:
	var list := Settings.get_bindings(action)
	var keep: Array = []
	for e: Dictionary in list:
		if not same_input(e, entry):
			keep.append(e)
	_store(action, keep)


static func _store(action: StringName, list: Array) -> void:
	var binds: Dictionary = (Settings.get_value("controls", "bindings") as Dictionary).duplicate(true)
	binds[String(action)] = list
	Settings.set_value("controls", "bindings", binds)


static func reset_all() -> void:
	Settings.reset_bindings()
	Settings.apply_controls()


static func action_label(action: StringName) -> String:
	return String(InputDefaults.ACTIONS.get(action, {}).get("label", String(action)))
