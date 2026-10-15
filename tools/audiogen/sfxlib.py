"""Higher-level SFX recipes shared by the element/body/creature generators:
whooshes, impacts, debris, fire, water, ice, rock and voice synthesis."""
from __future__ import annotations

import math

import numpy as np
from scipy import signal

import dsp as D
from dsp import SR, TAU


def gamma_env(n: int, t_peak: float, k: float = 2.0, sr: int = SR) -> np.ndarray:
	"""Smooth swell peaking at 1.0 at t_peak: (x e^(1-x))^k."""
	x = D.taxis(n, sr) / max(t_peak, 1e-4)
	return (x * np.exp(1.0 - x)) ** k


# ---------------------------------------------------------------------------
# Air
# ---------------------------------------------------------------------------

def whoosh(rng: np.random.Generator, dur: float, f_lo: float = 250.0, f_hi: float = 2400.0, q: float = 1.1,
		peak: float = 0.45, sharp: float = 2.0, body: float = 0.35, whistle: float = 0.0, doppler: float = 0.0,
		sr: int = SR) -> np.ndarray:
	"""Moving-air whoosh: band-passed noise whose centre frequency and level follow a
	swell; optional resonant whistle and doppler pitch drop after the peak."""
	n = D.ns(dur, sr)
	env = gamma_env(n, peak * dur, sharp, sr)
	fc = f_lo * (f_hi / f_lo) ** env
	if doppler > 0:
		t = D.taxis(n, sr)
		fc = fc * (1.0 + doppler * np.tanh((peak * dur - t) / (0.12 * dur)))
	src = D.white(n, rng)
	# Two cascaded band-passes: a steep moving band is what the ear hears as "swish".
	y = D.tv_filter(D.tv_filter(src, "bp", fc, q, sr=sr), "bp", fc, q * 0.8, sr=sr) * 2.0
	y += 0.35 * D.tv_filter(src, "bp", fc * 2.2, q, sr=sr)
	if body > 0:
		y += body * 0.6 * D.tv_filter(D.pink(n, rng) * 3.0, "lp", fc * 0.45, 0.8, sr=sr)
	if whistle > 0:
		y += whistle * D.tv_filter(D.white(n, rng), "bp", fc * 1.6, 14.0, sr=sr) * env
	return y * env


def air_puff(rng: np.random.Generator, dur: float = 0.25, f: float = 180.0, sr: int = SR) -> np.ndarray:
	"""Low pressure 'thoomp' of displaced air."""
	n = D.ns(dur, sr)
	src = D.brown(n, rng)
	y = D.tv_filter(src, "lp", D.curve([(0, f * 3), (dur * 0.3, f), (dur, f * 0.6)], n, sr, log=True), 1.0, sr=sr)
	return y * gamma_env(n, 0.03, 1.2, sr) + 0.5 * D.thump(dur, f * 0.8, f * 0.4, dur * 0.6, sr)


def swirl(rng: np.random.Generator, n: int, rate: float = 2.5, f_center: float = 900.0, spread: float = 1.2,
		q: float = 2.0, sr: int = SR) -> np.ndarray:
	"""Rotating wind (shields, tornado): resonant bands orbiting in pitch with AM."""
	t = D.taxis(n, sr)
	out = np.zeros(n)
	for i in range(3):
		ph = TAU * rate * (1 + 0.13 * i) * t + rng.uniform(0, TAU)
		fc = f_center * (1.0 + 0.25 * i) * 2 ** (spread * 0.5 * np.sin(ph))
		band = D.tv_filter(D.white(n, rng), "bp", fc, q, sr=sr, block=128)
		out += band * (0.55 + 0.45 * np.sin(ph + 1.2)) / (1 + i * 0.4)
	return out


# ---------------------------------------------------------------------------
# Impacts / earth
# ---------------------------------------------------------------------------

