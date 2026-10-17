"""Firebending: ignition transients, turbulent roar beds, crackle, explosions."""
from __future__ import annotations

import numpy as np

import dsp as D
import sfxlib as L
from registry import sfx


def burst(rng, dur, peak, sharp, bright=1.0, crack_density=40.0):
	"""Roar burst with a swell envelope + crackle riding on it."""
	n = D.ns(dur)
	env = L.gamma_env(n, peak, sharp)
	r = L.roar(rng, n, env * bright)
	c = L.crackle(rng, n, crack_density * env + 2.0)
	return D.norm_peak(r) * env + c * 0.5 * env


@sfx("fire_ignite", "bending", variants=4)
def fire_ignite(rng, v):
	ig = L.ignite(rng, 0.6, rng.uniform(0.8, 1.1))
	n = D.ns(0.6)
	hiss = D.butter(D.white(n, rng), "band", (3000, 10000), 2) * L.gamma_env(n, 0.04, 1.2) * 0.25
	return D.mix(ig, (L.crackle(rng, n, 120 * np.exp(-D.taxis(n) / 0.12)), 0.6), (hiss, 1.0))


@sfx("fire_blast", "bending", variants=4)
def fire_blast(rng, v):
	dur = rng.uniform(0.75, 0.9)
	n = D.ns(dur)
	b = burst(rng, dur, 0.12, 1.1, 1.2, 60)
	t = D.taxis(n)
	# moving away: brightness falls after the peak
	b = D.tv_filter(b, "lp", D.curve([(0, 9000), (0.15, 7000), (dur, 1500)], n, log=True), 0.7)
	return D.mix((L.ignite(rng, 0.4, 0.7), 0.8), (b, 1.0), (L.whoosh(rng, dur, 200, 2000, 0.9, 0.2, 1.4, 0.5, doppler=0.2), 0.35))


@sfx("fire_whoosh", "bending", variants=4)
def fire_whoosh(rng, v):
	dur = rng.uniform(0.55, 0.7)
	n = D.ns(dur)
	amp, ratio, close = D.passby(n, dur * 0.45, 30.0, 2.0)
	r = L.roar(rng, n, 0.4 + 0.9 * close)
	r = D.tv_filter(r, "bp", 700 * ratio * (0.6 + 0.8 * close), 0.6)
	c = L.crackle(rng, n, 30 + 80 * close)
	w = L.whoosh(rng, dur, 250, 2600, 1.0, 0.45, 2.0, 0.3, doppler=0.3)
	return D.mix((D.norm_peak(r) * amp, 1.0), (c * amp, 0.4), (w, 0.4))


@sfx("fire_impact", "impact", variants=4)
def fire_impact(rng, v):
	dur = 0.9
	n = D.ns(dur)
	t = D.taxis(n)
	tail = burst(rng, dur, 0.03, 0.9, 1.0, 90)
	hiss = D.butter(D.white(n, rng), "band", (2500, 9000), 2) * L.gamma_env(n, 0.05, 1.0) * 0.3
	return D.mix((L.ignite(rng, 0.45, 0.6), 0.8), (tail, 0.8), (hiss, 1.0), (D.thump(0.3, 140, 60, 0.15), 0.5),
		(L.crackle(rng, n, 160 * np.exp(-t / 0.2)), 0.4))


@sfx("fire_explosion", "impact", variants=3, gain_db=2.0)
def fire_explosion(rng, v):
	dur = 2.4
	n = D.ns(dur)
	t = D.taxis(n)
	boom = D.thump(1.4, 70, 26, 0.9, sweep_t=0.05)
	ig = L.ignite(rng, 1.2, 2.2)
	r = L.roar(rng, n, 1.6 * np.exp(-t / 0.6) + 0.35 * np.exp(-t / 1.6), flicker=0.25)
	r = D.norm_peak(r) * L.gamma_env(n, 0.06, 0.8) * (0.6 * np.exp(-t / 0.5) + 0.4 * np.exp(-t / 1.5))
	cr = L.crackle(rng, n, 220 * np.exp(-t / 0.6) + 10, pop=0.6) * (0.2 + 0.8 * np.exp(-t / 0.6))
	deb = L.debris(rng, dur, 120, (1000, 5000), 0.6, 0.5, 0.1)
	low = D.butter(D.brown(n, rng), "low", 120, 2)
	low = D.norm_peak(low) * L.gamma_env(n, 0.08, 1.0) * np.exp(-t / 0.8)
	return D.mix((boom, 1.0), (ig, 0.7), (r, 0.8), (cr, 0.5), (deb, 0.25), (low, 0.6))


