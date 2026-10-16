class_name ArrivalCinematic
extends Node
## New-game arrival (docs/modules/worldscene.md): a letterboxed camera flight along
## WorldData.get_arrival_camera(element) - from high above the home region down to just behind
## the player - with the home region's title card, the regional theme swelling in and a gong,
## that ends by settling exactly onto the player's own camera and handing control back.
## Any key / button / tap skips (quick fade, same end state). Total <= ~10 s.
##
##   var arrival := ArrivalCinematic.new()
##   scene.add_child(arrival)
##   arrival.prepare(scene)       # before the first visible frame: camera at the start, bars on
##   arrival.play()               # after the reveal; emits finished(skipped)

signal finished(skipped: bool)

## Seconds of the final settle onto the player's camera.
const SETTLE_TIME := 1.6
## Inputs are ignored this long after the start (a held confirm from the menu must not skip).
const SKIP_GRACE := 0.5
const TITLE_AT := 0.2
const TITLE_HOLD := 3.4

var scene: PlayableScene
var element: int = ElementDefs.Element.NONE
var camera: Camera3D
var duration := 8.0
var start := Transform3D.IDENTITY
var end := Transform3D.IDENTITY
var fov_start := 58.0
var fov_end := 72.0
var running := false
var skipped := false
## Elapsed cinematic time (s).
var time := 0.0

var _p0 := Vector3.ZERO
var _p1 := Vector3.ZERO
var _p2 := Vector3.ZERO
var _p3 := Vector3.ZERO
var _look0 := Vector3.ZERO
var _look1 := Vector3.ZERO
var _title_shown := false
var _skip_hint_shown := false
var _done := false
var _track: StringName = &""
var _settle_from := Transform3D.IDENTITY
var _settle_fov := 72.0
var _settling := false


## Camera path for an element: the baked arrival camera, or an orbit-down fallback.
static func path_for(p_element: int, spawn: Transform3D) -> Dictionary:
	var d := WorldData.get_arrival_camera(p_element)
	if not d.is_empty():
		return d
	var f := -spawn.basis.z
	var s := Transform3D(Basis.IDENTITY, spawn.origin - f * 160.0 + Vector3.UP * 90.0).looking_at(spawn.origin + f * 200.0, Vector3.UP)
	var e := Transform3D(Basis.IDENTITY, spawn.origin - f * 7.0 + Vector3.UP * 3.0).looking_at(spawn.origin + f * 60.0 + Vector3.UP * 0.5, Vector3.UP)
	return {"start": s, "end": e, "duration": 8.0, "fov_start": 58.0, "fov_end": 72.0}


## Sets up the shot before the first visible frame.
func prepare(p_scene: PlayableScene) -> void:
	scene = p_scene
	element = scene.element
	var spawn := scene.player.global_transform if scene.player else WorldData.get_spawn(element)
	var d := path_for(element, spawn)
	start = d["start"]
	end = d["end"]
	duration = clampf(float(d.get("duration", 8.0)), 5.0, 9.0)
	fov_start = float(d.get("fov_start", 58.0))
	fov_end = float(d.get("fov_end", 72.0))
	_build_curve()
	camera = Camera3D.new()
	camera.name = "ArrivalCamera"
	camera.far = 12000.0
	camera.near = 0.1
	scene.add_child(camera)
	camera.global_transform = _sample(0.0)
	camera.fov = fov_start
	camera.make_current()
	if scene.player:
		scene.player.enter_cinematic(duration + SETTLE_TIME + 20.0)
	scene.set_hud_visible(false)
	scene.overlay.show_bars(0.0)
	# The first look at home is a clear one; regional weather resumes afterwards.
	scene.renderer.set_weather(&"clear", 0.0)
	_track = SoundCatalog.REGION_MUSIC.get(StringName(ElementDefs.get_data(element).get("home_region", &"")), &"")
	if _track != &"":
		Audio.play_music(_track, 1.0, -7.0)
	var amb: StringName = SoundCatalog.REGION_AMBIENCE.get(StringName(ElementDefs.get_data(element).get("home_region", &"")), &"")
	if amb != &"":
		Audio.set_ambience(amb, 0.0, 2.0)


## Starts the flight (call after the scene is revealed).
func play() -> void:
	running = true
	time = 0.0
	set_process(true)
	set_process_input(true)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)


## Cubic Bezier: keeps altitude at first (a glide over the region), then swoops down behind
## the player; the look target travels from the start's focus to the end's.
func _build_curve() -> void:
	_p0 = start.origin
	_p3 = end.origin
	var span := _p3 - _p0
	var flat := Vector3(span.x, 0.0, span.z)
	_p1 = _p0 + flat * 0.42 + Vector3.UP * maxf(0.0, -span.y) * 0.04
	_p2 = _p3 - flat.normalized() * minf(flat.length() * 0.22, 120.0) + Vector3.UP * minf(absf(span.y) * 0.18, 40.0)
	_look0 = start.origin - start.basis.z * 400.0
	_look1 = end.origin - end.basis.z * 60.0


static func _bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return a * (u * u * u) + b * (3.0 * u * u * t) + c * (3.0 * u * t * t) + d * (t * t * t)


