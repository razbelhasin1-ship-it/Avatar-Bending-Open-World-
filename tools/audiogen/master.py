"""Mastering, loudness measurement (ITU-R BS.1770 style), file writers and analysis."""
from __future__ import annotations

import math
import os
import shutil
import struct
import subprocess
import tempfile

import numpy as np
from scipy import signal

import dsp as D


# ---------------------------------------------------------------------------
# Loudness
# ---------------------------------------------------------------------------

def _k_coeffs(sr: int):
	"""K-weighting pre-filter (high shelf) + RLB high-pass for any sample rate."""
	out = []
	for kind, G, Q, fc in (("hs", 3.999843853973347, 0.7071752369554196, 1681.974450955533),
			("hp", 0.0, 0.5003270373238773, 38.13547087602444)):
		A = 10 ** (G / 40.0)
		w0 = 2 * math.pi * fc / sr
		alpha = math.sin(w0) / (2 * Q)
		cw = math.cos(w0)
		if kind == "hs":
			b = [A * ((A + 1) + (A - 1) * cw + 2 * math.sqrt(A) * alpha), -2 * A * ((A - 1) + (A + 1) * cw),
				A * ((A + 1) + (A - 1) * cw - 2 * math.sqrt(A) * alpha)]
			a = [(A + 1) - (A - 1) * cw + 2 * math.sqrt(A) * alpha, 2 * ((A - 1) - (A + 1) * cw),
				(A + 1) - (A - 1) * cw - 2 * math.sqrt(A) * alpha]
		else:
			b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
			a = [1 + alpha, -2 * cw, 1 - alpha]
		out.append((np.array(b) / a[0], np.array(a) / a[0]))
	return out


def k_weight(x: np.ndarray, sr: int) -> np.ndarray:
	y = x
	for b, a in _k_coeffs(sr):
		y = signal.lfilter(b, a, y, axis=-1)
	return y


def block_loudness(x: np.ndarray, sr: int, win: float = 0.4, hop: float = 0.1) -> np.ndarray:
	"""Loudness (LUFS) of overlapping windows. Short inputs are zero padded to one window."""
	xs = x if x.ndim == 2 else x[None, :]
	z = k_weight(xs, sr) ** 2
	w = int(win * sr)
	h = max(1, int(hop * sr))
	n = z.shape[-1]
	if n < w:
		z = np.pad(z, ((0, 0), (0, w - n)))
		n = w
	c = np.cumsum(np.pad(z.sum(axis=0), (1, 0)))
	starts = np.arange(0, n - w + 1, h)
	ms = (c[starts + w] - c[starts]) / w
	return -0.691 + 10 * np.log10(ms + 1e-20)


def integrated_lufs(x: np.ndarray, sr: int) -> float:
	bl = block_loudness(x, sr)
	g = bl[bl > -70.0]
	if g.size == 0:
		return -120.0
	rel = 10 * np.log10(np.mean(10 ** (g / 10))) - 10.0
	g2 = g[g > rel]
	if g2.size == 0:
		return -120.0
	return float(10 * np.log10(np.mean(10 ** (g2 / 10))))


def max_momentary(x: np.ndarray, sr: int, win: float = 0.4) -> float:
	return float(np.max(block_loudness(x, sr, win, 0.02)))


def true_peak(x: np.ndarray) -> float:
	xs = x if x.ndim == 2 else x[None, :]
	up = signal.resample_poly(xs, 4, 1, axis=-1)
	return float(np.max(np.abs(up)))


# ---------------------------------------------------------------------------
# Dynamics
# ---------------------------------------------------------------------------

def peak_envelope(x: np.ndarray, chunk: int = 1 << 20) -> np.ndarray:
	"""Per-sample true-peak estimate (4x oversampled, max over channels)."""
	xs = x if x.ndim == 2 else x[None, :]
	n = xs.shape[-1]
	out = np.empty(n)
	pad = 64
	for s in range(0, n, chunk):
		e = min(n, s + chunk)
		a = max(0, s - pad)
		b = min(n, e + pad)
		up = np.abs(signal.resample_poly(xs[:, a:b], 4, 1, axis=-1)).max(axis=0)
		up = up[(s - a) * 4:(s - a) * 4 + (e - s) * 4]
		out[s:e] = up.reshape(-1, 4).max(axis=1)
	return np.maximum(out, np.abs(xs).max(axis=0))