def crack(rng: np.random.Generator, dur: float = 0.12, lo: float = 700.0, hi: float = 4000.0, modes: int = 6,
		bright: float = 1.0, sr: int = SR) -> np.ndarray:
	"""Brittle fracture: broadband snap + short inharmonic ringing."""
	n = D.ns(dur, sr)
	k = D.ns(0.004, sr)
	snap = D.butter(D.white(k, rng), "high", 1200.0 * bright, 2, sr) * D.exp_decay(k, 0.004, sr)
	y = np.zeros(n)
	D.place(y, snap, 0)
	imp = np.zeros(n)
	imp[0] = 1.0
	for _ in range(2):
		imp[rng.integers(1, D.ns(0.006, sr))] = rng.uniform(0.3, 0.8)
	freqs = np.exp(rng.uniform(math.log(lo), math.log(hi), modes))
	decs = rng.uniform(0.015, 0.06, modes) * dur / 0.12
	y += 0.8 * D.modal(imp, freqs, decs, rng.uniform(0.4, 1.0, modes), sr)
	return y


def debris(rng: np.random.Generator, dur: float, density: float = 60.0, band=(1500.0, 6500.0), decay: float = 0.4,
		ring: float = 0.6, delay: float = 0.0, sr: int = SR) -> np.ndarray:
	"""Pebbles / shards raining down: granular pings with decaying density."""
	n = D.ns(dur, sr)
	t = D.taxis(n, sr)
	dens = density * np.exp(-np.maximum(t - delay, 0) / max(decay, 1e-3)) * (t >= delay)
	return D.grains(n, rng, dens, (0.001, 0.004), band, sr, 1.6, ring)


def rumble(rng: np.random.Generator, dur: float, f: float = 90.0, rate: float = 3.0, sr: int = SR) -> np.ndarray:
	"""Low ground rumble with slow random amplitude movement."""
	n = D.ns(dur, sr)
	y = D.butter(D.brown(n, rng), "low", f, 4, sr)
	y = D.norm_peak(y, 1.0) * (0.6 + 0.4 * D.smooth_noise(n, rate, rng, sr))
	return y


def grind(rng: np.random.Generator, dur: float, rate=40.0, f_band=(250.0, 1500.0), sr: int = SR) -> np.ndarray:
	"""Stone-on-stone grinding: a dense rough scrape (many small stick-slip events
	through rock resonances) under slower, larger slips. `rate` scales the
	density of the large slips (events/s)."""
	n = D.ns(dur, sr)
	r = np.broadcast_to(np.asarray(rate, dtype=float), (n,)) * (1 + 0.5 * D.smooth_noise(n, 6, rng, sr))
	fine = D.dust(n, np.maximum(r * 12.0, 50.0), rng, sr, 1.5)
	big = D.dust(n, np.maximum(r, 1.0), rng, sr, 2.5)
	freqs = np.exp(rng.uniform(math.log(f_band[0]), math.log(f_band[1]), 6))
	tex = D.modal(fine * 0.5 + big, freqs, rng.uniform(0.008, 0.025, 6), rng.uniform(0.4, 1.0, 6), sr)
	tex = D.onepole_lp(tex, f_band[1] * 2.0, sr)
	rough = 0.5 + 0.5 * np.abs(D.smooth_noise(n, 35, rng, sr))
	scrape = D.butter(D.white(n, rng), "band", f_band, 2, sr) * rough
	return D.norm_peak(tex) * 0.8 + 0.5 * D.norm_peak(scrape)


def impact_core(rng: np.random.Generator, dur: float = 0.3, band=(120.0, 1600.0), t60: float = 0.14,
		sr: int = SR) -> np.ndarray:
	"""The 'meat' of a heavy impact: a band-limited noise burst with fast decay."""
	n = D.ns(dur, sr)
	y = D.butter(D.white(n, rng), "band", band, 2, sr) * D.exp_decay(n, t60, sr)
	return D.norm_peak(y * np.clip(D.taxis(n, sr) / 0.0015, 0, 1))


