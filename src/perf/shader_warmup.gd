class_name ShaderWarmup
extends Node3D
## Shader / pipeline warm-up behind a loading screen (perf_polish, docs/qa/perf_polish.md).
##
## The first use of a bending technique used to hitch (0.5-2.3 s under software rendering, a
## visible stall on phones) because its FX materials, mesh formats and particle shaders compiled
## their render pipelines on demand. The warm-up casts every technique of the player's element
## once - plus the light and heavy strikes of the other three elements (enemy benders) - on
## rig-less casters standing on a private stage far outside the playable world, aimed at training
## posts (hits, blocks, burns, freezes), and spawns the shared one-shots every element uses
## (particle bursts, decals, rings, flashes, debris, parries, world impacts). Its own camera looks
## at all of it for a couple of seconds while the loading screen (or `cover`) hides the view, so
## every pipeline is compiled - and every pooled FX node created - before the player can act.
##
##   var w := ShaderWarmup.start(scene, element)      # runs on its own (a child of `scene`)
##   ... loading continues ...
##   await w.wait_done(20.0)                          # wall-clock cap
##   print(w.report); w.queue_free()                  # the stage is gone already
##
## Never runs headless (nothing renders) or with the `--no-warmup` user argument. Gameplay stays
## untouched: the casters are not the player (no HUD events, focus, practice, hitstop or shake),
## the stage sits beyond the world edge (no NPC, enemy, wildlife, grass or snow reacts), the SFX
## bus is muted while it runs, and everything it raised (projectiles, constructs, fire rings) is
## removed again. `report` = {skipped, abilities, casters, frames, seconds, compiles, compiles_draw}.

signal finished(report: Dictionary)

## Game seconds the casts run (charges, travel, impacts) before the stage is cleared.
const RUN_SECONDS := 2.4
## Wall-clock cap of the whole pass (slow first-run compiles on a phone).
const MAX_SECONDS := 30.0
const SPACING := Vector2(9.0, 15.0)
const COLUMNS := 6
const TARGET_DISTANCE := 5.0

var element: int = ElementDefs.Element.FIRE
## Also the other elements' light + heavy strikes (enemy benders, sparring partners).
var other_elements := true
## Black full-screen cover while it runs (scenes without a loading screen: the combat arena).
var cover := false
var done := false
var report: Dictionary = {}

var _camera: Camera3D = null
var _prev_camera: Camera3D = null
var _casters: Array[BendingController] = []
var _bodies: Array[CharacterBody3D] = []
var _zones: Array[StringName] = []
var _cover_layer: CanvasLayer = null
var _sfx_bus := -1
var _sfx_was_muted := false
var _t0 := 0
var _frames := 0
var _pc0 := {}


## True when a warm-up makes sense here (something renders, not disabled for this run).
static func enabled() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--no-warmup")


## Starts a warm-up under `parent` for `p_element`. opts: other_elements (bool, true),
## cover (bool, false).
static func start(parent: Node, p_element: int, opts: Dictionary = {}) -> ShaderWarmup:
	var w := ShaderWarmup.new()
	w.name = "ShaderWarmup"
	w.element = p_element if ElementDefs.is_valid(p_element) else ElementDefs.Element.FIRE
	w.other_elements = bool(opts.get("other_elements", true))
	w.cover = bool(opts.get("cover", false))
	parent.add_child(w)
	if enabled() and not bool(opts.get("skip", false)):
		w._run()
	else:
		w._finish(true)
	return w


## Waits until the warm-up finished or `timeout` wall-clock seconds passed. Returns done.
func wait_done(timeout: float = MAX_SECONDS) -> bool:
	var t0 := Time.get_ticks_msec()
	while not done and is_inside_tree() and Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		await get_tree().process_frame
	return done


## Stage origin: beyond the north-east corner of the world, well above any terrain.
static func stage_origin() -> Vector3:
	var b := WorldData.get_bounds()
	return Vector3(b.end.x + 1600.0, 420.0, b.end.y + 1600.0)


