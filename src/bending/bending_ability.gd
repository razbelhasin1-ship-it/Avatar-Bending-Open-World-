class_name BendingAbility
extends RefCounted
## Base class of every bending ability (docs/modules/bending.md "Adding an ability").
##
## Lifecycle, driven by BendingController:
##   can_use() -> &"" or a failure reason (&"no_ground", &"no_target" ...)
##   begin()                     plays the clip (play_clip) and sets the movement request
##   on_event(event)             the rig's timed clip events: spawn gameplay on
##                               &"release" / &"impact" (never on a free-running timer)
##   update(delta)               per physics tick while running
##   on_input_released()         the slot's button was released (charge / hold)
##   on_cancel(reason)           interrupted (hit, dodge-cancel, death): clean up
##   on_finish()                 normal end: clean up
## Call finish() when done; the default update() finishes when the clip ends.
## Rig-less casters get the clip's events from a virtual timeline built from
## the AnimClip data, so abilities behave the same without a body.

var def: AbilityDef
var ctx: BendingContext
var controller: BendingController
## Seconds since begin().
var time := 0.0
var finished := false
var cancelled := false
## Unique id per use: every target is hit at most once per attack_id (BendingHits).
var attack_id := 0
## Clip currently playing for this ability (events of other clips are ignored).
var clip: StringName = &""
## Time (ability clock) the current clip ends.
var clip_end := 0.0
## Time from which dodge/defend may cancel (recovery cancel window).
var cancel_at := INF
## Hard safety timeout: the ability ends no matter what after this many seconds.
var max_time := 4.0
## True while the slot's button is still held (charges, holds).
var input_held := true
## Slot the ability was started from (&"light", &"heavy", &"technique_2" ...).
var slot: StringName = &""

var _virtual: Array = []


# --- overridable ------------------------------------------------------------------------------

## Extra conditions beyond chi/cooldown (checked by the controller before begin()).
func can_use() -> StringName:
	return &""


func begin() -> void:
	if def.clip != &"":
		play_clip(def.clip, {"speed": def.clip_speed, "start": def.clip_start})


func on_event(_event: StringName) -> void:
	pass


func update(_delta: float) -> void:
	if time >= clip_end:
		finish()


func on_input_released() -> void:
	pass


func on_cancel(_reason: StringName) -> void:
	pass


func on_finish() -> void:
	pass


## May a press of `slot_kind` (&"dodge", &"defense", &"light", &"heavy", &"technique") cancel this ability now?
func can_cancel_into(slot_kind: StringName) -> bool:
	return (slot_kind == &"dodge" or slot_kind == &"defense") and time >= cancel_at


## Is this ability currently granting invulnerability frames?
func has_iframes() -> bool:
	return ctx != null and ctx.invulnerable


## Defense abilities return true while they guard (see DefenseAbility).
func is_defending() -> bool:
	return false


# --- helpers for subclasses ----------------------------------------------------------------------

## Plays a clip on the caster's rig and schedules its events. Returns the
## remaining duration (s). opts: speed, start, mirror, mask, blend_in, root_motion.
func play_clip(clip_name: StringName, opts: Dictionary = {}) -> float:
	var c := AnimLibrary.get_clip(clip_name)
	if c == null:
		push_warning("BendingAbility %s: unknown clip %s" % [def.id if def else &"?", clip_name])
		clip = &""
		clip_end = time
		return 0.0
	var speed := maxf(float(opts.get("speed", 1.0)), 0.01)
	var start := clampf(float(opts.get("start", 0.0)), 0.0, 0.99)
	clip = clip_name
	var dur := c.length * (1.0 - start) / speed
	clip_end = time + dur
	var rec := c.event_time(&"recover")
	var cw := def.cancel_window if def and def.cancel_window >= 0.0 else (rec if rec >= 0.0 else 0.8)
	cancel_at = time + maxf(0.0, cw - start) * c.length / speed
	_virtual.clear()
	var has_rig := ctx != null and ctx.rig != null and is_instance_valid(ctx.rig) and ctx.rig.is_inside_tree()
	for e: Array in c.events:
		if float(e[0]) > start:
			# [ability time, event, virtual only (no rig), fired]
			_virtual.append([time + (float(e[0]) - start) * c.length / speed, e[1], not has_rig, false])
	if has_rig:
		ctx.rig.play_action(clip_name, opts)
	return dur


## Seconds from now until `event` of the current clip (INF if it already passed / none).
func time_to_event(event: StringName) -> float:
	for v: Array in _virtual:
		if v[1] == event and not bool(v[3]):
			return maxf(0.0, float(v[0]) - time)
	return INF


func finish() -> void:
	finished = true


## Fresh attack id (multi-hit abilities: a new id per hit that may re-hit).
func new_attack() -> int:
	attack_id = HitInfo.new_attack_id()
	return attack_id


func hit_data(overrides: Dictionary = {}) -> Dictionary:
	var h := def.hit.duplicate()
	for k: String in overrides:
		h[k] = overrides[k]
	return h


func param(key: String, fallback: Variant = null) -> Variant:
	return def.params.get(key, fallback)


## Feedback helper shortcut.
func sound(event: StringName, pos: Vector3, volume_db: float = 0.0) -> void:
	BendingFeedback.sound(ctx.element, event, pos, volume_db)


# --- internal (controller) ----------------------------------------------------------------------

func _tick(delta: float) -> void:
	time += delta
	# Virtual events: rig-less casters, and a safety net if the rig never fires
	# an event of this clip (e.g. it was replaced by another animation).
	var c := clip
	for v: Array in _virtual:
		if bool(v[3]):
			continue
		var late: float = 0.0 if bool(v[2]) else 0.12
		if time >= float(v[0]) + late:
			v[3] = true
			on_event(v[1])
			if finished or clip != c:
				return


func _rig_event(clip_name: StringName, event: StringName) -> void:
	if clip_name != clip:
		return
	for v: Array in _virtual:
		if v[1] == event and not bool(v[3]):
			v[3] = true
			on_event(event)
			return
