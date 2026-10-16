class_name EncounterDirector
extends Node
## Runs encounters around the player (docs/modules/enemies.md "Encounters"):
##
## * Sites (EncounterSites): hostile camps at WorldData camp POIs, authored outposts
##   near the home regions (built by EncounterProvider through WorldContent), patrol
##   routes on roads and beast dens. A site spawns its members when the player comes
##   within `spawn_radius` (nearest sites first, within the active-enemy budget of
##   Settings.detail_level()) and despawns them beyond `despawn_radius` when calm.
##   Dead members stay dead until the site respawns (`respawn_time`, never in view);
##   cleared camps are remembered in GameState.world_flags["encounters"].
## * Cheap far simulation: calm enemies beyond `sim_radius` go dormant (no physics /
##   AI / animation); far patrols keep walking kinematically along their route.
## * Combat state: Events.combat_state_changed(true) when the first enemy engages the
##   player, false 2.5 s after the last one stops (music).
## * Rewards: enemies pay XP + loot themselves (EnemyRewards); a cleared camp adds a
##   bonus, a toast and the cleared flag.
##
##   var d := EncounterDirector.new(); add_child(d); d.setup(player)     # world
##   var e := d.spawn_enemy(&"bandit_archer", xform)                      # arenas, quests

signal combat_changed(in_combat: bool)
signal site_activated(site: EncounterSite)
signal site_cleared(site: EncounterSite)
signal enemy_spawned(enemy: EnemyBase)

const COMBAT_EXIT_DELAY := 2.5
const BUDGET := [7, 11, 15, 20]
const FLAG_KEY := "encounters"

## Build the world sites from WorldData (false: arenas / tests drive it by hand).
var use_world_sites := true
var spawn_radius := 110.0
var despawn_radius := 150.0
var sim_radius := 70.0
var player: Node3D = null
var sites: Array[EncounterSite] = []
var enemies: Array[EnemyBase] = []
var in_combat := false
## Container for enemy nodes (defaults to this node).
var enemy_root: Node = null
## Multiplier on site respawn times (tests).
var respawn_scale := 1.0

var _combat_off := -1.0
var _site_t := 0.0
var _site_cursor := 0
var _sim_t := 0.0

static var _instance: WeakRef = null


static func instance() -> EncounterDirector:
	return _instance.get_ref() as EncounterDirector if _instance != null else null


func _ready() -> void:
	_instance = weakref(self)
	if enemy_root == null:
		enemy_root = self
	_configure()
	Events.graphics_settings_changed.connect(_configure)
	Events.player_spawned.connect(func(p: Node3D) -> void: player = p)
	if use_world_sites and sites.is_empty():
		sites = EncounterSites.build_all()
		_load_flags()


func _exit_tree() -> void:
	if in_combat:
		Events.combat_state_changed.emit(false)
		in_combat = false
	AttackTokens.reset()


func setup(p_player: Node3D) -> void:
	player = p_player


func _configure() -> void:
	var lvl := Settings.detail_level()
	spawn_radius = [85.0, 100.0, 110.0, 130.0][lvl]
	despawn_radius = spawn_radius + 40.0
	sim_radius = [45.0, 60.0, 70.0, 85.0][lvl]


func budget() -> int:
	return int(BUDGET[Settings.detail_level()])


func active_count() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.is_alive():
			n += 1
	return n


# --- spawning -----------------------------------------------------------------------------------------

## Creates an enemy of `archetype` at `xform` and starts tracking it.
func spawn_enemy(archetype: StringName, xform: Transform3D, opts: Dictionary = {}) -> EnemyBase:
	var o := opts.duplicate()
	o["home"] = xform
	var e := EnemyBase.create(archetype, o)
	enemy_root.add_child(e)
	adopt(e)
	return e


## Tracks an enemy created elsewhere (quests, scripted scenes).
func adopt(e: EnemyBase) -> void:
	if enemies.has(e):
		return
	enemies.append(e)
	e.despawn_ready.connect(_on_despawn_ready)
	e.defeated.connect(_on_defeated)
	enemy_spawned.emit(e)


func _on_despawn_ready(e: EnemyBase) -> void:
	enemies.erase(e)
	var site := _site_of(e)
	if site:
		site.forget_node(e)
	if is_instance_valid(e):
		e.queue_free()


func _on_defeated(e: EnemyBase, _how: StringName) -> void:
	var site := _site_of(e)
	if site == null:
		return
	site.mark_defeated(e)
	if site.is_cleared():
		_clear_site(site)