def limiter(x: np.ndarray, sr: int, ceiling_db: float = -1.0, lookahead: float = 0.0015, release: float = 0.08,
		circular: bool = False) -> np.ndarray:
	"""Look-ahead peak limiter (gain computer with instant attack inside the
	look-ahead window, exponential release). `circular` treats the signal as a
	loop so gain at the boundary is continuous."""
	ceil = D.undb(ceiling_db)
	mono = peak_envelope(x)
	n = mono.shape[0]
	L = max(1, int(lookahead * sr))
	pad = 0
	if circular:
		pad = min(n, L * 4 + int(release * sr * 6))
		mono = np.concatenate([mono[-pad:], mono, mono[:pad]])
	need = np.maximum(mono / ceil, 1.0)
	att = 1.0 - 1.0 / need
	held = D.hold_max(att, size=2 * L + 1)
	lr = -1.0 / max(release * sr, 1.0)
	m = np.arange(held.shape[0], dtype=float)
	la = np.log(held + 1e-30)
	env = np.exp(m * lr + np.maximum.accumulate(la - m * lr))
	env = D.box_avg(env, size=L)
	gain = 1.0 - np.clip(env, 0.0, 1.0)
	if circular:
		gain = gain[pad:pad + n]
	y = x * gain
	return np.clip(y, -ceil, ceil)


def compress(x: np.ndarray, sr: int, threshold_db: float = -18.0, ratio: float = 2.0, attack: float = 0.01,
		release: float = 0.2, makeup_db: float = 0.0) -> np.ndarray:
	"""Gentle RMS-ish bus compressor (feed-forward, smoothed envelope)."""
	mono = np.max(np.abs(x), axis=0) if x.ndim == 2 else np.abs(x)
	a = math.exp(-1.0 / (attack * sr))
	r = math.exp(-1.0 / (release * sr))
	# Two-stage smoothing: fast follower then slow release (linear filters approximate).
	env = signal.lfilter([1 - a], [1, -a], mono)
	env = np.maximum(env, signal.lfilter([1 - r], [1, -r], mono))
	lvl = 20 * np.log10(env + 1e-9)
	over = np.maximum(lvl - threshold_db, 0.0)
	gr = -over * (1.0 - 1.0 / ratio)
	g = 10 ** ((gr + makeup_db) / 20.0)
	return x * g


# ---------------------------------------------------------------------------
# Mastering chain
# ---------------------------------------------------------------------------

def trim_silence(x: np.ndarray, thresh_db: float = -66.0, keep: float = 0.01, sr: int = D.SR) -> np.ndarray:
	"""Removes trailing (and leading near-silence before the first transient)."""
	mono = np.max(np.abs(x), axis=0) if x.ndim == 2 else np.abs(x)
	th = D.undb(thresh_db) * max(np.max(mono), 1e-9)
	idx = np.nonzero(mono > th)[0]
	if idx.size == 0:
		return x
	s = max(0, idx[0] - int(keep * sr * 0.2))
	e = min(mono.shape[0], idx[-1] + int(keep * sr))
	return x[..., s:e]


def master_oneshot(x: np.ndarray, sr: int, target_lufs: float, ceiling_db: float = -1.0, fade_in: float = 0.0015,
		fade_out: float = 0.03, win: float = 0.3, max_gr_db: float = 3.0) -> np.ndarray:
	"""One-shot SFX: DC removal, trim, loudness match on max short-term loudness,
	gentle limiting (at most `max_gr_db` of gain reduction), short fades."""
	y = D.butter(x, "high", 18.0, 2, sr)
	y = trim_silence(y, -56.0, sr=sr)
	y = D.fades(y, fade_in, fade_out, sr)
	lm = max_momentary(y, sr, win)
	y = y * D.undb(target_lufs - lm)
	# Gentle limiting only: never squash transients by more than max_gr_db to hit
	# the loudness target (very peaky sounds end up slightly under target instead).
	pk = D.db(float(np.max(peak_envelope(y))))
	if pk > ceiling_db + max_gr_db:
		y = y * D.undb(ceiling_db + max_gr_db - pk)
	y = limiter(y, sr, ceiling_db)
	return D.fades(y, 0.0, 0.004, sr)


def master_loop(x: np.ndarray, sr: int, target_lufs: float, ceiling_db: float = -1.0) -> np.ndarray:
	"""Loops: integrated loudness match + circular limiting; never faded or trimmed."""
	y = x - np.mean(x, axis=-1, keepdims=True)
	li = integrated_lufs(y, sr)
	y = y * D.undb(target_lufs - li)
	return limiter(y, sr, ceiling_db, release=0.25, circular=True)


# ---------------------------------------------------------------------------
# Writers
# ---------------------------------------------------------------------------

def _to_int16(x: np.ndarray, rng: np.random.Generator) -> np.ndarray:
	d = (rng.random(x.shape) - rng.random(x.shape)) / 32768.0  # TPDF dither, 1 LSB
	y = np.clip(x + d, -1.0, 32767 / 32768)
	return np.round(y * 32767.0).astype("<i2")


