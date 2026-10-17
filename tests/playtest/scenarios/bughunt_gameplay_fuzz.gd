extends RefCounted
## bughunt_gameplay: long randomized play per element, through InputMap actions only, with a
## watchdog of gameplay invariants and an engine-error collector (every error / warning is a
## bug). Two arenas:
##   MODE=arena  the enemy arena (flat courtyard, pool, snow, ice, walls) with rotating enemy
##               groups and the element's companion;
##   MODE=world  the real world next to an encounter site near the element's home, enemies
##               topped up through the EncounterDirector, the companion from the world hook,
##               the Journey Book and saves in odd states.
## The monkey presses / holds every combat action, techniques (rotated through the element's
## whole tree), the signature, lock-on, jump / glide, mount / dismount / call, the pause menu
## and the Journey Book; adversarial events add near-death, swims, dismounts over water and
## next to walls, saves mid-action, focus refills and chi starvation.
##
## Env: ELEMENT=air|earth|fire|water|all (default all), MODE=arena|world (default arena),
##      MINUTES=<game minutes per element> (default 5), SEED=<int>, SHOT_EVERY=<game s> (60).
## Headless + fast:  godot --headless --fixed-fps 60 --path . res://tests/playtest/playtest.tscn \
##                   -- --test --scenario=bughunt_gameplay_fuzz
## Rendered (screenshots): tools/playtest.sh bughunt_gameplay_fuzz <out> 960x540

const U := preload("res://tests/playtest/scenarios/bughunt_gameplay_util.gd")
const E := ElementDefs.Element
const DT := 1.0 / 60.0
const ARENA_GROUPS: Array = [
	[&"bandit_brawler", &"bandit_skirmisher", &"bandit_archer"],
	[&"fire_soldier", &"fire_shieldbearer", &"fire_archer"],
	[&"earth_rogue", &"dai_li_agent"],
	[&"water_pirate", &"pirate_cutlass", &"pirate_archer"],
	[&"air_renegade", &"bandit_brawler"],
	[&"fire_captain"],
	[&"earth_chief"],
	[&"komodo_rhino"],
]
const COMPANION_OF := {E.AIR: &"sky_bison", E.EARTH: &"badgermole", E.FIRE: &"dragon", E.WATER: &"polar_bear_dog"}

var p: Playtest
var rng := RandomNumberGenerator.new()
var errlog: Object
var mode := "arena"
var minutes := 5.0
var shot_every := 60.0
var summary: Array[String] = []


func run(pt: Playtest) -> void:
	p = pt
	mode = OS.get_environment("MODE") if OS.get_environment("MODE") != "" else "arena"
	minutes = float(OS.get_environment("MINUTES")) if OS.get_environment("MINUTES") != "" else 5.0
	shot_every = float(OS.get_environment("SHOT_EVERY")) if OS.get_environment("SHOT_EVERY") != "" else 60.0
	var seed_v := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 4242
	var which := OS.get_environment("ELEMENT")
	var elements: Array = [E.AIR, E.EARTH, E.FIRE, E.WATER]
	if which != "" and which != "all":
		elements = []
		for s in which.split(","):
			elements.append(ElementDefs.from_id(StringName(s)))
	errlog = U.ErrorLog.install()
	for e: int in elements:
		rng.seed = seed_v + e * 101
		if mode == "world":
			await _world(e)
		else:
			await _arena(e)
	p.note("==== SUMMARY ====")
	for s in summary:
		p.note(s)
	errlog.call("uninstall")


# --- shared --------------------------------------------------------------------------------------------

func _techniques(e: int) -> Array[AbilityDef]:
	var out: Array[AbilityDef] = []
	for d in AbilityRegistry.for_element(e):
		if d.slot == AbilityDef.Slot.TECHNIQUE and not d.script_path.is_empty():
			out.append(d)
	return out


## Everything learned; four random techniques equipped through GameState (the real reload path).
func _learn_all(e: int) -> void:
	for d in AbilityRegistry.for_element(e):
		if d.slot == AbilityDef.Slot.TECHNIQUE or d.slot == AbilityDef.Slot.SIGNATURE:
			GameState.unlock_ability(d.id, false)
	_rotate(e)


func _rotate(e: int) -> void:
	var t := _techniques(e)
	t.shuffle()
	for i in 4:
		GameState.equip_ability(i, t[i % t.size()].id if not t.is_empty() else &"")


