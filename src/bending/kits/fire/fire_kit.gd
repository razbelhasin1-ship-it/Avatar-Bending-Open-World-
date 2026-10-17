class_name FireKit
extends RefCounted
## Fire Nation kit (docs/GAME_DESIGN.md §4 Fire, docs/modules/bending_fire.md):
## aggressive, precise, explosive. Fire comes from the body - breath and Northern
## Shaolin strikes - so every technique has a source (fists, feet, palms), a volume,
## motion and an impact, lights its surroundings briefly and leaves the world scorched.
##
## Technique tree (unlock rules read by AbilityRegistry.can_unlock; tier / branch /
## column are layout data for the skill-tree UI):
##   tier 1 (new game)  Fire Burst (breath)            Flame Sweep (flame)
##   tier 2 (level 3)   Jet Step <- Fire Burst x6      Fire Ring <- Flame Sweep x6
##   tier 3 (level 5)                                  Fire Whip <- Fire Ring x6
##   tier 4 (level 7)                                  Inferno (signature) <- Fire Whip, Master Jinzo, 2 points
##   tier 5 (level 9)   Lightning Generation <- Jet Step x8, Master Jinzo, 2 points (lightning)
## Trainer ids (GameState flag "trained_<trainer>_<ability>"): see TRAINERS.

const E := ElementDefs.Element.FIRE
const R := HitInfo.Reaction
const DIR := "res://src/bending/kits/fire/"
const ICONS := "res://src/bending/kits/fire/icons/"

## Trainers referenced by the unlock rules (for the NPC / trainer module). Master Jinzo
## teaches at the Flame Kata Grounds of the Fire Nation capital (npc id fn_jinzo).
const TRAINERS := {
	&"fn_jinzo": {"name": "Master Jinzo", "region": &"fire_nation", "teaches": [&"inferno", &"lightning"]},
}


