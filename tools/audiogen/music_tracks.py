"""The eight looping music tracks, written with the compose.py engine.

All themes are original. They use Chinese pentatonic modes (gong/zhi/yu) with
occasional bian tones for colour, and an instrumentation of guzheng, pipa,
dizi, xiao, erhu, taiko/tanggu, muyu, gongs, bells, string pads and low brass.
Each piece ends on a turnaround into its first bar, and Score.render folds the
ringing tail onto the head, so every file loops seamlessly.
"""
from __future__ import annotations

from compose import Score
from registry import music


def kit(s: Score, *names: str, gain: float = 1.0) -> None:
	"""Declares common percussion instruments."""
	defs = {
		"odaiko": dict(kind="drum", pan=0.0, gain=0.9, send=0.22, params={"synth": "taiko", "size": "odaiko"}),
		"nagado": dict(kind="drum", pan=-0.25, gain=0.6, send=0.2, params={"synth": "taiko", "size": "nagado"}),
		"shime": dict(kind="drum", pan=0.3, gain=0.22, send=0.12, params={"synth": "taiko", "size": "shime"}),
		"ka": dict(kind="drum", pan=0.35, gain=0.18, send=0.12, params={"synth": "taiko", "size": "rim"}),
		"frame": dict(kind="drum", pan=-0.2, gain=0.45, send=0.25, params={"synth": "frame"}),
		"tsuzumi": dict(kind="drum", pan=0.4, gain=0.35, send=0.3, params={"synth": "tsuzumi"}),
		"muyu_hi": dict(kind="drum", pan=0.45, gain=0.22, send=0.2, params={"synth": "woodblock", "freq": 920.0}),
		"muyu_lo": dict(kind="drum", pan=-0.4, gain=0.24, send=0.2, params={"synth": "woodblock", "freq": 610.0}),
		"ban": dict(kind="drum", pan=0.15, gain=0.2, send=0.2, params={"synth": "clapper"}),
		"cymbal": dict(kind="drum", pan=0.3, gain=0.18, send=0.3, params={"synth": "cymbal", "t60": 1.4}),
		"tamtam": dict(kind="fx", pan=0.0, gain=0.45, send=0.4, params={"synth": "tamtam", "dur": 7.0}),
		"daluo": dict(kind="fx", pan=-0.2, gain=0.3, send=0.35, params={"synth": "opera_low", "dur": 3.0}),
		"xiaoluo": dict(kind="fx", pan=0.25, gain=0.2, send=0.3, params={"synth": "opera_high"}),
		"bowl": dict(kind="fx", pan=-0.3, gain=0.25, send=0.5, params={"synth": "bowl", "dur": 7.0}),
		"chime": dict(kind="fx", pan=0.5, gain=0.12, send=0.5, params={"synth": "bell", "type": "chime", "dur": 3.0}),
		"glass": dict(kind="fx", pan=-0.45, gain=0.14, send=0.55, params={"synth": "bell", "type": "glass", "dur": 3.5}),
		"temple_bell": dict(kind="fx", pan=0.1, gain=0.3, send=0.5, params={"synth": "bell", "type": "temple", "dur": 7.0}),
	}
	for n in names:
		d = dict(defs[n])
		d["gain"] *= gain
		s.inst(n, **d)


def strings(s: Score, gain: float = 0.3, bright: float = 1600.0, send: float = 0.4) -> None:
	"""A wide string section: two pads panned left/right."""
	s.inst("str_l", "pad", pan=-0.55, gain=gain, send=send, params={"bright": bright, "attack": 1.2, "release": 1.5})
	s.inst("str_r", "pad", pan=0.55, gain=gain, send=send, params={"bright": bright * 1.1, "attack": 1.4, "release": 1.5})


def pads(s: Score, bar: int, nbars: int, vel: float = 0.5, center: int | None = None, spread: bool = False) -> None:
	s.pad("str_l", bar, nbars, vel, center, spread)
	s.pad("str_r", bar, nbars, vel * 0.9, (center or s.key + 2) + 5, spread)


# ---------------------------------------------------------------------------
# 1. Main menu: "The Four Nations" (epic, hopeful) - D gong mode, 76 bpm
# ---------------------------------------------------------------------------

