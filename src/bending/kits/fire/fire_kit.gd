extends RefCounted
## Fire Nation core kit (docs/GAME_DESIGN.md §4 Fire): aggressive, precise,
## explosive. Fists ignite on every strike; kicks leave arcs of flame.

const E := ElementDefs.Element.FIRE
const R := HitInfo.Reaction
const DIR := "res://src/bending/kits/fire/"


static func defs() -> Array[AbilityDef]:
	var out: Array[AbilityDef] = [
		AbilityDef.make({"id": &"fire_combo", "element": E, "slot": AbilityDef.Slot.LIGHT, "display_name": "Fire Fist / Fire Kick",
			"description": "Jab, jab, kick, roundhouse: fire bolts leave the fists, the kicks sweep arcs of flame.",
			"icon": "res://assets/ui/ability_flame.svg", "startup": 0.07, "active": 0.1, "recovery": 0.2,
			"hit": {"damage": 6.0, "reaction": R.FLINCH, "force": 2.0, "poise": 7.0, "status": {"burn": 1.5}},
			"params": {"steps": [
				{"clip": &"combo_fire_1", "start": 0.18, "speed": 1.0, "event": &"release", "chain_at": 0.62, "kind": "bolt", "hand": &"hand_r"},
				{"clip": &"combo_fire_2", "start": 0.18, "speed": 1.0, "event": &"release", "chain_at": 0.62, "kind": "bolt", "hand": &"hand_l"},
				{"clip": &"combo_fire_3", "start": 0.25, "speed": 1.2, "event": &"impact", "chain_at": 0.7, "kind": "kick", "hand": &"foot_r", "move": "lunge", "lunge": 2.2,
					"hit": {"damage": 9.0, "force": 4.0, "poise": 12.0}},
				{"clip": &"fire_spin_kick_r", "start": 0.32, "speed": 1.15, "event": &"release", "kind": "wave", "hand": &"foot_r",
					"hit": {"damage": 13.0, "reaction": R.KNOCKBACK, "force": 9.0, "poise": 26.0, "heavy": true, "status": {"burn": 3.0}}},
			], "bolt_speed": 34.0, "bolt_range": 15.0},
			"fx": {"vfx": &"fire_bolt", "sfx": &"cast_light"}, "script_path": DIR + "fire_combo.gd"}),
		AbilityDef.make({"id": &"fire_blast", "element": E, "slot": AbilityDef.Slot.HEAVY, "display_name": "Fire Blast / Blaze Charge",
			"description": "Tap: a fast long-range fireball. Hold: flame gathers between the fists and explodes on impact.",
			"icon": "res://assets/ui/ability_flame.svg", "chi_cost": 10.0, "charge_time": 1.1, "max_hold": 3.0,
			"hit": {"damage": 15.0, "reaction": R.STAGGER, "force": 5.0, "stun": 0.45, "poise": 24.0, "heavy": true, "status": {"burn": 2.5}},
			"params": {"hold_clip": &"fire_charge_hold", "release_clip": &"fire_charge_release", "release_start": 0.1, "tap_start": 0.16,
				"tap_time": 0.2, "min_windup": 0.08, "charge_chi": 16.0, "walk_scale": 0.3, "speed": 36.0, "range": 32.0},
			"fx": {"vfx": &"fireball", "sfx": &"cast_heavy", "charge": &"charge_loop"}, "script_path": DIR + "fire_blast.gd"}),
		AbilityDef.make({"id": &"flame_guard", "element": E, "slot": AbilityDef.Slot.DEFENSE, "display_name": "Flame Guard",
			"description": "A flare of fire that burns incoming projectiles away and blocks 75%. Perfect timing: Fire Burst counter.",
			"icon": "res://assets/ui/ability_shield.svg", "clip": &"fire_guard_hold",
			"params": {"reduction": 0.75, "arc": 85.0, "upkeep": 5.0, "burn_projectiles": true, "walk_scale": 0.45, "counter_damage": 4.0},
			"fx": {"vfx": &"flame_flare", "sfx": &"shield_up"}, "script_path": DIR + "flame_guard.gd"}),
		AbilityDef.make({"id": &"fire_step", "element": E, "slot": AbilityDef.Slot.DODGE, "display_name": "Fire Step",
			"description": "An explosive burst step (4.5 m, 0.2 s i-frames) leaving a short flame trail. Cancels into strikes.",
			"icon": "res://assets/ui/ability_flame.svg",
			"params": {"clips": {"fwd": &"dodge_fire_burst", "back": &"dodge_back", "left": &"dodge_side_l", "right": &"dodge_side_r"},
				"recovery": 0.1, "cancel_strikes": 0.14},
			"fx": {"vfx": &"flame_trail", "sfx": &"dash"}, "script_path": DIR + "fire_step.gd"}),
		AbilityDef.make({"id": &"flame_sweep", "element": E, "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Flame Sweep",
			"description": "A low sweeping kick that sends a wide wave of fire rolling outward along the ground.",
			"icon": "res://assets/ui/ability_sweep.svg", "chi_cost": 22.0, "cooldown": 6.0, "clip": &"flame_sweep_kick", "clip_speed": 1.05,
			"startup": 0.35, "recovery": 0.3, "starter": true, "unlock": {"level": 1},
			"hit": {"damage": 18.0, "reaction": R.KNOCKBACK, "force": 7.0, "lift": 1.5, "poise": 30.0, "heavy": true, "status": {"burn": 4.0}},
			"params": {"range": 7.5, "half_angle": 62.0, "wave_time": 0.42},
			"fx": {"vfx": &"flame_wave", "sfx": &"cast_heavy"}, "script_path": DIR + "flame_sweep.gd"}),
	]
	return out
