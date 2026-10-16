class_name SettingsSchema
extends RefCounted
## Data describing every option of the settings menu, one entry per row, grouped by tab.
## Row: {"kind": "choice"|"slider"|"toggle"|"header"|"bindings", "section", "key",
## "label", "help", "apply": "display"|"graphics"|"audio"|"controls"|"gameplay",
## "feature": Settings.is_feature_supported() name (row disabled if unsupported),
## choice "items": [{"value", "label", "feature"?}], slider "min"/"max"/"step"/"format"}.

const TABS := ["display", "graphics", "audio", "controls", "gameplay"]
const TAB_TITLES := {"display": "DISPLAY", "graphics": "GRAPHICS", "audio": "AUDIO", "controls": "CONTROLS", "gameplay": "GAMEPLAY"}
## Settings sections restored by "Restore Defaults" on each tab.
const TAB_SECTIONS := {"display": ["display"], "graphics": ["graphics"], "audio": ["audio"], "controls": ["controls", "touch"], "gameplay": ["gameplay"]}

const LEVEL_ITEMS := [{"value": 0, "label": "Low"}, {"value": 1, "label": "Medium"}, {"value": 2, "label": "High"}, {"value": 3, "label": "Ultra"}]


static func rows(tab: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match tab:
		"display": out = _display()
		"graphics": out = _graphics()
		"audio": out = _audio()
		"controls": out = _controls()
		"gameplay": out = _gameplay()
	return out


static func _display() -> Array[Dictionary]:
	return [
		{"kind": "choice", "section": "display", "key": "mode", "label": "Display Mode", "apply": "display", "feature": "display_mode",
			"help": "Windowed, borderless window covering the screen, fullscreen, or exclusive fullscreen (lowest latency).",
			"items": [{"value": "windowed", "label": "Windowed"}, {"value": "borderless", "label": "Borderless", "feature": "borderless"},
				{"value": "fullscreen", "label": "Fullscreen"}, {"value": "exclusive", "label": "Exclusive", "feature": "exclusive"}]},
		{"kind": "choice", "section": "display", "key": "resolution", "label": "Resolution", "apply": "display", "feature": "resolution",
			"help": "Window size in windowed mode. Only resolutions that fit your screen are listed.", "items": resolution_items()},
		{"kind": "choice", "section": "display", "key": "vsync", "label": "Vertical Sync", "apply": "display", "feature": "vsync",
			"help": "Synchronise frames with the monitor to prevent tearing. Adaptive allows tearing only when the frame rate drops.",
			"items": [{"value": "disabled", "label": "Off"}, {"value": "enabled", "label": "On"}, {"value": "adaptive", "label": "Adaptive"}, {"value": "mailbox", "label": "Mailbox"}]},
		{"kind": "choice", "section": "display", "key": "fps_limit", "label": "Frame Rate Limit", "apply": "display",
			"help": "Caps the frame rate to save power and keep fans quiet.", "items": fps_items()},
		{"kind": "slider", "section": "display", "key": "render_scale", "label": "Render Scale", "apply": "graphics", "min": 0.5, "max": 2.0, "step": 0.05, "format": "percent_value",
			"help": "Resolution of the 3D image relative to the window. Below 100% renders faster and is upscaled; above 100% supersamples."},
		{"kind": "choice", "section": "display", "key": "upscaler", "label": "Upscaler", "apply": "graphics",
			"help": "How a reduced render scale is upscaled. FSR 1 sharpens; FSR 2 reconstructs detail over time (Forward+ only).",
			"items": [{"value": "bilinear", "label": "Bilinear"}, {"value": "fsr1", "label": "FSR 1.0", "feature": "fsr1"}, {"value": "fsr2", "label": "FSR 2.2", "feature": "fsr2"}]},
		{"kind": "slider", "section": "display", "key": "fov", "label": "Field of View", "apply": "display", "min": 55.0, "max": 100.0, "step": 1.0, "format": "degrees",
			"help": "Vertical camera field of view during gameplay. Wider shows more of the battlefield."},
	]


static func _graphics() -> Array[Dictionary]:
	var presets: Array = [{"value": "low", "label": "Low"}, {"value": "medium", "label": "Medium"}, {"value": "high", "label": "High"},
			{"value": "ultra", "label": "Ultra"}, {"value": "custom", "label": "Custom", "disabled": true}]
	if Settings.is_mobile_device():
		presets.push_front({"value": "mobile", "label": "Mobile"})
	return [
		{"kind": "choice", "section": "graphics", "key": "preset", "label": "Quality Preset", "apply": "preset",
			"help": "Sets every graphics option at once. Changing any single option switches to Custom.", "items": presets},
		{"kind": "choice", "section": "graphics", "key": "antialiasing", "label": "Anti-Aliasing", "apply": "graphics",
			"help": "Smooths jagged edges. FXAA is cheapest, MSAA is sharp on geometry, TAA is smoothest (Forward+ only).",
			"items": [{"value": "off", "label": "Off"}, {"value": "fxaa", "label": "FXAA"}, {"value": "smaa", "label": "SMAA", "feature": "smaa"},
				{"value": "msaa2", "label": "MSAA 2x"}, {"value": "msaa4", "label": "MSAA 4x"}, {"value": "msaa8", "label": "MSAA 8x"}, {"value": "taa", "label": "TAA", "feature": "taa"}]},
		{"kind": "choice", "section": "graphics", "key": "shadows", "label": "Shadows", "apply": "graphics",
			"help": "Shadow map resolution, softness and draw distance.",
			"items": [{"value": 0, "label": "Off"}, {"value": 1, "label": "Low"}, {"value": 2, "label": "Medium"}, {"value": 3, "label": "High"}, {"value": 4, "label": "Ultra"}]},
		{"kind": "toggle", "section": "graphics", "key": "ssao", "label": "Ambient Occlusion", "apply": "graphics", "feature": "ssao",
			"help": "Screen-space ambient occlusion darkens creases and contact points."},
		{"kind": "toggle", "section": "graphics", "key": "ssil", "label": "Indirect Lighting", "apply": "graphics", "feature": "ssil",
			"help": "Screen-space indirect lighting lets bright surfaces tint their surroundings."},
		{"kind": "toggle", "section": "graphics", "key": "glow", "label": "Glow", "apply": "graphics",
			"help": "Bloom around fire, lightning, the sun and other bright light."},
		{"kind": "toggle", "section": "graphics", "key": "volumetric_fog", "label": "Volumetric Fog", "apply": "graphics", "feature": "volumetric_fog",
			"help": "Light shafts and depth through mist, steam and smoke."},
		{"kind": "toggle", "section": "graphics", "key": "sdfgi", "label": "Global Illumination", "apply": "graphics", "feature": "sdfgi",
			"help": "Real-time global illumination (SDFGI). Beautiful bounce light; expensive."},
		{"kind": "choice", "section": "graphics", "key": "view_distance", "label": "View Distance", "apply": "graphics", "items": LEVEL_ITEMS,
			"help": "How far terrain, settlements and landmarks are drawn."},
		{"kind": "choice", "section": "graphics", "key": "vegetation", "label": "Vegetation", "apply": "graphics", "items": LEVEL_ITEMS,
			"help": "Density and draw distance of grass, trees and ground clutter."},
		{"kind": "choice", "section": "graphics", "key": "effects", "label": "Bending Effects", "apply": "graphics", "items": LEVEL_ITEMS,
			"help": "Particle counts of bending, impacts and weather."},
		{"kind": "choice", "section": "graphics", "key": "detail", "label": "Detail", "apply": "graphics", "items": LEVEL_ITEMS,
			"help": "Mesh detail and level-of-detail distances for characters, creatures and props."},
	]


static func _audio() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for spec: Array in [["master", "Master Volume", "Overall loudness."], ["music", "Music", "Score and menu themes."],
			["sfx", "Effects", "Bending, combat, footsteps and creatures."], ["ambience", "Ambience", "Wind, sea, cities and wildlife beds."],
			["ui", "Interface", "Menu and HUD sounds."], ["voice", "Voice", "Spoken lines and barks."]]:
		out.append({"kind": "slider", "section": "audio", "key": spec[0], "label": spec[1], "apply": "audio", "min": 0.0, "max": 1.0, "step": 0.05,
				"format": "percent", "help": spec[2] + " Changes are heard immediately."})
	return out


static func _controls() -> Array[Dictionary]:
	var all := _controls_general()
	# On phones / tablets the touch section is what matters: show it first.
	if Settings.touch_controls_enabled():
		var touch: Array[Dictionary] = []
		var rest: Array[Dictionary] = []
		var in_touch := false
		for r: Dictionary in all:
			if String(r.get("kind", "")) == "header":
				in_touch = String(r.get("label", "")) == "TOUCH CONTROLS"
			if in_touch:
				touch.append(r)
			else:
				rest.append(r)
		if not rest.is_empty() and String(rest[0].get("kind", "")) != "header":
			rest.push_front({"kind": "header", "label": "CAMERA & MOVEMENT"})
		touch.append_array(rest)
		return touch
	return all


static func _controls_general() -> Array[Dictionary]:
	return [
		{"kind": "slider", "section": "controls", "key": "mouse_sensitivity", "label": "Mouse Sensitivity", "apply": "controls", "min": 0.1, "max": 3.0, "step": 0.05, "format": "multiplier",
			"help": "Camera turn speed with the mouse."},
		{"kind": "slider", "section": "controls", "key": "controller_sensitivity", "label": "Controller Sensitivity", "apply": "controls", "min": 0.1, "max": 3.0, "step": 0.05, "format": "multiplier",
			"help": "Camera turn speed with the right stick."},
		{"kind": "toggle", "section": "controls", "key": "invert_y", "label": "Invert Camera Y", "apply": "controls",
			"help": "Push up to look down."},
		{"kind": "slider", "section": "controls", "key": "camera_distance", "label": "Camera Distance", "apply": "controls", "min": 0.6, "max": 1.6, "step": 0.05, "format": "percent_value",
			"help": "How far the camera follows behind your bender."},
		{"kind": "slider", "section": "controls", "key": "camera_shake", "label": "Camera Shake", "apply": "controls", "min": 0.0, "max": 1.5, "step": 0.05, "format": "percent_value",
			"help": "Strength of impact and earthquake camera shake. Lower it if shaking causes discomfort."},
		{"kind": "toggle", "section": "controls", "key": "toggle_sprint", "label": "Toggle Sprint", "apply": "controls",
			"help": "Press sprint once instead of holding it."},
		{"kind": "header", "label": "TOUCH CONTROLS"},
		{"kind": "choice", "section": "touch", "key": "controls", "label": "On-Screen Controls", "apply": "controls",
			"help": "Virtual stick and bending buttons for phones and tablets. Auto enables them on touchscreens.",
			"items": [{"value": "auto", "label": "Auto"}, {"value": "on", "label": "On"}, {"value": "off", "label": "Off"}]},
		{"kind": "slider", "section": "touch", "key": "button_scale", "label": "Button Size", "apply": "controls", "min": 0.6, "max": 1.6, "step": 0.05, "format": "percent_value",
			"help": "Size of the on-screen buttons."},
		{"kind": "slider", "section": "touch", "key": "opacity", "label": "Button Opacity", "apply": "controls", "min": 0.2, "max": 1.0, "step": 0.05, "format": "percent_value",
			"help": "How visible the on-screen controls are."},
		{"kind": "toggle", "section": "touch", "key": "left_handed", "label": "Left-Handed Layout", "apply": "controls",
			"help": "Mirror the on-screen controls."},
		{"kind": "slider", "section": "touch", "key": "camera_sensitivity", "label": "Touch Look Speed", "apply": "controls", "min": 0.1, "max": 3.0, "step": 0.05, "format": "multiplier",
			"help": "Camera speed when dragging on the screen."},
		{"kind": "toggle", "section": "touch", "key": "auto_sprint", "label": "Auto Sprint", "apply": "controls",
			"help": "Pushing the virtual stick to its edge sprints."},
		{"kind": "toggle", "section": "touch", "key": "haptics", "label": "Haptics", "apply": "controls",
			"help": "Vibration feedback on hits and button presses."},
		{"kind": "header", "label": "KEY BINDINGS"},
		{"kind": "bindings", "feature": "rebinding", "label": "Bindings",
			"help": "Select a binding and press the new key or button. Esc cancels keyboard capture; Menu cancels controller capture."},
	]


static func _gameplay() -> Array[Dictionary]:
	return [
		{"kind": "choice", "section": "gameplay", "key": "difficulty", "label": "Difficulty", "apply": "gameplay",
			"help": "Story: enemies hit for half damage. Hard: enemies hit for 150% damage.",
			"items": [{"value": "story", "label": "Story"}, {"value": "normal", "label": "Normal"}, {"value": "hard", "label": "Hard"}]},
		{"kind": "toggle", "section": "gameplay", "key": "hints", "label": "Hints", "apply": "gameplay",
			"help": "Contextual tips about bending and the world."},
		{"kind": "toggle", "section": "gameplay", "key": "damage_numbers", "label": "Damage Numbers", "apply": "gameplay",
			"help": "Show damage dealt above enemies."},
		{"kind": "toggle", "section": "gameplay", "key": "subtitles", "label": "Subtitles", "apply": "gameplay",
			"help": "Show spoken lines as text."},
	]


## Resolutions that fit the current screen (always includes the configured one).
static func resolution_items() -> Array:
	var screen := Vector2i.ZERO
	if not Settings.is_headless():
		screen = DisplayServer.screen_get_size()
	var current: Vector2i = Settings.get_value("display", "resolution")
	var out: Array = []
	for r: Vector2i in Settings.RESOLUTIONS:
		if screen.x <= 0 or (r.x <= screen.x and r.y <= screen.y) or r == current:
			out.append({"value": r, "label": "%d × %d" % [r.x, r.y]})
	if out.is_empty():
		out.append({"value": current, "label": "%d × %d" % [current.x, current.y]})
	return out


static func fps_items() -> Array:
	var out: Array = []
	for f: int in Settings.FPS_LIMITS:
		out.append({"value": f, "label": "Unlimited" if f == 0 else "%d FPS" % f})
	return out


## Formats a slider value for its readout.
static func format_value(fmt: String, v: float) -> String:
	match fmt:
		"percent_value": return "%d%%" % roundi(v * 100.0)
		"multiplier": return "%.2fx" % v
		"degrees": return "%d°" % roundi(v)
	return "%d%%" % roundi(v * 100.0)
