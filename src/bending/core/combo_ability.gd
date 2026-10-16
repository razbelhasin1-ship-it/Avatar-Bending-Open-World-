class_name ComboAbility
extends BendingAbility
## Light strike chain (3-4 hits). def.params["steps"] is an Array of steps:
##   {"clip": &"combo_fire_1", "speed": 1.0, "start": 0.15, "mirror": false,
##    "event": &"impact",        # clip event that delivers the strike
##    "chain_at": 0.62,          # normalized clip time from which the next press chains
##    "hit": {...},              # overrides def.hit for this step
##    "move": "free" | "brake" | "lunge", "lunge": 2.5}
## A press inside the chain window (strike .. clip end + CHAIN_GRACE) continues
## the chain; earlier presses are buffered by the input layer. Subclasses
## implement strike(step, data) to spawn the element's gameplay + VFX.

var step := 0
var first_step := 0
var struck := false
var chain_ready_at := INF
var _step_data: Dictionary = {}


func steps() -> Array:
	return def.params.get("steps", [])


func step_count() -> int:
	return steps().size()


func is_last_step() -> bool:
	return step >= step_count() - 1


func begin() -> void:
	_play_step(clampi(first_step, 0, maxi(step_count() - 1, 0)))


func _play_step(i: int) -> void:
	step = i
	struck = false
	new_attack()
	_step_data = steps()[i]
	var sd := _step_data
	var move := String(sd.get("move", "free"))
	ctx.move_mode = BendingContext.Move.FREE if move == "free" else BendingContext.Move.BRAKE
	ctx.move_speed_scale = float(sd.get("move_scale", 0.25))
	ctx.brake_rate = float(sd.get("brake", 30.0))
	if move == "lunge":
		ctx.move_mode = BendingContext.Move.DRIVE
		ctx.move_velocity = ctx.aim_flat() * float(sd.get("lunge", 2.0))
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 2400.0
	ctx.poise_armor = float(sd.get("armor", def.poise_armor))
	var clip_name: StringName = sd.get("clip", def.clip)
	var start := float(sd.get("start", 0.0))
	var speed := float(sd.get("speed", 1.0))
	play_clip(clip_name, {"speed": speed, "start": start, "mirror": bool(sd.get("mirror", false)), "blend_in": float(sd.get("blend_in", 0.05))})
	var c := AnimLibrary.get_clip(clip_name)
	var ev: StringName = sd.get("event", &"impact")
	var et := c.event_time(ev) if c else 0.5
	var chain_at := float(sd.get("chain_at", minf(et + 0.22, 0.85)))
	chain_ready_at = time + maxf(0.0, chain_at - start) * (c.length if c else 0.4) / speed
	on_step_begin(i, sd)


func on_event(event: StringName) -> void:
	if struck:
		return
	if event == StringName(_step_data.get("event", &"impact")):
		struck = true
		ctx.face_dir = Vector3.ZERO
		if String(_step_data.get("move", "free")) == "lunge":
			ctx.move_mode = BendingContext.Move.BRAKE
		strike(step, _step_data)


func update(_delta: float) -> void:
	if time >= clip_end:
		finish()


## May the next light press continue the chain now?
func can_chain() -> bool:
	return struck and not is_last_step() and time >= chain_ready_at


func chain() -> void:
	_play_step(step + 1)


func step_hit() -> Dictionary:
	var h := def.hit.duplicate()
	for k: String in (_step_data.get("hit", {}) as Dictionary):
		h[k] = _step_data["hit"][k]
	return h


## Override: spawn the strike's gameplay (projectile / sweep / cone) + VFX.
func strike(_i: int, _data: Dictionary) -> void:
	pass


## Override: per-step setup (e.g. ignite the striking fist).
func on_step_begin(_i: int, _data: Dictionary) -> void:
	pass
