class_name WorldScene
extends PlayableScene
## The open world (scenes/world/world.tscn, Router.WORLD). On top of PlayableScene's
## composition and loading sequence it runs:
## * new game: spawn at WorldData.get_spawn(element) at a flattering hour, ArrivalCinematic,
##   then control; GameState.intro_done + an immediate autosave so the journey exists;
## * continue (Router.params.new_game == false): restore GameState position / yaw / health /
##   time of day (abilities and element come from GameState through the player);
## * RegionDirector (regions, first-visit titles, regional audio, POI discovery, autosave on
##   region change), RespawnSystem (death -> nearest safe point at 50 %, fall net),
##   TravelSystem (ferries, travel_to), WorldSaveGuard (consistent saves), PauseMenu.
##
##   Router.goto(Router.WORLD, {"new_game": true, "element": ElementDefs.Element.FIRE})
##   var w := get_tree().get_first_node_in_group(&"world_scene") as WorldScene
##   await w.travel.travel_to(Transform3D(Basis(), Vector3(1200, 58, 360)))
##
## Extra options: skip_intro (bool) - no arrival cinematic.

## Control was handed to the player (after the arrival cinematic, or right away on continue).
signal gameplay_started

## Arrival hour per element: a flattering light for each home region's first view.
const ARRIVAL_HOUR := {
	ElementDefs.Element.AIR: 9.0,
	ElementDefs.Element.EARTH: 16.4,
	ElementDefs.Element.FIRE: 15.6,
	ElementDefs.Element.WATER: 8.6,
}

var region_director: RegionDirector
var respawn: RespawnSystem
var travel: TravelSystem
var arrival: ArrivalCinematic = null
var save_guard: WorldSaveGuard
## Control is with the player (false during loading and the arrival).
var playing := false


func _ready() -> void:
	add_to_group(&"world_scene")
	super._ready()


func _configure() -> void:
	is_tutorial = false
	var e := int(options.get("element", ElementDefs.Element.NONE))
	if GameState.has_element():
		e = GameState.element          # the journey's element wins over params
	element = e
	if GameState.has_element() and GameState.is_tutorial:
		# Entering the world straight from the training grounds: a fresh journey.
		GameState.new_game(element)
	GameState.is_tutorial = false
	new_game = bool(options.get("new_game", not GameState.player_position.is_finite()))
	if new_game and not options.has("time_of_day") and ARRIVAL_HOUR.has(element) and not GameState.intro_done:
		GameState.time_of_day = float(ARRIVAL_HOUR[element])


func _spawn_transform() -> Transform3D:
	if not new_game and GameState.player_position.is_finite():
		return Transform3D(Basis(Vector3.UP, GameState.player_yaw), GameState.player_position)
	return WorldData.get_spawn(element)


func _loading_text() -> String:
	if new_game:
		return "Journeying to %s" % String(ElementDefs.get_data(element).get("home_name", "the world"))
	var r := GameState.region if GameState.region != &"" else StringName(ElementDefs.get_data(element).get("home_region", &""))
	return "Returning to %s" % TitleCard.region_title(r)


func _before_spawn(_spawn: Transform3D) -> void:
	region_director = RegionDirector.new()
	region_director.name = "RegionDirector"
	add_child(region_director)
	respawn = RespawnSystem.new()
	respawn.name = "RespawnSystem"
	add_child(respawn)
	travel = TravelSystem.new()
	travel.name = "TravelSystem"
	add_child(travel)
	travel.scene = self
	travel.build_docks(props_root)
	pause_menu = (load(PAUSE_SCENE) as PackedScene).instantiate() as PauseMenu
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.process_mode = Node.PROCESS_MODE_DISABLED   # enabled once playing


func _after_spawn() -> void:
	if not new_game:
		player.health.health = player.health.max_health * clampf(GameState.player_health_ratio, 0.05, 1.0)
		player.health.changed.emit(player.health.health, player.health.max_health)
	hud.region_titles = false
	region_director.target = player
	region_director.hud = hud
	region_director.title_card = title_card
	region_director.can_autosave = can_autosave
	respawn.setup(self, player)
	travel.setup(self, player)
	travel.director = region_director
	save_guard = WorldSaveGuard.new(self)
	add_child(save_guard)


func _prepare_first_frame() -> void:
	if new_game and not GameState.intro_done and not bool(options.get("skip_intro", false)):
		arrival = ArrivalCinematic.new()
		arrival.name = "ArrivalCinematic"
		add_child(arrival)
		arrival.prepare(self)
	else:
		super._prepare_first_frame()
		set_hud_visible(true, 0.0)


func _play() -> void:
	Events.game_started.emit(element, new_game)
	Events.world_ready.emit()
	if arrival:
		arrival.finished.connect(_on_arrival_finished, CONNECT_ONE_SHOT)
		arrival.play()
	else:
		_begin_gameplay(false)


func _on_arrival_finished(_skipped: bool) -> void:
	GameState.intro_done = true
	if is_instance_valid(arrival):
		arrival.queue_free()
	arrival = null
	_begin_gameplay(true)


func _begin_gameplay(after_intro: bool) -> void:
	if is_exiting():
		return
	playing = true
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	if player.get_state() == PlayerCharacter.State.CINEMATIC:
		player.exit_cinematic()
	if not hud.visible:
		set_hud_visible(true, 0.6)
	capture_mouse()
	var here := WorldData.get_region(player.global_position.x, player.global_position.z)
	region_director.start(here, true)
	if after_intro:
		region_director.autosave()
	else:
		Events.notify.emit("Journey resumed  ·  %s" % TitleCard.region_title(region_director.current_region), &"info")
	gameplay_started.emit()
	WorldHooks.call_all(hooks, &"world_ready")


## Automatic saves only while playing normally (never mid-cinematic, dead or travelling).
func can_autosave() -> bool:
	if not playing or is_exiting() or player == null or not is_instance_valid(player):
		return false
	if travel and travel.busy:
		return false
	if respawn and respawn.busy:
		return false
	return player.is_alive() and player.get_state() != PlayerCharacter.State.CINEMATIC
