class_name EnemyArchetypes
extends RefCounted
## Data-driven enemy archetypes (docs/modules/enemies.md "Archetypes").
##
## Every enemy is an EnemyBase configured from one of these dictionaries; nothing
## behavioural is hard-coded per archetype except through these fields:
##
##   role        &"brawler" &"skirmisher" &"ranged" &"defender" &"bender" &"captain" &"beast"
##   faction     &"bandits" &"fire_nation" &"pirates" &"dai_li" &"earth_rogues" &"wild"
##   element     ElementDefs.Element (benders) or NONE
##   look        HumanoidRig config ({"preset", "style", "palette", ...}) or {"creature": id, "scale"}
##   props       [[prop, socket], ...]   RigProps names or EnemyProps names (club, knives, bow, shield, quiver)
##   health, poise, poise_resist (poise damage below which stagger/knockback become flinches),
##   mass (knockback multiplier), armor (damage reduction 0..1)
##   speed       {"walk", "run", "strafe"} m/s
##   sight, fov (deg), hearing (m)
##   engage      Vector2(min, max) preferred distance to the target while circling
##   aggression  0..1: how eagerly it takes attack tokens and presses forward
##   attacks     Array of attack dictionaries (EnemyActions.ATTACK_FIELDS)
##   block       {} or {"arc", "reduction", "projectiles", "guard_hp", "chance", "bending"}
##   dodge       {"chance", "distance", "duration", "iframes"} (vs slow / heavy attacks)
##   flee        {} or {"health", "flee", "surrender"} (chances rolled once per enemy)
##   phases      captains: [{"at": health ratio, "speed": x, "telegraph": x, "attacks": [...], "shout": text}]
##   xp, loot    [{"item", "chance", "min", "max"}]
##
## Attack dictionary (see EnemyActions):
##   id, kind (&"melee" &"projectile" &"bending" &"charge" &"slam"), clip, mirror, windup (normalized
##   hold point of the clip), approach (s to reach it), telegraph (s held, before difficulty),
##   speed (clip speed), range Vector2(min, max), cooldown, weight, hit {...}, shape {...},
##   lunge (m), recover (s), armor (poise), glint (socket), ring (ground telegraph radius),
##   next (follow-up attack id for combos), bending {"slot", "hold", "steps"}, projectile {...}

const R := HitInfo.Reaction
const E := ElementDefs.Element

const ROLES: Array[StringName] = [&"brawler", &"skirmisher", &"ranged", &"defender", &"bender", &"captain", &"beast"]

## Faction colours (health bar accents, camp banners, alert marks).
const FACTION_COLORS := {
	&"bandits": Color(0.72, 0.5, 0.28), &"fire_nation": Color(0.86, 0.2, 0.12), &"pirates": Color(0.25, 0.42, 0.6),
	&"dai_li": Color(0.18, 0.42, 0.26), &"earth_rogues": Color(0.45, 0.55, 0.22), &"wild": Color(0.62, 0.55, 0.42),
	&"air_acolytes": Color(0.92, 0.66, 0.24),
}

const FACTION_NAMES := {
	&"bandits": "Bandits", &"fire_nation": "Fire Nation", &"pirates": "Pirates", &"dai_li": "Dai Li",
	&"earth_rogues": "Raiders", &"wild": "Wildlife", &"air_acolytes": "Air Acolytes",
}

# --- shared attack pieces ------------------------------------------------------------------------

const _KICK := {"id": &"push_kick", "kind": &"melee", "clip": &"front_kick_r", "windup": 0.24, "approach": 0.14, "telegraph": 0.38,
	"range": Vector2(0.0, 2.0), "cooldown": 3.0, "weight": 0.6, "glint": &"foot_r",
	"hit": {"damage": 6.0, "reaction": R.KNOCKBACK, "force": 8.0, "poise": 18.0}, "shape": {"type": &"sweep", "reach": 1.9, "radius": 0.55},
	"recover": 0.35, "tag": &"space"}

## A kit's ready-made technique attack (FireKit / EarthKit / WaterKit / AirKit.enemy_attacks())
## with archetype-specific overrides (weight, cooldown, range ...). The slot it names is
## filled by EnemyAbilities.LOADOUTS with the enemy-tuned copy of the technique.
static func _kit(attacks: Dictionary, id: StringName, over: Dictionary = {}) -> Dictionary:
	var a: Dictionary = (attacks.get(id, {}) as Dictionary).duplicate(true)
	for k: String in over:
		a[k] = over[k]
	return a


static var _data: Dictionary = {}


static func ids() -> Array[StringName]:
	_ensure()
	var out: Array[StringName] = []
	for k: StringName in _data:
		out.append(k)
	out.sort()
	return out


static func has(id: StringName) -> bool:
	_ensure()
	return _data.has(id)


## The archetype dictionary (shared, read-only: duplicate before changing it).
static func get_archetype(id: StringName) -> Dictionary:
	_ensure()
	return _data.get(id, {})


## Register (or replace) an archetype at runtime (quests, other modules).
static func register(id: StringName, d: Dictionary) -> void:
	_ensure()
	var a := d.duplicate(true)
	a["id"] = id
	_data[id] = _normalized(a)


static func by_faction(faction: StringName) -> Array[StringName]:
	_ensure()
	var out: Array[StringName] = []
	for k: StringName in _data:
		if (_data[k] as Dictionary).get("faction", &"") == faction:
			out.append(k)
	out.sort()
	return out


static func _ensure() -> void:
	if not _data.is_empty():
		return
	for id: StringName in _defs():
		var a: Dictionary = _defs()[id]
		a["id"] = id
		_data[id] = _normalized(a)


