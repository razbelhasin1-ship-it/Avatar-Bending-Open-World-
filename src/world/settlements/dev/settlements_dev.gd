extends Node3D
## Dev scene: the real world (WorldRenderer + WorldContent) with the settlements streamed in and a
## free-fly camera.
##   godot --path . -- --scene=res://scenes/dev/settlements_wa.tscn
## Controls: RMB + mouse look, WASD move, Q/E down/up, Shift x6, 1-9 view presets, T +1 h,
## P prints settlement stats, N toggles night.

## Camera presets (world positions; "agl": y values are metres above max(ground, sea level)).
const VIEWS := {
	"nwt_bay": {"pos": Vector3(-300, 170, -2180), "look": Vector3(-300, 20, -2780), "hour": 10.5, "fov": 60.0},
	"nwt_gate": {"pos": Vector3(-300, 12, -2290), "look": Vector3(-300, 24, -2700), "hour": 9.5, "fov": 64.0},
	"nwt_canal": {"pos": Vector3(-194.3, 17.7, -3044.0), "look": Vector3(-113.7, 16.0, -3002.0), "hour": 11.0, "fov": 68.0},
	"nwt_street": {"pos": Vector3(-595.7, 4.2, -2790.8), "look": Vector3(-561.6, 4.0, -2839.5), "hour": 10.0, "fov": 68.0},
	"nwt_palace": {"pos": Vector3(-300, 62, -3135), "look": Vector3(-300, 75, -3260), "hour": 15.5, "fov": 66.0},
	"nwt_oasis": {"pos": Vector3(-532.1, 55.8, -3188.0), "look": Vector3(-560.0, 54.5, -3200.0), "hour": 13.0, "fov": 66.0},
	"nwt_interior": {"pos": Vector3(-448.9, 33.9, -3139.5), "look": Vector3(-446.0, 33.0, -3129.4), "hour": 12.0, "fov": 72.0},
	"nwt_hall": {"pos": Vector3(-21.9, 34.2, -3072.1), "look": Vector3(-28.1, 33.0, -3082.8), "hour": 12.0, "fov": 72.0},
	"nwt_night": {"pos": Vector3(-300, 9, -2860), "look": Vector3(-300, 45, -3240), "hour": 22.5, "fov": 62.0},
	"nwt_aurora": {"pos": Vector3(-300, 48, -2452), "look": Vector3(-300, 168, -3150), "hour": 23.0, "fov": 72.0},
	"nwt_night_street": {"pos": Vector3(-397.8, 17.9, -2985.1), "look": Vector3(-267.1, 19.0, -2996.6), "hour": 22.0, "fov": 68.0},
	"nwt_plaza": {"pos": Vector3(-286, 19.0, -3036), "look": Vector3(-302, 15.5, -3058), "hour": 13.5, "fov": 66.0},
	"nwt_harbor": {"pos": Vector3(-250, 12, -2860), "look": Vector3(-150, 6, -2880), "hour": 9.0, "fov": 66.0},
	"nwt_canal_ring": {"pos": Vector3(-492.9, 18.6, -2998.7), "look": Vector3(-359.1, 15.0, -3040.9), "hour": 10.5, "fov": 66.0},
	"arctic_village": {"pos": Vector3(-2046, 7.0, -2992), "look": Vector3(-2080, 1.5, -3020), "hour": 11.0, "fov": 64.0, "agl": true},
	"arctic_camp": {"pos": Vector3(-2652, 8.0, -2752), "look": Vector3(-2682, 1.0, -2782), "hour": 15.0, "fov": 64.0, "agl": true},
	"sat_far": {"pos": Vector3(2120, 960, 2560), "look": Vector3(2500, 840, 3350), "hour": 9.0, "fov": 50.0},
	"sat_courtyard": {"pos": Vector3(2521, 805.5, 3246), "look": Vector3(2500, 845, 3350), "hour": 10.0, "fov": 66.0},
	"sat_terrace": {"pos": Vector3(2370, 784.2, 3275), "look": Vector3(2500, 835, 3350), "hour": 10.5, "fov": 66.0},
	"sat_bridge": {"pos": Vector3(2338, 784.3, 3367), "look": Vector3(2200, 788, 3381), "hour": 11.0, "fov": 66.0},
	"sat_door": {"pos": Vector3(2500, 804.6, 3456), "look": Vector3(2500, 808.5, 3424), "hour": 14.0, "fov": 66.0},
	"sat_landing": {"pos": Vector3(2536, 765.5, 3146), "look": Vector3(2500, 800, 3330), "hour": 8.5, "fov": 66.0},
	"sat_pinnacle": {"pos": Vector3(2800, 785.5, 3436), "look": Vector3(2500, 835, 3350), "hour": 16.0, "fov": 62.0},
	"sat_sunset": {"pos": Vector3(2820, 880, 3120), "look": Vector3(2500, 830, 3350), "hour": 18.6, "fov": 56.0},
	"sat_night": {"pos": Vector3(2521, 805.5, 3246), "look": Vector3(2500, 845, 3350), "hour": 21.5, "fov": 66.0},
	"sat_night_far": {"pos": Vector3(2120, 960, 2560), "look": Vector3(2500, 840, 3350), "hour": 22.0, "fov": 50.0},
}

