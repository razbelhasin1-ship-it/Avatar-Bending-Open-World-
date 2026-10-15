class_name OutfitPresets
extends RefCounted
## Outfit preset data: per-preset defaults (info) and the "dress" step that
## turns a palette into body color bands and garment pieces.
##
## Torso t landmarks (lm.torso): crotch 0 .. hip .. belt .. waist .. chest ..
## armpit .. shoulder .. neck 1. Arm: shoulder .. elbow .. wrist 1.
## Leg: hip .. knee .. ankle 1. Inflate values are fractions of body height.

const B := preload("res://src/characters/outfits/character_outfits.gd")

const C_SHOE := Color(0.36, 0.24, 0.16)
const C_BLACK := Color(0.12, 0.105, 0.11)
const C_WHITE_FUR := Color(0.95, 0.95, 0.96)
const C_GOLD := Color(0.93, 0.73, 0.27)

const INFO := {
	&"air_nomad": {"style": &"air", "accessories": ["staff@back"], "skins": [1, 2, 3], "hair_male": ["bald"], "hair_female": [["parted", "bun"], ["bangs", "long"]],
		"hair_colors": [1, 2, 3], "eyes": [B.EYE_GREY, B.EYE_BROWN], "tattoo": true,
		"palettes": [{"robe": Color(0.96, 0.55, 0.16), "shirt": Color(0.99, 0.79, 0.3), "wrap": Color(0.9, 0.83, 0.62), "shoe": Color(0.5, 0.33, 0.2)},
			{"robe": Color(0.93, 0.47, 0.13), "shirt": Color(0.98, 0.74, 0.25), "wrap": Color(0.86, 0.78, 0.58), "shoe": Color(0.45, 0.3, 0.18)}]},
	&"monk_elder": {"style": &"elder", "age": "elder", "skins": [1, 2], "hair_male": ["bald"], "hair_female": [["parted", "bun"]], "beard": "long", "beard_chance": 1.0,
		"eyes": [B.EYE_GREY], "tattoo": true,
		"palettes": [{"robe": Color(0.94, 0.52, 0.16), "shirt": Color(0.98, 0.78, 0.3), "shoe": Color(0.45, 0.3, 0.18)}]},
	&"water_tribe": {"style": &"water", "skins": [3, 4, 5], "hair_male": [["undercut", "wolf_tail"], ["short"]], "hair_female": [["parted", "loopies", "braid"], ["parted", "long", "loopies"]],
		"hair_colors": [0, 1], "eyes": [B.EYE_BLUE, B.EYE_BLUE, B.EYE_GREY],
		"palettes": [{"parka": Color(0.22, 0.43, 0.74), "pants": Color(0.16, 0.22, 0.38), "trim": Color(0.62, 0.82, 0.95), "boot": Color(0.27, 0.22, 0.22)},
			{"parka": Color(0.18, 0.36, 0.64), "pants": Color(0.2, 0.2, 0.3), "trim": Color(0.92, 0.94, 0.96), "boot": Color(0.24, 0.24, 0.3)},
			{"parka": Color(0.3, 0.5, 0.78), "pants": Color(0.14, 0.18, 0.32), "trim": Color(0.55, 0.75, 0.9), "boot": Color(0.3, 0.24, 0.2)}]},
	&"water_warrior": {"style": &"water", "skins": [3, 4, 5], "hair_male": ["undercut"], "hair_female": ["undercut"], "hair_colors": [0, 1], "eyes": [B.EYE_BLUE],
		"palettes": [{"parka": Color(0.17, 0.3, 0.55), "pants": Color(0.13, 0.16, 0.28), "trim": Color(0.6, 0.78, 0.92), "boot": Color(0.2, 0.2, 0.24), "armor": Color(0.36, 0.4, 0.48)}]},
	&"earth_kingdom": {"style": &"earth", "skins": [1, 2, 3, 4], "hair_male": [["slick", "topknot"], ["short"]], "hair_female": [["parted", "bun"], ["bangs", "long"]],
		"hair_colors": [0, 1, 2], "eyes": [B.EYE_BROWN, B.EYE_GREEN, B.EYE_DARK],
		"palettes": [{"tunic": Color(0.33, 0.56, 0.29), "under": Color(0.84, 0.74, 0.52), "pants": Color(0.36, 0.28, 0.19), "sash": Color(0.84, 0.7, 0.32), "trim": Color(0.18, 0.34, 0.17), "shoe": Color(0.32, 0.22, 0.14)},
			{"tunic": Color(0.42, 0.58, 0.32), "under": Color(0.8, 0.7, 0.5), "pants": Color(0.24, 0.32, 0.2), "sash": Color(0.62, 0.45, 0.26), "trim": Color(0.25, 0.38, 0.2), "shoe": Color(0.3, 0.22, 0.15)},
			{"tunic": Color(0.26, 0.47, 0.3), "under": Color(0.88, 0.8, 0.6), "pants": Color(0.42, 0.33, 0.22), "sash": Color(0.78, 0.6, 0.3), "trim": Color(0.16, 0.28, 0.18), "shoe": Color(0.28, 0.2, 0.14)}]},
	&"earth_soldier": {"style": &"soldier", "skins": [1, 2, 3, 4], "hair_male": ["short"], "hair_female": ["slick"], "hair_colors": [0, 1], "eyes": [B.EYE_BROWN],
		"palettes": [{"tunic": Color(0.29, 0.5, 0.26), "armor": Color(0.2, 0.36, 0.2), "under": Color(0.78, 0.68, 0.46), "pants": Color(0.3, 0.26, 0.18), "trim": Color(0.72, 0.62, 0.38), "shoe": Color(0.24, 0.18, 0.12)}]},
	&"dai_li": {"style": &"earth", "skins": [1, 2, 3], "hair_male": [["slick", "braid"]], "hair_female": [["slick", "braid"]], "hair_colors": [0], "eyes": [B.EYE_DARK],
		"palettes": [{"robe": Color(0.12, 0.25, 0.17), "trim": Color(0.08, 0.08, 0.09), "sash": Color(0.6, 0.62, 0.26), "stone": Color(0.42, 0.42, 0.4)}]},
	&"fire_nation": {"style": &"fire", "skins": [0, 1, 2], "hair_male": [["slick", "topknot"]], "hair_female": [["bangs", "topknot", "long"]], "hair_colors": [0, 1], "eyes": [B.EYE_AMBER, B.EYE_AMBER, B.EYE_BROWN],
		"palettes": [{"tunic": Color(0.74, 0.14, 0.11), "dark": Color(0.4, 0.07, 0.07), "black": C_BLACK, "gold": C_GOLD},
			{"tunic": Color(0.66, 0.12, 0.1), "dark": Color(0.18, 0.08, 0.08), "black": Color(0.15, 0.12, 0.12), "gold": Color(0.9, 0.68, 0.22)}]},
	&"fire_soldier": {"style": &"soldier", "skins": [0, 1, 2], "hair_male": ["cropped"], "hair_female": ["cropped"], "hair_colors": [0], "eyes": [B.EYE_AMBER],
		"palettes": [{"armor": Color(0.42, 0.09, 0.08), "tunic": Color(0.62, 0.12, 0.1), "black": Color(0.11, 0.1, 0.1), "metal": Color(0.2, 0.19, 0.2)}]},
	&"bandit": {"style": &"civilian", "skins": [1, 2, 3, 4, 5], "hair_male": ["spiky", "short"], "hair_female": [["bangs", "ponytail"]], "hair_colors": [0, 1, 2, 3], "eyes": [B.EYE_BROWN, B.EYE_DARK],
		"palettes": [{"shirt": Color(0.82, 0.76, 0.64), "vest": Color(0.36, 0.25, 0.17), "pants": Color(0.4, 0.38, 0.36), "scarf": Color(0.58, 0.18, 0.14), "shoe": Color(0.26, 0.2, 0.15)},
			{"shirt": Color(0.6, 0.58, 0.5), "vest": Color(0.24, 0.24, 0.26), "pants": Color(0.35, 0.28, 0.2), "scarf": Color(0.32, 0.3, 0.5), "shoe": Color(0.22, 0.18, 0.15)}]},
	&"pirate": {"style": &"civilian", "skins": [1, 2, 3, 4], "hair_male": ["spiky", ["short", "ponytail"]], "hair_female": [["bangs", "ponytail"]], "hair_colors": [0, 1, 3], "eyes": [B.EYE_BROWN, B.EYE_GREY],
		"palettes": [{"shirt": Color(0.88, 0.85, 0.78), "stripe": Color(0.58, 0.14, 0.12), "vest": Color(0.18, 0.16, 0.2), "pants": Color(0.3, 0.27, 0.24), "sash": Color(0.7, 0.18, 0.14), "shoe": Color(0.15, 0.12, 0.11)}]},
	&"merchant": {"style": &"civilian", "skins": [1, 2, 3], "hair_male": [["slick", "topknot"]], "hair_female": [["parted", "bun"]], "hair_colors": [0, 1, 4], "bulk": 0.5, "beard": "goatee", "beard_chance": 0.8, "eyes": [B.EYE_BROWN],
		"palettes": [{"robe": Color(0.5, 0.3, 0.42), "trim": Color(0.88, 0.7, 0.32), "under": Color(0.9, 0.84, 0.7), "sash": Color(0.3, 0.2, 0.3), "hat": Color(0.3, 0.2, 0.28)},
			{"robe": Color(0.28, 0.44, 0.42), "trim": Color(0.85, 0.72, 0.4), "under": Color(0.9, 0.86, 0.72), "sash": Color(0.55, 0.32, 0.18), "hat": Color(0.2, 0.25, 0.25)}]},
	&"guard": {"style": &"soldier", "accessories": ["spear@hand_r"], "skins": [1, 2, 3, 4], "hair_male": ["short"], "hair_female": ["slick"], "hair_colors": [0, 1], "eyes": [B.EYE_BROWN],
		"palettes": [{"tunic": Color(0.5, 0.42, 0.24), "armor": Color(0.24, 0.38, 0.22), "pants": Color(0.26, 0.22, 0.16), "trim": Color(0.75, 0.62, 0.32), "shoe": Color(0.2, 0.16, 0.12)}]},
	&"villager_air": {"style": &"civilian", "skins": [1, 2, 3], "hair_male": ["short", "cropped", "bald"], "hair_female": [["parted", "bun"], ["bangs", "long"]], "hair_colors": [1, 2, 3], "eyes": [B.EYE_GREY, B.EYE_BROWN],
		"palettes": [{"robe": Color(0.92, 0.6, 0.25), "shirt": Color(0.95, 0.82, 0.48), "wrap": Color(0.85, 0.78, 0.6), "shoe": Color(0.48, 0.34, 0.22)},
			{"robe": Color(0.82, 0.5, 0.22), "shirt": Color(0.9, 0.78, 0.5), "wrap": Color(0.8, 0.72, 0.56), "shoe": Color(0.42, 0.3, 0.2)}]},
	&"villager_water": {"style": &"civilian", "skins": [3, 4, 5], "hair_male": [["undercut", "wolf_tail"], ["short"]], "hair_female": [["parted", "braid"], ["parted", "long"], ["parted", "loopies", "braid"]], "hair_colors": [0, 1],
		"eyes": [B.EYE_BLUE, B.EYE_GREY, B.EYE_BROWN],
		"palettes": [{"parka": Color(0.32, 0.46, 0.66), "pants": Color(0.22, 0.25, 0.35), "trim": Color(0.92, 0.92, 0.9), "boot": Color(0.3, 0.25, 0.22)},
			{"parka": Color(0.4, 0.42, 0.55), "pants": Color(0.25, 0.25, 0.3), "trim": Color(0.75, 0.82, 0.9), "boot": Color(0.28, 0.24, 0.24)},
			{"parka": Color(0.25, 0.36, 0.52), "pants": Color(0.2, 0.22, 0.28), "trim": Color(0.9, 0.88, 0.82), "boot": Color(0.34, 0.27, 0.22)}]},
	&"villager_earth": {"style": &"civilian", "skins": [1, 2, 3, 4], "hair_male": [["slick", "topknot"], ["short"], ["cropped"]], "hair_female": [["parted", "bun"], ["parted", "braid"], ["bangs", "long"]], "hair_colors": [0, 1, 2, 3],
		"eyes": [B.EYE_BROWN, B.EYE_GREEN, B.EYE_DARK],
		"palettes": [{"tunic": Color(0.55, 0.62, 0.38), "under": Color(0.86, 0.78, 0.6), "pants": Color(0.42, 0.32, 0.22), "sash": Color(0.6, 0.45, 0.25), "trim": Color(0.36, 0.42, 0.24), "shoe": Color(0.32, 0.24, 0.16)},
			{"tunic": Color(0.62, 0.5, 0.34), "under": Color(0.88, 0.82, 0.66), "pants": Color(0.3, 0.36, 0.24), "sash": Color(0.38, 0.5, 0.28), "trim": Color(0.42, 0.32, 0.2), "shoe": Color(0.3, 0.22, 0.15)},
			{"tunic": Color(0.4, 0.55, 0.42), "under": Color(0.82, 0.76, 0.58), "pants": Color(0.38, 0.3, 0.24), "sash": Color(0.72, 0.62, 0.36), "trim": Color(0.26, 0.38, 0.28), "shoe": Color(0.28, 0.2, 0.14)}]},
	&"villager_fire": {"style": &"civilian", "skins": [0, 1, 2], "hair_male": [["slick", "topknot"], ["short"]], "hair_female": [["parted", "bun"], ["bangs", "long"]], "hair_colors": [0, 1, 2], "eyes": [B.EYE_AMBER, B.EYE_BROWN],
		"palettes": [{"tunic": Color(0.72, 0.3, 0.22), "under": Color(0.86, 0.78, 0.66), "pants": Color(0.2, 0.17, 0.17), "sash": Color(0.4, 0.14, 0.12), "trim": Color(0.48, 0.16, 0.12), "shoe": Color(0.18, 0.14, 0.13)},
			{"tunic": Color(0.78, 0.66, 0.5), "under": Color(0.68, 0.26, 0.2), "pants": Color(0.28, 0.2, 0.18), "sash": Color(0.62, 0.2, 0.15), "trim": Color(0.6, 0.22, 0.16), "shoe": Color(0.2, 0.15, 0.13)}]},
}