func _site_of(e: EnemyBase) -> EncounterSite:
	if e == null or e.site_id == &"":
		return null
	for s in sites:
		if s.id == e.site_id:
			return s
	return null


# --- main loop ----------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(&"player") as Node3D
	_update_combat(delta)
	_sim_t -= delta
	if _sim_t <= 0.0:
		_sim_t = 0.25
		_update_activity()
	if use_world_sites and player != null:
		_site_t -= delta
		if _site_t <= 0.0:
			_site_t = 0.5
			_update_sites()


func _update_combat(delta: float) -> void:
	var engaged := false
	if player != null and Combat.is_alive(player):
		for e in enemies:
			if is_instance_valid(e) and not e.dormant and e.in_combat() and e.global_position.distance_to(player.global_position) < 60.0:
				engaged = true
				break
	if engaged:
		_combat_off = -1.0
		if not in_combat:
			in_combat = true
			combat_changed.emit(true)
			Events.combat_state_changed.emit(true)
	elif in_combat:
		if _combat_off < 0.0:
			_combat_off = COMBAT_EXIT_DELAY
		_combat_off -= delta
		if _combat_off <= 0.0:
			in_combat = false
			_combat_off = -1.0
			combat_changed.emit(false)
			Events.combat_state_changed.emit(false)


## Dormancy: calm enemies far from the player stop simulating; anything engaged or
## close is fully awake.
func _update_activity() -> void:
	if player == null:
		return
	var pp := player.global_position
	for s in sites:
		if s.active and s.kind == &"patrol":
			s.advance_patrol(0.25)
	for e in enemies:
		if not is_instance_valid(e) or not e.is_alive():
			continue
		var d := e.global_position.distance_to(pp)
		var calm := not e.in_combat() and e.state in [EnemyBase.State.IDLE, EnemyBase.State.PATROL]
		var want := calm and d > sim_radius
		if want != e.dormant:
			e.dormant = want


func _update_sites() -> void:
	var pp := player.global_position
	var n := sites.size()
	if n == 0:
		return
	# Time-sliced: a handful of sites per update.
	var budget_left := budget() - active_count()
	var order: Array[EncounterSite] = []
	for i in mini(n, 8):
		order.append(sites[(_site_cursor + i) % n])
	_site_cursor = (_site_cursor + 8) % n
	for s in order:
		var d := s.distance_to(pp)
		if s.active:
			if d > despawn_radius and not s.any_engaged():
				s.deactivate(self)
		else:
			s.tick_respawn(GameState.play_time, respawn_scale, d > despawn_radius)
			if d < spawn_radius and s.alive_members() > 0 and budget_left > 0:
				budget_left -= s.activate(self)
				site_activated.emit(s)


func _clear_site(site: EncounterSite) -> void:
	site.cleared_at = GameState.play_time
	_save_flags()
	site_cleared.emit(site)
	if site.kind == &"camp" or site.kind == &"outpost":
		var bonus := 40 + 10 * site.members.size()
		if not GameState.is_tutorial:
			GameState.add_xp(bonus, "Cleared %s" % site.display_name)
			Events.notify.emit("%s cleared  ·  +%d XP" % [site.display_name, bonus], &"discovery")
			Audio.play_2d(&"quest_complete", -6.0)
		GameState.incr_stat("camps_cleared")


func _load_flags() -> void:
	var f: Dictionary = GameState.world_flags.get(FLAG_KEY, {})
	for s in sites:
		if f.has(String(s.id)):
			s.cleared_at = float(f[String(s.id)])
			s.mark_all_defeated()


func _save_flags() -> void:
	var f: Dictionary = {}
	for s in sites:
		if s.cleared_at >= 0.0:
			f[String(s.id)] = s.cleared_at
	GameState.world_flags[FLAG_KEY] = f


## Debug / tests: site by id.
func get_site(id: StringName) -> EncounterSite:
	for s in sites:
		if s.id == id:
			return s
	return null


func get_stats() -> Dictionary:
	var dormant := 0
	for e in enemies:
		if is_instance_valid(e) and e.dormant:
			dormant += 1
	var active_sites := 0
	for s in sites:
		if s.active:
			active_sites += 1
	return {"sites": sites.size(), "active_sites": active_sites, "enemies": active_count(), "dormant": dormant,
		"budget": budget(), "in_combat": in_combat}
