extends RefCounted
## Air Nomad core kit (docs/GAME_DESIGN.md §4 Air): fast, evasive, acrobatic.
## Every gust is a travelling volume (pierce projectile) so hits land exactly
## when the visible current reaches the target.

const E := ElementDefs.Element.AIR
const R := HitInfo.Reaction
const DIR := "res://src/bending/kits/air/"


static func defs() -> Array[AbilityDef]:
	var out: Array[AbilityDef] = [
		AbilityDef.make({"id": &"air_combo", "element": E, "slot": AbilityDef.Slot.LIGHT, "display_name": "Air Combo",
			"description": "Palm gust, spinning kick gust, double-palm burst. Each pushes; the third staggers.",
			"icon": "res://assets/ui/ability_blast.svg", "startup": 0.09, "active": 0.2, "recovery": 0.25,
			"hit": {"damage": 7.0, "reaction": R.FLINCH, "force": 4.5, "poise": 8.0},
			"params": {"steps": [
				{"clip": &"combo_air_1", "start": 0.24, "speed": 1.1, "event": &"impact", "chain_at": 0.72, "hand": &"hand_l",
					"gust": {"radius": 0.55, "grow": 1.6, "speed": 30.0, "range": 7.0}},
				{"clip": &"combo_air_2", "start": 0.24, "speed": 1.15, "event": &"impact", "chain_at": 0.74, "hand": &"foot_r",
					"hit": {"damage": 8.0, "force": 5.5}, "gust": {"radius": 0.7, "grow": 2.4, "speed": 28.0, "range": 6.5, "low": true}},
				{"clip": &"combo_air_3", "start": 0.48, "speed": 1.15, "event": &"release", "hand": &"hands",
					"hit": {"damage": 11.0, "reaction": R.STAGGER, "force": 8.0, "stun": 0.45, "poise": 22.0},
					"gust": {"radius": 0.7, "grow": 2.0, "speed": 34.0, "range": 9.0}},
			]},
			"fx": {"vfx": &"air_gust", "sfx": &"cast_light"}, "script_path": DIR + "air_combo.gd"}),
		AbilityDef.make({"id": &"air_blast", "element": E, "slot": AbilityDef.Slot.HEAVY, "display_name": "Air Blast",
			"description": "Tap: a fast gust that staggers and pushes. Hold: a wider charged blast that hurls enemies back.",
			"icon": "res://assets/ui/ability_blast.svg", "chi_cost": 10.0, "startup": 0.3, "charge_time": 1.0, "max_hold": 3.0,
			"hit": {"damage": 14.0, "reaction": R.STAGGER, "force": 8.0, "stun": 0.5, "poise": 25.0, "heavy": true},
			"params": {"hold_clip": &"air_charge_hold", "release_clip": &"air_charge_release", "release_start": 0.1,
				"tap_clip": &"air_blast", "tap_start": 0.28, "tap_time": 0.2, "min_windup": 0.1, "charge_chi": 14.0, "walk_scale": 0.35},
			"fx": {"vfx": &"air_gust", "sfx": &"cast_heavy", "charge": &"charge_loop"}, "script_path": DIR + "air_blast.gd"}),
		AbilityDef.make({"id": &"air_shield", "element": E, "slot": AbilityDef.Slot.DEFENSE, "display_name": "Air Shield",
			"description": "A spinning current that blocks 70% and deflects projectiles. Perfect timing redirects them back.",
			"icon": "res://assets/ui/ability_shield.svg", "clip": &"",
			"params": {"reduction": 0.7, "arc": 100.0, "upkeep": 4.0, "deflect": true, "redirect": true, "walk_scale": 0.5, "counter_damage": 5.0},
			"fx": {"vfx": &"air_swirl", "sfx": &"shield_loop"}, "script_path": DIR + "air_shield.gd"}),
		AbilityDef.make({"id": &"air_dash", "element": E, "slot": AbilityDef.Slot.DODGE, "display_name": "Air Dash",
			"description": "A long wind-assisted dash with invulnerability. Works in the air.",
			"icon": "res://assets/ui/ability_whirl.svg",
			"params": {"clips": {"fwd": &"air_dash", "back": &"dodge_flip", "left": &"dodge_side_l", "right": &"dodge_side_r"}, "in_air": true, "recovery": 0.1},
			"fx": {"vfx": &"air_gust", "sfx": &"dash"}, "script_path": DIR + "air_dash.gd"}),
		AbilityDef.make({"id": &"air_jump", "element": E, "slot": AbilityDef.Slot.INNATE, "display_name": "Air Jump",
			"description": "Jump again in mid-air; hold jump while falling to glide. Landings are cushioned.",
			"icon": "res://assets/ui/ability_whirl.svg", "fx": {"sfx": &"jump"}, "script_path": ""}),
		AbilityDef.make({"id": &"air_sweep", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Air Sweep",
			"description": "A 360° circular sweep kick that knocks back every enemy around you.",
			"icon": "res://assets/ui/ability_sweep.svg", "chi_cost": 25.0, "cooldown": 6.0, "clip": &"air_sweep", "clip_speed": 1.1,
			"startup": 0.35, "active": 0.15, "recovery": 0.35, "starter": true, "unlock": {"level": 1},
			"hit": {"damage": 14.0, "reaction": R.KNOCKBACK, "force": 11.0, "lift": 2.0, "poise": 32.0, "heavy": true},
			"params": {"radius": 4.6}, "fx": {"vfx": &"air_swirl", "sfx": &"cast_heavy"}, "script_path": DIR + "air_sweep.gd"}),
	]
	return out
