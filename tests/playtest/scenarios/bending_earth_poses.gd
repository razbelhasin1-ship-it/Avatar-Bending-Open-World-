extends RefCounted
## Pose sheets of the Earth technique clips (EarthClips) frozen at their key
## frames, for reviewing the Hung Gar body motion (characters_posesheet with the
## earth clips registered). VIEW=front|side|34|back (default 34).

const SHEETS := [
	"earth_pillar_raise@0.14,earth_pillar_raise@0.32,earth_pillar_raise@0.42,earth_stomp_quake@0.17,earth_stomp_quake@0.31,earth_stomp_quake@0.38",
	"earth_spikes_drive@0.18,earth_spikes_drive@0.4,earth_grab_clench@0.18,earth_grab_clench@0.3,earth_grab_clench@0.55,earth_armor_don@0.24",
	"earth_armor_don@0.48,earth_armor_don@0.66,earth_armor_don@0.8,earth_armor_shed@0.2,earth_armor_shed@0.36,earthquake_slam@0.12",
	"earthquake_slam@0.26,earthquake_slam@0.4,earthquake_slam@0.56,earthquake_slam@0.72,combo_earth_1@0.46,combo_earth_3@0.56",
]


func run(p: Playtest) -> void:
	EarthClips.ensure()
	BendingClips.ensure()
	var only := OS.get_environment("SHEET")
	if only == "":
		OS.set_environment("SHEET", ";".join(SHEETS))
	if OS.get_environment("PRESET") == "":
		OS.set_environment("PRESET", "earth_kingdom")
	if OS.get_environment("VIEW") == "":
		OS.set_environment("VIEW", "34")
	var sheet: Object = load("res://tests/playtest/scenarios/characters_posesheet.gd").new()
	await sheet.run(p)
