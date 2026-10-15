"""Stereo ambience loops (40 s, crossfaded seam): wind, blizzard, city, forest,
mountain, volcanic, ocean, night, rain, temple.

Beds are rendered per channel from independent noise sharing the same slow
modulation (so the image is wide but gusts move together); point events
(birds, bells, knocks) are placed with constant-power panning.
"""
from __future__ import annotations

import math

import numpy as np

import dsp as D
import instruments as I
import sfxlib as L
from dsp import TAU
from registry import ambience

LOOP = 40.0
XF = 3.0
TOTAL = LOOP + XF


def blank():
	return np.zeros((2, D.ns(TOTAL)))


def gusts(rng, n, rate=0.12, depth=0.6, floor=0.25):
	"""Slow gust envelope in [floor, 1]."""
	g = 0.5 + 0.5 * D.smooth_noise(n, rate, rng)
	g = g + 0.25 * (0.5 + 0.5 * D.smooth_noise(n, rate * 3.1, rng))
	g = np.clip(g / 1.25, 0, 1) ** 1.4
	return floor + (1 - floor) * (1 - depth + depth * g)


def wind_channel(rng, n, gust, base=350.0, span=2.2, q=0.9, howl=0.0, howl_f=(380.0, 900.0), bright=0.0):
	src = D.pink(n, rng) * 0.8 + D.brown(n, rng) * 0.5
	fc = base * 2 ** (span * (gust - 0.5))
	y = D.tv_filter(src, "bp", fc, q, block=256)
	y = D.norm_peak(y) * (0.35 + 0.65 * gust)
	if bright > 0:
		hi = D.butter(D.white(n, rng), "band", (2500, 9000), 2) * gust ** 2
		y += bright * D.norm_peak(hi)
	if howl > 0:
		for f in howl_f:
			hf = f * 2 ** (0.6 * (gust - 0.5)) * (1 + 0.02 * D.smooth_noise(n, 0.7, rng))
			y += howl * D.norm_peak(D.tv_filter(D.white(n, rng), "bp", hf, 16.0, block=256)) * gust ** 2.2
	return y


def stereo_wind(rng, n, gust, **kw):
	shift = D.ns(0.35)
	g2 = np.concatenate([gust[shift:], gust[:shift]])
	return np.stack([wind_channel(rng, n, gust, **kw), wind_channel(rng, n, g2, **kw)])


def place_pan(out, x, t, pan, gain=1.0):
	D.place(out, D.pan(x, pan), D.ns(t), gain)


def event_times(rng, start, end, mean_gap, jitter=0.6):
	t = start + rng.uniform(0, mean_gap)
	out = []
	while t < end:
		out.append(t)
		t += mean_gap * rng.uniform(1 - jitter, 1 + jitter)
	return out


# --- creature/event voices ----------------------------------------------------------

def bird(rng, kind=None):
	kind = kind or rng.choice(["whistle", "trill", "two_note", "warble"])
	if kind == "whistle":
		d = rng.uniform(0.25, 0.5)
		n = D.ns(d)
		f0 = rng.uniform(2500, 4200)
		f = D.curve([(0, f0), (d * 0.3, f0 * 1.08), (d, f0 * rng.uniform(0.65, 0.8))], n, log=True)
		y = np.sin(TAU * D.phase(f, n)) * L.gamma_env(n, d * 0.3, 1.2)
	elif kind == "trill":
		k = int(rng.integers(5, 11))
		f0 = rng.uniform(3000, 5000)
		y = np.zeros(D.ns(k * 0.075 + 0.1))
		for i in range(k):
			d = rng.uniform(0.03, 0.045)
			n = D.ns(d)
			f = D.curve([(0, f0 * 0.85), (d, f0 * 1.15)], n, log=True)
			D.place(y, np.sin(TAU * D.phase(f, n)) * np.sin(np.linspace(0, math.pi, n)), D.ns(i * 0.07))
	elif kind == "two_note":
		f0 = rng.uniform(2200, 3400)
		y = np.zeros(D.ns(0.7))
		for i, r in enumerate((1.0, rng.choice([1.19, 1.26, 0.84]))):
			d = 0.22
			n = D.ns(d)
			f = f0 * r * (1 + 0.02 * np.sin(TAU * 30 * D.taxis(n)))
			D.place(y, np.sin(TAU * D.phase(f, n)) * L.gamma_env(n, 0.05, 1.0), D.ns(i * 0.3))
	else:
		d = rng.uniform(0.6, 1.0)
		n = D.ns(d)
		f0 = rng.uniform(2800, 4000)
		f = f0 * (1 + 0.12 * np.sin(TAU * rng.uniform(18, 28) * D.taxis(n))) * D.curve([(0, 1.0), (d, 1.15)], n)
		y = np.sin(TAU * D.phase(f, n)) * L.gamma_env(n, d * 0.4, 1.0) * (0.6 + 0.4 * np.abs(D.smooth_noise(n, 12, rng)))
	return y + 0.08 * np.sin(2 * np.arcsin(np.clip(y, -1, 1)))


