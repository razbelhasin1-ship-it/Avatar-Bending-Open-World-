"""Airbending: pressurised gusts, whistles, swirling shields and tornado roar."""
from __future__ import annotations

import numpy as np

import dsp as D
import sfxlib as L
from registry import sfx


def gust(rng, dur, f_start, f_end, q=1.4, peak=0.12, sharp=1.3, whistle=0.25):
	"""Directed gust: pitch/brightness sweep from f_start to f_end while the level
	swells fast and tails off."""
	n = D.ns(dur)
	env = L.gamma_env(n, dur * peak, sharp)
	fc = D.curve([(0, f_start), (dur * peak, f_start * 0.9), (dur, f_end)], n, log=True)
	src = 0.6 * D.white(n, rng) + 1.2 * D.pink(n, rng)
	y = D.tv_filter(src, "bp", fc, q) + 0.4 * D.tv_filter(src, "lp", fc * 0.5, 0.8)
	if whistle > 0:
		y += whistle * D.tv_filter(D.white(n, rng), "bp", fc * 2.1, 18.0) * 2.5
	return y * env


@sfx("air_blast", "bending", variants=4)
def air_blast(rng, v):
	dur = rng.uniform(0.65, 0.8)
	g = gust(rng, dur, rng.uniform(2200, 3000), rng.uniform(350, 500), 1.3, 0.1, 1.2, 0.3)
	puff = L.air_puff(rng, 0.3, rng.uniform(140, 180))
	crackle = D.butter(D.white(D.ns(0.03), rng), "high", 3000, 2) * D.exp_decay(D.ns(0.03), 0.02)
	return D.mix(g, (puff, 0.7), (crackle, 0.3))


@sfx("air_sweep", "bending", variants=3)
def air_sweep(rng, v):
	dur = rng.uniform(0.85, 1.0)
	a = L.whoosh(rng, dur, 250, 3200, 1.0, 0.4, 1.8, 0.4, whistle=0.2, doppler=0.25)
	b = L.whoosh(rng, dur * 0.8, 400, 4200, 1.3, 0.5, 2.2, 0.2, whistle=0.15, doppler=0.2)
	return D.mix(a, (b, 0.6, dur * 0.12), (L.air_puff(rng, 0.3, 150), 0.4))


@sfx("air_dash", "bending", variants=3)
def air_dash(rng, v):
	dur = rng.uniform(0.38, 0.45)
	w = L.whoosh(rng, dur, 300, 4500, 1.2, 0.35, 2.8, 0.35, whistle=0.2, doppler=0.35)
	return D.mix(w, (L.air_puff(rng, 0.2, 170), 0.6), (L.cloth(rng, dur * 0.7, 1.2), 0.25))


@sfx("air_jump", "bending", variants=3)
def air_jump(rng, v):
	dur = 0.65
	up = gust(rng, dur, 350, 2600, 1.2, 0.25, 1.4, 0.25)
	return D.mix((L.air_puff(rng, 0.35, 120), 0.9), (up, 0.8, 0.02), (L.cloth(rng, 0.3, 1.0), 0.25, 0.03))


@sfx("air_push", "bending", variants=3)
def air_push(rng, v):
	dur = rng.uniform(0.55, 0.65)
	w = L.whoosh(rng, dur, 160, 1300, 0.8, 0.35, 1.6, 0.8)
	return D.mix(w, (L.air_puff(rng, 0.4, 110), 0.8))


@sfx("air_impact", "impact", variants=4)
def air_impact(rng, v):
	n = D.ns(0.7)
	burst = D.butter(D.white(n, rng), "band", (500, 6000), 2) * L.gamma_env(n, 0.012, 0.9) * np.exp(-D.taxis(n) / 0.12)
	dust = D.butter(D.white(n, rng), "band", (2500, 9000), 2) * L.gamma_env(n, 0.06, 1.2) * 0.25
	return D.mix(burst, (L.air_puff(rng, 0.4, rng.uniform(100, 140)), 1.0), (dust, 1.0),
		(L.debris(rng, 0.5, 90, (2000, 7000), 0.12, 0.4, 0.02), 0.2))


@sfx("air_shield_loop", "loop", loop=(4.0, 0.6))
def air_shield_loop(rng, v):
	dur = 4.6
	n = D.ns(dur)
	sw = L.swirl(rng, n, 2.0, 900, 1.3, 2.2)
	t = D.taxis(n)
	bed = D.butter(D.pink(n, rng), "band", (150, 1500), 2) * (0.7 + 0.3 * np.sin(2 * np.pi * 2.0 * t))
	whistle = D.tv_filter(D.white(n, rng), "bp", 1900 * 2 ** (0.4 * np.sin(2 * np.pi * 1.0 * t)), 20.0) * 1.5
	return sw + 0.8 * D.norm_peak(bed) * 0.4 + whistle * 0.25


@sfx("air_tornado_loop", "loop", loop=(5.0, 0.8), gain_db=3.0)
def air_tornado_loop(rng, v):
	dur = 5.8
	n = D.ns(dur)
	roar = D.butter(D.brown(n, rng), "low", 400, 2)
	roar = D.norm_peak(roar) * (0.75 + 0.25 * D.smooth_noise(n, 4, rng))
	sw = L.swirl(rng, n, 3.2, 650, 1.6, 1.6)
	hi = L.swirl(rng, n, 4.1, 2400, 0.8, 4.0) * 0.4
	debris = D.grains(n, rng, 90, (0.001, 0.003), (1500, 6000), ring=0.5) * 0.4
	rumble = L.rumble(rng, dur, 70, 1.5)
	return roar * 0.9 + sw * 0.7 + hi + debris + rumble * 0.5
