"""Core DSP primitives for the procedural audio generator.

Everything here is plain numpy/scipy so the generator runs anywhere Python 3 with
numpy + scipy is available. Signals are float64 numpy arrays in [-1, 1]; stereo
signals have shape (2, n). All functions take an explicit sample rate where it
matters and an explicit numpy Generator where randomness is involved, so every
sound is reproducible from its seed.
"""
from __future__ import annotations

import math

import numpy as np
from scipy import signal
from scipy.ndimage import maximum_filter1d, uniform_filter1d

SR = 44100
TAU = 2.0 * math.pi


# ---------------------------------------------------------------------------
# Time helpers
# ---------------------------------------------------------------------------

def ns(seconds: float, sr: int = SR) -> int:
	"""Number of samples for a duration."""
	return max(1, int(round(seconds * sr)))


def taxis(n: int, sr: int = SR) -> np.ndarray:
	return np.arange(n) / sr


def place(dst: np.ndarray, src: np.ndarray, start: int, gain: float = 1.0) -> None:
	"""Mixes `src` into `dst` at sample `start` (clipped to dst bounds)."""
	if start >= dst.shape[-1] or gain == 0.0:
		return
	s0 = max(0, start)
	off = s0 - start
	n = min(src.shape[-1] - off, dst.shape[-1] - s0)
	if n <= 0:
		return
	dst[..., s0:s0 + n] += src[..., off:off + n] * gain


def mix(*parts, sr: int = SR) -> np.ndarray:
	"""Sums mono signals of different lengths. Each part is an array or a tuple
	(array, gain) / (array, gain, offset_seconds)."""
	items = []
	end = 1
	for p in parts:
		if isinstance(p, tuple):
			x, g = p[0], p[1]
			off = int(round(p[2] * sr)) if len(p) > 2 else 0
		else:
			x, g, off = p, 1.0, 0
		items.append((x, g, off))
		end = max(end, off + x.shape[-1])
	out = np.zeros(end)
	for x, g, off in items:
		out[off:off + x.shape[-1]] += x * g
	return out


def pad_to(x: np.ndarray, n: int) -> np.ndarray:
	if x.shape[-1] >= n:
		return x[..., :n]
	pad = [(0, 0)] * (x.ndim - 1) + [(0, n - x.shape[-1])]
	return np.pad(x, pad)


# ---------------------------------------------------------------------------
# Envelopes
# ---------------------------------------------------------------------------

def curve(points, n: int, sr: int = SR, log: bool = False) -> np.ndarray:
	"""Piecewise curve from (time_s, value) points. `log` interpolates in the log
	domain (use for frequencies so sweeps sound even)."""
	pts = sorted(points)
	tt = np.array([p[0] for p in pts], dtype=float)
	vv = np.array([p[1] for p in pts], dtype=float)
	t = taxis(n, sr)
	if log:
		return np.exp(np.interp(t, tt, np.log(np.maximum(vv, 1e-9))))
	return np.interp(t, tt, vv)


def exp_decay(n: int, t60: float, sr: int = SR) -> np.ndarray:
	"""Exponential decay reaching -60 dB after t60 seconds."""
	return np.exp(-6.907755 * taxis(n, sr) / max(t60, 1e-4))


def ad_env(n: int, attack: float, t60: float, sr: int = SR, attack_curve: float = 1.0) -> np.ndarray:
	"""Attack ramp (power curve) followed by an exponential decay."""
	t = taxis(n, sr)
	a = max(attack, 1e-4)
	rise = np.clip(t / a, 0.0, 1.0) ** attack_curve
	fall = np.exp(-6.907755 * np.maximum(t - a, 0.0) / max(t60, 1e-4))
	return rise * fall


def adsr(n: int, a: float, d: float, s: float, r: float, sr: int = SR) -> np.ndarray:
	"""Classic ADSR where the release starts `r` seconds before the end."""
	t = taxis(n, sr)
	dur = n / sr
	rel_start = max(dur - r, 0.0)
	env = np.where(t < a, t / max(a, 1e-5), s + (1.0 - s) * np.exp(-(t - a) / max(d, 1e-5) * 3.0))
	rel = np.clip((dur - t) / max(r, 1e-5), 0.0, 1.0)
	env = np.where(t >= rel_start, env * rel, env)
	return env


