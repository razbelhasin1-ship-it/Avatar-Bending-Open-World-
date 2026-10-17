extends RefCounted
## First-use hitches of every technique, with and without the shader warm-up (perf_polish,
## docs/qa/perf_polish.md). Loads the combat arena for ELEMENT (default fire), lets the
## ShaderWarmup run (WARMUP=0 skips it), then casts every technique of the element through the
## real player and input actions - light chain, heavy charged, defense held, dodge, each
## technique (charges held to full), the signature - and records per cast: the longest frame,
## and the pipelines compiled while the frame waited (RenderingServer draw-time compilations).
## A second round of the same casts shows the warm steady state. Report: <out>/warmup_<el>_<on|off>_<renderer>.json.
##
## Run: ELEMENT=fire tools/playtest.sh perf_polish_warmup .playtest/warm 960x540
##      ELEMENT=fire WARMUP=0 tools/playtest.sh perf_polish_warmup .playtest/cold 960x540
##      RENDERER=mobile MOBILE=1 ... (phone preset)
## The pipeline cache on disk keeps compiled pipelines between runs: compare on/off runs made
## back to back on the same machine; FIRST_RUN=1 deletes the user shader / pipeline caches first.

var p: Playtest
var pl: PlayerCharacter
var rec: FrameRecorder
var report := {}


func run(pt: Playtest) -> void:
	p = pt
	var e := ElementDefs.Element.FIRE
	if OS.get_environment("ELEMENT") != "":
		e = ElementDefs.from_id(StringName(OS.get_environment("ELEMENT")))
	var warm := OS.get_environment("WARMUP") != "0"
	if OS.get_environment("MOBILE") != "" or Settings.is_mobile_device():
		Settings.apply_preset("mobile")
		Settings.apply()
	report["element"] = ElementDefs.id_of(e)
	report["warmup"] = warm
	report["renderer"] = Settings.rendering_method()
	GameState.new_game(e, true)
	rec = FrameRecorder.attach(p.get_tree())
	var t0 := Time.get_ticks_msec()
	var arena := await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": e, "warmup": warm, "no_warmup": not warm})
	var warm_node: Variant = arena.get("warmup")
	if warm_node is ShaderWarmup and is_instance_valid(warm_node):
		await (warm_node as ShaderWarmup).wait_done(ShaderWarmup.MAX_SECONDS + 5.0)
	report["warmup_report"] = arena.get("warmup_report")
	report["load_s"] = (Time.get_ticks_msec() - t0) / 1000.0
	p.note("arena ready in %.1f s, warm-up %s" % [report["load_s"], str(report["warmup_report"])])
	await p.wait_game(1.0)
	pl = p.player() as PlayerCharacter
	pl.resources.infinite_chi = true
	var bot := arena.get("bot") as Node
	if bot:
		bot.set("active", false)
	pl.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, -1.5)))
	await p.wait_game(0.5)
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.5)
	var idle := rec.mark()
	await p.wait_game(1.0)
	report["idle"] = rec.summary(idle)
	var rounds: Array = []
	for r in 2:
		var casts: Array = []
		for d: AbilityDef in AbilityRegistry.for_element(e):
			if d.slot == AbilityDef.Slot.PASSIVE or d.slot == AbilityDef.Slot.INNATE or d.script_path.is_empty():
				continue
			casts.append(await _cast(d))
		var worst := 0.0
		var draw := 0
		var total := 0
		for c: Dictionary in casts:
			worst = maxf(worst, float(c["max_ms"]))
			draw += int(c["compiles_draw"])
			total += int(c["compiles"])
		p.note("round %d (%s): worst frame %.0f ms, pipelines compiled %d (draw-time %d)" % [r + 1, "first casts" if r == 0 else "warm", worst, total, draw])
		rounds.append({"casts": casts, "worst_ms": worst, "compiles": total, "compiles_draw": draw})
		if r == 0:
			await p.screenshot("warmup_%s_%s" % [ElementDefs.id_of(e), "on" if warm else "off"])
	report["rounds"] = rounds
	var path := p.out_dir.path_join("warmup_%s_%s_%s.json" % [ElementDefs.id_of(e), "on" if warm else "off", report["renderer"]])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
	p.note("report written to %s" % path)
	if warm:
		var first: Dictionary = rounds[0]
		p.check(int(first["compiles_draw"]) <= 2, "after the warm-up the first casts compile (almost) no pipelines at draw time (%d)" % first["compiles_draw"])
		# with ubershaders the engine never waits at draw time; the specialised pipelines are still
		# compiled (in the background, and on phones that costs frames): the warm-up must cover them
		p.check(int(first["compiles"]) <= 3, "after the warm-up the first casts compile (almost) no pipelines at all (%d)" % first["compiles"])
	rec.queue_free()


## Casts one technique through the player's input and measures the frames around it.
func _cast(d: AbilityDef) -> Dictionary:
	pl.controller.reset_cooldowns()
	pl.resources.set_chi(PlayerResources.CHI_MAX)
	pl.resources.set_focus(100.0)
	var action: StringName = &"ability_1"
	match d.slot:
		AbilityDef.Slot.LIGHT: action = &"attack_light"
		AbilityDef.Slot.HEAVY: action = &"attack_heavy"
		AbilityDef.Slot.DEFENSE: action = &"block"
		AbilityDef.Slot.DODGE: action = &"dodge"
		AbilityDef.Slot.SIGNATURE:
			action = &"ability_special"
			pl.controller.set_slot(&"signature", d)
		_:
			pl.controller.set_slot(&"technique_1", d)
	if d.slot == AbilityDef.Slot.LIGHT:
		pl.controller.set_slot(&"light", d)
	var hold := 0.08
	if d.charge_time > 0.0:
		hold = minf(d.charge_time + 0.1, 1.8)
	elif d.max_hold > 0.0 or d.slot == AbilityDef.Slot.DEFENSE:
		hold = 0.6
	var mark := rec.mark()
	var presses := 3 if d.slot == AbilityDef.Slot.LIGHT else 1
	for k in presses:
		p.hold(action)
		await p.wait_game(hold)
		p.release(action)
		await p.wait_game(0.28)
	await p.wait_game(1.1)
	# leave toggles (scooter, armor) and long channels
	if pl.controller.is_busy():
		pl.controller.cancel_current(&"test")
	await p.wait_game(0.3)
	var s := rec.summary(mark)
	s["id"] = String(d.id)
	p.note("   %-16s frames %3d  worst %6.0f ms  avg %5.0f ms  pipelines compiled %3d (draw-time %d)" % [d.id, s["frames"], s["max_ms"], s["avg_ms"],
			s["compiles"], s["compiles_draw"]])
	return s