@music("music_menu")
def music_menu(rng):
	s = Score(76, 38, key=62)
	s.reverb.update(seconds=3.6, t60_low=3.0, t60_high=1.6, wet=0.3)
	s.inst("gz", "pluck", pan=-0.35, gain=0.5, send=0.3, body="guzheng")
	s.inst("gz_lead", "pluck", pan=-0.1, gain=0.62, send=0.32, body="guzheng", params={"ring": 2.2})
	s.inst("dizi", "phrase", pan=0.18, gain=0.62, send=0.35, params={"voice": "dizi"})
	s.inst("erhu", "phrase", pan=-0.15, gain=0.72, send=0.33, params={"voice": "erhu"})
	s.inst("pipa", "pluck", pan=0.4, gain=0.32, send=0.25, body="pipa", params={"synth": "pipa"})
	s.inst("choir", "choir", pan=0.0, gain=0.3, send=0.55, params={"vowel": "a"})
	s.inst("cello", "pad", pan=-0.1, gain=0.42, send=0.25, params={"bright": 700.0, "attack": 0.6})
	s.inst("bass", "pluck", pan=0.0, gain=0.45, send=0.15, body="bass", params={"synth": "bass", "ring": 0.8})
	strings(s, 0.28)
	kit(s, "odaiko", "nagado", "shime", "tamtam", "cymbal", "chime")
	# Harmony
	s.progression(0, "1add9 1add9 4add9/1 5sus4")
	s.progression(4, "1add9 6m7 4add9 5sus4 1add9 6m7 4add9:5sus4 1add9")
	s.progression(12, "4add9 5sus4 3m7 6m7 4add9 5 6m7:5sus4 1add9")
	s.progression(20, "1add9 6m7 4add9 5sus4 1add9 6m7 4add9:5sus4 1add9")
	s.progression(28, "6m7 4add9 6m7 5sus4 4add9 5sus4")
	s.progression(34, "4add9 1add9/3 4add9 5sus4")
	theme_a = "5, 1 2 3_ 5_ | 6- 5 3 | 2 3_ 5_ 1 6, | 2--- | 5, 1 2 3_ 5_ | 6- 1' 2' | 3'_ 2'_ 1' 6 5_ 6_ | 1'--- |"
	theme_b = "6 1' 2'- | 3'. 2'_ 1' 2' | 3'- 5' 3' | 2'- 1' 6 | 6 1' 2' 3'_ 5'_ | 6'- 5' 3' | 2'. 3'_ 2' 1'_ 6_ | 1'--- |"
	# Intro (0-3): gong, glissando, the theme's head stated slowly.
	s.hit("tamtam", 0, 0, 0.8)
	s.gliss("gz", 0, 0, [1, 2, 3, 5, 6, 8, 9, 10, 12, 13], 1.5, 0.55, octave=-1)
	s.melody("dizi", 0, "5,-- 1 | 2--- | 3- 5- | 2--- |", octave=1, vel=0.6)
	pads(s, 0, 4, 0.4)
	s.pad("cello", 0, 4, 0.5, center=s.key - 22)
	s.drums("odaiko", 0, 4, "X... .... .... .... ", 0.7)
	s.drums("shime", 3, 1, "o.o. o.o. x.x. xxxx", 0.6, ramp=(0.5, 1.0))
	# A (4-11): theme on dizi over guzheng arpeggios.
	s.melody("dizi", 4, theme_a, octave=1, vel=0.8)
	s.arp("gz", 4, 8, [0, 1, 2, 11, 12, 11, 2, 1], 0.5, 0.5, center=s.key - 5)
	pads(s, 4, 8, 0.45)
	s.bass("bass", 4, 8, [(0, 1.5), (2.5, 1.5)], 0.6)
	s.drums("odaiko", 4, 8, "X... .... x... .... ", 0.75)
	s.drums("shime", 8, 4, "o.o. o.o. o.o. o.o. ", 0.4)
	# B (12-19): broader; erhu + dizi, choir, full taiko.
	s.hit("tamtam", 12, 0, 0.6)
	s.hit("cymbal", 12, 0, 0.6)
	s.melody("erhu", 12, theme_b, octave=0, vel=0.85)
	s.melody("dizi", 16, "6 1' 2' 3'_ 5'_ | 6'- 5' 3' | 2'. 3'_ 2' 1'_ 6_ | 1'--- |", octave=1, vel=0.6)
	s.pad("choir", 12, 8, 0.6, center=s.key + 3)
	pads(s, 12, 8, 0.55, spread=True)
	s.pad("cello", 12, 8, 0.6, center=s.key - 22)
	s.arp("gz", 12, 8, [0, 1, 2, 11, 12, 11, 2, 1], 0.5, 0.45, center=s.key)
	s.bass("bass", 12, 8, [(0, 1.0), (1.5, 0.5), (2.0, 1.0), (3.0, 1.0)], 0.7, fifth_on=(2,))
	s.drums("odaiko", 12, 8, "X... .... X..x .... ", 0.85)
	s.drums("nagado", 12, 8, "..x. ..x. ..x. x.x. ", 0.6)
	s.drums("shime", 12, 8, "o.o. x.o. o.o. x.oo ", 0.5)
	# A' (20-27): theme on erhu, dizi descant, pipa tremolo colour.
	s.hit("cymbal", 20, 0, 0.5)
	s.melody("erhu", 20, theme_a, octave=1, vel=0.8)
	s.melody("dizi", 20, "5--- | 3--- | 2--- | 1--- | 3--- | 5--- | 6- 5- | 3--- |", octave=1, vel=0.45)
	s.melody("pipa", 24, "3t--- | 1't--- | 6t- 5t- | 1't--- |", octave=1, vel=0.4)
	s.arp("gz", 20, 8, [0, 2, 11, 2, 12, 2, 11, 2], 0.5, 0.45, center=s.key - 5)
	pads(s, 20, 8, 0.5)
	s.bass("bass", 20, 8, [(0, 1.5), (2.5, 1.5)], 0.65)
	s.drums("odaiko", 20, 8, "X... ..x. X... .... ", 0.8)
	s.drums("nagado", 20, 8, ".... x... .... x.x. ", 0.55)
	s.drums("shime", 20, 8, "o.o. o.o. o.o. o.o. ", 0.4)
	# Interlude (28-33): guzheng solo with left-hand bends, tam-tam bloom.
	s.hit("tamtam", 28, 0, 0.5)
	s.melody("gz_lead", 28, "6, 1 /2 3 | 2- 1 6, | 1 2 3 5~ | 2--- | 5 6 5 3 | \\2--- |", octave=1, vel=0.75)
	s.pad("cello", 28, 6, 0.45, center=s.key - 22)
	pads(s, 28, 6, 0.35)
	s.drums("odaiko", 28, 6, "X... .... .... .... ", 0.55)
	# Turnaround (34-37): rebuild into the intro.
	s.melody("dizi", 34, "5- 6- | 1'--- | 6- 5- | 2--- |", octave=1, vel=0.65)
	s.arp("gz", 34, 4, [0, 1, 2, 11, 12, 11, 2, 1], 0.5, 0.5, center=s.key - 5)
	pads(s, 34, 4, 0.5)
	s.bass("bass", 34, 4, [(0, 2.0), (2, 2.0)], 0.6)
	s.drums("odaiko", 34, 4, "X... .... x... .... ", 0.7)
	s.drums("shime", 36, 2, "o.o. o.o. x.x. xxxx ", 0.6, ramp=(0.4, 1.0))
	s.drums("nagado", 37, 1, ".... .... x.x. XXXX ", 0.7)
	return s.render(rng)


# ---------------------------------------------------------------------------
# 2. Element select: reflective, building - A major / F# yu mode, 72 bpm
# ---------------------------------------------------------------------------

