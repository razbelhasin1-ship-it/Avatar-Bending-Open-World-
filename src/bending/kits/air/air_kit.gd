class_name AirKit
extends RefCounted
## Air Nomad kit (docs/GAME_DESIGN.md §4 Air, docs/modules/bending_air.md): fast,
## evasive, acrobatic. Every gust is a travelling volume (pierce projectile) or an
## expanding front, so hits land exactly when the visible wind reaches the target.
##
##   AirKit.defs()            # every Air AbilityDef (registered by AbilityRegistry)
##   AirKit.tree()            # technique tree for the skill-tree UI
##   AirKit.TRAINERS          # trainer ids (NPC module) and what they teach
##   AirKit.enemy_attacks()   # EnemyActions entries for air-bending enemies

const E := ElementDefs.Element.AIR
const R := HitInfo.Reaction
const DIR := "res://src/bending/kits/air/"
const ICONS := "res://src/bending/kits/air/icons/"

## Masters who teach Air techniques (unlock.trainer ids). A lesson sets
## GameState flag "trained_<trainer>_<ability>" (AbilityRegistry.can_unlock).
const TRAINERS := {
	&"at_tashi": {"name": "Master Tashi", "where": "Southern Air Temple, the sanctum under the great spire",
		"teaches": [&"vortex_ward", &"air_tornado"]},
}

## Skill-tree branches (UI labels).
const BRANCHES := {&"gale": "Gale", &"circle": "Circle", &"flight": "Flight"}


