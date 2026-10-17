extends TestCase
## Wave-4 cross-module integration fixes (docs/qa/integration_fixes.md):
## * practice is counted exactly once per technique use, for every element (real player);
## * one level-up presentation (banner in the world, one HUD toast elsewhere);
## * DialogueBox reopened during its closing fade stays visible;
## * burn ticks hurt but never shake the camera;
## * new-game loadouts, the locked signature hint, lessons / rewards filling free slots,
##   signatures never filling a technique slot, the HUD following at once;
## * interior anchors face into their rooms (the -Z contract);
## * enemy benders cast the element techniques (archetype data + loadouts, air archetype);
## * world fires (settlement / outpost / POI braziers, torches, lanterns, campfires) react.

const E := ElementDefs.Element


func before_each() -> void:
	WorldData.use_flat_world(true)
	TimeDilation.enabled = false
	GroundSampler.clear_zones()
	BendingHits.clear_log()


func after_each() -> void:
	WorldData.use_flat_world(false)
	WorldData.clear_water_sources()
	GroundSampler.clear_zones()
	TimeDilation.enabled = true
	TimeDilation.clear()
	Engine.time_scale = 1.0
	for c in BendingConstruct.live.duplicate():
		if is_instance_valid(c):
			c.queue_free()
	BendingConstruct.live.clear()
	for p in BendingProjectile.live.duplicate():
		if is_instance_valid(p):
			p.queue_free()
	GameState.reset()


func _ground() -> void:
	PlayerSim.ground(self)


## Texts of the HUD toasts currently shown.
func _toast_texts(hud: Hud) -> Array:
	var out: Array = []
	for t in hud.toasts.get_children():
		if t.is_queued_for_deletion():
			continue
		var labels := t.find_children("*", "Label", true, false)
		if not labels.is_empty():
			out.append((labels.back() as Label).text)   # title (optional) then the text
	return out


func _until_idle(p: PlayerCharacter, max_frames: int = 600) -> void:
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), max_frames)


# --- 3. practice counted once ---------------------------------------------------------------------

## Every technique and signature of every element, cast once by the real player through its
## input action, adds exactly one practice to itself and none to anything else.
func test_practice_counted_exactly_once_per_use() -> void:
	_ground()
	var report: Array[String] = []
	for e: int in [E.AIR, E.EARTH, E.FIRE, E.WATER]:
		GameState.new_game(e)
		var p := PlayerSim.player(self, e, Vector3.ZERO)
		p.resources.infinite_chi = true
		var dummy := TrainingDummy.new()
		dummy.look = &"post"
		dummy.max_health = 9000.0
		add_child(dummy)
		dummy.global_position = Vector3(0, 0, -6.0)
		await PlayerSim.step(p, 3)
		for d in AbilityRegistry.for_element(e):
			if d.slot != AbilityDef.Slot.TECHNIQUE and d.slot != AbilityDef.Slot.SIGNATURE:
				continue
			if d.script_path.is_empty():
				continue
			p.teleport(Transform3D(Basis.IDENTITY, Vector3.ZERO))
			p.health.health = p.health.max_health * 0.5   # Healing Waters refuses at full health
			p.controller.reset_cooldowns()
			p.controller.cancel_current(&"test")
			var sig := d.slot == AbilityDef.Slot.SIGNATURE
			var slot := &"signature" if sig else &"technique_1"
			var action := &"ability_special" if sig else &"ability_1"
			p.controller.set_slot(slot, d)
			if sig:
				p.resources.add_focus(100.0)
			var before := GameState.ability_practice.duplicate()
			# hold for 1.8 s (charges / holds: lightning, jet, wave), then release
			p.input.press(action)
			await PlayerSim.step(p, 108)
			p.input.release(action)
			await PlayerSim.step(p, 2)
			# toggles (air scooter, earth armor) end on a second press of their slot
			if p.controller.is_busy() and p.controller.current.def == d:
				await PlayerSim.step(p, 30)
				if p.controller.is_busy() and p.controller.current.def == d:
					await PlayerSim.tap(p, action, 2)
			await _until_idle(p, 500)
			var got := int(GameState.ability_practice.get(String(d.id), 0)) - int(before.get(String(d.id), 0))
			var others := 0
			for k: Variant in GameState.ability_practice:
				if String(k) != String(d.id):
					others += int(GameState.ability_practice[k]) - int(before.get(k, 0))
			report.append("%s=%d%s" % [d.id, got, "" if others == 0 else " (+%d other)" % others])
			expect_eq(got, 1, "%s practice per use" % d.id)
			expect_eq(others, 0, "%s counts no other technique" % d.id)
			if sig:
				p.controller.set_slot(&"signature", null)
			await PlayerSim.step(p, 20)
		p.queue_free()
		dummy.queue_free()
		await frames(2)
	print("[integration_fixes] practice per use: ", ", ".join(report))


# --- 4. one level-up flow ---------------------------------------------------------------------------

