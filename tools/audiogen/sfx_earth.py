"""Earthbending: sub thumps, rock fractures, grinding pillars, debris and quakes."""
from __future__ import annotations

import numpy as np

import dsp as D
import sfxlib as L
from registry import sfx


def sub_thump(rng, dur=0.7, f0=75.0, f1=34.0, t60=0.45):
	"""Ground thump: saturated sub sweep (harmonics keep it audible on small
	speakers) + a mid-bass punch layer + a noisy body burst."""
	y = D.saturate(D.thump(dur, f0, f1, t60 * 0.6, sweep_t=0.03) * 2.5, 1.0)
	n = y.shape[0]
	punch = D.thump(min(dur, 0.25), f0 * 2.6, f0 * 1.5, 0.09, sweep_t=0.012)
	low = D.butter(D.brown(n, rng), "low", 260, 2) * L.gamma_env(n, 0.015, 1.0)
	core = L.impact_core(rng, min(dur, 0.35), (120, 1400), 0.12)
	return D.mix((y, 0.5), (punch, 0.45), (D.norm_peak(low), 0.45), (core, 0.55))


def glue(x, drive=1.8):
	"""Soft saturation of a whole layered impact: rounds the stacked transient
	peaks so the sound is dense and loud without hard limiting."""
	return D.saturate(D.norm_peak(x) * drive, 1.0)


def dust_hiss(rng, dur=0.8, delay=0.05):
	n = D.ns(dur)
	return D.butter(D.white(n, rng), "band", (1500, 7000), 2) * L.gamma_env(n, delay + 0.08, 1.1) * 0.25


def rock_chunk(rng, scale=1.0):
	"""One rock hitting rock/ground: small thud + fracture."""
	return D.mix((D.thump(0.18, 200 / scale, 110 / scale, 0.06 * scale, sweep_t=0.01), 0.6),
		(L.crack(rng, 0.06, 600 / scale, 3500 / scale, 4), 0.6))


@sfx("earth_stomp", "bending", variants=4, gain_db=1.0)
def earth_stomp(rng, v):
	dur = 0.9
	return glue(D.mix(sub_thump(rng, dur, rng.uniform(70, 85), rng.uniform(30, 36), 0.4),
		(L.crack(rng, 0.1, 500, 2500, 6), 0.7, 0.004), (L.rumble(rng, 0.7, 90) * L.gamma_env(D.ns(0.7), 0.04, 1.0), 0.4),
		(L.debris(rng, 0.7, 90, (1200, 5000), 0.18, 0.6, 0.05), 0.35), (dust_hiss(rng, 0.6), 0.7)), 2.0)


@sfx("earth_raise", "bending", variants=3)
def earth_raise(rng, v):
	dur = rng.uniform(0.9, 1.1)
	n = D.ns(dur)
	env = L.gamma_env(n, dur * 0.45, 1.3)
	gr = L.grind(rng, dur, D.curve([(0, 25), (dur, 70)], n), (200, 1300)) * env
	rum = L.rumble(rng, dur, 110) * env
	out = D.mix((D.norm_peak(gr), 0.6), (rum, 0.7), (L.crack(rng, 0.09, 500, 2500, 5), 0.5),
		(sub_thump(rng, 0.5, 90, 45, 0.25), 0.5), (L.debris(rng, dur, 70, (1500, 5000), dur * 0.5, 0.5, 0.1), 0.25))
	D.place(out, rock_chunk(rng, 1.2), D.ns(dur * 0.85), 0.5)
	return out


@sfx("earth_launch", "bending", variants=3)
def earth_launch(rng, v):
	w = L.whoosh(rng, 0.6, 140, 1100, 0.9, 0.45, 2.0, 0.7, doppler=0.2)
	return D.mix((L.crack(rng, 0.12, 400, 2200, 6), 0.7), (sub_thump(rng, 0.45, 95, 50, 0.2), 0.6), (w, 0.6, 0.06),
		(L.debris(rng, 0.6, 120, (1500, 6000), 0.15, 0.6), 0.3))


@sfx("earth_impact", "impact", variants=4, gain_db=1.0)
def earth_impact(rng, v):
	return glue(D.mix(sub_thump(rng, 0.9, rng.uniform(65, 80), 32, 0.5), (L.crack(rng, 0.14, 450, 3000, 7), 1.0),
		(rock_chunk(rng, 0.8), 0.5, 0.015), (L.debris(rng, 1.0, 180, (1200, 6000), 0.25, 0.6, 0.03), 0.5),
		(dust_hiss(rng, 0.9, 0.08), 1.0)), 2.0)


