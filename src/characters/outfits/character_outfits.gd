class_name CharacterOutfits
extends RefCounted
## Character config -> resolved outfit spec.
##
## A config is a plain Dictionary (all keys optional except "preset"):
##   preset: StringName  (see PRESETS)
##   body: "male" | "female"          age: "adult" | "teen" | "child" | "elder"
##   height: float (m)                bulk: float (-1 slim .. 1 heavy)
##   skin: int (index into SKIN_TONES) or Color
##   hair_style: String               hair_color: Color or int (HAIR_COLORS)
##   hair_extras: Array[String]       eye_color: Color
##   palette: Dictionary (overrides named colors, e.g. {"primary": Color(...)})
##   accessories: Array[String] props "name" or "name@socket" (RigProps.NAMES),
##                e.g. ["staff@back", "lantern@hand_l"]
##   tattoo: bool     beard: String
##   style: StringName (animation style override)
##   seed: int (seeded variation of everything not given explicitly)
##   detail: int 0..3 (mesh detail; default Settings.detail_level())
##
## resolve() returns the spec consumed by CharacterMeshBuilder and HumanoidRig:
## colors resolved, body bands, garment pieces, "style", "scale", "cache_key".

const PRESETS: Array[StringName] = [
	&"air_nomad", &"monk_elder", &"water_tribe", &"water_warrior", &"earth_kingdom", &"earth_soldier",
	&"dai_li", &"fire_nation", &"fire_soldier", &"bandit", &"pirate", &"merchant", &"guard",
	&"villager_air", &"villager_water", &"villager_earth", &"villager_fire",
]

const SKIN_TONES: Array[Color] = [
	Color(0.98, 0.84, 0.73), Color(0.95, 0.78, 0.64), Color(0.88, 0.68, 0.52),
	Color(0.78, 0.57, 0.40), Color(0.64, 0.44, 0.30), Color(0.49, 0.33, 0.22),
]
const HAIR_COLORS: Array[Color] = [
	Color(0.09, 0.075, 0.08), Color(0.19, 0.12, 0.085), Color(0.33, 0.21, 0.12),
	Color(0.45, 0.28, 0.15), Color(0.63, 0.63, 0.66), Color(0.9, 0.9, 0.92),
]
const EYE_BROWN := Color(0.36, 0.21, 0.11)
const EYE_DARK := Color(0.2, 0.13, 0.09)
const EYE_GREY := Color(0.42, 0.46, 0.52)
const EYE_BLUE := Color(0.2, 0.46, 0.78)
const EYE_AMBER := Color(0.86, 0.6, 0.16)
const EYE_GREEN := Color(0.32, 0.5, 0.26)