@sfx("fire_loop", "loop", loop=(5.0, 0.8))
def fire_loop(rng, v):
	dur = 5.8
	n = D.ns(dur)
	r = L.roar(rng, n, 0.6 + 0.1 * D.smooth_noise(n, 1.5, rng), flicker=0.45)
	c = L.crackle(rng, n, 22 + 18 * (0.5 + 0.5 * D.smooth_noise(n, 0.8, rng)))
	hiss = D.butter(D.white(n, rng), "band", (3000, 9000), 2) * 0.03
	return D.norm_peak(r) * 0.9 + c * 0.6 + hiss


@sfx("fire_charge_loop", "loop", loop=(3.0, 0.5), gain_db=2.0)
def fire_charge_loop(rng, v):
	dur = 3.5
	n = D.ns(dur)
	t = D.taxis(n)
	r = L.roar(rng, n, 1.0, flicker=0.22)
	pulse = 0.75 + 0.25 * np.sin(2 * np.pi * 4.0 * t)
	whine = D.tv_filter(D.white(n, rng), "bp", 620 * (1 + 0.03 * np.sin(2 * np.pi * 4.0 * t)), 25.0) * 3.0
	whine2 = D.tv_filter(D.white(n, rng), "bp", 1240, 30.0) * 1.5
	c = L.crackle(rng, n, 45, pop=0.5)
	return D.norm_peak(r) * pulse + (whine + whine2) * 0.35 * pulse + c * 0.6


@sfx("fire_ring", "bending", variants=2)
def fire_ring(rng, v):
	dur = 1.3
	n = D.ns(dur)
	t = D.taxis(n)
	env = L.gamma_env(n, 0.35, 1.4)
	circ = 0.7 + 0.3 * np.sin(2 * np.pi * D.phase(D.curve([(0, 6), (dur, 2)], n), n))
	r = L.roar(rng, n, env * 1.3 * circ)
	w = L.whoosh(rng, dur, 200, 2400, 0.9, 0.3, 1.5, 0.4, doppler=0.15)
	return D.mix((L.ignite(rng, 0.4, 0.8), 0.6), (D.norm_peak(r) * env, 1.0), (w, 0.35),
		(L.crackle(rng, n, 80 * env + 5), 0.5))


# --- Lightning Generation (bending_fire module) ---------------------------------------

def _zaps(rng, n, density, band=(1800.0, 9000.0)):
	"""Electric arcing: short bursts of noise chopped at a buzzing rate (a few ms to
	40 ms each) - harsher and more mechanical than fuel crackle."""
	out = np.zeros(n)
	ev = D.dust(n, density, rng, amp_exp=1.4, signed=False)
	for i in np.nonzero(ev)[0]:
		m = D.ns(rng.uniform(0.004, 0.04))
		tt = D.taxis(m)
		gate = (np.sin(2 * np.pi * rng.uniform(90.0, 260.0) * tt) > rng.uniform(-0.3, 0.4)).astype(float)
		seg = D.white(m, rng) * gate * D.exp_decay(m, max(0.006, m / D.SR * 1.5))
		D.place(out, seg, int(i), float(ev[i]))
	return D.butter(out, "band", band, 2)


def _buzz(rng, n, f0, bright=1.0):
	"""Arc hum: two detuned saws through a wandering band-pass."""
	t = D.taxis(n)
	vib = 1.0 + 0.01 * D.smooth_noise(n, 6.0, rng)
	x = D.saw(f0 * vib, n) + 0.7 * D.saw(f0 * 1.503 * vib, n) + 0.25 * D.square(f0 * 0.5, n)
	f = 1400.0 * bright * (1.0 + 0.35 * D.smooth_noise(n, 3.0, rng))
	return D.tv_filter(x, "bp", np.clip(f, 500.0, 6000.0), 1.4) * (0.75 + 0.25 * np.sin(2 * np.pi * 7.0 * t))


