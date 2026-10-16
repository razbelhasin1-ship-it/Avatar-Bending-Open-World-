class_name BendingFeedback
extends RefCounted
## Hit feedback rules (docs/GAME_DESIGN.md §5): hitstop 0.04 s (light) /
## 0.08 s (heavy), camera shake scaled by Settings (the camera applies the
## scale), element impact VFX, Focus gain, sounds per docs/modules/audio.md:
## target hits are sounded automatically by Audio from Events.hit_landed, so
## abilities only play casts, loops and WORLD impacts (world_impact()).
## Damage numbers come from Events.hit_landed (HUD).

const HITSTOP_LIGHT := 0.04
const HITSTOP_HEAVY := 0.08
const HITSTOP_PARRY := 0.12

static var _hitstop_frame := -1
static var _hitstop_amount := 0.0
static var _shake_frame := -1


## Called by BendingHits.deliver for every hit with a non-IGNORED result.
static func on_result(ctx: BendingContext, hit: HitInfo, target: Node, result: int, _requested: float = 0.0) -> void:
	var from: Node = ctx.caster if ctx != null and is_instance_valid(ctx.caster) else target
	var player_involved := (ctx != null and ctx.is_player()) or target.is_in_group(&"player")
	match result:
		Combat.Result.HIT, Combat.Result.KILLED:
			ImpactFx.hit(from, hit.element, hit.position, hit.direction, hit.is_heavy)
			# Sustained multi-hit moves (tornado pulses) tag their ticks &"no_hitstop".
			if player_involved and not hit.has_meta(&"no_hitstop"):
				hitstop(HITSTOP_HEAVY if hit.is_heavy or result == Combat.Result.KILLED else HITSTOP_LIGHT)
				shake(0.32 if hit.is_heavy else 0.14, 0.18 if hit.is_heavy else 0.1)
			# Parry counters are already paid by the parry's +15.
			if ctx != null and ctx.is_player() and not ctx.no_focus and not hit.has_meta(&"no_focus"):
				ctx.add_focus(10.0 if hit.is_heavy else 6.0)
		Combat.Result.BLOCKED:
			ImpactFx.block(from, hit.element, hit.position, -hit.direction)
			if player_involved:
				shake(0.1, 0.08)
		Combat.Result.DEFLECTED:
			if player_involved:
				hitstop(HITSTOP_PARRY)


## Requests hitstop at most once per physics frame (the longest wins).
static func hitstop(duration: float) -> void:
	var f := Engine.get_physics_frames()
	if f == _hitstop_frame and duration <= _hitstop_amount:
		return
	_hitstop_frame = f
	_hitstop_amount = duration
	Events.hitstop.emit(duration)


static func shake(strength: float, duration: float) -> void:
	var f := Engine.get_physics_frames()
	if f == _shake_frame:
		return
	_shake_frame = f
	Events.camera_shake.emit(strength, duration)


static func impulse(dir: Vector3, strength: float) -> void:
	Events.camera_impulse.emit(dir, strength)


## Element sound for a bending event (casts, loops start separately) at a position.
static func sound(element: int, event: StringName, pos: Vector3, volume_db: float = 0.0) -> void:
	Audio.play_bending(element, event, pos, volume_db)


## Projectile / attack hitting terrain or a wall: VFX + impact sound.
static func world_impact(from: Node, element: int, pos: Vector3, normal: Vector3, size: float = 1.0) -> void:
	ImpactFx.world(from, element, pos, normal, size, GroundSampler.surface(pos))
	Audio.play_bending(element, &"impact", pos, -2.0 if size < 1.0 else 0.0)
