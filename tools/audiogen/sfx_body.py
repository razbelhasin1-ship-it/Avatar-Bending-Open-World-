"""Body / martial-arts combat sounds: whooshes, punches, kicks, blocks, falls, parry."""
from __future__ import annotations

import numpy as np

import dsp as D
import instruments as I
import sfxlib as L
from registry import sfx


@sfx("whoosh_light", "body", variants=5)
def whoosh_light(rng, v):
	dur = rng.uniform(0.2, 0.3)
	w = L.whoosh(rng, dur, rng.uniform(300, 480), rng.uniform(2600, 4000), rng.uniform(0.9, 1.4), rng.uniform(0.4, 0.55),
		2.6, 0.3, doppler=0.12)
	return D.mix(w, (L.cloth(rng, dur * 0.8, 1.2), 0.25))


@sfx("whoosh_heavy", "body", variants=4)
def whoosh_heavy(rng, v):
	dur = rng.uniform(0.42, 0.55)
	w = L.whoosh(rng, dur, rng.uniform(140, 200), rng.uniform(1300, 1900), 1.0, 0.5, 2.2, 0.6, doppler=0.18)
	low = D.butter(D.brown(D.ns(dur), rng), "low", 220, 2) * L.gamma_env(D.ns(dur), dur * 0.5, 2.0)
	return D.mix(w, (D.norm_peak(low), 0.35), (L.cloth(rng, dur, 0.9), 0.3))


def _impact(rng, f_body, slap_band, crunch_amt, dur=0.35):
	n = D.ns(dur)
	y = D.thump(dur, f_body * 2.0, f_body, dur * 0.3, sweep_t=0.012)
	k = D.ns(0.045)
	slap = D.butter(D.white(k, rng), "band", slap_band, 2) * D.exp_decay(k, 0.03)
	D.place(y, slap, 0, 0.9)
	if crunch_amt > 0:
		D.place(y, L.crack(rng, 0.04, 900, 3200, 4), D.ns(0.002), crunch_amt)
	tail = D.butter(D.white(n, rng), "band", (200, 1200), 2) * D.exp_decay(n, 0.08) * 0.15
	return y + tail


@sfx("punch_impact", "impact", variants=5)
def punch_impact(rng, v):
	y = _impact(rng, rng.uniform(105, 140), (350, 2600), 0.25)
	return D.mix(y, (L.cloth(rng, 0.12, 1.0), 0.2))


@sfx("kick_impact", "impact", variants=4)
def kick_impact(rng, v):
	y = _impact(rng, rng.uniform(80, 100), (250, 2000), 0.2, 0.45)
	return D.mix(y, (L.whoosh(rng, 0.2, 400, 1800, 1.0, 0.2, 2.0, 0.3), 0.3), (L.cloth(rng, 0.18, 0.9), 0.3, 0.01))


@sfx("hit_flesh", "impact", variants=4)
def hit_flesh(rng, v):
	n = D.ns(0.22)
	slap = D.butter(D.white(n, rng), "band", (500, 3500), 2) * D.exp_decay(n, 0.05)
	wet = D.butter(D.white(n, rng), "band", (900, 2200), 2) * L.gamma_env(n, 0.012, 1.0) * 0.6
	return D.mix(D.thump(0.25, 220, 120, 0.08, sweep_t=0.01), (slap, 0.8), (wet, 0.5), (L.crack(rng, 0.03, 1200, 3500, 3), 0.12))


@sfx("block_impact", "impact", variants=4)
def block_impact(rng, v):
	y = D.thump(0.25, 260, 150, 0.07, sweep_t=0.008)
	knock = I.woodblock(rng.uniform(480, 620), rng, 0.6, t60=0.05)
	snap = D.butter(D.white(D.ns(0.02), rng), "band", (1500, 6000), 2) * D.exp_decay(D.ns(0.02), 0.012)
	return D.mix((y, 0.8), (knock, 0.35), (snap, 0.5), (L.cloth(rng, 0.14, 1.1), 0.3))


@sfx("body_fall", "impact", variants=3)
def body_fall(rng, v):
	out = np.zeros(D.ns(1.0))
	D.place(out, D.thump(0.5, 120, 55, 0.22, sweep_t=0.015), 0)
	D.place(out, D.thump(0.4, 150, 70, 0.15, sweep_t=0.012), D.ns(rng.uniform(0.07, 0.12)), 0.7)
	n = D.ns(0.45)
	scrape = D.butter(D.white(n, rng), "band", (600, 4000), 2) * L.gamma_env(n, 0.12, 1.2)
	D.place(out, scrape, D.ns(0.1), 0.25)
	D.place(out, L.cloth(rng, 0.35, 0.8), 0, 0.4)
	D.place(out, L.debris(rng, 0.5, 60, (1500, 5000), 0.15, 0.5, 0.01), 0, 0.15)
	return out


@sfx("dodge_whoosh", "body", variants=3)
def dodge_whoosh(rng, v):
	dur = rng.uniform(0.32, 0.4)
	w = L.whoosh(rng, dur, 220, 2200, 0.9, 0.45, 2.0, 0.45, doppler=0.2)
	n = D.ns(dur)
	flutter = L.cloth(rng, dur, 1.0) * (0.6 + 0.4 * np.sin(2 * np.pi * 26 * D.taxis(n)))
	foot = D.butter(D.white(D.ns(0.06), rng), "band", (1000, 6000), 2) * L.gamma_env(D.ns(0.06), 0.015, 1.4)
	return D.mix(w, (flutter, 0.4), (foot, 0.3, dur * 0.75))


@sfx("jump", "body", variants=3)
def jump(rng, v):
	push = D.mix(D.butter(D.white(D.ns(0.07), rng), "band", (700, 5000), 2) * L.gamma_env(D.ns(0.07), 0.015, 1.4),
		(D.thump(0.12, 160, 90, 0.05), 0.4))
	w = L.whoosh(rng, 0.3, 400, 2400, 1.1, 0.35, 2.0, 0.25)
	return D.mix(push, (w, 0.55, 0.02), (L.cloth(rng, 0.25, 1.0), 0.35, 0.02))


@sfx("parry", "impact", variants=3, gain_db=1.0)
def parry(rng, v):
	f = rng.uniform(1650, 2100)
	ring = I.bell(f, 0.9, rng, "glass", 0.7, t60=0.6)
	ring2 = I.bell(f * 1.5, 0.6, rng, "glass", 0.4, t60=0.35)
	snap = D.butter(D.white(D.ns(0.015), rng), "high", 2500, 2) * D.exp_decay(D.ns(0.015), 0.01)
	w = L.whoosh(rng, 0.25, 800, 5000, 1.2, 0.2, 2.0, 0.1)
	thud = D.thump(0.2, 240, 140, 0.06, sweep_t=0.008)
	return D.mix((ring, 0.45), (ring2, 0.2), (snap, 0.6), (w, 0.35), (thud, 0.5))
