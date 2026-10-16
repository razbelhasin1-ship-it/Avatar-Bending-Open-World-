class_name EnemyBrain
extends RefCounted
## Enemy decisions (docs/modules/enemies.md "AI"):
##
##   IDLE / PATROL --(awareness builds)--> ALERT (suspicious: stare, investigate)
##        --(spotted / hit / ally call)--> ALERT (spotted beat: "!" + point + call allies)
##        --> CHASE --> STRAFE (circle at the role's preferred range, always moving)
##        --(attack token granted)--> ATTACK (EnemyActions: telegraph -> strike -> recover)
##   reactive: BLOCK (shields / bending guards vs incoming projectiles, combo breaker),
##             DODGE (agile roles evade slow / heavy attacks)
##   hit:      STAGGER / KNOCKDOWN -> GETUP (i-frames) -> back to STRAFE
##   leash / lost target -> RETURN (heals) -> IDLE / PATROL
##   low health (rolled): FLEE (vanishes, half XP) or SURRENDER (kneels, hands over loot)
##
## At most AttackTokens.max_tokens() enemies attack the player at once; the others
## circle and pressure. Every state has a timeout (EnemyBase.STATE_TIMEOUT).

const S := EnemyBase.State
const THINK := 0.16
const ALLY_CALL_RADIUS := 22.0
const MELEE_ROLES: Array[StringName] = [&"brawler", &"skirmisher", &"defender", &"captain", &"beast"]

var e: EnemyBase
var target: Node3D = null
var strafe_sign := 1.0
var pending: Dictionary = {}

var _think := 0.0
var _strafe_switch := 2.0
var _breather := 0.0
var _approach_t := 0.0
var _patrol_i := 0
var _patrol_wait := 0.0
var _idle_look := 3.0
var _investigate_at := Vector3.INF
var _investigate_t := 0.0
var _lost_t := 0.0
var _spotted_beat := 0.0
var _block_hold := 0.0
var _getup_len := 0.7
var _stuck_t := 0.0
var _retreat_t := 0.0
var _feint_t := 0.0
var _seen_threats: Dictionary = {}
var _reengage_grace := 0.0
var _flee_t := 0.0
var _surrender_t := 0.0
var _counter := false
var _player_charge_seen := false


func _init(p_enemy: EnemyBase) -> void:
	e = p_enemy
	strafe_sign = 1.0 if e.rng.randf() < 0.5 else -1.0
	_strafe_switch = e.rng.randf_range(1.2, 3.0)


func start(s: S) -> void:
	pending = {}
	target = null
	e.set_state(s)
	e.stop_moving()


# --- main tick ------------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	_think -= delta
	_breather -= delta
	_strafe_switch -= delta
	_reengage_grace -= delta
	_retreat_t -= delta
	match e.state:
		S.IDLE: _idle(delta)
		S.PATROL: _patrol(delta)
		S.ALERT: _alert(delta)
		S.CHASE: _chase(delta)
		S.STRAFE: _strafe(delta)
		S.ATTACK: _attack(delta)
		S.BLOCK: _block(delta)
		S.DODGE: _dodge(delta)
		S.STAGGER: _stagger(delta)
		S.KNOCKDOWN: _knockdown(delta)
		S.GETUP: _getup(delta)
		S.RETURN: _return(delta)
		S.FLEE: _flee(delta)
		S.SURRENDER: _surrender(delta)
		S.RECOVER: _resume_combat()
	e.visual.combat = e.in_combat()
	if _valid(target) and e.in_combat() and e.state != S.DEAD:
		e.visual.look_at(BendingContext.target_point(target), 0.8)
	elif e.state in [S.IDLE, S.PATROL, S.RETURN]:
		e.visual.clear_look()


func get_patrol_index() -> int:
	return _patrol_i


func set_patrol_index(i: int) -> void:
	_patrol_i = maxi(i, 0) % maxi(e.patrol.size(), 1)


# --- calm states ----------------------------------------------------------------------------------------

