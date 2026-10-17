extends Node
## Progression UI world hook (installed by WorldHooks in the world scene, not in the training
## grounds): adds the Journey Book (skills / map / journal / inventory / character), the
## level-up banner, and keeps the map's knowledge current - places visited and the explored
## mask (MapModel.note_position at 1 Hz, discoveries reveal around the POI) - plus the
## companion bond record (CompanionBond).

const BOOK_SCENE := "res://scenes/ui/journey_book.tscn"

var scene: Node = null
var book: JourneyBook = null
var banner: LevelUpBanner = null
var player: Node3D = null

var _t := 0.0


func world_setup(p_scene: Node) -> void:
	scene = p_scene
	if bool(scene.get("is_tutorial")):
		return
	book = (load(BOOK_SCENE) as PackedScene).instantiate() as JourneyBook
	book.name = "JourneyBook"
	book.enabled = false
	scene.add_child(book)
	var layer := CanvasLayer.new()
	layer.name = "LevelUpLayer"
	layer.layer = 38
	scene.add_child(layer)
	banner = LevelUpBanner.new()
	banner.name = "LevelUpBanner"
	banner.book = book
	layer.add_child(banner)
	Events.poi_discovered.connect(_on_poi_discovered)


func player_spawned(p: Node3D) -> void:
	player = p
	if book != null and p != null:
		MapModel.ensure_seeded(p.global_position)


func world_ready() -> void:
	if book != null:
		book.enabled = true


func world_exit() -> void:
	if Events.poi_discovered.is_connected(_on_poi_discovered):
		Events.poi_discovered.disconnect(_on_poi_discovered)


func _process(delta: float) -> void:
	if book == null or player == null or not is_instance_valid(player):
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0
	MapModel.note_position(player.global_position)
	CompanionBond.sync()


func _on_poi_discovered(id: StringName) -> void:
	var p := WorldData.get_poi(id)
	if not p.is_empty():
		MapModel.reveal(p["position"], MapModel.POI_REVEAL_M)
