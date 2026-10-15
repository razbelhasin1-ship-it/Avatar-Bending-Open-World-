"""Waterbending: bubble-synthesis liquids, splashes, surges, and crystalline ice."""
from __future__ import annotations

import numpy as np

import dsp as D
import instruments as I
import sfxlib as L
from registry import sfx


def rush(rng, n, intensity, bright=1.0):
	"""Rushing water mass: band-limited turbulent noise whose brightness follows intensity."""
	src = D.pink(n, rng) * 2.0 + D.white(n, rng) * 0.3
	cut = 400 + 3500 * np.clip(intensity, 0, 1.5) * bright
	y = D.tv_filter(src, "lp", cut, 0.7) - 0.6 * D.tv_filter(src, "lp", 180, 0.7)
	y *= 0.7 + 0.3 * D.smooth_noise(n, 14, rng)
	return D.norm_peak(y) * intensity


@sfx("water_whip", "bending", variants=4)
def water_whip(rng, v):
	dur = rng.uniform(0.6, 0.75)
	n = D.ns(dur)
	env = L.gamma_env(n, dur * 0.4, 2.0)
	wet = L.flow(rng, n, env, bubbly=0.8)
	w = L.whoosh(rng, dur, 300, 2800, 1.1, 0.4, 2.2, 0.3, doppler=0.2)
	crack_t = dur * 0.62
	snap = D.mix((L.crack(rng, 0.05, 1500, 6000, 4), 0.5), (L.splash(rng, 0.45, 0.45), 0.8))
	return D.mix((w, 0.7), (D.norm_peak(wet), 0.45), (snap, 0.9, crack_t))


@sfx("water_splash", "impact", variants=4)
def water_splash(rng, v):
	return D.mix(L.splash(rng, 1.1, rng.uniform(0.9, 1.2)), (D.thump(0.25, 120, 60, 0.12), 0.35))


@sfx("water_blast", "bending", variants=4)
def water_blast(rng, v):
	dur = 0.85
	n = D.ns(dur)
	env = L.gamma_env(n, 0.12, 1.2)
	jet = rush(rng, n, env * 1.1, 1.2)
	b = D.bubbles(n, rng, 500 * env, (500, 3000), (0.015, 0.05), (0.5, 1.5))
	w = L.whoosh(rng, dur, 250, 2400, 1.0, 0.25, 1.6, 0.4, doppler=0.25)
	return D.mix((jet, 0.9), (b, 0.6), (w, 0.4), (L.splash(rng, 0.5, 0.6), 0.5, 0.02))


@sfx("water_shield_loop", "loop", loop=(4.0, 0.6))
def water_shield_loop(rng, v):
	dur = 4.6
	n = D.ns(dur)
	t = D.taxis(n)
	swirlmod = 0.75 + 0.25 * np.sin(2 * np.pi * 1.6 * t)
	f = L.flow(rng, n, swirlmod, bubbly=1.3)
	r = rush(rng, n, 0.4 * swirlmod, 0.7)
	sw = L.swirl(rng, n, 1.6, 700, 0.8, 1.5) * 0.15
	return D.norm_peak(f) * 0.8 + r * 0.6 + sw


@sfx("water_surge", "bending", variants=3)
def water_surge(rng, v):
	dur = 1.9
	n = D.ns(dur)
	t = D.taxis(n)
	rise = np.clip(t / 1.1, 0, 1) ** 1.6 * np.exp(-np.maximum(t - 1.15, 0) / 0.35)
	r = rush(rng, n, rise * 1.2, 1.0)
	b = D.bubbles(n, rng, 600 * rise, (250, 2500), (0.02, 0.08), (0.3, 1.2))
	low = D.norm_peak(D.butter(D.brown(n, rng), "low", 180, 2)) * rise
	crash = D.mix(L.splash(rng, 0.9, 1.4), (D.thump(0.4, 110, 50, 0.25), 0.5))
	return D.mix((r, 1.0), (b, 0.5), (low, 0.5), (crash, 0.9, 1.05))


@sfx("water_draw", "bending", variants=3)
def water_draw(rng, v):
	dur = 1.25
	n = D.ns(dur)
	t = D.taxis(n)
	swell = L.gamma_env(n, dur * 0.7, 1.6)
	gurgle = D.bubbles(n, rng, 380 * swell, (180, 1600), (0.03, 0.1), (0.4, 1.4))
	suck = D.tv_filter(D.pink(n, rng), "bp", D.curve([(0, 300), (dur, 2600)], n, log=True), 2.0) * swell
	drops = D.bubbles(n, rng, 18 * swell, (1200, 3500), (0.015, 0.04), (2.0, 3.5))
	return D.mix((gurgle, 1.0), (D.norm_peak(suck), 0.35), (drops, 0.6), (L.flow(rng, n, swell * 0.6), 0.3))


