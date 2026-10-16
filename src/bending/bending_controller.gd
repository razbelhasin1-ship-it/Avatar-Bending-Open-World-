class_name BendingController
extends Node
## Runs a caster's bending: loadout slots, light combo chain windows, heavy
## tap/charge, defense hold, element dodge, 4 technique slots
## (GameState.equipped_abilities for the player), the signature (Focus 100),
## cooldowns, chi costs and cancel windows. Used by the player and by enemies.
##
##   var bc := BendingController.new()
##   body.add_child(bc)
##   bc.setup(ctx)                       # loads the element's core kit
##   bc.load_equipped()                  # player: techniques from GameState
##   var why := bc.request(&"light")     # &"" = started, &"busy" = try again (buffer), else failure reason
##   bc.release(&"heavy")                # button released (charge / hold)
##   bc.tick(delta)                      # every physics tick (the owner calls it)
##
## Slots: &"light", &"heavy", &"defense", &"dodge", &"technique_1".."technique_4", &"signature".
## Failure reasons: &"chi", &"focus", &"cooldown", &"empty", &"locked", &"busy" + ability reasons.

signal ability_started(ability: BendingAbility)
signal ability_ended(ability: BendingAbility, was_cancelled: bool)
signal ability_failed(ability_id: StringName, reason: StringName)

const TECHNIQUE_SLOTS: Array[StringName] = [&"technique_1", &"technique_2", &"technique_3", &"technique_4"]
## Seconds after a light strike ends during which the next press continues the chain.
const CHAIN_GRACE := 0.35

var ctx: BendingContext
var element: int = ElementDefs.Element.NONE
## slot -> AbilityDef
var loadout: Dictionary = {}
## ability id -> seconds left
var cooldowns: Dictionary = {}
var current: BendingAbility = null
## Emit Events.ability_used / ability_failed (player only, so enemies never touch the HUD).
var emit_events := false
## When false the owner calls tick(); otherwise _physics_process does.
var auto_tick := false
## Controller clock (s).
var clock := 0.0
## Light combo bookkeeping: last finished step and until when the chain continues.
var light_step := -1
var light_chain_until := -1.0
var last_failure: StringName = &""

var _rig_connected: HumanoidRig = null


func setup(p_ctx: BendingContext) -> void:
	# Bending-specific clips (also needed by rig-less casters' virtual timelines).
	BendingClips.ensure()
	ctx = p_ctx
	ctx.controller = self
	element = ctx.element
	emit_events = ctx.is_player()
	_connect_rig()
	load_core_kit()


func _connect_rig() -> void:
	if _rig_connected and is_instance_valid(_rig_connected) and _rig_connected.action_event.is_connected(_on_rig_event):
		_rig_connected.action_event.disconnect(_on_rig_event)
	_rig_connected = null
	if ctx.rig != null and is_instance_valid(ctx.rig):
		ctx.rig.action_event.connect(_on_rig_event)
		_rig_connected = ctx.rig


## Re-binds after the caster's rig was rebuilt (element change).
func set_rig(rig: HumanoidRig) -> void:
	ctx.rig = rig
	_connect_rig()


func load_core_kit() -> void:
	loadout.clear()
	var kit := AbilityRegistry.core_kit(element)
	for slot_name: StringName in kit:
		loadout[slot_name] = kit[slot_name]


## Player: fills technique slots from GameState.equipped_abilities (+ signature
## from the unlocked set).
func load_equipped() -> void:
	for i in TECHNIQUE_SLOTS.size():
		var id: StringName = GameState.equipped_abilities[i] if i < GameState.equipped_abilities.size() else &""
		var d := AbilityRegistry.get_def(id) if id != &"" else null
		if d != null and d.element == element and d.slot == AbilityDef.Slot.TECHNIQUE:
			loadout[TECHNIQUE_SLOTS[i]] = d
		else:
			loadout.erase(TECHNIQUE_SLOTS[i])
	loadout.erase(&"signature")
	for id: StringName in GameState.unlocked_abilities:
		var d := AbilityRegistry.get_def(id)
		if d != null and d.element == element and d.slot == AbilityDef.Slot.SIGNATURE:
			loadout[&"signature"] = d
			break


