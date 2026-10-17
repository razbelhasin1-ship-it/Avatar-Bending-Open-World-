class_name WaterKit
extends RefCounted
## Water Tribe kit (docs/GAME_DESIGN.md §4 Water, docs/modules/bending_water.md):
## fluid, adaptive, defensive, versatile. Water is drawn from the nearest
## source (sea, lakes, canals, fountains, snow and ice); without one the bender
## uses the canteen: smaller water, +30% chi (WaterSource).
##
## Technique tree (unlock rules read by AbilityRegistry.can_unlock; the extra
## keys tier / branch / column are layout data for the skill-tree UI):
##   tier 1 (new game)  Ice Shards, Water Surge, Ice Wall
##   tier 2 (level 3)   Ice Trap  <- Ice Shards x8 practice     Water Wave <- Water Surge x6 practice
##   tier 3             Water Jet (level 5) <- Water Wave x6     Healing Waters (level 4, healer Yugoda)
##   tier 4 signature   Tidal Torrent (level 7) <- Water Jet, Master Pakku
## Trainer ids (GameState flag "trained_<trainer>_<ability>"): see TRAINERS.

const E := ElementDefs.Element.WATER
const R := HitInfo.Reaction
const DIR := "res://src/bending/kits/water/"
const ICONS := "res://src/bending/kits/water/icons/"

## Trainers referenced by the unlock rules (for the NPC / trainer module).
const TRAINERS := {
	&"wt_siku": {"name": "Master Siku", "region": &"water_tribe", "teaches": [&"healing_waters", &"tidal_torrent"]},
}