@music("music_select")
def music_select(rng):
	s = Score(72, 28, key=57)
	s.reverb.update(seconds=3.4, t60_low=3.0, t60_high=1.5, wet=0.32)
	s.inst("gz", "pluck", pan=-0.3, gain=0.55, send=0.32, body="guzheng")
	s.inst("harp", "pluck", pan=0.45, gain=0.35, send=0.4, body="harp", params={"synth": "harp"})
	s.inst("xiao", "phrase", pan=0.15, gain=0.75, send=0.38, params={"voice": "xiao"})
	s.inst("erhu", "phrase", pan=-0.12, gain=0.7, send=0.32, params={"voice": "erhu"})
	s.inst("cello", "pad", pan=0.0, gain=0.4, send=0.3, params={"bright": 650.0, "attack": 1.0})
	strings(s, 0.26, 1500.0)
	kit(s, "frame", "bowl", "chime", "tamtam", "nagado")
	s.progression(0, "6m7 4add9 1add9 5sus4", bars_each=2)
	s.progression(8, "6m7 4add9 1add9 6m7 3m7 1add9 5sus4 6m7")
	s.progression(16, "6m7 4add9 1add9 6m7 3m7 1add9 5sus4 6m7")
	s.progression(24, "4add9 1add9 5sus4 5sus4")
	theme = "6,- 1 2 | 3- 2 1 | 2 3_ 5_ 3 2 | 1- 6,- | 3- 5 6 | 5- 3 2 | 1 2_ 3_ 2 1 | 6,--- |"
	arp = [0, 1, 2, 11, 12, 11, 2, 1]
	# S1 (0-7): guzheng alone, pad and bowl entering.
	s.hit("bowl", 0, 0, 0.6)
	s.arp("gz", 0, 8, arp, 0.5, 0.5, center=s.key + 2)
	pads(s, 4, 4, 0.35)
	s.hit("chime", 6, 2, 0.4, midi=s.key + 21)
	# S2 (8-15): xiao melody.
	s.melody("xiao", 8, theme, octave=1, vel=0.75)
	s.arp("gz", 8, 8, arp, 0.5, 0.45, center=s.key + 2)
	pads(s, 8, 8, 0.4)
	s.pad("cello", 8, 8, 0.45, center=s.key - 14)
	# S3 (16-23): erhu takes the theme, xiao harmony, heartbeat drum, harp.
	s.hit("tamtam", 16, 0, 0.45)
	s.melody("erhu", 16, theme, octave=1, vel=0.8)
	s.melody("xiao", 16, "1--- | 5--- | 3--- | 3--- | 5--- | 3--- | 5- 4- | 3--- |", octave=1, vel=0.45)
	s.arp("harp", 16, 8, [0, 1, 2, 11, 12, 21, 12, 11], 0.5, 0.45, center=s.key + 7)
	s.arp("gz", 16, 8, [0, 2, 11, 2], 1.0, 0.4, center=s.key - 3)
	pads(s, 16, 8, 0.55, spread=True)
	s.pad("cello", 16, 8, 0.55, center=s.key - 14)
	s.drums("frame", 16, 8, "X... .... x... .... ", 0.6, ramp=(0.5, 1.0))
	s.drums("nagado", 20, 4, "X... .... .... ..x. ", 0.5)
	# S4 (24-27): wind down into the loop.
	s.hit("bowl", 24, 0, 0.5)
	s.arp("gz", 24, 4, arp, 0.5, 0.45, center=s.key + 2)
	pads(s, 24, 4, 0.4)
	s.melody("xiao", 24, "3- 2 1 | 2--- | 1- 2- | 3--- |", octave=1, vel=0.55)
	return s.render(rng)


# ---------------------------------------------------------------------------
# 3. Northern Water Tribe: icy, flowing, ethereal - E yu mode, 3/4, 66 bpm
# ---------------------------------------------------------------------------

@music("music_water_tribe")
def music_water_tribe(rng):
	s = Score(66, 40, key=67, beats_per_bar=3)
	s.reverb.update(seconds=4.5, t60_low=4.0, t60_high=2.6, brightness=9000.0, wet=0.38, predelay=0.04)
	s.inst("harp", "pluck", pan=0.35, gain=0.45, send=0.45, body="harp", params={"synth": "harp"})
	s.inst("xiao", "phrase", pan=-0.1, gain=0.8, send=0.45, params={"voice": "xiao"})
	s.inst("choir", "choir", pan=0.0, gain=0.32, send=0.6, params={"vowel": "u", "attack": 2.0})
	s.inst("drone", "fx", pan=0.0, gain=0.18, send=0.3, params={"synth": "drone", "type": "fifth"})
	s.inst("wind", "fx", pan=0.0, gain=0.07, send=0.3, params={"synth": "wind", "base": 700.0})
	strings(s, 0.22, 2600.0, 0.55)
	kit(s, "glass", "frame", "tsuzumi", "bowl")
	s.progression(0, "6madd9 6madd9 4maj7 4maj7 2m7 2m7 5sus2 5sus2")
	s.progression(8, "6madd9 6madd9 4maj7 4maj7 1 1 2m7 2m7 6madd9 6madd9 4maj7 4maj7 5sus2 2m7 6madd9 6madd9")
	s.progression(24, "6madd9 4maj7 1 5sus2 6madd9 4maj7 2m7 6madd9")
	s.progression(32, "4maj7 1 2m7 6madd9")
	s.progression(36, "4maj7 4maj7 5sus2 5sus2")
	flow = [0, 1, 2, 11, 12, 11]
	a = "6,- 1 | 3- 2 | 1 6, 5, | 6,-- | 3- 5 | 6 5 3 | 2 3 1 | 2-- |"
	a2 = "6,- 1 | 3- 5 | 6_ 5_ 3 2 | 3-- | 5 3 2 | 1 2 6, | 1_ 2_ 1 6, | 6,-- |"
	s.hit("drone", 0, 0, 0.6, midi=s.key - 27, dur=40 * 3)
	s.hit("wind", 0, 0, 0.8, dur=40 * 3)
	# Intro (0-7)
	s.hit("bowl", 0, 0, 0.5)
	s.arp("harp", 0, 8, flow, 0.5, 0.4, center=s.key - 3)
	pads(s, 2, 6, 0.3, center=s.key + 7)
	for b, m in ((1, 88), (3, 83), (5, 86), (7, 81)):
		s.hit("glass", b, 1, 0.45, midi=m)
	# A (8-23): xiao melody.
	s.melody("xiao", 8, a, octave=0, vel=0.75)
	s.melody("xiao", 16, a2, octave=0, vel=0.75)
	s.arp("harp", 8, 16, flow, 0.5, 0.38, center=s.key - 3)
	pads(s, 8, 16, 0.32, center=s.key + 7)
	s.drums("frame", 8, 16, "X... .... x... ", 0.35)
	# B (24-31): glass bells carry the theme, choir.
	s.melody("glass", 24, "6- 1' | 3'-- | 2' 1' 6 | 6-- | 3'- 5' | 6'-- | 5' 3' 2' | 3'-- |", octave=0, vel=0.55)
	s.pad("choir", 24, 8, 0.6, center=s.key - 2)
	s.arp("harp", 24, 8, [0, 2, 11, 12, 11, 2], 0.5, 0.35, center=s.key - 3)
	pads(s, 24, 8, 0.28, center=s.key + 7)
	s.drums("tsuzumi", 24, 8, "X... .... .... ", 0.4)
	# C (32-35): xiao returns briefly.
	s.melody("xiao", 32, "5 6 5 | 3-- | 2 3 1 | 6,-- |", octave=0, vel=0.7)
	s.arp("harp", 32, 4, flow, 0.5, 0.36, center=s.key - 3)
	pads(s, 32, 4, 0.3, center=s.key + 7)
	s.drums("frame", 32, 4, "X... .... x... ", 0.3)
	# Outro (36-39)
	s.hit("bowl", 36, 0, 0.45)
	s.arp("harp", 36, 4, flow, 0.5, 0.33, center=s.key - 3)
	pads(s, 36, 4, 0.28, center=s.key + 7)
	s.hit("glass", 37, 1, 0.4, midi=86)
	s.hit("glass", 39, 0, 0.35, midi=83)
	return s.render(rng, tail=9.0)


