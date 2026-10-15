class_name WorldRenderer
extends Node3D
## Visual and physical ground of the open world: clipmap terrain, collision streaming,
## ocean/lake/canal water, sky + day/night, regional atmosphere, weather and snow trails.
##
##   var world := WorldRenderer.new()
##   add_child(world)
##   world.setup(player, camera)          # focus drives collision/snow/regions, camera the LOD
##   await world.wait_until_ready()       # optional: collision under the focus exists
##   world.set_time_of_day(17.5); world.set_weather(&"snow", 8.0)
##
## The node owns its WorldEnvironment and sun/moon lights: scenes using it must not add their
## own. Full reference: docs/modules/worldrender.md.

## Emitted once terrain is built and collision under the focus is ready.
signal world_ready_for_play

## Region ids the atmosphere blends (WorldData.get_region answers these).
const REGIONS: Array[StringName] = [&"water_tribe", &"earth_kingdom", &"fire_nation", &"air_temple", &"wilds", &"ocean"]
## Radius (m) of the region sampling ring around the focus.
const REGION_SAMPLE_RADIUS := 380.0
## How fast the regional atmosphere follows the focus (fraction per second).
const REGION_BLEND_RATE := 0.35

var focus: Node3D = null
var camera: Camera3D = null
var clipmap: TerrainClipmap
var bounds: HeightBounds
var sky: SkyController
var cycle: DayNightCycle
var normal_baker: TerrainNormalBaker
var terrain_material: ShaderMaterial
var water: WaterSystem
var weather: WeatherSystem
var precipitation: WeatherParticles
var cloud_sea: CloudSea
var collision: TerrainCollision
var snow: SnowTrails

var _region_weights: Dictionary = {}
var _region_target: Dictionary = {}
var _region_timer: float = 0.0
var _is_ready := false
var _last_cam := Vector3.ZERO
var _world_time := 0.0
var _config_key := ""


func _init() -> void:
	WorldShaderGlobals.ensure()


func _ready() -> void:
	WorldData.load_world()
	add_to_group(&"persist")
	bounds = HeightBounds.new()
	bounds.build_async()
	cycle = DayNightCycle.new()
	cycle.name = "DayNightCycle"
	add_child(cycle)
	cycle.set_hour(GameState.time_of_day)
	sky = SkyController.new()
	sky.name = "Sky"
	add_child(sky)
	terrain_material = TerrainMaterial.make()
	clipmap = TerrainClipmap.new()
	clipmap.name = "Terrain"
	clipmap.material = terrain_material
	clipmap.bounds = bounds
	add_child(clipmap)
	_configure_terrain()
	water = WaterSystem.new()
	water.name = "Water"
	add_child(water)
	weather = WeatherSystem.new()
	weather.name = "Weather"
	add_child(weather)
	precipitation = WeatherParticles.new()
	precipitation.name = "Precipitation"
	add_child(precipitation)
	cloud_sea = CloudSea.new()
	add_child(cloud_sea)
	collision = TerrainCollision.new()
	collision.name = "Collision"
	add_child(collision)
	snow = SnowTrails.new()
	snow.name = "Snow"
	add_child(snow)
	snow.bind_material(terrain_material)
	normal_baker = TerrainNormalBaker.new()
	normal_baker.name = "NormalBaker"
	add_child(normal_baker)
	normal_baker.finished.connect(func(tex: Texture2D) -> void: TerrainMaterial.set_normal_map(terrain_material, tex))
	normal_baker.bake(4096 if Settings.detail_level() >= 2 else 2048)
	for r in REGIONS:
		_region_weights[r] = 0.0
	Events.graphics_settings_changed.connect(_on_graphics_changed)
	_update_regions(true)


func _exit_tree() -> void:
	if bounds:
		bounds.wait()


# --- Public API ------------------------------------------------------------------------------

## Sets the focus (player/mount) and the camera used for terrain LOD. Either may be null:
## without a camera the viewport's active camera is used, without a focus the camera.
func setup(p_focus: Node3D, p_camera: Camera3D) -> void:
	focus = p_focus
	camera = p_camera
	_update_regions(true)