func _shot(tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await p.screenshot(tag)


func _finish_element(tag: String, pl: PlayerCharacter, watch: Object, monkey: Object) -> void:
	monkey.call("release_all")
	p.release_all()
	# Queued input events (a last pause / map press) are handled first, then every menu closed
	# through its own API and the rider helped down.
	await p.frames(3)
	for n: Node in p.get_tree().get_nodes_in_group(&"journey_book"):
		if bool(n.get("is_open")):
			n.call("close")
	for n: Node in p.get_tree().root.find_children("*", "PauseMenu", true, false):
		if bool(n.get("is_open")):
			n.call("resume")
	await p.frames(2)
	if pl.get_tree().paused:
		pl.get_tree().paused = false
	if pl.get_state() == PlayerCharacter.State.MOUNTED and pl.mount_node != null and pl.mount_node.has_method("request_dismount"):
		pl.mount_node.call("request_dismount")
	# Settle with no input: everything must come back to rest by itself.
	var back := false
	for i in int(14.0 * 60.0):
		await p.get_tree().physics_frame
		watch.call("tick", DT)
		if pl.get_state() == PlayerCharacter.State.LOCOMOTION and not pl.controller.is_busy() and i > 120:
			back = true
			break
		# Still riding (the mount was burrowing / landing when asked): ask again.
		if i % 60 == 30 and pl.get_state() == PlayerCharacter.State.MOUNTED and pl.mount_node != null and pl.mount_node.has_method("request_dismount"):
			pl.mount_node.call("request_dismount")
	var live_proj := 0
	for pr in BendingProjectile.live:
		if is_instance_valid(pr) and pr.alive:
			live_proj += 1
	p.check(back, "%s: player back in Locomotion after the fuzz (%s)" % [tag, pl.get_state_name()])
	p.check(not pl.controller.is_busy(), "%s: no ability left running" % tag)
	p.check(Engine.time_scale == 1.0, "%s: time scale restored (%.3f)" % [tag, Engine.time_scale])
	p.check(not pl.get_tree().paused, "%s: tree not paused" % tag)
	var w: Dictionary = watch.get("violations")
	var rep: String = watch.call("report")
	if not w.is_empty():
		p.note("%s violations:\n%s" % [tag, rep])
	p.check(w.is_empty(), "%s: no invariant violations (%s)" % [tag, ", ".join(w.keys())])
	var states: Dictionary = watch.get("states_seen")
	var abil: Dictionary = watch.get("abilities_seen")
	var line := "%s: %.0f s game, states %s, abilities %d (%s), hits landed %d, taken %d, deaths %d, mounts %d, max proj %d, constructs %d, fx %d, enemies %d, live proj at end %d, inputs %s, nodes %s" % [
		tag, float(watch.get("clock")), str(states.keys()), abil.size(), ", ".join(abil.keys().map(func(k: StringName) -> String: return String(k))),
		int(watch.get("hits_landed")), int(watch.get("hits_taken")), int(watch.get("deaths")), int(watch.get("mounts")),
		int(watch.get("max_live_projectiles")), int(watch.get("max_live_constructs")), int(watch.get("max_fx_alive")), int(watch.get("max_enemies")),
		live_proj, str(monkey.get("counts")), str(watch.get("node_samples"))]
	summary.append(line)
	p.note(line)
	var errs: Array = errlog.get("errors")
	var warns: Array = errlog.get("warnings")
	if not errs.is_empty() or not warns.is_empty():
		p.note("%s engine errors/warnings so far:\n%s" % [tag, errlog.call("report")])
		for s: String in errs.slice(0, 6):
			p.note("ERROR " + s)
		for s: String in warns.slice(0, 6):
			p.note("WARN " + s)
	p.check(errs.is_empty(), "%s: no engine errors (%d)" % [tag, errs.size()])
	p.check(warns.is_empty(), "%s: no engine warnings (%d)" % [tag, warns.size()])
	watch.call("stop")
	(errlog.get("errors") as Array).clear()
	(errlog.get("warnings") as Array).clear()
	(errlog.get("counts") as Dictionary).clear()


func _diag(tag: String, t: float, pl: PlayerCharacter) -> void:
	var best := INF
	var st := ""
	for e: Node in p.get_tree().get_nodes_in_group(&"enemy"):
		var en := e as EnemyBase
		if en != null and en.is_alive():
			var d := en.global_position.distance_to(pl.global_position)
			if d < best:
				best = d
				st = en.get_state_name()
	var c := pl.get_companion() as Companion
	p.note("%s t=%.0f %s pos=%s nearest enemy %.1f m (%s) lock=%s companion=%s %.1f m" % [tag, t, pl.get_state_name(),
			str(pl.global_position.snapped(Vector3.ONE * 0.1)), best, st, str(pl.get_lock_target() != null),
			c.get_mode_name() if c else "-", c.global_position.distance_to(pl.global_position) if c else -1.0])


# --- arena ---------------------------------------------------------------------------------------------

func _arena(e: int) -> void:
	var tag := "arena_%s" % ElementDefs.id_of(e)
	p.note("---- %s (%.1f min) ----" % [tag, minutes])
	GameState.new_game(e)
	GameState.intro_done = true
	var arena: Node = await p.load_scene("res://scenes/dev/enemy_arena.tscn", {"element": e, "spawn": false})
	await p.wait_game(0.4)
	var pl: PlayerCharacter = arena.get("player")
	pl.camera_rig.require_capture = false
	_learn_all(e)
	await p.wait_game(0.1)
	var c := Companion.create(COMPANION_OF[e])
	c.player = pl
	arena.add_child(c)
	c.motor.teleport(pl.global_position + Vector3(-4.0, 0.0, 2.0), pl.rotation.y)
	c.rig.reset_feet()
	pl.companion = c
	var watch: Object = U.Watch.new(p.get_tree(), pl)
	watch.set("floor_y", -2.6)
	watch.set("companion", c)
	var monkey: Object = U.Monkey.new(p, pl, rng)
	monkey.set("allow_ui", false)   # no Journey Book in the arena; the pause menu is
	var total := minutes * 60.0
	var t := 0.0
	var next_group := 0.0
	var next_rotate := 25.0
	var next_event := 12.0
	var next_shot := 3.0
	while t < total:
		await p.get_tree().physics_frame
		if pl.get_tree().paused:
			# The pause menu: the monkey closes it again (its own deadline) - keep its clock running.
			monkey.call("step", DT)
			watch.call("tick", 0.0)
			continue
		t += DT
		monkey.call("step", DT)
		watch.call("tick", DT)
		if t >= next_group:
			next_group = t + 3.0
			var alive := 0
			for v: Variant in arena.get("enemies"):
				if is_instance_valid(v) and (v as EnemyBase).is_alive() and not (v as EnemyBase).surrendered:
					alive += 1
			if alive < 2:
				var g: Array = ARENA_GROUPS[rng.randi() % ARENA_GROUPS.size()]
				var spots: Array = []
				for i in g.size():
					var a := rng.randf() * TAU
					var q := pl.global_position + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(7.0, 13.0)
					spots.append(Vector3(clampf(q.x, -20.0, 20.0), 0.0, clampf(q.z, -25.0, 20.0)))
				arena.call("spawn_group", g, spots)
		if t >= next_rotate:
			next_rotate = t + rng.randf_range(15.0, 35.0)
			_rotate(e)
		if t >= next_event:
			next_event = t + rng.randf_range(6.0, 18.0)
			_arena_event(arena, pl, c, e)
		if t >= next_shot:
			next_shot = t + shot_every
			await _shot("%s_%03d" % [tag, int(t)])
		if int((t - DT) / 10.0) != int(t / 10.0):
			_diag(tag, t, pl)
		# The dev arena's floor ends at +-60 m (no fall net there): bring a wanderer back.
		if pl.get_state() != PlayerCharacter.State.MOUNTED and (absf(pl.global_position.x) > 45.0 or absf(pl.global_position.z) > 45.0):
			pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 4)))
			p.note("%s: wandered off the arena, back to the start" % tag)
		if c.global_position.y < -20.0 or absf(c.global_position.x) > 55.0 or absf(c.global_position.z) > 55.0:
			c.motor.teleport(pl.global_position + Vector3(-3.0, 0.5, 2.0), 0.0)
		# Keep fights going: an occasional heal, but deaths are allowed (the arena respawns).
		if pl.is_alive() and pl.health.health < pl.health.max_health * 0.2 and rng.randf() < 0.002:
			pl.health.heal(pl.health.max_health * 0.5)
	await _shot("%s_end" % tag)
	await _finish_element(tag, pl, watch, monkey)
	arena.call("clear_enemies")
	c.queue_free()
	await p.frames(2)