# ---------------------------------------------------------------------------
# 4. Earth Kingdom: grounded, stately, wooden percussion - G gong mode, 84 bpm
# ---------------------------------------------------------------------------

@music("music_earth_kingdom")
def music_earth_kingdom(rng):
	s = Score(84, 40, key=55)
	s.reverb.update(seconds=2.6, t60_low=2.2, t60_high=1.1, brightness=5500.0, wet=0.26)
	s.inst("gz", "pluck", pan=-0.3, gain=0.6, send=0.28, body="guzheng", params={"ring": 2.0})
	s.inst("gz_arp", "pluck", pan=-0.45, gain=0.38, send=0.25, body="guzheng")
	s.inst("erhu", "phrase", pan=0.15, gain=0.75, send=0.3, params={"voice": "erhu"})
	s.inst("dizi", "phrase", pan=0.3, gain=0.5, send=0.3, params={"voice": "dizi"})
	s.inst("pipa", "pluck", pan=0.4, gain=0.35, send=0.22, body="pipa", params={"synth": "pipa"})
	s.inst("bass", "pluck", pan=0.0, gain=0.5, send=0.12, body="bass", params={"synth": "bass", "ring": 0.6})
	s.inst("cello", "pad", pan=0.0, gain=0.4, send=0.25, params={"bright": 700.0, "attack": 0.5})
	strings(s, 0.22, 1400.0)
	kit(s, "muyu_hi", "muyu_lo", "ban", "nagado", "odaiko", "daluo", "xiaoluo", "frame")
	s.progression(0, "1 1 4 5")
	s.progression(4, "1 6m 2m7 6m 1 4 5sus4:5 1")
	s.progression(12, "1 6m 2m7 6m 1 4 5sus4:5 1")
	s.progression(20, "4 5 3m7 6m 2m7 5sus4 1 1")
	s.progression(28, "6m 6m 4 5")
	s.progression(32, "1 6m 2m7 6m 1 4 5sus4:5 1")
	a = "1. 2_ 3 5 | 6 5 3- | 2. 3_ 5 3 | 2 1 6,- | 1. 2_ 3 5 | 6 1' 6 5 | 3 5 2 3 | 1--- |"
	b = "6 1' 2' 3' | 2'- 1' 6 | 3'- 5' 3' | 2'--- | 1' 2' 6 5 | 3 5 6- | 5 3 2 1 | 1--- |"
	wood = "x.x. x.x. x.x. x.x. "
	# Intro (0-3)
	s.hit("daluo", 0, 0, 0.8)
	s.drums("nagado", 0, 4, "X... .... X... ..x. ", 0.7)
	s.drums("muyu_hi", 0, 4, wood, 0.6)
	s.melody("pipa", 0, "1t--- | 5t--- | 6t--- | 5t--- |", octave=1, vel=0.45)
	s.pad("cello", 0, 4, 0.5, center=s.key - 12)
	# A (4-11): guzheng theme.
	s.hit("xiaoluo", 4, 0, 0.6)
	s.melody("gz", 4, a, octave=1, vel=0.8)
	s.bass("bass", 4, 8, [(0, 1.0), (2.0, 1.0)], 0.65, fifth_on=(1,))
	s.drums("muyu_lo", 4, 8, "x... x... x... x... ", 0.6)
	s.drums("muyu_hi", 4, 8, "..x. ..x. ..x. ..xx ", 0.5)
	s.drums("ban", 4, 8, "X... .... .... .... ", 0.7)
	s.drums("nagado", 4, 8, "X... .... .... .... ", 0.55)
	pads(s, 4, 8, 0.3)
	# A' (12-19): erhu theme, guzheng arpeggios, pipa off-beats.
	s.hit("daluo", 12, 0, 0.55)
	s.melody("erhu", 12, a, octave=1, vel=0.8)
	s.arp("gz_arp", 12, 8, [0, 1, 2, 11, 2, 1], 0.5, 0.45, center=s.key + 2)
	s.arp("pipa", 12, 8, [None, 0, None, 1, None, 2, None, 1], 0.5, 0.35, center=s.key + 9)
	s.bass("bass", 12, 8, [(0, 1.0), (1.5, 0.5), (2.0, 1.0)], 0.65, fifth_on=(2,))
	s.drums("muyu_lo", 12, 8, "x... x... x... x... ", 0.55)
	s.drums("muyu_hi", 12, 8, "..x. ..x. ..x. .xx. ", 0.5)
	s.drums("ban", 12, 8, "X... .... X... .... ", 0.6)
	s.drums("nagado", 12, 8, "X... ..x. .... x... ", 0.6)
	pads(s, 12, 8, 0.35)
	# B (20-27): lyrical, erhu low + dizi joins.
	s.hit("daluo", 20, 0, 0.5)
	s.melody("erhu", 20, b, octave=0, vel=0.85)
	s.melody("dizi", 24, "1' 2' 6 5 | 3 5 6- | 5 3 2 1 | 1--- |", octave=1, vel=0.6)
	s.arp("gz_arp", 20, 8, [0, 1, 2, 11, 12, 11, 2, 1], 0.5, 0.42, center=s.key + 2)
	pads(s, 20, 8, 0.45, spread=True)
	s.pad("cello", 20, 8, 0.55, center=s.key - 12)
	s.bass("bass", 20, 8, [(0, 2.0), (2.0, 2.0)], 0.6)
	s.drums("odaiko", 20, 8, "X... .... .... .... ", 0.6)
	s.drums("muyu_lo", 20, 8, "x... .... x... .... ", 0.45)
	# Bridge (28-31): percussion feature.
	s.hit("daluo", 28, 0, 0.7)
	s.drums("nagado", 28, 4, "X..x ..x. X.x. x.x. ", 0.7)
	s.drums("frame", 28, 4, "..x. x..x ..x. .xx. ", 0.6)
	s.drums("muyu_hi", 28, 4, "x.xx x.x. x.xx x.x. ", 0.5)
	s.drums("muyu_lo", 28, 4, "x... .x.. x... .x.. ", 0.55)
	s.drums("ban", 28, 4, "X... .... X... X... ", 0.6)
	s.melody("pipa", 28, "6t--- | 6t--- | 4t--- | 5t--- |", octave=1, vel=0.45)
	s.pad("cello", 28, 4, 0.5, center=s.key - 12)
	s.hit("xiaoluo", 31, 3, 0.6)
	# A'' (32-39): guzheng + dizi in octaves, full ensemble.
	s.hit("daluo", 32, 0, 0.6)
	s.melody("gz", 32, a, octave=1, vel=0.8)
	s.melody("dizi", 32, a, octave=2, vel=0.5)
	s.arp("pipa", 32, 8, [None, 0, None, 1, None, 2, None, 1], 0.5, 0.32, center=s.key + 9)
	s.bass("bass", 32, 8, [(0, 1.0), (1.5, 0.5), (2.0, 1.0)], 0.65, fifth_on=(2,))
	pads(s, 32, 8, 0.4)
	s.drums("muyu_lo", 32, 8, "x... x... x... x... ", 0.55)
	s.drums("muyu_hi", 32, 8, "..x. ..x. ..x. ..xx ", 0.5)
	s.drums("ban", 32, 8, "X... .... X... .... ", 0.6)
	s.drums("nagado", 32, 8, "X... ..x. .... x... ", 0.6)
	return s.render(rng)