@sfx("fire_lightning", "bending", variants=2, gain_db=2.0)
def fire_lightning(rng, v):
	"""The bolt: a split-second crack, a tearing electric rip, then a short rolling thunder."""
	dur = 2.2
	n = D.ns(dur)
	t = D.taxis(n)
	k = D.ns(0.006)
	crack = D.butter(D.white(k, rng), "high", 1500.0, 2) * D.exp_decay(k, 0.006)
	y = np.zeros(n)
	D.place(y, crack, 0, 1.0)
	rip = _zaps(rng, n, 900.0 * np.exp(-t / 0.08) + 4.0, (1200.0, 10000.0)) * 3.0
	buzz = _buzz(rng, n, 118.0, 1.6) * np.exp(-t / 0.18)
	low = D.butter(D.brown(n, rng), "low", 170.0, 2)
	rumble = D.norm_peak(low) * L.gamma_env(n, 0.16, 1.2) * np.exp(-t / 0.7) * (0.7 + 0.3 * D.smooth_noise(n, 5.0, rng))
	boom = D.thump(0.9, 95, 32, 0.6, sweep_t=0.04)
	tail = L.sizzle(rng, dur) * np.exp(-t / 0.35) * 0.25
	return D.mix((y, 1.0), (D.norm_peak(rip), 0.8), (D.norm_peak(buzz), 0.45), (rumble, 0.8), (boom, 0.55), (tail, 0.5))


@sfx("fire_lightning_crackle", "bending", variants=3)
def fire_lightning_crackle(rng, v):
	"""Lightning crackling at the fingertips (full charge cue, a fizzled charge)."""
	dur = 0.6
	n = D.ns(dur)
	t = D.taxis(n)
	z = _zaps(rng, n, 260.0 * np.exp(-t / 0.14) + 6.0)
	b = _buzz(rng, n, 140.0, 1.3) * L.gamma_env(n, 0.02, 1.0) * np.exp(-t / 0.12)
	snap = L.crack(rng, 0.1, 2500.0, 9000.0, 5, 1.6)
	return D.mix((D.norm_peak(z), 1.0), (D.norm_peak(b), 0.4), (snap, 0.5))


@sfx("fire_lightning_loop", "loop", loop=(3.0, 0.5))
def fire_lightning_loop(rng, v):
	"""Charging: a steady electric hum with irregular arcs snapping over it."""
	dur = 3.5
	n = D.ns(dur)
	t = D.taxis(n)
	b = _buzz(rng, n, 104.0, 1.0) * (0.75 + 0.25 * D.smooth_noise(n, 2.0, rng))
	z = _zaps(rng, n, 18.0 + 14.0 * (0.5 + 0.5 * D.smooth_noise(n, 1.2, rng)))
	whine = D.sine(3150.0 * (1.0 + 0.004 * np.sin(2 * np.pi * 5.0 * t)), n) * 0.04
	hum = D.sine(52.0, n) * 0.12
	return D.norm_peak(b) * 0.7 + D.norm_peak(z) * 0.6 + whine + hum


@sfx("fire_extinguish", "bending", variants=3)
def fire_extinguish(rng, v):
	dur = 1.1
	n = D.ns(dur)
	t = D.taxis(n)
	r = L.roar(rng, n, 0.9 * np.exp(-t / 0.15))
	sz = L.sizzle(rng, dur) * L.gamma_env(n, 0.12, 1.0)
	steam = D.tv_filter(D.white(n, rng), "bp", D.curve([(0, 5000), (dur, 2500)], n, log=True), 1.5) * L.gamma_env(n, 0.25, 1.2)
	return D.mix((D.norm_peak(r) * np.exp(-t / 0.2), 0.6), (sz, 0.6), (steam, 0.5))
