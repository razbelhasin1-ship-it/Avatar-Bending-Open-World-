class_name TutorialDirector
extends Node
## Runs the training-grounds lessons (TutorialSteps): shows each step's card (TutorialPrompt),
## watches the player's real gameplay for the step's condition, drives the sparring partner
## per step and moves on with a short "well done" beat. Every step can be skipped by holding
## the interact button (no stuck state), and companion steps exist only when a companion does.
##
## Condition kinds (all measured on the real systems, never on button presses alone):
##   look      camera rotation (deg, mouse / stick / touch drag)
##   move      metres walked on the ground
##   sprint    seconds sprinting above run speed
##   jump      ground jumps (PlayerMotor.jumped)       air_jump   air jumps
##   glide     seconds gliding
##   dodge     dodges started (BendingController)
##   light     strikes of one light chain landing on training dummies (distinct attack ids)
##   heavy     a tapped heavy released                charge     a heavy released at >= 70 % charge
##   lockon    lock-on acquired                        block      a sparring fireball BLOCKED
##   parry     a sparring attack DEFLECTED (parry)     technique  the starter technique used
##   companion_call  Events.companion_command(&"call") mount  Events.mounted

signal step_started(step: Dictionary, index: int)
signal step_completed(step: Dictionary, index: int, skipped: bool)
signal finished(summary: Dictionary)

const STEP_GAP := 1.1
const SKIP_HOLD := 1.2
## Light hits further apart than this start a new chain (s).
const CHAIN_GAP := 1.7
const CHARGE_MIN := 0.7

var scene: PlayableScene
var player: PlayerCharacter
var prompt: TutorialPrompt
var bot: SparringBot
var element: int = ElementDefs.Element.WATER
var steps: Array[Dictionary] = []
var index := -1
var current: Dictionary = {}
var progress := 0.0
var running := false
var done := false
var completed: Array[StringName] = []
var skipped: Array[StringName] = []
## Seconds spent on the current step (game time).
var step_time := 0.0

var _advancing := false
var _skip_hold := 0.0
var _last_yaw := 0.0
var _last_pitch := 0.0
var _last_pos := Vector3.INF
var _chain_ids: Array[int] = []
var _chain_t := -100.0
var _light_id: StringName = &""
var _tech_id: StringName = &""


func setup(p_scene: PlayableScene, p_player: PlayerCharacter, p_prompt: TutorialPrompt, p_bot: SparringBot) -> void:
	scene = p_scene
	player = p_player
	prompt = p_prompt
	bot = p_bot
	element = player.element


## Builds the step list for the player's kit and starts the first lesson.
func start() -> void:
	var light_def := player.controller.get_slot_def(&"light")
	var n_light := 3
	if light_def and light_def.params.has("steps"):
		n_light = (light_def.params["steps"] as Array).size()
	_light_id = light_def.id if light_def else &""
	var tech := player.controller.get_slot_def(&"technique_1")
	_tech_id = tech.id if tech else &""
	steps = TutorialSteps.build(element, n_light, player.get_companion() != null, tech.display_name if tech else "your technique")
	player.motor.jumped.connect(_on_jumped)
	player.controller.ability_started.connect(_on_ability_started)
	player.controller.ability_ended.connect(_on_ability_ended)
	Events.hit_landed.connect(_on_hit_landed)
	Events.target_locked.connect(_on_target_locked)
	Events.ability_used.connect(_on_ability_used)
	Events.companion_command.connect(_on_companion_command)
	Events.mounted.connect(_on_mounted)
	if prompt:
		prompt.set_element(element)
	running = true
	index = -1
	_next()


func _exit_tree() -> void:
	for pair: Array in [[Events.hit_landed, _on_hit_landed], [Events.target_locked, _on_target_locked], [Events.ability_used, _on_ability_used],
			[Events.companion_command, _on_companion_command], [Events.mounted, _on_mounted]]:
		var s: Signal = pair[0]
		if s.is_connected(pair[1]):
			s.disconnect(pair[1])