static func defs() -> Array[AbilityDef]:
	# Clips used by the Water techniques (also needed by rig-less casters' timelines).
	WaterClips.ensure()
	var out: Array[AbilityDef] = [
		AbilityDef.make({"id": &"water_whip", "element": E, "slot": AbilityDef.Slot.LIGHT, "display_name": "Water Whip",
			"description": "A flexible lash combo. The third lash wraps the target and yanks it toward you.",
			"icon": "res://assets/ui/ability_wave.svg", "startup": 0.09, "active": 0.12, "recovery": 0.3,
			"hit": {"damage": 7.0, "reaction": R.FLINCH, "force": 3.0, "poise": 8.0, "status": {"soaked": 3.0}},
			"params": {"steps": [
				{"clip": &"combo_water_1", "start": 0.38, "speed": 1.4, "event": &"impact", "chain_at": 0.86, "hand": &"hand_r", "reach": 5.2},
				{"clip": &"combo_water_2", "start": 0.38, "speed": 1.4, "event": &"impact", "chain_at": 0.86, "hand": &"hand_l", "reach": 5.2},
				{"clip": &"combo_water_3", "start": 0.48, "speed": 1.2, "event": &"impact", "hand": &"hands", "reach": 5.8, "pull": true,
					"hit": {"damage": 10.0, "reaction": R.PULL, "force": 7.0, "stun": 0.5, "poise": 20.0}},
			], "whip_radius": 0.42},
			"fx": {"vfx": &"water_stream", "sfx": &"cast_light"}, "script_path": DIR + "water_whip.gd"}),
		AbilityDef.make({"id": &"water_blast", "element": E, "slot": AbilityDef.Slot.HEAVY, "display_name": "Water Blast / Torrent",
			"description": "Tap: a concentrated water projectile. Hold: gather a stream around the body and release it as a crushing torrent.",
			"icon": "res://assets/ui/ability_wave.svg", "chi_cost": 10.0, "charge_time": 1.2, "max_hold": 3.5,
			"hit": {"damage": 14.0, "reaction": R.KNOCKBACK, "force": 6.0, "poise": 22.0, "heavy": true, "status": {"soaked": 5.0}},
			"params": {"hold_clip": &"water_gather_hold", "release_clip": &"water_surge", "release_start": 0.25, "tap_clip": &"water_jab_r",
				"tap_start": 0.3, "tap_time": 0.2, "min_windup": 0.1, "charge_chi": 14.0, "walk_scale": 0.35, "speed": 30.0},
			"fx": {"vfx": &"torrent", "sfx": &"cast_heavy", "charge": &"charge_loop"}, "script_path": DIR + "water_blast.gd"}),
		AbilityDef.make({"id": &"water_shield", "element": E, "slot": AbilityDef.Slot.DEFENSE, "display_name": "Water Shield",
			"description": "A rotating barrier of water. Perfect timing redirects projectiles and freezes melee attackers.",
			"icon": "res://assets/ui/ability_shield.svg", "clip": &"",
			"params": {"reduction": 0.8, "arc": 110.0, "upkeep": 4.0, "deflect": true, "redirect": true, "walk_scale": 0.45, "counter_damage": 4.0},
			"fx": {"vfx": &"water_ring", "sfx": &"shield_loop"}, "script_path": DIR + "water_shield.gd"}),
		AbilityDef.make({"id": &"flow_slide", "element": E, "slot": AbilityDef.Slot.DODGE, "display_name": "Flow Slide",
			"description": "A smooth slide roll on a sheet of water (4 m, 0.26 s i-frames). A perfect dodge briefly slows time.",
			"icon": "res://assets/ui/ability_wave.svg",
			"params": {"clips": {"fwd": &"dodge_roll", "back": &"dodge_back", "left": &"dodge_water_slide_l", "right": &"dodge_water_slide_r"}, "recovery": 0.14,
				"slowmo_scale": 0.35, "slowmo_time": 0.55},
			"fx": {"vfx": &"spray", "sfx": &"dash"}, "script_path": DIR + "flow_slide.gd"}),
		# --- tier 1: starters -----------------------------------------------------------------
		AbilityDef.make({"id": &"ice_shards", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Ice Shards",
			"description": "Draw water from the nearest source, freeze it into three ice daggers and hurl them. Soaked targets are flash-frozen.",
			"icon": "res://assets/ui/ability_shards.svg", "chi_cost": 22.0, "cooldown": 5.0, "clip": &"water_draw", "clip_speed": 1.15,
			"startup": 0.55, "recovery": 0.25, "starter": true, "unlock": {"level": 1, "tier": 1, "branch": &"ice", "column": 0},
			"hit": {"damage": 9.0, "reaction": R.FLINCH, "force": 2.5, "poise": 10.0, "deflectable": true, "status": {"chill": 2.0}},
			"params": {"count": 3, "speed": 34.0, "spread_deg": 6.0, "range": 30.0, "flash_freeze": 0.9},
			"fx": {"vfx": &"ice_shard", "sfx": &"freeze"}, "script_path": DIR + "ice_shards.gd"}),
		AbilityDef.make({"id": &"water_surge", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Water Surge",
			"description": "Heave a great mass of water out of the nearest source and drive it down into a crashing wave that rolls over everything ahead: knocks back, soaks, carries foes away and puts out fires.",
			"icon": "res://assets/ui/ability_wave.svg", "chi_cost": 26.0, "cooldown": 7.0, "clip": &"water_surge_heave", "clip_speed": 1.1,
			"startup": 0.68, "active": 0.7, "recovery": 0.35, "starter": true, "poise_armor": 25.0,
			"unlock": {"level": 1, "tier": 1, "branch": &"flow", "column": 1},
			"hit": {"damage": 18.0, "reaction": R.KNOCKBACK, "force": 9.0, "lift": 2.5, "poise": 35.0, "heavy": true, "status": {"soaked": 6.0}},
			"params": {"speed": 14.0, "distance": 10.0, "width": 4.6, "height": 2.2, "start_ahead": 1.6, "carry": 0.55},
			"fx": {"vfx": &"water_wave", "sfx": &"surge"}, "script_path": DIR + "water_surge.gd"}),
		AbilityDef.make({"id": &"ice_wall", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Ice Wall",
			"description": "Lift a sheet of water and freeze it into a wall of ice that blocks attacks and movement. Broken by enemies, it shatters into flying shards. On water it stands on a fresh ice floe.",
			"icon": "res://assets/ui/ability_wall.svg", "chi_cost": 28.0, "cooldown": 9.0, "clip": &"water_ice_wall", "clip_speed": 1.15,
			"startup": 0.41, "active": 0.22, "recovery": 0.3, "starter": true,
			"unlock": {"level": 1, "tier": 1, "branch": &"ice", "column": 2},
			"params": {"distance": 3.4, "size": Vector3(4.6, 2.8, 0.9), "hp": 150.0, "lifetime": 10.0, "rise_time": 0.22, "lift": 5.0, "launch_damage": 6.0,
				"shards": 7, "floe_radius": 3.0,
				"shard_hit": {"damage": 7.0, "reaction": R.FLINCH, "force": 3.0, "poise": 10.0, "deflectable": true, "status": {"chill": 2.0}}},
			"fx": {"vfx": &"ice_wall", "sfx": &"wall"}, "script_path": DIR + "ice_wall.gd"}),
		# --- tier 2 -------------------------------------------------------------------------------
		AbilityDef.make({"id": &"ice_trap", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Ice Trap",
			"description": "Send water skimming along the ground to the target's feet and freeze it: encases them in ice (longer when soaked). Missed, the frozen patch stays armed; on open water it freezes a walkable floe.",
			"icon": ICONS + "ability_ice_trap.svg", "chi_cost": 24.0, "cooldown": 8.0, "clip": &"water_ice_trap", "clip_speed": 1.1,
			"startup": 0.33, "active": 0.27, "recovery": 0.25,
			"unlock": {"level": 3, "prerequisite": &"ice_shards", "practice": 8, "cost": 1, "tier": 2, "branch": &"ice", "column": 0},
			"hit": {"damage": 8.0, "reaction": R.FREEZE, "stun": 2.0, "poise": 40.0, "status": {"frozen": 2.0, "chill": 3.0}},
			"params": {"range": 14.0, "default_distance": 8.0, "radius": 1.4, "stun": 2.0, "armed_time": 4.0, "floe_radius": 2.6, "floe_lifetime": 14.0},
			"fx": {"vfx": &"ice_prison", "sfx": &"freeze"}, "script_path": DIR + "ice_trap.gd"}),
		AbilityDef.make({"id": &"water_wave", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Water Wave",
			"description": "Hold to raise a wave under your feet and ride it over ground or water, bowling enemies aside. Release to crash it forward. Over open water you land on a frozen floe.",
			"icon": ICONS + "ability_water_wave.svg", "chi_cost": 22.0, "cooldown": 8.0, "startup": 0.15, "active": 2.6, "recovery": 0.4, "poise_armor": 30.0,
			"unlock": {"level": 3, "prerequisite": &"water_surge", "practice": 6, "cost": 1, "tier": 2, "branch": &"flow", "column": 1},
			"hit": {"damage": 16.0, "reaction": R.KNOCKDOWN, "force": 8.0, "lift": 2.0, "stun": 0.9, "poise": 45.0, "heavy": true, "status": {"soaked": 6.0}},
			"params": {"speed": 12.0, "turn_rate": 110.0, "max_ride": 2.6, "min_ride": 0.45, "upkeep": 9.0, "crash_distance": 5.0,
				"ride_hit": {"damage": 10.0, "reaction": R.KNOCKBACK, "force": 9.0, "lift": 1.5, "poise": 30.0, "status": {"soaked": 5.0}}},
			"fx": {"vfx": &"water_wave", "sfx": &"surge"}, "script_path": DIR + "water_wave.gd"}),
		# --- tier 3 -------------------------------------------------------------------------------
		AbilityDef.make({"id": &"water_jet", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Water Jet",
			"description": "Hold to pour a pressurised jet from your palms that follows your aim: steady damage, pushes foes back, soaks them and douses fires along its length.",
			"icon": ICONS + "ability_water_jet.svg", "chi_cost": 10.0, "cooldown": 6.0, "clip": &"water_jet_open", "startup": 0.28, "active": 3.0, "recovery": 0.2,
			"unlock": {"level": 5, "prerequisite": &"water_wave", "practice": 6, "cost": 1, "tier": 3, "branch": &"flow", "column": 1},
			"hit": {"damage": 3.5, "reaction": R.FLINCH, "force": 5.0, "poise": 7.0, "status": {"soaked": 4.0}},
			"params": {"range": 12.0, "radius": 0.3, "pulse": 0.15, "upkeep": 16.0, "max_hold": 3.0, "min_hold": 0.35, "walk_scale": 0.25, "push_speed": 3.5},
			"fx": {"vfx": &"water_stream", "sfx": &"shield_loop"}, "script_path": DIR + "water_jet.gd"}),
		AbilityDef.make({"id": &"healing_waters", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Healing Waters",
			"description": "Hold to draw water into your hands, where it glows, and press it to your wounds: heals up to 35 health per use (allies close by get half). Leaves you rooted; a staggering hit breaks it.",
			"icon": ICONS + "ability_healing.svg", "chi_cost": 25.0, "cooldown": 18.0, "clip": &"water_heal_channel", "startup": 0.4, "active": 3.5, "recovery": 0.25,
			"unlock": {"level": 4, "trainer": &"wt_siku", "cost": 1, "tier": 3, "branch": &"healing", "column": 2},
			"params": {"rate": 10.0, "max_heal": 35.0, "upkeep": 6.0, "max_hold": 4.0, "min_hold": 0.5, "ally_radius": 3.5},
			"fx": {"vfx": &"healing_glow", "sfx": &"heal_loop"}, "script_path": DIR + "healing_waters.gd"}),
		# --- tier 4: signature --------------------------------------------------------------------
		AbilityDef.make({"id": &"tidal_torrent", "element": E, "slot": AbilityDef.Slot.SIGNATURE, "display_name": "Tidal Torrent",
			"description": "Call in all the water around you and rise at the heart of a huge spiralling vortex that drags enemies in, then drive it outward: a ring of water knocks everyone down and a towering wave rolls ahead.",
			"icon": ICONS + "ability_tidal.svg", "focus_cost": 100.0, "clip": &"tidal_torrent", "startup": 0.78, "active": 1.45, "recovery": 0.8,
			"unlock": {"level": 7, "prerequisite": &"water_jet", "trainer": &"wt_siku", "cost": 2, "tier": 4, "branch": &"flow", "column": 1},
			"hit": {"damage": 34.0, "reaction": R.KNOCKDOWN, "force": 14.0, "lift": 4.0, "stun": 1.2, "poise": 80.0, "heavy": true, "status": {"soaked": 8.0}},
			"params": {"vortex_radius": 3.6, "vortex_height": 6.0, "lift": 1.3, "pulse": 0.25, "pull_radius": 9.0, "launch_radius": 3.4,
				"ring_radius": 10.0, "wave_distance": 15.0, "damage_reduction": 0.5},
			"fx": {"vfx": &"water_vortex", "sfx": &"special"}, "script_path": DIR + "tidal_torrent.gd"}),
	]
	return out


## The technique tree for the skill-tree UI: tiers of {id, tier, branch, column,
## requires (prerequisite id), level, practice, trainer, cost}, starters first.
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
