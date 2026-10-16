extends "res://src/world/settlements/dev/settlements_dev.gd"
## Dev scene of Settlements II (Ba Sing Se, Omashu, Earth Kingdom villages, the Fire Nation
## capital, Crimson Harbor and the Fire Nation villages): the real world + content + every
## settlement, free-fly camera and the named views below (plus settlements_wa's).
##   godot --path . -- --scene=res://scenes/dev/settlements_ef.tscn
## Controls as in settlements_dev.gd (RMB look, WASD/QE fly, Shift x6, T +1 h, N night, P stats);
## F1..F12 jump to the first twelve views of EF_VIEWS.

const EF_VIEWS := {
	# --- Ba Sing Se ---
	"bss_far": {"pos": Vector3(1020, 150, 520), "look": Vector3(1900, 80, 160), "hour": 16.0, "fov": 55.0},
	"bss_wall": {"pos": Vector3(1180, 64, 330), "look": Vector3(1300, 80, 200), "hour": 15.5, "fov": 62.0},
	"bss_gate": {"pos": Vector3(1215, 61, 206), "look": Vector3(1300, 70, 200), "hour": 16.5, "fov": 64.0},
	"bss_farm": {"pos": Vector3(1460, 70, 330), "look": Vector3(1640, 62, 230), "hour": 10.0, "fov": 64.0},
	"bss_inner_wall": {"pos": Vector3(1560, 64, 228), "look": Vector3(1625, 75, 200), "hour": 11.0, "fov": 64.0},
	"bss_lower": {"pos": Vector3(1722.7, 62.4, 329.3), "look": Vector3(1707.4, 62.0, 289.5), "hour": 14.0, "fov": 68.0},
	"bss_lower_market": {"pos": Vector3(1649.3, 63.4, 230.7), "look": Vector3(1670.0, 61.5, 197.1), "hour": 11.5, "fov": 68.0},
	"bss_middle": {"pos": Vector3(1816.8, 69.2, 94.2), "look": Vector3(1803.9, 69.0, 120.8), "hour": 10.5, "fov": 66.0},
	"bss_upper": {"pos": Vector3(2066.2, 88.2, 121.1), "look": Vector3(2081.2, 89.0, 136.6), "hour": 16.4, "fov": 64.0},
	"bss_gate_inside": {"pos": Vector3(1360.0, 62.0, 200.0), "look": Vector3(1300.0, 72.0, 200.0), "hour": 9.5, "fov": 64.0},
	"bss_tea_shop": {"pos": Vector3(1692.2, 62.3, 254.3), "look": Vector3(1681.1, 61.6, 244.8), "hour": 12.0, "fov": 74.0},
	"bss_hall": {"pos": Vector3(1803.2, 69.4, 104.0), "look": Vector3(1791.5, 68.6, 98.3), "hour": 12.0, "fov": 74.0},
	"bss_palace": {"pos": Vector3(2000, 100, 330), "look": Vector3(2000, 115, 200), "hour": 15.0, "fov": 64.0},
	"bss_spawn": {"pos": Vector3(1875.75, 89, 242.64), "look": Vector3(1808.75, 86.5, 242.64), "hour": 16.4, "fov": 72.0},
	"bss_night": {"pos": Vector3(1590, 95, 120), "look": Vector3(2000, 80, 200), "hour": 22.0, "fov": 60.0},
	"bss_arrival": {"pos": Vector3(2508.75, 346.0, 242.64), "look": Vector3(1608.75, 56.0, 242.64), "hour": 16.4, "fov": 58.0},
	"bss_gate_noon": {"pos": Vector3(1215, 61, 206), "look": Vector3(1300, 70, 200), "hour": 11.0, "fov": 64.0},
	"bss_aerial": {"pos": Vector3(1400, 520, 900), "look": Vector3(2000, 60, 200), "hour": 15.0, "fov": 55.0},
	# --- Omashu ---
	"omashu_far": {"pos": Vector3(980, 260, -300), "look": Vector3(380, 190, -420), "hour": 15.0, "fov": 55.0},
	"omashu_bridge": {"pos": Vector3(752, 166, -414), "look": Vector3(640, 176, -420), "hour": 16.0, "fov": 66.0},
	"omashu_city": {"pos": Vector3(655, 163.8, -414), "look": Vector3(380, 215, -420), "hour": 10.0, "fov": 64.0},
	"omashu_market": {"pos": Vector3(439.5, 179.8, -583.5), "look": Vector3(491.8, 179.0, -553.3), "hour": 11.0, "fov": 68.0},
	"omashu_summit": {"pos": Vector3(470, 230, -300), "look": Vector3(380, 225, -420), "hour": 15.0, "fov": 62.0},
	"fmb_square": {"pos": Vector3(-282, 9.0, 1712), "look": Vector3(-300, 7.0, 1700), "hour": 11.0, "fov": 68.0},
	"fmb_harbor": {"pos": Vector3(-600, 12, 1760), "look": Vector3(-520, 6, 1760), "hour": 16.0, "fov": 62.0},
	# --- Earth Kingdom villages ---
	"fmb_port": {"pos": Vector3(-560, 30, 1900), "look": Vector3(-320, 10, 1720), "hour": 9.5, "fov": 60.0},
	"millet_hollow": {"pos": Vector3(780, 112, 470), "look": Vector3(860, 94, 420), "hour": 11.0, "fov": 62.0},
	"cedar_rest": {"pos": Vector3(700, 70, 1470), "look": Vector3(760, 57, 1420), "hour": 13.0, "fov": 62.0},
	"northreach": {"pos": Vector3(-420, 30, -1760), "look": Vector3(-300, 6, -1610), "hour": 12.0, "fov": 62.0},
	# --- Fire Nation ---
	"fnc_rim": {"pos": Vector3(-2879, 306, 2177), "look": Vector3(-2600, 150, 2600), "hour": 16.0, "fov": 58.0},
	"fnc_aerial": {"pos": Vector3(-2600, 520, 3130), "look": Vector3(-2600, 130, 2640), "hour": 15.0, "fov": 55.0},
	"fnc_gorge": {"pos": Vector3(-2180, 100, 2318), "look": Vector3(-2240, 104, 2366), "hour": 15.0, "fov": 64.0},
	"fnc_palace": {"pos": Vector3(-2600, 141, 2720), "look": Vector3(-2600, 160, 2600), "hour": 15.6, "fov": 64.0},
	"fnc_courtyard": {"pos": Vector3(-2600, 148, 2640), "look": Vector3(-2600, 152, 2600), "hour": 15.0, "fov": 70.0},
	"fnc_lower": {"pos": Vector3(-2618, 114, 2935.5), "look": Vector3(-2570, 115, 2932), "hour": 11.0, "fov": 68.0},
	"fnc_noble": {"pos": Vector3(-2450, 126, 2700), "look": Vector3(-2510, 126, 2650), "hour": 13.0, "fov": 68.0},
	"fnc_spawn": {"pos": Vector3(-2484.82, 141, 2562.23), "look": Vector3(-2428.6, 138.5, 2525.78), "hour": 15.6, "fov": 72.0},
	"fnc_night": {"pos": Vector3(-2879, 306, 2177), "look": Vector3(-2600, 140, 2600), "hour": 22.5, "fov": 58.0},
	"fnc_braziers": {"pos": Vector3(-2560, 142, 2700), "look": Vector3(-2600, 150, 2620), "hour": 21.5, "fov": 66.0},
	"fh_harbor": {"pos": Vector3(-1640, 30, 1880), "look": Vector3(-1760, 8, 2080), "hour": 10.0, "fov": 62.0},
	"fh_town": {"pos": Vector3(-1900, 40, 2120), "look": Vector3(-1980, 50, 2100), "hour": 14.0, "fov": 64.0},
	"saltspark": {"pos": Vector3(-3500, 20, 2600), "look": Vector3(-3560, 4, 2660), "hour": 10.0, "fov": 62.0},
	"ashleaf": {"pos": Vector3(-2300, 125, 3240), "look": Vector3(-2350, 106, 3300), "hour": 9.0, "fov": 62.0},
	"sunflare": {"pos": Vector3(-3230, 30, 1460), "look": Vector3(-3300, 8, 1390), "hour": 17.0, "fov": 62.0},
}


func set_view(vname: String) -> void:
	if not EF_VIEWS.has(vname):
		super(vname)
		return
	var v: Dictionary = EF_VIEWS[vname]
	var pos: Vector3 = v["pos"]
	var look: Vector3 = v["look"]
	if v.get("agl", false):
		pos.y += maxf(WorldData.get_height(pos.x, pos.z), 0.0)
		look.y += maxf(WorldData.get_height(look.x, look.z), 0.0)
	place_camera(pos, look, v.get("fov", 60.0))
	if v.has("hour"):
		world.set_time_of_day(v["hour"])
	world.set_weather(v.get("weather", &"clear"), 0.0)


## All view names (settlements_ef first).
func view_names() -> Array:
	return EF_VIEWS.keys() + VIEWS.keys()


func has_view(vname: String) -> bool:
	return EF_VIEWS.has(vname) or VIEWS.has(vname)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key >= KEY_F1 and key <= KEY_F12 and key - KEY_F1 < EF_VIEWS.size():
			set_view(EF_VIEWS.keys()[key - KEY_F1])
			return
	super(event)