static func defs() -> Array[AbilityDef]:
	# Clips used by the Fire techniques (also needed by rig-less casters' timelines).
	FireClips.ensure()
	var out: Array[AbilityDef] = [
		AbilityDef.make({"id": &"fire_combo", "element": E, "slot": AbilityDef.Slot.LIGHT, "display_name": "Fire Fist / Fire Kick",
			"description": "Jab, jab, kick, roundhouse: fire darts snap from the fists, the kicks sweep arcs of flame and the roundhouse sets the target alight.",
			"icon": "res://assets/ui/ability_flame.svg", "startup": 0.07, "active": 0.1, "recovery": 0.2,
			"hit": {"damage": 6.0, "reaction": R.FLINCH, "force": 2.0, "poise": 7.0, "status": {"burn": 1.5}},
			"params": {"steps": [
				{"clip": &"combo_fire_1", "start": 0.18, "speed": 1.0, "event": &"release", "chain_at": 0.62, "kind": "bolt", "hand": &"hand_r"},
				{"clip": &"combo_fire_2", "start": 0.18, "speed": 1.0, "event": &"release", "chain_at": 0.62, "kind": "bolt", "hand": &"hand_l"},
				{"clip": &"combo_fire_3", "start": 0.28, "speed": 1.2, "event": &"impact", "chain_at": 0.7, "kind": "kick", "hand": &"foot_r", "move": "lunge", "lunge": 2.4,
					"hit": {"damage": 9.0, "force": 4.0, "poise": 12.0, "status": {"burn": 2.0}}},
				{"clip": &"fire_spin_kick_r", "start": 0.32, "speed": 1.15, "event": &"release", "kind": "wave", "hand": &"foot_r",
					"hit": {"damage": 13.0, "reaction": R.KNOCKBACK, "force": 9.0, "poise": 26.0, "heavy": true, "status": {"burn": 3.0}}},
			], "bolt_speed": 38.0, "bolt_range": 16.0, "bolt_size": 0.2},
			"fx": {"vfx": &"fire_bolt", "sfx": &"cast_light"}, "script_path": DIR + "fire_combo.gd"}),
		AbilityDef.make({"id": &"fire_blast", "element": E, "slot": AbilityDef.Slot.HEAVY, "display_name": "Fire Blast / Blaze Charge",
			"description": "Tap: a fast long-range fireball. Hold: breathe the fire into a growing ball at your hip (it flares when fully charged) and drive it out as a blast that explodes on impact.",
			"icon": "res://assets/ui/ability_flame.svg", "chi_cost": 10.0, "charge_time": 1.1, "max_hold": 3.0,
			"hit": {"damage": 15.0, "reaction": R.STAGGER, "force": 5.0, "stun": 0.45, "poise": 24.0, "heavy": true, "status": {"burn": 2.5}},
			"params": {"hold_clip": &"fire_blaze_hold", "release_clip": &"fire_blaze_release", "release_start": 0.12,
				"tap_clip": &"fire_charge_release", "tap_start": 0.16, "tap_time": 0.2, "min_windup": 0.08, "charge_chi": 16.0, "walk_scale": 0.3,
				"speed": 36.0, "range": 32.0, "explode_radius": 2.4, "explode_radius_full": 4.2},
			"fx": {"vfx": &"fireball", "sfx": &"cast_heavy", "charge": &"charge_loop"}, "script_path": DIR + "fire_blast.gd"}),
		AbilityDef.make({"id": &"flame_guard", "element": E, "slot": AbilityDef.Slot.DEFENSE, "display_name": "Flame Guard",
			"description": "A flare of fire that burns incoming projectiles away and blocks 75%. Perfect timing: a Fire Burst counter knocks the attacker down.",
			"icon": "res://assets/ui/ability_shield.svg", "clip": &"fire_guard_hold",
			"params": {"reduction": 0.75, "arc": 85.0, "upkeep": 5.0, "burn_projectiles": true, "walk_scale": 0.45, "counter_damage": 4.0, "counter_radius": 3.2},
			"fx": {"vfx": &"flame_flare", "sfx": &"shield_up"}, "script_path": DIR + "flame_guard.gd"}),
		AbilityDef.make({"id": &"fire_step", "element": E, "slot": AbilityDef.Slot.DODGE, "display_name": "Fire Step",
			"description": "An explosive burst step (4.5 m, 0.2 s i-frames) jet-propelled from the feet, leaving a short flame trail. Cancels into strikes.",
			"icon": "res://assets/ui/ability_flame.svg",
			"params": {"clips": {"fwd": &"dodge_fire_burst", "back": &"dodge_back", "left": &"dodge_side_l", "right": &"dodge_side_r"},
				"recovery": 0.1, "cancel_strikes": 0.12},
			"fx": {"vfx": &"flame_trail", "sfx": &"dash"}, "script_path": DIR + "fire_step.gd"}),
		# --- tier 1: starters -------------------------------------------------------------------
		AbilityDef.make({"id": &"fire_burst", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Fire Burst",
			"description": "Breathe in, stomp and throw both palms out: a point-blank explosion that blasts everyone around you away (knocked down up close) and burns incoming projectiles. Space when you are surrounded.",
			"icon": ICONS + "ability_fire_burst.svg", "chi_cost": 20.0, "cooldown": 5.0, "clip": &"fire_burst_blast", "clip_speed": 1.0,
			"startup": 0.26, "active": 0.12, "recovery": 0.3, "starter": true, "poise_armor": 30.0,
			"unlock": {"level": 1, "tier": 1, "branch": &"breath", "column": 0},
			"hit": {"damage": 14.0, "reaction": R.KNOCKBACK, "force": 11.0, "lift": 2.5, "stun": 0.5, "poise": 40.0, "heavy": true, "status": {"burn": 3.0}},
			"params": {"radius": 3.8, "inner": 2.0, "inner_hit": {"reaction": R.KNOCKDOWN, "damage": 16.0, "lift": 3.5, "stun": 0.9}},
			"fx": {"vfx": &"fire_burst", "sfx": &"explosion"}, "script_path": DIR + "fire_burst.gd"}),
		AbilityDef.make({"id": &"flame_sweep", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Flame Sweep",
			"description": "A low sweeping kick that sends a wide wave of fire rolling outward along the ground.",
			"icon": "res://assets/ui/ability_sweep.svg", "chi_cost": 22.0, "cooldown": 6.0, "clip": &"flame_sweep_kick", "clip_speed": 1.05,
			"startup": 0.35, "recovery": 0.3, "starter": true, "unlock": {"level": 1, "tier": 1, "branch": &"flame", "column": 1},
			"hit": {"damage": 18.0, "reaction": R.KNOCKBACK, "force": 7.0, "lift": 1.5, "poise": 30.0, "heavy": true, "status": {"burn": 4.0}},
			"params": {"range": 7.5, "half_angle": 62.0, "wave_time": 0.42},
			"fx": {"vfx": &"flame_wave", "sfx": &"cast_heavy"}, "script_path": DIR + "flame_sweep.gd"}),
		# --- tier 2 -------------------------------------------------------------------------------
		AbilityDef.make({"id": &"jet_step", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Jet Step",
			"description": "Fire jets from your feet and palms launch you up and forward; hold to hover on the flames for a moment (usable in the air once). Taking off scorches whoever stands close.",
			"icon": ICONS + "ability_jet_step.svg", "chi_cost": 14.0, "cooldown": 1.6, "clip": &"jet_step_launch",
			"startup": 0.17, "active": 1.2, "recovery": 0.1,
			"unlock": {"level": 3, "prerequisite": &"fire_burst", "practice": 6, "cost": 1, "tier": 2, "branch": &"breath", "column": 0},
			"hit": {"damage": 8.0, "reaction": R.KNOCKBACK, "force": 7.0, "lift": 1.5, "poise": 18.0, "status": {"burn": 2.0}},
			"params": {"launch_up": 9.5, "launch_fwd": 8.0, "air_up": 7.0, "thrust_time": 0.28, "hover_time": 1.1, "hover_upkeep": 18.0,
				"drift": 5.0, "takeoff_radius": 2.2, "min_hold": 0.22, "in_air": true},
			"fx": {"vfx": &"fire_jet", "sfx": &"jump"}, "script_path": DIR + "jet_step.gd"}),
		AbilityDef.make({"id": &"fire_ring", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Fire Ring",
			"description": "Coil and spin with the leg extended: a wall of flame races outward in a full circle, knocking back everyone it reaches. Jump over it or put a wall between you.",
			"icon": ICONS + "ability_fire_ring.svg", "chi_cost": 26.0, "cooldown": 7.0, "clip": &"fire_ring_kick", "clip_speed": 1.0,
			"startup": 0.42, "active": 0.38, "recovery": 0.36, "poise_armor": 25.0,
			"unlock": {"level": 3, "prerequisite": &"flame_sweep", "practice": 6, "cost": 1, "tier": 2, "branch": &"flame", "column": 1},
			"hit": {"damage": 16.0, "reaction": R.KNOCKBACK, "force": 9.0, "lift": 2.5, "poise": 32.0, "heavy": true, "status": {"burn": 3.5}},
			"params": {"radius": 6.5, "wave_time": 0.38, "height": 1.35, "clearance": 1.4},
			"fx": {"vfx": &"fire_ring", "sfx": &"special"}, "script_path": DIR + "fire_ring.gd"}),
		# --- tier 3 -------------------------------------------------------------------------------
		AbilityDef.make({"id": &"fire_whip", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Fire Whip",
			"description": "Circle the flame over your head and lash it down across the field: a 7.5 m whip of fire cuts through everyone in its arc and cracks at the tip (stronger at the tip).",
			"icon": ICONS + "ability_fire_whip.svg", "chi_cost": 24.0, "cooldown": 6.0, "clip": &"fire_whip_lash", "clip_speed": 1.0,
			"startup": 0.32, "active": 0.16, "recovery": 0.33, "poise_armor": 20.0,
			"unlock": {"level": 5, "prerequisite": &"fire_ring", "practice": 6, "cost": 1, "tier": 3, "branch": &"flame", "column": 1},
			"hit": {"damage": 14.0, "reaction": R.STAGGER, "force": 6.0, "stun": 0.55, "poise": 30.0, "heavy": true, "status": {"burn": 3.0}},
			"params": {"reach": 7.5, "arc": 110.0, "radius": 0.45, "tip": 1.6,
				"tip_hit": {"damage": 21.0, "reaction": R.KNOCKBACK, "force": 10.0, "lift": 2.0, "poise": 45.0}},
			"fx": {"vfx": &"fire_whip", "sfx": &"cast_heavy"}, "script_path": DIR + "fire_whip.gd"}),
		# --- tier 4: signature --------------------------------------------------------------------
		AbilityDef.make({"id": &"inferno", "element": E, "slot": AbilityDef.Slot.SIGNATURE, "display_name": "Inferno",
			"description": "Breathe in and rise spinning at the heart of a whirling column of fire that scorches everyone close, then stomp and drive it outward: a towering ring of flame races out and launches everything it reaches.",
			"icon": ICONS + "ability_inferno.svg", "focus_cost": 100.0, "clip": &"inferno_spin", "startup": 0.38, "active": 1.05, "recovery": 0.35,
			"unlock": {"level": 7, "prerequisite": &"fire_whip", "trainer": &"fn_jinzo", "cost": 2, "tier": 4, "branch": &"flame", "column": 1},
			"hit": {"damage": 34.0, "reaction": R.LAUNCH, "force": 9.0, "lift": 8.0, "stun": 1.2, "poise": 90.0, "heavy": true, "status": {"burn": 5.0}},
			"params": {"vortex_radius": 3.0, "vortex_height": 4.5, "vortex_hit": {"damage": 5.0, "reaction": R.FLINCH, "force": 3.0, "poise": 10.0, "status": {"burn": 2.5}},
				"ring_radius": 11.0, "ring_time": 0.55, "ring_height": 2.2, "clearance": 1.8, "damage_reduction": 0.5},
			"fx": {"vfx": &"inferno", "sfx": &"special"}, "script_path": DIR + "inferno.gd"}),
		# --- tier 5: lightning (a separate discipline) ---------------------------------------------
		AbilityDef.make({"id": &"lightning", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Lightning Generation",
			"description": "The cold-blooded fire. Hold to separate the energies: rooted, arms tracing slow circles while lightning gathers at your fingertips (1.6 s). Release on the full charge for a devastating bolt. Released early it is weaker or fizzles; held too long or struck while charging, the lightning turns on you.",
			"icon": ICONS + "ability_lightning.svg", "chi_cost": 40.0, "cooldown": 14.0, "clip": &"lightning_release", "charge_time": 1.6, "max_hold": 2.8,
			"startup": 1.6, "active": 0.1, "recovery": 0.4,
			"unlock": {"level": 9, "prerequisite": &"jet_step", "practice": 8, "trainer": &"fn_jinzo", "cost": 2, "tier": 5, "branch": &"lightning", "column": 2},
			"hit": {"damage": 55.0, "reaction": R.KNOCKDOWN, "force": 8.0, "lift": 2.0, "stun": 1.4, "poise": 120.0, "heavy": true, "unblockable": true},
			"params": {"hold_clip": &"lightning_charge", "range": 38.0, "min_charge": 0.55, "weak_scale": 0.55, "overcharge": 2.8,
				"backfire_damage": 18.0, "backfire_hit_damage": 12.0, "chain_radius": 4.0, "chain_scale": 0.4, "water_radius": 5.0},
			"fx": {"vfx": &"lightning", "sfx": &"fire_lightning"}, "script_path": DIR + "lightning.gd"}),
	]
	return out