func _idle(delta: float) -> void:
	e.stop_moving()
	e.face_dir = -e.home.basis.z
	e.face_rate = 120.0
	_idle_look -= delta
	if _idle_look <= 0.0:
		_idle_look = e.rng.randf_range(2.5, 6.0)
		var a := e.rng.randf_range(-1.2, 1.2)
		e.visual.look_at(e.global_position + Vector3.UP * 1.6 + (-e.home.basis.z).rotated(Vector3.UP, a) * 6.0, 0.5)
	_check_perception()


func _patrol(delta: float) -> void:
	if _check_perception():
		return
	if e.patrol.size() < 2:
		e.set_state(S.IDLE)
		return
	var p := e.patrol[_patrol_i % e.patrol.size()]
	if e.flat_distance(p) < 0.9:
		e.stop_moving()
		_patrol_wait -= delta
		if _patrol_wait <= 0.0:
			_patrol_i = (_patrol_i + 1) % e.patrol.size()
			_patrol_wait = e.rng.randf_range(1.5, 3.5)
		return
	e.face_dir = Vector3.ZERO
	e.face_rate = 300.0
	e.steer_to(p, float(e.archetype["speed"]["walk"]))
	_track_stuck(delta, p)


## Sight / hearing checks while calm. Returns true when the state changed.
func _check_perception() -> bool:
	var p := e.perception
	if p.is_spotted() and _valid(p.target):
		engage(p.target)
		return true
	if p.awareness > 0.3 and p.last_seen_pos.is_finite():
		investigate(p.last_seen_pos)
		return true
	if p.since_heard < 0.4 and p.heard_pos.is_finite():
		investigate(p.heard_pos)
		return true
	return false


func investigate(pos: Vector3) -> void:
	if e.state in [S.DEAD, S.SURRENDER, S.FLEE] or e.perception.engaged:
		return
	_investigate_at = pos
	_investigate_t = 0.0
	if e.state != S.ALERT:
		e.set_state(S.ALERT)


## Fight `t`. `via_ally`: called out by an ally (no extra call, shorter beat).
func engage(t: Node3D, via_ally: bool = false) -> void:
	if not _valid(t) or e.state in [S.DEAD, S.SURRENDER, S.FLEE] or e.surrendered:
		return
	target = t
	var first := not e.perception.engaged
	e.perception.alert_to(t, t.global_position)
	e.perception.engaged = true
	if not first:
		return
	e.alerted.emit(e, t)
	Events.enemy_alerted.emit(e)
	_spotted_beat = 0.35 if via_ally else 0.7
	if e.state in [S.IDLE, S.PATROL, S.ALERT, S.RETURN, S.CHASE, S.STRAFE]:
		e.set_state(S.ALERT)
		e.stop_moving()
		e.show_alert_mark()
		if not via_ally:
			if e.visual.is_creature():
				e.visual.play(&"roar")
			else:
				e.visual.play(&"enemy_spotted", {"blend_in": 0.08})
			e.bark(_spot_line())
	if not via_ally:
		for n in e.get_tree().get_nodes_in_group(&"enemy"):
			var o := n as EnemyBase
			if o == null or o == e or not o.is_alive() or o.dormant or o.perception.engaged:
				continue
			if o.faction != e.faction:
				continue
			if o.global_position.distance_to(e.global_position) <= ALLY_CALL_RADIUS:
				o.brain.engage(t, true)


func _spot_line() -> String:
	var lines: Dictionary = {
		&"fire_nation": ["Intruder!", "For the Fire Lord!", "Halt! Bender!"],
		&"bandits": ["Hey! Get them!", "Fresh meat!", "Over there!"],
		&"earth_rogues": ["We've got company!", "Crush them!"],
		&"pirates": ["Blades out, lads!", "A bender! Get 'em!"],
		&"dai_li": ["Detain them.", "You are under arrest."],
	}
	var l: Array = lines.get(e.archetype.get("faction", &""), [])
	return "" if l.is_empty() else String(l[e.rng.randi() % l.size()])


