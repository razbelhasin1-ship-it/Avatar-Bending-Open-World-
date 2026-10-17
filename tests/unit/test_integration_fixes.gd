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