def pings(rng: np.random.Generator, n: int, density, f_range=(2500.0, 11000.0), t60_range=(0.02, 0.12),
		sr: int = SR, amp_exp: float = 1.8) -> np.ndarray:
	"""Individually pitched pings (glass/ice fragments): each event gets its own
	random inharmonic pair of partials, so no pitch repeats mechanically."""
	out = np.zeros(n)
	dens = np.broadcast_to(np.asarray(density, dtype=float), (n,))
	k = rng.poisson(float(dens.sum() / sr))
	if k == 0:
		return out
	cdf = np.cumsum(dens)
	cdf /= cdf[-1]
	starts = np.searchsorted(cdf, rng.random(k))
	lo, hi = math.log(f_range[0]), math.log(f_range[1])
	for s in starts:
		f = math.exp(rng.uniform(lo, hi))
		t60 = rng.uniform(*t60_range)
		m = D.ns(t60 * 1.1, sr)
		t = D.taxis(m, sr)
		r2 = rng.uniform(1.9, 2.9)
		p = (np.sin(TAU * f * t) + 0.4 * np.sin(TAU * f * r2 * t) * np.exp(-t / (t60 * 0.08))) * np.exp(-6.9 * t / t60)
		D.place(out, p * rng.random() ** amp_exp, int(s))
	return out


def body_thud(rng: np.random.Generator, dur: float = 0.25, f: float = 110.0, bright: float = 1.0, sr: int = SR) -> np.ndarray:
	"""Fleshy/muffled body impact (punches, falls)."""
	n = D.ns(dur, sr)
	y = D.thump(dur, f * 1.8, f, dur * 0.35, sr, sweep_t=0.02)
	k = D.ns(0.05, sr)
	slap = D.butter(D.white(k, rng), "band", (400.0, 2500.0 * bright), 2, sr) * D.exp_decay(k, 0.035, sr)
	D.place(y, slap * 0.9, 0)
	return y


def cloth(rng: np.random.Generator, dur: float = 0.2, bright: float = 1.0, sr: int = SR) -> np.ndarray:
	"""Fabric flap/rustle (robes, sleeves)."""
	n = D.ns(dur, sr)
	src = D.white(n, rng) * (0.6 + 0.4 * np.abs(D.smooth_noise(n, 40, rng, sr)))
	y = D.butter(src, "band", (500.0, 5000.0 * bright), 2, sr)
	return y * gamma_env(n, dur * 0.35, 1.6, sr)


# ---------------------------------------------------------------------------
# Fire
# ---------------------------------------------------------------------------

def roar(rng: np.random.Generator, n: int, intensity=1.0, sr: int = SR, flicker: float = 0.35) -> np.ndarray:
	"""Fire roar bed: low turbulent noise whose brightness tracks intensity."""
	inten = np.broadcast_to(np.asarray(intensity, dtype=float), (n,))
	src = D.brown(n, rng) * 0.6 + D.pink(n, rng) * 0.4
	fl = 1.0 + flicker * D.smooth_noise(n, 9.0, rng, sr) + 0.5 * flicker * D.smooth_noise(n, 23.0, rng, sr)
	cut = 220.0 + 1400.0 * np.clip(inten, 0, 2) * np.clip(fl, 0.4, 2.0)
	y = D.tv_filter(src, "lp", cut, 0.9, sr=sr, block=128)
	mid = D.tv_filter(D.white(n, rng), "bp", cut * 1.6, 0.8, sr=sr, block=128) * 0.12
	return (D.norm_peak(y, 1.0) + mid) * inten * np.clip(fl, 0.3, 1.8)


def crackle(rng: np.random.Generator, n: int, density=30.0, sr: int = SR, pop: float = 0.4) -> np.ndarray:
	"""Wood/fuel crackle: sparse sharp clicks + a few resonant pops."""
	imp = D.dust(n, density, rng, sr, 2.5)
	g = D.butter(D.white(D.ns(0.0012, sr), rng), "high", 2000.0, 2, sr)
	y = signal.oaconvolve(imp, g)[:n]
	if pop > 0:
		pops = D.dust(n, np.asarray(density) * 0.15, rng, sr, 1.2)
		y += pop * D.modal(pops, [1400, 2300, 3700], [0.012, 0.009, 0.006], [1, .7, .4], sr)
	return D.butter(y, "high", 700.0, 2, sr)