## The abilities warmed for `e`: [[element, AbilityDef], ...] (every technique of the element,
## the light + heavy strikes of the others).
static func program(e: int, others: bool = true) -> Array:
	var out: Array = []
	for d: AbilityDef in AbilityRegistry.for_element(e):
		if d.slot == AbilityDef.Slot.PASSIVE or d.slot == AbilityDef.Slot.INNATE:
			continue
		if d.script_path.is_empty():
			continue
		out.append([e, d])
	if others:
		for o in [ElementDefs.Element.AIR, ElementDefs.Element.EARTH, ElementDefs.Element.FIRE, ElementDefs.Element.WATER]:
			if o == e:
				continue
			var kit := AbilityRegistry.core_kit(o)
			for slot: StringName in [&"light", &"heavy"]:
				var d: AbilityDef = kit.get(slot)
				if d != null and not d.script_path.is_empty():
					out.append([o, d])
	return out


# --- run ---------------------------------------------------------------------------------------------

func _run() -> void:
	_t0 = Time.get_ticks_msec()
	_pc0 = FrameRecorder.pipeline_compilations()
	global_position = stage_origin()
	if cover:
		_add_cover()
	_mute_sfx(true)
	var entries := program(element, other_elements)
	_build_stage(entries)
	_camera = Camera3D.new()
	_camera.name = "WarmupCamera"
	_camera.fov = 80.0
	_camera.far = 600.0
	add_child(_camera)
	var rows := ceili(float(entries.size()) / COLUMNS)
	var depth := rows * SPACING.y
	_camera.position = Vector3(0.0, 16.0 + depth * 0.35, 18.0)
	_camera.look_at(global_position + Vector3(0.0, 0.0, -depth * 0.45), Vector3.UP)
	_prev_camera = get_viewport().get_camera_3d()
	_camera.make_current()
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	for i in _casters.size():
		_cast(_casters[i], entries[i][1])
	_common_fx()
	var ticks := int(RUN_SECONDS * Engine.physics_ticks_per_second)
	for i in ticks:
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		_step_bodies()
		if Time.get_ticks_msec() - _t0 > int(MAX_SECONDS * 1000.0):
			break
	# Every effect drew at least once; two more rendered frames for the ones spawned last (the
	# headless server draws nothing and never posts frame_post_draw: forced runs in the tests).
	var drawn := DisplayServer.get_name() != "headless"
	for i in 2:
		if drawn:
			await RenderingServer.frame_post_draw
		else:
			await get_tree().process_frame
		if not is_inside_tree():
			return
	report["abilities"] = entries.size()
	_cleanup()
	_finish(false)


func _process(_d: float) -> void:
	if not done:
		_frames += 1


func _finish(skipped: bool) -> void:
	var pc := FrameRecorder.pipeline_compilations()
	report["skipped"] = skipped
	report["casters"] = _casters.size()
	report["frames"] = _frames
	report["seconds"] = (Time.get_ticks_msec() - _t0) / 1000.0 if _t0 > 0 else 0.0
	report["compiles"] = int(pc["total"]) - int(_pc0.get("total", pc["total"]))
	report["compiles_draw"] = int(pc["draw"]) - int(_pc0.get("draw", pc["draw"]))
	done = true
	finished.emit(report)
	# The stage goes; this node stays (inert) so the owner can read `report`, then frees it.
	for c in get_children():
		c.queue_free()


func _exit_tree() -> void:
	# Interrupted (scene change while loading): never leave the bus muted or zones behind.
	if not done:
		_cleanup()
		done = true


# --- stage -------------------------------------------------------------------------------------------