## Fills defaults so the rest of the module can read fields without fallbacks.
static func _normalized(a: Dictionary) -> Dictionary:
	var d := {
		"display_name": "Enemy", "role": &"brawler", "faction": &"bandits", "element": E.NONE, "tier": 1,
		"look": {"preset": &"bandit"}, "props": [], "health": 80.0, "poise": 25.0, "poise_resist": 0.0, "mass": 1.0,
		"armor": 0.0, "speed": {"walk": 1.5, "run": 4.6, "strafe": 2.0}, "sight": 24.0, "fov": 130.0, "hearing": 28.0,
		"engage": Vector2(3.0, 5.0), "aggression": 0.5, "attacks": [], "block": {}, "dodge": {}, "flee": {},
		"phases": [], "xp": 20, "loot": [], "radius": 0.34, "height": 1.75, "voice": &"",
	}
	for k: String in a:
		d[k] = a[k]
	var sp: Dictionary = {"walk": 1.5, "run": 4.6, "strafe": 2.0}
	for k: String in (d["speed"] as Dictionary):
		sp[k] = d["speed"][k]
	d["speed"] = sp
	return d


static func _defs() -> Dictionary:
	var fire_t := FireKit.enemy_attacks()
	var earth_t := EarthKit.enemy_attacks()
	var water_t := WaterKit.enemy_attacks()
	var air_t := AirKit.enemy_attacks()
	return {
		# --- bandits ---------------------------------------------------------------------------
		&"bandit_brawler": {
			"display_name": "Bandit Brawler", "role": &"brawler", "faction": &"bandits",
			"look": {"preset": &"bandit", "style": &"soldier", "bulk": 0.5}, "props": [[&"club", &"hand_r"]],
			"health": 95.0, "poise": 32.0, "poise_resist": 10.0, "speed": {"walk": 1.5, "run": 4.4, "strafe": 1.9},
			"engage": Vector2(2.6, 4.2), "aggression": 0.65, "xp": 22,
			"attacks": [
				{"id": &"club_swing", "kind": &"melee", "clip": &"enemy_slash_r", "windup": 0.3, "approach": 0.2, "telegraph": 0.42,
					"range": Vector2(0.0, 2.3), "cooldown": 1.4, "weight": 1.0, "glint": &"weapon",
					"hit": {"damage": 10.0, "reaction": R.STAGGER, "force": 3.5, "stun": 0.35, "poise": 16.0},
					"shape": {"type": &"sweep", "reach": 2.2, "radius": 0.6}, "lunge": 1.4, "recover": 0.45, "next": &"club_backswing", "next_chance": 0.55},
				{"id": &"club_backswing", "kind": &"melee", "clip": &"enemy_backslash_r", "windup": 0.26, "approach": 0.12, "telegraph": 0.22,
					"range": Vector2(0.0, 2.4), "cooldown": 0.0, "weight": 0.0, "glint": &"",
					"hit": {"damage": 9.0, "reaction": R.STAGGER, "force": 4.5, "stun": 0.35, "poise": 18.0},
					"shape": {"type": &"sweep", "reach": 2.2, "radius": 0.6}, "lunge": 1.0, "recover": 0.65},
				{"id": &"overhead_smash", "kind": &"melee", "clip": &"enemy_overhead", "windup": 0.36, "approach": 0.3, "telegraph": 0.75,
					"range": Vector2(0.0, 2.6), "cooldown": 4.5, "weight": 0.55, "glint": &"weapon", "armor": 30.0, "ring": 1.4,
					"hit": {"damage": 19.0, "reaction": R.KNOCKDOWN, "force": 6.0, "stun": 0.9, "poise": 40.0, "heavy": true},
					"shape": {"type": &"sphere", "reach": 1.6, "radius": 1.25}, "lunge": 1.6, "recover": 0.9, "shake": 0.3},
			],
			"flee": {"health": 0.22, "flee": 0.35, "surrender": 0.35},
			"loot": [{"item": &"copper_coins", "chance": 0.9, "min": 3, "max": 8}, {"item": &"cloth_scrap", "chance": 0.3, "min": 1, "max": 1}],
		},
		&"bandit_skirmisher": {
			"display_name": "Bandit Cutthroat", "role": &"skirmisher", "faction": &"bandits",
			"look": {"preset": &"bandit", "body": "female", "style": &"fire", "bulk": -0.5}, "props": [[&"knife", &"hand_r"], [&"knife", &"hand_l"]],
			"health": 62.0, "poise": 16.0, "mass": 1.25, "speed": {"walk": 1.7, "run": 5.6, "strafe": 3.1},
			"engage": Vector2(3.4, 5.2), "aggression": 0.75, "xp": 22, "radius": 0.3,
			"dodge": {"chance": 0.75, "distance": 3.6, "duration": 0.32, "iframes": 0.26, "cooldown": 1.2},
			"attacks": [
				{"id": &"knife_flurry", "kind": &"melee", "clip": &"enemy_knife_slash_r", "windup": 0.28, "approach": 0.12, "telegraph": 0.34,
					"range": Vector2(0.0, 2.0), "cooldown": 1.2, "weight": 1.0, "glint": &"weapon",
					"hit": {"damage": 6.0, "reaction": R.FLINCH, "force": 2.0, "poise": 8.0},
					"shape": {"type": &"sweep", "reach": 1.9, "radius": 0.5}, "lunge": 2.2, "recover": 0.2, "next": &"knife_flurry_2", "next_chance": 0.85},
				{"id": &"knife_flurry_2", "kind": &"melee", "clip": &"enemy_knife_slash_r", "mirror": true, "windup": 0.28, "approach": 0.08, "telegraph": 0.12,
					"range": Vector2(0.0, 2.2), "cooldown": 0.0, "weight": 0.0, "glint": &"",
					"hit": {"damage": 7.0, "reaction": R.STAGGER, "force": 3.0, "stun": 0.3, "poise": 12.0},
					"shape": {"type": &"sweep", "reach": 1.9, "radius": 0.5}, "lunge": 1.6, "recover": 0.55, "retreat": 3.0},
				{"id": &"lunge_stab", "kind": &"melee", "clip": &"enemy_stab_r", "windup": 0.3, "approach": 0.16, "telegraph": 0.5,
					"range": Vector2(2.6, 5.5), "cooldown": 3.5, "weight": 0.8, "glint": &"weapon",
					"hit": {"damage": 11.0, "reaction": R.STAGGER, "force": 4.0, "stun": 0.45, "poise": 20.0},
					"shape": {"type": &"sweep", "reach": 1.6, "radius": 0.5}, "lunge": 4.6, "recover": 0.6},
				{"id": &"throw_knife", "kind": &"projectile", "clip": &"enemy_throw_r", "windup": 0.32, "approach": 0.16, "telegraph": 0.45,
					"range": Vector2(5.5, 13.0), "cooldown": 4.0, "weight": 0.6, "glint": &"hand_r",
					"hit": {"damage": 7.0, "reaction": R.FLINCH, "force": 2.0, "poise": 8.0},
					"projectile": {"visual": &"knife", "speed": 24.0, "gravity": 4.0, "radius": 0.14, "range": 18.0, "socket": &"hand_r"}, "recover": 0.3},
			],
			"flee": {"health": 0.25, "flee": 0.5, "surrender": 0.2},
			"loot": [{"item": &"copper_coins", "chance": 0.9, "min": 2, "max": 6}],
		},
		&"bandit_archer": {
			"display_name": "Bandit Archer", "role": &"ranged", "faction": &"bandits",
			"look": {"preset": &"bandit", "style": &"civilian"}, "props": [[&"bow", &"hand_l"], [&"quiver", &"back"]],
			"health": 58.0, "poise": 15.0, "mass": 1.15, "speed": {"walk": 1.5, "run": 4.8, "strafe": 2.3},
			"engage": Vector2(9.0, 16.0), "aggression": 0.5, "xp": 20, "sight": 30.0,
			"dodge": {"chance": 0.35, "distance": 3.0, "duration": 0.34, "iframes": 0.2, "cooldown": 2.0},
			"attacks": [
				{"id": &"arrow_shot", "kind": &"projectile", "clip": &"enemy_bow_shot", "windup": 0.55, "approach": 0.4, "telegraph": 0.55,
					"range": Vector2(4.0, 26.0), "cooldown": 1.8, "weight": 1.0, "glint": &"arrow", "needs_los": true,
					"hit": {"damage": 9.0, "reaction": R.FLINCH, "force": 2.0, "poise": 10.0},
					"projectile": {"visual": &"arrow", "speed": 30.0, "gravity": 3.0, "radius": 0.1, "range": 34.0, "socket": &"hand_l"}, "recover": 0.4},
				{"id": &"power_shot", "kind": &"projectile", "clip": &"enemy_bow_shot", "windup": 0.55, "approach": 0.45, "telegraph": 1.15,
					"range": Vector2(7.0, 26.0), "cooldown": 6.0, "weight": 0.45, "glint": &"arrow", "needs_los": true,
					"hit": {"damage": 16.0, "reaction": R.KNOCKBACK, "force": 7.0, "poise": 28.0, "heavy": true},
					"projectile": {"visual": &"arrow", "speed": 40.0, "gravity": 1.5, "radius": 0.12, "range": 40.0, "socket": &"hand_l", "trail": true},
					"recover": 0.6},
				_KICK,
			],
			"flee": {"health": 0.3, "flee": 0.6, "surrender": 0.25},
			"loot": [{"item": &"copper_coins", "chance": 0.85, "min": 2, "max": 5}, {"item": &"arrows", "chance": 0.5, "min": 2, "max": 6}],
		},
		# --- Fire Nation --------------------------------------------------------------------------
		&"fire_shieldbearer": {
			"display_name": "Fire Nation Spearman", "role": &"defender", "faction": &"fire_nation",
			"look": {"preset": &"fire_soldier", "style": &"soldier"}, "props": [[&"spear", &"hand_r"], [&"shield", &"hand_l"]],
			"health": 120.0, "poise": 45.0, "poise_resist": 18.0, "mass": 0.8, "speed": {"walk": 1.4, "run": 4.0, "strafe": 1.5},
			"engage": Vector2(2.4, 3.6), "aggression": 0.55, "xp": 28,
			"block": {"arc": 75.0, "reduction": 0.85, "projectiles": true, "guard_hp": 70.0, "chance": 0.85, "move": true},
			"attacks": [
				{"id": &"spear_thrust", "kind": &"melee", "clip": &"enemy_thrust", "windup": 0.32, "approach": 0.2, "telegraph": 0.5,
					"range": Vector2(0.0, 3.2), "cooldown": 1.6, "weight": 1.0, "glint": &"spear_tip",
					"hit": {"damage": 12.0, "reaction": R.STAGGER, "force": 4.0, "stun": 0.4, "poise": 18.0},
					"shape": {"type": &"sweep", "reach": 3.0, "radius": 0.45}, "lunge": 1.2, "recover": 0.55},
				{"id": &"shield_bash", "kind": &"melee", "clip": &"enemy_shield_bash", "windup": 0.3, "approach": 0.16, "telegraph": 0.4,
					"range": Vector2(0.0, 1.9), "cooldown": 3.0, "weight": 0.7, "glint": &"hand_l", "armor": 25.0,
					"hit": {"damage": 7.0, "reaction": R.KNOCKBACK, "force": 7.0, "poise": 26.0},
					"shape": {"type": &"sweep", "reach": 1.7, "radius": 0.7}, "lunge": 1.6, "recover": 0.5},
			],
			"loot": [{"item": &"copper_coins", "chance": 0.8, "min": 3, "max": 7}, {"item": &"iron_scrap", "chance": 0.35, "min": 1, "max": 2}],
		},
		&"fire_archer": {
			"display_name": "Yuyan Archer", "role": &"ranged", "faction": &"fire_nation",
			"look": {"preset": &"fire_soldier", "style": &"soldier", "bulk": -0.5}, "props": [[&"bow", &"hand_l"], [&"quiver", &"back"]],
			"health": 60.0, "poise": 16.0, "mass": 1.1, "speed": {"walk": 1.5, "run": 4.8, "strafe": 2.3},
			"engage": Vector2(10.0, 18.0), "aggression": 0.55, "xp": 24, "sight": 34.0,
			"dodge": {"chance": 0.4, "distance": 3.0, "duration": 0.34, "iframes": 0.2, "cooldown": 2.0},
			"attacks": [
				{"id": &"arrow_shot", "kind": &"projectile", "clip": &"enemy_bow_shot", "windup": 0.55, "approach": 0.4, "telegraph": 0.5,
					"range": Vector2(4.0, 30.0), "cooldown": 1.6, "weight": 1.0, "glint": &"arrow", "needs_los": true,
					"hit": {"damage": 9.0, "reaction": R.FLINCH, "force": 2.0, "poise": 10.0},
					"projectile": {"visual": &"arrow", "speed": 32.0, "gravity": 3.0, "radius": 0.1, "range": 38.0, "socket": &"hand_l"}, "recover": 0.35},
				{"id": &"pin_shot", "kind": &"projectile", "clip": &"enemy_bow_shot", "windup": 0.55, "approach": 0.45, "telegraph": 1.0,
					"range": Vector2(6.0, 30.0), "cooldown": 7.0, "weight": 0.4, "glint": &"arrow", "needs_los": true,
					"hit": {"damage": 8.0, "reaction": R.FREEZE, "stun": 0.9, "poise": 20.0},
					"projectile": {"visual": &"arrow", "speed": 38.0, "gravity": 1.5, "radius": 0.12, "range": 40.0, "socket": &"hand_l", "trail": true},
					"recover": 0.6},
				_KICK,
			],
			"loot": [{"item": &"copper_coins", "chance": 0.8, "min": 2, "max": 6}, {"item": &"arrows", "chance": 0.6, "min": 3, "max": 6}],
		},
		&"fire_soldier": {
			"display_name": "Firebender Soldier", "role": &"bender", "faction": &"fire_nation", "element": E.FIRE,
			"look": {"preset": &"fire_soldier", "style": &"fire"}, "props": [],
			"health": 88.0, "poise": 26.0, "poise_resist": 8.0, "speed": {"walk": 1.6, "run": 4.8, "strafe": 2.2},
			"engage": Vector2(6.0, 11.0), "aggression": 0.6, "xp": 30,
			"dodge": {"chance": 0.3, "bending": true, "cooldown": 2.5},
			"block": {"chance": 0.35, "bending": true, "projectiles": true, "arc": 85.0},
			"attacks": [
				{"id": &"fire_jabs", "kind": &"bending", "clip": &"combo_fire_1", "windup": 0.2, "approach": 0.12, "telegraph": 0.42,
					"range": Vector2(2.5, 15.0), "cooldown": 1.6, "weight": 1.0, "glint": &"hand_r", "needs_los": true,
					"bending": {"slot": &"light", "steps": 2}, "recover": 0.45},
				{"id": &"fire_blast", "kind": &"bending", "clip": &"fire_charge_hold", "windup": 0.5, "approach": 0.15, "telegraph": 0.5,
					"range": Vector2(5.0, 22.0), "cooldown": 4.0, "weight": 0.7, "glint": &"hands", "needs_los": true,
					"bending": {"slot": &"heavy", "tap": true}, "recover": 0.55},
				{"id": &"flame_sweep", "kind": &"bending", "clip": &"flame_sweep_kick", "windup": 0.2, "approach": 0.12, "telegraph": 0.3,
					"range": Vector2(0.0, 5.5), "cooldown": 7.0, "weight": 0.9, "glint": &"foot_r", "ring": 3.0,
					"bending": {"slot": &"technique_1"}, "recover": 0.5},
				# Fire Burst clears space when the player closes in (ring telegraph, 3.8 m).
				_kit(fire_t, &"fire_burst", {"weight": 0.8, "cooldown": 8.0}),
			],
			"loot": [{"item": &"copper_coins", "chance": 0.8, "min": 3, "max": 8}, {"item": &"fire_nation_insignia", "chance": 0.25, "min": 1, "max": 1}],
		},
		&"fire_captain": {
			"display_name": "Fire Navy Lieutenant", "role": &"captain", "faction": &"fire_nation", "element": E.FIRE, "tier": 2,
			"look": {"preset": &"fire_nation", "style": &"fire", "bulk": 0.5, "palette": {"tunic": Color(0.55, 0.08, 0.06)}}, "props": [],
			"health": 270.0, "poise": 75.0, "poise_resist": 28.0, "mass": 0.6, "armor": 0.1,
			"speed": {"walk": 1.6, "run": 5.0, "strafe": 2.4}, "engage": Vector2(4.0, 8.0), "aggression": 0.85, "xp": 120,
			"dodge": {"chance": 0.35, "bending": true, "cooldown": 3.0},
			"block": {"chance": 0.45, "bending": true, "projectiles": true, "arc": 85.0},
			"attacks": [
				{"id": &"fire_combo", "kind": &"bending", "clip": &"combo_fire_1", "windup": 0.2, "approach": 0.12, "telegraph": 0.38,
					"range": Vector2(0.0, 12.0), "cooldown": 1.8, "weight": 1.0, "glint": &"hand_r", "needs_los": true,
					"bending": {"slot": &"light", "steps": 4}, "recover": 0.55, "armor": 20.0},
				{"id": &"blaze_charge", "kind": &"bending", "range": Vector2(4.0, 24.0), "cooldown": 5.0, "weight": 0.8, "glint": &"hands",
					"needs_los": true, "telegraph": 0.0, "bending": {"slot": &"heavy", "hold": 0.75}, "recover": 0.6, "armor": 35.0},
				{"id": &"flame_sweep", "kind": &"bending", "clip": &"flame_sweep_kick", "windup": 0.2, "approach": 0.12, "telegraph": 0.3,
					"range": Vector2(0.0, 6.0), "cooldown": 6.0, "weight": 1.0, "glint": &"foot_r", "ring": 3.0,
					"bending": {"slot": &"technique_1"}, "recover": 0.45},
				# The lieutenant's mid-range lash (overhead wind-up is the tell).
				_kit(fire_t, &"fire_whip", {"weight": 0.9}),
			],
			"phases": [
				{"at": 0.5, "speed": 1.15, "telegraph": 0.85, "cooldown": 0.8, "shout": "Enough games!", "burst": 4.5,
					"attacks": [
						# Second phase: a racing ring of flame (jump it or get out of 6.5 m).
						_kit(fire_t, &"fire_ring", {"weight": 1.0}),
						{"id": &"blazing_leap", "kind": &"slam", "clip": &"leap_attack", "windup": 0.15, "approach": 0.16, "telegraph": 0.45,
							"range": Vector2(3.5, 9.0), "cooldown": 6.0, "weight": 1.2, "glint": &"hands", "ring": 3.2, "element": E.FIRE,
							"hit": {"damage": 22.0, "reaction": R.KNOCKDOWN, "force": 8.0, "lift": 2.0, "stun": 1.0, "poise": 50.0, "heavy": true, "status": {"burn": 3.0}},
							"shape": {"type": &"sphere", "reach": 0.0, "radius": 3.0}, "leap": true, "recover": 1.0, "armor": 60.0, "shake": 0.45},
					]},
			],
			"loot": [{"item": &"silver_coins", "chance": 1.0, "min": 2, "max": 4}, {"item": &"fire_nation_insignia", "chance": 1.0, "min": 1, "max": 1}],
		},
		# --- Earth rogues ---------------------------------------------------------------------------
		&"earth_rogue": {
			"display_name": "Rogue Earthbender", "role": &"bender", "faction": &"earth_rogues", "element": E.EARTH,
			"look": {"preset": &"earth_soldier", "style": &"earth", "bulk": 0.5, "palette": {"armor": Color(0.42, 0.36, 0.26)}}, "props": [],
			"health": 115.0, "poise": 42.0, "poise_resist": 18.0, "mass": 0.75, "speed": {"walk": 1.3, "run": 4.0, "strafe": 1.6},
			"engage": Vector2(6.0, 12.0), "aggression": 0.55, "xp": 32,
			"block": {"chance": 0.45, "bending": true, "projectiles": true, "arc": 70.0},
			"attacks": [
				{"id": &"rock_punches", "kind": &"bending", "clip": &"combo_earth_1", "windup": 0.32, "approach": 0.16, "telegraph": 0.4,
					"range": Vector2(2.5, 16.0), "cooldown": 1.9, "weight": 1.0, "glint": &"hand_r", "needs_los": true,
					"bending": {"slot": &"light", "steps": 2}, "recover": 0.5},
				{"id": &"boulder", "kind": &"bending", "range": Vector2(5.0, 20.0), "cooldown": 6.0, "weight": 0.75, "glint": &"hands",
					"needs_los": true, "telegraph": 0.0, "bending": {"slot": &"heavy", "hold": 0.55}, "recover": 0.6, "armor": 45.0},
				{"id": &"earth_wall", "kind": &"bending", "clip": &"earth_wall", "windup": 0.2, "approach": 0.12, "telegraph": 0.2,
					"range": Vector2(4.0, 30.0), "cooldown": 14.0, "weight": 0.0, "glint": &"hands",
					"bending": {"slot": &"technique_1"}, "recover": 0.4, "tag": &"cover"},
				# A stone column under the player at range (launch; sidestep after the stomp).
				_kit(earth_t, &"earth_pillar", {"weight": 0.7, "cooldown": 8.0}),
				# Up close: the stomp shockwave (ring telegraph, jump it).
				_kit(earth_t, &"earth_stomp", {"weight": 0.6, "cooldown": 9.0}),
			],
			"flee": {"health": 0.2, "flee": 0.3, "surrender": 0.3},
			"loot": [{"item": &"copper_coins", "chance": 0.85, "min": 3, "max": 8}, {"item": &"jade_shard", "chance": 0.15, "min": 1, "max": 1}],
		},
		&"earth_chief": {
			"display_name": "Raider Chief Dun", "role": &"captain", "faction": &"earth_rogues", "element": E.EARTH, "tier": 2,
			"look": {"preset": &"earth_soldier", "style": &"earth", "bulk": 1.0, "height": 1.9, "palette": {"armor": Color(0.32, 0.28, 0.22)}},
			"props": [], "health": 300.0, "poise": 90.0, "poise_resist": 32.0, "mass": 0.45, "armor": 0.12,
			"speed": {"walk": 1.3, "run": 4.2, "strafe": 1.8}, "engage": Vector2(4.0, 9.0), "aggression": 0.8, "xp": 130, "radius": 0.4,
			"block": {"chance": 0.5, "bending": true, "projectiles": true, "arc": 70.0},
			"attacks": [
				{"id": &"rock_punches", "kind": &"bending", "clip": &"combo_earth_1", "windup": 0.32, "approach": 0.16, "telegraph": 0.38,
					"range": Vector2(0.0, 16.0), "cooldown": 1.8, "weight": 1.0, "glint": &"hand_r", "needs_los": true,
					"bending": {"slot": &"light", "steps": 3}, "recover": 0.5, "armor": 25.0},
				{"id": &"boulder", "kind": &"bending", "range": Vector2(4.0, 20.0), "cooldown": 5.0, "weight": 0.8, "glint": &"hands",
					"needs_los": true, "telegraph": 0.0, "bending": {"slot": &"heavy", "hold": 0.7}, "recover": 0.6, "armor": 60.0},
				{"id": &"quake_stomp", "kind": &"slam", "clip": &"ground_slam", "windup": 0.3, "approach": 0.25, "telegraph": 0.65,
					"range": Vector2(0.0, 4.2), "cooldown": 6.0, "weight": 1.0, "glint": &"hands", "ring": 4.2, "element": E.EARTH,
					"hit": {"damage": 16.0, "reaction": R.KNOCKDOWN, "force": 7.0, "lift": 2.5, "stun": 0.9, "poise": 45.0, "heavy": true},
					"shape": {"type": &"sphere", "reach": 0.6, "radius": 4.2}, "recover": 0.9, "armor": 70.0, "shake": 0.4},
				_kit(earth_t, &"earth_pillar", {"weight": 0.8, "cooldown": 7.0}),
			],
			"phases": [
				{"at": 0.5, "speed": 1.1, "telegraph": 0.85, "cooldown": 0.8, "shout": "You'll be buried here!", "burst": 4.0,
					"attacks": [
						{"id": &"spike_line", "kind": &"slam", "clip": &"stomp_r", "windup": 0.3, "approach": 0.2, "telegraph": 0.55,
							"range": Vector2(2.0, 10.0), "cooldown": 5.5, "weight": 1.1, "glint": &"foot_r", "element": E.EARTH, "line": 9.0,
							"hit": {"damage": 15.0, "reaction": R.LAUNCH, "force": 3.0, "lift": 6.5, "poise": 40.0, "heavy": true},
							"shape": {"type": &"line", "reach": 9.0, "radius": 0.9}, "recover": 0.8, "armor": 50.0, "shake": 0.3},
					]},
			],
			"loot": [{"item": &"silver_coins", "chance": 1.0, "min": 3, "max": 5}, {"item": &"jade_shard", "chance": 0.8, "min": 1, "max": 2}],
		},
		# --- Dai Li ------------------------------------------------------------------------------
		&"dai_li_agent": {
			"display_name": "Dai Li Agent", "role": &"bender", "faction": &"dai_li", "element": E.EARTH,
			"look": {"preset": &"dai_li", "style": &"earth"}, "props": [],
			"health": 95.0, "poise": 30.0, "poise_resist": 10.0, "speed": {"walk": 1.6, "run": 5.2, "strafe": 2.6},
			"engage": Vector2(6.0, 11.0), "aggression": 0.6, "xp": 34,
			"dodge": {"chance": 0.45, "distance": 3.5, "duration": 0.3, "iframes": 0.24, "cooldown": 2.0},
			"block": {"chance": 0.3, "bending": true, "projectiles": true, "arc": 70.0},
			"attacks": [
				{"id": &"rock_glove", "kind": &"bending", "clip": &"jab_r", "windup": 0.22, "approach": 0.14, "telegraph": 0.5,
					"range": Vector2(3.0, 15.0), "cooldown": 4.0, "weight": 1.0, "glint": &"hand_r", "needs_los": true,
					"bending": {"slot": &"technique_1"}, "recover": 0.4},
				{"id": &"rock_punches", "kind": &"bending", "clip": &"combo_earth_1", "windup": 0.32, "approach": 0.16, "telegraph": 0.38,
					"range": Vector2(2.0, 14.0), "cooldown": 1.7, "weight": 0.9, "glint": &"hand_l", "needs_los": true,
					"bending": {"slot": &"light", "steps": 2}, "recover": 0.45},
				# Dai Li drive spike lines through the street toward their quarry.
				_kit(earth_t, &"earth_spikes", {"weight": 0.55, "cooldown": 10.0}),
			],
			"loot": [{"item": &"copper_coins", "chance": 0.7, "min": 4, "max": 9}, {"item": &"jade_shard", "chance": 0.3, "min": 1, "max": 1}],
		},
		# --- Pirates -----------------------------------------------------------------------------
		&"pirate_cutlass": {
			"display_name": "Pirate Raider", "role": &"skirmisher", "faction": &"pirates",
			"look": {"preset": &"pirate", "style": &"fire"}, "props": [[&"sword", &"hand_r"]],
			"health": 72.0, "poise": 20.0, "mass": 1.1, "speed": {"walk": 1.6, "run": 5.2, "strafe": 2.8},
			"engage": Vector2(3.0, 5.0), "aggression": 0.7, "xp": 22,
			"dodge": {"chance": 0.6, "distance": 3.4, "duration": 0.32, "iframes": 0.24, "cooldown": 1.5},
			"attacks": [
				{"id": &"cutlass_slash", "kind": &"melee", "clip": &"enemy_slash_r", "windup": 0.3, "approach": 0.16, "telegraph": 0.38,
					"range": Vector2(0.0, 2.3), "cooldown": 1.3, "weight": 1.0, "glint": &"weapon",
					"hit": {"damage": 9.0, "reaction": R.STAGGER, "force": 3.0, "stun": 0.3, "poise": 14.0},
					"shape": {"type": &"sweep", "reach": 2.2, "radius": 0.55}, "lunge": 1.8, "recover": 0.4, "next": &"cutlass_back", "next_chance": 0.6},
				{"id": &"cutlass_back", "kind": &"melee", "clip": &"enemy_backslash_r", "windup": 0.26, "approach": 0.1, "telegraph": 0.18,
					"range": Vector2(0.0, 2.4), "cooldown": 0.0, "weight": 0.0, "glint": &"",
					"hit": {"damage": 9.0, "reaction": R.STAGGER, "force": 4.0, "stun": 0.35, "poise": 16.0},
					"shape": {"type": &"sweep", "reach": 2.2, "radius": 0.55}, "lunge": 1.2, "recover": 0.6, "retreat": 2.5},
				{"id": &"lunge_stab", "kind": &"melee", "clip": &"enemy_stab_r", "windup": 0.3, "approach": 0.16, "telegraph": 0.55,
					"range": Vector2(2.6, 5.5), "cooldown": 4.0, "weight": 0.7, "glint": &"weapon",
					"hit": {"damage": 12.0, "reaction": R.STAGGER, "force": 4.0, "stun": 0.45, "poise": 20.0},
					"shape": {"type": &"sweep", "reach": 1.9, "radius": 0.5}, "lunge": 4.4, "recover": 0.65},
			],
			"flee": {"health": 0.22, "flee": 0.4, "surrender": 0.3},
			"loot": [{"item": &"copper_coins", "chance": 0.9, "min": 3, "max": 9}, {"item": &"sea_salt", "chance": 0.3, "min": 1, "max": 2}],
		},
		&"pirate_archer": {
			"display_name": "Pirate Crossbowman", "role": &"ranged", "faction": &"pirates",
			"look": {"preset": &"pirate", "style": &"civilian"}, "props": [[&"bow", &"hand_l"], [&"quiver", &"back"]],
			"health": 60.0, "poise": 15.0, "mass": 1.15, "speed": {"walk": 1.5, "run": 4.8, "strafe": 2.3},
			"engage": Vector2(9.0, 16.0), "aggression": 0.5, "xp": 20, "sight": 30.0,
			"dodge": {"chance": 0.3, "distance": 3.0, "duration": 0.34, "iframes": 0.2, "cooldown": 2.0},
			"attacks": [
				{"id": &"arrow_shot", "kind": &"projectile", "clip": &"enemy_bow_shot", "windup": 0.55, "approach": 0.4, "telegraph": 0.6,
					"range": Vector2(4.0, 26.0), "cooldown": 1.9, "weight": 1.0, "glint": &"arrow", "needs_los": true,
					"hit": {"damage": 9.0, "reaction": R.FLINCH, "force": 2.0, "poise": 10.0},
					"projectile": {"visual": &"arrow", "speed": 30.0, "gravity": 3.0, "radius": 0.1, "range": 34.0, "socket": &"hand_l"}, "recover": 0.4},
				_KICK,
			],
			"flee": {"health": 0.3, "flee": 0.6, "surrender": 0.2},
			"loot": [{"item": &"copper_coins", "chance": 0.85, "min": 2, "max": 6}],
		},
		&"water_pirate": {
			"display_name": "Rogue Waterbender", "role": &"bender", "faction": &"pirates", "element": E.WATER,
			"look": {"preset": &"pirate", "style": &"water", "body": "female"}, "props": [],
			"health": 82.0, "poise": 24.0, "poise_resist": 6.0, "mass": 1.0, "speed": {"walk": 1.6, "run": 5.0, "strafe": 2.6},
			"engage": Vector2(4.5, 9.0), "aggression": 0.6, "xp": 32,
			"dodge": {"chance": 0.4, "bending": true, "cooldown": 2.2},
			"block": {"chance": 0.45, "bending": true, "projectiles": true, "arc": 110.0},
			"attacks": [
				{"id": &"water_whip", "kind": &"bending", "clip": &"combo_water_1", "windup": 0.36, "approach": 0.16, "telegraph": 0.4,
					"range": Vector2(1.5, 5.4), "cooldown": 1.7, "weight": 1.0, "glint": &"hand_r",
					"bending": {"slot": &"light", "steps": 2}, "recover": 0.45},
				{"id": &"water_blast", "kind": &"bending", "clip": &"water_gather_hold", "windup": 0.5, "approach": 0.2, "telegraph": 0.45,
					"range": Vector2(4.0, 20.0), "cooldown": 4.5, "weight": 0.7, "glint": &"hands", "needs_los": true,
					"bending": {"slot": &"heavy", "tap": true}, "recover": 0.5},
				{"id": &"ice_shards", "kind": &"bending", "clip": &"water_draw", "windup": 0.3, "approach": 0.18, "telegraph": 0.3,
					"range": Vector2(6.0, 18.0), "cooldown": 7.0, "weight": 0.8, "glint": &"hands", "needs_los": true,
					"bending": {"slot": &"technique_1"}, "recover": 0.45},
				_kit(water_t, &"water_surge", {"weight": 0.75}),
				_kit(water_t, &"ice_trap", {"weight": 0.7}),
				_kit(water_t, &"ice_wall", {}),
			],
			"flee": {"health": 0.2, "flee": 0.4, "surrender": 0.2},
			"loot": [{"item": &"copper_coins", "chance": 0.85, "min": 3, "max": 8}, {"item": &"sea_salt", "chance": 0.4, "min": 1, "max": 2}],
		},
		# --- Airbenders ----------------------------------------------------------------------------
		# The temple's sparring monks duel visitors (the air trainer's spar partner is built on it).
		&"air_sparring_monk": AirKit.enemy_archetype(),
		# An exile from the temples who sold the wind to road bandits: light, evasive, pushes the
		# player out of reach and cuts from range. Leads the north road bandits.
		&"air_renegade": {
			"display_name": "Renegade Airbender", "role": &"bender", "faction": &"bandits", "element": E.AIR,
			"look": {"preset": &"bandit", "style": &"air", "body": "male", "bulk": -0.4, "palette": {"tunic": Color(0.55, 0.42, 0.2)}}, "props": [],
			"health": 78.0, "poise": 20.0, "poise_resist": 6.0, "mass": 1.2, "speed": {"walk": 1.8, "run": 5.6, "strafe": 3.0},
			"engage": Vector2(4.0, 9.0), "aggression": 0.65, "xp": 36,
			"dodge": {"chance": 0.55, "bending": true, "cooldown": 1.8},
			"block": {"chance": 0.3, "bending": true, "projectiles": true, "arc": 100.0},
			"attacks": [
				{"id": &"air_jabs", "kind": &"bending", "clip": &"combo_air_1", "windup": 0.18, "approach": 0.12, "telegraph": 0.36,
					"range": Vector2(1.5, 7.0), "cooldown": 1.5, "weight": 1.0, "glint": &"hand_l", "needs_los": true,
					"bending": {"slot": &"light", "steps": 2}, "recover": 0.45},
				{"id": &"air_blast", "kind": &"bending", "clip": &"air_blast", "windup": 0.35, "approach": 0.14, "telegraph": 0.45,
					"range": Vector2(4.0, 18.0), "cooldown": 4.0, "weight": 0.7, "glint": &"hands", "needs_los": true,
					"bending": {"slot": &"heavy", "tap": true}, "recover": 0.5},
				_kit(air_t, &"wind_blade", {"weight": 0.9}),
				_kit(air_t, &"air_sweep", {"weight": 0.8}),
				_kit(air_t, &"air_push", {"weight": 1.0}),
			],
			"flee": {"health": 0.25, "flee": 0.5, "surrender": 0.25},
			"loot": [{"item": &"copper_coins", "chance": 0.9, "min": 4, "max": 9}, {"item": &"cloth_scrap", "chance": 0.4, "min": 1, "max": 2}],
		},
		# --- Wild beasts -------------------------------------------------------------------------
		&"komodo_rhino": {
			"display_name": "Wild Komodo Rhino", "role": &"beast", "faction": &"wild",
			"look": {"creature": &"komodo_rhino", "scale": 1.0}, "props": [],
			"health": 220.0, "poise": 80.0, "poise_resist": 30.0, "mass": 0.35, "armor": 0.1,
			"speed": {"walk": 1.5, "run": 6.0, "strafe": 2.0}, "engage": Vector2(4.0, 8.0), "aggression": 0.7, "xp": 60,
			"sight": 20.0, "fov": 150.0, "hearing": 26.0, "radius": 0.75, "height": 1.5,
			"attacks": [
				{"id": &"bite", "kind": &"beast", "action": &"bite", "telegraph": 0.5, "range": Vector2(0.0, 3.2), "cooldown": 1.8, "weight": 1.0,
					"glint": &"mouth", "hit": {"damage": 14.0, "reaction": R.STAGGER, "force": 5.0, "stun": 0.4, "poise": 22.0},
					"shape": {"type": &"sphere", "reach": 2.6, "radius": 1.2}, "lunge": 1.5, "recover": 0.6, "event": &"hit"},
				{"id": &"tail_swipe", "kind": &"beast", "action": &"swipe", "telegraph": 0.55, "range": Vector2(0.0, 3.5), "cooldown": 3.5, "weight": 0.7,
					"glint": &"tail", "ring": 3.2, "hit": {"damage": 12.0, "reaction": R.KNOCKBACK, "force": 9.0, "poise": 30.0, "heavy": true},
					"shape": {"type": &"sphere", "reach": 0.0, "radius": 3.3}, "recover": 0.7, "event": &"hit"},
				{"id": &"rhino_charge", "kind": &"charge", "action": &"roar", "telegraph": 0.9, "range": Vector2(5.0, 16.0), "cooldown": 7.0, "weight": 0.9,
					"glint": &"head", "hit": {"damage": 22.0, "reaction": R.KNOCKDOWN, "force": 10.0, "lift": 2.0, "stun": 1.0, "poise": 60.0, "heavy": true},
					"shape": {"type": &"sphere", "reach": 2.2, "radius": 1.3}, "charge": {"speed": 11.0, "distance": 16.0}, "recover": 1.2,
					"armor": 80.0, "shake": 0.45},
			],
			"loot": [{"item": &"komodo_hide", "chance": 0.7, "min": 1, "max": 1}],
		},
	}
