extends Node3D
## Dev scene: the real world (WorldRenderer) with streamed WorldContent and a free-fly camera.
##   godot --path . -- --scene=res://scenes/dev/worldcontent_world.tscn
## Controls: RMB + mouse look, WASD move, Q/E down/up, Shift x6, 1-9 presets, T +1 h, P stats.

## Camera presets. With "agl": true the y of pos/look is metres above max(ground, sea level).
const VIEWS := {
	"snow_forest": {"pos": Vector3(150, 2.2, -1660), "look": Vector3(110, 6, -1730), "agl": true, "hour": 11.0, "fov": 66.0},
	"snow_forest_mid": {"pos": Vector3(260, 70, -1580), "look": Vector3(120, 0, -1760), "agl": true, "hour": 11.0, "fov": 62.0},
	"wt_snow": {"pos": Vector3(3545, 2.4, -3560), "look": Vector3(3600, 6, -3640), "agl": true, "hour": 12.0, "fov": 66.0},
	"ek_forest": {"pos": Vector3(2030, 1.8, -1080), "look": Vector3(2070, 5, -1140), "agl": true, "hour": 10.0, "fov": 68.0},
	"ek_forest_mid": {"pos": Vector3(1960, 80, -980), "look": Vector3(2080, 0, -1150), "agl": true, "hour": 10.0, "fov": 62.0},
	"ek_farms": {"pos": Vector3(1850, 3.0, -330), "look": Vector3(1920, 2, -400), "agl": true, "hour": 16.5, "fov": 66.0},
	"ek_farms_mid": {"pos": Vector3(1800, 70, -270), "look": Vector3(1930, 0, -420), "agl": true, "hour": 16.5, "fov": 62.0},
	"ek_meadow": {"pos": Vector3(-1240, 1.6, -1230), "look": Vector3(-1290, 2, -1290), "agl": true, "hour": 9.5, "fov": 68.0},
	"fn_jungle": {"pos": Vector3(-3450, 2.0, 1070), "look": Vector3(-3500, 6, 1010), "agl": true, "hour": 13.0, "fov": 68.0},
	"fn_jungle_mid": {"pos": Vector3(-3380, 90, 1160), "look": Vector3(-3500, 0, 1010), "agl": true, "hour": 13.0, "fov": 62.0},
	"fn_beach": {"pos": Vector3(-3760, 2.0, 1030), "look": Vector3(-3800, 3, 980), "agl": true, "hour": 15.0, "fov": 68.0},
	"fn_volcanic": {"pos": Vector3(-3360, 2.2, 2880), "look": Vector3(-3420, 4, 2950), "agl": true, "hour": 18.2, "fov": 66.0},
	"fn_volcanic_mid": {"pos": Vector3(-3300, 70, 2840), "look": Vector3(-3420, 0, 2960), "agl": true, "hour": 18.2, "fov": 62.0},
	"at_garden": {"pos": Vector3(2790, 2.0, 2995), "look": Vector3(2840, 4, 3050), "agl": true, "hour": 8.5, "fov": 66.0},
	"at_slopes_mid": {"pos": Vector3(2690, 90, 2930), "look": Vector3(2850, 0, 3080), "agl": true, "hour": 8.5, "fov": 62.0},
	"forest_far": {"pos": Vector3(1500, 260, -700), "look": Vector3(2200, 30, -1200), "hour": 11.0, "fov": 62.0},
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
	add_child(content)
	content.setup(cam, cam)
	set_view(Router.params.get("view", "ek_forest"))


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


## Spawns (or moves) the real player character - walk tests over bridges and into caves. World
## streaming and content then follow the player and its camera rig.
func spawn_player(xform: Transform3D, element: int = ElementDefs.Element.AIR) -> PlayerCharacter:
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


## Back to the free-fly camera.
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
		elif key == KEY_P:
			print(content.get_stats())


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
	if dir != Vector3.ZERO:
		cam.global_position += dir.normalized() * speed * mult * delta