func _alert(delta: float) -> void:
	var p := e.perception
	if p.engaged:
		# Spotted beat: turn to the intruder, point and call out, then fight.
		e.stop_moving()
		if _valid(target):
			e.face_dir = e.flat_dir_to(target)
			e.face_rate = 600.0
		_spotted_beat -= delta
		if _spotted_beat <= 0.0:
			_to_combat()
		return
	# Suspicious: stare at the stimulus, walk over to it, give up after a while.
	if p.is_spotted() and _valid(p.target):
		engage(p.target)
		return
	_investigate_t += delta
	if p.can_see and p.last_seen_pos.is_finite():
		_investigate_at = p.last_seen_pos
		e.stop_moving()
	elif _investigate_at.is_finite() and e.flat_distance(_investigate_at) > 2.0 and _investigate_t > 0.8:
		e.steer_to(_investigate_at, float(e.archetype["speed"]["walk"]) * 1.2)
	else:
		e.stop_moving()
	if _investigate_at.is_finite():
		var d := _investigate_at - e.global_position
		d.y = 0.0
		if d.length() > 0.5:
			e.face_dir = d.normalized()
			e.face_rate = 300.0
	if _investigate_t > 7.0:
		_go_home()


# --- combat states ---------------------------------------------------------------------------------------

func _to_combat() -> void:
	if not _valid(target):
		_lose_target()
		return
	e.set_state(S.CHASE)


func _resume_combat() -> void:
	e.visual.tint(Color.WHITE, 0.0)
	if _valid(target) and e.perception.engaged:
		e.set_state(S.STRAFE)
		_breather = maxf(_breather, 0.35)
	else:
		_go_home()


func _engage_range() -> Vector2:
	return e.archetype.get("engage", Vector2(3.0, 5.0))


func _chase(delta: float) -> void:
	if not _valid(target):
		_lose_target()
		return
	if _leash_broken():
		_go_home()
		return
	var p := e.perception
	_lost_t = 0.0 if p.can_see else _lost_t + delta
	if _lost_t > 6.0:
		_lose_target()
		return
	var d := e.flat_distance_to(target)
	var er := _engage_range()
	if d <= er.y + 0.5 and (p.can_see or d < 4.0):
		e.set_state(S.STRAFE)
		return
	var goal := target.global_position if p.can_see or not p.last_seen_pos.is_finite() else p.last_seen_pos
	e.face_dir = Vector3.ZERO
	e.face_rate = 600.0
	e.steer_to(goal, float(e.archetype["speed"]["run"]))
	_track_stuck(delta, goal)
	if _think <= 0.0:
		_think = THINK
		_threats()


func _strafe(delta: float) -> void:
	if not _valid(target):
		_lose_target()
		return
	if _leash_broken():
		_go_home()
		return
	var p := e.perception
	_lost_t = 0.0 if p.can_see else _lost_t + delta
	if _lost_t > 5.0:
		e.set_state(S.CHASE)
		return
	var d := e.flat_distance_to(target)
	var er := _engage_range()
	if d > er.y + 4.0:
		e.set_state(S.CHASE)
		return
	var to := e.flat_dir_to(target)
	e.face_dir = to
	e.face_rate = 420.0
	# Close in for a granted attack.
	if not pending.is_empty():
		_approach_t -= delta
		var r: Vector2 = pending.get("range", Vector2(0, 2))
		if d <= r.y - 0.2 or (d <= r.y + 0.3 and _approach_t < 1.2):
			var a := pending
			pending = {}
			_start_attack(a)
			return
		if _approach_t <= 0.0:
			pending = {}
			AttackTokens.release(e, target)
			_breather = 0.6
		else:
			e.steer_dir(to, float(e.archetype["speed"]["run"]))
			return
	# Circle at the preferred range; never stand still.
	var radial := 0.0
	if d > er.y:
		radial = 1.0
	elif d < er.x:
		radial = -1.0 if e.role != &"ranged" else -1.4
	if _retreat_t > 0.0:
		radial = -1.2
	_feint_t -= delta
	if _feint_t <= 0.0 and e.role in MELEE_ROLES and AttackTokens.count(target) >= AttackTokens.max_tokens():
		_feint_t = e.rng.randf_range(1.6, 3.4) / maxf(float(e.archetype["aggression"]), 0.2)
		radial = 1.6
	var tangent := Vector3(-to.z, 0.0, to.x) * strafe_sign
	var dir := (to * radial + tangent * (1.0 if absf(radial) < 1.2 else 0.4)).normalized()
	var speed := float(e.archetype["speed"]["strafe"]) * (1.25 if absf(radial) > 1.0 else 1.0)
	e.steer_dir(dir, speed)
	if e.desired_velocity.length() < 0.2 or _strafe_switch <= 0.0:
		strafe_sign = -strafe_sign
		_strafe_switch = e.rng.randf_range(1.4, 3.2)
	if _think > 0.0:
		return
	_think = THINK + e.rng.randf() * 0.08
	if _threats():
		return
	if _breather > 0.0:
		return
	var a2 := _pick_attack(d, p.can_see)
	if a2.is_empty():
		return
	var priority := e.role == &"captain"
	if not AttackTokens.request(e, target, priority):
		return
	var r2: Vector2 = a2.get("range", Vector2(0, 2))
	if d > r2.y:
		pending = a2
		_approach_t = 2.4
	else:
		_start_attack(a2)