static func info(preset: StringName) -> Dictionary:
	return INFO.get(preset, INFO[&"villager_earth"])


static func dress(preset: StringName, spec: Dictionary, pal: Dictionary, lm: Dictionary, rng: RandomNumberGenerator) -> void:
	var female: bool = spec["body"] == "female"
	var pieces: Array = []
	spec["pieces"] = pieces
	match preset:
		&"air_nomad", &"villager_air":
			_air(spec, pal, lm, female, preset == &"villager_air", rng)
		&"monk_elder":
			_monk(spec, pal, lm)
		&"water_tribe", &"villager_water", &"water_warrior":
			_water(spec, pal, lm, female, preset)
		&"earth_kingdom", &"villager_earth", &"earth_soldier", &"guard":
			_earth(spec, pal, lm, female, preset, rng)
		&"dai_li":
			_dai_li(spec, pal, lm)
		&"fire_nation", &"villager_fire", &"fire_soldier":
			_fire(spec, pal, lm, female, preset, rng)
		&"bandit", &"pirate":
			_outlaw(spec, pal, lm, preset == &"pirate", rng)
		&"merchant":
			_merchant(spec, pal, lm, female)
	if spec["age"] == "elder" and spec["style"] == &"civilian":
		spec["style"] = &"elder"
	if spec["age"] == "child" and spec["style"] in [&"civilian", &"elder"]:
		spec["style"] = &"child"