def ignite(rng: np.random.Generator, dur: float = 0.5, size: float = 1.0, sr: int = SR) -> np.ndarray:
	"""Fire 'whoomph': fast filter sweep of turbulent noise + low pressure thump."""
	n = D.ns(dur, sr)
	src = D.white(n, rng) * 0.5 + D.brown(n, rng) * 0.5
	f = D.curve([(0, 150), (0.05 * size, 4500), (0.18 * size, 1800), (dur, 600)], n, sr, log=True)
	y = D.tv_filter(src, "lp", f, 1.3, sr=sr)
	env = gamma_env(n, 0.06 * size, 1.4, sr)
	y = D.norm_peak(y * env, 1.0)
	D.place(y, D.thump(min(dur, 0.35), 110, 55, 0.25 * size, sr), 0, 0.45)
	return y


def sizzle(rng: np.random.Generator, dur: float, sr: int = SR) -> np.ndarray:
	"""Steam hiss with fizzing grains (fire meets water)."""
	n = D.ns(dur, sr)
	hiss = D.butter(D.white(n, rng), "band", (2500, 11000), 2, sr)
	fizz = D.grains(n, rng, 900.0, (0.0005, 0.002), (3000, 12000), sr, 2.0)
	return hiss * 0.6 + fizz * 1.5


# ---------------------------------------------------------------------------
# Water / ice
# ---------------------------------------------------------------------------

def splash(rng: np.random.Generator, dur: float = 0.8, size: float = 1.0, sr: int = SR) -> np.ndarray:
	"""Water splash: impact transient, spray, bubble cloud and droplet tail."""
	n = D.ns(dur, sr)
	t = D.taxis(n, sr)
	y = np.zeros(n)
	k = D.ns(0.06 * size, sr)
	hit = D.butter(D.white(k, rng), "band", (300, 5000), 2, sr) * D.exp_decay(k, 0.05 * size, sr)
	D.place(y, hit, 0)
	spray_env = gamma_env(n, 0.04 * size, 1.0, sr) * np.exp(-t / (0.25 * size))
	spray = D.butter(D.white(n, rng), "band", (1800, 11000), 2, sr) * spray_env
	spray *= 0.6 + 0.4 * np.abs(D.smooth_noise(n, 60, rng, sr))
	y += 0.55 * spray
	dens = 900.0 * size * np.exp(-t / (0.12 * size))
	y += 1.1 * D.bubbles(n, rng, dens, (350.0 / size ** 0.4, 2800.0), (0.02, 0.07), (0.4, 1.6), sr)
	drop_dens = 22.0 * np.exp(-np.maximum(t - 0.15 * size, 0) / (0.35 * size)) * (t > 0.1 * size)
	y += 0.8 * D.bubbles(n, rng, drop_dens, (900.0, 3500.0), (0.015, 0.045), (1.5, 3.5), sr)
	low = D.butter(D.brown(n, rng), "low", 250.0, 2, sr) * gamma_env(n, 0.03 * size, 1.0, sr) * np.exp(-t / 0.15)
	y += 0.6 * D.norm_peak(low) * size
	return y


def flow(rng: np.random.Generator, n: int, intensity=1.0, sr: int = SR, bubbly: float = 1.0) -> np.ndarray:
	"""Flowing/churning water texture (streams, shields, whips)."""
	inten = np.broadcast_to(np.asarray(intensity, dtype=float), (n,))
	base = D.butter(D.pink(n, rng), "band", (200, 3500), 2, sr) * (0.6 + 0.4 * D.smooth_noise(n, 5.0, rng, sr))
	b = D.bubbles(n, rng, 260.0 * bubbly * inten, (300.0, 2200.0), (0.02, 0.08), (0.3, 1.2), sr)
	gurgle = D.bubbles(n, rng, 25.0 * bubbly * inten, (120.0, 400.0), (0.05, 0.14), (0.2, 0.6), sr)
	return (base * 0.8 + b * 0.9 + gurgle * 1.2) * inten


