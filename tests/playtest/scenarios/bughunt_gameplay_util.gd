extends RefCounted
## bughunt_gameplay helpers (not a scenario): an engine-error collector (Logger), a random
## "monkey" that plays through InputMap actions only (the same path as a keyboard / pad /
## touch player), and a watchdog of gameplay invariants checked every physics frame.
##
##   var U := preload("res://tests/playtest/scenarios/bughunt_gameplay_util.gd")
##   var log := U.ErrorLog.install()
##   var watch := U.Watch.new(tree, player)
##   var monkey := U.Monkey.new(playtest, player, rng)
##   loop: monkey.step(dt); watch.tick(dt)
##   watch.report() / log.report()


## Collects every engine error / warning (script errors, push_error/push_warning, engine
## checks) with the script backtrace. Treat each one as a bug.
class ErrorLog extends Logger:
	var mutex := Mutex.new()
	var errors: Array[String] = []
	var warnings: Array[String] = []
	## message -> count (dedupe for the report)
	var counts: Dictionary = {}
	var enabled := true

	static func install() -> ErrorLog:
		var l := ErrorLog.new()
		OS.add_logger(l)
		return l

	func uninstall() -> void:
		OS.remove_logger(self)

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if not enabled:
			return
		var msg := "%s (%s:%d %s)" % [rationale if rationale != "" else code, file.get_file(), line, function]
		var bt := ""
		for b in script_backtraces:
			if b != null and not b.is_empty():
				bt += "\n" + b.format(4, 2)
		mutex.lock()
		var key := msg
		counts[key] = int(counts.get(key, 0)) + 1
		if int(counts[key]) <= 3:
			if error_type == ERROR_TYPE_WARNING:
				warnings.append(msg + bt)
			else:
				errors.append(msg + bt)
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func total() -> int:
		var n := 0
		for k: String in counts:
			n += int(counts[k])
		return n

	func report() -> String:
		var lines: Array[String] = []
		mutex.lock()
		for k: String in counts:
			lines.append("  x%d  %s" % [int(counts[k]), k])
		mutex.unlock()
		return "\n".join(lines)