## Picks an attack by weight among the usable ones (close-in melee allowed).
func _pick_attack(d: float, los: bool) -> Dictionary:
	var total := 0.0
	var cands: Array = []
	for a: Dictionary in e.attacks:
		var w := float(a.get("weight", 1.0)) * maxf(float(e.archetype["aggression"]), 0.15)
		if w <= 0.0:
			continue
		var tag: StringName = a.get("tag", &"")
		if tag == &"cover":
			continue
		if tag == &"space" and d > 2.6:
			continue
		var ok := e.actions.can_use(a, d, los)
		if not ok and e.role in MELEE_ROLES and e.actions.cooldown_left(a.get("id", &"")) <= 0.0:
			var r: Vector2 = a.get("range", Vector2(0, 2))
			# Close-in: a melee attack slightly out of reach is still a choice (we walk in).
			ok = d > r.y and d < r.y + 5.0 and r.y < 6.0 and a.get("kind", &"") != &"bending" and (los or d < 4.0)
			w *= 0.6
		if ok:
			cands.append([a, w])
			total += w
	if cands.is_empty():
		return {}
	var roll := e.rng.randf() * total
	for c: Array in cands:
		roll -= float(c[1])
		if roll <= 0.0:
			return c[0]
	return cands[cands.size() - 1][0]


func _start_attack(a: Dictionary) -> void:
	e.stop_moving()
	if e.actions.start(a, target):
		e.set_state(S.ATTACK)
	else:
		AttackTokens.release(e, target)
		_breather = 0.4


func _attack(_delta: float) -> void:
	e.stop_moving()
	if _valid(target) and not e.actions.face_locked:
		e.face_dir = e.flat_dir_to(target)
		e.face_rate = 300.0 if e.actions.in_windup() else 120.0
	if not e.actions.is_busy() and e.state == S.ATTACK:
		# Finished without the callback (safety).
		AttackTokens.release(e, target)
		_resume_combat()


func on_attack_finished(a: Dictionary, _landed: bool) -> void:
	if e.state != S.ATTACK:
		AttackTokens.release(e, target)
		return
	var next_id: StringName = a.get("next", &"")
	if next_id != &"" and _valid(target) and e.rng.randf() < float(a.get("next_chance", 1.0)):
		for n: Dictionary in e.attacks:
			if n.get("id", &"") == next_id:
				var r: Vector2 = n.get("range", Vector2(0, 2.5))
				if e.flat_distance_to(target) <= r.y + 1.2 and e.actions.start(n, target):
					return
	AttackTokens.release(e, target)
	_breather = e.rng.randf_range(0.5, 1.3) / maxf(float(e.archetype["aggression"]), 0.3)
	if float(a.get("retreat", 0.0)) > 0.0:
		_retreat_t = 0.7
	_resume_combat()


