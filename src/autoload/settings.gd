extends Node
## Persistent game settings (autoload "Settings").
##
## Values live in `_values` (section -> key -> value) and are saved to
## user://settings.cfg. Menus edit values with set_value(), then call apply()
## and save(). Use snapshot()/restore_snapshot() to implement Cancel.
##
## Systems that own rendering objects must configure them through
## configure_environment(), configure_sun() and the helper getters, and re-run
## that when Events.graphics_settings_changed fires.

const SAVE_PATH := "user://settings.cfg"
const AUDIO_BUSES := ["Music", "SFX", "Ambience", "UI", "Voice"]

const DISPLAY_MODES := ["windowed", "borderless", "fullscreen", "exclusive"]
const VSYNC_MODES := ["disabled", "enabled", "adaptive", "mailbox"]
const FPS_LIMITS := [0, 30, 60, 75, 120, 144, 165, 240]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
		Vector2i(2560, 1440), Vector2i(3440, 1440), Vector2i(3840, 2160)]
const AA_MODES := ["off", "fxaa", "smaa", "msaa2", "msaa4", "msaa8", "taa"]
const UPSCALERS := ["bilinear", "fsr1", "fsr2"]
const QUALITY_PRESETS := ["mobile", "low", "medium", "high", "ultra", "custom"]
## 0 = Off/Low ... 4 = Ultra for shadows; 0..3 for the other level settings.
const LEVEL_NAMES := ["Low", "Medium", "High", "Ultra"]
const SHADOW_NAMES := ["Off", "Low", "Medium", "High", "Ultra"]

const DEFAULTS := {
	"display": {
		"mode": "windowed",
		"resolution": Vector2i(1600, 900),
		"vsync": "enabled",
		"fps_limit": 0,
		"render_scale": 1.0,
		"upscaler": "bilinear",
		"fov": 72.0,
	},
	"graphics": {
		"preset": "high",
		"antialiasing": "fxaa",
		"shadows": 3,
		"ssao": true,
		"ssil": false,
		"glow": true,
		"volumetric_fog": true,
		"sdfgi": false,
		"view_distance": 2,
		"vegetation": 2,
		"effects": 2,
		"detail": 2,
	},
	"audio": {
		"master": 0.9,
		"music": 0.65,
		"sfx": 0.85,
		"ambience": 0.75,
		"ui": 0.7,
		"voice": 0.9,
	},
	"controls": {
		"mouse_sensitivity": 1.0,
		"controller_sensitivity": 1.0,
		"invert_y": false,
		"camera_distance": 1.0,
		"camera_shake": 1.0,
		"toggle_sprint": false,
		"bindings": {},
	},
	"gameplay": {
		"difficulty": "normal",
		"hints": true,
		"damage_numbers": true,
		"subtitles": true,
	},
	"touch": {
		## "auto" (on for phones/tablets/touchscreens), "on" or "off".
		"controls": "auto",
		"button_scale": 1.0,
		"opacity": 0.7,
		"left_handed": false,
		"camera_sensitivity": 1.0,
		## Pushing the virtual stick to the edge sprints.
		"auto_sprint": true,
		"haptics": true,
	},
}

## Applied once on first launch on phones/tablets (and mobile browsers).
const MOBILE_DEFAULTS := {
	"display": {"render_scale": 0.75, "fps_limit": 60, "upscaler": "fsr1"},
	"graphics": {"preset": "mobile", "antialiasing": "msaa2", "shadows": 1, "ssao": false, "ssil": false,
			"glow": true, "volumetric_fog": false, "sdfgi": false, "view_distance": 0, "vegetation": 0,
			"effects": 0, "detail": 0},
}