## Random play through InputMap actions (Input.action_press + an InputEventAction, exactly
## like Playtest.hold), with held buttons released on their own deadlines. Mounted / UI /
## menu intents are included when `allow_*` say so.
class Monkey extends RefCounted:
	var p: Playtest
	var pl: PlayerCharacter
	var rng: RandomNumberGenerator
	var clock := 0.0
	## action -> release time (game s)
	var held: Dictionary = {}
	var next_decision := 0.0
	var allow_mount := true
	var allow_ui := true
	var allow_pause := true
	var allow_lock := true
	## Intent counters (report).
	var counts: Dictionary = {}
	var _move_until := 0.0
	var _ui_close_at := -1.0
	var _ui_close_action: StringName = &""

	func _init(pt: Playtest, player: PlayerCharacter, r: RandomNumberGenerator) -> void:
		p = pt
		pl = player
		rng = r

	func press(a: StringName, seconds: float) -> void:
		if not InputMap.has_action(a):
			return
		if not held.has(a):
			p.hold(a)
		held[a] = maxf(float(held.get(a, 0.0)), clock + seconds)
		counts[a] = int(counts.get(a, 0)) + 1

	func release_all() -> void:
		for a: StringName in held.keys():
			p.release(a)
		held.clear()

	func _note(k: String) -> void:
		counts[k] = int(counts.get(k, 0)) + 1

	## One physics tick of play. `dt` = game seconds since the last call.
	func step(dt: float) -> void:
		clock += dt
		for a: StringName in held.keys():
			if clock >= float(held[a]):
				p.release(a)
				held.erase(a)
		# UI opened by us: close it after a moment (the menus pause the tree).
		if _ui_close_at >= 0.0 and clock >= _ui_close_at:
			_ui_close_at = -1.0
			p.hold(_ui_close_action)
			p.release(_ui_close_action)
			_note("ui_close_" + String(_ui_close_action))
		if clock < next_decision:
			return
		next_decision = clock + rng.randf_range(0.04, 0.22)
		var mounted := pl.get_state() == PlayerCharacter.State.MOUNTED
		# Movement: a fresh random stick every so often (sometimes idle).
		if clock >= _move_until:
			_move_until = clock + rng.randf_range(0.2, 1.6)
			for a: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right"]:
				if held.has(a):
					p.release(a)
					held.erase(a)
			if rng.randf() < 0.8:
				var dirs: Array = [[&"move_forward"], [&"move_forward", &"move_left"], [&"move_forward", &"move_right"], [&"move_left"],
					[&"move_right"], [&"move_back"], [&"move_back", &"move_left"], [&"move_forward"], [&"move_forward"]]
				for a: StringName in dirs[rng.randi() % dirs.size()]:
					press(a, _move_until - clock)
			if rng.randf() < 0.35:
				press(&"sprint", rng.randf_range(0.2, 1.5))
		if rng.randf() < 0.3:
			p.look(rng.randf_range(-160.0, 160.0), rng.randf_range(-40.0, 40.0))
		# Seek a fight: lock onto someone when nothing is locked (the camera then faces them and
		# "forward" walks into the fight).
		if allow_lock and not mounted and pl.get_lock_target() == null and rng.randf() < 0.06:
			press(&"lock_on", 0.05)
		var r := rng.randf()
		if mounted:
			# Riding: steer, climb / dive, boost, burrow, sometimes hop off.
			if r < 0.25:
				press(&"jump", rng.randf_range(0.05, 1.8))
			elif r < 0.4:
				press(&"descend", rng.randf_range(0.05, 1.5))
			elif r < 0.43:
				press(&"mount", 0.06)
				_note("dismount_try")
			elif r < 0.45:
				press(&"interact", 0.06)
			elif r < 0.5:
				press(&"attack_light", 0.06)   # must be ignored while riding
			elif r < 0.52 and allow_ui:
				_open_ui()
			return
		if r < 0.22:
			press(&"attack_light", rng.randf_range(0.03, 0.1))
		elif r < 0.32:
			press(&"attack_heavy", rng.randf_range(0.05, 2.0) if rng.randf() < 0.6 else rng.randf_range(0.03, 0.12))
		elif r < 0.40:
			press(&"block", rng.randf_range(0.03, 1.8))
		elif r < 0.48:
			press(&"dodge", 0.06)
		elif r < 0.58:
			var a: StringName = [&"ability_1", &"ability_2", &"ability_3", &"ability_4"][rng.randi() % 4]
			press(a, rng.randf_range(0.04, 2.2) if rng.randf() < 0.4 else 0.07)
		elif r < 0.61:
			press(&"ability_special", rng.randf_range(0.05, 1.0))
		elif r < 0.70:
			press(&"jump", rng.randf_range(0.05, 1.2))
		elif r < 0.73 and allow_lock:
			press(&"lock_on", 0.05)
		elif r < 0.75:
			press(&"interact", 0.06)
		elif r < 0.79 and allow_mount:
			press(&"mount", 0.06)
			_note("mount_try")
		elif r < 0.81 and allow_mount:
			press(&"companion_call", 0.06)
		elif r < 0.825 and allow_ui:
			_open_ui()
		elif r < 0.83 and allow_pause:
			p.hold(&"pause")
			p.release(&"pause")
			_note("pause")
			_ui_close_at = clock + rng.randf_range(0.05, 0.6)
			_ui_close_action = &"pause"

	func _open_ui() -> void:
		var a: StringName = [&"open_map", &"open_skills", &"open_journal"][rng.randi() % 3]
		if not InputMap.has_action(a):
			return
		p.hold(a)
		p.release(a)
		_note(String(a))
		_ui_close_at = clock + rng.randf_range(0.05, 0.8)
		_ui_close_action = [&"ui_cancel", a, &"pause"][rng.randi() % 3]


