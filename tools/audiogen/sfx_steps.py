"""Footsteps per surface (heel + toe roll) and landings."""
from __future__ import annotations

import numpy as np

import dsp as D
import sfxlib as L
from registry import sfx

STEP_VARIANTS = 5


def thud(rng, dur=0.09, f=120.0, low=260.0):
	"""Muffled heel thud: pitched-down sine + low-passed noise."""
	n = D.ns(dur)
	body = D.thump(dur, f * 1.6, f, dur * 0.45, sweep_t=0.012)
	nz = D.butter(D.white(n, rng), "low", low, 2) * L.gamma_env(n, 0.006, 1.0)
	return body * 0.8 + D.norm_peak(nz) * 0.5


def scuff(rng, dur=0.05, band=(1500.0, 7000.0)):
	n = D.ns(dur)
	return D.butter(D.white(n, rng), "band", band, 2) * L.gamma_env(n, dur * 0.3, 1.5)


def crunch(rng, dur=0.16, density=1800.0, band=(500.0, 6000.0), peak=0.35):
	"""Granular compression crunch (snow, gravel): density swells then stops."""
	n = D.ns(dur)
	env = L.gamma_env(n, dur * peak, 1.3)
	return D.grains(n, rng, density * env, (0.0006, 0.0025), band, D.SR, 1.4) * (0.4 + 0.6 * env)


def compose(rng, heel, toe, toe_delay=(0.05, 0.09), toe_gain=0.5, total=0.45):
	out = np.zeros(D.ns(total))
	D.place(out, heel, 0)
	D.place(out, toe, D.ns(rng.uniform(*toe_delay)), toe_gain * rng.uniform(0.8, 1.1))
	return out


@sfx("step_stone", "step", variants=STEP_VARIANTS)
def step_stone(rng, v):
	heel = D.mix((L.crack(rng, 0.05, 1500, 5500, 5), 0.5), thud(rng, 0.08, 150),
		(D.grains(D.ns(0.05), rng, 900, (0.0005, 0.0015), (2500, 9000)), 0.4))
	toe = D.mix((scuff(rng, 0.045, (1800, 8000)), 0.8), (L.crack(rng, 0.03, 2500, 7000, 3), 0.2))
	return compose(rng, heel, toe, (0.045, 0.075), 0.45, 0.3)


@sfx("step_snow", "step", variants=STEP_VARIANTS)
def step_snow(rng, v):
	heel = D.mix(crunch(rng, rng.uniform(0.14, 0.2), 2200, (500, 6500)), (thud(rng, 0.1, 90, 220), 0.35))
	n = heel.shape[0]
	squeak = D.modal(D.dust(n, 25, rng), [rng.uniform(900, 1500), rng.uniform(1700, 2600)], [0.012, 0.008], [1, .6])
	heel = heel + squeak * 0.35
	toe = crunch(rng, 0.1, 1400, (900, 7000), 0.25)
	return compose(rng, heel, toe, (0.08, 0.13), 0.55, 0.42)


@sfx("step_ice", "step", variants=STEP_VARIANTS)
def step_ice(rng, v):
	heel = D.mix((L.crack(rng, 0.06, 2200, 7500, 6), 0.6), (thud(rng, 0.07, 140), 0.6), (L.ice_ring(rng, 0.18, 2500, 8500, 6), 0.12))
	slide = D.butter(D.white(D.ns(0.08), rng), "band", (3000, 10000), 2) * L.gamma_env(D.ns(0.08), 0.03, 1.2)
	toe = D.mix((slide, 0.6), (L.crack(rng, 0.03, 3000, 8000, 3), 0.25))
	return compose(rng, heel, toe, (0.05, 0.08), 0.45, 0.32)


@sfx("step_grass", "step", variants=STEP_VARIANTS)
def step_grass(rng, v):
	n = D.ns(0.18)
	swish = D.butter(D.white(n, rng), "band", (1100, 6000), 2) * L.gamma_env(n, 0.05, 1.2)
	swish *= 0.55 + 0.45 * np.abs(D.smooth_noise(n, 90, rng))
	twigs = D.grains(n, rng, 120 * L.gamma_env(n, 0.03, 1.0), (0.0005, 0.0015), (2000, 7000))
	heel = D.mix((thud(rng, 0.1, 105, 260), 1.0), (swish, 0.45), (twigs, 0.3))
	toe = D.mix((swish[: D.ns(0.12)], 0.5), (scuff(rng, 0.04, (1500, 6000)), 0.3))
	return compose(rng, heel, toe, (0.06, 0.1), 0.5, 0.36)


@sfx("step_dirt", "step", variants=STEP_VARIANTS)
def step_dirt(rng, v):
	grit = crunch(rng, 0.07, 900, (700, 4500), 0.2)
	heel = D.mix((thud(rng, 0.09, 115, 300), 0.8), (grit, 0.55))
	toe = D.mix((scuff(rng, 0.05, (900, 5000)), 0.5), (crunch(rng, 0.05, 600, (900, 5000), 0.3), 0.4))
	return compose(rng, heel, toe, (0.05, 0.085), 0.45, 0.3)


@sfx("step_sand", "step", variants=STEP_VARIANTS)
def step_sand(rng, v):
	n = D.ns(0.2)
	shush = D.butter(D.white(n, rng), "band", (1200, 7500), 2) * L.gamma_env(n, 0.035, 1.1)
	fine = D.grains(n, rng, 2500 * L.gamma_env(n, 0.04, 1.0), (0.0003, 0.001), (3500, 11000))
	heel = D.mix((thud(rng, 0.08, 95, 200), 0.45), (shush, 0.7), (fine, 0.25))
	toe = shush[: D.ns(0.13)] * 0.55
	return compose(rng, heel, toe, (0.07, 0.11), 0.5, 0.38)