def write_wav(path: str, x: np.ndarray, sr: int, loop: bool = False, seed: int = 0) -> None:
	"""16-bit PCM WAV. Loops get a 'smpl' chunk (forward loop over the whole file)
	which Godot's importer reads with loop mode "Detect from WAV"."""
	rng = np.random.default_rng(seed)
	data = x if x.ndim == 1 else x.T  # interleave stereo
	pcm = _to_int16(data, rng)
	ch = 1 if x.ndim == 1 else x.shape[0]
	frames = x.shape[-1]
	raw = pcm.tobytes()
	fmt = struct.pack("<HHIIHH", 1, ch, sr, sr * ch * 2, ch * 2, 16)
	chunks = [b"fmt ", struct.pack("<I", len(fmt)), fmt, b"data", struct.pack("<I", len(raw)), raw]
	if len(raw) % 2:
		chunks.append(b"\x00")
	if loop:
		smpl = struct.pack("<9I", 0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0)
		# cue id, type (0 = forward), start, end (Godot treats end as exclusive), fraction, play count
		smpl += struct.pack("<6I", 0, 0, 0, frames, 0, 0)
		chunks += [b"smpl", struct.pack("<I", len(smpl)), smpl]
	body = b"WAVE" + b"".join(chunks)
	with open(path, "wb") as f:
		f.write(b"RIFF" + struct.pack("<I", len(body)) + body)


def ogg_backend() -> str:
	try:
		import soundfile as sf  # noqa: F401
		if "OGG" in sf.available_formats():
			return "soundfile"
	except Exception:
		pass
	if shutil.which("ffmpeg"):
		return "ffmpeg"
	return ""


def write_ogg(path: str, x: np.ndarray, sr: int, quality: float = 0.35) -> bool:
	"""OGG Vorbis (quality 0..1 ~ vorbis q0..q10). Returns False if no encoder."""
	backend = ogg_backend()
	data = (x if x.ndim == 1 else x.T).astype(np.float32)
	data = np.clip(data, -1.0, 1.0)
	if backend == "soundfile":
		import soundfile as sf
		ch = 1 if data.ndim == 1 else data.shape[1]
		# libsndfile's Vorbis encoder crashes on very large single writes: stream it.
		with sf.SoundFile(path, "w", sr, ch, format="OGG", subtype="VORBIS",
				compression_level=float(np.clip(1.0 - quality, 0.0, 1.0))) as f:
			for i in range(0, data.shape[0], sr):
				f.write(data[i:i + sr])
		return True
	if backend == "ffmpeg":
		with tempfile.TemporaryDirectory() as td:
			tmp = os.path.join(td, "in.wav")
			write_wav(tmp, x, sr)
			subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a",
				"%.1f" % (quality * 10.0), path], check=True)
		return True
	return False


# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------

def spectral_centroid(x: np.ndarray, sr: int) -> float:
	mono = x.mean(axis=0) if x.ndim == 2 else x
	n = min(mono.shape[0], 1 << 18)
	seg = mono[:n] if mono.shape[0] <= n else mono[(mono.shape[0] - n) // 2:(mono.shape[0] + n) // 2]
	f, p = signal.welch(seg, sr, nperseg=min(4096, n))
	return float(np.sum(f * p) / (np.sum(p) + 1e-20))


def loop_metrics(x: np.ndarray, sr: int) -> tuple[float, float, float]:
	"""(boundary jump / 99.5th percentile sample step,
	RMS step in dB between the 50 ms windows either side of the loop point,
	95th percentile of the same RMS step between adjacent windows inside the file)."""
	xs = x if x.ndim == 2 else x[None, :]
	jump = float(np.max(np.abs(xs[:, 0] - xs[:, -1])))
	steps = np.abs(np.diff(xs, axis=-1))
	typical = float(np.percentile(steps, 99.5)) + 1e-9
	w = int(0.05 * sr)
	a = math.sqrt(float(np.mean(xs[:, -w:] ** 2)) + 1e-20)
	b = math.sqrt(float(np.mean(xs[:, :w] ** 2)) + 1e-20)
	k = xs.shape[-1] // w
	wins = np.sqrt(np.mean(xs[:, :k * w].reshape(xs.shape[0], k, w) ** 2, axis=(0, 2)) + 1e-20)
	internal = np.abs(np.diff(20 * np.log10(wins)))
	return jump / typical, abs(20 * math.log10(a / b)), float(np.percentile(internal, 95)) if internal.size else 0.0


def analyze(x: np.ndarray, sr: int, loop: bool) -> dict:
	peak = float(np.max(np.abs(x)))
	rms = math.sqrt(float(np.mean(x ** 2)))
	out = {
		"duration": x.shape[-1] / sr,
		"channels": 1 if x.ndim == 1 else x.shape[0],
		"sr": sr,
		"peak_db": D.db(peak),
		"true_peak_db": D.db(true_peak(x)),
		"rms_db": D.db(rms),
		"lufs_i": integrated_lufs(x, sr),
		"lufs_m_max": max_momentary(x, sr),
		"centroid_hz": spectral_centroid(x, sr),
		"clipped": int(np.sum(np.abs(x) >= 0.9999)),
	}
	if loop:
		j, s, p95 = loop_metrics(x, sr)
		out["loop_jump_ratio"] = j
		out["loop_rms_step_db"] = s
		out["loop_rms_p95_db"] = p95
	return out
