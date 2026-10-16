class_name RegionDirector
extends Node
## Tracks where the player is and makes the world react (docs/modules/worldscene.md):
## * region at the player (WorldData.get_region) with time hysteresis (a new region must be
##   reported continuously for `hold_time` s) -> GameState.region, Events.region_entered
##   (Audio switches the regional music/ambience bed, the HUD compass shows the name);
## * first visit of a region -> "Region Discovered" title card (persisted in
##   GameState.world_flags["visited_regions"]);
## * local audio from the ground under the player: city / temple / forest reverb and the
##   settlement ambience layer;
## * POI discovery inside a POI's radius -> GameState.discover_poi, title card, XP toast
##   (the HUD compass marks discovered vs undiscovered places itself);
## * autosave on every region change (through `autosave` so the world can veto it).

signal region_changed(region_id: StringName, previous: StringName)
signal poi_found(poi: Dictionary)

const FLAG_VISITED := "visited_regions"
## Seconds a different region must be reported before it becomes current.
const HOLD_TIME := 2.0
const SAMPLE_INTERVAL := 0.25
const POI_INTERVAL := 0.5
const AUDIO_INTERVAL := 1.0
## Extra discovery margin beyond a POI's radius (m), and the vertical tolerance.
const POI_MARGIN := 12.0
const POI_MAX_DY := 45.0
const XP_BY_TYPE := {
	&"landmark": 50, &"vista": 60, &"shrine": 40, &"ruin": 50, &"cave": 50, &"waterfall": 40,
	&"spirit_spot": 60, &"village": 40, &"dock": 25, &"training_ground": 40, &"camp": 30,
	&"resource": 30, &"bridge": 30,
}
const TYPE_LABEL := {
	&"landmark": "Landmark", &"vista": "Vista", &"shrine": "Shrine", &"ruin": "Ruins", &"cave": "Cave",
	&"waterfall": "Waterfall", &"spirit_spot": "Spirit Place", &"village": "Village", &"dock": "Harbor",
	&"training_ground": "Training Ground", &"camp": "Camp", &"resource": "Resource", &"bridge": "Bridge",
}

## The tracked body (the player). Anything Node3D works (tests use a marker).
var target: Node3D = null
var hud: Hud = null
var title_card: TitleCard = null
var active := false
var current_region: StringName = &""
## Region lookup (x, z) -> StringName; defaults to WorldData.get_region (tests inject one).
var region_provider: Callable = Callable()
## Veto for automatic saves: Callable() -> bool. Default: always allowed.
var can_autosave: Callable = Callable()
## When false, nothing is persisted (tutorial) and no autosave happens.
var persistent := true
var discover_pois := true
var saves_made := 0

var _candidate: StringName = &""
var _candidate_t := 0.0
var _sample_t := 0.0
var _poi_t := 0.0
var _audio_t := 0.0
var _audio_env: StringName = &""
var _audio_local: StringName = &""


## Begins tracking. `initial` (default GameState.region or the region at the target) becomes
## current immediately; `announce` shows its title card if it was never visited.
func start(initial: StringName = &"", announce: bool = false) -> void:
	active = true
	var r := initial
	if r == &"" and target and is_instance_valid(target):
		r = _region_at(target.global_position)
	if r == &"":
		r = GameState.region
	_enter(r, announce, false)


func stop() -> void:
	active = false


## Regions the player has visited (persisted in GameState.world_flags).
static func visited_regions() -> Array:
	var v: Variant = GameState.world_flags.get(FLAG_VISITED, [])
	return v if v is Array else []


static func mark_visited(region_id: StringName) -> bool:
	var v := visited_regions().duplicate()
	if v.has(String(region_id)):
		return false
	v.append(String(region_id))
	GameState.world_flags[FLAG_VISITED] = v
	return true


static func is_visited(region_id: StringName) -> bool:
	return visited_regions().has(String(region_id))


func _process(delta: float) -> void:
	if not active or target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var pos := target.global_position
	_sample_t -= delta
	if _sample_t <= 0.0:
		_sample_t = SAMPLE_INTERVAL
		step_region(_region_at(pos), SAMPLE_INTERVAL)
	_poi_t -= delta
	if _poi_t <= 0.0 and discover_pois:
		_poi_t = POI_INTERVAL
		check_pois(pos)
	_audio_t -= delta
	if _audio_t <= 0.0:
		_audio_t = AUDIO_INTERVAL
		_update_local_audio(pos)