@sfx("earth_wall_rise", "bending", variants=3)
def earth_wall_rise(rng, v):
	dur = rng.uniform(1.25, 1.45)
	n = D.ns(dur)
	t = D.taxis(n)
	env = np.clip(t / 0.15, 0, 1) * np.clip((dur * 0.88 - t) / 0.06, 0, 1)
	gr = L.grind(rng, dur, D.curve([(0, 35), (dur, 55)], n), (180, 1100)) * env
	rum = L.rumble(rng, dur, 120, 5.0) * (0.4 + 0.6 * env)
	out = D.mix((D.norm_peak(gr), 0.55), (rum, 0.8), (sub_thump(rng, 0.5, 80, 40, 0.3), 0.5),
		(L.debris(rng, dur, 100, (1200, 5500), dur, 0.5, 0.1), 0.2))
	stop = dur * 0.86
	D.place(out, sub_thump(rng, 0.6, 95, 40, 0.3), D.ns(stop), 0.7)
	D.place(out, L.crack(rng, 0.1, 500, 2600, 5), D.ns(stop), 0.4)
	D.place(out, L.debris(rng, 0.6, 140, (1500, 6000), 0.15, 0.6), D.ns(stop + 0.02), 0.3)
	return out


@sfx("earth_crumble", "impact", variants=3)
def earth_crumble(rng, v):
	dur = 1.6
	out = np.zeros(D.ns(dur + 0.4))
	t = 0.0
	while t < dur * 0.7:
		D.place(out, L.crack(rng, 0.1, 400, 2600, 5), D.ns(t), rng.uniform(0.3, 0.7))
		if rng.random() < 0.5:
			D.place(out, rock_chunk(rng, rng.uniform(0.8, 1.5)), D.ns(t + rng.uniform(0.0, 0.05)), rng.uniform(0.2, 0.5))
		t += rng.uniform(0.04, 0.16)
	D.place(out, L.debris(rng, dur, 260, (900, 5500), 0.5, 0.6, 0.03), 0, 0.45)
	D.place(out, L.rumble(rng, dur, 100) * L.gamma_env(D.ns(dur), 0.3, 1.2), 0, 0.6)
	D.place(out, dust_hiss(rng, dur, 0.3), 0, 0.8)
	return out


@sfx("earth_quake", "impact", variants=2, gain_db=1.0)
def earth_quake(rng, v):
	dur = 3.2
	n = D.ns(dur)
	env = L.gamma_env(n, 0.7, 1.0)
	rum = D.mix((L.rumble(rng, dur, 70, 4.0), 1.0), (L.rumble(rng, dur, 160, 7.0), 0.4)) * env
	t = D.taxis(n)
	shake = np.sin(2 * np.pi * D.phase(D.curve([(0, 38), (dur, 28)], n), n)) * env * (0.6 + 0.4 * D.smooth_noise(n, 6, rng))
	out = D.mix((rum, 1.0), (shake, 0.35), (sub_thump(rng, 1.0, 60, 28, 0.7), 0.7))
	tt = 0.1
	while tt < dur * 0.8:
		D.place(out, L.crack(rng, 0.1, 350, 2200, 5), D.ns(tt), 0.35 * float(np.interp(tt, t, env)))
		tt += rng.uniform(0.08, 0.3)
	D.place(out, L.debris(rng, dur, 140, (1000, 5000), 1.2, 0.5, 0.2), 0, 0.3)
	return out


@sfx("earth_spikes", "bending", variants=3)
def earth_spikes(rng, v):
	out = np.zeros(D.ns(1.1))
	count = int(rng.integers(3, 6))
	t = 0.0
	for i in range(count):
		spike = D.mix((L.crack(rng, 0.09, 600, 3200, 5), 0.8), (sub_thump(rng, 0.35, 110, 55, 0.12), 0.5),
			(L.grind(rng, 0.15, 60, (300, 1600)) * L.gamma_env(D.ns(0.15), 0.03, 1.0), 0.15))
		D.place(out, spike, D.ns(t), 0.9 - 0.08 * i)
		t += rng.uniform(0.06, 0.1)
	D.place(out, L.debris(rng, 0.9, 150, (1500, 6000), 0.25, 0.6, 0.05), 0, 0.3)
	return out


@sfx("earth_armor", "bending", variants=2)
def earth_armor(rng, v):
	dur = 0.9
	out = np.zeros(D.ns(dur + 0.4))
	t = 0.0
	while t < dur:
		D.place(out, rock_chunk(rng, rng.uniform(1.3, 2.2)), D.ns(t), rng.uniform(0.2, 0.45) * (0.5 + t / dur))
		t += rng.uniform(0.025, 0.07) * (1.3 - t / dur)
	D.place(out, sub_thump(rng, 0.5, 100, 50, 0.25), D.ns(dur), 0.7)
	D.place(out, L.grind(rng, dur, 40, (300, 1500)) * L.gamma_env(D.ns(dur), dur * 0.6, 1.2), 0, 0.08)
	return out


@sfx("rock_debris", "impact", variants=4, gain_db=-2.0)
def rock_debris(rng, v):
	dur = 0.9
	n = D.ns(dur)
	t = D.taxis(n)
	# Bouncing pebbles: a few density bursts decaying like bounces.
	dens = np.zeros(n)
	for k, (t0, a) in enumerate([(0.0, 1.0), (0.18, 0.5), (0.32, 0.3), (0.43, 0.15)]):
		dens += 320 * a * np.exp(-np.maximum(t - t0, 0) / 0.05) * (t >= t0)
	y = D.grains(n, rng, dens, (0.0008, 0.003), (1200, 7000), ring=0.7)
	return D.mix(y, (rock_chunk(rng, 1.5), 0.3))
