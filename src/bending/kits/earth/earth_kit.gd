class_name EarthKit
extends RefCounted
## Earth Kingdom kit (docs/GAME_DESIGN.md §4 Earth, docs/modules/bending_earth.md):
## grounded, deliberate, forceful. Rock is always torn out of the ground first,
## in the colours of that ground; nothing to bend on ice, wood or deep water.
##
## Technique tree (unlock rules read by AbilityRegistry.can_unlock; the extra
## keys tier / branch / column are layout data for the skill-tree UI):
##   tier 1 (new game)  Earth Pillar, Earth Stomp, Earth Wall
##   tier 2 (level 3)   Earth Grab <- Earth Pillar x6 practice   Earth Spikes <- Earth Stomp x6 practice
##   tier 3 (level 5)   Earth Armor <- Earth Wall, Master Bao Shan
##   tier 4 signature   Earthquake (level 7) <- Earth Spikes, Master Bao Shan, 2 points
## Trainer ids (GameState flag "trained_<trainer>_<ability>"): see TRAINERS.

const E := ElementDefs.Element.EARTH
const R := HitInfo.Reaction
const DIR := "res://src/bending/kits/earth/"
const ICONS := "res://src/bending/kits/earth/icons/"

## Trainers referenced by the unlock rules (for the NPC / trainer module).
const TRAINERS := {
	&"ek_bao_shan": {"name": "Master Bao Shan", "region": &"earth_kingdom", "place": "Ba Sing Se, Middle Ring training hall",
		"teaches": [&"earth_armor", &"earthquake"]},
}