def hawk(rng):
	d = rng.uniform(0.9, 1.2)
	n = D.ns(d)
	f = D.curve([(0, 2600), (0.15, 3300), (d, 2100)], n, log=True) * (1 + 0.012 * np.sin(TAU * 70 * D.taxis(n)))
	y = np.sin(TAU * D.phase(f, n)) + 0.3 * np.sin(TAU * D.phase(f * 2, n))
	y += 0.25 * D.tv_filter(D.white(n, rng), "bp", f, 8.0)
	return y * L.gamma_env(n, d * 0.2, 0.9)


def cricket(rng, n, rate, carrier, pulses=4, period=0.7, pan=0.0):
	t = D.taxis(n)
	ph = (t % period) / period
	gate = (ph < pulses / rate / period).astype(float)
	pulse = (0.5 + 0.5 * np.sin(TAU * rate * t)) ** 4
	y = np.sin(TAU * carrier * t + 0.3 * np.sin(TAU * carrier * 2 * t)) * pulse * gate
	return D.pan(y * (0.7 + 0.3 * D.smooth_noise(n, 0.1, rng)), pan)


def frog(rng):
	d = rng.uniform(0.25, 0.4)
	n = D.ns(d)
	f0 = rng.uniform(180, 260)
	src = D.saw(f0 * (1 + 0.1 * np.sin(TAU * 35 * D.taxis(n))), n)
	y = D.formants(src, [(rng.uniform(500, 700), 5, 1.0), (1400, 7, 0.4)]) * L.gamma_env(n, d * 0.3, 1.0)
	return D.norm_peak(y)


def owl(rng):
	out = np.zeros(D.ns(2.2))
	f0 = rng.uniform(330, 400)
	for i, (dt, d) in enumerate(((0.0, 0.35), (0.55, 0.2), (0.85, 0.6))):
		n = D.ns(d)
		f = D.curve([(0, f0 * 1.04), (d, f0 * 0.95)], n)
		hoot = np.sin(TAU * D.phase(f, n)) * np.sin(np.linspace(0, math.pi, n)) ** 1.5
		hoot += 0.15 * D.butter(D.white(n, rng), "band", (300, 800), 2) * np.sin(np.linspace(0, math.pi, n))
		D.place(out, hoot, D.ns(dt))
	return out


