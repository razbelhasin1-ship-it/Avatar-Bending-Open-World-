class_name LightBudget
extends Node
## Budget for the point lights of lanterns, braziers and windows. Every kit light is an
## OmniLight3D created by `LightBudget.make_light()`; a single manager node (added to the scene
## root on first use) keeps only the nearest `max_lights()` of them enabled, fades their energy
## in with the darkness (world_sun_color) and with distance, and never casts shadows. The
## emissive geometry (kit_glow.gdshader) already reads at any distance, so lights are only the
## warm pools of light around the camera.
##
## | Settings detail_level | 0 (mobile/low) | 1 | 2 | 3 |
## | lights                | 4              | 8 | 14 | 22 |

const UPDATE_INTERVAL := 0.25
const MAX_DISTANCE := 70.0

static var _instance: LightBudget = null
static var _lights: Array = []           # weakrefs to OmniLight3D
## Optional filter `func(world_pos: Vector3) -> bool`: true keeps that light off (WorldFires:
## the light of a brazier / lantern / campfire that has been put out).
static var suppress: Callable = Callable()

var _timer := 0.0


## Number of simultaneously enabled kit lights for the current Settings.
static func max_lights() -> int:
	return [4, 8, 14, 22][Settings.detail_level()]


## Creates a budgeted light from a record {"position", "color", "range", "energy", "priority",
## "interior"}. Interior lights (caves, tunnels) shine by day too; the others fade in with dusk.
static func make_light(rec: Dictionary) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = "KitLight"
	l.position = rec.get("position", Vector3.ZERO)
	# glow colours are saturated for emissive paper; the light itself is a softer warm white
	l.light_color = (rec.get("color", Color(1, 0.8, 0.5)) as Color).lerp(Color(1.0, 0.93, 0.82), 0.45)
	l.omni_range = float(rec.get("range", 9.0))
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.light_specular = 0.2
	# no froxel-lit volumetric fog blocks around lanterns (and cheaper)
	l.light_volumetric_fog_energy = 0.0
	l.set_meta(&"base_energy", float(rec.get("energy", 1.6)))
	l.set_meta(&"priority", int(rec.get("priority", 0)))
	l.set_meta(&"interior", bool(rec.get("interior", false)))
	l.light_energy = 0.0
	l.visible = false
	register(l)
	return l


static func register(light: OmniLight3D) -> void:
	_lights.append(weakref(light))
	_ensure_manager()


static func _ensure_manager() -> void:
	if _instance and is_instance_valid(_instance):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_instance = LightBudget.new()
	_instance.name = "LightBudget"
	tree.root.add_child.call_deferred(_instance)


## Re-picks the enabled lights at once (a fire was put out / lit).
static func refresh() -> void:
	if _instance and is_instance_valid(_instance) and _instance.is_inside_tree():
		_instance.update_now()


## Live registered light count (stats).
static func light_count() -> int:
	var n := 0
	for w: WeakRef in _lights:
		if w.get_ref() != null:
			n += 1
	return n


## Enabled (visible) light count (stats).
static func active_count() -> int:
	var n := 0
	for w: WeakRef in _lights:
		var l: OmniLight3D = w.get_ref()
		if l and l.visible:
			n += 1
	return n


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		_apply_fade()
		return
	_timer = UPDATE_INTERVAL
	update_now()


## Night factor 0 (bright day) .. 1 (night) from the world sun colour global.
static func darkness() -> float:
	var sun: Variant = WorldShaderGlobals.get_value(&"world_sun_color")
	if not sun is Color:
		return 0.0
	var c: Color = sun
	var lum := c.r * 0.3 + c.g * 0.5 + c.b * 0.2
	return 1.0 - smoothstep(0.08, 0.55, lum)


## Re-picks the enabled lights now (also called by tests).
func update_now() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var alive: Array = []
	var cand: Array = []
	var dark := darkness()
	for w: WeakRef in _lights:
		var l: OmniLight3D = w.get_ref()
		if l == null:
			continue
		alive.append(w)
		if not l.is_inside_tree():
			continue
		var d := cam.global_position.distance_to(l.global_position) if cam else 0.0
		var dk := 1.0 if l.get_meta(&"interior", false) else dark
		if suppress.is_valid() and d < MAX_DISTANCE and bool(suppress.call(l.global_position)):
			l.visible = false
			continue
		if d < MAX_DISTANCE and dk > 0.02:
			cand.append([d - float(l.get_meta(&"priority", 0)) * 10.0, l, d, dk])
		else:
			l.visible = false
	_lights = alive
	cand.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var n := max_lights()
	for i in cand.size():
		var l: OmniLight3D = cand[i][1]
		var on := i < n
		l.visible = on
		if on:
			var fade := 1.0 - smoothstep(MAX_DISTANCE * 0.6, MAX_DISTANCE, float(cand[i][2]))
			l.set_meta(&"target", float(l.get_meta(&"base_energy", 1.6)) * float(cand[i][3]) * fade)
	_apply_fade()


func _apply_fade() -> void:
	var dt := get_process_delta_time()
	for w: WeakRef in _lights:
		var l: OmniLight3D = w.get_ref()
		if l and l.visible:
			l.light_energy = move_toward(l.light_energy, float(l.get_meta(&"target", 0.0)), dt * 4.0)