## Changes the node that drives collision streaming, snow trails and the regional atmosphere.
func set_focus(node: Node3D) -> void:
	focus = node
	_update_regions(true)


func set_time_of_day(hour: float) -> void:
	cycle.set_hour(hour)


func get_time_of_day() -> float:
	return cycle.hour


## Game hours per real second (default 1/120: one game hour every two real minutes).
func set_time_scale(hours_per_second: float) -> void:
	cycle.time_scale = maxf(hours_per_second, 0.0)


func get_time_scale() -> float:
	return cycle.time_scale


## Changes the weather (clear, cloudy, snow, blizzard, rain, ash, fog) over `transition_s`
## seconds and locks it (quests, cinematics). `set_auto_weather(true)` resumes regional weather.
func set_weather(weather_name: StringName, transition_s: float = 10.0) -> void:
	weather.set_weather(weather_name, transition_s)


## The current (target) weather state.
func get_weather() -> StringName:
	return weather.current


## Enables/disables the regional weather cycle (on by default).
func set_auto_weather(enabled: bool) -> void:
	weather.set_auto(enabled)


## Current wind velocity on x/z (m/s), gusts included.
func get_wind() -> Vector2:
	return weather.wind_velocity()


## The sun light (for shadows/cinematics). The moon is `get_moon()`.
func get_sun() -> DirectionalLight3D:
	return sky.sun


func get_moon() -> DirectionalLight3D:
	return sky.moon


func get_environment() -> Environment:
	return sky.environment


## Current regional weights around the focus (region id -> 0..1, sums to 1).
func get_region_weights() -> Dictionary:
	return _region_weights.duplicate()


## Dominant region at the focus.
func get_dominant_region() -> StringName:
	var best: StringName = &"wilds"
	var bw := -1.0
	for r: StringName in _region_weights:
		if _region_weights[r] > bw:
			bw = _region_weights[r]
			best = r
	return best


## Keeps terrain collision within `radius` m of `pos` (NPC groups, companions, projectiles
## landing far away) until `release_collision_request(id)` or for `lifetime_s` if > 0.
func request_collision_around(pos: Vector3, radius: float, lifetime_s: float = 0.0) -> int:
	return collision.request_around(pos, radius, lifetime_s)


## Moves a collision request (e.g. a companion that follows at a distance).
func move_collision_request(id: int, pos: Vector3) -> void:
	collision.move_request(id, pos)


func release_collision_request(id: int) -> void:
	collision.release_request(id)


## True when terrain collision exists under `pos` (spawns should wait for it).
func is_collision_ready_at(pos: Vector3) -> bool:
	return collision.is_ready_at(pos)


## Builds the collision patch under `pos` immediately (teleports/respawns).
func ensure_collision_now(pos: Vector3) -> void:
	collision.ensure_now(pos)


## Resolves once terrain collision under the focus is ready (or immediately if it is).
func wait_until_ready() -> void:
	while not _is_ready:
		await world_ready_for_play


## How deep (m) trails have pressed the snow at `pos`: lower feet/hooves by this so they sit
## in their own prints (collision stays on the undisturbed snow surface).
func get_snow_sink_depth(pos: Vector3) -> float:
	return snow.get_sink_depth(pos)


## Ripple ring, foam and spray on the water surface at `pos` (for bending). `strength` 0.2
## (pebble) .. 3 (boulder / water surge). Returns false if there is no water at `pos`.
func splash(pos: Vector3, strength: float = 1.0) -> bool:
	return water.splash(pos, strength)


## Visible water surface height at x/z including the ocean swell (-INF where there is no water).
## Gameplay that only needs the still level should use WorldData.get_water_height.
func get_water_surface_height(x: float, z: float) -> float:
	return water.surface_height(x, z)


## Writes the clock to GameState before saving (group &"persist").
func write_save_state() -> void:
	GameState.time_of_day = cycle.hour