func _build_stage(entries: Array) -> void:
	var rows := ceili(float(entries.size()) / COLUMNS)
	var w := COLUMNS * SPACING.x + 20.0
	var d := rows * SPACING.y + 20.0
	var floor_body := StaticBody3D.new()
	floor_body.name = "StageFloor"
	floor_body.collision_layer = Layers.WORLD
	floor_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, 1.0, d)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0.0, -0.5, -d * 0.5 + 10.0)
	add_child(floor_body)
	# Surfaces for the surface-aware effects: snow under water benders (their water source; snow
	# steam / dust for the others), stone elsewhere. Zones are rectangles in x/z beyond the world.
	var o := global_position
	for i in entries.size():
		var e: int = entries[i][0]
		var p := _slot_pos(i)
		var id := StringName("warmup_%d" % i)
		GroundSampler.add_zone(id, Rect2(o.x + p.x - SPACING.x * 0.5, o.z + p.z - SPACING.y + 1.0, SPACING.x, SPACING.y),
				&"snow" if e == ElementDefs.Element.WATER else &"stone", 0.1)
		_zones.append(id)
		_casters.append(_make_caster(e, p))
		var dummy := TrainingDummy.new()
		dummy.name = "WarmupPost%d" % i
		dummy.look = &"post"
		dummy.max_health = 100000.0
		# every other other-element target guards: block impacts for every element too
		dummy.guarding = e != element and i % 2 == 1
		dummy.position = p + Vector3(0.0, 0.0, -TARGET_DISTANCE)
		add_child(dummy)
		dummy.home = dummy.global_transform


func _slot_pos(i: int) -> Vector3:
	@warning_ignore("integer_division")
	var row := i / COLUMNS
	var col := i % COLUMNS
	return Vector3((col - (COLUMNS - 1) * 0.5) * SPACING.x, 0.0, -row * SPACING.y)


func _make_caster(e: int, p: Vector3) -> BendingController:
	var b := CharacterBody3D.new()
	b.name = "WarmupCaster"
	b.collision_layer = 0
	b.collision_mask = Layers.WORLD
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.74
	cs.shape = cap
	cs.position = Vector3(0, 0.87, 0)
	b.add_child(cs)
	b.position = p
	add_child(b)
	_bodies.append(b)
	var ctx := BendingContext.new(b, null, e, Combat.Team.PLAYER)
	ctx.aim_provider = func() -> Dictionary:
		var f := ctx.forward()
		return {"direction": f, "target": null, "point": ctx.origin() + Vector3.UP * 1.1 + f * TARGET_DISTANCE}
	var bc := BendingController.new()
	b.add_child(bc)
	bc.setup(ctx)
	bc.auto_tick = true
	return bc


## Keeps the casters standing on the stage (abilities never move a body themselves).
func _step_bodies() -> void:
	for b in _bodies:
		if is_instance_valid(b) and b.is_inside_tree():
			b.velocity = Vector3(0.0, -2.0, 0.0)
			b.move_and_slide()


# --- casting -----------------------------------------------------------------------------------------

## One use of `d` on `bc`, pressed and released like a player would (charges are held to full).
func _cast(bc: BendingController, d: AbilityDef) -> void:
	var slot: StringName
	match d.slot:
		AbilityDef.Slot.LIGHT: slot = &"light"
		AbilityDef.Slot.HEAVY: slot = &"heavy"
		AbilityDef.Slot.DEFENSE: slot = &"defense"
		AbilityDef.Slot.DODGE: slot = &"dodge"
		AbilityDef.Slot.SIGNATURE: slot = &"signature"
		_: slot = &"technique_1"
	bc.set_slot(slot, d)
	var presses := 3 if d.slot == AbilityDef.Slot.LIGHT else 1
	var hold := 0.08
	if d.charge_time > 0.0:
		hold = minf(d.charge_time + 0.1, 1.8)
	elif d.max_hold > 0.0 or d.slot == AbilityDef.Slot.DEFENSE:
		hold = 0.6
	for k in presses:
		if not is_instance_valid(bc) or not bc.is_inside_tree():
			return
		bc.request(slot)
		await _game_wait(hold)
		if not is_instance_valid(bc) or not bc.is_inside_tree():
			return
		bc.release(slot)
		if k < presses - 1:
			await _game_wait(0.26)


func _game_wait(t: float) -> void:
	for i in maxi(1, int(round(t * Engine.physics_ticks_per_second))):
		await get_tree().physics_frame
		if not is_inside_tree():
			return