# ---------------------------------------------------------------------------
# 5. Fire Nation: martial, intense - D minor (F-do jianpu, b2/Eb colour), 96 bpm
# ---------------------------------------------------------------------------

@music("music_fire_nation")
def music_fire_nation(rng):
	s = Score(96, 44, key=53)
	s.reverb.update(seconds=2.4, t60_low=2.0, t60_high=0.9, brightness=5000.0, wet=0.24)
	s.inst("brass", "brass", pan=-0.1, gain=0.42, send=0.25)
	s.inst("brass2", "brass", pan=0.25, gain=0.3, send=0.25)
	s.inst("erhu", "phrase", pan=0.12, gain=0.78, send=0.28, params={"voice": "erhu"})
	s.inst("pipa", "pluck", pan=0.4, gain=0.36, send=0.22, body="pipa", params={"synth": "pipa"})
	s.inst("ost", "stacc", pan=-0.3, gain=0.42, send=0.18, params={"len": 0.14})
	s.inst("choir", "choir", pan=0.0, gain=0.3, send=0.5, params={"vowel": "o"})
	s.inst("cello", "pad", pan=0.0, gain=0.45, send=0.2, params={"bright": 600.0, "attack": 0.4})
	strings(s, 0.2, 1300.0)
	kit(s, "odaiko", "nagado", "shime", "ka", "tamtam", "cymbal")
	s.progression(0, "6m5 6m5 6m5 6m5")
	s.progression(4, "6m5 6m5 4 b7 6m5 6m5 4 5")
	s.progression(12, "6m5 4 b7 6m5 6m5 5 4 6m5")
	s.progression(20, "4 5 6m5 6m5 4 5 b7 b7")
	s.progression(28, "6m5 6m5 6m5 6m5")
	s.progression(32, "6m5 4 b7 6m5 6m5 5 4 6m5")
	s.progression(40, "6m5 b7 4 5")
	motif = "6- 6_ 1'_ 2' | 1'- b7 6 | 6- 6_ 1'_ 3' | 2'- 1' b7 |"
	erhu_a = "6 6_ 1'_ 2' 3' | 5'- 3' 2' | 1'_ b7_ 6 5 6 | 6--- | 6 6_ 1'_ 2' 3' | 5' 6' 5' 3' | 2'_ 3'_ 2' 1' 6 | 6--- |"
	erhu_b = "3'- 2' 1' | 2'- 3' 5' | 6'--- | 5'_ 6'_ 5' 3'- | 3'- 2' 1' | 2' 3' 5' 6' | b7'--- | 6'--- |"
	ostinato = [0, 0, 10, 0, 1, 0, 10, 1]
	groove_o = "X... ..X. ..X. .... "
	groove_n = ".... x... .... x.x. "
	groove_s = "o.x. o.x. o.x. oxxo "
	# Intro (0-3)
	s.hit("tamtam", 0, 0, 0.75)
	s.melody("brass", 0, "6--- | 6--- | 5- 6- | 6--- |", octave=-1, vel=0.7)
	s.drums("odaiko", 0, 4, "X... .... X... .... ", 0.85)
	s.drums("ka", 2, 2, "..x. ..x. ..x. x.x. ", 0.6)
	s.pad("cello", 0, 4, 0.6, center=s.key - 17)
	# A (4-11): brass motif over string ostinato and taiko groove.
	s.melody("brass", 4, motif + " " + motif, octave=-1, vel=0.8)
	s.arp("ost", 4, 8, ostinato, 0.5, 0.75, center=s.key - 3)
	s.drums("odaiko", 4, 8, groove_o, 0.85)
	s.drums("nagado", 4, 8, groove_n, 0.7)
	s.drums("shime", 4, 8, groove_s, 0.5)
	s.pad("cello", 4, 8, 0.5, center=s.key - 17)
	# A' (12-19): erhu takes the lead.
	s.hit("cymbal", 12, 0, 0.6)
	s.melody("erhu", 12, erhu_a, octave=1, vel=0.85)
	s.melody("brass", 12, "6--- | 4--- | b7--- | 6--- | 6--- | 5--- | 4--- | 6--- |", octave=-1, vel=0.55)
	s.arp("ost", 12, 8, ostinato, 0.5, 0.75, center=s.key - 3)
	s.drums("odaiko", 12, 8, groove_o, 0.85)
	s.drums("nagado", 12, 8, groove_n, 0.7)
	s.drums("shime", 12, 8, groove_s, 0.55)
	s.drums("ka", 12, 8, "..x. ..x. ..x. ..x. ", 0.4)
	pads(s, 12, 8, 0.35)
	# B (20-27): pipa tremolo, choir, soaring erhu and brass counterline.
	s.hit("tamtam", 20, 0, 0.6)
	s.hit("cymbal", 20, 0, 0.6)
	s.melody("erhu", 20, erhu_b, octave=1, vel=0.9)
	s.melody("brass2", 20, "4--- | 5--- | 6- 5- | 3--- | 4--- | 5--- | b7- 4- | b7--- |", octave=-1, vel=0.6)
	s.melody("pipa", 20, "1't--- | 2't--- | 3't--- | 3't--- | 1't--- | 2't--- | b7t--- | b7t--- |", octave=1, vel=0.4)
	s.pad("choir", 20, 8, 0.6, center=s.key + 7)
	pads(s, 20, 8, 0.45, spread=True)
	s.arp("ost", 20, 8, ostinato, 0.5, 0.7, center=s.key - 3)
	s.drums("odaiko", 20, 8, "X..X ..X. X... X.X. ", 0.85)
	s.drums("nagado", 20, 8, "..x. x... ..x. x.xx ", 0.7)
	s.drums("shime", 20, 8, "x.x. x.x. x.x. xxxx ", 0.5)
	# Breakdown (28-31): taiko feature.
	s.hit("tamtam", 28, 0, 0.5)
	s.drums("odaiko", 28, 4, "X... .X.. X... X... ", 0.9)
	s.drums("nagado", 28, 4, "..xx x..x ..x. xxxx ", 0.75, ramp=(0.6, 1.0))
	s.drums("shime", 28, 4, "xxxx xxxx xxxx xxxx ", 0.45, ramp=(0.4, 1.0))
	s.drums("ka", 28, 4, "x... x... x... x... ", 0.6)
	s.pad("cello", 28, 4, 0.55, center=s.key - 17)
	# A'' (32-39): full statement.
	s.hit("cymbal", 32, 0, 0.7)
	s.melody("erhu", 32, erhu_a, octave=1, vel=0.9)
	s.melody("brass", 32, motif + " " + motif, octave=-1, vel=0.75)
	s.arp("ost", 32, 8, ostinato, 0.5, 0.75, center=s.key - 3)
	s.drums("odaiko", 32, 8, groove_o, 0.85)
	s.drums("nagado", 32, 8, groove_n, 0.7)
	s.drums("shime", 32, 8, groove_s, 0.55)
	pads(s, 32, 8, 0.4)
	# Outro (40-43): back to the intro.
	s.melody("brass", 40, "6--- | b7--- | 4--- | 5- 6- |", octave=-1, vel=0.75)
	s.drums("odaiko", 40, 4, "X... .... X... .... ", 0.85)
	s.drums("shime", 42, 2, "o.o. o.o. x.x. xxxx ", 0.6, ramp=(0.5, 1.0))
	s.pad("cello", 40, 4, 0.55, center=s.key - 17)
	return s.render(rng)


