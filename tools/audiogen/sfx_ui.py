"""UI sounds and stingers: soft wood, bells and guzheng tones in D major pentatonic."""
from __future__ import annotations

import numpy as np

import dsp as D
import instruments as I
import sfxlib as L
from registry import sfx

# D major pentatonic (jianpu 1 2 3 5 6 = D E F# A B)
PENTA = [62, 64, 66, 69, 71]


def pm(degree: int, octave: int = 0) -> float:
	"""Pentatonic degree (0-based, may exceed 4) to MIDI."""
	o, d = divmod(degree, 5)
	return PENTA[d] + 12 * (o + octave)


def room(x: np.ndarray, rng: np.random.Generator, wet: float = 0.18, seconds: float = 1.2, bright: float = 7000.0) -> np.ndarray:
	"""Small mono room/hall used to glue UI layers."""
	ir = D.make_ir(seconds, rng, t60_low=seconds * 0.8, t60_high=seconds * 0.45, predelay=0.012, brightness=bright, stereo=False)
	return D.reverb(x, ir, wet, 1.0).mean(axis=0)


def pluck(midi: float, dur: float, rng, vel: float = 0.7) -> np.ndarray:
	return I.body(I.guzheng(D.midi_hz(midi), dur, rng, vel), "guzheng")


def seq(events, total: float, rng) -> np.ndarray:
	"""Mixes (time, signal, gain) tuples into a buffer of `total` seconds."""
	out = np.zeros(D.ns(total))
	for t, s, g in events:
		D.place(out, s, D.ns(t) if t > 0 else 0, g)
	return out


@sfx("ui_hover", "ui", variants=3, gain_db=-6.0)
def ui_hover(rng, v):
	tick = I.woodblock(2300 + 180 * v, rng, 0.5, t60=0.025)
	harm = I.ks_string(D.midi_hz(pm(10 + v)), 0.18, rng, t60=0.12, bright=0.4, vel=0.4)
	return seq([(0, tick, 0.6), (0.002, harm, 0.5)], 0.2, rng)


@sfx("ui_click", "ui", variants=3)
def ui_click(rng, v):
	knock = I.woodblock(980 + 60 * v, rng, 0.8, t60=0.06)
	p = pluck(pm(7 + v), 0.35, rng, 0.6)
	return room(seq([(0, knock, 0.8), (0.004, p, 0.35)], 0.4, rng), rng, 0.12)


@sfx("ui_back", "ui")
def ui_back(rng, v):
	a = pluck(pm(8), 0.5, rng, 0.6)
	b = pluck(pm(5), 0.7, rng, 0.55)
	k = I.woodblock(760, rng, 0.5, t60=0.05)
	return room(seq([(0, k, 0.4), (0.0, a, 0.6), (0.075, b, 0.6)], 0.8, rng), rng, 0.15)


@sfx("ui_confirm", "ui")
def ui_confirm(rng, v):
	a = pluck(pm(5), 0.9, rng, 0.7)
	b = pluck(pm(8), 0.9, rng, 0.7)
	bell = I.bell(D.midi_hz(pm(10)), 1.0, rng, "small", 0.5)
	k = I.woodblock(1150, rng, 0.6, t60=0.05)
	return room(seq([(0, k, 0.5), (0, a, 0.55), (0.06, b, 0.6), (0.12, bell, 0.35)], 1.1, rng), rng, 0.2)


@sfx("ui_open", "ui")
def ui_open(rng, v):
	sw = L.whoosh(rng, 0.35, 900, 5000, 1.0, 0.6, 1.5, 0.2)
	notes = [pluck(pm(d), 0.8, rng, 0.5) for d in (5, 7, 8)]
	ev = [(0, sw * 0.5, 0.5)] + [(0.09 + 0.045 * i, s, 0.45) for i, s in enumerate(notes)]
	return room(seq(ev, 1.0, rng), rng, 0.18)


@sfx("ui_close", "ui")
def ui_close(rng, v):
	sw = L.whoosh(rng, 0.3, 2500, 600, 1.0, 0.3, 1.5, 0.2)
	a = pluck(pm(6), 0.6, rng, 0.5)
	b = pluck(pm(3), 0.8, rng, 0.5)
	return room(seq([(0, sw * 0.5, 0.5), (0.05, a, 0.4), (0.1, b, 0.45)], 0.9, rng), rng, 0.15)