func step_id() -> StringName:
	return StringName(current.get("id", &""))


func target() -> float:
	return float(current.get("target", 1.0))


func _next() -> void:
	index += 1
	if index >= steps.size():
		_finish()
		return
	current = steps[index]
	progress = 0.0
	step_time = 0.0
	_skip_hold = 0.0
	_chain_ids.clear()
	_chain_t = -100.0
	_last_pos = Vector3.INF
	if player.camera_rig:
		_last_yaw = player.camera_rig.yaw
		_last_pitch = player.camera_rig.pitch
	_apply_bot(StringName(current.get("bot", &"off")))
	if prompt:
		prompt.show_step(current, index, steps.size())
	step_started.emit(current, index)


func _finish() -> void:
	running = false
	done = true
	current = {}
	_apply_bot(&"off")
	if prompt:
		prompt.hide_card()
	finished.emit({"completed": completed.duplicate(), "skipped": skipped.duplicate(), "total": steps.size()})


## Adds progress to the current step (completes it at the target).
func add_progress(amount: float) -> void:
	if not running or _advancing:
		return
	set_progress(progress + amount)


func set_progress(value: float) -> void:
	if not running or _advancing:
		return
	progress = value
	if prompt:
		prompt.set_progress(progress)
	if progress >= target() - 1e-4:
		complete_step(false)


## Ends the current step (skipped = held the skip button / test). Moves on after a beat.
func complete_step(was_skipped: bool = false) -> void:
	if not running or _advancing or current.is_empty():
		return
	_advancing = true
	var id := step_id()
	if was_skipped:
		skipped.append(id)
	else:
		completed.append(id)
	if prompt:
		prompt.flash_done(was_skipped)
	UiFx.sound(&"ui_confirm" if not was_skipped else &"ui_back")
	step_completed.emit(current, index, was_skipped)
	await scene.wait_seconds(STEP_GAP)
	_advancing = false
	if running and is_inside_tree():
		_next()


# --- sparring partner ---------------------------------------------------------------------------------

func _apply_bot(mode: StringName) -> void:
	if bot == null or not is_instance_valid(bot):
		return
	match mode:
		&"fire":
			bot.mode = &"projectile"
			bot.interval = 2.6
			bot.telegraph = 0.65
			bot.attack_in(1.4, &"projectile")
		&"slow":
			bot.mode = &"projectile"
			bot.interval = 3.2
			bot.telegraph = 1.0
			bot.attack_in(1.8, &"projectile")
		_:
			bot.active = false


# --- polled conditions ----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not running or current.is_empty() or not is_instance_valid(player):
		return
	step_time += delta
	_poll_skip(delta)
	if _advancing:
		return
	match StringName(current.get("kind", &"")):
		&"look":
			if player.camera_rig:
				var dy := absf(wrapf(player.camera_rig.yaw - _last_yaw, -PI, PI))
				var dp := absf(player.camera_rig.pitch - _last_pitch)
				_last_yaw = player.camera_rig.yaw
				_last_pitch = player.camera_rig.pitch
				if dy + dp > 0.0001:
					add_progress(rad_to_deg(dy + dp))
		&"move":
			var p := player.global_position
			if _last_pos.is_finite() and player.motor.on_floor:
				var d := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
				if d < 1.0:
					add_progress(d)
			_last_pos = p
		&"sprint":
			var hv := Vector2(player.velocity.x, player.velocity.z).length()
			if player.input.sprinting and hv > player.profile.run_speed * 0.9:
				add_progress(delta)
		&"glide":
			if player.motor.gliding:
				add_progress(delta)