func test_level_up_has_one_presentation() -> void:
	GameState.new_game(E.WATER)
	var toasts: Array = []
	var cb := func(text: String, _kind: StringName) -> void: toasts.append(text)
	Events.notify.connect(cb)
	# No HUD, no banner: GameState itself announces nothing (no duplicate toast source).
	GameState.add_xp(GameState.xp_for_level(1) + 5)
	await frames(2)
	expect_eq(GameState.level, 2, "levelled up")
	expect(toasts.is_empty(), "GameState emits no level-up toast: %s" % str(toasts))
	# HUD alone (dev arena): exactly one toast, even for two levels at once.
	var hud: Hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await frames(1)
	var n0 := _toast_texts(hud).size()
	GameState.add_xp(GameState.xp_for_level(2) + GameState.xp_for_level(3) + 5)
	await frames(2)
	expect_eq(GameState.level, 4, "two more levels")
	var shown := _toast_texts(hud)
	expect_eq(shown.size() - n0, 1, "one HUD toast for two levels: %s" % str(shown))
	expect(not shown.is_empty() and String(shown.back()).contains("Level 4"), "the toast names the highest level")
	expect(toasts.is_empty(), "still no Events.notify toast: %s" % str(toasts))
	# With the progression banner in the scene, the banner is the only presentation.
	var layer := CanvasLayer.new()
	add_child(layer)
	var banner := LevelUpBanner.new()
	layer.add_child(banner)
	await frames(1)
	var n1 := _toast_texts(hud).size()
	GameState.add_xp(GameState.xp_for_level(4) + 5)
	await frames(3)
	expect(banner.shown == 1 and banner.is_showing, "the banner shows the level-up")
	expect_eq(_toast_texts(hud).size(), n1, "no HUD toast while a banner exists")
	expect(toasts.is_empty(), "no Events.notify toast either: %s" % str(toasts))
	Events.notify.disconnect(cb)
	hud.queue_free()
	layer.queue_free()
	await frames(1)


# --- 6. DialogueBox fade race ----------------------------------------------------------------------

func test_dialogue_box_reopened_during_close_fade_stays_visible() -> void:
	var box := DialogueBox.new()
	add_child(box)
	await frames(1)
	box.open()
	await seconds(0.25)
	box.close()
	await frames(2)
	box.open()   # inside the 0.15 s closing fade
	await seconds(0.45)
	expect(box.is_open and box.visible, "box open and visible after reopening mid-fade")
	expect(box.modulate.a > 0.95, "box faded back in (alpha %.2f)" % box.modulate.a)
	box.close()
	await seconds(0.3)
	expect(not box.visible, "a normal close still hides it")
	box.queue_free()


# --- 8. onboarding: new-game loadout, locked signature, lessons / rewards -------------------------

## A NEW GAME per element: level 1, the starters on slots 1..n in order, the other slots
## empty, the signature locked with its level shown by the HUD, R explains it, nothing dead.
func test_new_game_loadout_per_element() -> void:
	_ground()
	var hud: Hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	for e: int in [E.AIR, E.EARTH, E.FIRE, E.WATER]:
		GameState.new_game(e)
		var p := PlayerSim.player(self, e, Vector3.ZERO)
		hud.bind_player(p)
		await PlayerSim.step(p, 2)
		await frames(2)
		var starters := AbilityRegistry.starter_techniques(e)
		expect(starters.size() >= 2 and starters.size() <= 3, "%s: 2-3 starter techniques (%d)" % [ElementDefs.id_of(e), starters.size()])
		expect_eq(GameState.level, 1, "level 1")
		for i in 4:
			var id := StringName(p.get_ability_slot_info(i).get("id", &""))
			if i < starters.size():
				expect_eq(id, starters[i], "%s slot %d holds a starter" % [ElementDefs.id_of(e), i + 1])
				expect(not hud.abilities.slot(i).is_empty(), "HUD slot %d shows it" % (i + 1))
			else:
				expect_eq(id, &"", "%s slot %d free" % [ElementDefs.id_of(e), i + 1])
		expect(p.get_ability_slot_info(4).is_empty(), "%s: no usable signature yet" % ElementDefs.id_of(e))
		var lk := p.get_locked_signature_info()
		var sig_def: AbilityDef = null
		for d in AbilityRegistry.for_element(e):
			if d.slot == AbilityDef.Slot.SIGNATURE:
				sig_def = d
		expect(sig_def != null and StringName(lk.get("id", &"")) == sig_def.id, "%s: locked signature named (%s)" % [ElementDefs.id_of(e), str(lk)])
		expect(int(lk.get("level", 0)) == int(sig_def.unlock.get("level", 1)), "lock shows the level it opens at")
		expect(hud.abilities.signature.is_locked(), "HUD signature slot drawn locked")
		# R on a locked signature: a clear reason (&"locked") and a HUD hint toast.
		hud._locked_hint_ms = -100000   # the hint is throttled to one per 4 s
		var n0 := _toast_texts(hud).size()
		await PlayerSim.tap(p, &"ability_special", 2)
		expect_eq(p.controller.last_failure, &"locked", "R reports locked")
		await frames(1)
		var t := _toast_texts(hud)
		expect(t.size() == n0 + 1 and String(t.back()).contains(sig_def.display_name) and String(t.back()).contains("level"),
				"HUD explains the locked signature: %s" % str(t))
		# Learn it: the signature button works at once and the lock is gone.
		GameState.unlock_ability(sig_def.id, false)
		await frames(2)
		expect_eq(StringName(p.get_ability_slot_info(4).get("id", &"")), sig_def.id, "signature usable right after learning")
		expect(p.get_locked_signature_info().is_empty(), "lock cleared")
		await frames(1)
		expect(not hud.abilities.signature.is_locked() and not hud.abilities.signature.is_empty(), "HUD signature slot updated")
		hud.bind_player(null)
		p.queue_free()
		await frames(2)
	hud.queue_free()


