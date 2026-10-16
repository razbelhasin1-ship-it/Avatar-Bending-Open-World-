extends RefCounted
## Earth Kingdom core kit (docs/GAME_DESIGN.md §4 Earth): grounded,
## deliberate, forceful. Rock is always torn out of the ground first.

const E := ElementDefs.Element.EARTH
const R := HitInfo.Reaction
const DIR := "res://src/bending/kits/earth/"


static func defs() -> Array[AbilityDef]:
	var out: Array[AbilityDef] = [
		AbilityDef.make({"id": &"earth_punch", "element": E, "slot": AbilityDef.Slot.LIGHT, "display_name": "Earth Punch",
			"description": "Rock chunks ripped from the ground and punched as projectiles. Three hits; the last is bigger.",
			"icon": "res://assets/ui/ability_spikes.svg", "startup": 0.08, "active": 0.1, "recovery": 0.35, "poise_armor": 12.0,
			"hit": {"damage": 9.0, "reaction": R.FLINCH, "force": 3.0, "poise": 12.0},
			"params": {"steps": [
				{"clip": &"combo_earth_1", "start": 0.32, "speed": 1.15, "event": &"release", "chain_at": 0.8, "hand": &"hand_r", "rock": 0.2, "move": "brake"},
				{"clip": &"combo_earth_2", "start": 0.32, "speed": 1.15, "event": &"release", "chain_at": 0.8, "hand": &"hand_l", "rock": 0.2, "move": "brake"},
				{"clip": &"combo_earth_3", "start": 0.5, "speed": 1.1, "event": &"release", "hand": &"hands", "rock": 0.36, "move": "brake",
					"hit": {"damage": 16.0, "reaction": R.KNOCKBACK, "force": 8.0, "poise": 30.0, "heavy": true}},
			], "speed": 30.0, "range": 28.0},
			"fx": {"vfx": &"rock", "sfx": &"cast_light"}, "script_path": DIR + "earth_punch.gd"}),
		AbilityDef.make({"id": &"earth_boulder", "element": E, "slot": AbilityDef.Slot.HEAVY, "display_name": "Earth Boulder",
			"description": "Stomp a boulder out of the ground, hold to aim, release to hurl it: heavy impact, knockdown.",
			"icon": "res://assets/ui/ability_wall.svg", "chi_cost": 14.0, "charge_time": 1.2, "max_hold": 4.0, "poise_armor": 45.0,
			"hit": {"damage": 26.0, "reaction": R.KNOCKDOWN, "force": 9.0, "lift": 3.0, "poise": 60.0, "heavy": true, "stun": 1.0},
			"params": {"lift_clip": &"earth_raise", "lift_speed": 1.3, "hold_clip": &"earth_hold", "throw_clip": &"earth_throw", "throw_start": 0.55,
				"throw_speed": 1.2, "charge_chi": 10.0, "speed": 24.0, "radius": 0.55, "splash": 2.2},
			"fx": {"vfx": &"boulder", "sfx": &"cast_heavy"}, "script_path": DIR + "earth_boulder.gd"}),
		AbilityDef.make({"id": &"earth_shield", "element": E, "slot": AbilityDef.Slot.DEFENSE, "display_name": "Earth Shield",
			"description": "A stone slab rises in front while held: blocks 90% from the front, breaks under sustained damage.",
			"icon": "res://assets/ui/ability_shield.svg", "clip": &"earth_shield",
			"params": {"reduction": 0.9, "arc": 70.0, "upkeep": 3.0, "guard_hp": 80.0, "chi_per_block": 4.0, "walk_scale": 0.3, "counter_damage": 8.0},
			"fx": {"vfx": &"slab", "sfx": &"shield_up"}, "script_path": DIR + "earth_shield.gd"}),
		AbilityDef.make({"id": &"earth_slide", "element": E, "slot": AbilityDef.Slot.DODGE, "display_name": "Earth Slide",
			"description": "A short slide riding the ground with full poise armor; ends in a small shockwave.",
			"icon": "res://assets/ui/ability_wall.svg",
			"params": {"clips": {"fwd": &"earth_slide_fwd", "back": &"dodge_back", "left": &"dodge_earth_slide_l", "right": &"dodge_earth_slide_r"},
				"recovery": 0.14, "shock_radius": 2.4},
			"hit": {"damage": 4.0, "reaction": R.STAGGER, "force": 4.0, "stun": 0.4, "poise": 20.0},
			"fx": {"vfx": &"dust", "sfx": &"dash"}, "script_path": DIR + "earth_slide.gd"}),
		AbilityDef.make({"id": &"earth_wall", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Earth Wall",
			"description": "A 6 x 3 m wall erupts from the ground at the aim point. Blocks projectiles and movement for 12 s; launches whoever stands on it.",
			"icon": "res://assets/ui/ability_wall.svg", "chi_cost": 30.0, "cooldown": 8.0, "clip": &"earth_wall", "clip_speed": 1.15,
			"startup": 0.45, "recovery": 0.3, "starter": true, "unlock": {"level": 1},
			"params": {"distance": 4.5, "size": Vector3(6.0, 3.0, 1.0), "hp": 180.0, "lifetime": 12.0, "rise_time": 0.3, "lift": 7.5},
			"fx": {"vfx": &"wall", "sfx": &"wall"}, "script_path": DIR + "earth_wall.gd"}),
	]
	return out
