class_name TravelSystem
extends Node
## Travel inside the world (docs/modules/worldscene.md "Travel"):
## * Ferry landings at every port with a route (WorldData.get_ports / get_ferries): the ferry
##   waits moored at the berth; "Take the ferry" asks for a destination (DialogueBox choices),
##   then a short sailing interlude plays - the boat casts off along the real route with the
##   player on deck (letterboxed chase camera), the screen fades while the destination streams
##   in, the boat glides up to the destination berth - and the player steps onto that quay.
## * `travel_to(xform)`: faded teleport for map fast travel (waits for terrain collision and
##   nearby content at the destination, never drops the player into the void).

signal travel_started(kind: StringName, destination: Transform3D)
signal travel_finished(kind: StringName, destination: Transform3D)

const SAIL_OUT_TIME := 3.0
const SAIL_IN_TIME := 2.0
const SAIL_OUT_DIST := 24.0
const SAIL_IN_DIST := 18.0
const CONTENT_TIMEOUT := 8.0

var scene: PlayableScene
var player: PlayerCharacter
var director: RegionDirector = null
var busy := false
## port id -> FerryDock / moored FerryBoat
var docks: Dictionary = {}
var moored: Dictionary = {}
## Multiplies interlude durations and waits (tests use a small value).
var interlude_scale := 1.0
var travels := 0
var last_kind: StringName = &""
var last_destination := Transform3D.IDENTITY
## Where the current trip ends (save guard reads it while busy).
var pending_destination := Transform3D.IDENTITY
## &"", &"depart", &"transit", &"arrive" while a ferry trip runs.
var phase: StringName = &""
var boat: FerryBoat = null
var camera: Camera3D = null

var _pts := PackedVector2Array()
var _s := 0.0
var _cam_t := 0.0


func _ready() -> void:
	# After the player's physics tick: passengers are pinned to the deck.
	process_physics_priority = 50


func setup(p_scene: PlayableScene, p_player: PlayerCharacter) -> void:
	scene = p_scene
	player = p_player


func _valid() -> bool:
	return is_instance_valid(scene) and is_instance_valid(player) and player.is_inside_tree() and not scene.is_exiting()


# --- data helpers ------------------------------------------------------------------------------------

static func port_by_id(id: StringName) -> Dictionary:
	for p: Dictionary in WorldData.get_ports():
		if StringName(p.get("id", &"")) == id:
			return p
	return {}