## Quest technique rewards and trainer lessons put techniques into the first free slot and
## the live player / HUD use them at once; a signature lesson never fills a technique slot
## (and an old save with one there is healed).
func test_lessons_and_rewards_fill_free_slots_and_hud_follows() -> void:
	_ground()
	GameState.new_game(E.FIRE)
	var p := PlayerSim.player(self, E.FIRE, Vector3.ZERO)
	var hud: Hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	hud.bind_player(p)
	await PlayerSim.step(p, 2)
	var starters := AbilityRegistry.starter_techniques(E.FIRE)
	# Opening-chain reward candidates (data/quests): the first one not learned yet is granted.
	var got := QuestRewards.unlock_first([&"fire_burst", &"fire_ring", &"jet_step"], "", false)
	expect_eq(got, &"fire_ring", "first unlearned candidate granted")
	await frames(2)
	var idx := starters.size()
	expect_eq(GameState.equipped_abilities[idx], &"fire_ring", "reward went to the first free slot (%d)" % (idx + 1))
	expect_eq(StringName(p.get_ability_slot_info(idx).get("id", &"")), &"fire_ring", "the live player can use it at once")
	await frames(1)
	expect_eq(StringName(hud.abilities.slot(idx).info.get("id", &"")), &"fire_ring", "HUD slot updated")
	expect(QuestRewards.slot_hint(&"fire_ring").contains("slot %d" % (idx + 1)), "toast says which slot")
	# Signature lesson (Master Jinzo teaches the Inferno): signature slot, not a technique slot.
	TrainerLessons.complete_lesson(&"fn_jinzo", &"inferno")
	await frames(2)
	expect(GameState.is_unlocked(&"inferno"), "inferno learned")
	expect(not GameState.equipped_abilities.has(&"inferno"), "signature not put in a technique slot: %s" % str(GameState.equipped_abilities))
	expect_eq(StringName(p.get_ability_slot_info(4).get("id", &"")), &"inferno", "on the signature button")
	# A technique lesson next still finds the last free slot.
	GameState.level = 9
	TrainerLessons.complete_lesson(&"fn_jinzo", &"jet_step")
	await frames(2)
	expect_eq(GameState.equipped_abilities[idx + 1], &"jet_step", "lesson technique in the next free slot")
	expect_eq(StringName(p.get_ability_slot_info(idx + 1).get("id", &"")), &"jet_step", "usable at once")
	# Old saves: a signature sitting in a technique slot is freed on load.
	GameState.equipped_abilities[idx + 1] = &"inferno"
	p.controller.load_equipped()
	expect_eq(GameState.equipped_abilities[idx + 1], &"", "dead signature slot healed")
	hud.queue_free()
	p.queue_free()


# --- 5. interior anchors face into their rooms (-Z contract) ---------------------------------------

