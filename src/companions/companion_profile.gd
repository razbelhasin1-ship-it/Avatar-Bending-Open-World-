class_name CompanionProfile
extends RefCounted
## Per-species tuning of an element companion (docs/modules/companions.md). Numbers are
## gameplay values at creature scale 1; speeds in m/s, angles in degrees unless noted.
##
##   var prof := CompanionProfile.for_species(&"sky_bison")
##   prof.flight["cruise"]   # 18.0
##
## Groups:
##   follow  formation slot (side / back offset from the player), personal space, speeds
##           of the gait engine (walk / run / sprint) and the catch-up limit
##   ride    mounted ground riding (walk / run / sprint, accel, turn rate, max slope, snow,
##           jump), camera params for PlayerCamera.set_mode
##   flight  flyers: escort height, cruise / glide / boost / min speed, accel, turn rates,
##           max bank (rad), climb / descend rates, terrain clearance, camera params
##   assist  combat assist move: kind, range, cooldown, hit data

const SPECIES: Array[StringName] = [&"sky_bison", &"dragon", &"polar_bear_dog", &"badgermole"]

var species: StringName = &""
var display_name := "Companion"
var element: int = ElementDefs.Element.NONE
var max_health := 300.0
## Fraction of incoming damage ignored (thick fur / hide / scales).
var armor := 0.3
var can_fly := false
## Flyers that prefer to escort from the air instead of walking beside the player.
var prefers_air := false
var can_burrow := false
var can_swim := true
var follow: Dictionary = {}
var ride: Dictionary = {}
var flight: Dictionary = {}
var assist: Dictionary = {}
## Vocal actions: greet (call / bark), angry (growl / roar), hurt.
var vocals: Dictionary = {}
## Contextual idle actions the brain may play (besides the rig's own random idles).
var play_actions: Array[StringName] = []