var world: WorldRenderer
var content: WorldContent
var cam: Camera3D
var player: PlayerCharacter = null
var speed := 30.0
var _yaw := 0.0
var _pitch := 0.0
var _looking := false


func _ready() -> void:
	cam = Camera3D.new()
	cam.name = "FlyCamera"
	cam.near = 0.1
	cam.far = 30000.0
	add_child(cam)
	cam.current = true
	world = WorldRenderer.new()
	world.name = "World"
	add_child(world)
	world.setup(cam, cam)
	content = WorldContent.new()
	content.name = "Content"
	if Router.params.get("no_default_content", false):
		content.use_default_providers = false
	add_child(content)
	content.setup(cam, cam)
	Settlements.register(content, Router.params.get("settlement_opts", {}))
	set_view(Router.params.get("view", "nwt_bay"))


## Moves the camera to a preset (and applies its hour/weather).
func set_view(vname: String) -> void:
	if not VIEWS.has(vname):
		return
	var v: Dictionary = VIEWS[vname]
	var pos: Vector3 = v["pos"]
	var look: Vector3 = v["look"]
	if v.get("agl", false):
		pos.y += maxf(WorldData.get_height(pos.x, pos.z), 0.0)
		look.y += maxf(WorldData.get_height(look.x, look.z), 0.0)
	place_camera(pos, look, v.get("fov", 60.0))
	if v.has("hour"):
		world.set_time_of_day(v["hour"])
	world.set_weather(v.get("weather", &"clear"), 0.0)


## Spawns (or moves) the real player character for walk tests; streaming follows the player.
func spawn_player(xform: Transform3D, element: int = ElementDefs.Element.WATER) -> PlayerCharacter:
	if player == null:
		player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerCharacter
		player.element = element
		player.auto_respawn = false
		add_child(player)
	player.teleport(xform)
	var pc := player.camera_rig.get_camera()
	pc.current = true
	world.setup(player, pc)
	content.setup(player, pc)
	return player


func remove_player() -> void:
	if player:
		player.queue_free()
		player = null
	cam.current = true
	world.setup(cam, cam)
	content.setup(cam, cam)


func place_camera(pos: Vector3, look: Vector3, fov: float = 60.0) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = fov
	_yaw = cam.rotation.y
	_pitch = cam.rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_looking = event.pressed
	elif event is InputEventMouseMotion and _looking:
		var rel := (event as InputEventMouseMotion).relative
		_yaw -= rel.x * 0.003
		_pitch = clampf(_pitch - rel.y * 0.003, -1.5, 1.5)
		cam.rotation = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		var keys := VIEWS.keys()
		if key >= KEY_1 and key <= KEY_9 and key - KEY_1 < keys.size():
			set_view(keys[key - KEY_1])
		elif key == KEY_T:
			world.set_time_of_day(world.get_time_of_day() + 1.0)
		elif key == KEY_N:
			world.set_time_of_day(22.5 if world.get_time_of_day() < 19.0 else 11.0)
		elif key == KEY_P:
			print(content.get_stats())
			for p in content.get_providers():
				if p is SettlementProvider:
					print(p.id, " ", (p as SettlementProvider).stats)


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir -= cam.global_basis.z
	if Input.is_physical_key_pressed(KEY_S):
		dir += cam.global_basis.z
	if Input.is_physical_key_pressed(KEY_A):
		dir -= cam.global_basis.x
	if Input.is_physical_key_pressed(KEY_D):
		dir += cam.global_basis.x
	if Input.is_physical_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		dir -= Vector3.UP
	var mult := 6.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	if dir != Vector3.ZERO and cam.current:
		cam.global_position += dir.normalized() * speed * mult * delta