## Every anchor inside an enterable interior (Water Tribe, Ba Sing Se, Fire Nation capital)
## faces into the room, not the wall behind it; the Flame Kata Grounds master faces his students
## and they face him. (A -Z-forward model with rotation `yaw`, as NpcCharacter places it.)
func test_interior_anchors_face_into_their_rooms() -> void:
	WorldData.use_flat_world(false)   # plans are cached for the run: build them on the real terrain
	var checked := 0
	for sid: StringName in [&"northern_water_tribe", &"ba_sing_se", &"fire_nation_capital"]:
		var plan := Settlements.plan(sid)
		if plan == null or plan.anchors.is_empty():
			continue
		for room: Dictionary in plan.data.get("interiors", []):
			var center: Vector3 = room["position"]
			for a: Dictionary in plan.anchors:
				if not bool(a.get("interior", false)) or a.get("building", &"") != room["kind"]:
					continue
				var pos: Vector3 = a["position"]
				var to := Vector3(center.x - pos.x, 0.0, center.z - pos.z)
				if to.length() < 1.0 or to.length() > 12.0:
					continue
				var fwd := Basis(Vector3.UP, float(a["yaw"])) * Vector3.FORWARD
				checked += 1
				expect(fwd.dot(to.normalized()) > 0.2, "%s %s %s faces into the room (dot %.2f)" % [sid, room["kind"], a["kind"], fwd.dot(to.normalized())])
		if sid == &"fire_nation_capital":
			var master: Dictionary = {}
			var students: Array = []
			for a: Dictionary in plan.anchors:
				var tags: Array = a.get("tags", [])
				if tags.has("kata_grounds"):
					if a["kind"] == &"trainer":
						master = a
					elif a["kind"] == &"student":
						students.append(a)
			if not master.is_empty() and not students.is_empty():
				var mid := Vector3.ZERO
				for s: Dictionary in students:
					mid += s["position"]
					var to_m: Vector3 = (master["position"] as Vector3) - (s["position"] as Vector3)
					to_m.y = 0.0
					expect((Basis(Vector3.UP, float(s["yaw"])) * Vector3.FORWARD).dot(to_m.normalized()) > 0.5, "kata student faces the master")
				mid /= students.size()
				var to_s: Vector3 = mid - (master["position"] as Vector3)
				to_s.y = 0.0
				expect((Basis(Vector3.UP, float(master["yaw"])) * Vector3.FORWARD).dot(to_s.normalized()) > 0.5, "kata master faces the students")
	if checked == 0:
		print("[integration_fixes] no baked world data: interior anchors not checked")
	else:
		expect(checked >= 10, "interior anchors checked (%d)" % checked)


# --- 7. burn ticks do not shake ---------------------------------------------------------------------

func test_burn_ticks_hurt_without_camera_shake() -> void:
	_ground()
	GameState.new_game(E.EARTH)
	var p := PlayerSim.player(self, E.EARTH, Vector3.ZERO)
	await PlayerSim.step(p, 3)
	var shakes: Array = []
	var cb := func(s: float, _d: float) -> void: shakes.append(s)
	Events.camera_shake.connect(cb)
	var h0 := p.health.health
	var m := FireStatus.ensure()
	expect(FireStatus.ignite(p, 3.5, null, Combat.Team.ENEMY), "player set alight")
	for i in 200:
		await PlayerSim.step(p, 1)
		m._physics_process(1.0 / 60.0)
	var ticks_took := h0 - p.health.health
	expect(ticks_took > 0.5, "burn ticks hurt the player (%.1f)" % ticks_took)
	expect(shakes.is_empty(), "no camera shake from burn ticks (%d)" % shakes.size())
	# A real blow still shakes.
	var hit := HitInfo.make(8.0, null, E.FIRE, HitInfo.Reaction.FLINCH, Vector3.FORWARD, 1.0)
	hit.team = Combat.Team.ENEMY
	p.receive_hit(hit)
	expect(not shakes.is_empty(), "a normal hit shakes")
	Events.camera_shake.disconnect(cb)
	FireStatus.douse(p)
	p.queue_free()


# --- 2. enemy benders use the element techniques ---------------------------------------------------

const TECH_IDS: Array[StringName] = [&"fire_burst", &"fire_ring", &"fire_whip", &"earth_pillar", &"earth_stomp", &"earth_spikes",
	&"water_surge", &"ice_trap", &"ice_wall", &"air_push", &"air_sweep", &"wind_blade"]


## Every bender archetype names element techniques whose slots its controller fills with
## the enemy-tuned (unregistered, slower) copy; readable telegraphs, sane ranges; an air
## archetype exists and the air sparring partner bends.
func test_enemy_bender_loadouts_carry_the_techniques() -> void:
	TrainerLessons.ensure_spar_archetypes()
	var seen := {}
	for id: StringName in [&"fire_soldier", &"fire_captain", &"earth_rogue", &"earth_chief", &"dai_li_agent", &"water_pirate",
			&"air_renegade", &"air_sparring_monk", &"spar_air", &"spar_fire", &"spar_water", &"spar_earth"]:
		expect(EnemyArchetypes.has(id), "%s exists" % id)
		var a := EnemyArchetypes.get_archetype(id)
		var e := EnemyBase.create(id, {"seed": 7})
		add_child(e)
		await frames(1)
		expect(e.controller != null, "%s bends" % id)
		var techs := 0
		var all: Array = (a["attacks"] as Array).duplicate()
		for ph: Dictionary in a["phases"]:
			all.append_array(ph.get("attacks", []))
		for atk: Dictionary in all:
			if atk.get("kind") != &"bending":
				continue
			var slot: StringName = (atk.get("bending", {}) as Dictionary).get("slot", &"light")
			var d: AbilityDef = e.controller.get_slot_def(slot) if e.controller else null
			expect(d != null, "%s/%s: slot %s filled" % [id, atk["id"], slot])
			if d == null:
				continue
			expect(String(d.id).begins_with("enemy_") and not AbilityRegistry.has(d.id), "%s/%s: enemy copy %s, unregistered" % [id, atk["id"], d.id])
			if TECH_IDS.has(StringName(atk["id"])):
				techs += 1
				seen[atk["id"]] = true
				expect(String(d.id) == "enemy_%s" % atk["id"], "%s/%s: the technique's own script (%s)" % [id, atk["id"], d.id])
				var r: Vector2 = atk["range"]
				if atk.get("tag", &"") != &"cover":
					expect(r.y > r.x and r.y <= 18.0, "%s/%s: range %s" % [id, atk["id"], str(r)])
					expect(float(atk.get("approach", 0.0)) + float(atk.get("telegraph", 0.0)) >= 0.45, "%s/%s: readable telegraph" % [id, atk["id"]])
					# the attack waits for both its own cooldown and the ability's
					expect(maxf(float(atk.get("cooldown", 0.0)), d.cooldown) >= 6.0, "%s/%s: technique every 6 s at most" % [id, atk["id"]])
					var base := AbilityRegistry.get_def(StringName(atk["id"]))
					expect(d.cooldown >= base.cooldown, "%s/%s: enemy copy no faster than the player's" % [id, atk["id"]])
		if not String(id).begins_with("spar_") or id == &"spar_air":
			expect(techs >= 1, "%s uses at least one element technique" % id)
		e.queue_free()
	await frames(1)
	for t: StringName in TECH_IDS:
		expect(seen.has(t), "some archetype uses %s" % t)
	expect(EnemyArchetypes.get_archetype(&"air_renegade")["element"] == E.AIR, "the renegade is an airbender")
	var road: Array = []
	for pt: Dictionary in EncounterSites.PATROLS:
		if pt["id"] == &"wl_north_road_bandits":
			road = pt["roster"]
	expect(road.has(&"air_renegade"), "the renegade leads the north road bandits")


