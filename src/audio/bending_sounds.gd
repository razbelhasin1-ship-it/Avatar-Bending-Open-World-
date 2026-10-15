class_name BendingSounds
extends RefCounted
## Maps (element, bending event) to sound names so abilities never hard-code
## file names. Used by Audio.play_bending() / Audio.start_bending_loop().
##
## Events (StringName):
##   &"cast_light"  light attack leaves the hands      &"cast_heavy"   heavy attack release
##   &"impact"      attack hits world/target           &"charge_loop"  holding a charge (loop)
##   &"shield_up"   defense starts (one-shot)          &"shield_loop"  defense held (loop)
##   &"dash"        element dodge / dash               &"jump"         element-assisted jump
##   &"wall"        construct raised                   &"wall_break"   construct destroyed
##   &"stomp"       ground slam                        &"special"      signature technique
##   &"special_loop" sustained signature (tornado...)  &"draw"         pull element from a source
##   &"freeze"      ice forms                          &"heal_loop"    healing (water)
##   &"ignite"      flame ignites                      &"extinguish"   flame doused
##   &"debris"      rock/shard rain                    &"armor"        earth armour forms
##   &"block"       blocked hit                        &"parry"        perfect defense
## Unknown events fall back to the element-less (martial arts) table.

const NONE := -1

const TABLE := {
	ElementDefs.Element.AIR: {
		&"cast_light": &"air_blast", &"cast_heavy": &"air_sweep", &"impact": &"air_impact",
		&"charge_loop": &"air_shield_loop", &"shield_up": &"air_push", &"shield_loop": &"air_shield_loop",
		&"dash": &"air_dash", &"jump": &"air_jump", &"wall": &"air_push", &"wall_break": &"air_impact",
		&"stomp": &"air_push", &"special": &"air_sweep", &"special_loop": &"air_tornado_loop", &"push": &"air_push",
	},
	ElementDefs.Element.EARTH: {
		&"cast_light": &"earth_launch", &"cast_heavy": &"earth_raise", &"impact": &"earth_impact",
		&"charge_loop": &"", &"shield_up": &"earth_wall_rise", &"shield_loop": &"",
		&"dash": &"rock_debris", &"jump": &"earth_raise", &"wall": &"earth_wall_rise", &"wall_break": &"earth_crumble",
		&"stomp": &"earth_stomp", &"special": &"earth_quake", &"special_loop": &"", &"spikes": &"earth_spikes",
		&"armor": &"earth_armor", &"debris": &"rock_debris", &"launch": &"earth_launch",
	},
	ElementDefs.Element.FIRE: {
		&"cast_light": &"fire_whoosh", &"cast_heavy": &"fire_blast", &"impact": &"fire_impact",
		&"charge_loop": &"fire_charge_loop", &"shield_up": &"fire_ignite", &"shield_loop": &"fire_loop",
		&"dash": &"fire_ignite", &"jump": &"fire_ignite", &"wall": &"fire_ring", &"wall_break": &"fire_extinguish",
		&"stomp": &"fire_explosion", &"special": &"fire_ring", &"special_loop": &"fire_loop",
		&"ignite": &"fire_ignite", &"extinguish": &"fire_extinguish", &"explosion": &"fire_explosion",
	},
	ElementDefs.Element.WATER: {
		&"cast_light": &"water_whip", &"cast_heavy": &"water_blast", &"impact": &"water_splash",
		&"charge_loop": &"water_shield_loop", &"shield_up": &"water_draw", &"shield_loop": &"water_shield_loop",
		&"dash": &"water_splash", &"jump": &"water_surge", &"wall": &"ice_form", &"wall_break": &"ice_shatter",
		&"stomp": &"water_wave", &"special": &"water_wave", &"special_loop": &"water_shield_loop",
		&"draw": &"water_draw", &"freeze": &"ice_form", &"ice_impact": &"ice_impact", &"shatter": &"ice_shatter",
		&"surge": &"water_surge", &"heal_loop": &"water_heal_loop", &"splash": &"water_splash",
	},
	NONE: {
		&"cast_light": &"whoosh_light", &"cast_heavy": &"whoosh_heavy", &"impact": &"punch_impact",
		&"impact_heavy": &"kick_impact", &"dash": &"dodge_whoosh", &"jump": &"jump", &"block": &"block_impact",
		&"parry": &"parry", &"hit": &"hit_flesh", &"fall": &"body_fall",
	},
}


## Sound for an element event, or &"" when the element has no sound for it.
static func sound_for(element: int, event: StringName) -> StringName:
	var t: Dictionary = TABLE.get(element, TABLE[NONE])
	if t.has(event):
		return t[event]
	var common: Dictionary = TABLE[NONE]
	return common.get(event, &"")


## Layers (sound names) that sell a landed hit, by Combat.Result. The first entry
## is the main layer; the rest are quieter sweeteners. `icy` marks ice attacks
## (freeze reactions, chill status, ice abilities) so water hits crack like ice.
static func hit_layers(element: int, is_heavy: bool, result: int, icy: bool = false) -> Array[StringName]:
	var out: Array[StringName] = []
	match result:
		Combat.Result.BLOCKED:
			out.append(&"block_impact")
		Combat.Result.DEFLECTED:
			out.append(&"parry")
		Combat.Result.HIT, Combat.Result.KILLED:
			if element == NONE:
				out.append(&"kick_impact" if is_heavy else &"punch_impact")
				out.append(&"hit_flesh")
			else:
				var imp := sound_for(element, &"impact")
				if icy:
					imp = &"ice_impact"
				out.append(imp)
				out.append(&"hit_flesh")
	return out
