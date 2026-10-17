extends RefCounted
## Pose sheets of the Air technique clips (AirClips) frozen at their key frames,
## for reviewing the Ba Gua body motion (characters_posesheet with the air clips
## registered). SHEET overrides the set; VIEW=front|side|34|back (default 34).

const SHEETS := [
	"air_push_gather@0.0,air_push_gather@0.5,air_push_release@0.15,air_push_release@0.3,air_push_release@0.56,air_scooter_ride@0.0",
	"wind_blade_kick@0.12,wind_blade_kick@0.3,wind_blade_kick@0.44,wind_blade_kick@0.62,wind_blade_air@0.28,wind_blade_air@0.46",
	"air_tornado_cast@0.05,air_tornado_cast@0.12,air_tornado_cast@0.2,air_tornado_cast@0.38,air_tornado_cast@0.62,air_tornado_cast@0.86",
	"air_dive@0.0,air_slam_land@0.1,air_slam_land@0.42,vortex_ward_hold@0.0,vortex_ward_hold@0.5,air_jump_flip@0.32",
]


func run(p: Playtest) -> void:
	AirClips.ensure()
	BendingClips.ensure()
	if OS.get_environment("SHEET") == "":
		OS.set_environment("SHEET", ";".join(SHEETS))
	if OS.get_environment("PRESET") == "":
		OS.set_environment("PRESET", "air_nomad")
	if OS.get_environment("VIEW") == "":
		OS.set_environment("VIEW", "34")
	var sheet: Object = load("res://tests/playtest/scenarios/characters_posesheet.gd").new()
	await sheet.run(p)
