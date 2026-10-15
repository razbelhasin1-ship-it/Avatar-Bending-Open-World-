"""Creature vocalisations (source-filter voices with formants) and movement."""
from __future__ import annotations

import numpy as np

import dsp as D
import sfxlib as L
from registry import sfx


def outdoor(x, rng, wet=0.12, seconds=1.4):
	ir = D.make_ir(seconds, rng, t60_low=seconds * 0.7, t60_high=seconds * 0.35, predelay=0.03, brightness=5000.0,
		stereo=False, early=4, early_span=0.12)
	return D.reverb(x, ir, wet, 1.0).mean(axis=0)


def env_ahr(n, a, hold, r):
	t = D.taxis(n)
	return np.clip(t / a, 0, 1) ** 1.5 * np.clip((a + hold + r - t) / r, 0, 1) ** 1.2


@sfx("bison_call", "creature", variants=3)
def bison_call(rng, v):
	dur = rng.uniform(2.4, 2.9)
	n = D.ns(dur)
	base = rng.uniform(62, 74)
	f0 = D.curve([(0, base), (dur * 0.25, base * 1.32), (dur * 0.6, base * 1.22), (dur, base * 0.82)], n, log=True)
	open_ = L.gamma_env(n, dur * 0.35, 1.0)
	forms = [(330 + 230 * open_, 4.0, 1.0), (850 + 300 * open_, 6.0, 0.6), (2300, 8.0, 0.18), (240, 5.0, 0.6)]
	amp = env_ahr(n, 0.35, dur - 1.0, 0.65) * (0.85 + 0.15 * D.smooth_noise(n, 3, rng))
	vo = L.voice(rng, f0, forms, amp, aspiration=0.06, fry=0.08, sub=0.15, jitter=0.006, tilt=900)
	octave = L.voice(rng, f0 * 0.5, [(200, 3.0, 1.0), (520, 5.0, 0.5)], amp, aspiration=0.02, jitter=0.004, tilt=500)
	breath = D.butter(D.white(n, rng), "band", (300, 2500), 2) * amp * 0.05
	return outdoor(D.mix(D.norm_peak(vo), (D.norm_peak(octave), 0.45), (breath, 1.0)), rng, 0.18, 2.0)


@sfx("bison_groan", "creature", variants=3)
def bison_groan(rng, v):
	dur = rng.uniform(1.5, 2.0)
	n = D.ns(dur)
	f0 = D.curve([(0, 58), (dur * 0.3, 62), (dur, 44)], n, log=True) * rng.uniform(0.9, 1.1)
	amp = env_ahr(n, 0.2, dur - 0.7, 0.5)
	forms = [(300, 4.0, 1.0), (700, 6.0, 0.5), (2000, 8.0, 0.12)]
	vo = L.voice(rng, f0, forms, amp, aspiration=0.18, fry=0.55, sub=0.2, jitter=0.015, tilt=700)
	return outdoor(vo, rng, 0.12)


@sfx("dragon_roar", "creature", variants=3, gain_db=2.0)
def dragon_roar(rng, v):
	dur = rng.uniform(1.8, 2.3)
	n = D.ns(dur)
	b = rng.uniform(85, 100)
	f0 = D.curve([(0, b * 0.8), (0.25, b * 1.5), (dur * 0.55, b * 1.3), (dur, b * 0.75)], n, log=True)
	open_ = L.gamma_env(n, dur * 0.35, 0.9)
	forms = [(480 + 420 * open_, 3.5, 1.0), (1050 + 550 * open_, 5.0, 0.7), (2600, 7.0, 0.35), (3500, 8.0, 0.2)]
	amp = env_ahr(n, 0.12, dur - 0.7, 0.55) * (0.8 + 0.2 * np.abs(D.smooth_noise(n, 18, rng)))
	vo = L.voice(rng, f0, forms, amp, aspiration=0.55, fry=0.35, sub=0.6, grit=0.7, jitter=0.03, tilt=1800)
	low = L.voice(rng, f0 * 0.5, [(260, 3.0, 1.0), (650, 4.0, 0.5)], amp, aspiration=0.2, fry=0.5, sub=0.3, grit=0.4)
	fire = L.roar(rng, n, amp * 0.8, flicker=0.3)
	return outdoor(D.mix(D.norm_peak(vo), (D.norm_peak(low), 0.55), (D.norm_peak(fire) * amp, 0.25)), rng, 0.2, 2.2)


@sfx("wing_flap_large", "creature", variants=4, gain_db=-2.0)
def wing_flap_large(rng, v):
	dur = 0.6
	n = D.ns(dur)
	push = D.butter(D.brown(n, rng), "low", 300, 2)
	push = D.norm_peak(push) * L.gamma_env(n, 0.07, 1.6)
	leather = L.cloth(rng, 0.35, 0.7) * (0.6 + 0.4 * np.sin(2 * np.pi * 34 * D.taxis(D.ns(0.35))))
	snap = D.butter(D.white(D.ns(0.03), rng), "band", (600, 3500), 2) * D.exp_decay(D.ns(0.03), 0.02)
	return D.mix((push, 1.0), (leather, 0.5, 0.02), (snap, 0.4, 0.07), (D.thump(0.3, 70, 40, 0.15), 0.4, 0.05))


