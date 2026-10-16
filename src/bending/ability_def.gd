class_name AbilityDef
extends Resource
## Data of one bending ability (docs/GAME_DESIGN.md §4, docs/modules/bending.md).
## Pure data: behaviour lives in a BendingAbility subclass (`script_path`).
##
## Times are seconds at clip speed. Hit data is a Dictionary understood by
## BendingContext.make_hit():
##   {"damage": 10, "reaction": HitInfo.Reaction.STAGGER, "force": 6.0, "lift": 0.0,
##    "stun": 0.4, "poise": 12, "heavy": false, "status": {"burn": 2.0}}

enum Slot { LIGHT, HEAVY, DEFENSE, DODGE, TECHNIQUE, SIGNATURE, PASSIVE, INNATE }

const SLOT_NAMES := {
	Slot.LIGHT: &"light", Slot.HEAVY: &"heavy", Slot.DEFENSE: &"defense", Slot.DODGE: &"dodge",
	Slot.TECHNIQUE: &"technique", Slot.SIGNATURE: &"signature", Slot.PASSIVE: &"passive", Slot.INNATE: &"innate",
}

@export var id: StringName = &""
@export var element: int = ElementDefs.Element.NONE
@export var display_name := ""
@export_multiline var description := ""
## res:// path of an SVG/PNG icon (HUD slots, skill tree).
@export var icon := ""
@export var slot: Slot = Slot.TECHNIQUE
@export var chi_cost := 0.0
## Focus spent (signatures: 100).
@export var focus_cost := 0.0
@export var cooldown := 0.0
## Design timing (documentation + virtual timeline for rig-less casters).
@export var startup := 0.1
@export var active := 0.1
@export var recovery := 0.3
## Normalized clip time after which dodge/defend may cancel the recovery
## (-1 = use the clip's &"recover" event, or 0.8).
@export var cancel_window := -1.0
## Main animation clip (AnimLibrary) and how to play it.
@export var clip: StringName = &""
@export var clip_speed := 1.0
@export var clip_start := 0.0
## Charge behaviour (heavy hold): seconds to full charge, max hold before auto release.
@export var charge_time := 0.0
@export var max_hold := 0.0
## Default hit data (see class doc).
@export var hit: Dictionary = {}
## Ability-specific tuning (radius, speed, count, combo steps ...).
@export var params: Dictionary = {}
## Effects / sounds (documentation and lookups): {"vfx": &"air_gust", "sfx": &"cast_heavy"}.
@export var fx: Dictionary = {}
## Unlock requirements for the skill tree:
## {"level": 1, "prerequisite": &"", "trainer": &"", "quest": &"", "practice": 0}.
@export var unlock: Dictionary = {}
## Granted on a new game (starter set).
@export var starter := false
## Poise armor while executing (Earth heavies): hits below this poise damage do not interrupt.
@export var poise_armor := 0.0
## BendingAbility subclass implementing it.
@export var script_path := ""


static func make(d: Dictionary) -> AbilityDef:
	var a := AbilityDef.new()
	for k: String in d:
		if k in a:
			a.set(k, d[k])
		else:
			push_warning("AbilityDef %s: unknown field '%s'" % [d.get("id", "?"), k])
	return a


func slot_name() -> StringName:
	return SLOT_NAMES.get(slot, &"technique")


func is_technique() -> bool:
	return slot == Slot.TECHNIQUE


func hit_value(key: String, fallback: Variant = null) -> Variant:
	return hit.get(key, fallback)


func param(key: String, fallback: Variant = null) -> Variant:
	return params.get(key, fallback)


func instantiate() -> BendingAbility:
	if script_path.is_empty():
		return null
	var s := load(script_path) as GDScript
	if s == null:
		push_error("AbilityDef %s: cannot load %s" % [id, script_path])
		return null
	var a: BendingAbility = s.new()
	a.def = self
	return a


## Summary for HUD / skill tree tooltips.
func to_info() -> Dictionary:
	return {"id": id, "name": display_name, "description": description, "icon": icon, "element": element,
			"slot": slot_name(), "cost": chi_cost, "cooldown": cooldown, "unlock": unlock.duplicate()}