## The archetypes' technique attacks really cast through EnemyActions (telegraph -> the
## technique's own script) and land on the player at their range.
func test_enemy_techniques_cast_and_land() -> void:
	PlayerSim.ground(self)
	EnemySim.begin()
	var cases := [[&"fire_soldier", &"fire_burst"], [&"fire_captain", &"fire_whip"], [&"earth_rogue", &"earth_pillar"],
		[&"earth_rogue", &"earth_stomp"], [&"dai_li_agent", &"earth_spikes"], [&"water_pirate", &"water_surge"],
		[&"water_pirate", &"ice_trap"], [&"air_renegade", &"air_push"], [&"air_renegade", &"wind_blade"], [&"air_renegade", &"air_sweep"]]
	var report: Array[String] = []
	for c: Array in cases:
		var arch: StringName = c[0]
		var tid: StringName = c[1]
		var a := EnemyArchetypes.get_archetype(arch)
		var atk: Dictionary = {}
		for x: Dictionary in a["attacks"]:
			if x["id"] == tid:
				atk = x
		expect(not atk.is_empty(), "%s has %s" % [arch, tid])
		if atk.is_empty():
			continue
		var r: Vector2 = atk["range"]
		var dist := clampf(lerpf(r.x, r.y, 0.4), r.x + 0.5, r.y - 0.5)
		var p := PlayerSim.player(self, E.EARTH, Vector3(0, 0, -dist))
		p.health.invulnerable = true
		var e := EnemySim.enemy(self, arch, Vector3.ZERO, p)
		await EnemySim.settle(self)
		e.perception.alert_to(p)
		e.perception.engaged = true
		e.brain.target = p
		var started: Array = []
		e.controller.ability_started.connect(func(ab: BendingAbility) -> void: started.append(ab.def.id))
		var hits: Array = []
		var cb := func(hit: HitInfo, target: Node, _r: int) -> void:
			if target == p and String(hit.ability_id) == "enemy_%s" % tid:
				hits.append(hit)
		Events.hit_landed.connect(cb)
		var tele := [0.0]
		e.attack_telegraphed.connect(func(_en: EnemyBase, _at: Dictionary, secs: float) -> void: tele[0] = secs)
		expect(e.actions.start(atk, p), "%s: %s starts" % [arch, tid])
		e.set_state(EnemyBase.State.ATTACK)
		# One sim step per real physics frame: shockwaves, spike lines and waves are their own
		# nodes and advance in their _physics_process.
		var settle_frames := 40
		for f in 420:
			await get_tree().physics_frame
			EnemySim.step_once([p, e])
			if not hits.is_empty():
				break
			if not e.actions.is_busy() and not started.is_empty():
				settle_frames -= 1
				if settle_frames <= 0:
					break
		Events.hit_landed.disconnect(cb)
		report.append("%s/%s cast=%s hits=%d tell=%.2fs" % [arch, tid, str(started), hits.size(), tele[0]])
		expect(started.has(StringName("enemy_%s" % tid)), "%s: cast the technique (%s)" % [tid, str(started)])
		expect(not hits.is_empty(), "%s: landed on the player at %.1f m" % [tid, dist])
		expect(tele[0] >= 0.3, "%s: telegraphed %.2f s before it struck" % [tid, tele[0]])
		e.queue_free()
		p.queue_free()
		for cst in BendingConstruct.live.duplicate():
			if is_instance_valid(cst):
				cst.queue_free()
		BendingConstruct.live.clear()
		await frames(2)
	EnemySim.end()
	print("[integration_fixes] enemy techniques: ", " | ".join(report))