## The technique tree for the skill-tree UI: [{id, tier, branch, column, requires
## (prerequisite id), level, practice, trainer, cost, starter, signature}] by tier / column.
static func tree() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in defs():
		if d.slot != AbilityDef.Slot.TECHNIQUE and d.slot != AbilityDef.Slot.SIGNATURE:
			continue
		var u := d.unlock
		out.append({"id": d.id, "tier": int(u.get("tier", 1)), "branch": StringName(u.get("branch", &"")), "column": int(u.get("column", 0)),
				"requires": StringName(u.get("prerequisite", &"")), "level": int(u.get("level", 1)), "practice": int(u.get("practice", 0)),
				"trainer": StringName(u.get("trainer", &"")), "cost": int(u.get("cost", 0 if d.starter else 1)), "starter": d.starter,
				"signature": d.slot == AbilityDef.Slot.SIGNATURE})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tier"] < b["tier"] or (a["tier"] == b["tier"] and a["column"] < b["column"]))
	return out


## Ready-made EnemyActions attack entries (kind &"bending") for enemy firebenders that
## get these techniques in a technique slot (EnemyAbilities / archetype data):
##   bc.set_slot(&"technique_2", AbilityRegistry.get_def(&"fire_burst"))
##   archetype["attacks"].append(FireKit.enemy_attacks()[&"fire_burst"])
static func enemy_attacks() -> Dictionary:
	return {
		&"fire_burst": {"id": &"fire_burst", "kind": &"bending", "clip": &"fire_burst_blast", "windup": 0.18, "approach": 0.12, "telegraph": 0.42,
			"range": Vector2(0.0, 3.4), "cooldown": 7.0, "weight": 1.1, "glint": &"hands", "ring": 3.8, "bending": {"slot": &"technique_2"},
			"recover": 0.5, "armor": 30.0},
		&"fire_ring": {"id": &"fire_ring", "kind": &"bending", "clip": &"fire_ring_kick", "windup": 0.16, "approach": 0.12, "telegraph": 0.45,
			"range": Vector2(0.0, 6.0), "cooldown": 8.0, "weight": 0.9, "glint": &"foot_r", "ring": 6.5, "bending": {"slot": &"technique_3"},
			"recover": 0.55, "armor": 25.0},
		&"fire_whip": {"id": &"fire_whip", "kind": &"bending", "clip": &"fire_whip_lash", "windup": 0.2, "approach": 0.12, "telegraph": 0.4,
			"range": Vector2(2.5, 7.0), "cooldown": 6.5, "weight": 1.0, "glint": &"hand_r", "needs_los": true, "bending": {"slot": &"technique_4"},
			"recover": 0.55, "armor": 20.0},
	}