static func _bands(steps: Array) -> Array:
	return B.bands(steps)


## V-neck opening with trim strips along both edges.
static func _vneck(spec: Dictionary, t_v: float, half: float, inner: Color, trim: Color, lift: float, cross: float = 0.0) -> void:
	var pieces: Array = spec["pieces"]
	pieces.append({"type": "vneck", "t": t_v, "half": half, "center": 0.25 + cross, "color": inner, "lift": lift - 0.0025})
	var c := 0.25 + cross
	pieces.append({"type": "strip", "part": "torso", "pts": [Vector2(t_v, c), Vector2(1.0, c - half)], "width": 0.011, "lift": lift, "color": trim})
	pieces.append({"type": "strip", "part": "torso", "pts": [Vector2(t_v - 0.004, c), Vector2(1.0, c + half)], "width": 0.011, "lift": lift, "color": trim})


static func _air(spec: Dictionary, pal: Dictionary, lm: Dictionary, female: bool, villager: bool, _rng: RandomNumberGenerator) -> void:
	var t: Dictionary = lm["torso"]
	var a: Dictionary = lm["arm"]
	var l: Dictionary = lm["leg"]
	var robe: Color = pal["robe"]
	var shirt: Color = pal["shirt"]
	var wrap: Color = pal["wrap"]
	var belt: float = t["belt"]
	var pants := robe.lerp(shirt, 0.35)
	spec["torso_bands"] = _bands([[belt - 0.01, pants, 0.006], [belt + 0.045, robe.darkened(0.12), 0.011], [t["armpit"] - 0.06, shirt, 0.006], [1.0, robe, 0.01]])
	spec["arm_bands"] = _bands([[a["shoulder"] + 0.2, robe, 0.009], [0.9, shirt, 0.004], [1.0, spec["skin"], 0.0]])
	spec["leg_bands"] = _bands([[l["knee"] + 0.1, pants, 0.006], [l["knee"] + 0.19, wrap, 0.008], [l["knee"] + 0.21, wrap.darkened(0.15), 0.008],
		[l["knee"] + 0.31, wrap, 0.008], [l["knee"] + 0.33, wrap.darkened(0.15), 0.008], [0.97, wrap, 0.008], [1.0, wrap.darkened(0.1), 0.006]])
	spec["foot_color"] = pal["shoe"]
	spec["foot_style"] = "shoe"
	spec["torso_bulk"] = {"chest": 0.004, "waist": 0.006}
	var pieces: Array = spec["pieces"]
	pieces.append({"type": "ring", "part": "torso", "t": 0.985, "width": 0.05, "thick": 0.009, "color": robe.darkened(0.1)})
	pieces.append({"type": "ring", "part": "arm", "t": 0.895, "width": 0.035, "thick": 0.007, "color": robe})
	pieces.append({"type": "strip", "part": "torso", "pts": [Vector2(t["armpit"] - 0.06, 0.0), Vector2(t["armpit"] - 0.06, 0.5), Vector2(t["armpit"] - 0.06, 1.0)], "width": 0.008, "lift": 0.0115, "color": robe.darkened(0.2)})
	if not villager:
		pieces.append({"type": "cape", "color": robe, "length": 0.24, "top": 0.94})
	if female:
		pieces.append({"type": "skirt", "top": belt + 0.02, "hem": 0.2, "flare": 1.3, "color": shirt, "trim": robe, "trim_w": 0.14})
	if spec["hair_style"] == "bald" and spec["tattoo"] and not villager:
		spec["arrow_tattoo"] = true
	spec["tattoo_color"] = Color(0.18, 0.45, 0.82)
	spec["hair_band_color"] = robe