const PRESETS := {
	"mobile": {"antialiasing": "msaa2", "shadows": 1, "ssao": false, "ssil": false, "glow": true, "volumetric_fog": false,
			"sdfgi": false, "view_distance": 0, "vegetation": 0, "effects": 0, "detail": 0},
	"low": {"antialiasing": "off", "shadows": 1, "ssao": false, "ssil": false, "glow": false, "volumetric_fog": false,
			"sdfgi": false, "view_distance": 0, "vegetation": 0, "effects": 0, "detail": 0},
	"medium": {"antialiasing": "fxaa", "shadows": 2, "ssao": false, "ssil": false, "glow": true, "volumetric_fog": false,
			"sdfgi": false, "view_distance": 1, "vegetation": 1, "effects": 1, "detail": 1},
	"high": {"antialiasing": "fxaa", "shadows": 3, "ssao": true, "ssil": false, "glow": true, "volumetric_fog": true,
			"sdfgi": false, "view_distance": 2, "vegetation": 2, "effects": 2, "detail": 2},
	"ultra": {"antialiasing": "taa", "shadows": 4, "ssao": true, "ssil": true, "glow": true, "volumetric_fog": true,
			"sdfgi": false, "view_distance": 3, "vegetation": 3, "effects": 3, "detail": 3},
}

var _values: Dictionary = {}
var _loaded := false
## Where save() / load_settings() keep the settings (tests point it at a scratch file so a run
## never touches the player's - or another test run's - settings.cfg).
var save_path := SAVE_PATH


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_values = _deep_copy(DEFAULTS)
	ensure_audio_buses()
	InputDefaults.apply_defaults()
	load_settings()
	apply()


# --- Value access --------------------------------------------------------------

func get_value(section: String, key: String, fallback: Variant = null) -> Variant:
	if _values.has(section) and _values[section].has(key):
		return _values[section][key]
	if DEFAULTS.has(section) and DEFAULTS[section].has(key):
		return DEFAULTS[section][key]
	return fallback


## Sets a value without applying it. Changing a graphics option marks the preset "custom".
func set_value(section: String, key: String, value: Variant) -> void:
	if not _values.has(section):
		_values[section] = {}
	_values[section][key] = value
	if section == "graphics" and key != "preset":
		_values["graphics"]["preset"] = _detect_preset()


func get_section(section: String) -> Dictionary:
	return (_values.get(section, {}) as Dictionary).duplicate(true)


func snapshot() -> Dictionary:
	return _deep_copy(_values)


func restore_snapshot(snap: Dictionary) -> void:
	_values = _deep_copy(snap)


func restore_defaults(section: String = "") -> void:
	if section.is_empty():
		_values = _deep_copy(DEFAULTS)
	elif DEFAULTS.has(section):
		_values[section] = _deep_copy(DEFAULTS[section])


func apply_preset(preset: String) -> void:
	if not PRESETS.has(preset):
		return
	for key: String in PRESETS[preset]:
		_values["graphics"][key] = PRESETS[preset][key]
	_values["graphics"]["preset"] = preset


func _detect_preset() -> String:
	for p: String in PRESETS:
		var ok := true
		for key: String in PRESETS[p]:
			if _values["graphics"].get(key) != PRESETS[p][key]:
				ok = false
				break
		if ok:
			return p
	return "custom"