@sfx("step_wood", "step", variants=STEP_VARIANTS)
def step_wood(rng, v):
	n = D.ns(0.22)
	imp = np.zeros(n)
	imp[0] = 1.0
	imp[D.ns(0.002)] = -0.4
	base = rng.uniform(150, 200)
	knock = D.modal(imp, [base, base * 1.72, base * 2.81, base * 4.4, base * 6.1], [0.12, 0.09, 0.06, 0.04, 0.025],
		[1.0, 0.7, 0.5, 0.3, 0.2])
	heel = D.mix((knock, 0.9), (scuff(rng, 0.02, (2000, 8000)), 0.3), (thud(rng, 0.06, 130), 0.35))
	if v in (1, 3):
		cr = L.creak(rng, 0.14, D.curve([(0, 90), (0.14, 60)], D.ns(0.14)), rng.uniform(700, 1100), 0.012)
		D.place(heel, cr, D.ns(0.05), 0.1)
	toe = D.mix((knock[: D.ns(0.12)], 0.4), (scuff(rng, 0.04, (1500, 7000)), 0.3))
	return compose(rng, heel, toe, (0.05, 0.08), 0.45, 0.35)


@sfx("step_water", "step", variants=STEP_VARIANTS)
def step_water(rng, v):
	heel = D.mix(L.splash(rng, 0.45, 0.35), (thud(rng, 0.08, 90, 200), 0.25))
	toe = L.splash(rng, 0.3, 0.22) * 0.8
	return compose(rng, heel, toe, (0.08, 0.13), 0.5, 0.55)


@sfx("step_ash", "step", variants=STEP_VARIANTS)
def step_ash(rng, v):
	n = D.ns(0.18)
	puff = D.butter(D.white(n, rng), "band", (300, 2500), 2) * L.gamma_env(n, 0.03, 1.2)
	heel = D.mix((thud(rng, 0.09, 100, 220), 0.6), (crunch(rng, 0.12, 900, (400, 3200), 0.3), 0.45), (puff, 0.35))
	toe = D.mix((puff[: D.ns(0.12)], 0.4), (crunch(rng, 0.07, 500, (500, 3500), 0.3), 0.3))
	return compose(rng, heel, toe, (0.06, 0.1), 0.5, 0.36)


@sfx("step_heavy", "step", variants=STEP_VARIANTS, gain_db=3.0)
def step_heavy(rng, v):
	n = D.ns(0.3)
	rattle = D.grains(n, rng, 500 * L.gamma_env(n, 0.04, 1.0), (0.0008, 0.002), (1200, 5000), ring=0.4)
	low = D.norm_peak(D.butter(D.brown(n, rng), "low", 200, 2)) * L.gamma_env(n, 0.01, 1.0)
	heel = D.mix(D.thump(0.3, 150, 62, 0.16, sweep_t=0.015), (L.crack(rng, 0.05, 900, 3500, 4), 0.25), (rattle, 0.3), (low, 0.4))
	toe = D.mix((thud(rng, 0.09, 100), 0.5), (scuff(rng, 0.05, (800, 5000)), 0.3))
	return compose(rng, heel, toe, (0.07, 0.11), 0.45, 0.45)


@sfx("land_soft", "step", variants=3, gain_db=2.0)
def land_soft(rng, v):
	out = np.zeros(D.ns(0.4))
	for i, dt in enumerate((0.0, rng.uniform(0.015, 0.035))):
		foot = D.mix(thud(rng, 0.1, 110, 280), (scuff(rng, 0.06, (1000, 6000)), 0.45))
		D.place(out, foot, D.ns(dt), 1.0 if i == 0 else 0.8)
	D.place(out, L.cloth(rng, 0.18), D.ns(0.01), 0.35)
	return out


@sfx("land_heavy", "step", variants=3, gain_db=5.0)
def land_heavy(rng, v):
	out = np.zeros(D.ns(0.9))
	D.place(out, D.thump(0.6, 140, 45, 0.3, sweep_t=0.02), 0)
	D.place(out, L.rumble(rng, 0.5, 110) * L.gamma_env(D.ns(0.5), 0.02, 1.0), 0, 0.5)
	D.place(out, L.crack(rng, 0.07, 800, 3500, 5), 0, 0.35)
	D.place(out, L.debris(rng, 0.6, 140, (1500, 6000), 0.15, 0.6, 0.02), 0, 0.35)
	D.place(out, L.cloth(rng, 0.25), 0, 0.3)
	D.place(out, thud(rng, 0.1, 100), D.ns(0.03), 0.6)
	return out


@sfx("land_snow", "step", variants=3, gain_db=3.0)
def land_snow(rng, v):
	out = np.zeros(D.ns(0.7))
	D.place(out, crunch(rng, 0.28, 3200, (450, 6500), 0.25), 0, 1.0)
	D.place(out, thud(rng, 0.14, 85, 220), 0, 0.6)
	D.place(out, crunch(rng, 0.2, 2000, (600, 6500), 0.3), D.ns(0.03), 0.6)
	n = D.ns(0.5)
	powder = D.butter(D.white(n, rng), "band", (600, 4000), 2) * L.gamma_env(n, 0.08, 1.2)
	D.place(out, powder, D.ns(0.02), 0.3)
	return out