# ---------------------------------------------------------------------------
# 6. Southern Air Temple: airy, flutes, bells, wind - G zhi mode (C-do), 70 bpm
# ---------------------------------------------------------------------------

@music("music_air_temple")
def music_air_temple(rng):
	s = Score(70, 32, key=60)
	s.reverb.update(seconds=5.0, t60_low=4.2, t60_high=2.4, brightness=8000.0, wet=0.36, predelay=0.05)
	s.inst("dizi", "phrase", pan=0.15, gain=0.6, send=0.4, echo=0.32, params={"voice": "dizi"})
	s.inst("xiao", "phrase", pan=-0.2, gain=0.78, send=0.42, echo=0.18, params={"voice": "xiao"})
	s.inst("harp", "pluck", pan=0.4, gain=0.34, send=0.45, body="harp", params={"synth": "harp"})
	s.inst("wind", "fx", pan=0.0, gain=0.09, send=0.3, params={"synth": "wind", "base": 900.0})
	strings(s, 0.2, 2800.0, 0.55)
	kit(s, "chime", "bowl", "temple_bell", "frame", "tsuzumi")
	s.progression(0, "5sus2 5sus2 4add9 4add9")
	s.progression(4, "5sus2 4add9 2m7 5sus2 1add9 2m7 4add9 5sus2")
	s.progression(12, "5sus2 4add9 2m7 5sus2")
	s.progression(16, "1add9 6m7 4add9 5sus2 1add9 6m7 4add9 5sus2")
	s.progression(24, "4add9 4add9 5sus2 5sus2")
	s.progression(28, "5sus2 4add9 2m7 5sus2")
	a = "5 6 1' 2' | 3'- 2' 1' | 6 1' 2'_ 1'_ 6 | 5--- | 2' 3' 5' 3' | 2'- 1' 6 | 1' 6 5_ 6_ 3 | 5--- |"
	theme_b = "1' 2' 3' 5' | 6'- 5' 3' | 5' 3' 2' 1' | 2'--- | 3' 5' 6'- | 6'- 5'_ 6'_ 5' | 3' 2' 1' 6 | 5--- |"
	s.hit("wind", 0, 0, 0.9, dur=32 * 4)
	# Intro (0-3)
	s.hit("bowl", 0, 0, 0.6)
	s.hit("temple_bell", 0, 2, 0.5, midi=43)
	s.arp("harp", 0, 4, [0, 1, 2, 11, 12, 11], 2.0 / 3.0, 0.35, center=s.key + 2)
	for b, m in ((1, 86), (2, 91), (3, 88)):
		s.hit("chime", b, 1.5, 0.4, midi=m)
	# A (4-11): dizi with echoes.
	s.melody("dizi", 4, a, octave=1, vel=0.75)
	s.arp("harp", 4, 8, [0, 1, 2, 11, 12, 11], 2.0 / 3.0, 0.32, center=s.key + 2)
	pads(s, 6, 6, 0.3, center=s.key + 7)
	s.drums("frame", 4, 8, "x... .... o... .... ", 0.35)
	# A2 (12-15): xiao answers in the low register.
	s.melody("xiao", 12, "5 6 1' 2' | 3'- 2' 1' | 6 1' 2'_ 1'_ 6 | 5--- |", octave=0, vel=0.7)
	s.arp("harp", 12, 4, [0, 1, 2, 11, 12, 11], 2.0 / 3.0, 0.3, center=s.key + 2)
	pads(s, 12, 4, 0.3, center=s.key + 7)
	s.hit("bowl", 12, 0, 0.45)
	# B (16-23): soaring dizi, high strings, tsuzumi.
	s.hit("temple_bell", 16, 0, 0.45, midi=43)
	s.melody("dizi", 16, theme_b, octave=1, vel=0.8)
	s.melody("xiao", 16, "3--- | 1--- | 1--- | 2--- | 3--- | 1--- | 1--- | 2--- |", octave=1, vel=0.4)
	s.arp("harp", 16, 8, [0, 1, 2, 11, 12, 21, 12, 11], 0.5, 0.32, center=s.key + 2)
	pads(s, 16, 8, 0.38, center=s.key + 7, spread=True)
	s.drums("tsuzumi", 16, 8, "X... .... .... ..x. ", 0.45)
	s.drums("frame", 16, 8, "x... ..o. x... .... ", 0.35)
	# Interlude (24-27): wind and bells, low xiao.
	s.hit("bowl", 24, 0, 0.55)
	s.melody("xiao", 24, "5, 6, 1 2 | 3--- | 2 1 6, 1 | 5,--- |", octave=1, vel=0.65)
	for b, m in ((24, 91), (25, 88), (26, 93), (27, 86)):
		s.hit("chime", b, 2, 0.35, midi=m)
	pads(s, 24, 4, 0.25, center=s.key + 7)
	# Outro (28-31): the opening phrase, echoing away.
	s.melody("dizi", 28, "5 6 1' 2' | 3'- 2' 1' | 6 1' 2'_ 1'_ 6 | 5--- |", octave=1, vel=0.6)
	s.arp("harp", 28, 4, [0, 1, 2, 11, 12, 11], 2.0 / 3.0, 0.3, center=s.key + 2)
	pads(s, 28, 4, 0.28, center=s.key + 7)
	return s.render(rng, tail=9.0)


# ---------------------------------------------------------------------------
# 7. Combat: driving percussion, tension - E minor (G-do jianpu), 144 bpm
# ---------------------------------------------------------------------------

