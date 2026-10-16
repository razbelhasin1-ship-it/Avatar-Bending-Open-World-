class_name NpcRoutines
extends RefCounted
## Daily schedules by role: what an NPC does at a given hour (GameState.time_of_day). Activity
## &"home" means indoors (asleep at night): the NPC walks to its door and is not spawned.
## Every record gets a personal offset (up to ~50 min) so a street empties gradually at dusk.
##
## Activities (NpcCharacter): stand, guard, patrol, work, wander, stroll, sit, talk, play,
## meditate, fish, train, home.

const SCHEDULES := {
	&"merchant": [[0.0, &"home"], [6.8, &"work"], [19.6, &"home"]],
	&"guard": [[0.0, &"guard"]],
	&"patrol": [[0.0, &"patrol"]],
	&"worker": [[0.0, &"home"], [6.2, &"work"], [12.0, &"wander"], [13.0, &"work"], [18.2, &"wander"], [20.2, &"home"]],
	&"fisher": [[0.0, &"home"], [5.2, &"fish"], [15.5, &"wander"], [19.2, &"home"]],
	&"child": [[0.0, &"home"], [8.0, &"play"], [12.3, &"wander"], [13.2, &"play"], [18.4, &"home"]],
	&"idler": [[0.0, &"home"], [7.0, &"talk"], [11.5, &"sit"], [14.0, &"talk"], [21.4, &"home"]],
	&"sitter": [[0.0, &"home"], [7.5, &"sit"], [21.0, &"home"]],
	&"resident": [[0.0, &"home"], [6.0, &"wander"], [9.0, &"stroll"], [12.0, &"wander"], [14.0, &"stroll"], [18.5, &"wander"], [20.6, &"home"]],
	&"shopper": [[0.0, &"home"], [7.6, &"wander"], [12.0, &"stroll"], [13.0, &"wander"], [18.8, &"home"]],
	&"elder": [[0.0, &"home"], [7.5, &"stand"], [10.0, &"sit"], [16.0, &"stand"], [19.5, &"home"]],
	&"student": [[0.0, &"home"], [6.0, &"train"], [12.0, &"wander"], [13.0, &"train"], [18.0, &"wander"], [20.0, &"home"]],
	&"gardener": [[0.0, &"home"], [6.0, &"work"], [11.5, &"wander"], [12.5, &"work"], [18.0, &"home"]],
	&"monk": [[0.0, &"home"], [5.0, &"meditate"], [7.5, &"wander"], [11.5, &"meditate"], [13.5, &"stroll"], [17.5, &"meditate"], [20.0, &"home"]],
	&"healer": [[0.0, &"work"]],
	&"noble": [[0.0, &"home"], [8.0, &"stand"], [12.0, &"stroll"], [15.0, &"stand"], [19.0, &"home"]],
	&"named": [[0.0, &"stand"]],
}


## Activity of `role` at `hour`; `offset` (hours, may be negative) shifts the whole schedule.
static func activity(role: StringName, hour: float, offset: float = 0.0) -> StringName:
	var sched: Array = SCHEDULES.get(role, SCHEDULES[&"resident"])
	var h := fposmod(hour - offset, 24.0)
	var act: StringName = (sched[0] as Array)[1]
	for e: Array in sched:
		if h >= float(e[0]):
			act = e[1]
	return act


## Personal schedule offset in hours from a record hash (-0.4 .. +0.45).
static func offset_for(h: int) -> float:
	return (float(absi(h) % 1000) / 1000.0 - 0.47) * 0.9


static func is_present(role: StringName, hour: float, offset: float = 0.0) -> bool:
	return activity(role, hour, offset) != &"home"


## True at night (lanterns for guards, quieter barks).
static func is_night(hour: float) -> bool:
	return hour >= 19.5 or hour < 5.5