@sfx("ui_error", "ui")
def ui_error(rng, v):
	k1 = I.woodblock(330, rng, 0.9, t60=0.07)
	k2 = I.woodblock(300, rng, 0.8, t60=0.08)
	p = I.pluck_bass(D.midi_hz(50), 0.5, rng, 0.6)
	p2 = I.pluck_bass(D.midi_hz(51), 0.5, rng, 0.4)
	return room(seq([(0, k1, 0.8), (0.11, k2, 0.8), (0, p, 0.35), (0.11, p2, 0.3)], 0.6, rng), rng, 0.1)


@sfx("ui_select_element", "ui", gain_db=2.0)
def ui_select_element(rng, v):
	g = I.gong("opera_low", rng, 0.6, dur=2.2)
	arp = [pluck(pm(d, -1), 1.6, rng, 0.65) for d in (0, 3, 5, 7, 8)]
	bell = I.bell(D.midi_hz(pm(10)), 1.8, rng, "chime", 0.5)
	taiko = I.taiko("nagado", rng, 0.6)
	ev = [(0, taiko, 0.5), (0, g, 0.25), (1.0, bell, 0.25)] + [(0.04 + 0.07 * i, s, 0.5) for i, s in enumerate(arp)]
	return room(seq(ev, 2.4, rng), rng, 0.3, 1.8)


@sfx("ui_notify", "ui")
def ui_notify(rng, v):
	a = I.bell(D.midi_hz(pm(8)), 1.0, rng, "small", 0.6)
	b = I.bell(D.midi_hz(pm(10)), 1.2, rng, "small", 0.6)
	return room(seq([(0, a, 0.6), (0.12, b, 0.6)], 1.3, rng), rng, 0.22)


@sfx("ui_quest", "ui")
def ui_quest(rng, v):
	arp = [pluck(pm(d), 1.2, rng, 0.6) for d in (3, 5, 6, 8)]
	bell = I.bell(D.midi_hz(pm(13)), 1.4, rng, "chime", 0.45)
	k = I.woodblock(900, rng, 0.6, t60=0.06)
	ev = [(0, k, 0.4), (0.4, bell, 0.3)] + [(0.07 * i, s, 0.5) for i, s in enumerate(arp)]
	return room(seq(ev, 1.6, rng), rng, 0.25, 1.5)


@sfx("ui_levelup", "ui", gain_db=2.0)
def ui_levelup(rng, v):
	run = [pluck(pm(d), 1.4, rng, 0.55 + 0.04 * i) for i, d in enumerate(range(5, 12))]
	chime = I.bell(D.midi_hz(pm(12)), 2.0, rng, "chime", 0.5)
	gong = I.gong("opera_high", rng, 0.5)
	ev = [(0.05 * i, s, 0.5) for i, s in enumerate(run)] + [(0.36, chime, 0.35), (0.36, gong, 0.2)]
	return room(seq(ev, 2.4, rng), rng, 0.3, 1.8)


@sfx("ui_discovery", "ui", gain_db=1.0)
def ui_discovery(rng, v):
	notes = [I.PNote(0.0, 0.18, pm(6), 0.7, legato=False), I.PNote(0.18, 0.18, pm(7), 0.75), I.PNote(0.36, 1.0, pm(8), 0.8, vib=1.2)]
	fl = I.render_phrase(notes, I.DIZI, rng)
	b1 = I.bell(D.midi_hz(pm(10)), 1.6, rng, "chime", 0.5)
	b2 = I.bell(D.midi_hz(pm(13)), 1.6, rng, "chime", 0.4)
	return room(seq([(0, fl, 0.6), (0.36, b1, 0.3), (0.5, b2, 0.25)], 2.0, rng), rng, 0.35, 2.0)


# ---------------------------------------------------------------------------
# Stingers (2D, player-centric)
# ---------------------------------------------------------------------------

