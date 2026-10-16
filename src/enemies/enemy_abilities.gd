class_name EnemyAbilities
extends RefCounted
## Enemy loadouts for elemental benders. Enemies cast the SAME bending abilities as
## the player (same BendingAbility scripts, projectiles, hits, VFX and sounds, through
## a non-player BendingContext with team ENEMY), tuned for fairness: slower
## projectiles, shorter chains, no redirecting parries. The tuned defs are copies of
## the kit defs with an "enemy_" id; they are NOT registered in AbilityRegistry, so
## the player's kits, skill tree and tutorial checks never see them.
##
##   EnemyAbilities.setup_controller(bc, ElementDefs.Element.FIRE, archetype)

## Enemy variants: kit id -> {"id": enemy id, "params": overrides, "hit": overrides, "steps": n}.
const VARIANTS := {
	&"fire_combo": {"params": {"bolt_speed": 20.0, "bolt_range": 18.0}},
	&"fire_blast": {"params": {"speed": 22.0, "range": 28.0}},
	&"flame_guard": {},
	&"fire_step": {},
	&"flame_sweep": {"cooldown": 7.0},
	&"earth_punch": {"params": {"speed": 19.0, "range": 22.0}, "hit": {"damage": 8.0}},
	&"earth_boulder": {"params": {"speed": 17.0}},
	&"earth_shield": {},
	&"earth_slide": {},
	&"earth_wall": {"cooldown": 14.0, "params": {"distance": 3.2, "hp": 110.0, "lifetime": 7.0, "lift": 5.0}},
	&"water_whip": {"hit": {"damage": 7.0}},
	&"water_blast": {"params": {"speed": 21.0}},
	&"water_shield": {"params": {"redirect": false}},
	&"flow_slide": {},
	&"ice_shards": {"cooldown": 7.0, "params": {"speed": 21.0}, "hit": {"damage": 5.0}},
}

## Element slot loadouts (light, heavy, defense, dodge + technique_1).
const LOADOUTS := {
	ElementDefs.Element.FIRE: {&"light": &"fire_combo", &"heavy": &"fire_blast", &"defense": &"flame_guard", &"dodge": &"fire_step",
		&"technique_1": &"flame_sweep"},
	ElementDefs.Element.EARTH: {&"light": &"earth_punch", &"heavy": &"earth_boulder", &"defense": &"earth_shield", &"dodge": &"earth_slide",
		&"technique_1": &"earth_wall"},
	ElementDefs.Element.WATER: {&"light": &"water_whip", &"heavy": &"water_blast", &"defense": &"water_shield", &"dodge": &"flow_slide",
		&"technique_1": &"ice_shards"},
}

static var _cache: Dictionary = {}


## The enemy-tuned copy of a kit ability (`steps` > 0 keeps only that many chain steps).
static func variant(kit_id: StringName, steps: int = 0) -> AbilityDef:
	var key := "%s#%d" % [kit_id, steps]
	if _cache.has(key):
		return _cache[key]
	var base := AbilityRegistry.get_def(kit_id)
	if base == null:
		return null
	var d := base.duplicate(false) as AbilityDef
	# Never share (and mutate) the kit's dictionaries.
	d.params = base.params.duplicate(true)
	d.hit = base.hit.duplicate(true)
	d.fx = base.fx.duplicate(true)
	d.id = StringName("enemy_%s" % kit_id)
	var v: Dictionary = VARIANTS.get(kit_id, {})
	for k: String in (v.get("params", {}) as Dictionary):
		d.params[k] = v["params"][k]
	for k: String in (v.get("hit", {}) as Dictionary):
		d.hit[k] = v["hit"][k]
	if v.has("cooldown"):
		d.cooldown = float(v["cooldown"])
	d.starter = false
	d.unlock = {}
	if steps > 0 and d.params.has("steps"):
		var all: Array = d.params["steps"]
		d.params["steps"] = all.slice(0, clampi(steps, 1, all.size()))
	_cache[key] = d
	return d


## Custom enemy-only abilities (also unregistered).
static func custom(id: StringName) -> AbilityDef:
	var key := "custom#%s" % id
	if _cache.has(key):
		return _cache[key]
	var d: AbilityDef = null
	match id:
		&"rock_glove":
			d = AbilityDef.make({"id": &"enemy_rock_glove", "element": ElementDefs.Element.EARTH, "slot": AbilityDef.Slot.TECHNIQUE,
				"display_name": "Rock Glove", "description": "A stone glove shot on a chain: roots the target in place.",
				"cooldown": 3.5, "clip": &"jab_r", "clip_start": 0.22, "clip_speed": 0.9, "startup": 0.1, "recovery": 0.5,
				"hit": {"damage": 8.0, "reaction": HitInfo.Reaction.FREEZE, "stun": 1.1, "poise": 18.0, "projectile": true, "deflectable": true},
				"params": {"speed": 20.0, "range": 16.0, "radius": 0.2},
				"script_path": "res://src/enemies/abilities/rock_glove.gd"})
	if d != null:
		_cache[key] = d
	return d


## Loads the element loadout into a controller and applies the archetype's chain
## lengths / special techniques (attacks with bending.slot + bending.steps / ability).
static func setup_controller(bc: BendingController, element: int, archetype: Dictionary) -> void:
	var lo: Dictionary = LOADOUTS.get(element, {})
	var steps := 0
	var technique: StringName = lo.get(&"technique_1", &"")
	for a: Dictionary in _all_attacks(archetype):
		var b: Dictionary = a.get("bending", {})
		if b.get("slot", &"") == &"light":
			steps = maxi(steps, int(b.get("steps", 0)))
		if b.get("slot", &"") == &"technique_1" and a.get("id", &"") == &"rock_glove":
			technique = &"rock_glove"
	for slot: StringName in lo:
		var kit_id: StringName = lo[slot]
		if slot == &"technique_1":
			kit_id = technique
		var d: AbilityDef = custom(kit_id) if kit_id == &"rock_glove" else variant(kit_id, steps if slot == &"light" else 0)
		bc.set_slot(slot, d)
	bc.reset_cooldowns()


static func _all_attacks(archetype: Dictionary) -> Array:
	var out: Array = (archetype.get("attacks", []) as Array).duplicate()
	for ph: Dictionary in archetype.get("phases", []):
		out.append_array(ph.get("attacks", []))
	return out


static func clear_cache() -> void:
	_cache.clear()