static func _monk(spec: Dictionary, pal: Dictionary, lm: Dictionary) -> void:
	var t: Dictionary = lm["torso"]
	var robe: Color = pal["robe"]
	var shirt: Color = pal["shirt"]
	var belt: float = t["belt"]
	spec["torso_bands"] = _bands([[belt - 0.01, robe, 0.006], [belt + 0.05, shirt, 0.012], [1.0, robe, 0.008]])
	spec["arm_bands"] = _bands([[0.97, robe, 0.006], [1.0, spec["skin"], 0.0]])
	spec["leg_bands"] = _bands([[0.96, robe.darkened(0.1), 0.006], [1.0, spec["skin"], 0.0]])
	spec["foot_color"] = pal["shoe"]
	spec["foot_style"] = "shoe"
	spec["torso_bulk"] = {"waist": 0.01, "hip": 0.004}
	var pieces: Array = spec["pieces"]
	pieces.append({"type": "skirt", "top": belt + 0.05, "hem": 0.035, "flare": 1.5, "color": robe, "trim": shirt, "trim_w": 0.08})
	pieces.append({"type": "sleeve", "from": 0.45, "extend": 0.02, "flare": 0.07, "color": robe, "trim": shirt})
	pieces.append({"type": "cape", "color": shirt, "length": 0.3, "top": 0.95, "width": 1.05})
	pieces.append({"type": "beads", "color": Color(0.5, 0.28, 0.15), "big_color": Color(0.25, 0.5, 0.8), "count": 18})
	pieces.append({"type": "knot", "t": belt + 0.025, "a": 0.32, "color": shirt})
	spec["arrow_tattoo"] = spec["hair_style"] == "bald"
	spec["tattoo_color"] = Color(0.18, 0.45, 0.82)