@sfx("dog_bark", "creature", variants=4)
def dog_bark(rng, v):
	dur = 0.5
	n = D.ns(dur)
	b = rng.uniform(140, 170)
	f0 = D.curve([(0, b * 0.9), (0.06, b * 1.25), (0.25, b * 0.8), (dur, b * 0.7)], n, log=True)
	shape = D.curve([(0, 0.0), (0.05, 1.0), (0.2, 0.4), (dur, 0.2)], n)
	forms = [(420 + 330 * shape, 3.5, 1.0), (1100 + 300 * shape, 5.0, 0.6), (2500, 7.0, 0.25)]
	amp = env_ahr(n, 0.015, 0.12, 0.22)
	vo = L.voice(rng, f0, forms, amp, aspiration=0.25, fry=0.15, sub=0.25, grit=0.35, jitter=0.02)
	chest = D.thump(0.2, 110, 70, 0.08)
	return outdoor(D.mix(D.norm_peak(vo), (chest, 0.35)), rng, 0.15)


@sfx("dog_growl", "creature", variants=3)
def dog_growl(rng, v):
	dur = rng.uniform(1.3, 1.6)
	n = D.ns(dur)
	f0 = D.curve([(0, 70), (dur * 0.5, 82), (dur, 66)], n, log=True) * rng.uniform(0.92, 1.08)
	amp = env_ahr(n, 0.15, dur - 0.5, 0.35) * (0.75 + 0.25 * np.sin(2 * np.pi * 21 * D.taxis(n)) ** 2)
	forms = [(360, 3.5, 1.0), (900, 5.0, 0.5), (2300, 6.0, 0.18)]
	vo = L.voice(rng, f0, forms, amp, aspiration=0.35, fry=0.75, sub=0.3, grit=0.3, jitter=0.03, tilt=900)
	return outdoor(vo, rng, 0.1)


@sfx("badgermole_snort", "creature", variants=3)
def badgermole_snort(rng, v):
	out = np.zeros(D.ns(0.7))
	t0 = 0.0
	for k in range(2 if v != 1 else 3):
		dur = rng.uniform(0.12, 0.18)
		n = D.ns(dur)
		nz = D.white(n, rng)
		snort = D.formants(nz, [(rng.uniform(700, 900), 4.0, 1.0), (rng.uniform(1800, 2300), 6.0, 0.6), (300, 3.0, 0.5)])
		snort *= L.gamma_env(n, dur * 0.25, 1.4)
		grunt = L.voice(rng, np.full(n, rng.uniform(85, 105)), [(400, 4, 1.0), (900, 5, 0.4)], L.gamma_env(n, dur * 0.3, 1.5),
			aspiration=0.4, fry=0.5)
		D.place(out, D.norm_peak(snort) * 0.8 + D.norm_peak(grunt) * 0.35, D.ns(t0))
		t0 += dur + rng.uniform(0.04, 0.09)
	return out


@sfx("badgermole_dig", "creature", variants=3, gain_db=-1.0)
def badgermole_dig(rng, v):
	dur = 1.3
	out = np.zeros(D.ns(dur + 0.3))
	t = 0.0
	while t < dur:
		sl = rng.uniform(0.12, 0.2)
		n = D.ns(sl)
		scrape = D.butter(D.white(n, rng), "band", (700, 4500), 2) * L.gamma_env(n, sl * 0.3, 1.3)
		dirt = D.grains(n, rng, 900 * L.gamma_env(n, sl * 0.4, 1.0), (0.0008, 0.003), (500, 4000))
		stroke = D.mix((scrape, 0.5), (dirt, 0.9), (D.thump(0.12, 120, 70, 0.05), 0.4))
		D.place(out, stroke, D.ns(t), rng.uniform(0.6, 1.0))
		t += sl + rng.uniform(0.04, 0.12)
	n = out.shape[0]
	fall = D.grains(n, rng, 160, (0.002, 0.006), (200, 1500)) * 0.25
	return out + fall


@sfx("creature_step_heavy", "step", variants=5, gain_db=5.0)
def creature_step_heavy(rng, v):
	thump = D.saturate(D.thump(0.6, rng.uniform(85, 100), rng.uniform(38, 46), 0.25, sweep_t=0.025) * 2.5, 1.0)
	pad = L.impact_core(rng, 0.2, (150, 1600), 0.07)
	punch = D.thump(0.2, 240, 130, 0.07, sweep_t=0.01)
	rum = L.rumble(rng, 0.5, 140) * L.gamma_env(D.ns(0.5), 0.03, 1.0)
	grit = D.grains(D.ns(0.3), rng, 400 * L.gamma_env(D.ns(0.3), 0.03, 1.0), (0.001, 0.003), (700, 4500))
	y = D.mix((thump, 0.5), (pad, 0.6), (punch, 0.45), (rum, 0.4), (grit, 0.35),
		(L.debris(rng, 0.5, 60, (1000, 4000), 0.1, 0.5, 0.02), 0.25))
	return D.saturate(D.norm_peak(y) * 1.6, 1.0)