@sfx("pickup", "stinger", variants=3, gain_db=-4.0)
def pickup(rng, v):
	a = pluck(pm(8 + v), 0.6, rng, 0.7)
	sparkle = I.bell(D.midi_hz(pm(13 + v)), 0.7, rng, "glass", 0.5)
	return room(seq([(0, a, 0.6), (0.05, sparkle, 0.3)], 0.8, rng), rng, 0.18)


@sfx("quest_complete", "stinger")
def quest_complete(rng, v):
	t = I.taiko("odaiko", rng, 0.9)
	t2 = I.taiko("nagado", rng, 0.7)
	gl = [pluck(pm(d, -1), 2.2, rng, 0.5 + 0.03 * i) for i, d in enumerate(range(0, 11))]
	notes = [I.PNote(0.0, 0.25, pm(5), 0.8, legato=False), I.PNote(0.25, 0.25, pm(6), 0.8), I.PNote(0.5, 0.25, pm(7), 0.85),
		I.PNote(0.75, 1.6, pm(8), 0.9, vib=1.3)]
	fl = I.render_phrase(notes, I.DIZI, rng)
	gong = I.gong("tamtam", rng, 0.7, dur=4.0)
	ev = [(0, t, 0.7), (0.5, t2, 0.5), (0.75, t, 0.6), (0.75, gong, 0.35), (0.45, fl, 0.55)]
	ev += [(0.03 * i, s, 0.4) for i, s in enumerate(gl)]
	return room(seq(ev, 4.2, rng), rng, 0.35, 2.2)


@sfx("discovery", "stinger")
def discovery(rng, v):
	notes = [I.PNote(0.0, 0.5, pm(3), 0.7, legato=False), I.PNote(0.5, 0.35, pm(5), 0.75), I.PNote(0.85, 0.35, pm(6), 0.75),
		I.PNote(1.2, 1.6, pm(5), 0.8, vib=1.2, slide=0.12)]
	fl = I.render_phrase(notes, I.XIAO, rng)
	pad = I.string_pad([pm(0, -1), pm(3, -1), pm(5, -1), pm(7, -1)], 2.4, rng, 0.6, attack=0.8, release=1.0)
	chimes = [I.bell(D.midi_hz(pm(d)), 2.0, rng, "chime", 0.4) for d in (10, 12, 13)]
	ev = [(0, fl, 0.7), (0.1, pad, 0.35)] + [(1.2 + 0.15 * i, c, 0.25) for i, c in enumerate(chimes)]
	return room(seq(ev, 4.0, rng), rng, 0.4, 2.5)


@sfx("level_up", "stinger")
def level_up(rng, v):
	run = [pluck(pm(d, -1), 2.0, rng, 0.5 + 0.03 * i) for i, d in enumerate(range(5, 16))]
	choir = I.choir_pad([pm(0, -1), pm(3, -1), pm(5, -1), pm(8, -1)], 2.0, rng, 0.6, attack=0.5, release=1.2)
	gong = I.gong("tamtam", rng, 0.7, dur=3.5)
	t = I.taiko("odaiko", rng, 0.8)
	bell = I.bell(D.midi_hz(pm(15)), 2.5, rng, "chime", 0.5)
	ev = [(0.045 * i, s, 0.45) for i, s in enumerate(run)] + [(0.5, choir, 0.4), (0.5, gong, 0.3), (0.5, t, 0.6), (0.55, bell, 0.25)]
	return room(seq(ev, 4.0, rng), rng, 0.35, 2.2)


@sfx("gong", "stinger", gain_db=-1.0)
def gong_sfx(rng, v):
	g = I.gong("tamtam", rng, 0.9, dur=6.0)
	return room(g, rng, 0.25, 2.5, 5000.0)


@sfx("wind_chime", "stinger", variants=2, gain_db=-5.0)
def wind_chime(rng, v):
	tubes = [pm(d) for d in (8, 9, 10, 11, 12, 13)]
	out = np.zeros(D.ns(3.5))
	t = 0.0
	for _ in range(9 + v * 2):
		t += rng.uniform(0.04, 0.35)
		if t > 2.4:
			break
		m = tubes[rng.integers(len(tubes))]
		D.place(out, I.bell(D.midi_hz(m), 1.4, rng, "chime", rng.uniform(0.3, 0.8)), D.ns(t), 0.4)
	return room(out, rng, 0.3, 2.0)