## The shared one-shots: every burst kind, decal, ring, flash, debris, parries and world impacts
## of all elements (they do not count as hits: no ImpactFx.hit here, the posts take real ones).
func _common_fx() -> void:
	var at := global_position + Vector3(0.0, 1.0, 6.0)
	var i := 0
	for kind: StringName in FxBurst.KINDS:
		FxBurst.spawn(self, kind, at + Vector3(-12.0 + i * 1.6, 0.0, 0.0))
		i += 1
	var g := global_position + Vector3(0.0, 0.02, 4.0)
	var j := 0
	for mark: StringName in [&"crack", &"scorch", &"wet", &"frost"]:
		FxDecal.spawn(self, g + Vector3(-6.0 + j * 4.0, 0.0, 0.0), mark, 1.4)
		j += 1
	FxRing.spawn(self, g + Vector3(8.0, 0.0, 0.0), 2.0, Color(1, 0.9, 0.7), 1.0)
	FxFlash.spawn(self, at, Color(1.0, 0.7, 0.4), 2.0, 0.6, 6.0)
	FxDebris.spawn(self, at + Vector3(4.0, 0.0, 0.0), {"kind": &"rock", "count": 4, "ground_y": global_position.y})
	FxDebris.spawn(self, at + Vector3(6.0, 0.0, 0.0), {"kind": &"ice", "count": 4, "ground_y": global_position.y})
	var k := 0
	for e in [ElementDefs.Element.AIR, ElementDefs.Element.EARTH, ElementDefs.Element.FIRE, ElementDefs.Element.WATER]:
		var p := at + Vector3(-9.0 + k * 6.0, 0.0, 3.0)
		ImpactFx.parry(self, e, p)
		ImpactFx.world(self, e, Vector3(p.x, global_position.y, p.z), Vector3.UP, 1.0, &"stone")
		k += 1


# --- cleanup -----------------------------------------------------------------------------------------

func _cleanup() -> void:
	for bc in _casters:
		if is_instance_valid(bc) and bc.current != null:
			bc.cancel_current(&"warmup")
	var mine := {}
	for b in _bodies:
		if is_instance_valid(b):
			mine[b.get_instance_id()] = true
	for pr in BendingProjectile.live.duplicate():
		var prj := pr as BendingProjectile
		if prj != null and is_instance_valid(prj) and prj.ctx != null and is_instance_valid(prj.ctx.caster) \
				and mine.has(prj.ctx.caster.get_instance_id()):
			prj.destroy(false)
	var o := global_position
	for c in BendingConstruct.live.duplicate():
		var con := c as BendingConstruct
		if con != null and is_instance_valid(con) and con.global_position.distance_to(o) < 200.0:
			con.queue_free()
	for w in FireRingWave.live.duplicate():
		var wave := w as FireRingWave
		if wave != null and is_instance_valid(wave) and wave.ctx != null and is_instance_valid(wave.ctx.caster) \
				and mine.has(wave.ctx.caster.get_instance_id()):
			wave.queue_free()
	for id in _zones:
		GroundSampler.remove_zone(id)
	_zones.clear()
	if _camera and is_instance_valid(_camera) and _camera.current:
		if _prev_camera != null and is_instance_valid(_prev_camera) and _prev_camera.is_inside_tree():
			_prev_camera.make_current()
		else:
			_camera.clear_current(false)
	_mute_sfx(false)
	if _cover_layer and is_instance_valid(_cover_layer):
		_cover_layer.queue_free()
	_cover_layer = null


func _mute_sfx(on: bool) -> void:
	if on:
		_sfx_bus = AudioServer.get_bus_index("SFX")
		if _sfx_bus >= 0:
			_sfx_was_muted = AudioServer.is_bus_mute(_sfx_bus)
			AudioServer.set_bus_mute(_sfx_bus, true)
	elif _sfx_bus >= 0:
		AudioServer.set_bus_mute(_sfx_bus, _sfx_was_muted)
		_sfx_bus = -1


func _add_cover() -> void:
	_cover_layer = CanvasLayer.new()
	_cover_layer.name = "WarmupCover"
	_cover_layer.layer = 118
	var r := ColorRect.new()
	r.color = Color(0.02, 0.018, 0.016, 1.0)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover_layer.add_child(r)
	add_child(_cover_layer)
