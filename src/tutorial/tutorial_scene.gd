class_name TutorialScene
extends PlayableScene
## The training grounds (scenes/world/tutorial.tscn, Router.TUTORIAL): the chosen element's
## training site in the real world (TrainingGround: Ice Flats, Stonefist Training Yard, Flame
## Kata Grounds, Airball Courts) with post dummies, a humanoid sparring dummy and the sparring
## partner; TutorialDirector teaches every core action with device-aware prompts. Nothing is
## saved (GameState.is_tutorial). Completion offers ENTER THE WORLD (a new journey as this
## element) or the main menu.
##
##   Router.goto(Router.TUTORIAL, {"element": ElementDefs.Element.AIR})
## Extra options: none beyond PlayableScene's.

signal tutorial_finished(summary: Dictionary)

const HUMANOID_PRESET := {
	ElementDefs.Element.WATER: &"water_warrior", ElementDefs.Element.EARTH: &"earth_soldier",
	ElementDefs.Element.FIRE: &"fire_soldier", ElementDefs.Element.AIR: &"air_nomad",
}

var site: Dictionary = {}
var ground: TrainingGround
var director: TutorialDirector
var respawn: RespawnSystem
var prompt: TutorialPrompt
var dummies: Array[TrainingDummy] = []
var bot: SparringBot
var complete_screen: TutorialCompleteScreen
## Replaces Router.goto(path, params) when leaving (tests).
var route_override: Callable
var start_xform := Transform3D.IDENTITY


func _ready() -> void:
	add_to_group(&"tutorial_scene")
	super._ready()


func _configure() -> void:
	is_tutorial = true
	new_game = true
	var e := int(options.get("element", ElementDefs.Element.NONE))
	if not ElementDefs.is_valid(e):
		e = GameState.element if GameState.has_element() else ElementDefs.Element.WATER
	element = e
	if not GameState.is_tutorial or GameState.element != element:
		GameState.new_game(element, true)
	if not options.has("time_of_day"):
		GameState.time_of_day = float(WorldScene.ARRIVAL_HOUR.get(element, 10.0))
	site = TrainingGround.site(element)


func _spawn_transform() -> Transform3D:
	var arena: Transform3D = site["xform"]
	var p := arena * TrainingGround.START
	p.y = WorldData.get_height(p.x, p.z)
	start_xform = Transform3D(arena.basis, p)
	return start_xform


func _loading_text() -> String:
	return "Entering %s" % String(site.get("name", "the training grounds"))


func _before_spawn(_spawn: Transform3D) -> void:
	ground = TrainingGround.new(element, site["xform"])
	props_root.add_child(ground)
	if content:
		var c: Vector3 = (site["xform"] as Transform3D).origin
		content.add_exclusion(c, TrainingGround.RING + 4.0, ContentExclusions.TAG_ALL, 3.0)
		content.add_exclusion(ground.local(TrainingGround.PAVILION), 7.0, ContentExclusions.TAG_ALL, 2.0)
	pause_menu = (load(PAUSE_SCENE) as PackedScene).instantiate() as PauseMenu
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.process_mode = Node.PROCESS_MODE_DISABLED


func _after_spawn() -> void:
	# Targets appear only once the ground under them is solid.
	for p in TrainingGround.DUMMY_POSTS:
		await wait_for_ground(ground.local(p), 10.0)
	await wait_for_ground(ground.local(TrainingGround.DUMMY_HUMANOID), 10.0)
	await wait_for_ground(ground.local(TrainingGround.BOT), 10.0)
	if is_exiting():
		return
	for p in TrainingGround.DUMMY_POSTS:
		_add_dummy(p, &"post")
	var h := _add_dummy(TrainingGround.DUMMY_HUMANOID, &"humanoid")
	h.display_name = "Sparring Dummy"
	bot = SparringBot.new()
	bot.name = "SparringPartner"
	bot.active = false
	bot.damage = 5.0
	bot.preset = &"fire_soldier"
	bot.transform = ground.local_xform(TrainingGround.BOT, Vector3.BACK)
	props_root.add_child(bot)
	respawn = RespawnSystem.new()
	respawn.name = "RespawnSystem"
	add_child(respawn)
	respawn.setup(self, player)
	respawn.use_fixed = true
	respawn.fixed_point = start_xform
	respawn.health_ratio = 1.0
	respawn.leash_radius = TrainingGround.RING + 34.0
	respawn.leash_drop = 12.0
	var layer := CanvasLayer.new()
	layer.name = "TutorialLayer"
	layer.layer = 20
	add_child(layer)
	prompt = TutorialPrompt.new()
	prompt.name = "Prompt"
	layer.add_child(prompt)
	director = TutorialDirector.new()
	director.name = "TutorialDirector"
	add_child(director)
	director.setup(self, player, prompt, bot)
	director.finished.connect(_on_finished)
	hud.region_titles = false
	hud.compass.set_region(String(site.get("name", "")))


func _add_dummy(local_pos: Vector3, look: StringName) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.look = look
	if look == &"humanoid":
		d.preset = HUMANOID_PRESET.get(element, &"earth_soldier")
	d.transform = ground.local_xform(local_pos, Vector3.BACK)
	props_root.add_child(d)
	d.home = d.global_transform
	dummies.append(d)
	return d


func _prepare_first_frame() -> void:
	super._prepare_first_frame()
	set_hud_visible(true, 0.0)


func _play() -> void:
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	capture_mouse()
	Audio.play_music(&"music_tutorial", 1.5)
	var amb: StringName = SoundCatalog.REGION_AMBIENCE.get(StringName(site.get("region", &"")), &"")
	if amb != &"":
		Audio.set_ambience(amb, -3.0, 2.0)
	if site.get("region", &"") == &"air_temple":
		Audio.set_environment(&"temple", 1.0)
	Events.game_started.emit(element, true)
	Events.world_ready.emit()
	title_card.show_title(String(site.get("name", "Training Grounds")), "Training Grounds", element, 2.4)
	await wait_seconds(1.4)
	if is_exiting():
		return
	director.start()
	WorldHooks.call_all(hooks, &"world_ready")


func _on_finished(summary: Dictionary) -> void:
	tutorial_finished.emit(summary)
	await wait_seconds(1.0)
	if is_exiting():
		return
	if player:
		player.enter_cinematic(600.0)
	release_mouse()
	complete_screen = TutorialCompleteScreen.new()
	complete_screen.name = "CompleteScreen"
	add_child(complete_screen)
	complete_screen.enter_world.connect(enter_world)
	complete_screen.main_menu.connect(to_main_menu)
	complete_screen.show_summary(element, summary)


## Leaves the training grounds for a brand new journey as this element.
func enter_world() -> void:
	GameState.new_game(element)
	_route(Router.WORLD, {"new_game": true, "element": element})


func to_main_menu() -> void:
	if route_override.is_valid():
		route_override.call(Router.MAIN_MENU, {})
		return
	Router.goto_main_menu()


func _route(path: String, params: Dictionary) -> void:
	if route_override.is_valid():
		route_override.call(path, params)
		return
	Router.goto(path, params)