func _block(delta: float) -> void:
	e.stop_moving()
	if _valid(target):
		e.face_dir = e.flat_dir_to(target)
		e.face_rate = 500.0
	_block_hold -= delta
	var bending := e.controller != null and e.controller.current is DefenseAbility
	if _block_hold <= 0.0:
		if bending:
			e.controller.release(&"defense")
		else:
			_resume_combat()
			return
	if bending and not e.controller.is_busy():
		_resume_combat()
	elif not bending and e.controller and not e.shield_up():
		_resume_combat()


func begin_block(hold: float) -> bool:
	var b: Dictionary = e.archetype["block"]
	if b.is_empty():
		return false
	if bool(b.get("bending", false)):
		if e.controller == null or e.controller.request(&"defense") != &"":
			return false
		var da := e.controller.current as DefenseAbility
		if da and not bool(b.get("parry", false)):
			# Enemies never get a frame-perfect parry on reflex.
			da.guard_time = DefenseAbility.PARRY_WINDOW + 0.01
	elif not e.shield_up():
		return false
	_block_hold = hold
	e.set_state(S.BLOCK)
	return true


func _dodge(_delta: float) -> void:
	if e.dodge_done():
		var counter := _counter
		_counter = false
		_resume_combat()
		if counter and _valid(target) and e.rng.randf() < 0.6:
			# Agile counter right after a clean evade.
			var a := _pick_attack(e.flat_distance_to(target), e.perception.can_see)
			if not a.is_empty() and AttackTokens.request(e, target, true):
				_start_attack(a)


func _stagger(delta: float) -> void:
	e.stun_t -= delta
	if e.stun_t <= 0.0:
		_resume_combat()


func _knockdown(delta: float) -> void:
	if e.airborne_reaction and not e.is_on_floor():
		return
	e.down_t -= delta
	if e.down_t <= 0.0:
		_getup_len = maxf(e.visual.get_up() * 0.85, 0.45)
		e.set_state(S.GETUP)


func _getup(_delta: float) -> void:
	if e.state_time >= _getup_len:
		_resume_combat()


# --- reactive defense -------------------------------------------------------------------------------------

## Incoming projectiles, slow player attacks, combo breakers. Returns true if it acted.
func _threats() -> bool:
	if not _valid(target) or e.actions.is_busy():
		return false
	var dodge: Dictionary = e.archetype["dodge"]
	var block: Dictionary = e.archetype["block"]
	# Projectiles about to arrive.
	for proj in BendingProjectile.incoming(e.global_position + Vector3.UP, 9.0, e.team):
		var id := proj.get_instance_id()
		if _seen_threats.has(id):
			continue
		var dist := proj.global_position.distance_to(e.global_position + Vector3.UP)
		var tti := dist / maxf(proj.velocity.length(), 1.0)
		if tti > 0.55:
			continue
		_seen_threats[id] = true
		if _seen_threats.size() > 32:
			_seen_threats.clear()
		var heavy := bool(proj.hit_template.get("heavy", false)) or proj.velocity.length() < 26.0
		if not block.is_empty() and e.rng.randf() < float(block.get("chance", 0.5)):
			if begin_block(0.7):
				return true
		if not dodge.is_empty() and heavy and e.rng.randf() < float(dodge.get("chance", 0.5)):
			var side := Vector3(-proj.velocity.z, 0, proj.velocity.x).normalized()
			if side.dot(e.global_position - proj.global_position) < 0.0:
				side = -side
			_counter = true
			if e.begin_dodge(side):
				return true
	# Slow player moves at close range (heavy charge release, techniques): agile roles evade.
	var pc := target as PlayerCharacter
	if pc != null and pc.controller != null and pc.controller.is_busy() and not dodge.is_empty():
		var cur := pc.controller.current
		var kind := pc.controller.current_kind()
		var close := e.flat_distance_to(pc) < 6.5
		var released := cur is ChargeAbility and (cur as ChargeAbility).released
		var slow := (kind == &"technique" and cur.time < 0.25) or (released and not _player_charge_seen)
		if released:
			_player_charge_seen = true
		if close and slow and e.rng.randf() < float(dodge.get("chance", 0.5)):
			var away := -e.flat_dir_to(pc)
			var side2 := Vector3(-away.z, 0, away.x) * (1.0 if e.rng.randf() < 0.5 else -1.0)
			_counter = true
			if e.begin_dodge((away * 0.6 + side2).normalized()):
				return true
	else:
		_player_charge_seen = false
	# Earth wall for cover when the player charges a heavy at range.
	if pc != null and pc.controller != null and pc.controller.current is ChargeAbility and (pc.controller.current as ChargeAbility).charging:
		for a: Dictionary in e.attacks:
			if a.get("tag", &"") == &"cover" and e.actions.can_use(a, e.flat_distance_to(pc), true):
				if AttackTokens.request(e, target, true):
					_start_attack(a)
					return true
	# Combo breaker: three hits in quick succession without being staggered.
	if e.recent_hits >= 3:
		e.recent_hits = 0
		if not block.is_empty() and begin_block(0.9):
			return true
		if not dodge.is_empty() and e.begin_dodge(-e.flat_dir_to(target)):
			return true
	return false