func _arena_event(arena: Node, pl: PlayerCharacter, c: Companion, e: int) -> void:
	var k := rng.randi() % 11
	match k:
		9, 10:
			# Walk up to the companion and get on (then the monkey rides / hops off).
			if not c.is_ridden() and pl.states.is_free() and pl.is_alive() and not c.is_airborne():
				var side := Vector3(cos(c.motor.yaw), 0.0, -sin(c.motor.yaw))
				pl.teleport(Transform3D(Basis.IDENTITY, c.global_position + side * (c.prof.radius() + 1.2) + Vector3.UP * 0.2))
				await p.wait_game(0.1)
				var can := c.can_mount(pl)
				p.hold(&"mount")
				await p.wait_game(0.05)
				p.release(&"mount")
				await p.wait_game(0.05)
				p.note("mount attempt: can_mount=%s state=%s companion=%s -> %s" % [can, pl.get_state_name(), c.get_mode_name(), pl.get_state_name()])
		0:
			# Near death: the next blow kills (death while an ability / mount / guard runs).
			if pl.is_alive():
				pl.health.health = 1.0
				pl.health.changed.emit(pl.health.health, pl.health.max_health)
		1:
			# Into the pool (swimming with buffered presses, water sources for Water).
			if pl.get_state() != PlayerCharacter.State.MOUNTED:
				pl.teleport(Transform3D(Basis.IDENTITY, Vector3(12.5, -0.5, -0.5)))
		2:
			pl.resources.mark_combat()
			pl.resources.set_focus(100.0)
		3:
			# Save in whatever state we are in (mid-action, mounted, dead, airborne).
			SaveSystem.save_game(3)
			var d := SaveSystem.read_slot(3)
			if d.is_empty():
				p.check(false, "save slot 3 readable after a save in state %s" % pl.get_state_name())
		4:
			# The companion over the pool / beside the wall, then mount + dismount there.
			var spots := [Vector3(12.5, 0.0, -0.5), Vector3(22.6, 0.0, -4.0), Vector3(-22.6, 0.0, 6.0), Vector3(0.0, 0.0, -27.6)]
			var q: Vector3 = spots[rng.randi() % spots.size()]
			if not c.is_ridden() and pl.get_state() != PlayerCharacter.State.MOUNTED:
				c.motor.teleport(q, rng.randf() * TAU)
				c.rig.reset_feet()
				if pl.is_alive():
					pl.teleport(Transform3D(Basis.IDENTITY, q + Vector3(1.5, 0.3, 1.5)))
		5:
			pl.resources.set_chi(rng.randf_range(0.0, 12.0))
		6:
			pl.resources.infinite_chi = not pl.resources.infinite_chi
		7:
			# A cheap shot from behind while busy (reaction during any state).
			if pl.is_alive():
				var h := HitInfo.make(rng.randf_range(4.0, 14.0), null, E.FIRE, [HitInfo.Reaction.FLINCH, HitInfo.Reaction.STAGGER,
						HitInfo.Reaction.KNOCKDOWN, HitInfo.Reaction.LAUNCH, HitInfo.Reaction.FREEZE, HitInfo.Reaction.PULL][rng.randi() % 6], pl.global_basis.z, 6.0)
				h.team = Combat.Team.ENEMY
				h.lift = 6.0
				h.stun_time = 0.6
				h.origin = pl.global_position - pl.global_basis.z * 3.0
				Combat.deal(pl, h)
		8:
			# Element hop in the middle of whatever is running (dev arenas allow it).
			if rng.randf() < 0.35:
				var ne: int = [E.AIR, E.EARTH, E.FIRE, E.WATER][rng.randi() % 4]
				arena.call("switch_element", ne)
				arena.call("switch_element", e)
				_learn_all(e)