@sfx("ice_form", "bending", variants=3)
def ice_form(rng, v):
	dur = 1.05
	n = D.ns(dur)
	t = D.taxis(n)
	grow = np.clip(t / (dur * 0.8), 0, 1) ** 1.3
	crk = D.grains(n, rng, 40 + 900 * grow, (0.0003, 0.001), (2500, 11000), ring=0.6)
	creak = L.creak(rng, dur, 40 + 220 * grow, 2200 + 1800 * rng.random(), 0.006) * grow
	ring = L.ice_ring(rng, 0.9, 2500, 9500, 12)
	shimmer = D.butter(D.white(n, rng), "band", (5000, 12000), 2) * grow * 0.08
	return D.mix((crk, 0.7), (creak, 0.25), (shimmer, 1.0), (ring, 0.35, dur * 0.72),
		(L.crack(rng, 0.06, 2500, 8000, 5), 0.5, dur * 0.72))


@sfx("ice_shatter", "impact", variants=4, gain_db=1.0)
def ice_shatter(rng, v):
	return D.mix((L.crack(rng, 0.12, 1800, 8000, 8, 1.4), 0.6), (L.ice_ring(rng, 0.45, 1500, 9000, 16), 0.6),
		(L.shards(rng, 1.2, 320, 0.3), 0.8, 0.01), (D.thump(0.25, 180, 90, 0.08), 0.4),
		(D.butter(D.white(D.ns(0.3), rng), "band", (3000, 12000), 2) * L.gamma_env(D.ns(0.3), 0.01, 0.8), 0.3))


@sfx("ice_impact", "impact", variants=4)
def ice_impact(rng, v):
	return D.mix((L.crack(rng, 0.08, 2000, 7500, 6, 1.2), 0.9), (D.thump(0.3, 200, 95, 0.1), 0.6),
		(L.ice_ring(rng, 0.45, 2200, 8000, 8), 0.35), (L.shards(rng, 0.6, 70, 0.12), 0.3, 0.01))


@sfx("water_wave", "bending", variants=3, gain_db=1.0)
def water_wave(rng, v):
	dur = 2.3
	n = D.ns(dur)
	t = D.taxis(n)
	swell = np.clip(t / 0.7, 0, 1) ** 2 * np.exp(-np.maximum(t - 0.75, 0) / 0.6)
	r = rush(rng, n, swell * 1.2, 0.9)
	foam = D.butter(D.white(n, rng), "band", (2000, 10000), 2) * np.exp(-np.maximum(t - 0.75, 0) / 0.5) * (t > 0.7) * 0.25
	foam *= 0.6 + 0.4 * np.abs(D.smooth_noise(n, 40, rng))
	b = D.bubbles(n, rng, 700 * np.exp(-np.maximum(t - 0.75, 0) / 0.4) * (t > 0.7), (300, 2800), (0.02, 0.07), (0.4, 1.5))
	crash = D.mix(L.splash(rng, 1.2, 1.6), (D.thump(0.5, 90, 40, 0.3), 0.6))
	return D.mix((r, 1.0), (foam, 1.0), (b, 0.5), (crash, 0.8, 0.72))


@sfx("water_heal_loop", "loop", loop=(5.0, 1.0), gain_db=-2.0)
def water_heal_loop(rng, v):
	dur = 6.0
	n = D.ns(dur)
	f = L.flow(rng, n, 0.35 + 0.1 * D.smooth_noise(n, 0.5, rng), bubbly=0.6)
	f = D.filt(f, "lp", 3000, 0.7)
	shimmer = D.tv_filter(D.white(n, rng), "bp", 5200 * 2 ** (0.3 * D.smooth_noise(n, 0.6, rng)), 6.0) * 0.6
	tones = np.zeros(n)
	# Gentle glassy tones on a D major pentatonic, spaced so the loop stays calm.
	for k, m in enumerate([86, 81, 90, 83, 88, 86]):
		D.place(tones, I.bell(D.midi_hz(m), 2.2, rng, "glass", 0.4, t60=1.8), D.ns(0.2 + k * 0.95))
	return D.norm_peak(f) * 0.6 + shimmer * 0.25 + tones * 0.3