def fades(x: np.ndarray, fin: float = 0.002, fout: float = 0.02, sr: int = SR) -> np.ndarray:
	"""Short raised-cosine fades on both ends (copy)."""
	y = np.array(x, dtype=float, copy=True)
	n = y.shape[-1]
	ni = min(ns(fin, sr), n // 2) if fin > 0 else 0
	no = min(ns(fout, sr), n // 2) if fout > 0 else 0
	if ni > 1:
		y[..., :ni] *= 0.5 - 0.5 * np.cos(np.linspace(0.0, math.pi, ni))
	if no > 1:
		y[..., n - no:] *= 0.5 + 0.5 * np.cos(np.linspace(0.0, math.pi, no))
	return y


def smooth_noise(n: int, rate_hz: float, rng: np.random.Generator, sr: int = SR) -> np.ndarray:
	"""Smooth random control signal in roughly [-1, 1] changing at `rate_hz`."""
	k = max(8, int(n / sr * rate_hz) + 4)
	pts = rng.uniform(-1.0, 1.0, k)
	xs = np.linspace(0, n, k)
	cs = signal.windows.hann(5)
	pts = np.convolve(pts, cs / cs.sum(), mode="same") * 1.6
	return np.interp(np.arange(n), xs, pts)


# ---------------------------------------------------------------------------
# Noise
# ---------------------------------------------------------------------------

def white(n: int, rng: np.random.Generator) -> np.ndarray:
	return rng.uniform(-1.0, 1.0, n)


def colored(n: int, rng: np.random.Generator, slope_db_oct: float) -> np.ndarray:
	"""Noise with a spectral slope (-3 = pink, -6 = brown, +3 = blue). Normalized to peak 1."""
	m = 1 << int(math.ceil(math.log2(max(n, 2))))
	spec = np.fft.rfft(rng.standard_normal(m))
	f = np.arange(spec.shape[0], dtype=float)
	f[0] = 1.0
	spec *= f ** (slope_db_oct / 6.0206)
	spec[0] = 0.0
	y = np.fft.irfft(spec, m)[:n]
	return y / (np.max(np.abs(y)) + 1e-12)


def pink(n: int, rng: np.random.Generator) -> np.ndarray:
	return colored(n, rng, -3.0)


def brown(n: int, rng: np.random.Generator) -> np.ndarray:
	return colored(n, rng, -6.0)


def dust(n: int, density, rng: np.random.Generator, sr: int = SR, amp_exp: float = 2.0, signed: bool = True) -> np.ndarray:
	"""Sparse random impulses. `density` (events/s) is a scalar or per-sample array.
	Amplitudes follow u**amp_exp (heavier tail of quiet events)."""
	dens = np.broadcast_to(np.asarray(density, dtype=float), (n,))
	p = np.clip(dens / sr, 0.0, 1.0)
	hits = rng.random(n) < p
	out = np.zeros(n)
	k = int(hits.sum())
	if k:
		amps = rng.random(k) ** amp_exp
		if signed:
			amps *= rng.choice([-1.0, 1.0], k)
		out[hits] = amps
	return out


# ---------------------------------------------------------------------------
# Oscillators
# ---------------------------------------------------------------------------

def phase(freq, n: int, sr: int = SR, phase0: float = 0.0) -> np.ndarray:
	"""Phase in cycles for a constant or per-sample frequency."""
	f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
	ph = np.cumsum(f) / sr
	return ph - ph[0] + phase0


def sine(freq, n: int, sr: int = SR, phase0: float = 0.0) -> np.ndarray:
	return np.sin(TAU * phase(freq, n, sr, phase0))


def _poly_blep(t: np.ndarray, dt: np.ndarray) -> np.ndarray:
	out = np.zeros_like(t)
	m1 = t < dt
	x = t[m1] / dt[m1]
	out[m1] = x + x - x * x - 1.0
	m2 = t > 1.0 - dt
	x = (t[m2] - 1.0) / dt[m2]
	out[m2] = x * x + x + x + 1.0
	return out


def saw(freq, n: int, sr: int = SR, phase0: float = 0.0) -> np.ndarray:
	"""Band-limited (polyBLEP) sawtooth."""
	f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
	ph = phase(f, n, sr, phase0) % 1.0
	dt = np.clip(f / sr, 1e-6, 0.5)
	return 2.0 * ph - 1.0 - _poly_blep(ph, dt)


def square(freq, n: int, sr: int = SR, pw: float = 0.5, phase0: float = 0.0) -> np.ndarray:
	"""Band-limited pulse wave."""
	f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
	ph = phase(f, n, sr, phase0) % 1.0
	dt = np.clip(f / sr, 1e-6, 0.5)
	y = np.where(ph < pw, 1.0, -1.0)
	y += _poly_blep(ph, dt)
	y -= _poly_blep((ph + 1.0 - pw) % 1.0, dt)
	return y


def additive(freq, n: int, amps, sr: int = SR, ratios=None, phases=None, decays=None, nyquist_guard: float = 0.45) -> np.ndarray:
	"""Sum of partials k*f (or ratio*f). `decays` are per-partial t60 seconds."""
	f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
	ph = phase(f, n, sr)
	out = np.zeros(n)
	t = taxis(n, sr) if decays is not None else None
	for i, a in enumerate(amps):
		if a == 0.0:
			continue
		r = (i + 1) if ratios is None else ratios[i]
		p0 = 0.0 if phases is None else phases[i]
		part = a * np.sin(TAU * (ph * r + p0))
		lim = f * r < nyquist_guard * sr
		if not np.all(lim):
			part = part * lim
		if decays is not None:
			part *= np.exp(-6.907755 * t / max(decays[i], 1e-4))
		out += part
	return out


# ---------------------------------------------------------------------------
# Filters (RBJ biquads, static and time-varying)
# ---------------------------------------------------------------------------

def _biquad(kind: str, f, q, gain_db, sr: int):
	"""RBJ cookbook coefficients. f/q may be arrays (vectorized design)."""
	f = np.clip(np.asarray(f, dtype=float), 5.0, sr * 0.49)
	q = np.maximum(np.asarray(q, dtype=float), 0.05)
	w0 = TAU * f / sr
	cw = np.cos(w0)
	sw = np.sin(w0)
	alpha = sw / (2.0 * q)
	A = 10.0 ** (np.asarray(gain_db, dtype=float) / 40.0)
	if kind == "lp":
		b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2
		a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
	elif kind == "hp":
		b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2
		a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
	elif kind == "bp":  # constant 0 dB peak gain
		b0 = alpha; b1 = 0 * cw; b2 = -alpha
		a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
	elif kind == "notch":
		b0 = 1 + 0 * cw; b1 = -2 * cw; b2 = 1 + 0 * cw
		a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
	elif kind == "peak":
		b0 = 1 + alpha * A; b1 = -2 * cw; b2 = 1 - alpha * A
		a0 = 1 + alpha / A; a1 = -2 * cw; a2 = 1 - alpha / A
	elif kind == "lowshelf":
		sq = 2 * np.sqrt(A) * alpha
		b0 = A * ((A + 1) - (A - 1) * cw + sq); b1 = 2 * A * ((A - 1) - (A + 1) * cw); b2 = A * ((A + 1) - (A - 1) * cw - sq)
		a0 = (A + 1) + (A - 1) * cw + sq; a1 = -2 * ((A - 1) + (A + 1) * cw); a2 = (A + 1) + (A - 1) * cw - sq
	elif kind == "highshelf":
		sq = 2 * np.sqrt(A) * alpha
		b0 = A * ((A + 1) + (A - 1) * cw + sq); b1 = -2 * A * ((A - 1) + (A + 1) * cw); b2 = A * ((A + 1) + (A - 1) * cw - sq)
		a0 = (A + 1) - (A - 1) * cw + sq; a1 = 2 * ((A - 1) - (A + 1) * cw); a2 = (A + 1) - (A - 1) * cw - sq
	else:
		raise ValueError(kind)
	return (np.stack([b0 / a0, b1 / a0, b2 / a0], -1), np.stack([np.ones_like(a0), a1 / a0, a2 / a0], -1))


def filt(x: np.ndarray, kind: str, f: float, q: float = 0.7071, gain_db: float = 0.0, sr: int = SR) -> np.ndarray:
	"""Static biquad filter (works on mono or stereo along the last axis)."""
	b, a = _biquad(kind, f, q, gain_db, sr)
	return signal.lfilter(b, a, x, axis=-1)


def butter(x: np.ndarray, kind: str, f, order: int = 4, sr: int = SR) -> np.ndarray:
	"""Butterworth lowpass/highpass/bandpass ('low', 'high', 'band')."""
	if kind == "band":
		lo, hi = f
		sos = signal.butter(order, [max(lo, 5.0), min(hi, sr * 0.49)], btype="band", fs=sr, output="sos")
	else:
		sos = signal.butter(order, min(max(f, 5.0), sr * 0.49), btype=kind, fs=sr, output="sos")
	return signal.sosfilt(sos, x, axis=-1)


def tv_filter(x: np.ndarray, kind: str, f, q=0.7071, gain_db=0.0, sr: int = SR, block: int = 64) -> np.ndarray:
	"""Time-varying biquad: `f` / `q` may be per-sample arrays. Coefficients are
	updated every `block` samples (state carried across blocks)."""
	n = x.shape[-1]
	nb = (n + block - 1) // block
	fa = np.broadcast_to(np.asarray(f, dtype=float), (n,))
	qa = np.broadcast_to(np.asarray(q, dtype=float), (n,))
	ga = np.broadcast_to(np.asarray(gain_db, dtype=float), (n,))
	idx = np.minimum(np.arange(nb) * block + block // 2, n - 1)
	B, A = _biquad(kind, fa[idx], qa[idx], ga[idx], sr)
	y = np.empty_like(x, dtype=float)
	zi = np.zeros(2) if x.ndim == 1 else np.zeros((x.shape[0], 2))
	for i in range(nb):
		s = i * block
		e = min(s + block, n)
		y[..., s:e], zi = signal.lfilter(B[i], A[i], x[..., s:e], axis=-1, zi=zi)
	return y


def onepole_lp(x: np.ndarray, fc: float, sr: int = SR) -> np.ndarray:
	a = math.exp(-TAU * fc / sr)
	return signal.lfilter([1 - a], [1, -a], x, axis=-1)


def resonator(x: np.ndarray, freq: float, t60: float, sr: int = SR) -> np.ndarray:
	"""Two-pole resonator ringing at `freq` with decay t60. Impulse-normalized: a
	unit impulse rings with amplitude ~1 whatever the decay (modal synthesis)."""
	r = math.exp(-6.907755 / (max(t60, 1e-4) * sr))
	w = TAU * min(freq, sr * 0.49) / sr
	return signal.lfilter([0.5, 0.0, -0.5], [1.0, -2.0 * r * math.cos(w), r * r], x, axis=-1)


def modal(excitation: np.ndarray, freqs, t60s, amps, sr: int = SR) -> np.ndarray:
	"""Bank of resonators driven by `excitation` (modal synthesis)."""
	out = np.zeros_like(excitation, dtype=float)
	for f, t, a in zip(freqs, t60s, amps):
		if f < sr * 0.48:
			out += a * resonator(excitation, f, t, sr)
	return out


def formants(x: np.ndarray, specs, sr: int = SR) -> np.ndarray:
	"""Parallel band-pass formant bank. specs: [(freq_or_curve, q, gain), ...]."""
	out = np.zeros_like(x, dtype=float)
	for f, q, g in specs:
		if np.ndim(f) == 0:
			out += g * filt(x, "bp", float(f), q, sr=sr)
		else:
			out += g * tv_filter(x, "bp", f, q, sr=sr)
	return out


# ---------------------------------------------------------------------------
# Non-linear and time-based effects
# ---------------------------------------------------------------------------

def saturate(x: np.ndarray, drive: float = 1.0) -> np.ndarray:
	"""Soft clipper normalized so small signals keep unity gain."""
	if drive <= 0.0:
		return x
	return np.tanh(x * drive) / drive


def varispeed(x: np.ndarray, rate) -> np.ndarray:
	"""Reads `x` with a per-sample playback rate (1 = normal) using linear
	interpolation. Used for pitch bends, vibrato and doppler."""
	n = x.shape[-1]
	r = np.broadcast_to(np.asarray(rate, dtype=float), (n,))
	pos = np.cumsum(r) - r[0]
	pos = np.clip(pos, 0, n - 1)
	return np.interp(pos, np.arange(n), x)


def delay_line(x: np.ndarray, delay_s, sr: int = SR) -> np.ndarray:
	"""Variable fractional delay (per-sample array or scalar), linear interpolation."""
	n = x.shape[-1]
	d = np.broadcast_to(np.asarray(delay_s, dtype=float) * sr, (n,))
	pos = np.arange(n) - d
	return np.interp(pos, np.arange(n), x, left=0.0)


def chorus(x: np.ndarray, rng: np.random.Generator, depth_ms: float = 3.0, rate: float = 0.4, voices: int = 2, sr: int = SR) -> np.ndarray:
	"""Mono chorus: sum of slowly modulated delayed copies."""
	n = x.shape[-1]
	t = taxis(n, sr)
	out = np.array(x, dtype=float, copy=True)
	for v in range(voices):
		lfo = np.sin(TAU * rate * (1 + 0.3 * v) * t + rng.uniform(0, TAU))
		out += 0.6 * delay_line(x, (8.0 + depth_ms * (1 + lfo)) / 1000.0, sr)
	return out / (1 + 0.6 * voices) ** 0.5


def echo(x: np.ndarray, time_s: float, feedback: float, mix: float, sr: int = SR, damp_hz: float = 4000.0, taps: int = 6) -> np.ndarray:
	"""Feedback delay with damping, computed as a finite sum of taps (fast)."""
	d = ns(time_s, sr)
	n = x.shape[-1]
	out = np.array(x, dtype=float, copy=True)
	wet = np.zeros_like(out)
	cur = x
	g = 1.0
	for k in range(1, taps + 1):
		cur = onepole_lp(cur, damp_hz, sr)
		g *= feedback if k > 1 else 1.0
		if k * d >= n:
			break
		wet[..., k * d:] += g * cur[..., :n - k * d]
	return out + mix * wet


def pan(x: np.ndarray, p: float) -> np.ndarray:
	"""Constant-power pan of a mono signal; p in [-1 (L), 1 (R)]."""
	a = (p + 1.0) * math.pi / 4.0
	return np.stack([x * math.cos(a), x * math.sin(a)])


def widen(x: np.ndarray, rng: np.random.Generator, amount: float = 0.5, sr: int = SR) -> np.ndarray:
	"""Mono -> pseudo-stereo using decorrelating short delays (Haas-ish)."""
	l = x + amount * 0.5 * delay_line(x, 0.011, sr)
	r = x + amount * 0.5 * delay_line(x, 0.017, sr)
	return np.stack([l, r]) / (1 + amount * 0.5)


# ---------------------------------------------------------------------------
# Reverb (synthetic impulse responses + FFT convolution)
# ---------------------------------------------------------------------------

def make_ir(seconds: float, rng: np.random.Generator, sr: int = SR, t60_low: float = 2.5, t60_high: float = 1.2,
		predelay: float = 0.02, early: int = 8, early_span: float = 0.06, brightness: float = 6000.0,
		stereo: bool = True) -> np.ndarray:
	"""Stereo impulse response: sparse early reflections + exponentially decaying
	noise tail whose high band decays faster than the low band."""
	n = ns(seconds, sr)
	chans = []
	for c in range(2 if stereo else 1):
		tail = rng.standard_normal(n)
		lo = butter(tail, "low", 800.0, 2, sr) * exp_decay(n, t60_low, sr)
		hi = butter(tail, "high", 800.0, 2, sr) * exp_decay(n, t60_high, sr)
		ir = lo + hi
		ir = butter(ir, "low", brightness, 2, sr)
		# soft onset of the diffuse tail
		on = np.clip(taxis(n, sr) / max(early_span, 1e-3), 0, 1) ** 1.5
		ir *= on
		er = np.zeros(n)
		for _ in range(early):
			k = ns(rng.uniform(0.004, early_span), sr)
			if k < n:
				er[k] += rng.uniform(0.3, 0.9) * rng.choice([-1, 1]) * (1 - k / (early_span * sr) * 0.5)
		ir = ir / (np.sqrt(np.sum(ir ** 2)) + 1e-12) + er * 0.35
		pd = ns(predelay, sr)
		ir = np.concatenate([np.zeros(pd), ir])[:n]
		chans.append(ir)
	return np.stack(chans)


def reverb(x: np.ndarray, ir: np.ndarray, wet: float = 0.25, dry: float = 1.0, tail: bool = True) -> np.ndarray:
	"""Convolution reverb. Mono input becomes stereo when the IR is stereo.
	With tail=True the output is extended by the IR length."""
	xs = x if x.ndim == 2 else np.stack([x, x])
	if ir.shape[0] == 1:
		ir = np.vstack([ir, ir])
	n = xs.shape[-1]
	out_len = n + ir.shape[-1] - 1 if tail else n
	out = np.zeros((2, out_len))
	for c in range(2):
		w = signal.oaconvolve(xs[c], ir[c])[:out_len]
		out[c, :w.shape[0]] += w * wet
		out[c, :n] += xs[c] * dry
	return out


# ---------------------------------------------------------------------------
# Synthesis building blocks shared by SFX and instruments
# ---------------------------------------------------------------------------

def noise_burst(n: int, rng: np.random.Generator, lo: float, hi: float, sr: int = SR) -> np.ndarray:
	return butter(white(n, rng), "band", (lo, hi), 2, sr)


def thump(seconds: float, f_start: float, f_end: float, t60: float, sr: int = SR, sweep_t: float = 0.08,
		click: float = 0.0, rng: np.random.Generator | None = None) -> np.ndarray:
	"""Pitched-down sine kick / sub thump with optional click transient."""
	n = ns(seconds, sr)
	t = taxis(n, sr)
	f = f_end + (f_start - f_end) * np.exp(-t / max(sweep_t, 1e-4))
	y = np.sin(TAU * phase(f, n, sr)) * ad_env(n, 0.002, t60, sr)
	if click > 0 and rng is not None:
		c = butter(white(ns(0.012, sr), rng), "band", (800, 6000), 2, sr) * exp_decay(ns(0.012, sr), 0.01, sr)
		place(y, c * click, 0)
	return y


def pitch_glide(points, n: int, sr: int = SR) -> np.ndarray:
	"""Log-interpolated frequency curve from (t, hz) points."""
	return curve(points, n, sr, log=True)


def bubble(f0: float, t60: float, rise: float, sr: int = SR, amp: float = 1.0) -> np.ndarray:
	"""Single bubble (van den Doel): sinusoid with exponentially rising pitch and
	exponential decay. `rise` is the relative pitch increase per second-scale."""
	n = ns(min(t60 * 1.2, 0.25), sr)
	t = taxis(n, sr)
	f = f0 * (1.0 + rise * t / max(t60, 1e-3))
	env = np.exp(-6.907755 * t / t60)
	att = np.clip(t / 0.0008, 0, 1)
	return amp * np.sin(TAU * phase(f, n, sr)) * env * att


def bubbles(n: int, rng: np.random.Generator, density, f_range=(400.0, 3000.0), t60_range=(0.02, 0.09),
		rise=(0.3, 1.5), sr: int = SR, amp_exp: float = 1.5) -> np.ndarray:
	"""Field of random bubbles. `density` = bubbles/s (scalar or per-sample)."""
	out = np.zeros(n)
	dens = np.broadcast_to(np.asarray(density, dtype=float), (n,))
	expected = float(dens.sum() / sr)
	k = rng.poisson(max(expected, 0.0))
	if k == 0:
		return out
	cdf = np.cumsum(dens)
	cdf /= cdf[-1]
	starts = np.searchsorted(cdf, rng.random(k))
	lf0, lf1 = math.log(f_range[0]), math.log(f_range[1])
	for s in starts:
		f0 = math.exp(rng.uniform(lf0, lf1))
		# Smaller (higher) bubbles die faster.
		t60 = rng.uniform(*t60_range) * (f_range[0] / f0) ** 0.35
		b = bubble(f0, max(t60, 0.006), rng.uniform(*rise), sr, rng.random() ** amp_exp)
		place(out, b, int(s))
	return out


def grains(n: int, rng: np.random.Generator, density, grain_s=(0.002, 0.008), band=(1000.0, 6000.0),
		sr: int = SR, amp_exp: float = 2.0, ring: float = 0.0) -> np.ndarray:
	"""Granular texture of tiny noise grains (crunch, crackle, debris). `ring` > 0
	adds a resonant ping per grain (stones, ice)."""
	imp = dust(n, density, rng, sr, amp_exp)
	gl = ns(rng.uniform(*grain_s), sr)
	g = white(gl, rng) * signal.windows.hann(gl)
	tex = signal.oaconvolve(imp, g)[:n]
	tex = butter(tex, "band", band, 2, sr)
	if ring > 0:
		# Every grain rings at its own pitch: impulses are dealt to a set of resonators.
		k = 8
		deal = rng.integers(0, k, n)
		rung = np.zeros(n)
		for i in range(k):
			f = math.exp(rng.uniform(math.log(band[0]), math.log(band[1])))
			rung += resonator(np.where(deal == i, imp, 0.0), f, 0.008 + 0.03 * rng.random(), sr)
		tex = tex * (1 - ring) + ring * rung * 0.6
	return tex


def passby(n: int, t_center: float, speed: float, dist: float, sr: int = SR, c: float = 343.0):
	"""Doppler pass-by curves: (amplitude, frequency ratio, closeness 0..1)."""
	t = taxis(n, sr) - t_center
	x = speed * t
	d = np.sqrt(x * x + dist * dist)
	amp = dist / d
	vr = speed * x / d  # radial velocity (positive = receding)
	ratio = c / (c + vr)
	return amp, ratio, amp ** 2


def crossfade_loop(x: np.ndarray, loop_len: int, xfade: int) -> np.ndarray:
	"""Seamless loop of `loop_len` samples from a render of at least loop_len+xfade:
	the material after the loop end is equal-power crossfaded into the head."""
	assert x.shape[-1] >= loop_len + xfade, "render too short for loop"
	y = np.array(x[..., :loop_len], dtype=float, copy=True)
	w = np.linspace(0.0, 1.0, xfade)
	fin = np.sin(w * math.pi / 2)
	fout = np.cos(w * math.pi / 2)
	y[..., :xfade] = x[..., :xfade] * fin + x[..., loop_len:loop_len + xfade] * fout
	return y


def fold_tail(x: np.ndarray, loop_len: int) -> np.ndarray:
	"""Loop for musical material: everything rendered after the loop end (ringing
	notes, reverb tails) is added onto the head so the loop is seamless."""
	y = np.array(x[..., :loop_len], dtype=float, copy=True)
	rest = x[..., loop_len:]
	while rest.shape[-1] > 0:
		k = min(rest.shape[-1], loop_len)
		y[..., :k] += rest[..., :k]
		rest = rest[..., k:]
	return y


def db(x: float) -> float:
	return 20.0 * math.log10(max(x, 1e-12))


def undb(d: float) -> float:
	return 10.0 ** (d / 20.0)


def midi_hz(m: float) -> float:
	return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


def norm_peak(x: np.ndarray, peak: float = 1.0) -> np.ndarray:
	m = np.max(np.abs(x))
	return x * (peak / m) if m > 0 else x


# Re-exported helpers used by other generator modules.
hold_max = maximum_filter1d
box_avg = uniform_filter1d