# --- 1. world fires ---------------------------------------------------------------------------------

func _fire_kit_node(pos: Vector3) -> Node3D:
	var kit := BuildingKit.new(NationPalette.get_palette(&"water_tribe"), 0, 5)
	kit.brazier(Vector3(0, 0, 0), {"height": 0.9, "radius": 0.5})
	kit.lantern(Vector3(3, 1.6, 0), {"style": &"paper"})
	kit.lantern(Vector3(-3, 0, 0), {"style": &"ice"})
	kit.add_fire(Vector3(0, 0.15, 4), &"campfire", 0.5)
	var root := kit.build().instantiate({"name": "FireKit"})
	root.position = pos
	add_child(root)
	return root


## Braziers / lanterns / fire pits record their fires (ice lanterns do not burn); a kit node
## registers them with WorldFires at its world position and forgets them when it leaves.
func test_world_fires_kit_records_and_registry() -> void:
	WorldFires.clear()
	var kit := BuildingKit.new(NationPalette.get_palette(&"neutral"), 0, 1)
	kit.brazier(Vector3.ZERO)
	kit.lantern(Vector3(2, 1, 0), {"style": &"post"})
	kit.lantern(Vector3(4, 1, 0), {"style": &"ice"})
	kit.add_fire(Vector3(6, 0.2, 0), &"campfire", 0.5)
	var res := kit.build()
	var kinds: Array = res.fires.map(func(f: Dictionary) -> StringName: return f["kind"])
	expect_eq(res.fires.size(), 3, "brazier + post lantern + campfire (ice lanterns excluded): %s" % str(kinds))
	expect(kinds.has(&"brazier") and kinds.has(&"lantern") and kinds.has(&"campfire"), "kinds %s" % str(kinds))
	var far := BuildingKit.new(NationPalette.get_palette(&"neutral"), 1, 1)
	far.brazier(Vector3.ZERO)
	expect(far.build().fires.is_empty(), "LOD1 kits record no fires (LOD0 is the interactive range)")
	var n0 := WorldFires.spot_count()
	var root := _fire_kit_node(Vector3(100, 0, 50))
	await frames(1)
	expect_eq(WorldFires.spot_count() - n0, 3, "three fires registered")
	var near := WorldFires.spots_near(Vector3(100, 1, 50), 2.0)
	expect(not near.is_empty() and StringName(near[0]["kind"]) == &"brazier", "the brazier sits at the node's world position")
	if not near.is_empty():
		expect((near[0]["pos"] as Vector3).distance_to(Vector3(100, 1.2, 50)) < 0.2, "flame base at the coal bed (%s)" % str(near[0]["pos"]))
	root.queue_free()
	await frames(2)
	expect_eq(WorldFires.spot_count(), n0, "forgotten when the node leaves")