# --- Frame update ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var cam := _active_camera()
	var cam_pos := cam.global_position if cam else _focus_position()
	_last_cam = cam_pos
	_world_time += delta
	WorldShaderGlobals.set_value(&"world_time", _world_time)
	cycle.advance(delta)
	_region_timer -= delta
	if _region_timer <= 0.0:
		_region_timer = 0.5
		_update_regions(false)
	_blend_regions(delta)
	cycle.max_elevation_deg = AtmospherePalettes.sun_max_elevation(_region_weights)
	var state := _palette()
	weather.update(delta, get_dominant_region())
	var mods := weather.sky_mods()
	mods[&"fog_height"] = maxf(WorldData.get_height(cam_pos.x, cam_pos.z), 0.0) + 35.0
	sky.apply(state, cycle.sun_direction(), cycle.moon_direction(), cycle.moon_phase, cycle.hour, mods,
			weather.wind_velocity(), delta)
	clipmap.update_center(cam_pos)
	water.wave_scale = float(weather.params["waves"])
	water.set_region_weights(_region_weights)
	water.update(cam_pos, delta)
	precipitation.set_intensities(weather.precipitation())
	precipitation.follow(cam_pos)
	cloud_sea.update(cam_pos, float(weather.params["coverage"]))
	var focus_pos := _focus_position()
	collision.focus = focus if focus and is_instance_valid(focus) else null
	collision.update(focus_pos, delta)
	snow.camera_position = cam_pos
	snow.refill_multiplier = float(weather.params["refill"])
	snow.update(focus_pos, delta)
	if not _is_ready and is_collision_ready_at(focus_pos):
		_is_ready = true
		world_ready_for_play.emit()


func _active_camera() -> Camera3D:
	if camera and is_instance_valid(camera):
		return camera
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func _focus_position() -> Vector3:
	if focus and is_instance_valid(focus):
		return focus.global_position
	var cam := _active_camera()
	return cam.global_position if cam else Vector3.ZERO


func _palette() -> Dictionary:
	var elev := cycle.sun_elevation_deg()
	var states: Array = []
	var weights := PackedFloat32Array()
	for r: StringName in _region_weights:
		var w: float = _region_weights[r]
		if w > 0.001:
			states.append(AtmospherePalettes.for_region(r, elev))
			weights.append(w)
	return AtmospherePalettes.blend(states, weights)


## Samples regions around the focus (centre + ring) into target weights.
func _update_regions(snap: bool) -> void:
	var p := _focus_position()
	var counts := {}
	for r in REGIONS:
		counts[r] = 0.0
	var samples := 0.0
	for k in 9:
		var off := Vector2.ZERO
		var w := 2.0
		if k > 0:
			var a := TAU * float(k - 1) / 8.0
			off = Vector2(cos(a), sin(a)) * REGION_SAMPLE_RADIUS
			w = 1.0
		var reg := WorldData.get_region(p.x + off.x, p.z + off.y)
		counts[reg] = float(counts.get(reg, 0.0)) + w
		samples += w
	for r in REGIONS:
		_region_target[r] = float(counts.get(r, 0.0)) / samples
	if snap:
		_region_weights = _region_target.duplicate()


func _blend_regions(delta: float) -> void:
	var t := 1.0 - exp(-REGION_BLEND_RATE * delta * 3.0)
	for r in REGIONS:
		_region_weights[r] = lerpf(float(_region_weights.get(r, 0.0)), float(_region_target.get(r, 0.0)), t)


# --- Settings ------------------------------------------------------------------------------------

func _configure_terrain() -> void:
	var detail := Settings.detail_level()
	var tile_res: int = [16, 20, 24, 32][detail]
	var spacing: float = [0.25, 0.25, 0.25, 0.125][detail]
	var key := "%d|%f|%f" % [tile_res, spacing, Settings.view_distance_m()]
	if key == _config_key:
		return
	_config_key = key
	clipmap.configure(tile_res, spacing, Settings.view_distance_m())
	clipmap.build()
	if _last_cam != Vector3.ZERO:
		clipmap.update_center(_last_cam)


func _on_graphics_changed() -> void:
	TerrainMaterial.apply_quality(terrain_material)
	_configure_terrain()