# --- damage hooks -----------------------------------------------------------------------------------------

func on_damaged(hit: HitInfo, aggressor: Node3D) -> void:
	if aggressor == null or not ("team" in aggressor) or int(aggressor.get("team")) == e.team:
		return
	if e.state == S.RETURN and _reengage_grace > 0.0:
		_reengage_grace = 0.0
	if not e.perception.engaged or target != aggressor:
		engage(aggressor)
		_spotted_beat = minf(_spotted_beat, 0.25)
	e.perception.last_seen_pos = aggressor.global_position
	e.perception.since_seen = 0.0
	if hit.is_projectile and e.state in [S.IDLE, S.PATROL]:
		e.face_dir = -hit.direction


## After a hit that did not kill: phase changes and low-health behaviour.
func after_hit(_hit: HitInfo, _reaction: int) -> void:
	var phases: Array = e.archetype.get("phases", [])
	if e.phase_index < phases.size() and e.health.ratio() <= float((phases[e.phase_index] as Dictionary).get("at", 0.5)):
		_enter_phase(phases[e.phase_index])
		return
	var lh: Dictionary = e.archetype.get("flee", {})
	if e.low_health_mode != &"" and not lh.is_empty() and e.health.ratio() <= float(lh.get("health", 0.2)):
		if e.low_health_mode == &"surrender":
			EnemyDamage.surrender(e)
		elif e.state != S.FLEE:
			_begin_flee()


func _enter_phase(ph: Dictionary) -> void:
	e.phase_index += 1
	for a: Dictionary in ph.get("attacks", []):
		e.attacks.append(a)
	e.bark(String(ph.get("shout", "")), 2.4)
	var burst := float(ph.get("burst", 0.0))
	var cry := {"id": &"war_cry", "kind": &"slam", "clip": &"enemy_war_cry", "windup": 0.25, "approach": 0.25, "telegraph": 0.35,
		"range": Vector2(0, 99), "cooldown": 0.0, "glint": &"", "ring": burst, "armor": 999.0, "element": e.element,
		"hit": {"damage": 6.0, "reaction": HitInfo.Reaction.KNOCKBACK, "force": 10.0, "lift": 2.0, "poise": 40.0},
		"shape": {"type": &"sphere", "reach": 0.0, "radius": maxf(burst, 0.5)}, "recover": 0.4, "shake": 0.35}
	e.actions.cancel(&"phase")
	if e.controller and e.controller.is_busy():
		e.controller.cancel_current(&"phase")
	e.stun_t = 0.0
	if e.actions.start(cry, target):
		e.set_state(S.ATTACK)
	Audio.play_sfx(&"gong", e.global_position, -6.0)


func _begin_flee() -> void:
	AttackTokens.release_all(e)
	e.actions.cancel(&"flee")
	_flee_t = 0.0
	e.set_state(S.FLEE)
	e.bark(["Run! Run!", "I'm out of here!", "Not worth it!"][e.rng.randi() % 3], 1.8)


func on_noise(pos: Vector3, source: Node3D) -> void:
	if e.state in [S.IDLE, S.PATROL, S.ALERT]:
		if source != null and source.is_in_group(&"player") and e.global_position.distance_to(pos) < 8.0:
			engage(source)
		else:
			investigate(pos)