## Water / wind put a lit fire out (hooks and hit proxies), the shader mask, night glow mask
## and light follow, it relights after its timer; fire relights it at once; a cold brazier
## stands unlit by day, lights with fire, burns out, and is lit at night; smoke follows;
## stand-ins are budgeted and runtime state drops far away.
func test_world_fires_douse_ignite_relight() -> void:
	WorldFires.clear()
	WorldFires.time_override = 1   # night: everything lit as baked
	SettlementFx.prepare()
	var root := _fire_kit_node(Vector3(0, 0, 0))
	var smoke := PropFx.particles(&"smoke")
	add_child(smoke)
	smoke.global_position = Vector3(0, 0.9, 4.0)
	var m := WorldFires.ensure()
	await frames(2)
	m.focus_override = Vector3(0, 1.5, 6)
	m.update_now()
	var br: Dictionary = WorldFires.spots_near(Vector3(0, 1.2, 0), 0.5)[0]
	var bid := int(br["id"])
	var bpos: Vector3 = br["pos"]
	expect(WorldFires.is_lit(bid), "brazier lit at night")
	expect(m.proxies.has(bid), "a stand-in at the brazier")
	expect(get_tree().get_nodes_in_group(FireEnv.EXTINGUISHABLE).any(func(n: Node) -> bool: return n is WorldFireSpot), "stand-ins join the extinguish hook")
	# Water (the shared EXTINGUISH hook, as Water Surge / Jet / Wave / Torrent call it).
	var probe := Node3D.new()
	add_child(probe)
	expect_eq(FireEnv.extinguish(probe, bpos + Vector3(0.4, 0.2, 0), 0.8), 1, "the hook puts the brazier out")
	await frames(2)
	expect(not WorldFires.is_lit(bid), "brazier out")
	expect(m.mask.size() == 1 and Vector3(m.mask[0].x, m.mask[0].y, m.mask[0].z).distance_to(bpos) < 0.01 and m.mask[0].w > 0.0, "masked (flames collapse): %s" % str(m.mask))
	var gm := NationPalette.material(&"glow") as ShaderMaterial
	expect_eq(int(gm.get_shader_parameter(&"fire_mask_count")), 1, "kit glow material masks it")
	var ng := SettlementFx.glow_material()
	expect(ng != null and int(ng.get_shader_parameter(&"fire_mask_count")) == 1, "night glow material masks it (glow matches the state)")
	expect(LightBudget.suppress.is_valid() and bool(LightBudget.suppress.call(bpos + Vector3(0, 0.4, 0))), "its light is kept off")
	expect(not bool(LightBudget.suppress.call(bpos + Vector3(3, 0.4, 0))), "other lights are not")
	# Fire relights it at once (IGNITE hook, as FireEnv.heat does).
	expect_eq(FireEnv.ignite_at(probe, bpos + Vector3(0, 0.3, 0), 0.8), 1, "fire lights it again")
	await frames(2)
	expect(WorldFires.is_lit(bid) and m.mask.is_empty(), "lit again, mask cleared")
	# A water hit on the flame (FireHitProxy) douses; the timer relights it.
	var sp: WorldFireSpot = m.proxies[bid]
	var wet := HitInfo.make(7.0, null, E.WATER, HitInfo.Reaction.FLINCH, Vector3.FORWARD, 3.0)
	wet.team = Combat.Team.PLAYER
	Combat.deal(sp.proxy, wet)
	await frames(2)
	expect(not WorldFires.is_lit(bid), "a water whip on the flame douses it")
	var o: Dictionary = m.overrides.get(bid, {})
	expect(not o.is_empty() and float(o["until"]) - m.clock >= 29.0, "relights after a while (%.0f s)" % (float(o.get("until", 0.0)) - m.clock))
	m.clock = float(o.get("until", 0.0)) + 0.1
	m.update_now()
	expect(WorldFires.is_lit(bid), "relit when its timer ran out")
	# Wind: a strong gust (AirEnv / FireEnv.extinguish) or a heavy air hit.
	var gust := HitInfo.make(10.0, null, E.AIR, HitInfo.Reaction.KNOCKBACK, Vector3.FORWARD, 8.0)
	gust.team = Combat.Team.PLAYER
	Combat.deal(sp.proxy, gust)
	await frames(2)
	expect(not WorldFires.is_lit(bid), "a strong gust blows it out")
	var light_gust := HitInfo.make(3.0, null, E.AIR, HitInfo.Reaction.FLINCH, Vector3.FORWARD, 1.0)
	m.clear_override(bid)
	await frames(1)
	Combat.deal(sp.proxy, light_gust)
	await frames(1)
	expect(WorldFires.is_lit(bid), "a light breeze does not")
	# Campfire smoke stops while it is out.
	var camp: Dictionary = WorldFires.spots_near(Vector3(0, 0.15, 4), 0.5)[0]
	WorldFires.extinguish(int(camp["id"]))
	await frames(2)
	expect(not smoke.emitting, "the campfire's smoke stops")
	WorldFires.ignite(int(camp["id"]))
	await frames(2)
	expect(smoke.emitting, "and starts again when it is relit")
	# Lantern: darken-only mask entry (negative radius).
	var lan: Dictionary = WorldFires.spots_near(Vector3(3, 1.6, 0), 0.6)[0]
	WorldFires.extinguish(int(lan["id"]))
	await frames(2)
	expect(m.mask.size() == 1 and m.mask[0].w < 0.0, "a lantern goes dark (no flame collapse)")
	WorldFires.ignite(int(lan["id"]))
	# Cold braziers: unlit by day, lit with fire, burn out, lit at night.
	var cold_root := Node3D.new()
	add_child(cold_root)
	var recs: Array = []
	for k in 30:
		recs.append({"position": Vector3(-20.0 + k * 1.37, 1.0, -8.0), "kind": &"brazier", "radius": 0.5})
	WorldFires.register(cold_root, recs)
	await frames(1)
	var cold: Dictionary = {}
	for s: Dictionary in WorldFires.spots_near(Vector3(0, 1, -8), 25.0):
		if bool(s["cold"]):
			cold = s
			break
	expect(not cold.is_empty(), "some braziers stand cold by day")
	if not cold.is_empty():
		var cid := int(cold["id"])
		WorldFires.time_override = 0
		m.update_now()
		expect(not WorldFires.is_lit(cid), "a cold brazier is unlit by day")
		expect(m.mask.size() >= 1, "and masked (no flames, no glow)")
		expect(WorldFires.ignite(cid), "a firebender lights it")
		await frames(2)
		expect(WorldFires.is_lit(cid), "lit by day")
		var oc: Dictionary = m.overrides.get(cid, {})
		expect(not oc.is_empty() and float(oc["until"]) - m.clock >= 59.0, "burns for a minute or more")
		m.clock = float(oc.get("until", 0.0)) + 0.1
		m.update_now()
		expect(not WorldFires.is_lit(cid), "then burns out by day")
		WorldFires.time_override = 1
		m.update_now()
		expect(WorldFires.is_lit(cid), "lit again at night")
	# Budget: stand-ins only for the nearest fires.
	m.update_now()
	expect(m.proxies.size() <= WorldFires.PROXIES[clampi(Settings.detail_level(), 0, 3)], "stand-ins within budget (%d)" % m.proxies.size())
	# Far away the runtime state drops (the fire shows its baked state again).
	WorldFires.extinguish(bid)
	m.focus_override = Vector3(400, 0, 400)
	m.update_now()
	expect(WorldFires.is_lit(bid) and m.proxies.is_empty(), "state and stand-ins dropped far away")
	m.focus_override = Vector3.INF
	WorldFires.time_override = -1
	root.queue_free()
	cold_root.queue_free()
	smoke.queue_free()
	probe.queue_free()
	await frames(2)
	WorldFires.clear()