def shards(rng: np.random.Generator, dur: float, density: float = 120.0, decay: float = 0.3, sr: int = SR,
		f_range=(2500.0, 11000.0)) -> np.ndarray:
	"""Tinkling ice/glass fragments: high inharmonic pings with decaying density."""
	n = D.ns(dur, sr)
	t = D.taxis(n, sr)
	return pings(rng, n, density * np.exp(-t / decay), f_range, (0.02, 0.1), sr)


def ice_ring(rng: np.random.Generator, dur: float = 0.6, f_lo: float = 1800.0, f_hi: float = 9000.0, count: int = 10,
		sr: int = SR) -> np.ndarray:
	"""Crystalline inharmonic partial cluster with fast high decays."""
	n = D.ns(dur, sr)
	freqs = np.exp(rng.uniform(math.log(f_lo), math.log(f_hi), count))
	amps = rng.uniform(0.3, 1.0, count) * (f_lo / freqs) ** 0.3
	decs = dur * rng.uniform(0.15, 0.7, count) * (f_lo / freqs) ** 0.4
	y = D.additive(1.0, n, amps, sr, ratios=freqs, phases=rng.uniform(0, 1, count), decays=decs)
	return y * np.clip(D.taxis(n, sr) / 0.0005, 0, 1)


def creak(rng: np.random.Generator, dur: float, rate_curve, f_res: float = 1800.0, q_t60: float = 0.01,
		sr: int = SR) -> np.ndarray:
	"""Stick-slip creak (ice stress, wood): a jittered pulse train through a resonance."""
	n = D.ns(dur, sr)
	rate = np.broadcast_to(np.asarray(rate_curve, dtype=float), (n,))
	ph = D.phase(rate * (1 + 0.15 * D.smooth_noise(n, 30, rng, sr)), n, sr)
	pulses = np.diff(np.floor(ph), prepend=0.0) * rng.uniform(0.5, 1.0, n)
	y = D.resonator(pulses, f_res, q_t60, sr) + 0.5 * D.resonator(pulses, f_res * 1.93, q_t60 * 0.7, sr)
	return y


# ---------------------------------------------------------------------------
# Creature voices
# ---------------------------------------------------------------------------

def voice(rng: np.random.Generator, f0, formant_specs, amp, sr: int = SR, aspiration: float = 0.15,
		fry: float = 0.0, sub: float = 0.0, grit: float = 0.0, jitter: float = 0.01, tilt: float = 1200.0) -> np.ndarray:
	"""Source-filter animal voice. f0/amp are per-sample arrays; formant_specs is a
	list of (freq or freq-curve, q, gain). `fry` adds irregular low pulses (growl),
	`sub` adds period doubling (roar), `grit` drives a saturator."""
	n = amp.shape[0]
	f = np.asarray(f0, dtype=float) * (1 + jitter * D.smooth_noise(n, 40, rng, sr))
	src = D.saw(f, n, sr)
	if sub > 0:
		src = src * (1 - sub * 0.5 * (1 + np.sin(TAU * D.phase(f * 0.5, n, sr))))
		src += sub * 0.5 * D.saw(f * 0.5, n, sr)
	if fry > 0:
		fr = 0.5 + 0.5 * np.sin(TAU * D.phase(np.maximum(f * 0.25, 8.0) * (1 + 0.4 * D.smooth_noise(n, 20, rng, sr)), n, sr))
		src *= 1 - fry + fry * fr ** 3 * 2.0
	src = D.onepole_lp(src, tilt, sr) * 3.0 + src * 0.25
	noise = D.white(n, rng) * aspiration * 3.0
	exc = src + noise
	y = D.formants(exc, formant_specs, sr)
	y *= amp
	if grit > 0:
		y = D.saturate(y / (np.max(np.abs(y)) + 1e-9) * (1 + 4 * grit), 1.0)
	return y