static func defs() -> Array[AbilityDef]:
	AirCommon.prepare()
	var out: Array[AbilityDef] = [
		AbilityDef.make({"id": &"air_combo", "element": E, "slot": AbilityDef.Slot.LIGHT, "display_name": "Air Combo",
			"description": "Palm gust, spinning hook-kick gust, double-palm burst. Each strike drives the target back; the third staggers. In the air every strike holds you aloft.",
			"icon": "res://assets/ui/ability_blast.svg", "startup": 0.08, "active": 0.2, "recovery": 0.25,
			"hit": {"damage": 7.0, "reaction": R.FLINCH, "force": 5.0, "poise": 9.0},
			"params": {"steps": [
				{"clip": &"combo_air_1", "start": 0.28, "speed": 1.15, "event": &"impact", "chain_at": 0.7, "hand": &"hand_l",
					"gust": {"radius": 0.55, "grow": 1.4, "speed": 36.0, "range": 7.0, "env": 0.35}},
				{"clip": &"air_combo_kick", "start": 0.27, "speed": 1.25, "event": &"impact", "chain_at": 0.66, "hand": &"foot_r",
					"hit": {"damage": 8.0, "force": 6.5, "poise": 12.0}, "gust": {"radius": 0.75, "grow": 2.4, "speed": 32.0, "range": 6.5, "low": true, "env": 0.5}},
				{"clip": &"combo_air_3", "start": 0.5, "speed": 1.15, "event": &"release", "hand": &"hands",
					"hit": {"damage": 11.0, "reaction": R.STAGGER, "force": 9.0, "stun": 0.45, "poise": 24.0},
					"gust": {"radius": 0.7, "grow": 2.0, "speed": 38.0, "range": 9.0, "env": 0.7}},
			], "air_lift": 0.6},
			"fx": {"vfx": &"air_gust", "sfx": &"cast_light"}, "script_path": DIR + "air_combo.gd"}),
		AbilityDef.make({"id": &"air_blast", "element": E, "slot": AbilityDef.Slot.HEAVY, "display_name": "Air Blast",
			"description": "Tap: a fast gust that staggers and pushes. Hold: wind spirals into a ball between the palms; release a wide blast that hurls enemies back. High in the air: Gale Drop, a dive that slams a ring of wind into the ground.",
			"icon": "res://assets/ui/ability_blast.svg", "chi_cost": 10.0, "startup": 0.3, "charge_time": 1.0, "max_hold": 3.0,
			"hit": {"damage": 14.0, "reaction": R.STAGGER, "force": 8.5, "stun": 0.5, "poise": 25.0, "heavy": true},
			"params": {"hold_clip": &"air_charge_hold", "release_clip": &"air_charge_release", "release_start": 0.1,
				"tap_clip": &"air_blast", "tap_start": 0.28, "tap_time": 0.2, "min_windup": 0.1, "charge_chi": 14.0, "walk_scale": 0.35,
				"dive_height": 2.4, "dive_speed": 24.0, "dive_radius": 3.8, "dive_max": 1.6,
				"dive_hit": {"damage": 18.0, "reaction": R.KNOCKDOWN, "force": 10.0, "lift": 2.5, "stun": 1.1, "poise": 42.0, "heavy": true}},
			"fx": {"vfx": &"air_gust", "sfx": &"cast_heavy", "charge": &"charge_loop"}, "script_path": DIR + "air_blast.gd"}),
		AbilityDef.make({"id": &"air_shield", "element": E, "slot": AbilityDef.Slot.DEFENSE, "display_name": "Air Shield",
			"description": "A spinning current that blocks 70% from the front and turns projectiles aside. Perfect timing sends projectiles back and blows melee attackers off their feet.",
			"icon": "res://assets/ui/ability_shield.svg", "clip": &"",
			"params": {"reduction": 0.7, "arc": 100.0, "upkeep": 4.0, "deflect": true, "redirect": true, "walk_scale": 0.55, "counter_damage": 5.0},
			"fx": {"vfx": &"air_swirl", "sfx": &"shield_loop"}, "script_path": DIR + "air_shield.gd"}),
		AbilityDef.make({"id": &"air_dash", "element": E, "slot": AbilityDef.Slot.DODGE, "display_name": "Air Dash",
			"description": "A long wind-assisted dash with invulnerability, twice per jump in the air. A perfect dodge leaves a gust behind that knocks the attacker back.",
			"icon": "res://assets/ui/ability_whirl.svg",
			"params": {"clips": {"fwd": &"air_dash", "back": &"dodge_flip", "left": &"dodge_side_l", "right": &"dodge_side_r"}, "in_air": true, "recovery": 0.1,
				"air_dashes": 2, "perfect_hit": {"damage": 4.0, "reaction": R.KNOCKBACK, "force": 9.0, "lift": 1.0, "poise": 20.0}},
			"fx": {"vfx": &"air_gust", "sfx": &"dash"}, "script_path": DIR + "air_dash.gd"}),
		AbilityDef.make({"id": &"air_jump", "element": E, "slot": AbilityDef.Slot.INNATE, "display_name": "Air Jump",
			"description": "Jump again in mid-air; hold jump while falling to glide. Landings are cushioned by the wind.",
			"icon": "res://assets/ui/ability_whirl.svg", "fx": {"sfx": &"jump"}, "script_path": ""}),
		# --- techniques -----------------------------------------------------------------------
		AbilityDef.make({"id": &"air_push", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Air Push",
			"description": "Gather the air between the palms, then throw both palms out: a ring of wind bursts outward and clears space. Knocks down whoever is close, blows the rest back, scatters projectiles. Hold to charge a wider ring.",
			"icon": ICONS + "ability_air_push.svg", "chi_cost": 16.0, "cooldown": 4.0, "clip": &"air_push_release", "clip_speed": 1.15,
			"startup": 0.12, "active": 0.22, "recovery": 0.35, "charge_time": 0.8, "max_hold": 2.0, "starter": true, "poise_armor": 15.0,
			"unlock": {"level": 1, "tier": 1, "branch": &"gale", "column": 0},
			"hit": {"damage": 8.0, "reaction": R.KNOCKBACK, "force": 10.0, "lift": 1.5, "poise": 26.0, "heavy": true},
			"params": {"hold_clip": &"air_push_gather", "release_start": 0.1, "release_speed": 1.15, "radius": 4.4, "radius_full": 6.8, "close": 2.0, "close_full": 3.0, "front_time": 0.2,
				"front_time_full": 0.28, "charge_chi": 10.0, "tap_time": 0.18, "in_air": true, "ai_hold": 0.0,
				"close_hit": {"damage": 12.0, "reaction": R.KNOCKDOWN, "force": 11.0, "lift": 2.5, "stun": 1.0, "poise": 40.0}},
			"fx": {"vfx": &"air_wave", "sfx": &"push"}, "script_path": DIR + "air_push.gd"}),
		AbilityDef.make({"id": &"air_sweep", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Air Sweep",
			"description": "A 360° circular sweep kick that knocks back every enemy around you.",
			"icon": "res://assets/ui/ability_sweep.svg", "chi_cost": 22.0, "cooldown": 5.5, "clip": &"air_sweep", "clip_speed": 1.15,
			"startup": 0.33, "active": 0.15, "recovery": 0.35, "starter": true, "unlock": {"level": 1, "tier": 1, "branch": &"circle", "column": 1},
			"hit": {"damage": 14.0, "reaction": R.KNOCKBACK, "force": 11.0, "lift": 2.0, "poise": 32.0, "heavy": true},
			"params": {"radius": 4.6}, "fx": {"vfx": &"air_swirl", "sfx": &"cast_heavy"}, "script_path": DIR + "air_sweep.gd"}),
		AbilityDef.make({"id": &"wind_blade", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Wind Blade",
			"description": "A spinning crescent kick compresses the air into a thin blade that slices through every enemy in its path. In the air: a flipping axe kick sends it down at an angle.",
			"icon": ICONS + "ability_wind_blade.svg", "chi_cost": 18.0, "cooldown": 3.5, "clip": &"wind_blade_kick", "clip_speed": 1.2,
			"startup": 0.28, "active": 0.6, "recovery": 0.3,
			"unlock": {"level": 3, "prerequisite": &"air_push", "practice": 6, "cost": 1, "tier": 2, "branch": &"gale", "column": 0},
			"hit": {"damage": 16.0, "reaction": R.STAGGER, "force": 6.5, "stun": 0.5, "poise": 30.0, "heavy": true, "deflectable": true},
			"params": {"air_clip": &"wind_blade_air", "speed": 40.0, "range": 24.0, "half_width": 1.25, "in_air": true, "air_lift": 2.5},
			"fx": {"vfx": &"wind_blade", "sfx": &"cast_heavy"}, "script_path": DIR + "wind_blade.gd"}),
		AbilityDef.make({"id": &"air_scooter", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Air Scooter",
			"description": "Ride a spinning ball of air: fast travel, carving turns, skimming over water and short runs up walls. Jump to launch off, press again to hop down. No attacks while riding; chi drains.",
			"icon": ICONS + "ability_air_scooter.svg", "chi_cost": 12.0, "cooldown": 1.5, "clip": &"air_scooter_ride",
			"startup": 0.1, "active": 20.0, "recovery": 0.2,
			"unlock": {"level": 3, "prerequisite": &"air_sweep", "practice": 6, "cost": 1, "tier": 2, "branch": &"flight", "column": 2},
			"params": {"speed": 16.5, "accel": 24.0, "turn": 210.0, "upkeep": 4.0, "ball_radius": 0.5, "ride_height": 0.9,
				"wall_time": 0.9, "wall_speed": 8.5, "jump_off": 8.5, "max_time": 22.0, "ai_time": 5.0, "water": true},
			"fx": {"vfx": &"air_ball", "sfx": &"special_loop"}, "script_path": DIR + "air_scooter.gd"}),
		AbilityDef.make({"id": &"vortex_ward", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Vortex Ward",
			"description": "Wrap yourself in a spinning sphere of wind for a few seconds: projectiles from every side are caught and whirled around you, then flung back when it bursts; anyone who steps in close is blown away.",
			"icon": ICONS + "ability_vortex_ward.svg", "chi_cost": 24.0, "cooldown": 10.0, "clip": &"vortex_ward_hold",
			"startup": 0.15, "active": 3.5, "recovery": 0.3,
			"unlock": {"level": 5, "prerequisite": &"air_scooter", "practice": 6, "trainer": "at_tashi", "cost": 1, "tier": 3, "branch": &"circle", "column": 1},
			"hit": {"damage": 6.0, "reaction": R.KNOCKBACK, "force": 12.0, "lift": 1.8, "poise": 30.0, "heavy": true},
			"params": {"duration": 3.5, "radius": 1.6, "reach": 2.4, "pulse": 0.35, "walk_scale": 0.55, "fling_speed_mult": 1.2,
				"burst_hit": {"damage": 10.0, "reaction": R.KNOCKBACK, "force": 13.0, "lift": 2.0, "poise": 34.0, "heavy": true}, "burst_radius": 3.6},
			"fx": {"vfx": &"air_ward", "sfx": &"shield_loop"}, "script_path": DIR + "vortex_ward.gd"}),
		AbilityDef.make({"id": &"air_tornado", "element": E, "slot": AbilityDef.Slot.SIGNATURE, "display_name": "Air Tornado",
			"description": "Spin up a tornado at the target: it drags everyone around it in, lifts them spinning up the column, and when the palms rise it throws them out into the sky.",
			"icon": ICONS + "ability_air_tornado.svg", "focus_cost": 100.0, "clip": &"air_tornado_cast", "clip_speed": 1.0,
			"startup": 0.52, "active": 1.7, "recovery": 0.4, "poise_armor": 60.0,
			"unlock": {"level": 7, "prerequisite": &"wind_blade", "trainer": "at_tashi", "cost": 2, "tier": 4, "branch": &"gale", "column": 1},
			"hit": {"damage": 0.0, "reaction": R.PULL, "force": 6.0, "stun": 0.4, "poise": 14.0},
			"params": {"distance": 6.0, "max_distance": 14.0, "pull_radius": 7.5, "capture_radius": 2.4, "height": 9.0, "funnel_radius": 3.4,
				"pulse": 0.22, "drift": 2.2, "orbit_radius": 1.7, "orbit_speed": 4.2, "lift_top": 4.2, "damage_reduction": 0.5,
				"lift_hit": {"damage": 4.0, "reaction": R.LAUNCH, "force": 2.0, "lift": 6.0, "poise": 30.0},
				"release_hit": {"damage": 30.0, "reaction": R.LAUNCH, "force": 15.0, "lift": 9.0, "poise": 80.0, "heavy": true, "unblockable": true}},
			"fx": {"vfx": &"air_vortex", "sfx": &"special_loop"}, "script_path": DIR + "air_tornado.gd"}),
	]
	return out