## Assigns a def to a slot directly (enemies, tests). null clears.
func set_slot(slot_name: StringName, d: AbilityDef) -> void:
	if d == null:
		loadout.erase(slot_name)
	else:
		loadout[slot_name] = d


func get_slot_def(slot_name: StringName) -> AbilityDef:
	return loadout.get(slot_name, null)


func _physics_process(delta: float) -> void:
	if auto_tick:
		tick(delta)


# --- requests ------------------------------------------------------------------------------

## Tries to start (or continue) the ability in `slot_name`. Returns &"" when it
## started, &"busy" when it cannot start *yet* (keep the press buffered), or a
## failure reason (already reported through ability_failed).
func request(slot_name: StringName) -> StringName:
	var d: AbilityDef = loadout.get(slot_name, null)
	if d == null:
		return _fail(&"", &"empty")
	var kind := _kind_of(d)
	# Toggle-style abilities (Air Scooter) take a second press of their own slot
	# (optional hook: `func on_repress() -> bool`, true = handled).
	if current != null and not current.finished and current.slot == slot_name and current.has_method(&"on_repress") \
			and bool(current.call(&"on_repress")):
		return &""
	# Continue a running light combo.
	if current != null and not current.finished:
		if kind == &"light" and current is ComboAbility and current.def == d:
			var combo := current as ComboAbility
			if combo.can_chain():
				combo.chain()
				return &""
			return &"busy"
		if not current.can_cancel_into(kind):
			return &"busy"
	var why := _check(d)
	if why != &"":
		return _fail(d.id, why)
	var ability := d.instantiate()
	if ability == null:
		return _fail(d.id, &"empty")
	ability.ctx = ctx
	ability.controller = self
	ability.slot = slot_name
	var custom := ability.can_use()
	if custom != &"":
		return _fail(d.id, custom)
	var cost := ability_chi_cost(ability)
	if cost > 0.0 and not ctx.has_chi(cost):
		return _fail(d.id, &"chi")
	if current != null and not current.finished:
		cancel_current(&"chain" if kind == &"light" else kind)
	if cost > 0.0:
		ctx.spend_chi(cost)
	if d.focus_cost > 0.0 and not ctx.spend_focus(d.focus_cost):
		return _fail(d.id, &"focus")
	_start(ability, slot_name)
	return &""


## The slot's button was released.
func release(slot_name: StringName) -> void:
	if current != null and current.slot == slot_name and not current.finished:
		current.input_held = false
		current.on_input_released()


## Checks chi/focus/cooldown without starting.
func can_start(slot_name: StringName) -> StringName:
	var d: AbilityDef = loadout.get(slot_name, null)
	if d == null:
		return &"empty"
	return _check(d)


func _check(d: AbilityDef) -> StringName:
	if cooldown_left(d.id) > 0.0:
		return &"cooldown"
	if d.chi_cost > 0.0 and not ctx.has_chi(d.chi_cost):
		return &"chi"
	if d.focus_cost > 0.0 and ctx.focus() + 0.001 < d.focus_cost:
		return &"focus"
	return &""


## Chi actually charged when `ability` starts (abilities may raise it, e.g.
## water without a source: +30%).
func ability_chi_cost(ability: BendingAbility) -> float:
	if ability.has_method("chi_cost"):
		return float(ability.call("chi_cost"))
	return ability.def.chi_cost


static func _kind_of(d: AbilityDef) -> StringName:
	match d.slot:
		AbilityDef.Slot.LIGHT: return &"light"
		AbilityDef.Slot.HEAVY: return &"heavy"
		AbilityDef.Slot.DEFENSE: return &"defense"
		AbilityDef.Slot.DODGE: return &"dodge"
		AbilityDef.Slot.SIGNATURE: return &"signature"
	return &"technique"