static func defs() -> Array[AbilityDef]:
	# Clips used by the Earth techniques (also needed by rig-less casters' timelines).
	EarthClips.ensure()
	var out: Array[AbilityDef] = [
		# --- core kit -----------------------------------------------------------------------------
		AbilityDef.make({"id": &"earth_punch", "element": E, "slot": AbilityDef.Slot.LIGHT, "display_name": "Earth Punch",
			"description": "Each punch stomps a chunk of rock out of the ground and drives it forward. Three hits; the third, two-handed, rips a bigger rock that knocks back. Without earth underfoot (ice, wood, deep water) the bender fights with stone-hard fists.",
			"icon": "res://assets/ui/ability_spikes.svg", "startup": 0.08, "active": 0.1, "recovery": 0.35, "poise_armor": 12.0,
			"hit": {"damage": 9.0, "reaction": R.FLINCH, "force": 3.0, "poise": 12.0},
			"params": {"steps": [
				{"clip": &"combo_earth_1", "start": 0.32, "speed": 1.15, "event": &"release", "chain_at": 0.8, "hand": &"hand_r", "rock": 0.2, "move": "brake"},
				{"clip": &"combo_earth_2", "start": 0.32, "speed": 1.15, "event": &"release", "chain_at": 0.8, "hand": &"hand_l", "rock": 0.2, "move": "brake"},
				{"clip": &"combo_earth_3", "start": 0.5, "speed": 1.1, "event": &"release", "hand": &"hands", "rock": 0.36, "move": "brake",
					"hit": {"damage": 16.0, "reaction": R.KNOCKBACK, "force": 8.0, "poise": 30.0, "heavy": true}},
			], "speed": 30.0, "range": 28.0, "fist_reach": 1.9, "fist_damage": 0.65},
			"fx": {"vfx": &"rock", "sfx": &"cast_light"}, "script_path": DIR + "earth_punch.gd"}),
		AbilityDef.make({"id": &"earth_boulder", "element": E, "slot": AbilityDef.Slot.HEAVY, "display_name": "Earth Boulder",
			"description": "Stomp a boulder out of the ground, hold to aim (and grow it), release to hurl it: heavy impact, knockdown, a crater where it lands.",
			"icon": "res://assets/ui/ability_wall.svg", "chi_cost": 14.0, "charge_time": 1.2, "max_hold": 4.0, "poise_armor": 45.0,
			"hit": {"damage": 26.0, "reaction": R.KNOCKDOWN, "force": 9.0, "lift": 3.0, "poise": 60.0, "heavy": true, "stun": 1.0},
			"params": {"lift_clip": &"earth_raise", "lift_speed": 1.3, "hold_clip": &"earth_hold", "throw_clip": &"earth_throw", "throw_start": 0.55,
				"throw_speed": 1.2, "charge_chi": 10.0, "speed": 24.0, "radius": 0.55, "splash": 2.2},
			"fx": {"vfx": &"boulder", "sfx": &"cast_heavy"}, "script_path": DIR + "earth_boulder.gd"}),
		AbilityDef.make({"id": &"earth_shield", "element": E, "slot": AbilityDef.Slot.DEFENSE, "display_name": "Earth Shield",
			"description": "A stone slab rises in front while held: blocks 90% from the front, breaks under sustained damage. A perfect block slams it into the attacker. With no earth underfoot only the forearms guard (50%).",
			"icon": "res://assets/ui/ability_shield.svg", "clip": &"earth_shield",
			"params": {"reduction": 0.9, "arc": 70.0, "upkeep": 3.0, "guard_hp": 80.0, "chi_per_block": 4.0, "walk_scale": 0.3, "counter_damage": 8.0,
				"bare_reduction": 0.5},
			"fx": {"vfx": &"slab", "sfx": &"shield_up"}, "script_path": DIR + "earth_shield.gd"}),
		AbilityDef.make({"id": &"earth_slide", "element": E, "slot": AbilityDef.Slot.DODGE, "display_name": "Earth Slide",
			"description": "A short slide riding the ground with full poise armor (no i-frames): ploughs a furrow and ends in a small shockwave.",
			"icon": "res://assets/ui/ability_wall.svg",
			"params": {"clips": {"fwd": &"earth_slide_fwd", "back": &"dodge_back", "left": &"dodge_earth_slide_l", "right": &"dodge_earth_slide_r"},
				"recovery": 0.14, "shock_radius": 2.4},
			"hit": {"damage": 4.0, "reaction": R.STAGGER, "force": 4.0, "stun": 0.4, "poise": 20.0},
			"fx": {"vfx": &"dust", "sfx": &"dash"}, "script_path": DIR + "earth_slide.gd"}),
		# --- tier 1: starters -----------------------------------------------------------------
		AbilityDef.make({"id": &"earth_pillar", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Earth Pillar",
			"description": "Stomp and drive both fists up: a stone column erupts beneath the target and launches it, then stands as cover and a platform. Without a target it rises at the aim point; hold the button to ride it up yourself.",
			"icon": ICONS + "ability_pillar.svg", "chi_cost": 22.0, "cooldown": 5.0, "clip": &"earth_pillar_raise", "clip_speed": 1.0,
			"startup": 0.38, "active": 0.16, "recovery": 0.35, "starter": true, "poise_armor": 25.0,
			"unlock": {"level": 1, "tier": 1, "branch": &"stone", "column": 0},
			"hit": {"damage": 14.0, "reaction": R.LAUNCH, "lift": 10.0, "force": 2.0, "poise": 45.0, "heavy": true, "unblockable": true},
			"params": {"range": 16.0, "distance": 5.0, "min_distance": 2.6, "max_spot": 9.0, "height": 2.8, "radius": 0.75, "hp": 120.0, "lifetime": 9.0,
				"rise_time": 0.16, "launch_radius": 1.15, "self_lift": true, "self_height": 3.0, "self_rise_time": 0.32, "max_stack": 6.0},
			"fx": {"vfx": &"pillar", "sfx": &"wall"}, "script_path": DIR + "earth_pillar.gd"}),
		AbilityDef.make({"id": &"earth_stomp", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Earth Stomp",
			"description": "Knee high, then slam the foot down: a shockwave rolls 5 m over the ground, staggering everyone standing on it, and leaves a cracked crater. Jumping clears it; walls stop it.",
			"icon": ICONS + "ability_stomp.svg", "chi_cost": 20.0, "cooldown": 6.0, "clip": &"earth_stomp_quake", "clip_speed": 1.1,
			"startup": 0.31, "active": 0.28, "recovery": 0.4, "starter": true, "poise_armor": 30.0,
			"unlock": {"level": 1, "tier": 1, "branch": &"seismic", "column": 1},
			"hit": {"damage": 12.0, "reaction": R.STAGGER, "force": 6.0, "lift": 1.0, "stun": 0.6, "poise": 35.0, "heavy": true, "unblockable": true},
			"params": {"radius": 5.0, "wave_time": 0.28, "clearance": 1.2, "crater": 1.5, "shards": 9},
			"fx": {"vfx": &"shockwave", "sfx": &"stomp"}, "script_path": DIR + "earth_stomp.gd"}),
		AbilityDef.make({"id": &"earth_wall", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Earth Wall",
			"description": "A 6 x 3 m wall erupts from the ground at the aim point. Blocks projectiles and movement for 12 s; launches whoever stands on it.",
			"icon": "res://assets/ui/ability_wall.svg", "chi_cost": 30.0, "cooldown": 8.0, "clip": &"earth_wall", "clip_speed": 1.15,
			"startup": 0.45, "recovery": 0.3, "starter": true, "unlock": {"level": 1, "tier": 1, "branch": &"guard", "column": 2},
			"params": {"distance": 4.5, "size": Vector3(6.0, 3.0, 1.0), "hp": 180.0, "lifetime": 12.0, "rise_time": 0.3, "lift": 7.5},
			"fx": {"vfx": &"wall", "sfx": &"wall"}, "script_path": DIR + "earth_wall.gd"}),
		# --- tier 2 -------------------------------------------------------------------------------
		AbilityDef.make({"id": &"earth_grab", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Earth Grab",
			"description": "Reach out and clench: a ripple runs under the ground to the target and stone jaws clamp its legs, rooting it for 2.5 s. Only grounded targets are caught; the grab cannot be blocked.",
			"icon": ICONS + "ability_grab.svg", "chi_cost": 22.0, "cooldown": 9.0, "clip": &"earth_grab_clench", "clip_speed": 1.1,
			"startup": 0.27, "active": 0.23, "recovery": 0.3, "poise_armor": 20.0,
			"unlock": {"level": 3, "prerequisite": &"earth_pillar", "practice": 6, "cost": 1, "tier": 2, "branch": &"stone", "column": 0},
			"hit": {"damage": 6.0, "reaction": R.FREEZE, "stun": 2.5, "poise": 30.0, "unblockable": true},
			"params": {"range": 14.0, "distance": 7.0, "radius": 1.25, "hold": 2.5},
			"fx": {"vfx": &"shackle", "sfx": &"wall"}, "script_path": DIR + "earth_grab.gd"}),
		AbilityDef.make({"id": &"earth_spikes", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Earth Spikes",
			"description": "Drive both claws into the ground: a line of stone spikes erupts toward the target, launching everything in its path. It follows the ground and stops at ice, water and walls.",
			"icon": ICONS + "ability_earth_spikes.svg", "chi_cost": 24.0, "cooldown": 7.0, "clip": &"earth_spikes_drive", "clip_speed": 1.1,
			"startup": 0.35, "active": 0.5, "recovery": 0.35, "poise_armor": 25.0,
			"unlock": {"level": 3, "prerequisite": &"earth_stomp", "practice": 6, "cost": 1, "tier": 2, "branch": &"seismic", "column": 1},
			"hit": {"damage": 16.0, "reaction": R.LAUNCH, "lift": 6.5, "force": 3.0, "poise": 40.0, "heavy": true, "unblockable": true},
			"params": {"length": 12.0, "speed": 24.0, "spacing": 0.6, "radius": 0.85, "start": 1.1, "hold": 1.4},
			"fx": {"vfx": &"spikes", "sfx": &"spikes"}, "script_path": DIR + "earth_spikes.gd"}),
		# --- tier 3 -------------------------------------------------------------------------------
		AbilityDef.make({"id": &"earth_armor", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Earth Armor",
			"description": "Toggle: tear stone plates from the ground and lock them onto your body - 40% less damage and hard to stagger, but 22% slower and draining 5 chi per second. Press again to burst out of it, knocking back everyone close.",
			"icon": ICONS + "ability_armor.svg", "chi_cost": 20.0, "cooldown": 4.0, "clip": &"earth_armor_don", "clip_speed": 1.0,
			"startup": 0.76, "active": 0.0, "recovery": 0.3, "poise_armor": 60.0,
			"unlock": {"level": 5, "prerequisite": &"earth_wall", "trainer": &"ek_bao_shan", "cost": 1, "tier": 3, "branch": &"guard", "column": 2},
			"hit": {"damage": 8.0, "reaction": R.KNOCKBACK, "force": 9.0, "lift": 1.5, "poise": 35.0, "heavy": true},
			"params": {"reduction": 0.4, "poise": 40.0, "speed_scale": 0.78, "drain": 5.0, "ai_time": 25.0, "burst_radius": 3.0,
				"shed_clip": &"earth_armor_shed", "shed_speed": 1.1},
			"fx": {"vfx": &"armor", "sfx": &"armor"}, "script_path": DIR + "earth_armor.gd"}),
		# --- tier 4: signature --------------------------------------------------------------------
		AbilityDef.make({"id": &"earthquake", "element": E, "slot": AbilityDef.Slot.SIGNATURE, "display_name": "Earthquake",
			"description": "Feel the stone, rise, and drive a fist into the earth: a fissure shockwave rolls 11 m and knocks down everything on the ground, the hovering boulders fly outward as debris, and the ground stays split and broken.",
			"icon": ICONS + "ability_earthquake.svg", "focus_cost": 100.0, "clip": &"earthquake_slam", "clip_speed": 1.0,
			"startup": 0.95, "active": 0.6, "recovery": 0.55, "poise_armor": 999.0,
			"unlock": {"level": 7, "prerequisite": &"earth_spikes", "trainer": &"ek_bao_shan", "cost": 2, "tier": 4, "branch": &"seismic", "column": 1},
			"hit": {"damage": 34.0, "reaction": R.KNOCKDOWN, "force": 9.0, "lift": 3.5, "stun": 1.2, "poise": 90.0, "heavy": true, "unblockable": true},
			"params": {"radius": 11.0, "wave_time": 0.6, "fissures": 7, "boulders": 6, "debris_speed": 15.0, "damage_reduction": 0.5,
				"debris_hit": {"damage": 10.0, "reaction": R.STAGGER, "force": 5.0, "stun": 0.5, "poise": 25.0, "heavy": false, "projectile": true,
					"deflectable": false, "unblockable": false}},
			"fx": {"vfx": &"earthquake", "sfx": &"special"}, "script_path": DIR + "earthquake.gd"}),
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


## Attack entries enemy earthbenders can add to an archetype's "attacks" list
## (EnemyActions format) to use the Earth techniques through their controller:
## set the matching controller slot to the def (AbilityRegistry.get_def or an
## EnemyAbilities.variant) and append the entry.
static func enemy_attacks() -> Dictionary:
	return {
		&"earth_pillar": {"id": &"earth_pillar", "kind": &"bending", "clip": &"earth_pillar_raise", "windup": 0.14, "approach": 0.12, "telegraph": 0.35,
			"range": Vector2(3.0, 14.0), "cooldown": 7.0, "weight": 0.8, "glint": &"hands", "needs_los": true, "bending": {"slot": &"technique_2"},
			"recover": 0.6, "armor": 30.0},
		&"earth_stomp": {"id": &"earth_stomp", "kind": &"bending", "clip": &"earth_stomp_quake", "windup": 0.17, "approach": 0.15, "telegraph": 0.45,
			"range": Vector2(0.0, 4.5), "cooldown": 7.0, "weight": 1.0, "glint": &"foot_r", "ring": 5.0, "bending": {"slot": &"technique_3"},
			"recover": 0.7, "armor": 40.0},
		&"earth_spikes": {"id": &"earth_spikes", "kind": &"bending", "clip": &"earth_spikes_drive", "windup": 0.18, "approach": 0.12, "telegraph": 0.4,
			"range": Vector2(3.0, 11.0), "cooldown": 8.0, "weight": 0.9, "glint": &"hands", "needs_los": true, "bending": {"slot": &"technique_4"},
			"recover": 0.6, "armor": 30.0},
	}