# --- leaving combat ---------------------------------------------------------------------------------------

func _leash_broken() -> bool:
	var home := e.home.origin
	if e.flat_distance(home) > e.leash + 10.0:
		return true
	if _valid(target):
		var t := target.global_position - home
		t.y = 0.0
		if t.length() > e.leash + 22.0:
			return true
	return false


func _lose_target() -> void:
	AttackTokens.release_all(e)
	_go_home()


func _go_home() -> void:
	AttackTokens.release_all(e)
	pending = {}
	e.perception.forget()
	target = null
	_reengage_grace = 2.0
	_stuck_t = 0.0
	e.set_state(S.RETURN)


func _return(delta: float) -> void:
	var h := e.home.origin
	e.face_dir = Vector3.ZERO
	e.face_rate = 300.0
	e.health.heal(e.health.max_health * 0.12 * delta)
	if e.flat_distance(h) < 0.9:
		e.stop_moving()
		e.set_state(S.PATROL if e.patrol.size() >= 2 else S.IDLE)
		return
	e.steer_to(h, float(e.archetype["speed"]["walk"]) * 1.6)
	_track_stuck(delta, h)
	if _reengage_grace <= 0.0:
		_check_perception()


func _flee(delta: float) -> void:
	_flee_t += delta
	var away := -e.flat_dir_to(target) if _valid(target) else e.forward()
	e.face_dir = Vector3.ZERO
	e.steer_dir(away, float(e.archetype["speed"]["run"]) * 1.1)
	var far := not _valid(target) or e.flat_distance_to(target) > 26.0
	if (far and not e.perception.can_see) or _flee_t > 8.0:
		GameState.incr_stat("enemies_defeated")
		if e.rewards:
			EnemyRewards.grant(e, &"fled")
		e.defeated.emit(e, &"fled")
		e.vanish()
		return
	# Cornered: turn and fight to the end.
	if _flee_t > 1.2 and Vector2(e.velocity.x, e.velocity.z).length() < 0.6:
		e.low_health_mode = &""
		_resume_combat()


func _surrender(delta: float) -> void:
	e.stop_moving()
	_surrender_t += delta
	var far := not _valid(target) or e.flat_distance_to(target) > 40.0
	if _surrender_t > 30.0 or (far and _surrender_t > 4.0):
		e.vanish()


func on_state_timeout(s: int) -> void:
	match s:
		S.ATTACK:
			e.actions.cancel(&"timeout")
			_resume_combat()
		S.BLOCK:
			if e.controller and e.controller.is_busy():
				e.controller.cancel_current(&"timeout")
			_resume_combat()
		S.DODGE, S.STAGGER, S.GETUP, S.RECOVER:
			_resume_combat()
		S.KNOCKDOWN:
			e.airborne_reaction = false
			e.down_t = 0.0
			_getup_len = maxf(e.visual.get_up() * 0.85, 0.45)
			e.set_state(S.GETUP)
		S.ALERT:
			_go_home()
		S.RETURN:
			e.global_transform = e.home
			e.velocity = Vector3.ZERO
			e.set_state(S.PATROL if e.patrol.size() >= 2 else S.IDLE)
		S.FLEE:
			e.vanish()


## Stuck while walking somewhere: flip the strafe side, and when going home for a
## long time with the player far away, snap home.
func _track_stuck(delta: float, goal: Vector3) -> void:
	var moving := Vector2(e.velocity.x, e.velocity.z).length() > 0.35
	if e.desired_velocity.length() < 0.5 or moving:
		_stuck_t = maxf(0.0, _stuck_t - delta)
		return
	_stuck_t += delta
	if _stuck_t > 1.2:
		strafe_sign = -strafe_sign
	if _stuck_t > 4.0 and e.state == S.RETURN and not e.near_player(25.0):
		e.global_position = goal
		_stuck_t = 0.0


static func _valid(n: Node3D) -> bool:
	return n != null and is_instance_valid(n) and n.is_inside_tree() and Combat.is_alive(n)