static func _water(spec: Dictionary, pal: Dictionary, lm: Dictionary, female: bool, preset: StringName) -> void:
	var t: Dictionary = lm["torso"]
	var a: Dictionary = lm["arm"]
	var l: Dictionary = lm["leg"]
	var parka: Color = pal["parka"]
	var pants: Color = pal["pants"]
	var trim: Color = pal["trim"]
	var boot: Color = pal["boot"]
	var belt: float = t["belt"]
	var warrior := preset == &"water_warrior"
	spec["torso_bands"] = _bands([[belt - 0.02, pants, 0.006], [belt + 0.035, Color(0.24, 0.19, 0.17), 0.018], [1.0, parka, 0.015]])
	spec["arm_bands"] = _bands([[0.9, parka, 0.011], [1.0, spec["skin"], 0.0]])
	spec["leg_bands"] = _bands([[l["knee"] + 0.06, pants, 0.007], [1.0, boot, 0.012]])
	spec["foot_color"] = boot
	spec["foot_style"] = "boot"
	spec["torso_bulk"] = {"chest": 0.004, "waist": 0.01, "hip": 0.006, "shoulder": 0.004}
	spec["arm_bulk"] = 0.004
	var pieces: Array = spec["pieces"]
	var hem: float = 0.27 if female else 0.4
	pieces.append({"type": "skirt", "top": belt + 0.035, "hem": hem, "flare": 1.22 if female else 1.15, "color": parka, "trim": C_WHITE_FUR if not warrior else trim, "trim_w": 0.16, "inflate": 0.012})
	pieces.append({"type": "ring", "part": "torso", "t": 0.975, "width": 0.07, "thick": 0.02, "fur": true, "color": C_WHITE_FUR})
	pieces.append({"type": "hood_back", "color": parka.darkened(0.1)})
	pieces.append({"type": "ring", "part": "arm", "t": 0.88, "width": 0.06, "thick": 0.012, "fur": true, "color": C_WHITE_FUR})
	pieces.append({"type": "ring", "part": "leg", "t": l["knee"] + 0.08, "width": 0.05, "thick": 0.012, "fur": true, "color": C_WHITE_FUR.darkened(0.08)})
	pieces.append({"type": "strip", "part": "torso", "pts": [Vector2(belt + 0.04, 0.25), Vector2(0.93, 0.25)], "width": 0.016, "lift": 0.0175, "color": trim})
	pieces.append({"type": "strip", "part": "torso", "pts": [Vector2(belt + 0.06, 0.0), Vector2(belt + 0.06, 0.5), Vector2(belt + 0.06, 1.0)], "width": 0.008, "lift": 0.0175, "color": trim})
	if warrior:
		pieces.append({"type": "plate", "t0": t["waist"] - 0.05, "t1": t["armpit"] + 0.04, "a0": 0.04, "a1": 0.46, "color": pal["armor"], "trim": trim, "lift": 0.02})
		pieces.append({"type": "plate", "t0": t["waist"] - 0.05, "t1": t["armpit"] + 0.04, "a0": 0.54, "a1": 0.96, "color": pal["armor"], "trim": trim, "lift": 0.02})
		pieces.append({"type": "pads", "color": pal["armor"], "trim": trim, "layers": 2, "size": 1.0})
		pieces.append({"type": "helmet_wolf", "color": Color(0.88, 0.89, 0.92), "dark": Color(0.3, 0.33, 0.42)})
		spec["face_paint"] = {"style": "warrior", "color": Color(0.93, 0.94, 0.96)}
		spec["head_covered"] = true
	if female and not warrior:
		pieces.append({"type": "necklace", "color": Color(0.15, 0.24, 0.5), "pendant_color": Color(0.35, 0.62, 0.9)})
	spec["hair_band_color"] = Color(0.3, 0.22, 0.18)