func _start(ability: BendingAbility, slot_name: StringName) -> void:
	ctx.reset_request()
	ability.attack_id = HitInfo.new_attack_id()
	current = ability
	if ability.def.cooldown > 0.0:
		cooldowns[ability.def.id] = ability.def.cooldown
	if ability is ComboAbility:
		var combo := ability as ComboAbility
		var next_step := light_step + 1 if clock <= light_chain_until else 0
		combo.first_step = next_step if next_step < combo.step_count() else 0
	ability.begin()
	if emit_events:
		Events.ability_used.emit(ability.def.id)
		GameState.incr_stat("abilities_used")
	ability_started.emit(ability)
	if ability.finished:
		_end(false)


func _fail(id: StringName, reason: StringName) -> StringName:
	last_failure = reason
	ability_failed.emit(id, reason)
	if emit_events:
		Events.ability_failed.emit(id, reason)
	return reason


## Interrupts the running ability (hit, death, dodge cancel).
func cancel_current(reason: StringName = &"cancel") -> void:
	if current == null:
		return
	var a := current
	a.cancelled = true
	a.finished = true
	a.on_cancel(reason)
	ctx.set_upkeep(0.0)
	if a is ComboAbility and reason != &"chain":
		light_step = -1
		light_chain_until = -1.0
	current = null
	ctx.reset_request()
	ability_ended.emit(a, true)


func _end(was_cancelled: bool) -> void:
	var a := current
	current = null
	if a == null:
		return
	if not was_cancelled:
		a.on_finish()
	ctx.set_upkeep(0.0)
	if a is ComboAbility:
		var combo := a as ComboAbility
		light_step = combo.step
		light_chain_until = clock + CHAIN_GRACE if not combo.is_last_step() else -1.0
	ctx.reset_request()
	ability_ended.emit(a, was_cancelled)


func is_busy() -> bool:
	return current != null and not current.finished


func current_kind() -> StringName:
	return _kind_of(current.def) if current != null else &""


# --- tick ----------------------------------------------------------------------------------

func tick(delta: float) -> void:
	clock += delta
	for id: StringName in cooldowns.keys():
		var left: float = cooldowns[id] - delta
		if left <= 0.0:
			cooldowns.erase(id)
		else:
			cooldowns[id] = left
	if current == null:
		return
	if not ctx.is_valid():
		cancel_current(&"invalid")
		return
	var a := current
	a._tick(delta)
	if current == a and not a.finished:
		a.update(delta)
	if current == a and (a.finished or a.time > a.max_time):
		if not a.finished:
			push_warning("BendingController: %s hit its safety timeout" % a.def.id)
		a.finished = true
		_end(false)


func _on_rig_event(clip_name: StringName, event: StringName) -> void:
	if current != null and not current.finished:
		var a := current
		a._rig_event(clip_name, event)
		if current == a and a.finished:
			_end(false)


# --- cooldown / HUD ------------------------------------------------------------------------

func cooldown_left(id: StringName) -> float:
	return float(cooldowns.get(id, 0.0))


func cooldown_ratio(id: StringName) -> float:
	var d := AbilityRegistry.get_def(id)
	if d == null or d.cooldown <= 0.0:
		return 0.0
	return clampf(cooldown_left(id) / d.cooldown, 0.0, 1.0)


func reset_cooldowns() -> void:
	cooldowns.clear()


## HUD slot dictionary for slot index i (0..3 techniques, 4 signature).
func get_slot_info(i: int) -> Dictionary:
	var slot_name: StringName = TECHNIQUE_SLOTS[i] if i >= 0 and i < 4 else (&"signature" if i == 4 else &"")
	var d: AbilityDef = loadout.get(slot_name, null)
	if d == null:
		return {}
	var available := _check(d) == &""
	return {"id": d.id, "name": d.display_name, "icon": d.icon, "element": d.element,
			"cooldown_ratio": cooldown_ratio(d.id), "cooldown_left": cooldown_left(d.id),
			"available": available, "cost": d.chi_cost if d.slot != AbilityDef.Slot.SIGNATURE else d.focus_cost}