# --- world ---------------------------------------------------------------------------------------------

func _world(e: int) -> void:
	var tag := "world_%s" % ElementDefs.id_of(e)
	p.note("---- %s (%.1f min) ----" % [tag, minutes])
	GameState.new_game(e)
	GameState.intro_done = true
	GameState.time_of_day = 14.0
	var home := WorldData.get_spawn(e)
	var site: EncounterSite = null
	for s in EncounterSites.build_all():
		if s.kind == &"patrol":
			continue
		if site == null or s.center.distance_to(home.origin) < site.center.distance_to(home.origin):
			site = s
	var start := site.center + Vector3(24.0, 0.0, 12.0)
	start = WorldData.get_safe_ground(start)
	var to := site.center - start
	var w: WorldScene = await p.load_scene("res://scenes/world/world.tscn", {"new_game": false, "spawn": Transform3D(Basis(Vector3.UP, atan2(-to.x, -to.z)), start + Vector3.UP * 0.3)}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.playing, 300.0)
	p.check(ok, "%s world ready" % tag)
	if not ok:
		return
	var pl := w.player
	pl.camera_rig.require_capture = false
	_learn_all(e)
	await p.wait_game(1.0)
	var director := EncounterDirector.instance()
	var watch: Object = U.Watch.new(p.get_tree(), pl)
	watch.set("world_mode", true)
	var monkey: Object = U.Monkey.new(p, pl, rng)
	p.note("%s at site %s (%s), %.0f m from home" % [tag, site.id, site.kind, site.center.distance_to(home.origin)])
	var total := minutes * 60.0
	var t := 0.0
	var next_spawn := 2.0
	var next_rotate := 25.0
	var next_event := 15.0
	var next_shot := 5.0
	var archs := [&"bandit_brawler", &"bandit_skirmisher", &"bandit_archer", &"fire_soldier", &"earth_rogue", &"water_pirate", &"air_renegade",
			&"fire_shieldbearer", &"dai_li_agent", &"pirate_cutlass", &"komodo_rhino"]
	var spawned: Array[EnemyBase] = []
	while t < total:
		await p.get_tree().physics_frame
		if pl.get_tree().paused:
			monkey.call("step", DT)
			watch.call("tick", 0.0)
			continue
		t += DT
		monkey.call("step", DT)
		watch.call("tick", DT)
		if t >= next_spawn and director != null:
			next_spawn = t + 4.0
			var alive := 0
			for v: Variant in director.enemies:
				if is_instance_valid(v) and (v as EnemyBase).is_alive() and not (v as EnemyBase).surrendered \
						and (v as EnemyBase).global_position.distance_to(pl.global_position) < 40.0:
					alive += 1
			if alive < 2 and pl.get_state() != PlayerCharacter.State.MOUNTED:
				for i in rng.randi_range(1, 3):
					var a := rng.randf() * TAU
					var q := WorldData.get_safe_ground(pl.global_position + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(9.0, 15.0))
					var en := director.spawn_enemy(archs[rng.randi() % archs.size()], Transform3D(Basis(Vector3.UP, a), q))
					if en != null:
						spawned.append(en)
		if t >= next_rotate:
			next_rotate = t + rng.randf_range(15.0, 35.0)
			_rotate(e)
		if t >= next_event:
			next_event = t + rng.randf_range(8.0, 20.0)
			await _world_event(w, pl)
		if t >= next_shot:
			next_shot = t + shot_every
			await _shot("%s_%03d" % [tag, int(t)])
		if pl.is_alive() and pl.health.health < pl.health.max_health * 0.2 and rng.randf() < 0.002:
			pl.health.heal(pl.health.max_health * 0.5)
	await _shot("%s_end" % tag)
	await _finish_element(tag, pl, watch, monkey)


