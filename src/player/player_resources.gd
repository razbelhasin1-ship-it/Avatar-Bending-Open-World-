class_name PlayerResources
extends Node
## Chi and Focus (docs/GAME_DESIGN.md §2) plus out-of-combat health regen.
##
## * Chi 0..100: spent by techniques, heavies and defense upkeep; regenerates
##   25/s after 0.6 s without bending (Water +20% near water). Light strikes
##   are free.
## * Focus 0..100: +6 light hit, +10 heavy hit, +15 parry; drains slowly out of
##   combat; the signature technique needs 100.
## * Health regenerates slowly out of combat (after 6 s without damage).
## Emits `changed(resource, value, max)`; the player re-emits it as its HUD
## `resource_changed` signal and Events.player_resource_changed.

signal changed(resource: StringName, value: float, max_value: float)

const CHI_MAX := 100.0
const FOCUS_MAX := 100.0
const CHI_REGEN := 25.0
const CHI_REGEN_DELAY := 0.6
const WATER_NEAR_BONUS := 1.2
const FOCUS_LIGHT := 6.0
const FOCUS_HEAVY := 10.0
const FOCUS_PARRY := 15.0
const FOCUS_DECAY := 2.0
const COMBAT_TIMEOUT := 6.0
const HEALTH_REGEN_DELAY := 6.0
## Fraction of max health per second.
const HEALTH_REGEN_RATE := 0.025

var chi := CHI_MAX
var focus := 0.0
var element: int = ElementDefs.Element.NONE
var health: HealthComponent = null
## Seconds since chi was last spent (regen delay).
var since_bending := 99.0
## Seconds since damage was dealt or taken (combat state).
var since_combat := 99.0
var since_damaged := 99.0
## Chi drained per second by a held defense / sustained technique (set by bending).
var upkeep := 0.0
## Set by the owner: callable(pos) -> bool "water nearby" (cached at 2 Hz).
var near_water := false
## Debug / tests: never run out.
var infinite_chi := false

var _near_water_timer := 0.0
var _emit_timer := 0.0
var _last_emitted := Vector2(-1, -1)


## When false the owner calls tick() itself (the player does, for ordering).
var auto_tick := true


func _physics_process(delta: float) -> void:
	if auto_tick:
		tick(delta)


func tick(delta: float) -> void:
	since_bending += delta
	since_combat += delta
	since_damaged += delta
	var chi_before := chi
	if upkeep > 0.0:
		_spend_raw(upkeep * delta)
		since_bending = 0.0
	elif since_bending >= CHI_REGEN_DELAY and chi < CHI_MAX:
		var rate := CHI_REGEN * (WATER_NEAR_BONUS if element == ElementDefs.Element.WATER and near_water else 1.0)
		chi = minf(CHI_MAX, chi + rate * delta)
	if since_combat > COMBAT_TIMEOUT and focus > 0.0:
		focus = maxf(0.0, focus - FOCUS_DECAY * delta)
	if health and not health.is_dead() and since_damaged > HEALTH_REGEN_DELAY and since_combat > HEALTH_REGEN_DELAY \
			and health.health < health.max_health:
		health.heal(health.max_health * HEALTH_REGEN_RATE * delta)
	_emit_timer -= delta
	if chi != chi_before or _emit_timer <= 0.0:
		_emit_changes()


func in_combat() -> bool:
	return since_combat < COMBAT_TIMEOUT


func mark_combat() -> void:
	since_combat = 0.0


func has_chi(amount: float) -> bool:
	return infinite_chi or chi + 0.001 >= amount


## Spends chi (false and nothing spent if insufficient).
func spend_chi(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if not has_chi(amount):
		return false
	_spend_raw(amount)
	since_bending = 0.0
	_emit_changes()
	return true


func _spend_raw(amount: float) -> void:
	if infinite_chi:
		return
	chi = maxf(0.0, chi - amount)


func set_chi(v: float) -> void:
	chi = clampf(v, 0.0, CHI_MAX)
	_emit_changes()


func add_focus(amount: float) -> void:
	if amount == 0.0:
		return
	focus = clampf(focus + amount, 0.0, FOCUS_MAX)
	_emit_changes()


func spend_focus(amount: float) -> bool:
	if focus + 0.001 < amount:
		return false
	focus = maxf(0.0, focus - amount)
	_emit_changes()
	return true


func set_focus(v: float) -> void:
	focus = clampf(v, 0.0, FOCUS_MAX)
	_emit_changes()


func get_resource(resource: StringName) -> Vector2:
	match resource:
		&"chi": return Vector2(chi, CHI_MAX)
		&"focus": return Vector2(focus, FOCUS_MAX)
		&"health":
			return Vector2(health.health, health.max_health) if health else Vector2.ZERO
	return Vector2.ZERO


func _emit_changes() -> void:
	_emit_timer = 0.25
	var now := Vector2(chi, focus)
	if now.is_equal_approx(_last_emitted):
		return
	if not is_equal_approx(now.x, _last_emitted.x):
		changed.emit(&"chi", chi, CHI_MAX)
	if not is_equal_approx(now.y, _last_emitted.y):
		changed.emit(&"focus", focus, FOCUS_MAX)
	_last_emitted = now