static func _earth(spec: Dictionary, pal: Dictionary, lm: Dictionary, female: bool, preset: StringName, rng: RandomNumberGenerator) -> void:
	var t: Dictionary = lm["torso"]
	var a: Dictionary = lm["arm"]
	var l: Dictionary = lm["leg"]
	var tunic: Color = pal["tunic"]
	var under: Color = pal.get("under", Color(0.8, 0.7, 0.5))
	var pants: Color = pal["pants"]
	var trim: Color = pal["trim"]
	var sash: Color = pal.get("sash", trim)
	var belt: float = t["belt"]
	var soldier := preset == &"earth_soldier" or preset == &"guard"
	spec["torso_bands"] = _bands([[belt - 0.015, pants, 0.005], [belt + 0.05, sash, 0.011], [1.0, tunic, 0.007]])
	spec["arm_bands"] = _bands([[a["elbow"] + 0.08, tunic, 0.007], [0.93, under, 0.005], [1.0, spec["skin"], 0.0]])
	spec["leg_bands"] = _bands([[l["knee"] + 0.2, pants, 0.007], [1.0, under.darkened(0.15), 0.008]])
	spec["foot_color"] = pal["shoe"]
	spec["foot_style"] = "shoe"
	spec["torso_bulk"] = {"waist": 0.004}
	_vneck(spec, 0.8, 0.07, under, trim, 0.0105, 0.02)
	var pieces: Array = spec["pieces"]
	var hem: float = 0.1 if (female and not soldier) else 0.36
	pieces.append({"type": "skirt", "top": belt + 0.05, "hem": hem, "flare": 1.35 if hem < 0.2 else 1.18, "color": tunic, "trim": trim, "trim_w": 0.1})
	pieces.append({"type": "knot", "t": belt + 0.025, "a": 0.34, "color": sash})
	pieces.append({"type": "ring", "part": "arm", "t": a["elbow"] + 0.08, "width": 0.03, "thick": 0.004, "color": trim})
	if soldier:
		var armor: Color = pal["armor"]
		pieces.append({"type": "plate", "t0": t["waist"] - 0.06, "t1": t["armpit"] + 0.03, "a0": 0.06, "a1": 0.44, "color": armor, "trim": pal["trim"], "lift": 0.018})
		pieces.append({"type": "plate", "t0": t["waist"] - 0.06, "t1": t["armpit"] + 0.03, "a0": 0.56, "a1": 0.94, "color": armor, "trim": pal["trim"], "lift": 0.018})
		pieces.append({"type": "pads", "color": armor, "trim": pal["trim"], "layers": 2, "size": 1.0})
		pieces.append({"type": "ring", "part": "arm", "t": 0.82, "width": 0.2, "thick": 0.008, "color": armor})
		spec["leg_bands"] = _bands([[l["knee"] - 0.04, pants, 0.007], [1.0, pal["shoe"], 0.012]])
		spec["foot_style"] = "boot"
		if preset == &"guard":
			pieces.append({"type": "helmet_round", "color": armor, "trim": pal["trim"]})
		else:
			pieces.append({"type": "hat_cone", "radius": 0.135, "height": 0.055, "sit": 0.16, "color": armor.lightened(0.08), "under": armor.darkened(0.4), "band": armor.darkened(0.3), "rim": pal["trim"]})
	elif preset == &"villager_earth" and rng.randf() < 0.4 and not female:
		pieces.append({"type": "hat_cone", "radius": 0.15, "height": 0.07, "sit": 0.17, "color": Color(0.86, 0.76, 0.48), "under": Color(0.55, 0.45, 0.28), "band": Color(0.45, 0.32, 0.2)})
	spec["hair_band_color"] = trim.darkened(0.2)


static func _dai_li(spec: Dictionary, pal: Dictionary, lm: Dictionary) -> void:
	var t: Dictionary = lm["torso"]
	var robe: Color = pal["robe"]
	var trim: Color = pal["trim"]
	var belt: float = t["belt"]
	spec["torso_bands"] = _bands([[belt - 0.01, robe, 0.006], [belt + 0.05, pal["sash"], 0.012], [1.0, robe, 0.008]])
	spec["arm_bands"] = _bands([[0.96, robe, 0.006], [1.0, pal["stone"], 0.01]])
	spec["leg_bands"] = _bands([[1.0, trim, 0.008]])
	spec["foot_color"] = trim
	spec["foot_style"] = "boot"
	spec["hand_color"] = pal["stone"]
	spec["stone_gloves"] = true
	_vneck(spec, 0.78, 0.065, trim, trim, 0.0115, 0.025)
	var pieces: Array = spec["pieces"]
	pieces.append({"type": "skirt", "top": belt + 0.05, "hem": 0.04, "flare": 1.45, "color": robe, "trim": trim, "trim_w": 0.07, "inner": trim})
	pieces.append({"type": "sleeve", "from": 0.42, "extend": 0.015, "flare": 0.075, "color": robe, "trim": trim})
	pieces.append({"type": "hat_cone", "radius": 0.165, "height": 0.068, "sit": 0.18, "color": robe.lightened(0.05), "under": trim, "band": trim, "rim": trim, "ornament": Color(0.42, 0.66, 0.4)})
	spec["hair_band_color"] = trim