## Technique tree for the skill-tree UI (same format as the other elements):
## [{id, tier, branch, column, requires, level, practice, trainer, cost, starter, signature}]
## sorted by tier then column. Core-kit moves are not part of the tree.
static func tree() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in AbilityRegistry.for_element(E):
		if d.slot != AbilityDef.Slot.TECHNIQUE and d.slot != AbilityDef.Slot.SIGNATURE:
			continue
		var u := d.unlock
		out.append({"id": d.id, "tier": int(u.get("tier", 1)), "branch": StringName(u.get("branch", &"gale")), "column": int(u.get("column", 0)),
			"requires": StringName(u.get("prerequisite", &"")), "level": int(u.get("level", 1)), "practice": int(u.get("practice", 0)),
			"trainer": StringName(str(u.get("trainer", ""))), "cost": int(u.get("cost", 0 if d.starter else 1)), "starter": d.starter,
			"signature": d.slot == AbilityDef.Slot.SIGNATURE})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["tier"]) < int(b["tier"]) or (int(a["tier"]) == int(b["tier"]) and int(a["column"]) < int(b["column"])))
	return out


## Ready EnemyActions entries (docs/modules/enemies.md "Attack dictionary") for an
## air-bending enemy whose controller has these techniques in the named slots:
##   bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"air_push"))
##   archetype["attacks"].append(AirKit.enemy_attacks()[&"air_push"])
static func enemy_attacks() -> Dictionary:
	return {
		&"air_push": {"id": &"air_push", "kind": &"bending", "clip": &"air_push_release", "windup": 0.15, "approach": 0.1, "telegraph": 0.42,
			"range": Vector2(0.0, 3.6), "cooldown": 6.0, "weight": 1.2, "glint": &"hands", "ring": 4.4, "bending": {"slot": &"technique_1"},
			"recover": 0.45, "armor": 15.0, "tag": &"space"},
		&"air_sweep": {"id": &"air_sweep", "kind": &"bending", "clip": &"air_sweep", "windup": 0.18, "approach": 0.12, "telegraph": 0.45,
			"range": Vector2(0.0, 4.0), "cooldown": 7.0, "weight": 0.9, "glint": &"foot_r", "ring": 4.6, "bending": {"slot": &"technique_2"},
			"recover": 0.5, "armor": 20.0},
		&"wind_blade": {"id": &"wind_blade", "kind": &"bending", "clip": &"wind_blade_kick", "windup": 0.22, "approach": 0.12, "telegraph": 0.45,
			"range": Vector2(3.0, 16.0), "cooldown": 5.0, "weight": 1.0, "glint": &"foot_r", "needs_los": true, "bending": {"slot": &"technique_3"},
			"recover": 0.5},
		&"air_tornado": {"id": &"air_tornado", "kind": &"bending", "clip": &"air_tornado_cast", "windup": 0.05, "approach": 0.12, "telegraph": 0.6,
			"range": Vector2(2.0, 12.0), "cooldown": 22.0, "weight": 0.5, "glint": &"hands", "ring": 7.5, "needs_los": true,
			"bending": {"slot": &"signature"}, "recover": 0.7, "armor": 60.0},
	}
