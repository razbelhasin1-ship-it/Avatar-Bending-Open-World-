extends Node3D
## Dev scene for the world renderer: free-fly camera over the real world with view presets.
##
##   godot --path . -- --scene=res://scenes/dev/world_render_test.tscn
## Controls: RMB + mouse look, WASD move, Q/E down/up, Shift x6 speed, 1-9 presets,
## T +1 hour, Y cycle weather, P print frame stats.

## Camera presets. With "agl": true the y of pos/look is metres above max(ground, sea level).
const VIEWS := {
	"water_tribe": {"pos": Vector3(360, 48, -2320), "look": Vector3(-300, 30, -2860), "agl": true, "hour": 10.5, "fov": 62.0},
	"water_tribe_blizzard": {"pos": Vector3(70, 5, -2650), "look": Vector3(-300, 12, -2760), "agl": true, "hour": 13.0, "weather": &"blizzard", "fov": 66.0},
	"water_tribe_night": {"pos": Vector3(360, 60, -2320), "look": Vector3(-300, 40, -2880), "agl": true, "hour": 23.2, "fov": 62.0},
	"ba_sing_se": {"pos": Vector3(2860, 45, 520), "look": Vector3(2000, 25, 210), "agl": true, "hour": 17.75, "fov": 60.0},
	"fire_nation": {"pos": Vector3(-2830, 345, 2270), "look": Vector3(-2400, 140, 2830), "hour": 15.5, "fov": 64.0},
	"fire_volcano": {"pos": Vector3(-2650, 330, 2620), "look": Vector3(-1735, 520, 3485), "hour": 17.6, "fov": 55.0},
	"air_temple": {"pos": Vector3(2150, 905, 2940), "look": Vector3(2520, 790, 3380), "hour": 8.0, "fov": 62.0},
	"shore": {"pos": Vector3(-3385, 1.7, 3470), "look": Vector3(-3470, 0.3, 3560), "agl": true, "hour": 11.0, "fov": 66.0},
	"vista": {"pos": Vector3(1400, 600, -900), "look": Vector3(2600, 300, 300), "hour": 11.5, "fov": 70.0},
}

var world: WorldRenderer
var cam: Camera3D
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
	set_view(Router.params.get("view", "water_tribe"))


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