@music("music_combat")
def music_combat(rng):
	s = Score(144, 56, key=55)
	s.reverb.update(seconds=2.0, t60_low=1.6, t60_high=0.8, brightness=5000.0, wet=0.2)
	s.inst("erhu", "phrase", pan=0.12, gain=0.75, send=0.25, params={"voice": "erhu", "gap_break": 0.5})
	s.inst("brass", "brass", pan=-0.15, gain=0.45, send=0.22)
	s.inst("stab", "brass", pan=0.2, gain=0.3, send=0.2, params={"legato": 0.5})
	s.inst("pipa", "pluck", pan=0.42, gain=0.34, send=0.2, body="pipa", params={"synth": "pipa"})
	s.inst("ost", "stacc", pan=-0.3, gain=0.5, send=0.15, params={"len": 0.12})
	s.inst("ost2", "stacc", pan=0.3, gain=0.3, send=0.15, params={"len": 0.1})
	s.inst("choir", "choir", pan=0.0, gain=0.28, send=0.45, params={"vowel": "a", "attack": 0.6})
	s.inst("cello", "pad", pan=0.0, gain=0.42, send=0.15, params={"bright": 650.0, "attack": 0.25})
	kit(s, "odaiko", "nagado", "shime", "ka", "cymbal", "tamtam")
	s.progression(0, "6m5 6m5 6m5 6m5")
	s.progression(4, "6m5 6m5 4 3m 6m5 4 2 3sus4")
	s.progression(12, "6m5 6m5 4 3m 6m5 4 2 3sus4")
	s.progression(20, "6m5 4 6m5 b7 6m5 4 3sus4 3")
	s.progression(28, "6m5 6m5 4 3m 6m5 4 2 3sus4")
	s.progression(36, "6m5 6m5 6m5 6m5 4 4 3sus4 3")
	s.progression(44, "6m5 6m5 4 3m 6m5 4 2 3sus4")
	s.progression(52, "6m5 4 3sus4 3")
	theme = "6- 7 1' | 1'_ 7_ 6 3- | 6- 1' 2' | 3'- 2'_ 1'_ 7 | 6- 7 1' | 2'_ 1'_ 7 6 5 | #4 5 6 7 | 6--- |"
	tension = "3'--- | 4'--- | 3'--- | 2'--- | 3'--- | 4'- 5'- | #4'--- | #5'--- |"
	ost = [0, 0, 10, 0, 1, 0, 10, 0]
	ost16 = [0, 10, 0, 1]
	go = "X... ..X. X... ..X. "
	gn = "..x. x... ..x. x.xx "
	gs = "x.x. x.x. x.x. xxxx "

	def groove(bar, nbars, intensity=1.0):
		s.drums("odaiko", bar, nbars, go, 0.85 * intensity)
		s.drums("nagado", bar, nbars, gn, 0.65 * intensity)
		s.drums("shime", bar, nbars, gs, 0.45 * intensity)

	# Intro (0-3)
	s.drums("shime", 0, 4, "xxxx xxxx xxxx xxxx ", 0.5, ramp=(0.35, 1.0))
	s.drums("odaiko", 0, 4, "X... X... X... X... ", 0.75)
	s.arp("ost", 0, 4, ost, 0.5, 0.7, center=s.key + 4)
	s.pad("cello", 0, 4, 0.5, center=s.key - 15)
	# A (4-11)
	s.hit("cymbal", 4, 0, 0.7)
	s.melody("erhu", 4, theme, octave=1, vel=0.85)
	s.arp("ost", 4, 8, ost, 0.5, 0.75, center=s.key + 4)
	for b in range(4, 12):
		s.hit("stab", b, 0, 0.7, midi=s.key - 3 + 12 * -1, dur=0.5)
		s.hit("stab", b, 1.5, 0.55, midi=s.key - 3 + 12 * -1, dur=0.5)
	groove(4, 8)
	s.pad("cello", 4, 8, 0.5, center=s.key - 15)
	# B (12-19): brass theme, pipa tremolo, erhu sustains.
	s.hit("tamtam", 12, 0, 0.5)
	s.melody("brass", 12, theme, octave=-1, vel=0.8)
	s.melody("pipa", 12, "3't--- | 3't--- | 1't--- | 2't--- | 3't--- | 1't--- | #4't--- | 3't--- |", octave=0, vel=0.45)
	s.arp("ost", 12, 8, ost16, 0.25, 0.65, center=s.key + 4)
	groove(12, 8)
	s.drums("ka", 12, 8, "..x. ..x. ..x. ..x. ", 0.5)
	# C (20-27): rising tension to the dominant.
	s.melody("erhu", 20, tension, octave=1, vel=0.85)
	s.pad("choir", 20, 8, 0.5, center=s.key + 7)
	s.arp("ost", 20, 8, ost16, 0.25, 0.7, center=s.key + 4)
	s.arp("ost2", 24, 4, [0, 1, 2, 1], 0.25, 0.55, center=s.key + 12)
	groove(20, 8, 1.05)
	s.drums("shime", 26, 2, "xxxx xxxx xxxx xxxx ", 0.5, ramp=(0.5, 1.0))
	# D (28-35): climax.
	s.hit("cymbal", 28, 0, 0.8)
	s.hit("tamtam", 28, 0, 0.6)
	s.melody("erhu", 28, theme, octave=1, vel=0.95)
	s.melody("brass", 28, theme, octave=-1, vel=0.8)
	s.pad("choir", 28, 8, 0.6, center=s.key + 7)
	s.arp("ost", 28, 8, ost16, 0.25, 0.75, center=s.key + 4)
	s.pad("cello", 28, 8, 0.6, center=s.key - 15)
	groove(28, 8, 1.1)
	s.drums("ka", 28, 8, "x.x. ..x. x.x. ..x. ", 0.5)
	# E (36-43): breakdown, drums and ostinato only, stabs.
	s.drums("odaiko", 36, 8, "X... .... X..X .... ", 0.85)
	s.drums("nagado", 36, 8, "..x. ..x. .... x.x. ", 0.6)
	s.drums("ka", 36, 8, "x... x... x... x... ", 0.55)
	s.arp("ost", 36, 8, ost, 0.5, 0.7, center=s.key + 4)
	for b in (36, 38, 40, 42):
		s.hit("stab", b, 0, 0.75, midi=s.key - 15, dur=1.0)
	s.drums("shime", 42, 2, "o.o. x.x. xxxx xxxx ", 0.55, ramp=(0.5, 1.0))
	# F (44-51): theme again with pipa doubling.
	s.hit("cymbal", 44, 0, 0.7)
	s.melody("erhu", 44, theme, octave=1, vel=0.9)
	s.melody("pipa", 44, theme, octave=1, vel=0.4)
	s.arp("ost", 44, 8, ost, 0.5, 0.75, center=s.key + 4)
	groove(44, 8)
	s.pad("cello", 44, 8, 0.5, center=s.key - 15)
	# Outro (52-55) -> intro
	s.melody("brass", 52, "6--- | 4--- | 3- 2- | #5,--- |", octave=0, vel=0.7)
	s.arp("ost", 52, 4, ost16, 0.25, 0.7, center=s.key + 4)
	s.drums("odaiko", 52, 4, "X... X... X... X... ", 0.85)
	s.drums("shime", 54, 2, "xxxx xxxx xxxx xxxx ", 0.5, ramp=(0.5, 1.0))
	return s.render(rng, tail=5.0)