## The real player's bending reaches a settlement-style brazier on a plinth (flame base 1.5 m
## up, as the Water Tribe's): an air blast and a water whip put it out, a fire jab lights it.
func test_player_bending_reaches_world_fires() -> void:
	_ground()
	WorldFires.clear()
	WorldFires.time_override = 1
	var kit := BuildingKit.new(NationPalette.get_palette(&"water_tribe"), 0, 3)
	kit.box(Vector3(0, 0.35, 0), Vector3(1.3, 0.7, 1.3), &"stone_dark", true)
	kit.brazier(Vector3(0, 0.7, 0), {"height": 0.5, "radius": 0.5, "range": 12.0})
	var root := kit.build().instantiate({"name": "Plinth"})
	root.position = Vector3(0, 0, -3.7)
	add_child(root)
	var m := WorldFires.ensure()
	await frames(2)
	m.focus_override = Vector3(0, 1.6, 2.0)
	m.update_now()
	var bid := int(WorldFires.spots_near(Vector3(0, 1.5, -3.7), 0.6)[0]["id"])
	var report: Array[String] = []
	for e: int in [E.AIR, E.WATER, E.FIRE]:
		GameState.new_game(e)
		var p := PlayerSim.player(self, e, Vector3.ZERO)
		p.resources.infinite_chi = true
		await PlayerSim.step(p, 3)
		if e == E.FIRE:
			WorldFires.extinguish(bid)
			await frames(1)
		var was := WorldFires.is_lit(bid)
		var action := &"attack_heavy" if e == E.AIR else &"attack_light"
		await PlayerSim.tap(p, action, 4)
		for i in 90:
			await get_tree().physics_frame
			PlayerSim.step_once(p)
			if WorldFires.is_lit(bid) != was:
				break
		report.append("%s %s: %s -> %s" % [ElementDefs.id_of(e), action, was, WorldFires.is_lit(bid)])
		expect(WorldFires.is_lit(bid) != was, "%s %s changes the brazier (%s)" % [ElementDefs.id_of(e), action, report.back()])
		m.clear_override(bid)
		await frames(2)
		p.queue_free()
		await frames(1)
	print("[integration_fixes] player vs brazier: ", " | ".join(report))
	WorldFires.time_override = -1
	m.focus_override = Vector3.INF
	root.queue_free()
	await frames(1)
	WorldFires.clear()


## The real settlements record their fires: a Water Tribe cell with braziers (and the fire pit
## of an arctic village) built by the SettlementProvider carries LOD0 fire records.
func test_settlement_cells_record_fires() -> void:
	WorldData.use_flat_world(false)
	var plan := Settlements.plan(&"northern_water_tribe")
	if plan == null or plan.pieces.is_empty():
		print("[integration_fixes] no baked world data: settlement fires not checked")
		return
	var builder := Settlements.builder(&"northern_water_tribe")
	var prov := SettlementProvider.new(plan, builder)
	prov.configure()
	var coord := Vector2i(999999, 0)
	for i in plan.pieces.size():
		if plan.pieces[i]["kind"] == &"brazier":
			var bp: Vector3 = plan.pieces[i]["pos"]
			coord = plan.coord_of(bp.x, bp.z)
			break
	expect(coord.x != 999999, "a brazier piece exists")
	if coord.x == 999999:
		return
	var origin := Vector3((coord.x + 0.5) * plan.cell_size, 0, (coord.y + 0.5) * plan.cell_size)
	var res: Array = prov.build_lods(coord, origin, 1)
	var r0: KitResult = res[0]
	var kinds := {}
	for f: Dictionary in r0.fires:
		kinds[f["kind"]] = int(kinds.get(f["kind"], 0)) + 1
	expect(int(kinds.get(&"brazier", 0)) >= 1, "the cell's braziers are recorded: %s" % str(kinds))
	expect((res[1] as KitResult).fires.is_empty(), "LOD1 carries none")