## Ferry routes leaving a port (both directions of every ferry line):
## [{"ferry": id, "to": port id, "points": PackedVector2Array from this berth to the other}].
static func routes_from(port_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Dictionary in WorldData.get_ferries():
		var pts: PackedVector2Array = f.get("points", PackedVector2Array())
		if StringName(f.get("from", &"")) == port_id:
			out.append({"ferry": f["id"], "to": StringName(f["to"]), "points": pts})
		elif StringName(f.get("to", &"")) == port_id:
			var rev := pts.duplicate()
			rev.reverse()
			out.append({"ferry": f["id"], "to": StringName(f["from"]), "points": rev})
	return out


static func route_between(from_id: StringName, to_id: StringName) -> Dictionary:
	for r in routes_from(from_id):
		if r["to"] == to_id:
			return r
	return {}


## Standing spot on a port's quay, facing inland (away from the berth).
static func quay_transform(port: Dictionary) -> Transform3D:
	var q: Vector3 = port.get("quay", Vector3.ZERO)
	return Transform3D(Basis(Vector3.UP, float(port.get("yaw", 0.0)) + PI), q)


static func polyline_length(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in pts.size() - 1:
		l += pts[i].distance_to(pts[i + 1])
	return l


## Point at arc length `s` along the polyline (clamped).
static func polyline_point(pts: PackedVector2Array, s: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var left := maxf(s, 0.0)
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if left <= seg or i == pts.size() - 2:
			return pts[i].lerp(pts[i + 1], clampf(left / maxf(seg, 0.001), 0.0, 1.0))
		left -= seg
	return pts[pts.size() - 1]


static func polyline_dir(pts: PackedVector2Array, s: float) -> Vector2:
	var total := polyline_length(pts)
	var a := polyline_point(pts, clampf(s - 3.0, 0.0, total))
	var b := polyline_point(pts, clampf(s + 8.0, 0.0, total))
	var d := b - a
	if d.length_squared() < 1e-6 and pts.size() > 1:
		d = pts[pts.size() - 1] - pts[0]
	return d.normalized()


static func port_label(port: Dictionary) -> String:
	return "%s  ·  %s" % [String(port.get("name", "?")), WorldData.get_region_name(StringName(port.get("region", &"")))]


# --- docks -------------------------------------------------------------------------------------------

## Builds a landing + a moored ferry at every port that has a ferry route.
func build_docks(parent: Node) -> void:
	for port: Dictionary in WorldData.get_ports():
		var id := StringName(port.get("id", &""))
		var routes := routes_from(id)
		if routes.is_empty() or docks.has(id):
			continue
		var dock := FerryDock.new(port)
		parent.add_child(dock)
		dock.requested.connect(_on_dock_requested)
		docks[id] = dock
		var b := FerryBoat.new(NationPalette.nation_for_region(StringName(port.get("region", &""))))
		b.name = "Ferry_%s" % String(id)
		parent.add_child(b)
		var pts: PackedVector2Array = routes[0]["points"]
		var berth: Vector3 = port.get("berth", Vector3.ZERO)
		var d := polyline_dir(pts, 0.0)
		b.place(Vector3(berth.x, _water_y(berth), berth.z), Vector3(d.x, 0.0, d.y))
		moored[id] = b


func _water_y(p: Vector3) -> float:
	var w := WorldData.get_water_height(p.x, p.z)
	return w if w > -INF else 0.0


func _set_docks_available(on: bool) -> void:
	for d: FerryDock in docks.values():
		if is_instance_valid(d):
			d.available = on
			if d.interactable:
				d.interactable.enabled = on


func _on_dock_requested(dock: FerryDock) -> void:
	if busy or not _valid():
		return
	open_dock(dock.port_id)


## Destination choice at a dock (DialogueBox), then the trip. Returns true if sailed.
func open_dock(port_id: StringName) -> bool:
	if busy or not _valid():
		return false
	var port := port_by_id(port_id)
	var routes := routes_from(port_id)
	if routes.is_empty():
		return false
	var labels: Array = []
	for r in routes:
		labels.append(port_label(port_by_id(r["to"])))
	labels.append("Stay ashore")
	var region := StringName(port.get("region", &""))
	var i := await scene.ask_choice("Ferry Master", "Fair winds out of %s today. Where are you bound?" % String(port.get("name", "the harbor")),
			labels, {"element": TitleCard.REGION_ELEMENT.get(region, ElementDefs.Element.NONE)})
	if i < 0 or i >= routes.size() or not _valid():
		return false
	return await take_ferry(port_id, routes[i]["to"])


# --- ferry trip ------------------------------------------------------------------------------------------

## Sails from one port to another with the interlude. Returns false if impossible/busy.
func take_ferry(from_id: StringName, to_id: StringName) -> bool:
	if busy or not _valid() or not player.is_alive():
		return false
	var route := route_between(from_id, to_id)
	var from_port := port_by_id(from_id)
	var to_port := port_by_id(to_id)
	if route.is_empty() or to_port.is_empty():
		return false
	busy = true
	_pts = route["points"]
	pending_destination = quay_transform(to_port)
	travel_started.emit(&"ferry", pending_destination)
	_set_docks_available(false)
	_pause_director(true)
	var k := maxf(interlude_scale, 0.01)
	var to_name := String(to_port.get("name", "?"))
	# --- cast off --------------------------------------------------------------------------
	await scene.fader.fade_out(0.45 * k)
	if not _valid():
		return _abort()
	if player.get_state() == PlayerCharacter.State.MOUNTED:
		player.dismount()
	player.enter_cinematic(120.0)
	scene.set_hud_visible(false)
	var home_boat: FerryBoat = moored.get(from_id)
	if home_boat and is_instance_valid(home_boat):
		home_boat.visible = false
	boat = FerryBoat.new(NationPalette.nation_for_region(StringName(from_port.get("region", &""))))
	boat.name = "SailingFerry"
	scene.props_root.add_child(boat)
	boat.set_deck_collision(true)
	_s = 0.0
	_place_boat()
	_board()
	camera = Camera3D.new()
	camera.name = "FerryCamera"
	camera.far = 9000.0
	camera.fov = 58.0
	scene.add_child(camera)
	camera.make_current()
	phase = &"depart"
	_cam_t = 0.0
	_update_camera(0.0)
	scene.overlay.show_bars(0.0)
	scene.overlay.set_caption("Bound for %s" % to_name, "Ferry from %s" % String(from_port.get("name", "")))
	Audio.set_ambience_layer(&"local", &"amb_ocean_waves", -2.0, 1.0)
	Audio.play_sfx(&"wind_chime", boat.global_position + Vector3.UP * 3.0, -4.0)
	for i in 2:
		await get_tree().physics_frame
	await scene.fader.fade_in(0.55 * k)
	await _sail(0.0, SAIL_OUT_DIST, SAIL_OUT_TIME * k, true)
	await scene.fader.fade_out(0.5 * k)
	if not _valid():
		return _abort()
	# --- open water (under black: the destination streams in) -----------------------------------
	phase = &"transit"
	scene.fader.set_text("Sailing to %s" % to_name)
	var total := polyline_length(_pts)
	var s_in := maxf(total - SAIL_IN_DIST, total * 0.5)
	_s = s_in
	_place_boat()
	_board()
	_cam_t = 0.0
	await _wait_content(CONTENT_TIMEOUT * k)
	for i in 3:
		await get_tree().process_frame
	if not _valid():
		return _abort()
	scene.fader.set_text("")
	phase = &"arrive"
	scene.overlay.set_caption(to_name, WorldData.get_region_name(StringName(to_port.get("region", &""))))
	await scene.fader.fade_in(0.5 * k)
	await _sail(s_in, total, SAIL_IN_TIME * k, false)
	await scene.fader.fade_out(0.45 * k)
	if not _valid():
		return _abort()
	# --- step ashore -------------------------------------------------------------------------
	phase = &""
	var quay := pending_destination
	await scene.wait_for_ground(quay.origin, 12.0)
	if not _valid():
		return _abort()
	var x := scene.ground_transform(quay)
	_end_interlude(from_id)
	player.exit_cinematic()
	player.teleport(x)
	player.velocity = Vector3.ZERO
	for i in 2:
		await get_tree().physics_frame
	await scene.fader.fade_in(0.6 * k)
	_finish(&"ferry", x)
	Events.notify.emit("Arrived at %s." % to_name, &"info")
	return true


func _sail(s0: float, s1: float, duration: float, ease_in: bool) -> void:
	var t := 0.0
	while t < duration and _valid():
		await get_tree().process_frame
		if get_tree().paused:
			continue
		t += get_process_delta_time()
		var u := clampf(t / maxf(duration, 0.001), 0.0, 1.0)
		var e := pow(u, 1.7) if ease_in else 1.0 - pow(1.0 - u, 2.2)
		_s = lerpf(s0, s1, e)
		_cam_t += get_process_delta_time()


func _place_boat() -> void:
	if boat == null or not is_instance_valid(boat):
		return
	var p := polyline_point(_pts, _s)
	var d := polyline_dir(_pts, _s)
	boat.place(Vector3(p.x, _water_y(Vector3(p.x, 0, p.y)), p.y), Vector3(d.x, 0.0, d.y))


## Pins the player to the deck (standing at the bow, facing ahead).
func _board() -> void:
	if boat == null or not is_instance_valid(boat) or not _valid():
		return
	var pt := boat.passenger_transform()
	player.global_position = pt.origin + Vector3.UP * 0.02
	player.velocity = Vector3.ZERO
	var f := -boat.global_basis.z
	if player.motor:
		player.motor.face(Vector3(f.x, 0.0, f.z))


func _physics_process(_delta: float) -> void:
	if phase == &"" or boat == null or not is_instance_valid(boat):
		return
	_place_boat()
	_board()


func _process(_delta: float) -> void:
	if phase != &"" and camera and is_instance_valid(camera):
		_update_camera(_cam_t)


func _update_camera(t: float) -> void:
	if boat == null or not is_instance_valid(boat):
		return
	var bt := Transform3D(boat.base_transform.basis, boat.base_transform.origin)
	var from: Vector3
	var look: Vector3
	if phase == &"arrive":
		# behind and above: the destination harbor ahead of the bow
		var k := clampf(t / 2.0, 0.0, 1.0)
		from = bt * Vector3(lerpf(6.0, 3.5, k), lerpf(8.5, 6.5, k), lerpf(26.0, 21.0, k))
		look = bt * Vector3(0.0, 1.5, -42.0)
	else:
		# a slow three-quarter orbit off the starboard bow
		var a := deg_to_rad(lerpf(38.0, 62.0, clampf(t / 3.5, 0.0, 1.0)))
		var r := 19.0
		from = bt * Vector3(sin(a) * r, 5.2, -cos(a) * r * 0.35 + 6.0)
		look = bt * Vector3(0.0, 3.0, -2.0)
	camera.global_transform = Transform3D(Basis.IDENTITY, from).looking_at(look, Vector3.UP)


func _wait_content(timeout: float) -> void:
	if scene.content == null:
		return
	var t0 := Time.get_ticks_msec()
	await get_tree().process_frame
	while not scene.content.is_settled() and Time.get_ticks_msec() - t0 < int(timeout * 1000.0) and _valid():
		await get_tree().process_frame


func _end_interlude(from_id: StringName) -> void:
	phase = &""
	if boat and is_instance_valid(boat):
		boat.queue_free()
	boat = null
	var home_boat: FerryBoat = moored.get(from_id)
	if home_boat and is_instance_valid(home_boat):
		home_boat.visible = true
	if camera and is_instance_valid(camera):
		camera.queue_free()
	camera = null
	if _valid() and player.camera_rig:
		player.camera_rig.make_current()
		player.camera_rig.snap_behind(player)
	scene.overlay.hide_bars(0.0)
	scene.set_hud_visible(true, 0.6)
	Audio.set_ambience_layer(&"local", &"", 0.0, 2.0)


func _finish(kind: StringName, at: Transform3D) -> void:
	busy = false
	travels += 1
	last_kind = kind
	last_destination = at
	_set_docks_available(true)
	_pause_director(false)
	if _valid():
		scene.capture_mouse()
	travel_finished.emit(kind, at)
	if director:
		director.autosave()


## Cleans up after the scene started leaving mid-trip.
func _abort() -> bool:
	_end_interlude(&"")
	busy = false
	phase = &""
	_set_docks_available(true)
	_pause_director(false)
	if _valid():
		player.process_mode = Node.PROCESS_MODE_INHERIT
		player.exit_cinematic()
		scene.fader.set_amount(0.0)
		scene.fader.set_text("")
	return false


func _pause_director(on: bool) -> void:
	if director and is_instance_valid(director):
		director.active = not on and director.target != null


# --- fast travel -----------------------------------------------------------------------------------------

## Faded teleport to `xform` (map fast travel, quest warps). Waits for collision + content at
## the destination. opts: fade (s), text (shown on black), content_timeout (s), autosave (bool).
## Returns false if busy, dead or the scene is leaving.
func travel_to(xform: Transform3D, opts: Dictionary = {}) -> bool:
	if busy or not _valid() or not player.is_alive():
		return false
	busy = true
	pending_destination = xform
	travel_started.emit(&"fast", xform)
	_pause_director(true)
	await scene.fader.fade_out(float(opts.get("fade", 0.45)))
	if not _valid():
		return _abort()
	scene.fader.set_text(String(opts.get("text", "")))
	if player.get_state() == PlayerCharacter.State.MOUNTED:
		player.dismount()
	# Frozen while the destination streams in (the old ground may be released meanwhile).
	player.process_mode = Node.PROCESS_MODE_DISABLED
	scene.focus_marker.global_transform = xform
	scene.renderer.set_focus(scene.focus_marker)
	if scene.content:
		scene.content.set_focus(scene.focus_marker)
	await scene.wait_for_ground(xform.origin, 15.0)
	await _wait_content(float(opts.get("content_timeout", CONTENT_TIMEOUT)))
	if not _valid():
		return _abort()
	var x := scene.ground_transform(xform)
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.teleport(x)
	player.velocity = Vector3.ZERO
	scene.renderer.set_focus(player)
	if scene.content:
		scene.content.set_focus(player)
	for i in 2:
		await get_tree().physics_frame
	await get_tree().process_frame
	scene.fader.set_text("")
	await scene.fader.fade_in(0.55)
	busy = false
	travels += 1
	last_kind = &"fast"
	last_destination = x
	_pause_director(false)
	travel_finished.emit(&"fast", x)
	if opts.get("autosave", true) and director:
		director.autosave()
	return true