func _world_event(w: WorldScene, pl: PlayerCharacter) -> void:
	var k := rng.randi() % 7
	match k:
		0:
			if pl.is_alive():
				pl.health.health = 1.0
				pl.health.changed.emit(pl.health.health, pl.health.max_health)
		1:
			pl.resources.mark_combat()
			pl.resources.set_focus(100.0)
		2:
			# Save mid-whatever: the save must hold a finite, solid position near the ground.
			SaveSystem.save_game(2)
			var d := SaveSystem.read_slot(2)
			var v: Variant = d.get("player_position")
			var pos := Vector3(float(v[0]), float(v[1]), float(v[2])) if v is Array and (v as Array).size() == 3 else Vector3.INF
			var pos_ok := pos.is_finite() and absf(pos.y - WorldData.get_height(pos.x, pos.z)) < 40.0
			if not pos_ok:
				p.check(false, "save in state %s keeps a sane position (%s)" % [pl.get_state_name(), str(v)])
		3:
			pl.resources.set_chi(rng.randf_range(0.0, 12.0))
		4:
			# Call the companion from wherever it is.
			var c := pl.get_companion() as Companion
			if c != null:
				c.call_companion()
		5:
			if pl.is_alive():
				var h := HitInfo.make(rng.randf_range(4.0, 14.0), null, E.EARTH, [HitInfo.Reaction.STAGGER, HitInfo.Reaction.KNOCKDOWN,
						HitInfo.Reaction.LAUNCH, HitInfo.Reaction.FREEZE][rng.randi() % 4], pl.global_basis.z, 6.0)
				h.team = Combat.Team.ENEMY
				h.lift = 6.0
				h.origin = pl.global_position - pl.global_basis.z * 3.0
				Combat.deal(pl, h)
		6:
			pl.resources.infinite_chi = not pl.resources.infinite_chi
