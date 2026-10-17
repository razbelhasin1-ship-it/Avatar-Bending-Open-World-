extends RefCounted
## bughunt_world: the world fixes played in the REAL world scene with the real player, rendered
## (docs/qa/bughunt_world.md). PART=canal,gorge,tablet,dao (default all).
##
##   canal  the Water Tribe's ring canal: the player in the water against the 1.8 m wall (+ curb)
##          presses jump and climbs out onto the walkway (before the fix a swimmer could only climb
##          ledges ~0.5 m above the water: every canal of the city was a trap).
##   gorge  the gorge below the Thundering Steps falls pool, 15 m under the pool level: the player
##          stands and walks there (before the fix gameplay water came from the pool's bounding
##          circle, the player "swam" and was pulled up into the air towards the pool level).
##
## tools/playtest.sh bughunt_world_regressions <out> 960x540

const E := ElementDefs.Element
const CANAL_WATER := Vector3(-723.4, 12.95, -2583.0)
const CANAL_WALK := Vector3(-716.4, 16.1, -2583.0)
const GORGE := Vector3(3187.6, 96.1, -879.2)
const POOL := Vector3(3205.9, 111.5, -869.9)

var p: Playtest
var w: WorldScene
var pl: PlayerCharacter


func run(pt: Playtest) -> void:
	p = pt
	SaveSystem.save_dir = "user://saves_bughunt_world_regressions"
	DirAccess.make_dir_recursive_absolute(SaveSystem.save_dir)
	GameState.new_game(E.EARTH)
	GameState.intro_done = true
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": true, "element": E.EARTH, "skip_intro": true, "time_of_day": 11.0}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.is_ready and w.playing, 600.0)
	if not p.check(ok, "world ready %s" % str(w.load_report)):
		return
	pl = w.player
	pl.camera_rig.require_capture = false
	var d := EncounterDirector.instance()
	if d != null:
		d.spawn_radius = -1.0
	var parts := OS.get_environment("PART")
	if parts == "":
		parts = "canal,gorge,tablet,dao"
	if "canal" in parts:
		await _canal()
	if "gorge" in parts:
		await _gorge()
	if "tablet" in parts:
		await _tablet()
	if "dao" in parts:
		await _dao()


func _travel(xf: Transform3D) -> bool:
	var ok: bool = await w.travel.travel_to(xf, {"fade": 0.05, "autosave": false, "content_timeout": 12.0})
	await p.wait_game(1.0)
	return ok


func _canal() -> void:
	# stand on the canal walkway first (the city streams in), then step into the water
	if not p.check(await _travel(Transform3D(Basis(Vector3.UP, PI * 0.5), CANAL_WALK)), "travelled to the Water Tribe's ring canal"):
		return
	var level := WorldData.get_water_height(CANAL_WATER.x, CANAL_WATER.z)
	p.check(absf(level - 14.2) < 0.2, "the canal is gameplay water at its level (%.2f)" % level)
	pl.teleport(Transform3D(Basis(Vector3.UP, -PI * 0.5), CANAL_WATER))       # facing +x, the inner wall
	pl.camera_rig.set_yaw(-PI * 0.5)
	await p.wait_game(1.5)
	p.check(pl.motor.swimming, "swimming in the canal (y %.2f, depth %.2f)" % [pl.global_position.y, pl.motor.water_depth])
	await p.screenshot("regress_01_canal_swimming")
	# swim to the wall (like a player: until it stops us)
	Input.action_press(&"move_forward")
	var reach_fwd := -pl.global_basis.z
	reach_fwd.y = 0.0
	for i in 40:
		await p.wait_game(0.1)
		if pl.test_move(pl.global_transform, reach_fwd.normalized() * 0.5):
			break
	await p.wait_game(0.2)
	var before := pl.global_position
	# what the climb-out sees from here (PlayerMotor.try_swim_exit): wall ahead, head room, ledge
	var xf := pl.global_transform
	var fwd := -pl.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var lifts: Array[String] = []
	for hgt: float in [1.8, pl.motor.water_height + PlayerMotor.CLIMB_OUT_MAX - before.y]:
		lifts.append("%.2f: up %s, ahead %s" % [hgt, "blocked" if pl.test_move(xf, Vector3.UP * hgt) else "free",
			"blocked" if pl.test_move(xf.translated(Vector3.UP * hgt), fwd * 0.8) else "free"])
	p.note("canal: water %.2f, swimmer feet %.2f, wall ahead %s; lifts %s" % [pl.motor.water_height, before.y,
		pl.test_move(xf, fwd * 0.6), "; ".join(lifts)])
	await p.tap(&"jump", 0.08)
	await p.wait_game(1.6)
	Input.action_release(&"move_forward")
	await p.wait_game(0.6)
	var after := pl.global_position
	p.note("canal climb: from (%.1f, %.2f, %.1f) to (%.1f, %.2f, %.1f), %s" % [before.x, before.y, before.z, after.x, after.y, after.z, pl.get_state_name()])
	p.check(not pl.motor.swimming and pl.motor.on_floor and after.y > 15.8, "jump against the wall climbs out onto the walkway (y %.2f)" % after.y)
	pl.camera_rig.set_yaw(PI * 0.5)
	await p.wait_game(0.8)
	await p.screenshot("regress_02_canal_climbed_out")