def babble_voice(rng, n):
	"""One distant talker: glottal source through syllable-wise switching formants."""
	t = D.taxis(n)
	f0 = rng.uniform(100, 210) * (1 + 0.08 * D.smooth_noise(n, 2.0, rng))
	syl = rng.uniform(3.5, 5.5)
	phrase = (D.smooth_noise(n, 0.35, rng) > -0.1).astype(float)
	phrase = D.onepole_lp(phrase, 3.0)
	amp = (0.5 + 0.5 * np.sin(TAU * D.phase(syl * (1 + 0.2 * D.smooth_noise(n, 1, rng)), n))) ** 2 * phrase
	vowels = [(730, 1090), (270, 2290), (530, 1840), (570, 840), (440, 1020), (300, 870), (660, 1720)]
	k = int(n / D.SR * syl) + 2
	idx = rng.integers(0, len(vowels), k)
	f1 = np.repeat([vowels[i][0] for i in idx], n // k + 1)[:n]
	f2 = np.repeat([vowels[i][1] for i in idx], n // k + 1)[:n]
	f1 = D.onepole_lp(f1.astype(float), 25.0)
	f2 = D.onepole_lp(f2.astype(float), 25.0)
	src = D.saw(f0, n) + 0.3 * D.white(n, rng)
	y = D.tv_filter(src, "bp", f1, 5.0, block=256) + 0.5 * D.tv_filter(src, "bp", f2, 7.0, block=256)
	return y * amp


# --- loops -----------------------------------------------------------------------------

@ambience("amb_arctic_wind")
def amb_arctic_wind(rng):
	n = D.ns(TOTAL)
	g = gusts(rng, n, 0.09, 0.75, 0.2)
	out = stereo_wind(rng, n, g, base=320, span=2.0, q=0.8, howl=0.12, howl_f=(420.0, 610.0), bright=0.06)
	low = D.norm_peak(D.butter(D.brown(n, rng), "low", 150, 2)) * (0.4 + 0.6 * g)
	out += np.stack([low, low]) * 0.35
	for t in event_times(rng, 3, TOTAL - 2, 9.0):
		cr = L.creak(rng, 0.4, D.curve([(0, 30), (0.4, 80)], D.ns(0.4)), rng.uniform(1500, 2500), 0.006)
		place_pan(out, cr * L.gamma_env(D.ns(0.4), 0.2, 1.0), t, rng.uniform(-0.8, 0.8), 0.05)
	return out


@ambience("amb_blizzard")
def amb_blizzard(rng):
	n = D.ns(TOTAL)
	g = gusts(rng, n, 0.2, 0.5, 0.45)
	out = stereo_wind(rng, n, g, base=520, span=1.6, q=0.7, howl=0.2, howl_f=(520.0, 780.0, 1150.0), bright=0.3)
	for c in range(2):
		pellets = D.grains(n, rng, 2500 * g, (0.0003, 0.001), (3000, 11000))
		out[c] += D.norm_peak(pellets) * 0.18
	low = D.norm_peak(D.butter(D.brown(n, rng), "low", 120, 2)) * g
	out += np.stack([low, low]) * 0.4
	return out


@ambience("amb_city")
def amb_city(rng):
	n = D.ns(TOTAL)
	out = blank()
	for i in range(18):
		v = babble_voice(rng, n)
		out += D.pan(D.norm_peak(v), rng.uniform(-0.9, 0.9)) * rng.uniform(0.3, 1.0)
	out = D.butter(out, "low", 2600, 2) * 0.35
	bed = np.stack([D.butter(D.pink(n, rng), "band", (120, 1200), 2) for _ in range(2)])
	out += D.norm_peak(bed) * 0.12
	for t in event_times(rng, 1, TOTAL - 1, 2.2):  # wooden carts, crates, footsteps
		k = I.woodblock(rng.uniform(300, 700), rng, 0.6, t60=0.05)
		place_pan(out, k, t, rng.uniform(-1, 1), rng.uniform(0.05, 0.15))
	for t in event_times(rng, 4, TOTAL - 4, 13.0):  # distant temple bell
		b = I.bell(rng.uniform(140, 190), 5.0, rng, "temple", 0.5)
		place_pan(out, D.butter(b, "low", 2500, 2), t, rng.uniform(-0.6, 0.6), 0.12)
	for t in event_times(rng, 6, TOTAL - 3, 11.0):  # vendor calls (a held vowel)
		d = rng.uniform(0.6, 1.0)
		m = D.ns(d)
		f0 = D.curve([(0, rng.uniform(180, 240)), (d, rng.uniform(150, 200))], m)
		call = L.voice(rng, f0, [(700, 6, 1.0), (1150, 8, 0.5), (2500, 9, 0.2)], L.gamma_env(m, d * 0.3, 1.0), aspiration=0.1)
		place_pan(out, D.butter(D.norm_peak(call), "low", 3000, 2), t, rng.uniform(-0.8, 0.8), 0.12)
	ir = D.make_ir(1.6, rng, t60_low=1.4, t60_high=0.7, predelay=0.02, brightness=4000.0)
	return D.reverb(out, ir, 0.25, 1.0)[:, :n]


@ambience("amb_forest")
def amb_forest(rng):
	n = D.ns(TOTAL)
	g = gusts(rng, n, 0.15, 0.7, 0.2)
	out = np.zeros((2, n))
	for c in range(2):
		leaves = D.butter(D.white(n, rng), "band", (1800, 9000), 2) * (0.5 + 0.5 * np.abs(D.smooth_noise(n, 30, rng)))
		out[c] = D.norm_peak(leaves) * g * 0.25
	out += stereo_wind(rng, n, g, base=250, span=1.4, q=0.8) * 0.25
	for t in event_times(rng, 0.5, TOTAL - 1.5, 1.6):
		place_pan(out, bird(rng), t, rng.uniform(-0.9, 0.9), rng.uniform(0.05, 0.16))
	for t in event_times(rng, 8, TOTAL - 3, 17.0):  # woodpecker drumming
		k = int(rng.integers(10, 18))
		dr = np.zeros(D.ns(k * 0.05 + 0.1))
		for i in range(k):
			D.place(dr, I.woodblock(rng.uniform(900, 1100), rng, 0.6 * (1 - i / (k * 1.5)), t60=0.03), D.ns(i * 0.048))
		place_pan(out, dr, t, rng.uniform(-0.8, 0.8), 0.06)
	return out


@ambience("amb_mountain_wind")
def amb_mountain_wind(rng):
	n = D.ns(TOTAL)
	g = gusts(rng, n, 0.1, 0.8, 0.15)
	out = stereo_wind(rng, n, g, base=700, span=1.8, q=1.4, howl=0.18, howl_f=(880.0, 1320.0), bright=0.12)
	for t in event_times(rng, 6, TOTAL - 4, 16.0):
		place_pan(out, D.butter(hawk(rng), "low", 5000, 2), t, rng.uniform(-0.8, 0.8), 0.07)
	return out


@ambience("amb_volcanic")
def amb_volcanic(rng):
	n = D.ns(TOTAL)
	out = np.zeros((2, n))
	for c in range(2):
		rum = D.norm_peak(D.butter(D.brown(n, rng), "low", 90, 4)) * (0.7 + 0.3 * D.smooth_noise(n, 0.2, rng))
		out[c] += rum * 0.8
		blub = D.bubbles(n, rng, 6.0, (70.0, 260.0), (0.15, 0.4), (0.1, 0.4))
		out[c] += D.norm_peak(blub) * 0.35
		out[c] += L.crackle(rng, n, 4.0, pop=0.3) * 0.08
	for t in event_times(rng, 2, TOTAL - 3, 7.0):  # steam vents
		d = rng.uniform(1.5, 3.0)
		m = D.ns(d)
		hiss = D.butter(D.white(m, rng), "band", (1500, 8000), 2) * L.gamma_env(m, d * 0.3, 1.2)
		place_pan(out, hiss, t, rng.uniform(-0.9, 0.9), 0.12)
	for t in event_times(rng, 10, TOTAL - 3, 18.0):  # distant rock tumble
		rt = L.debris(rng, 1.5, 120, (600, 3000), 0.4, 0.5)
		place_pan(out, D.butter(rt, "low", 3000, 2), t, rng.uniform(-0.8, 0.8), 0.1)
	return out


@ambience("amb_ocean_waves")
def amb_ocean_waves(rng):
	n = D.ns(TOTAL)
	out = np.zeros((2, n))
	for c in range(2):
		bed = D.butter(D.pink(n, rng), "band", (150, 2500), 2)
		out[c] += D.norm_peak(bed) * 0.15
	period = LOOP / 5  # five wave cycles per loop keeps the seam on the same phase
	for k in range(6):
		t0 = k * period + rng.uniform(-0.6, 0.6)
		d = period * 1.2
		m = D.ns(d)
		tt = D.taxis(m)
		swell = np.clip(tt / (d * 0.35), 0, 1) ** 2 * np.exp(-np.maximum(tt - d * 0.35, 0) / (d * 0.25))
		pan = rng.uniform(-0.5, 0.5)
		for c in range(2):
			wv = D.tv_filter(D.pink(m, rng), "lp", 300 + 4500 * swell, 0.7, block=256)
			foam = D.butter(D.white(m, rng), "band", (2500, 10000), 2) * np.exp(-np.maximum(tt - d * 0.35, 0) / (d * 0.18)) * (tt > d * 0.33)
			w = (D.norm_peak(wv) * swell + 0.25 * foam) * (1 + (pan if c else -pan) * 0.4)
			D.place(out[c], w, D.ns(max(t0, 0)), 0.8)
	return out


@ambience("amb_night")
def amb_night(rng):
	n = D.ns(TOTAL)
	g = gusts(rng, n, 0.08, 0.5, 0.3)
	out = stereo_wind(rng, n, g, base=220, span=1.0, q=0.8) * 0.2
	for i in range(5):
		out += cricket(rng, n, rng.uniform(22, 32), rng.uniform(3900, 5200), int(rng.integers(3, 6)),
			rng.uniform(0.5, 0.9), rng.uniform(-0.9, 0.9)) * rng.uniform(0.04, 0.09)
	for t in event_times(rng, 1, TOTAL - 1, 2.5):
		place_pan(out, frog(rng), t, rng.uniform(-0.9, 0.9), rng.uniform(0.03, 0.08))
	for t in event_times(rng, 9, TOTAL - 4, 15.0):
		place_pan(out, owl(rng), t, rng.uniform(-0.7, 0.7), 0.12)
	return out


@ambience("amb_rain")
def amb_rain(rng):
	n = D.ns(TOTAL)
	inten = 0.8 + 0.2 * D.smooth_noise(n, 0.05, rng)
	out = np.zeros((2, n))
	for c in range(2):
		hiss = D.butter(D.pink(n, rng), "band", (400, 9000), 2)
		drops = D.grains(n, rng, 1500 * inten, (0.0002, 0.0008), (2000, 12000))
		plinks = D.bubbles(n, rng, 35 * inten, (1500.0, 4500.0), (0.01, 0.03), (1.5, 3.0))
		low = D.butter(D.brown(n, rng), "low", 200, 2)
		out[c] = (D.norm_peak(hiss) * 0.5 + D.norm_peak(drops) * 0.3 + D.norm_peak(plinks) * 0.12 + D.norm_peak(low) * 0.25) * inten
	return out


@ambience("amb_temple")
def amb_temple(rng):
	n = D.ns(TOTAL)
	g = gusts(rng, n, 0.07, 0.6, 0.3)
	out = stereo_wind(rng, n, g, base=400, span=1.2, q=1.0, howl=0.06, howl_f=(600.0,)) * 0.5
	drone = np.zeros(n)
	for m, a in ((45, 1.0), (52, 0.5), (57, 0.3)):  # low resonant hum of the halls
		drone += a * np.sin(TAU * D.midi_hz(m) * D.taxis(n) + rng.uniform(0, TAU)) * (0.7 + 0.3 * D.smooth_noise(n, 0.1, rng))
	out += np.stack([drone, drone]) * 0.05
	for t in event_times(rng, 2, TOTAL - 4, 9.0):
		chime = np.zeros(D.ns(3.0))
		tt = 0.0
		for _ in range(int(rng.integers(3, 7))):
			tt += rng.uniform(0.08, 0.4)
			D.place(chime, I.bell(D.midi_hz(rng.choice([86, 88, 90, 93, 95, 98])), 1.6, rng, "chime", rng.uniform(0.3, 0.8)), D.ns(tt))
		place_pan(out, chime, t, rng.uniform(-0.8, 0.8), 0.05)
	for t in event_times(rng, 12, TOTAL - 6, 20.0):
		place_pan(out, I.bell(D.midi_hz(rng.choice([45, 47])), 6.0, rng, "temple", 0.6), t, rng.uniform(-0.4, 0.4), 0.12)
	ir = D.make_ir(3.0, rng, t60_low=2.8, t60_high=1.4, predelay=0.03, brightness=5000.0)
	return D.reverb(out, ir, 0.3, 1.0)[:, :n]