## Resolves a config into a full spec (deterministic for a given config/seed).
static func resolve(config: Dictionary) -> Dictionary:
	var preset: StringName = StringName(config.get("preset", &"villager_earth"))
	if not PRESETS.has(preset):
		push_warning("CharacterOutfits: unknown preset '%s', using villager_earth" % preset)
		preset = &"villager_earth"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(config.get("seed", 0)) + String(preset))
	var info: Dictionary = OutfitPresets.info(preset)
	var body: String = config.get("body", info.get("body", "male"))
	var age: String = config.get("age", info.get("age", "adult"))
	var bulk: float = config.get("bulk", [-0.5, 0.0, 0.0, 0.5][rng.randi_range(0, 3)] if config.has("seed") else float(info.get("bulk", 0.0)))
	bulk = snappedf(clampf(bulk, -1.0, 1.0), 0.5)
	var props := RigSkeletonDef.make_proportions(body, age, bulk)
	var d := RigSkeletonDef.new().build(props)
	var canon: float = props["height"]
	var height: float = config.get("height", canon * (1.0 + (rng.randf_range(-0.035, 0.035) if config.has("seed") else 0.0)))
	var spec := {
		"preset": preset, "body": body, "age": age, "bulk": bulk,
		"style": StringName(config.get("style", info.get("style", &"civilian"))),
		"scale": height / canon, "height": height,
		"detail": int(config.get("detail", _default_detail())),
	}
	# Skin, hair, eyes.
	var skin_v: Variant = config.get("skin", null)
	var skin_choices: Array = info.get("skins", [1, 2, 3])
	var skin_i: int = skin_choices[rng.randi_range(0, skin_choices.size() - 1)]
	if skin_v is int:
		skin_i = clampi(skin_v, 0, SKIN_TONES.size() - 1)
	spec["skin"] = skin_v if skin_v is Color else SKIN_TONES[skin_i]
	var styles: Array = info.get("hair_" + body, info.get("hair", ["short"]))
	if age == "elder" and info.has("hair_elder"):
		styles = info["hair_elder"]
	var hs_pick: Variant = styles[rng.randi_range(0, styles.size() - 1)]
	var hair_style: String
	var hair_extras: Array = []
	if hs_pick is Array:
		hair_style = hs_pick[0]
		hair_extras = (hs_pick as Array).slice(1)
	else:
		hair_style = hs_pick
	hair_style = config.get("hair_style", hair_style)
	hair_extras = config.get("hair_extras", hair_extras)
	spec["hair_style"] = hair_style
	spec["hair_extras"] = hair_extras
	var hc_choices: Array = info.get("hair_colors", [0, 1])
	var hc_i: int = hc_choices[rng.randi_range(0, hc_choices.size() - 1)]
	if age == "elder":
		hc_i = 4 if rng.randf() < 0.5 else 5
	var hc_v: Variant = config.get("hair_color", null)
	spec["hair_color"] = hc_v if hc_v is Color else HAIR_COLORS[clampi(hc_v if hc_v is int else hc_i, 0, HAIR_COLORS.size() - 1)]
	var eyes: Array = info.get("eyes", [EYE_BROWN])
	spec["eye_color"] = config.get("eye_color", eyes[rng.randi_range(0, eyes.size() - 1)])
	if config.has("beard"):
		spec["beard"] = config["beard"]
	elif age == "elder" and body == "male" and rng.randf() < float(info.get("beard_chance", 0.6)):
		spec["beard"] = info.get("beard", "goatee")
	# Palette: preset variant + overrides.
	var pals: Array = info.get("palettes", [{}])
	var pal_i := rng.randi_range(0, pals.size() - 1)
	var pal: Dictionary = (pals[pal_i] as Dictionary).duplicate()
	var over: Dictionary = config.get("palette", {})
	for k: String in over:
		pal[k] = over[k]
	pal["skin"] = spec["skin"]
	pal["hair"] = spec["hair_color"]
	var acc: Array = config.get("accessories", info.get("accessories", []))
	spec["accessories"] = acc
	spec["tattoo"] = config.get("tattoo", info.get("tattoo", false))
	var lm := {
		"torso": RigBodyBuilder.torso_landmarks(d),
		"arm": arm_landmarks(d),
		"leg": leg_landmarks(d),
	}
	OutfitPresets.dress(preset, spec, pal, lm, rng)
	# Band inflation is authored as a fraction of height; the mesh works in meters.
	for key: String in ["torso_bands", "arm_bands", "leg_bands", "foot_bands", "neck_bands"]:
		for band: Dictionary in spec.get(key, []):
			band["inflate"] = float(band.get("inflate", 0.0)) * canon
	spec["cache_key"] = "%s|%s|%s|%.1f|%s|%s|%s|%s|%d|%s|%d|%s" % [preset, body, age, bulk, (spec["skin"] as Color).to_html(), hair_style, ",".join(PackedStringArray(hair_extras)),
		(spec["hair_color"] as Color).to_html(), pal_i, (spec["eye_color"] as Color).to_html(), spec["detail"], str(spec.get("beard", "")) + str(spec["tattoo"]) + str(over)]
	return spec


static func _default_detail() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root.has_node(^"Settings"):
		return int(tree.root.get_node(^"Settings").call(&"detail_level"))
	return 2


static func arm_landmarks(d: RigSkeletonDef) -> Dictionary:
	var h: float = d.p["height"]
	var top := 0.018 * h
	var total := top + d.upper_arm_len + d.forearm_len
	return {"shoulder": top / total, "elbow": (top + d.upper_arm_len) / total, "wrist": 1.0}


static func leg_landmarks(d: RigSkeletonDef) -> Dictionary:
	var h: float = d.p["height"]
	var top := 0.04 * h
	var total := top + d.thigh_len + d.shin_len
	return {"hip": top / total, "knee": (top + d.thigh_len) / total, "ankle": 1.0}


## Convenience: builds a list of contiguous bands from [t_end, color, inflate] steps.
static func bands(steps: Array) -> Array:
	var out: Array = []
	var t0 := 0.0
	for s: Array in steps:
		var t1: float = s[0]
		if t1 > t0 + 0.0005:
			out.append({"t0": t0, "t1": t1, "color": s[1], "inflate": float(s[2]) if s.size() > 2 else 0.0})
		t0 = t1
	return out