# ---------------------------------------------------------------------------
# 8. Tutorial: light, encouraging - F gong mode, 100 bpm
# ---------------------------------------------------------------------------

@music("music_tutorial")
def music_tutorial(rng):
	s = Score(100, 40, key=53)
	s.reverb.update(seconds=2.2, t60_low=1.8, t60_high=0.9, brightness=6500.0, wet=0.22)
	s.inst("dizi", "phrase", pan=0.15, gain=0.6, send=0.28, params={"voice": "dizi"})
	s.inst("pipa", "pluck", pan=0.35, gain=0.48, send=0.22, body="pipa", params={"synth": "pipa", "ring": 0.8})
	s.inst("gz", "pluck", pan=-0.35, gain=0.42, send=0.26, body="guzheng")
	s.inst("bass", "pluck", pan=0.0, gain=0.55, send=0.1, body="bass", params={"synth": "bass", "ring": 0.5})
	strings(s, 0.2, 1700.0)
	kit(s, "muyu_hi", "muyu_lo", "frame", "ban", "chime")
	s.progression(0, "1 4 1 5")
	s.progression(4, "1 6m 4 5 1 4 2m:5 1")
	s.progression(12, "4 5 3m 6m 2m 5 1 1")
	s.progression(20, "1 6m 4 5 1 4 2m:5 1")
	s.progression(28, "4 5 6m 5")
	s.progression(32, "1 6m 4 5 1 4 2m:5 1")
	a = "1 2 3 5 | 6_ 5_ 3 5- | 3 5 6 1' | 6_ 5_ 6 5- | 1 2 3 5 | 6_ 1'_ 6 5 3 | 2 3_ 2_ 1 6, | 1--- |"
	b = "6 1' 6 5 | 3 5 6- | 5 3 2 3 | 6,--- | 2 3 5 6 | 5- 6 1' | 6 5 3 2 | 1--- |"
	bounce = [0, 1, 2, 1]
	# Intro (0-3)
	s.arp("pipa", 0, 4, [0, 1, 2, 11, 2, 1], 0.5, 0.5, center=s.key + 7)
	s.drums("muyu_hi", 0, 4, "x.x. x.x. x.x. x.x. ", 0.5)
	s.bass("bass", 0, 4, [(0, 1.0), (2.0, 1.0)], 0.6, fifth_on=(1,))
	# A (4-11)
	s.melody("dizi", 4, a, octave=1, vel=0.8)
	s.arp("gz", 4, 8, bounce, 0.5, 0.42, center=s.key + 7)
	s.bass("bass", 4, 8, [(0, 1.0), (1.5, 0.5), (2.0, 1.0), (3.0, 1.0)], 0.65, fifth_on=(2,))
	s.drums("muyu_lo", 4, 8, "x... x... x... x... ", 0.5)
	s.drums("muyu_hi", 4, 8, "..x. ..x. ..x. .xx. ", 0.45)
	s.drums("frame", 4, 8, "X... .... X... .... ", 0.5)
	pads(s, 4, 8, 0.28)
	# B (12-19): pipa lead, guzheng countermelody.
	s.hit("chime", 12, 0, 0.4, midi=s.key + 24)
	s.melody("pipa", 12, b, octave=1, vel=0.7)
	s.melody("gz", 12, "3--- | 2--- | 1--- | 2--- | 5,--- | 2--- | 3--- | 3--- |", octave=1, vel=0.45)
	s.bass("bass", 12, 8, [(0, 1.0), (2.0, 1.0)], 0.6, fifth_on=(1,))
	s.drums("ban", 12, 8, "X... .... .... .... ", 0.6)
	s.drums("muyu_hi", 12, 8, "x.x. x.x. x.x. x.x. ", 0.4)
	s.drums("frame", 12, 8, "X... ..x. X... .... ", 0.5)
	pads(s, 12, 8, 0.3)
	# A' (20-27): dizi + guzheng arpeggios, full.
	s.melody("dizi", 20, a, octave=1, vel=0.85)
	s.arp("gz", 20, 8, [0, 1, 2, 11, 12, 11, 2, 1], 0.5, 0.42, center=s.key + 7)
	s.arp("pipa", 20, 8, [None, 0, None, 1], 0.5, 0.35, center=s.key + 12)
	s.bass("bass", 20, 8, [(0, 1.0), (1.5, 0.5), (2.0, 1.0), (3.0, 1.0)], 0.65, fifth_on=(2,))
	s.drums("muyu_lo", 20, 8, "x... x... x... x... ", 0.5)
	s.drums("muyu_hi", 20, 8, "..x. ..x. ..x. .xx. ", 0.45)
	s.drums("frame", 20, 8, "X... ..x. X... .x.. ", 0.55)
	s.drums("ban", 20, 8, "X... .... .... .... ", 0.5)
	pads(s, 20, 8, 0.32)
	# Bridge (28-31): call and response, bells and dizi.
	s.melody("chime", 28, "1' 2' 3' 5' | 0--- | 6' 5' 3' 5' | 0--- |", octave=1, vel=0.45)
	s.melody("dizi", 28, "0--- | 5 3 5 6 | 0--- | 2 3 2 1 |", octave=1, vel=0.7)
	s.bass("bass", 28, 4, [(0, 1.0), (2.0, 1.0)], 0.55)
	s.drums("muyu_hi", 28, 4, "x.x. x.x. x.x. x.x. ", 0.4)
	pads(s, 28, 4, 0.25)
	# A'' (32-39)
	s.melody("dizi", 32, a, octave=1, vel=0.85)
	s.melody("gz", 32, a, octave=0, vel=0.45)
	s.arp("pipa", 32, 8, bounce, 0.5, 0.35, center=s.key + 12)
	s.bass("bass", 32, 8, [(0, 1.0), (1.5, 0.5), (2.0, 1.0), (3.0, 1.0)], 0.65, fifth_on=(2,))
	s.drums("muyu_lo", 32, 8, "x... x... x... x... ", 0.5)
	s.drums("muyu_hi", 32, 8, "..x. ..x. ..x. .xx. ", 0.45)
	s.drums("frame", 32, 8, "X... ..x. X... .x.. ", 0.55)
	pads(s, 32, 8, 0.32)
	return s.render(rng, tail=5.0)
