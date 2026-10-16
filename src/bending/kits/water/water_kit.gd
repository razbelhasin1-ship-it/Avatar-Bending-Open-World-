extends RefCounted
## Water Tribe core kit (docs/GAME_DESIGN.md §4 Water): fluid, adaptive,
## defensive. Water is drawn from the nearest source (sea, lakes, canals,
## fountains, snow and ice); without one the bender uses the canteen:
## smaller water, +30% chi (WaterSource).

const E := ElementDefs.Element.WATER
const R := HitInfo.Reaction
const DIR := "res://src/bending/kits/water/"


static func defs() -> Array[AbilityDef]:
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
		AbilityDef.make({"id": &"ice_shards", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Ice Shards",
			"description": "Draw water from the nearest source, freeze it into three ice daggers and hurl them.",
			"icon": "res://assets/ui/ability_shards.svg", "chi_cost": 22.0, "cooldown": 5.0, "clip": &"water_draw", "clip_speed": 1.15,
			"startup": 0.55, "recovery": 0.25, "starter": true, "unlock": {"level": 1},
			"hit": {"damage": 9.0, "reaction": R.FLINCH, "force": 2.5, "poise": 10.0, "deflectable": true, "status": {"chill": 2.0}},
			"params": {"count": 3, "speed": 34.0, "spread_deg": 6.0, "range": 30.0},
			"fx": {"vfx": &"ice_shard", "sfx": &"freeze"}, "script_path": DIR + "ice_shards.gd"}),
	]
	return out