func _gorge() -> void:
	var to_pool := atan2(-(POOL.x - GORGE.x), -(POOL.z - GORGE.z))
	if not p.check(await _travel(Transform3D(Basis(Vector3.UP, to_pool), GORGE)), "travelled to the gorge below the Thundering Steps pool"):
		return
	pl.camera_rig.set_yaw(to_pool)
	var g := pl.global_position
	await p.wait_game(2.0)
	var depth_read := WorldData.get_water_height(g.x, g.z)
	p.check(depth_read == -INF, "no gameplay water reported on the gorge floor (%.1f)" % depth_read)
	p.check(not pl.motor.swimming and pl.motor.on_floor, "standing, not swimming (%s, on floor %s)" % [pl.get_state_name(), pl.motor.on_floor])
	p.check(pl.global_position.y < g.y + 0.6, "stays on the ground (y %.2f, arrived at %.2f, pool level %.1f)" % [pl.global_position.y, g.y, POOL.y])
	await p.screenshot("regress_03_gorge_below_the_falls")
	Input.action_press(&"move_forward")
	await p.wait_game(1.2)
	Input.action_release(&"move_forward")
	await p.wait_game(0.4)
	p.check(not pl.motor.swimming and pl.global_position.y < POOL.y - 8.0, "walks along the gorge floor (y %.2f)" % pl.global_position.y)
	await p.screenshot("regress_04_gorge_walked")


## The Whistling Caves' cave mouth lies on the floor of the Hundred Winds falls pool; the tablet
## "at the cave mouth" was 3 m under water among the boulders - out of a swimmer's reach (3.7 m at
## the closest) and only readable from one boulder. It rests on the boulders over the mouth now:
## a player wading or swimming up to it reads it with interact.
func _tablet() -> void:
	var q := &"at_whistling_caves"
	Quests.reset_quest(q)
	if not p.check(Quests.start(q, {"silent": true}), "Whistling Caves started"):
		return
	var poi := WorldData.get_poi(q)
	var mouth: Vector3 = poi["position"]
	var tab := mouth + Vector3(2.5, 0, 2.5)
	var level := WorldData.get_water_height(tab.x, tab.z)
	tab.y = level
	if not p.check(await _travel(Transform3D(Basis(), Vector3(tab.x, level + 0.3, tab.z + 3.0))), "travelled to the falls pool"):
		return
	await p.wait_game(1.5)
	var props := w.props_root.get_node_or_null("QuestProps") as QuestProps
	if props:
		props.refresh()
	await p.wait_game(0.5)
	p.note("at the pool over the cave mouth: y %.1f, level %.1f, %s" % [pl.global_position.y, level, "swimming" if pl.motor.swimming else "wading on the rocks"])
	# swim / wade over to it like a player (steer at it until within 1.2 m; against the boulders,
	# jump: a swimmer climbs out onto them)
	var last := pl.global_position
	for i in 80:
		var d := Vector2(tab.x - pl.global_position.x, tab.z - pl.global_position.z)
		if d.length() < 1.2:
			break
		pl.camera_rig.set_yaw(atan2(-d.x, -d.y))
		Input.action_press(&"move_forward")
		await p.wait_game(0.1)
		if i % 8 == 7:
			if pl.global_position.distance_to(last) < 0.4:
				await p.tap(&"jump")
			last = pl.global_position
	Input.action_release(&"move_forward")
	await p.wait_game(0.4)
	await p.screenshot("regress_05_tablet_from_the_surface")
	await p.tap(&"interact")
	await p.wait_game(1.0)
	var tablet: Node3D = null
	if props:
		for n in props.live_props():
			if (n as QuestProps.QuestPropNode) and (n as QuestProps.QuestPropNode).quest_id == q:
				tablet = n
	p.check(QuestProps.is_taken(q, &"tablet", 0) or not Quests.is_objective_active(q, &"tablet"),
		"read the tablet (player %.1f m from the cave mouth, %s)" % [Vector2(pl.global_position.x - tab.x, pl.global_position.z - tab.z).length(),
		"swimming" if pl.motor.swimming else "wading / standing"])
	if tablet == null:
		p.note("the tablet prop was taken (gone)")
	Quests.reset_quest(q)


## Farmer Dao (Lost in the Millet) stood inside his farmhouse and was pushed out under the ground;
## his spot is in front of the house now: he stands on the ground, visible, and talks.
func _dao() -> void:
	var xf := NpcRegistry.placement(&"ek_dao")
	var front := xf.origin + (xf.basis * Vector3.FORWARD) * 2.5
	front.y = WorldData.get_height(front.x, front.z) + 0.1
	var to_dao := atan2(-(xf.origin.x - front.x), -(xf.origin.z - front.z))
	if not p.check(await _travel(Transform3D(Basis(Vector3.UP, to_dao), front)), "travelled to Farmer Dao"):
		return
	await p.wait_game(3.0)
	var npc := NpcRegistry.live_npc(&"ek_dao") as NpcCharacter
	if not p.check(npc != null, "Farmer Dao is there"):
		return
	var g := WorldData.get_height(npc.global_position.x, npc.global_position.z)
	p.check(absf(npc.global_position.y - g) < 0.5, "standing on the ground (y %.2f, ground %.2f)" % [npc.global_position.y, g])
	pl.camera_rig.set_yaw(to_dao)
	await p.wait_game(0.5)
	await p.screenshot("regress_06_farmer_dao")
	await p.tap(&"interact")
	await p.wait_game(1.5)
	# a conversation frames the camera: the player is in CINEMATIC while the dialogue box is up
	p.check(pl.get_state() in [PlayerCharacter.State.INTERACTING, PlayerCharacter.State.CINEMATIC], "interact talks to him (%s)" % pl.get_state_name())
	await p.screenshot("regress_07_farmer_dao_talks")