# --- Persistence --------------------------------------------------------------

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		if is_mobile_device():
			for section: String in MOBILE_DEFAULTS:
				for key: String in MOBILE_DEFAULTS[section]:
					_values[section][key] = MOBILE_DEFAULTS[section][key]
		_loaded = true
		return
	for section: String in DEFAULTS:
		for key: String in DEFAULTS[section]:
			if cfg.has_section_key(section, key):
				var v: Variant = cfg.get_value(section, key)
				if typeof(v) == typeof(DEFAULTS[section][key]) or (typeof(DEFAULTS[section][key]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
					_values[section][key] = v
	_loaded = true


func save() -> void:
	var cfg := ConfigFile.new()
	for section: String in _values:
		for key: String in _values[section]:
			cfg.set_value(section, key, _values[section][key])
	var err := cfg.save(save_path)
	if err != OK:
		push_warning("Settings: could not save (%s)" % error_string(err))


# --- Application ----------------------------------------------------------------

func apply() -> void:
	apply_display()
	apply_graphics()
	apply_audio()
	apply_controls()
	Events.settings_applied.emit()


func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Test runs pass `-- --test` to keep window/resolution untouched.
func is_test_run() -> bool:
	return OS.get_cmdline_user_args().has("--test") or is_headless()


func rendering_method() -> String:
	return RenderingServer.get_current_rendering_method()


func is_compatibility_renderer() -> bool:
	return rendering_method() == "gl_compatibility"


## Mobile (Vulkan) renderer used on Android/iOS.
func is_mobile_renderer() -> bool:
	return rendering_method() == "mobile"


## Phone/tablet, including mobile web browsers. `--mobile` on the command line
## simulates one for testing.
func is_mobile_device() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") \
			or OS.get_cmdline_user_args().has("--mobile")


## True when the on-screen touch controls should be shown.
func touch_controls_enabled() -> bool:
	match String(get_value("touch", "controls")):
		"on": return true
		"off": return false
	return is_mobile_device() or (DisplayServer.is_touchscreen_available() and not is_headless())


## Whether an option can take effect with the active renderer/platform.
func is_feature_supported(feature: String) -> bool:
	var compat := is_compatibility_renderer()
	var mobile_r := is_mobile_renderer()
	match feature:
		"ssao", "ssil", "sdfgi", "volumetric_fog", "taa", "fsr2", "smaa":
			return not compat and not mobile_r
		"fsr1":
			# Godot 4.7: FSR 1.0 3D scaling is Forward+ only ("only available when using the
			# Forward+ renderer"); the Mobile renderer falls back to bilinear with a warning.
			return not compat and not mobile_r
		"exclusive", "borderless", "vsync", "resolution", "display_mode":
			return not is_headless() and OS.get_name() not in ["Web", "Android", "iOS"]
		"rebinding":
			return not is_mobile_device()
	return true


func apply_display() -> void:
	Engine.max_fps = int(get_value("display", "fps_limit"))
	if is_test_run() or not is_feature_supported("display_mode"):
		return
	var mode: String = get_value("display", "mode")
	var res: Vector2i = get_value("display", "resolution")
	match mode:
		"fullscreen":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"exclusive":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			var screen := DisplayServer.window_get_current_screen()
			DisplayServer.window_set_position(DisplayServer.screen_get_position(screen))
			DisplayServer.window_set_size(DisplayServer.screen_get_size(screen))
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			var screen_size := DisplayServer.screen_get_size()
			var size := Vector2i(mini(res.x, screen_size.x), mini(res.y, screen_size.y))
			DisplayServer.window_set_size(size)
			var screen_pos := DisplayServer.screen_get_position()
			DisplayServer.window_set_position(screen_pos + (screen_size - size) / 2)
	var vs: String = get_value("display", "vsync")
	var vmode := DisplayServer.VSYNC_ENABLED
	match vs:
		"disabled": vmode = DisplayServer.VSYNC_DISABLED
		"adaptive": vmode = DisplayServer.VSYNC_ADAPTIVE
		"mailbox": vmode = DisplayServer.VSYNC_MAILBOX
	DisplayServer.window_set_vsync_mode(vmode)


func apply_graphics() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	configure_viewport(vp)
	var level: int = int(get_value("graphics", "shadows"))
	var dir_sizes := [512, 2048, 4096, 4096, 8192]
	var pos_sizes := [0, 1024, 2048, 4096, 8192]
	RenderingServer.directional_shadow_atlas_set_size(dir_sizes[clampi(level, 0, 4)], true)
	vp.positional_shadow_atlas_size = pos_sizes[clampi(level, 0, 4)]
	var soft := [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
			RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
			RenderingServer.SHADOW_QUALITY_SOFT_HIGH]
	RenderingServer.directional_soft_shadow_filter_set_quality(soft[clampi(level, 0, 4)])
	RenderingServer.positional_soft_shadow_filter_set_quality(soft[clampi(level, 0, 4)])
	Events.graphics_settings_changed.emit()


## Applies AA / render scale / LOD to any viewport (main or SubViewport previews).
func configure_viewport(vp: Viewport) -> void:
	var aa: String = get_value("graphics", "antialiasing")
	var compat := is_compatibility_renderer() or is_mobile_renderer()
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	# Godot 4.7's Compatibility renderer (Web) has no screen-space AA at all: FXAA / SMAA /
	# TAA fall back to MSAA 2x there instead of a warning and jagged edges.
	if is_compatibility_renderer() and aa in ["fxaa", "smaa", "taa"]:
		aa = "msaa2"
	match aa:
		"fxaa": vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		"smaa": vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if compat else Viewport.SCREEN_SPACE_AA_SMAA
		"msaa2": vp.msaa_3d = Viewport.MSAA_2X
		"msaa4": vp.msaa_3d = Viewport.MSAA_4X
		"msaa8": vp.msaa_3d = Viewport.MSAA_8X
		"taa":
			if compat:
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			else:
				vp.use_taa = true
	var scale: float = clampf(float(get_value("display", "render_scale")), 0.5, 2.0)
	vp.scaling_3d_scale = scale
	var up: String = get_value("display", "upscaler")
	if is_compatibility_renderer() or is_mobile_renderer() or scale >= 1.0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	elif up == "fsr2" and not is_mobile_renderer():
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	elif up == "fsr1" or up == "fsr2":
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var detail: int = int(get_value("graphics", "detail"))
	vp.mesh_lod_threshold = [4.0, 2.0, 1.0, 0.5][clampi(detail, 0, 3)]


## Applies post-processing toggles to a scene Environment. Call from every scene
## that owns a WorldEnvironment, and again on Events.graphics_settings_changed.
func configure_environment(env: Environment) -> void:
	if env == null:
		return
	var full := not is_compatibility_renderer() and not is_mobile_renderer()
	env.ssao_enabled = bool(get_value("graphics", "ssao")) and full
	env.ssil_enabled = bool(get_value("graphics", "ssil")) and full
	env.sdfgi_enabled = bool(get_value("graphics", "sdfgi")) and full
	env.glow_enabled = bool(get_value("graphics", "glow"))
	env.volumetric_fog_enabled = bool(get_value("graphics", "volumetric_fog")) and full


## Shadow settings for the scene's main DirectionalLight3D.
func configure_sun(light: DirectionalLight3D) -> void:
	if light == null:
		return
	var level: int = int(get_value("graphics", "shadows"))
	light.shadow_enabled = level > 0
	light.directional_shadow_max_distance = [0.0, 60.0, 120.0, 220.0, 400.0][clampi(level, 0, 4)]
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if level <= 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	if level == 1:
		# Low / mobile: one cascade. Every shadow caster is drawn once instead of per split
		# (mobile perf pass: halves the shadow pass on phones).
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL


## Terrain/scene view distance in meters.
func view_distance_m() -> float:
	return [1500.0, 2600.0, 4000.0, 6500.0][clampi(int(get_value("graphics", "view_distance")), 0, 3)]


## Vegetation/clutter density multiplier (instance count scale).
func vegetation_density() -> float:
	return [0.25, 0.55, 1.0, 1.5][clampi(int(get_value("graphics", "vegetation")), 0, 3)]


## Vegetation draw distance in meters.
func vegetation_distance_m() -> float:
	return [120.0, 220.0, 350.0, 550.0][clampi(int(get_value("graphics", "vegetation")), 0, 3)]


## Particle amount multiplier for VFX (also caps simultaneous effects).
func effects_scale() -> float:
	return [0.35, 0.6, 1.0, 1.4][clampi(int(get_value("graphics", "effects")), 0, 3)]


## Detail level 0..3 (mesh subdivisions, NPC counts, decal lifetimes).
func detail_level() -> int:
	return clampi(int(get_value("graphics", "detail")), 0, 3)


func fov() -> float:
	return float(get_value("display", "fov"))


func mouse_sensitivity() -> float:
	return float(get_value("controls", "mouse_sensitivity"))


func controller_sensitivity() -> float:
	return float(get_value("controls", "controller_sensitivity"))


func invert_y() -> bool:
	return bool(get_value("controls", "invert_y"))


func camera_shake_scale() -> float:
	return float(get_value("controls", "camera_shake"))


func difficulty_damage_scale() -> float:
	## Multiplier applied to damage the player receives.
	match String(get_value("gameplay", "difficulty")):
		"story": return 0.5
		"hard": return 1.5
	return 1.0


# --- Audio --------------------------------------------------------------------

static func ensure_audio_buses() -> void:
	for bus_name: String in AUDIO_BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func apply_audio() -> void:
	ensure_audio_buses()
	_set_bus("Master", float(get_value("audio", "master")))
	_set_bus("Music", float(get_value("audio", "music")))
	_set_bus("SFX", float(get_value("audio", "sfx")))
	_set_bus("Ambience", float(get_value("audio", "ambience")))
	_set_bus("UI", float(get_value("audio", "ui")))
	_set_bus("Voice", float(get_value("audio", "voice")))
	Events.audio_settings_changed.emit()


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	linear = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


# --- Controls ---------------------------------------------------------------------

func apply_controls() -> void:
	InputDefaults.apply_defaults()
	var binds: Dictionary = get_value("controls", "bindings")
	for action_name: String in binds:
		var action := StringName(action_name)
		if InputDefaults.ACTIONS.has(action) and binds[action_name] is Array:
			InputDefaults.set_action_events(action, binds[action_name])
	if touch_controls_enabled():
		_strip_mouse_buttons()
	Events.controls_changed.emit()
	Events.touch_controls_changed.emit(touch_controls_enabled())


## With touch controls active every screen tap is also emulated as a left mouse
## click; remove mouse-button bindings so taps on virtual buttons never fire
## attacks by accident (the touch overlay presses actions directly).
func _strip_mouse_buttons() -> void:
	for action: StringName in InputDefaults.ACTIONS:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventMouseButton:
				InputMap.action_erase_event(action, ev)


func touch_button_scale() -> float:
	return clampf(float(get_value("touch", "button_scale")), 0.6, 1.6)


func touch_opacity() -> float:
	return clampf(float(get_value("touch", "opacity")), 0.2, 1.0)


func touch_camera_sensitivity() -> float:
	return float(get_value("touch", "camera_sensitivity"))


## Current binding entries of an action (defaults merged with overrides).
func get_bindings(action: StringName) -> Array:
	var binds: Dictionary = get_value("controls", "bindings")
	if binds.has(String(action)):
		return (binds[String(action)] as Array).duplicate(true)
	return (InputDefaults.ACTIONS[action]["events"] as Array).duplicate(true) if InputDefaults.ACTIONS.has(action) else []


## Replaces the keyboard/mouse (device="kbm") or controller (device="pad") binding of an action.
func set_binding(action: StringName, device: String, entry: Dictionary) -> void:
	var list := get_bindings(action)
	var out: Array = []
	var replaced := false
	for e: Dictionary in list:
		var is_kbm := String(e.get("type")) in ["key", "mouse"]
		if (device == "kbm") == is_kbm and not replaced:
			out.append(entry)
			replaced = true
		else:
			out.append(e)
	if not replaced:
		out.append(entry)
	var binds: Dictionary = (get_value("controls", "bindings") as Dictionary).duplicate(true)
	binds[String(action)] = out
	set_value("controls", "bindings", binds)


func reset_bindings() -> void:
	set_value("controls", "bindings", {})


# --- Utils --------------------------------------------------------------------------

static func _deep_copy(d: Dictionary) -> Dictionary:
	return d.duplicate(true)