static func _fire(spec: Dictionary, pal: Dictionary, lm: Dictionary, female: bool, preset: StringName, rng: RandomNumberGenerator) -> void:
	var t: Dictionary = lm["torso"]
	var a: Dictionary = lm["arm"]
	var l: Dictionary = lm["leg"]
	var tunic: Color = pal["tunic"]
	var black: Color = pal.get("black", C_BLACK)
	var belt: float = t["belt"]
	var pieces: Array = spec["pieces"]
	if preset == &"fire_soldier":
		var armor: Color = pal["armor"]
		var metal: Color = pal["metal"]
		spec["torso_bands"] = _bands([[belt - 0.01, black, 0.005], [belt + 0.045, black.lightened(0.05), 0.012], [1.0, tunic.darkened(0.25), 0.007]])
		spec["arm_bands"] = _bands([[0.55, tunic.darkened(0.25), 0.007], [1.0, black, 0.006]])
		spec["leg_bands"] = _bands([[l["knee"] - 0.06, black, 0.006], [1.0, black.lightened(0.06), 0.012]])
		spec["foot_color"] = black
		spec["foot_style"] = "boot"
		spec["hand_color"] = black
		pieces.append({"type": "plate", "t0": t["waist"] - 0.07, "t1": t["armpit"] + 0.06, "a0": 0.05, "a1": 0.45, "color": armor, "trim": black, "lift": 0.019})
		pieces.append({"type": "plate", "t0": t["waist"] - 0.07, "t1": t["armpit"] + 0.06, "a0": 0.55, "a1": 0.95, "color": armor, "trim": black, "lift": 0.019})
		pieces.append({"type": "pads", "color": armor, "trim": black, "layers": 3, "size": 1.1})
		pieces.append({"type": "skirt", "top": belt + 0.045, "hem": 0.33, "flare": 1.2, "color": armor, "trim": black, "trim_w": 0.14, "a0": 0.06, "a1": 0.44, "band_top": black})
		pieces.append({"type": "skirt", "top": belt + 0.045, "hem": 0.33, "flare": 1.2, "color": armor, "trim": black, "trim_w": 0.14, "a0": 0.56, "a1": 0.94, "band_top": black})
		pieces.append({"type": "ring", "part": "arm", "t": 0.82, "width": 0.22, "thick": 0.008, "color": armor})
		pieces.append({"type": "helmet_fire", "color": armor.darkened(0.15), "mask": metal, "trim": black})
		spec["head_covered"] = true
		spec["face_hidden"] = true
		return
	var gold: Color = pal.get("gold", C_GOLD)
	var dark: Color = pal.get("dark", tunic.darkened(0.4))
	var villager := preset == &"villager_fire"
	if villager:
		var under: Color = pal["under"]
		spec["torso_bands"] = _bands([[belt - 0.01, pal["pants"], 0.005], [belt + 0.045, pal["sash"], 0.01], [1.0, tunic, 0.006]])
		spec["arm_bands"] = _bands([[a["elbow"] + 0.12, tunic, 0.006], [1.0, spec["skin"], 0.0]])
		spec["leg_bands"] = _bands([[0.9, pal["pants"], 0.006], [1.0, spec["skin"], 0.0]])
		spec["foot_color"] = pal["shoe"]
		spec["foot_style"] = "shoe"
		_vneck(spec, 0.8, 0.065, under, pal["trim"], 0.0095, 0.02)
		pieces.append({"type": "skirt", "top": belt + 0.045, "hem": 0.12 if female else 0.36, "flare": 1.3 if female else 1.15, "color": tunic, "trim": pal["trim"], "trim_w": 0.1})
		if rng.randf() < 0.35 and not female:
			pieces.append({"type": "hat_cone", "radius": 0.15, "height": 0.07, "sit": 0.17, "color": Color(0.84, 0.74, 0.46), "under": Color(0.5, 0.42, 0.26), "band": pal["trim"]})
		spec["hair_band_color"] = pal["trim"]
		return
	spec["torso_bands"] = _bands([[belt - 0.01, black, 0.005], [belt + 0.045, black.lightened(0.06), 0.011], [1.0, tunic, 0.007]])
	spec["arm_bands"] = _bands([[a["elbow"] - 0.02, tunic, 0.007], [1.0, black, 0.005]])
	spec["leg_bands"] = _bands([[l["knee"] - 0.06, black, 0.006], [1.0, black.lightened(0.04), 0.012]])
	spec["foot_color"] = black
	spec["foot_style"] = "boot"
	_vneck(spec, 0.8, 0.06, black, gold, 0.0095, 0.0)
	pieces.append({"type": "pads", "color": dark, "trim": gold, "layers": 2, "size": 0.95})
	pieces.append({"type": "skirt", "top": belt + 0.045, "hem": 0.2 if female else 0.27, "flare": 1.22, "color": tunic, "trim": dark, "trim_w": 0.12, "a0": 0.07, "a1": 0.43, "band_top": black})
	pieces.append({"type": "skirt", "top": belt + 0.045, "hem": 0.2 if female else 0.27, "flare": 1.22, "color": tunic, "trim": dark, "trim_w": 0.12, "a0": 0.57, "a1": 0.93, "band_top": black})
	pieces.append({"type": "ring", "part": "arm", "t": 0.8, "width": 0.24, "thick": 0.009, "color": dark})
	pieces.append({"type": "ring", "part": "arm", "t": 0.685, "width": 0.012, "thick": 0.011, "color": gold})
	pieces.append({"type": "strip", "part": "torso", "pts": [Vector2(belt + 0.025, 0.0), Vector2(belt + 0.025, 0.5), Vector2(belt + 0.025, 1.0)], "width": 0.008, "lift": 0.0125, "color": gold})
	if spec["hair_extras"].has("topknot"):
		spec["crown"] = true
		spec["crown_color"] = gold
	spec["hair_band_color"] = dark


