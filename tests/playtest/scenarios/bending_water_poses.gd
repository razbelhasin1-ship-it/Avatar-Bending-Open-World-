extends RefCounted
## Pose sheets of the Water technique clips (WaterClips) frozen at their key
## frames, for reviewing the body motion (characters_posesheet with the water
## clips registered). VIEW=front|side|34|back (default side).

const SHEETS := [
	"water_surge_heave@0.16,water_surge_heave@0.34,water_surge_heave@0.48,water_surge_heave@0.6,water_surge_heave@0.8",
	"water_ice_wall@0.2,water_ice_wall@0.44,water_ice_wall@0.52,water_ice_trap@0.18,water_ice_trap@0.4,water_ice_trap@0.72",
	"water_wave_ride@0.0,water_wave_ride@0.5,water_wave_crash@0.24,water_wave_crash@0.42,water_jet_open@0.6,water_heal_channel@0.9",
	"tidal_torrent@0.1,tidal_torrent@0.26,tidal_torrent@0.42,tidal_torrent@0.58,tidal_torrent@0.68,tidal_torrent@0.74",
]


func run(p: Playtest) -> void:
	WaterClips.ensure()
	OS.set_environment("SHEET", ";".join(SHEETS))
	OS.set_environment("PRESET", "water_tribe_f")
	if OS.get_environment("VIEW") == "":
		OS.set_environment("VIEW", "side")
	var sheet: Object = load("res://tests/playtest/scenarios/characters_posesheet.gd").new()
	await sheet.run(p)