static func for_species(id: StringName) -> CompanionProfile:
	var p := CompanionProfile.new()
	p.species = id
	match id:
		&"sky_bison":
			p.display_name = "Sky Bison"
			p.element = ElementDefs.Element.AIR
			p.max_health = 420.0
			p.armor = 0.35
			p.can_fly = true
			p.follow = {"side": 7.5, "back": 3.5, "space": 4.6, "walk": 1.6, "run": 4.8, "sprint": 6.8,
					"max": 7.6, "turn": 110.0, "max_slope": 36.0, "radius": 1.8, "height": 3.6}
			p.ride = {"walk": 2.4, "run": 5.6, "sprint": 7.6, "accel": 4.5, "decel": 6.0, "turn": 80.0, "max_slope": 36.0,
					"snow": 0.15, "jump": 0.0,
					"camera": {"height": 5.4, "distance": 13.0, "fov": 4.0, "auto_align": true}}
			p.flight = {"escort_height": 16.0, "cruise": 18.0, "glide": 11.0, "boost": 30.0, "min": 0.0, "hover": 0.0,
					"accel": 5.5, "decel": 4.5, "boost_accel": 8.0, "turn_slow": 80.0, "turn_fast": 46.0, "max_bank": 0.5,
					"climb": 8.0, "descend": 11.0, "clearance": 10.0, "land_clearance": 1.2, "glide_sink": 1.1,
					"camera": {"height": 5.2, "distance": 15.5, "fov": 10.0, "auto_align": true}}
			p.assist = {"kind": &"tail_gust", "range": 10.0, "min_range": 2.5, "cooldown": 10.0,
					"hit": {"damage": 10.0, "reaction": HitInfo.Reaction.KNOCKBACK, "force": 15.0, "lift": 3.0, "stun": 0.6, "poise": 40.0, "heavy": true}}
			p.vocals = {"greet": &"call", "angry": &"groan", "hurt": &"groan"}
			p.play_actions = [&"lie_down", &"shake", &"sniff", &"groan"]
		&"dragon":
			p.display_name = "Dragon"
			p.element = ElementDefs.Element.FIRE
			p.max_health = 460.0
			p.armor = 0.4
			p.can_fly = true
			p.prefers_air = true
			p.can_swim = false
			p.follow = {"side": 10.0, "back": 5.0, "space": 6.0, "walk": 2.2, "run": 7.5, "sprint": 10.0,
					"max": 11.0, "turn": 120.0, "max_slope": 34.0, "radius": 1.3, "height": 3.0}
			p.ride = {"walk": 2.6, "run": 7.5, "sprint": 10.5, "accel": 6.0, "decel": 7.0, "turn": 75.0, "max_slope": 36.0,
					"snow": 0.2, "jump": 0.0,
					"camera": {"height": 6.2, "distance": 15.0, "fov": 6.0, "auto_align": true}}
			p.flight = {"escort_height": 26.0, "cruise": 24.0, "glide": 16.0, "boost": 40.0, "min": 9.0, "hover": 9.0,
					"accel": 7.0, "decel": 5.0, "boost_accel": 11.0, "turn_slow": 100.0, "turn_fast": 62.0, "max_bank": 0.75,
					"climb": 10.0, "descend": 14.0, "clearance": 12.0, "land_clearance": 1.5, "glide_sink": 1.4,
					"camera": {"height": 6.5, "distance": 17.5, "fov": 12.0, "auto_align": true}}
			p.assist = {"kind": &"fire_breath", "range": 13.0, "min_range": 3.0, "cooldown": 11.0, "cone": 24.0, "ticks": 7, "tick_time": 0.22,
					"hit": {"damage": 5.0, "reaction": HitInfo.Reaction.FLINCH, "force": 2.0, "stun": 0.2, "poise": 8.0, "status": {"burn": 3.0}}}
			p.vocals = {"greet": &"roar", "angry": &"snort", "hurt": &"roar"}
			p.play_actions = [&"stretch_wings", &"snort", &"sniff"]
		&"polar_bear_dog":
			p.display_name = "Polar Bear Dog"
			p.element = ElementDefs.Element.WATER
			p.max_health = 260.0
			p.armor = 0.2
			p.follow = {"side": 3.4, "back": 2.2, "space": 1.9, "walk": 1.6, "run": 4.5, "sprint": 11.0,
					"max": 13.0, "turn": 320.0, "max_slope": 42.0, "radius": 0.75, "height": 2.0}
			p.ride = {"walk": 2.6, "run": 8.0, "sprint": 15.0, "accel": 11.0, "decel": 12.0, "turn": 220.0, "max_slope": 42.0,
					"snow": 0.0, "jump": 7.5,
					"camera": {"height": 2.9, "distance": 7.4, "fov": 6.0, "auto_align": true}}
			p.assist = {"kind": &"pounce", "range": 9.0, "min_range": 2.5, "cooldown": 7.0,
					"hit": {"damage": 16.0, "reaction": HitInfo.Reaction.KNOCKDOWN, "force": 7.0, "stun": 1.0, "poise": 45.0, "heavy": true}}
			p.vocals = {"greet": &"bark", "angry": &"growl", "hurt": &"growl"}
			p.play_actions = [&"rear_up", &"shake", &"sit", &"scratch", &"howl"]
		&"badgermole":
			p.display_name = "Badgermole"
			p.element = ElementDefs.Element.EARTH
			p.max_health = 340.0
			p.armor = 0.45
			p.can_burrow = true
			p.follow = {"side": 5.0, "back": 3.0, "space": 2.8, "walk": 1.4, "run": 6.5, "sprint": 8.5,
					"max": 9.5, "turn": 160.0, "max_slope": 52.0, "radius": 1.1, "height": 1.8}
			p.ride = {"walk": 2.2, "run": 6.5, "sprint": 9.0, "accel": 6.5, "decel": 9.0, "turn": 130.0, "max_slope": 55.0,
					"snow": 0.25, "jump": 0.0, "rugged": true,
					"camera": {"height": 3.0, "distance": 8.2, "fov": 4.0, "auto_align": true}}
			p.flight = {}
			p.assist = {"kind": &"tremor", "range": 6.5, "min_range": 0.0, "cooldown": 9.0,
					"hit": {"damage": 12.0, "reaction": HitInfo.Reaction.STAGGER, "force": 5.0, "lift": 2.0, "stun": 0.8, "poise": 50.0, "heavy": true}}
			p.vocals = {"greet": &"call", "angry": &"growl", "hurt": &"growl"}
			p.play_actions = [&"dig", &"sniff", &"shake", &"rear_up"]
		_:
			push_warning("CompanionProfile: unknown species %s" % id)
			p.follow = {"side": 3.0, "back": 2.0, "space": 2.0, "walk": 1.5, "run": 4.5, "sprint": 7.0, "max": 8.0,
					"turn": 200.0, "max_slope": 40.0, "radius": 0.8, "height": 1.8}
			p.ride = {"walk": 2.0, "run": 6.0, "sprint": 8.0, "accel": 6.0, "decel": 8.0, "turn": 120.0, "max_slope": 40.0,
					"snow": 0.2, "jump": 0.0, "camera": {"height": 3.0, "distance": 8.0, "fov": 4.0, "auto_align": true}}
			p.vocals = {"greet": &"call", "angry": &"growl", "hurt": &"growl"}
	return p


## Species of an element's companion (ElementDefs), or &"" if none.
static func species_for_element(e: int) -> StringName:
	return StringName(ElementDefs.get_data(e).get("companion", &"")) if ElementDefs.is_valid(e) else &""


func f(group: Dictionary, key: String, fallback: float = 0.0) -> float:
	return float(group.get(key, fallback))


## Ground speed of the follow gait for `kind` (&"walk", &"run", &"sprint", &"max").
func follow_speed(kind: String) -> float:
	return f(follow, kind, 4.0)


func radius() -> float:
	return f(follow, "radius", 1.0)


func body_height() -> float:
	return f(follow, "height", 2.0)