## One hysteresis step with region `r` reported for `dt` seconds. Public for tests.
func step_region(r: StringName, dt: float) -> void:
	if r == current_region or r == &"":
		_candidate = &""
		_candidate_t = 0.0
		return
	if r != _candidate:
		_candidate = r
		_candidate_t = 0.0
	_candidate_t += dt
	if _candidate_t >= HOLD_TIME:
		_candidate = &""
		_candidate_t = 0.0
		_enter(r, true, true)


func _region_at(pos: Vector3) -> StringName:
	if region_provider.is_valid():
		return region_provider.call(pos.x, pos.z)
	return WorldData.get_region(pos.x, pos.z)


func _enter(r: StringName, announce: bool, save: bool) -> void:
	var prev := current_region
	current_region = r
	GameState.region = r
	var first := persistent and mark_visited(r)
	if first and announce:
		var tc := _title()
		if tc:
			tc.show_region(r)
	Events.region_entered.emit(r)
	region_changed.emit(r, prev)
	if save and prev != &"" and prev != r:
		autosave()


func _title() -> TitleCard:
	if title_card and is_instance_valid(title_card):
		return title_card
	return hud.title_card if hud else null


## Saves to the autosave slot unless the world vetoes it. Returns success.
func autosave() -> bool:
	if not persistent or not SaveSystem.can_save():
		return false
	if can_autosave.is_valid() and not bool(can_autosave.call()):
		return false
	var ok := SaveSystem.save_game(SaveSystem.AUTOSAVE_SLOT)
	if ok:
		saves_made += 1
	return ok


# --- POIs ------------------------------------------------------------------------------------------

## Discovers every undiscovered POI whose area contains `pos`. Returns how many.
func check_pois(pos: Vector3) -> int:
	if not persistent:
		return 0
	var found := 0
	for poi: Dictionary in WorldData.get_pois_in_radius(pos, 180.0):
		var id := StringName(poi.get("id", &""))
		if id == &"" or GameState.discovered_pois.has(String(id)):
			continue
		var pp: Vector3 = poi["position"]
		var d := Vector2(pp.x - pos.x, pp.z - pos.z).length()
		if d > float(poi.get("radius", 20.0)) + POI_MARGIN or absf(pp.y - pos.y) > POI_MAX_DY:
			continue
		if discover(poi):
			found += 1
	return found


## Marks a POI discovered: GameState, XP, title card + toast. False if already known.
func discover(poi: Dictionary) -> bool:
	var id := StringName(poi.get("id", &""))
	if not GameState.discover_poi(id):
		return false
	var type: StringName = StringName(poi.get("type", &"landmark"))
	var xp := int(XP_BY_TYPE.get(type, 30))
	var poi_name := String(poi.get("name", "Unknown place"))
	GameState.add_xp(xp, "discovery")
	GameState.incr_stat("places_discovered")
	var tc := _title()
	if tc:
		tc.show_title(poi_name, "%s Discovered" % TYPE_LABEL.get(type, "Place"), TitleCard.REGION_ELEMENT.get(StringName(poi.get("region", &"")), ElementDefs.Element.NONE), 2.2)
	Events.notify.emit("%s  ·  +%d XP" % [poi_name, xp], &"discovery")
	poi_found.emit(poi)
	return true


# --- local audio -------------------------------------------------------------------------------------

func _update_local_audio(pos: Vector3) -> void:
	var b := WorldData.get_biome(pos.x, pos.z)
	var env: StringName = &"open"
	var local: StringName = &""
	match b:
		WorldData.Biome.CITY:
			env = &"city"
			local = &"amb_city"
		WorldData.Biome.TEMPLE:
			env = &"temple"
			local = &"amb_temple"
		WorldData.Biome.FOREST:
			env = &"forest"
	if env != _audio_env:
		_audio_env = env
		Audio.set_environment(env, 2.0)
	if local != _audio_local:
		_audio_local = local
		Audio.set_ambience_layer(&"local", local, -4.0, 4.0)