static func _outlaw(spec: Dictionary, pal: Dictionary, lm: Dictionary, pirate: bool, rng: RandomNumberGenerator) -> void:
	var t: Dictionary = lm["torso"]
	var a: Dictionary = lm["arm"]
	var l: Dictionary = lm["leg"]
	var shirt: Color = pal["shirt"]
	var vest: Color = pal["vest"]
	var pants: Color = pal["pants"]
	var belt: float = t["belt"]
	var pieces: Array = spec["pieces"]
	if pirate:
		var st: Color = pal["stripe"]
		var steps: Array = [[belt - 0.01, pants, 0.006], [belt + 0.05, pal["sash"], 0.012]]
		var y := belt + 0.05
		var k := 0
		while y < 0.9:
			y = minf(y + 0.045, 0.9)
			steps.append([y, st if k % 2 == 0 else shirt, 0.006])
			k += 1
		steps.append([1.0, shirt, 0.006])
		spec["torso_bands"] = _bands(steps)
		pieces.append({"type": "headband", "color": pal["sash"], "phi": 1.02})
		pieces.append({"type": "knot", "t": belt + 0.025, "a": 0.08, "color": pal["sash"]})
	else:
		spec["torso_bands"] = _bands([[belt - 0.01, pants, 0.006], [belt + 0.035, Color(0.42, 0.3, 0.2), 0.01], [1.0, shirt, 0.006]])
		pieces.append({"type": "scarf_mask", "color": pal["scarf"]})
		if rng.randf() < 0.6:
			pieces.append({"type": "headband", "color": pal["scarf"].darkened(0.2), "phi": 1.1})
	spec["arm_bands"] = _bands([[a["elbow"] - 0.04, shirt, 0.006], [a["elbow"] + 0.02, shirt.darkened(0.1), 0.01], [0.78, spec["skin"], 0.0], [0.96, Color(0.72, 0.64, 0.5), 0.006], [1.0, spec["skin"], 0.0]])
	spec["leg_bands"] = _bands([[l["knee"] + 0.12, pants, 0.007], [1.0, pal["shoe"], 0.012]])
	spec["foot_color"] = pal["shoe"]
	spec["foot_style"] = "boot"
	pieces.append({"type": "plate", "t0": t["belt"] + 0.03, "t1": 0.93, "a0": 0.02, "a1": 0.2, "color": vest, "trim": vest.darkened(0.3), "lift": 0.012})
	pieces.append({"type": "plate", "t0": t["belt"] + 0.03, "t1": 0.93, "a0": 0.3, "a1": 0.98, "color": vest, "trim": vest.darkened(0.3), "lift": 0.012})
	spec["hair_band_color"] = vest


static func _merchant(spec: Dictionary, pal: Dictionary, lm: Dictionary, female: bool) -> void:
	var t: Dictionary = lm["torso"]
	var robe: Color = pal["robe"]
	var trim: Color = pal["trim"]
	var belt: float = t["belt"]
	spec["torso_bands"] = _bands([[belt - 0.01, robe, 0.006], [belt + 0.06, pal["sash"], 0.016], [1.0, robe, 0.01]])
	spec["arm_bands"] = _bands([[0.96, robe, 0.008], [1.0, spec["skin"], 0.0]])
	spec["leg_bands"] = _bands([[1.0, robe.darkened(0.3), 0.008]])
	spec["foot_color"] = Color(0.2, 0.15, 0.12)
	spec["foot_style"] = "shoe"
	spec["torso_bulk"] = {"waist": 0.02, "hip": 0.01, "chest": 0.006}
	_vneck(spec, 0.82, 0.06, pal["under"], trim, 0.014, 0.02)
	var pieces: Array = spec["pieces"]
	pieces.append({"type": "skirt", "top": belt + 0.06, "hem": 0.06, "flare": 1.45, "color": robe, "trim": trim, "trim_w": 0.08})
	pieces.append({"type": "sleeve", "from": 0.42, "extend": 0.02, "flare": 0.07, "color": robe, "trim": trim})
	if not female:
		pieces.append({"type": "hat_cone", "radius": 0.07, "height": 0.05, "sit": 0.12, "color": pal["hat"], "under": pal["hat"].darkened(0.4), "band": trim})
	spec["hair_band_color"] = trim