static func _smootherstep(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


## Camera transform along the flight at normalised time u (0..1).
func _sample(u: float) -> Transform3D:
	var e := _smootherstep(u)
	var pos := _bezier(_p0, _p1, _p2, _p3, e)
	var lk := _look0.lerp(_look1, _smootherstep(clampf((u - 0.15) / 0.75, 0.0, 1.0)))
	if pos.distance_to(lk) < 0.5:
		lk = pos - end.basis.z
	var t := Transform3D(Basis.IDENTITY, pos).looking_at(lk, Vector3.UP)
	# a gentle bank while the heading turns
	var bank := sin(e * PI) * 0.035
	return Transform3D(t.basis * Basis(Vector3.BACK, bank), pos)


func _process(delta: float) -> void:
	if not running or _done:
		return
	time += delta
	if not _title_shown and time >= duration * TITLE_AT:
		_title_shown = true
		_show_title()
	if not _skip_hint_shown and time >= 1.2:
		_skip_hint_shown = true
		scene.overlay.show_skip_hint(true)
	if _any_action_pressed():
		skip()
		return
	if time < duration:
		var u := time / duration
		camera.global_transform = _sample(u)
		camera.fov = lerpf(fov_start, fov_end, _smootherstep(u))
		return
	# Settle: blend from the path end onto the player's live camera.
	var pc := _player_camera()
	if not _settling:
		_settling = true
		_settle_from = camera.global_transform
		_settle_fov = camera.fov
		scene.overlay.hide_bars(SETTLE_TIME)
		scene.set_hud_visible(true, SETTLE_TIME)
		if _track != &"":
			Audio.music.set_base(_track, 6.0, 0.0)
	var k := _smootherstep((time - duration) / SETTLE_TIME)
	if pc:
		camera.global_transform = _settle_from.interpolate_with(pc.global_transform, k)
		camera.fov = lerpf(_settle_fov, pc.fov, k)
	if time >= duration + SETTLE_TIME:
		_finish(false)


func _player_camera() -> Camera3D:
	if scene.player and is_instance_valid(scene.player) and scene.player.camera_rig:
		return scene.player.camera_rig.camera
	return null


func _show_title() -> void:
	var data := ElementDefs.get_data(element)
	var home := String(data.get("home_name", "Home"))
	var region := StringName(data.get("home_region", &""))
	var region_title := TitleCard.region_title(region)
	# The caption names the nation when the city name does not ("Ba Sing Se" / The Earth Kingdom).
	var caption := "Your journey begins"
	if not home.to_lower().contains(WorldData.get_region_name(region).to_lower()):
		caption = region_title
	scene.title_card.show_title(home, caption, element, TITLE_HOLD)
	RegionDirector.mark_visited(region)
	Audio.play_2d(&"wind_chime" if element == ElementDefs.Element.AIR else &"gong", -6.0)
	if _track != &"":
		Audio.music.set_base(_track, 2.5, 1.5)


func _input(event: InputEvent) -> void:
	if not running or _done or time < SKIP_GRACE:
		return
	var pressed := false
	if event is InputEventKey:
		pressed = (event as InputEventKey).pressed and not (event as InputEventKey).echo
	elif event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventJoypadButton:
		pressed = (event as InputEventJoypadButton).pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventJoypadMotion:
		pressed = absf((event as InputEventJoypadMotion).axis_value) > 0.75 \
				and (event as InputEventJoypadMotion).axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]
	elif event is InputEventAction:
		pressed = (event as InputEventAction).pressed
	if pressed:
		get_viewport().set_input_as_handled()
		skip()


## Touch overlay buttons press actions without events: any gameplay action skips too.
func _any_action_pressed() -> bool:
	if time < SKIP_GRACE:
		return false
	for a: StringName in [&"jump", &"attack_light", &"attack_heavy", &"dodge", &"interact", &"pause", &"block"]:
		if InputMap.has_action(a) and Input.is_action_just_pressed(a):
			return true
	return false


## Skips to the end state: quick fade, camera on the player, bars and title gone.
func skip() -> void:
	if _done or skipped:
		return
	skipped = true
	running = false
	scene.overlay.show_skip_hint(false)
	_skip_sequence()


func _skip_sequence() -> void:
	await scene.fader.fade_out(0.25)
	if not is_instance_valid(scene) or scene.is_exiting():
		return
	scene.title_card.skip()
	scene.overlay.hide_bars(0.0)
	scene.set_hud_visible(true, 0.0)
	if not _title_shown:
		RegionDirector.mark_visited(StringName(ElementDefs.get_data(element).get("home_region", &"")))
	if _track != &"":
		Audio.music.set_base(_track, 2.0, 0.0)
	var pc := _player_camera()
	if pc:
		camera.global_transform = pc.global_transform
		camera.fov = pc.fov
	_finish(true)
	await scene.fader.fade_in(0.45)


func _finish(was_skipped: bool) -> void:
	if _done:
		return
	_done = true
	running = false
	set_process(false)
	scene.renderer.set_auto_weather(true)
	if scene.player and is_instance_valid(scene.player) and scene.player.camera_rig:
		scene.player.camera_rig.make_current()
	if camera and is_instance_valid(camera):
		camera.queue_free()
	camera = null
	finished.emit(was_skipped)


func _exit_tree() -> void:
	if camera and is_instance_valid(camera):
		camera.queue_free()