func _poll_skip(delta: float) -> void:
	var held := player.input.is_held(&"interact") or (InputMap.has_action(&"interact") and Input.is_action_pressed(&"interact"))
	if held and not _advancing:
		_skip_hold += delta
		if prompt:
			prompt.set_skip_progress(clampf(_skip_hold / SKIP_HOLD, 0.0, 1.0))
		if _skip_hold >= SKIP_HOLD:
			_skip_hold = 0.0
			complete_step(true)
	elif _skip_hold > 0.0:
		_skip_hold = 0.0
		if prompt:
			prompt.set_skip_progress(0.0)


# --- event conditions -----------------------------------------------------------------------------------

func _kind() -> StringName:
	return StringName(current.get("kind", &"")) if running else &""


func _on_jumped(kind: StringName) -> void:
	match _kind():
		&"jump":
			if kind == &"jump":
				add_progress(1.0)
		&"air_jump":
			if kind == &"air_jump":
				add_progress(1.0)


func _on_ability_started(a: BendingAbility) -> void:
	if _kind() == &"dodge" and a.def.slot == AbilityDef.Slot.DODGE:
		add_progress(1.0)


func _on_ability_ended(a: BendingAbility, _cancelled: bool) -> void:
	var strike := heavy_strike_of(a)
	if strike.is_empty():
		return       # not a heavy, or cancelled before the release: not a strike
	match _kind():
		&"heavy":
			if bool(strike["tapped"]):
				add_progress(1.0)
		&"charge":
			if not bool(strike["tapped"]) and float(strike["charge"]) >= CHARGE_MIN:
				add_progress(1.0)


## {tapped, charge} of a heavy-slot ability that released its strike, else {}. Heavies follow
## ChargeAbility's release contract (`released`, `tapped`, `charge`) whether or not they extend
## it: Earth Boulder is its own state machine (lift -> hold -> throw), so a class check alone
## never counted Earth's heavy or charged strike (the tutorial's lessons stalled for Earth).
static func heavy_strike_of(a: BendingAbility) -> Dictionary:
	if a == null or a.def == null or a.def.slot != AbilityDef.Slot.HEAVY:
		return {}
	var released: Variant = a.get(&"released")
	if not (released is bool) or not bool(released):
		return {}
	var tapped: Variant = a.get(&"tapped")
	var charge: Variant = a.get(&"charge")
	return {"tapped": bool(tapped) if tapped is bool else true, "charge": float(charge) if charge is float else 0.0}


func _on_hit_landed(hit: HitInfo, target_node: Node, result: int) -> void:
	match _kind():
		&"light":
			if target_node is TrainingDummy and hit.ability_id == _light_id and (result == Combat.Result.HIT or result == Combat.Result.KILLED):
				if step_time - _chain_t > CHAIN_GAP:
					_chain_ids.clear()
				_chain_t = step_time
				if not _chain_ids.has(hit.attack_id):
					_chain_ids.append(hit.attack_id)
				set_progress(float(_chain_ids.size()))
		&"block":
			if _is_player_side(target_node) and result == Combat.Result.BLOCKED:
				add_progress(1.0)
			elif _is_player_side(target_node) and result == Combat.Result.DEFLECTED:
				add_progress(1.0)      # a parry is a perfect block
		&"parry":
			if _is_player_side(target_node) and result == Combat.Result.DEFLECTED:
				add_progress(1.0)


func _is_player_side(n: Node) -> bool:
	if n == player:
		return true
	return n is BendingConstruct and (n as BendingConstruct).follow == player


func _on_target_locked(_t: Node3D) -> void:
	if _kind() == &"lockon":
		add_progress(1.0)


func _on_ability_used(id: StringName) -> void:
	if _kind() == &"technique" and (id == _tech_id or _tech_id == &""):
		add_progress(1.0)


func _on_companion_command(command: StringName) -> void:
	if _kind() == &"companion_call" and command == &"call":
		add_progress(1.0)


func _on_mounted(_m: Node3D) -> void:
	if _kind() == &"mount":
		add_progress(1.0)