## Gameplay invariants, checked every physics frame. Violations are deduplicated by kind
## (first few kept with context) and turned into playtest failures by the scenario.
class Watch extends RefCounted:
	const S := PlayerCharacter.State
	var tree: SceneTree
	var pl: PlayerCharacter
	var clock := 0.0
	var violations: Dictionary = {}     # kind -> count
	var samples: Dictionary = {}        # kind -> Array[String]
	## Arena floor (min y) or NAN in the world (terrain relative).
	var floor_y := -3.0
	var world_mode := false
	var max_live_projectiles := 0
	var max_live_constructs := 0
	var max_fx_alive := 0
	var max_enemies := 0
	var states_seen: Dictionary = {}
	var abilities_seen: Dictionary = {}
	var hits_landed := 0
	var hits_taken := 0
	var deaths := 0
	var mounts := 0
	var node_samples: Array = []
	var _idle_frames := 0
	var _busy_free_frames := 0
	var _dead_mismatch := 0
	var _slow_since_us := -1
	var _hits: Dictionary = {}          # "attack_id:target_id" -> clock
	var _hit_order: Array[String] = []
	var _cd_last: Dictionary = {}       # ability id -> clock of the last start
	var _loops_first: Dictionary = {}   # loop id -> clock first seen
	var _mount_desync := 0.0
	var _ride_desync := 0.0
	var _next_node_sample := 0.0
	var companion: Companion = null

	func _init(t: SceneTree, player: PlayerCharacter) -> void:
		tree = t
		pl = player
		Events.hit_landed.connect(_on_hit)
		Events.ability_used.connect(_on_ability_used)
		Events.player_died.connect(_on_died)
		Events.mounted.connect(_on_mounted)
		Events.player_damaged.connect(_on_damaged)

	## Disconnects from the event bus (call before the player goes away).
	func stop() -> void:
		for pair: Array in [[Events.hit_landed, _on_hit], [Events.ability_used, _on_ability_used], [Events.player_died, _on_died],
				[Events.mounted, _on_mounted], [Events.player_damaged, _on_damaged]]:
			if (pair[0] as Signal).is_connected(pair[1]):
				(pair[0] as Signal).disconnect(pair[1])
		pl = null

	func _on_died() -> void:
		deaths += 1

	func _on_mounted(_m: Node3D) -> void:
		mounts += 1

	func _on_damaged(_a: float, _h: HitInfo) -> void:
		hits_taken += 1

	func flag(kind: String, detail: String) -> void:
		violations[kind] = int(violations.get(kind, 0)) + 1
		var arr: Array = samples.get(kind, [])
		if arr.size() < 4:
			arr.append("t=%.2f %s | %s" % [clock, detail, context()])
			samples[kind] = arr
			print("[bughunt] VIOLATION %s: %s" % [kind, arr.back()])

	func context() -> String:
		if pl == null or not is_instance_valid(pl):
			return "no player"
		var cur := pl.controller.current
		return "state=%s st=%.2f to=%.2f ab=%s(%.2f/%.2f) pos=%s v=%.1f chi=%.0f foc=%.0f hp=%.0f layer=%d" % [
			pl.get_state_name(), pl.states.state_time, pl.states.timeout,
			String(cur.def.id) if cur != null else "-", cur.time if cur != null else 0.0, cur.max_time if cur != null else 0.0,
			str(pl.global_position.snapped(Vector3.ONE * 0.1)), pl.velocity.length(), pl.resources.chi, pl.resources.focus,
			pl.health.health, pl.collision_layer]

	# --- per-frame ----------------------------------------------------------------------------

	func tick(dt: float) -> void:
		clock += dt
		if pl == null or not is_instance_valid(pl) or not pl.is_inside_tree():
			return
		_player_checks()
		_ability_checks()
		_resource_checks()
		_time_checks()
		_pool_checks()
		_enemy_checks()
		_companion_checks(dt)
		if clock >= _next_node_sample:
			_next_node_sample = clock + 20.0
			node_samples.append([snappedf(clock, 0.1), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT))])

	func _player_checks() -> void:
		var st := pl.get_state()
		var name := pl.get_state_name()
		states_seen[name] = int(states_seen.get(name, 0)) + 1
		var t := pl.states.state_time
		var to := pl.states.timeout
		var cap := INF
		match st:
			S.HITSTUN: cap = 2.15
			S.KNOCKED_DOWN: cap = 4.15
			S.GETUP: cap = 1.35
			S.INTERACTING: cap = 10.2
			S.DEAD: cap = 12.0
			S.AIRBORNE: cap = 45.0
			S.DODGE, S.ACTION, S.DEFEND, S.CINEMATIC: cap = to + 0.25
		if t > cap:
			flag("state_overrun_" + name, "state %s for %.2f s (cap %.2f)" % [name, t, cap])
		var pos := pl.global_position
		if not pos.is_finite() or not pl.velocity.is_finite():
			flag("non_finite", "pos %s vel %s" % [pos, pl.velocity])
			return
		if pl.velocity.length() > 140.0:
			flag("velocity_spike", "v=%.1f" % pl.velocity.length())
		if st != S.MOUNTED:
			if pl.collision_layer != Layers.PLAYER or pl.collision_mask != (Layers.SOLID | Layers.ENEMY | Layers.NPC):
				flag("collision_layers", "layer %d mask %d while %s" % [pl.collision_layer, pl.collision_mask, name])
			if pl.mount_node != null or pl.mount_seat != null:
				flag("stale_mount_refs", "mount refs while %s" % name)
		var ground := floor_y
		if world_mode:
			ground = WorldData.get_height(pos.x, pos.z) - 4.0
		if st != S.MOUNTED and pos.y < ground:
			flag("below_ground", "y=%.2f ground=%.2f" % [pos.y, ground])
		# Camera: no leftover mount / cinematic framing in free play.
		if pl.camera_rig and pl.states.is_free() and t > 1.0:
			var ov: Variant = pl.camera_rig.get("_override")
			if ov != null and is_instance_valid(ov):
				flag("camera_override_left", "override %s while %s" % [str(ov), name])
			if pl.camera_rig.mode != &"default" and pl.camera_rig.mode != &"lock":
				flag("camera_mode_left", "camera mode %s while %s" % [pl.camera_rig.mode, name])
		# Death bookkeeping.
		var dead := pl.health.is_dead()
		if dead != (st == S.DEAD):
			_dead_mismatch += 1
			if _dead_mismatch > 3:
				flag("death_state_mismatch", "health dead=%s state=%s" % [dead, name])
		else:
			_dead_mismatch = 0

	func _ability_checks() -> void:
		var c := pl.controller
		var cur := c.current
		if cur != null:
			abilities_seen[cur.def.id] = true
			if cur.time > cur.max_time + 0.05:
				flag("ability_overrun", "%s time %.2f > max %.2f" % [cur.def.id, cur.time, cur.max_time])
		var st := pl.get_state()
		if c.is_busy() and pl.states.is_free():
			_busy_free_frames += 1
			if _busy_free_frames > 3:
				flag("ability_running_in_free_state", "%s running while %s" % [cur.def.id, pl.get_state_name()])
		else:
			_busy_free_frames = 0
		if c.is_busy() and st in [S.DEAD, S.MOUNTED, S.CINEMATIC, S.HITSTUN, S.KNOCKED_DOWN, S.GETUP, S.INTERACTING]:
			flag("ability_running_in_" + pl.get_state_name(), "%s running" % cur.def.id)
		if c.is_busy():
			_idle_frames = 0
			return
		_idle_frames += 1
		if _idle_frames < 3:
			return
		var ctx := pl.ctx
		if ctx.invulnerable:
			flag("iframes_leak", "ctx.invulnerable with no ability")
		if not is_equal_approx(ctx.damage_reduction, ctx.base_damage_reduction):
			flag("damage_reduction_leak", "dr %.2f base %.2f" % [ctx.damage_reduction, ctx.base_damage_reduction])
		if not is_equal_approx(ctx.poise_armor, ctx.base_poise_armor):
			flag("poise_armor_leak", "armor %.1f base %.1f" % [ctx.poise_armor, ctx.base_poise_armor])
		if ctx.gravity_scale != 1.0:
			flag("gravity_leak", "gravity %.2f" % ctx.gravity_scale)
		if pl.resources.upkeep > 0.0 and not _toggle_upkeep():
			flag("upkeep_leak", "upkeep %.2f/s with no ability" % pl.resources.upkeep)

	## Toggles (Earth Armor) keep an upkeep running after their cast.
	func _toggle_upkeep() -> bool:
		return pl.ctx.base_damage_reduction > 0.0 or pl.ctx.base_poise_armor > 0.0 or pl.has_meta(&"earth_armor")

	func _resource_checks() -> void:
		var r := pl.resources
		if r.chi < -0.001 or r.chi > PlayerResources.CHI_MAX + 0.001 or not is_finite(r.chi):
			flag("chi_range", "chi %.3f" % r.chi)
		if r.focus < -0.001 or r.focus > PlayerResources.FOCUS_MAX + 0.001 or not is_finite(r.focus):
			flag("focus_range", "focus %.3f" % r.focus)
		var h := pl.health
		if h.health < -0.001 or h.health > h.max_health + 0.001 or not is_finite(h.health):
			flag("health_range", "health %.3f / %.3f" % [h.health, h.max_health])

	func _time_checks() -> void:
		if Engine.time_scale < 0.999:
			var now := Time.get_ticks_usec()
			if _slow_since_us < 0:
				_slow_since_us = now
			elif now - _slow_since_us > int((TimeDilation.MAX_DURATION + 0.4) * 1000000.0):
				flag("time_scale_stuck", "Engine.time_scale %.3f for %.2f s real (dilation active %s)" % [Engine.time_scale,
						float(now - _slow_since_us) / 1000000.0, TimeDilation.is_active()])
				_slow_since_us = now
		else:
			_slow_since_us = -1
		if not TimeDilation.is_active() and Engine.time_scale < 0.999 and not tree.paused:
			flag("time_scale_leak", "time_scale %.3f with no dilation request" % Engine.time_scale)

	func _pool_checks() -> void:
		var lp := 0
		for pr in BendingProjectile.live:
			if is_instance_valid(pr) and pr.alive:
				lp += 1
				if pr.age > pr.max_age + 0.5:
					flag("projectile_overage", "%s age %.1f > %.1f" % [pr.ability_id, pr.age, pr.max_age])
		max_live_projectiles = maxi(max_live_projectiles, lp)
		if lp > 90:
			flag("projectiles_unbounded", "%d live projectiles" % lp)
		max_live_constructs = maxi(max_live_constructs, BendingConstruct.live.size())
		if BendingConstruct.live.size() > 40:
			flag("constructs_unbounded", "%d live constructs" % BendingConstruct.live.size())
		var fx := FxLib.total_alive()
		max_fx_alive = maxi(max_fx_alive, fx)
		# Loops: a bending loop alive for over 40 s of game time is stuck (shield / charge / tornado loops are short).
		for v: Dictionary in Audio.voices.snapshot():
			var id := int(v.get("loop", 0))
			if id == 0 or String(v.get("sound", "")).begins_with("amb_") or String(v.get("sound", "")).begins_with("music"):
				continue
			if not _loops_first.has(id):
				_loops_first[id] = clock
			elif clock - float(_loops_first[id]) > 40.0:
				flag("audio_loop_stuck", "loop %s alive %.0f s" % [v.get("sound", ""), clock - float(_loops_first[id])])
				_loops_first[id] = clock

	func _enemy_checks() -> void:
		var n := 0
		var attacking := 0
		for e: Node in tree.get_nodes_in_group(&"enemy"):
			var en := e as EnemyBase
			if en == null or not is_instance_valid(en) or not en.is_inside_tree():
				continue
			n += 1
			if en.dormant:
				continue
			var cap: float = EnemyBase.STATE_TIMEOUT.get(en.state, INF)
			if en.state_time > cap + 0.25:
				flag("enemy_state_overrun_" + en.get_state_name(), "%s %s %.2f s" % [en.display_name, en.get_state_name(), en.state_time])
			if not en.global_position.is_finite() or not en.velocity.is_finite():
				flag("enemy_non_finite", "%s at %s" % [en.display_name, en.global_position])
				continue
			var gy := -3.0 if not world_mode else WorldData.get_height(en.global_position.x, en.global_position.z) - 6.5
			if en.global_position.y < gy:
				flag("enemy_below_ground", "%s y %.2f" % [en.display_name, en.global_position.y])
			if en.state == EnemyBase.State.ATTACK:
				attacking += 1
			if en.controller and en.controller.current != null and en.controller.current.time > en.controller.current.max_time + 0.05:
				flag("enemy_ability_overrun", "%s %s" % [en.display_name, en.controller.current.def.id])
		max_enemies = maxi(max_enemies, n)
		if attacking > AttackTokens.max_tokens() + 1:
			flag("too_many_attackers", "%d attacking (tokens %d)" % [attacking, AttackTokens.max_tokens()])

	func _companion_checks(dt: float) -> void:
		var c := companion
		if c == null or not is_instance_valid(c):
			c = tree.get_first_node_in_group(&"companion") as Companion
			companion = c
		if c == null or not c.is_inside_tree():
			return
		if Companion.MODE_TIMEOUT.has(c.mode) and c.mode_time > float(Companion.MODE_TIMEOUT[c.mode]) + 0.25:
			flag("companion_mode_overrun_" + c.get_mode_name(), "%.2f s" % c.mode_time)
		if not c.global_position.is_finite():
			flag("companion_non_finite", str(c.global_position))
		var mounted := pl.get_state() == S.MOUNTED
		var ridden := c.is_ridden()
		_mount_desync = _mount_desync + dt if mounted and not ridden else 0.0
		_ride_desync = _ride_desync + dt if ridden and not mounted and pl.get_state() != S.CINEMATIC else 0.0
		if _mount_desync > 1.0:
			flag("mounted_without_ridden_companion", "companion mode %s" % c.get_mode_name())
			_mount_desync = 0.0
		if _ride_desync > 3.5:
			flag("companion_ridden_without_rider", "companion mode %s, player %s" % [c.get_mode_name(), pl.get_state_name()])
			_ride_desync = 0.0

	# --- events -------------------------------------------------------------------------------

	func _on_hit(hit: HitInfo, target: Node, result: int) -> void:
		if pl == null or not is_instance_valid(pl):
			return
		if result != Combat.Result.HIT and result != Combat.Result.KILLED:
			return
		if hit.source == pl:
			hits_landed += 1
		if hit.attack_id == 0 or target == null:
			return
		var key := "%d:%d" % [hit.attack_id, target.get_instance_id()]
		if _hits.has(key):
			flag("double_hit", "attack %d (%s) hit %s twice" % [hit.attack_id, hit.ability_id, target.name])
		_hits[key] = clock
		_hit_order.append(key)
		if _hit_order.size() > 4000:
			_hits.erase(_hit_order.pop_front())
		# The player's melee / area hits while dead / mounted / in a cinematic: a leaked ability.
		# (The companion's assist is credited to the player and may finish its move: allowed.)
		if hit.source == pl and not hit.is_projectile and pl.get_state() in [S.DEAD, S.CINEMATIC] \
				and not String(hit.ability_id).begins_with("companion_"):
			flag("hit_from_inactive_player", "%s while %s" % [hit.ability_id, pl.get_state_name()])

	func _on_ability_used(id: StringName) -> void:
		if pl == null or not is_instance_valid(pl):
			return
		var st := pl.get_state()
		if st in [S.DEAD, S.MOUNTED, S.CINEMATIC, S.INTERACTING, S.HITSTUN, S.KNOCKED_DOWN]:
			flag("ability_started_in_" + pl.get_state_name(), String(id))
		if tree.paused:
			flag("ability_started_while_paused", String(id))
		var d := AbilityRegistry.get_def(id)
		if d != null and d.cooldown > 0.0 and _cd_last.has(id):
			var since := clock - float(_cd_last[id])
			if since < d.cooldown * 0.97:
				flag("cooldown_bypass", "%s again after %.2f s (cooldown %.1f)" % [id, since, d.cooldown])
		_cd_last[id] = clock

	func report() -> String:
		var lines: Array[String] = []
		for k: String in violations:
			lines.append("  %s x%d" % [k, int(violations[k])])
			for s: String in samples.get(k, []):
				lines.append("      " + s)
		return "\n".join(lines)
