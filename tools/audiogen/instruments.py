"""Synthesized instruments: plucked strings (Karplus-Strong), bowed erhu, dizi/xiao
flutes, drums, gongs, bells and synth pads/brass. Shared by music and UI/stinger SFX.

Note renderers return mono float arrays starting at the note onset. Phrase
renderers (flute, erhu) take a list of notes and render one continuous voice so
slides, vibrato and legato behave like a real player.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np
from scipy import signal

import dsp as D
from dsp import SR, TAU


# ---------------------------------------------------------------------------
# Plucked strings
# ---------------------------------------------------------------------------

def ks_string(freq: float, dur: float, rng: np.random.Generator, sr: int = SR, t60: float = 2.5, bright: float = 0.6,
		pluck_pos: float = 0.18, vel: float = 0.8, excite_times=None, excite_gains=None) -> np.ndarray:
	"""Karplus-Strong string with exact fractional tuning (first-order allpass in the
	loop, solved as one IIR with scipy.lfilter). `excite_times` (seconds) re-plucks
	the same vibrating string (pipa tremolo)."""
	P = sr / freq
	s = float(np.clip(0.5 - 0.42 * bright, 0.06, 0.5))  # loop low-pass tap weight
	L = int(math.floor(P - s - 0.1))
	L = max(L, 2)
	d = P - s - L
	C = (1.0 - d) / (1.0 + d)
	w = TAU * freq / sr
	hmag = abs((1 - s) + s * np.exp(-1j * w))
	rho = min(10 ** (-3.0 / (t60 * freq)) / max(hmag, 1e-6), 0.99995)
	n = D.ns(dur, sr)
	m = max(4, int(P))
	x = np.zeros(n)
	times = [0.0] if excite_times is None else list(excite_times)
	gains = [1.0] * len(times) if excite_gains is None else list(excite_gains)
	for t0, g in zip(times, gains):
		exc = rng.uniform(-1.0, 1.0, m)
		exc = D.onepole_lp(exc, 600.0 + 11000.0 * (vel * 0.6 + 0.4) * bright, sr)
		k = max(1, int(pluck_pos * m))
		exc[k:] = exc[k:] - exc[:-k]
		exc -= exc.mean()
		exc *= g * vel / (np.max(np.abs(exc)) + 1e-9)
		D.place(x, exc, D.ns(t0, sr) if t0 > 0 else 0)
	a = np.zeros(L + 3)
	a[0] = 1.0
	a[1] = C
	a[L] += -rho * (1 - s) * C
	a[L + 1] += -rho * ((1 - s) + s * C)
	a[L + 2] += -rho * s
	y = signal.lfilter([1.0, C], a, x)
	# The note ends where the player damps the string: short release, never a cut.
	return D.fades(y, 0.0, min(0.06, dur * 0.3), sr)


def guzheng(freq: float, dur: float, rng: np.random.Generator, vel: float = 0.8, sr: int = SR, bend_cents=None) -> np.ndarray:
	"""Guzheng note: long ringing steel/nylon string, bright attack, optional
	left-hand bend/vibrato curve (cents per sample, array or callable)."""
	t60 = float(np.interp(freq, [80, 300, 1200], [6.0, 3.6, 1.6]))
	br = float(np.interp(freq, [70, 250, 800], [0.35, 0.6, 0.72]))
	y = ks_string(freq, dur, rng, sr, t60=t60, bright=br, pluck_pos=0.14, vel=vel)
	# Metallic shimmer from slightly detuned second polarisation.
	y2 = ks_string(freq * 1.0012, dur, rng, sr, t60=t60 * 0.8, bright=br + 0.08, pluck_pos=0.2, vel=vel)
	y = y + 0.35 * y2
	nail = D.butter(D.white(D.ns(0.006, sr), rng), "band", (2500, 9000), 2, sr) * D.exp_decay(D.ns(0.006, sr), 0.004, sr)
	D.place(y, nail * 0.25 * vel, 0)
	if bend_cents is not None:
		cents = np.broadcast_to(np.asarray(bend_cents, dtype=float), (y.shape[0],))
		y = D.varispeed(y, 2.0 ** (cents / 1200.0))
	return y


def pipa(freq: float, dur: float, rng: np.random.Generator, vel: float = 0.8, sr: int = SR, tremolo: float = 0.0) -> np.ndarray:
	"""Pipa: brighter, drier pluck with a nail click; tremolo (lun) re-plucks the
	string `tremolo` times per second for the whole duration."""
	t60 = float(np.interp(freq, [100, 400, 1200], [2.4, 1.4, 0.7]))
	times = None
	gains = None
	if tremolo > 0:
		k = max(1, int(dur * tremolo * 0.92))
		times = [i / tremolo + rng.normal(0, 0.004) for i in range(k)]
		times[0] = 0.0
		gains = [0.75 + 0.25 * rng.random() for _ in range(k)]
		gains[0] = 1.0
	y = ks_string(freq, dur, rng, sr, t60=t60, bright=0.85, pluck_pos=0.09, vel=vel, excite_times=times, excite_gains=gains)
	click = D.butter(D.white(D.ns(0.004, sr), rng), "band", (1800, 7000), 2, sr) * D.exp_decay(D.ns(0.004, sr), 0.003, sr)
	for t0 in (times or [0.0]):
		D.place(y, click * 0.3 * vel, D.ns(max(t0, 0.0), sr))
	if tremolo > 0:
		y *= D.fades(np.ones_like(y), 0.0, 0.05, sr)
	return y


def harp(freq: float, dur: float, rng: np.random.Generator, vel: float = 0.7, sr: int = SR) -> np.ndarray:
	t60 = float(np.interp(freq, [80, 400, 1500], [5.0, 3.0, 1.4]))
	return ks_string(freq, dur, rng, sr, t60=t60, bright=0.35, pluck_pos=0.32, vel=vel)


def pluck_bass(freq: float, dur: float, rng: np.random.Generator, vel: float = 0.8, sr: int = SR) -> np.ndarray:
	"""Round low pluck (pizzicato-like bass / zhongruan)."""
	y = ks_string(freq, dur, rng, sr, t60=1.4, bright=0.25, pluck_pos=0.4, vel=vel)
	return D.filt(y, "lp", 1800.0, 0.7, sr=sr)


BODY_EQ = {
	"guzheng": [("peak", 125, 1.4, 4.0), ("peak", 260, 2.0, 3.0), ("peak", 520, 2.2, 2.0), ("peak", 1150, 2.5, 1.5),
		("highshelf", 6000, 0.7, -3.0)],
	"pipa": [("peak", 320, 2.0, 3.0), ("peak", 750, 2.5, 3.0), ("peak", 2100, 2.0, 2.0), ("highshelf", 7000, 0.7, -2.0)],
	"harp": [("peak", 200, 1.2, 2.0), ("highshelf", 5000, 0.7, -4.0)],
	"bass": [("peak", 110, 1.0, 3.0)],
}


def body(x: np.ndarray, kind: str, sr: int = SR) -> np.ndarray:
	"""Instrument body resonance EQ for a whole instrument bus."""
	y = x
	for k, f, q, g in BODY_EQ.get(kind, []):
		y = D.filt(y, k, f, q, g, sr)
	return y


# ---------------------------------------------------------------------------
# Continuous voices (flutes, erhu) rendered per phrase
# ---------------------------------------------------------------------------

@dataclass
class PNote:
	"""Note inside a phrase. Times in seconds relative to the phrase start."""
	t: float
	dur: float
	midi: float
	vel: float = 0.8
	slide: float = 0.0       # seconds of portamento into this note (0 = quick legato)
	vib: float = 1.0         # vibrato amount multiplier
	legato: bool = True      # tie to the previous note without re-articulation
	grace: float = 0.0       # semitones of an upper grace note (0 = none)
	accent: float = 0.0


@dataclass
class VoiceSpec:
	harmonics: list
	attack: float = 0.04
	release: float = 0.12
	vib_rate: float = 5.4
	vib_cents: float = 18.0
	vib_delay: float = 0.22
	breath: float = 0.06
	chiff: float = 0.0
	buzz: float = 0.0
	formant: list = field(default_factory=list)
	formant_mix: float = 0.0
	bow_noise: float = 0.0
	bright_follow: float = 0.06
	trem: float = 0.0
	lowcut: float = 120.0
	level: float = 1.0       # output normalization so voices peak near 1.0


DIZI = VoiceSpec([1, .55, .42, .26, .2, .14, .1, .07, .05, .04, .03, .02], attack=0.03, release=0.09, vib_rate=5.6,
	vib_cents=16, vib_delay=0.25, breath=0.05, chiff=0.35, buzz=0.22, trem=0.12, lowcut=250, level=0.5)
XIAO = VoiceSpec([1, .2, .09, .045, .02, .01], attack=0.07, release=0.18, vib_rate=4.8, vib_cents=12, vib_delay=0.35,
	breath=0.16, chiff=0.12, trem=0.08, lowcut=150, level=0.75)
ERHU = VoiceSpec([1.0 / (k ** 0.8) for k in range(1, 31)], attack=0.08, release=0.14, vib_rate=6.0, vib_cents=32,
	vib_delay=0.18, breath=0.0, formant=[(820, 2.2, 1.0), (1550, 3.0, 0.75), (2750, 4.0, 0.5), (4300, 5.0, 0.18)],
	formant_mix=0.7, bow_noise=0.035, bright_follow=0.05, lowcut=180, level=0.32)
HORN = VoiceSpec([1, .7, .5, .38, .3, .22, .16, .1, .07, .05, .03], attack=0.09, release=0.2, vib_rate=5.0,
	vib_cents=6, vib_delay=0.4, breath=0.02, bright_follow=0.12, lowcut=60, level=0.45)


def render_phrase(notes: list[PNote], spec: VoiceSpec, rng: np.random.Generator, sr: int = SR, tail: float = 0.4) -> np.ndarray:
	"""Renders a monophonic legato phrase with portamento, delayed vibrato,
	breath/bow noise and articulation."""
	if not notes:
		return np.zeros(1)
	end = max(nt.t + nt.dur for nt in notes) + tail
	n = D.ns(end, sr)
	t = D.taxis(n, sr)
	pitch = np.full(n, float(notes[0].midi))
	amp = np.zeros(n)
	vib_amt = np.zeros(n)
	art = np.ones(n)  # articulation dips
	prev_midi = notes[0].midi
	prev_end = -1.0
	for i, nt in enumerate(notes):
		s = D.ns(nt.t, sr) if nt.t > 0 else 0
		e = min(n, D.ns(nt.t + nt.dur, sr))
		if e <= s:
			continue
		connected = nt.legato and i > 0 and abs(nt.t - prev_end) < 0.03
		# Pitch: glide from previous pitch.
		pitch[s:] = nt.midi
		glide = nt.slide if nt.slide > 0 else (0.035 if connected else 0.0)
		if nt.slide > 0 and not connected:
			start_m = nt.midi - 2.0
		else:
			start_m = prev_midi
		if glide > 0:
			g = min(D.ns(glide, sr), e - s)
			w = 0.5 - 0.5 * np.cos(np.linspace(0, math.pi, g))
			pitch[s:s + g] = start_m + (nt.midi - start_m) * w
		if nt.grace:
			g = min(D.ns(0.055, sr), e - s)
			gl = min(D.ns(0.018, sr), g)
			pitch[s:s + g] = nt.midi + nt.grace
			w = 0.5 - 0.5 * np.cos(np.linspace(0, math.pi, gl))
			pitch[s + g - gl:s + g] = nt.midi + nt.grace * (1 - w)
		# Amplitude envelope for the note.
		ln = e - s
		env = np.ones(ln) * nt.vel
		att = D.ns(spec.attack * (0.5 if connected else 1.0), sr)
		att = min(att, ln)
		if not connected:
			env[:att] *= np.linspace(0, 1, att) ** 1.3
		else:
			dip = min(D.ns(0.05, sr), ln)
			art[s:s + dip] *= 1.0 - 0.18 * np.sin(np.linspace(0, math.pi, dip))
		# Slight swell then relax across long notes (phrasing).
		if nt.dur > 0.6:
			x = np.linspace(0, 1, ln)
			env *= 0.9 + 0.16 * np.sin(math.pi * np.clip(x * 1.2, 0, 1)) - 0.08 * x
		if nt.accent:
			k = min(D.ns(0.12, sr), ln)
			env[:k] *= 1.0 + nt.accent * np.linspace(1, 0, k)
		amp[s:e] = np.maximum(amp[s:e], env)
		rel = D.ns(spec.release, sr)
		nxt = notes[i + 1] if i + 1 < len(notes) else None
		tied_next = nxt is not None and nxt.legato and abs(nxt.t - (nt.t + nt.dur)) < 0.03
		if not tied_next:
			r_end = min(n, e + rel)
			amp[e:r_end] = np.maximum(amp[e:r_end], nt.vel * np.linspace(1, 0, r_end - e) ** 1.5)
		# Vibrato ramps in after a delay on longer notes.
		if nt.dur > 0.3 and nt.vib > 0:
			vd = D.ns(spec.vib_delay, sr)
			ramp = np.clip((np.arange(ln) - vd) / (0.35 * sr), 0, 1)
			vib_amt[s:e] = np.maximum(vib_amt[s:e], ramp * nt.vib)
		prev_midi = nt.midi
		prev_end = nt.t + nt.dur
	amp = D.onepole_lp(amp * art, 40.0, sr)
	vib_amt = D.onepole_lp(vib_amt, 6.0, sr)
	rate = spec.vib_rate * (1 + 0.06 * D.smooth_noise(n, 1.5, rng, sr))
	vib = np.sin(TAU * D.phase(rate, n, sr)) * vib_amt * spec.vib_cents / 100.0
	drift = 0.04 * D.smooth_noise(n, 0.7, rng, sr)
	f0 = 440.0 * 2.0 ** ((pitch + vib + drift - 69.0) / 12.0)
	ph = D.phase(f0, n, sr)
	logamp = np.log(np.maximum(amp, 1e-5))
	out = np.zeros(n)
	for k, a in enumerate(spec.harmonics, start=1):
		if a <= 0:
			continue
		mask = f0 * k < sr * 0.45
		bright = np.exp(logamp * (1.0 + spec.bright_follow * (k - 1)))
		part = a * np.sin(TAU * k * ph + rng.uniform(0, TAU)) * bright
		if spec.buzz > 0 and k >= 4:
			part *= 1.0 + spec.buzz * 3.0 * D.onepole_lp(D.white(n, rng), 300.0, sr)
		out += part * mask
	out *= 1.0 + spec.trem * vib_amt * np.sin(TAU * D.phase(rate, n, sr) + 1.3) * 0.5
	if spec.formant:
		fm = D.formants(out, spec.formant, sr)
		out = (1 - spec.formant_mix) * out + spec.formant_mix * fm * 2.2
	if spec.breath > 0:
		nz = D.white(n, rng)
		br = D.tv_filter(nz, "bp", np.clip(f0, 60, 8000), 6.0, sr=sr) * 1.4 + D.butter(nz, "high", 3000.0, 2, sr) * 0.35
		out += spec.breath * br * amp
	if spec.chiff > 0 or spec.bow_noise > 0:
		nz = D.white(n, rng)
		if spec.bow_noise > 0:
			out += spec.bow_noise * D.butter(nz, "band", (1500, 6000), 2, sr) * amp * (1 + 0.5 * D.smooth_noise(n, 8, rng, sr))
		if spec.chiff > 0:
			ch = np.zeros(n)
			for i, nt in enumerate(notes):
				connected = nt.legato and i > 0 and abs(nt.t - (notes[i - 1].t + notes[i - 1].dur)) < 0.03
				if connected:
					continue
				k = D.ns(0.03, sr)
				s = D.ns(nt.t, sr)
				D.place(ch, D.butter(D.white(k, rng), "band", (1800, 6500), 2, sr) * D.exp_decay(k, 0.03, sr) * nt.vel, s)
			out += spec.chiff * ch
	out = D.butter(out, "high", spec.lowcut, 2, sr)
	return out * spec.level


# ---------------------------------------------------------------------------
# Percussion
# ---------------------------------------------------------------------------

MEMBRANE = [1.0, 1.593, 2.136, 2.296, 2.653, 2.918, 3.156, 3.501]


def drum(f0: float, rng: np.random.Generator, vel: float = 0.8, t60: float = 1.0, sr: int = SR, drop: float = 0.35,
		modes: int = 6, stick: float = 0.4, stick_band=(200.0, 2500.0), dur: float | None = None, inflect=None) -> np.ndarray:
	"""Membrane drum (taiko, tanggu, frame drum): circular-membrane modes with a
	tension pitch drop, stick/hand transient."""
	dur = dur or min(t60 * 1.1 + 0.05, 4.0)
	n = D.ns(dur, sr)
	t = D.taxis(n, sr)
	bend = 1.0 + drop * vel * np.exp(-t / 0.035) + 0.06 * vel * np.exp(-t / 0.25)
	if inflect is not None:
		bend = bend * inflect(t)
	f = f0 * bend
	ph = D.phase(f, n, sr)
	y = np.zeros(n)
	amps = [1.0, 0.55, 0.38, 0.25, 0.18, 0.12, 0.08, 0.05]
	for i in range(min(modes, len(MEMBRANE))):
		decay = t60 * (1.0 / (1 + 0.9 * i))
		y += amps[i] * np.sin(TAU * MEMBRANE[i] * ph + rng.uniform(0, 1)) * D.exp_decay(n, decay, sr)
	y *= np.clip(t / 0.0015, 0, 1)
	k = D.ns(0.03, sr)
	hit = D.butter(D.white(k, rng), "band", stick_band, 2, sr) * D.exp_decay(k, 0.025, sr)
	D.place(y, hit * stick * (0.5 + vel), 0)
	return y * vel


def taiko(size: str, rng: np.random.Generator, vel: float = 0.8, sr: int = SR) -> np.ndarray:
	if size == "odaiko":
		return drum(52.0, rng, vel, 1.6, sr, drop=0.45, stick=0.5, stick_band=(150, 1500))
	if size == "nagado":
		return drum(92.0, rng, vel, 0.9, sr, drop=0.35, stick=0.5, stick_band=(200, 2500))
	if size == "shime":
		return drum(330.0, rng, vel, 0.18, sr, drop=0.12, modes=4, stick=0.9, stick_band=(1500, 7000))
	if size == "rim":  # "ka" stick on the rim
		return woodblock(1300.0, rng, vel, sr, t60=0.05)
	raise ValueError(size)


def tsuzumi(rng: np.random.Generator, vel: float = 0.8, high: bool = False, sr: int = SR) -> np.ndarray:
	"""Hourglass drum 'pon': pitch inflects up then settles as the cords are squeezed."""
	f0 = 420.0 if high else 270.0
	infl = lambda t: 1.0 + 0.12 * np.sin(np.clip(t / 0.25, 0, 1) * math.pi) * (1 - np.exp(-t / 0.02))
	return drum(f0, rng, vel, 0.45 if not high else 0.22, sr, drop=0.08, modes=3, stick=0.6, stick_band=(800, 5000), inflect=infl)


def frame_drum(rng: np.random.Generator, vel: float = 0.8, sr: int = SR) -> np.ndarray:
	return drum(150.0, rng, vel, 0.35, sr, drop=0.2, modes=5, stick=0.7, stick_band=(400, 4000))


def woodblock(freq: float, rng: np.random.Generator, vel: float = 0.8, sr: int = SR, t60: float = 0.09) -> np.ndarray:
	"""Muyu / temple block: hollow wooden modes from a mallet impulse."""
	n = D.ns(t60 * 2.5 + 0.02, sr)
	imp = np.zeros(n)
	imp[0] = 1.0
	imp[1] = -0.5
	y = D.modal(imp, [freq, freq * 2.57, freq * 4.03], [t60, t60 * 0.5, t60 * 0.3], [1.0, 0.45, 0.2], sr)
	click = D.butter(D.white(D.ns(0.003, sr), rng), "high", 2000.0, 2, sr)
	D.place(y, click * 0.15, 0)
	return D.norm_peak(y, vel)


def clapper(rng: np.random.Generator, vel: float = 0.8, sr: int = SR) -> np.ndarray:
	"""Ban (wooden clapper): two slabs clacking."""
	n = D.ns(0.12, sr)
	y = np.zeros(n)
	for k, g in ((0, 1.0), (D.ns(0.006, sr), 0.6)):
		imp = np.zeros(n)
		imp[k] = 1.0
		y += g * D.modal(imp, [1250, 2150, 3400, 5100], [0.035, 0.025, 0.02, 0.012], [1, .7, .5, .3], sr)
	nz = D.butter(D.white(n, rng), "band", (1500, 8000), 2, sr) * D.exp_decay(n, 0.02, sr)
	return D.norm_peak(y + nz * 0.004, vel)


def cymbal(rng: np.random.Generator, vel: float = 0.8, t60: float = 1.2, sr: int = SR, choke: float = 0.0) -> np.ndarray:
	"""Small Chinese cymbals (bo): dense inharmonic metal modes + wash."""
	dur = choke if choke > 0 else t60 * 1.1
	n = D.ns(dur, sr)
	freqs = np.exp(rng.uniform(math.log(450), math.log(9000), 34))
	amps = rng.uniform(0.2, 1.0, freqs.size) / np.sqrt(freqs / 450.0)
	decs = t60 * rng.uniform(0.3, 1.0, freqs.size) * (450.0 / freqs) ** 0.25
	y = D.additive(1.0, n, amps, sr, ratios=freqs, phases=rng.uniform(0, 1, freqs.size), decays=decs)
	wash = D.butter(D.white(n, rng), "high", 3000.0, 2, sr) * D.exp_decay(n, t60 * 0.6, sr)
	y = y / (np.max(np.abs(y)) + 1e-9) + 0.5 * wash
	y *= np.clip(D.taxis(n, sr) / 0.001, 0, 1)
	if choke > 0:
		y = D.fades(y, 0.0, choke * 0.5, sr)
	return D.norm_peak(y, vel)


def gong(kind: str, rng: np.random.Generator, vel: float = 0.8, sr: int = SR, dur: float | None = None) -> np.ndarray:
	"""Gongs: 'tamtam' (wash that blooms), 'opera_low' (pitch falls), 'opera_high'
	(pitch rises), 'bowl' (singing bowl)."""
	if kind == "tamtam":
		dur = dur or 7.0
		n = D.ns(dur, sr)
		t = D.taxis(n, sr)
		freqs = np.exp(rng.uniform(math.log(55), math.log(4200), 70))
		y = np.zeros(n)
		for f in freqs:
			bloom = 0.02 + 0.9 * (math.log(f / 55) / math.log(4200 / 55)) ** 1.5  # highs bloom later
			env = (1 - np.exp(-t / bloom)) * np.exp(-6.9 * t / (dur * rng.uniform(0.45, 0.95) * (300 / f) ** 0.18))
			y += rng.uniform(0.3, 1.0) * np.sin(TAU * f * t + rng.uniform(0, TAU)) * env / (f / 200) ** 0.35
		y = y / (np.max(np.abs(y)) + 1e-9)
		D.place(y, D.thump(0.4, 90, 60, 0.35, sr), 0, 0.6)
		shimmer = D.butter(D.white(n, rng), "band", (2000, 7000), 2, sr) * (1 - np.exp(-t / 0.6)) * np.exp(-t / 1.6)
		y += 0.08 * shimmer
		return D.norm_peak(y, vel)
	if kind in ("opera_low", "opera_high"):
		dur = dur or (3.0 if kind == "opera_low" else 1.6)
		n = D.ns(dur, sr)
		t = D.taxis(n, sr)
		if kind == "opera_low":
			f = 245.0 * (0.83 + 0.17 * np.exp(-t / 0.35))
		else:
			f = 690.0 * (1.12 - 0.12 * np.exp(-t / 0.22))
		ratios = [1.0, 1.52, 2.23, 2.94, 3.61, 4.4, 5.3]
		amps = [1.0, 0.5, 0.42, 0.3, 0.22, 0.14, 0.1]
		decs = [dur * 0.85, dur * 0.5, dur * 0.42, dur * 0.3, dur * 0.22, dur * 0.18, dur * 0.12]
		y = D.additive(f, n, amps, sr, ratios=ratios, phases=rng.uniform(0, 1, 7), decays=decs)
		k = D.ns(0.02, sr)
		D.place(y, D.butter(D.white(k, rng), "band", (600, 5000), 2, sr) * D.exp_decay(k, 0.015, sr) * 0.6, 0)
		return D.norm_peak(y * np.clip(t / 0.001, 0, 1), vel)
	if kind == "bowl":
		dur = dur or 6.0
		return bell(220.0, dur, rng, "bowl", vel, sr)
	raise ValueError(kind)


BELLS = {
	# ratio, amp, t60 scale
	"temple": ([0.5, 1.0, 1.19, 1.5, 2.0, 2.52, 2.66, 3.01, 4.07, 5.2], [0.7, 1.0, 0.6, 0.45, 0.5, 0.3, 0.25, 0.2, 0.12, 0.06],
		[1.0, 0.85, 0.6, 0.55, 0.45, 0.35, 0.3, 0.25, 0.15, 0.1]),
	"chime": ([1.0, 2.756, 5.404, 8.933], [1.0, 0.45, 0.22, 0.1], [1.0, 0.45, 0.22, 0.12]),
	"small": ([1.0, 2.0, 2.92, 4.16, 5.43], [1.0, 0.35, 0.3, 0.15, 0.08], [1.0, 0.5, 0.35, 0.2, 0.12]),
	"bowl": ([1.0, 2.71, 5.15, 8.17], [1.0, 0.4, 0.18, 0.07], [1.0, 0.55, 0.3, 0.15]),
	"glass": ([1.0, 2.32, 4.25, 6.63, 9.38], [1.0, 0.5, 0.3, 0.16, 0.08], [1.0, 0.4, 0.25, 0.14, 0.08]),
}


def bell(freq: float, dur: float, rng: np.random.Generator, kind: str = "small", vel: float = 0.8, sr: int = SR,
		t60: float | None = None) -> np.ndarray:
	"""Modal bell with beating partial pairs and a strike transient."""
	ratios, amps, decs = BELLS[kind]
	t60 = t60 or dur * 0.9
	n = D.ns(dur, sr)
	y = np.zeros(n)
	for r, a, dsc in zip(ratios, amps, decs):
		if freq * r > sr * 0.45:
			continue
		beat = 1.0 + rng.uniform(0.0008, 0.003)
		dec = [t60 * dsc] * 2
		y += D.additive(freq * r, n, [a * 0.6, a * 0.4], sr, ratios=[1.0, beat], phases=rng.uniform(0, 1, 2), decays=dec)
	k = D.ns(0.004, sr)
	strike = D.butter(D.white(k, rng), "high", min(freq * 2, 8000), 2, sr) * D.exp_decay(k, 0.003, sr)
	D.place(y, strike * 0.25, 0)
	y *= np.clip(D.taxis(n, sr) / 0.0007, 0, 1)
	return D.norm_peak(y, vel)


# ---------------------------------------------------------------------------
# Sustained synth voices
# ---------------------------------------------------------------------------

def string_pad(midis, dur: float, rng: np.random.Generator, vel: float = 0.6, sr: int = SR, attack: float = 1.0,
		release: float = 1.2, bright: float = 1600.0, voices: int = 3, detune: float = 9.0) -> np.ndarray:
	"""Warm section strings: detuned band-limited saws, slow attack, gentle filter."""
	n = D.ns(dur + release, sr)
	out = np.zeros(n)
	t = D.taxis(n, sr)
	for m in midis:
		f = D.midi_hz(m)
		for v in range(voices):
			cents = (v - (voices - 1) / 2) * detune + rng.normal(0, 2)
			drift = 1 + 0.0015 * D.smooth_noise(n, 0.5, rng, sr) + 0.0025 * np.sin(TAU * 5.2 * t + rng.uniform(0, TAU)) * np.clip(t / 1.5, 0, 1)
			out += D.saw(f * 2 ** (cents / 1200) * drift, n, sr, rng.uniform(0, 1))
	out /= max(1, len(midis) * voices) ** 0.5
	env = np.clip(t / attack, 0, 1) ** 1.6 * np.clip((dur + release - t) / release, 0, 1) ** 1.2
	env = np.where(t < dur, np.clip(t / attack, 0, 1) ** 1.6, np.clip(t / attack, 0, 1) ** 1.6 * np.clip(1 - (t - dur) / release, 0, 1) ** 1.5)
	cut = bright * (0.45 + 0.55 * env) * (0.6 + 0.6 * vel)
	y = D.tv_filter(out, "lp", cut, 0.8, sr=sr, block=256)
	y = D.filt(y, "lp", bright * 2.5, 0.7, sr=sr)
	return y * env * vel


def choir_pad(midis, dur: float, rng: np.random.Generator, vel: float = 0.5, sr: int = SR, vowel: str = "a",
		attack: float = 1.4, release: float = 1.6) -> np.ndarray:
	"""Wordless choir: detuned saw ensemble through vowel formants."""
	V = {"a": [(730, 6, 1.0), (1090, 8, 0.6), (2440, 10, 0.3)], "o": [(450, 6, 1.0), (800, 8, 0.5), (2830, 10, 0.15)],
		"u": [(325, 6, 1.0), (700, 8, 0.3), (2530, 10, 0.1)]}[vowel]
	raw = string_pad(midis, dur, rng, 1.0, sr, attack, release, bright=5000.0, voices=4, detune=14.0)
	y = D.formants(raw, V, sr)
	breath = D.butter(D.white(raw.shape[0], rng), "band", (2000, 6000), 2, sr) * np.abs(raw).mean() * 0.4
	return (y * 2.5 + breath) * vel


def brass(midi: float, dur: float, rng: np.random.Generator, vel: float = 0.8, sr: int = SR) -> np.ndarray:
	"""Low brass-like synth (Fire Nation horns): scooped pitch, filter blat on
	the attack, mild overdrive."""
	rel = 0.25
	n = D.ns(dur + rel, sr)
	t = D.taxis(n, sr)
	f = D.midi_hz(midi) * (1 - 0.025 * np.exp(-t / 0.05)) * (1 + 0.002 * D.smooth_noise(n, 3, rng, sr))
	y = 0.7 * D.saw(f, n, sr) + 0.5 * D.saw(f * 1.004, n, sr, 0.3) + 0.25 * D.square(f * 0.5, n, sr)
	env = np.where(t < dur, np.clip(t / 0.06, 0, 1), np.clip(1 - (t - dur) / rel, 0, 1)) ** 1.3
	blat = 1.0 + 1.6 * vel * np.exp(-t / 0.12)
	cut = (250.0 + 1500.0 * vel) * blat * (0.5 + 0.5 * env)
	y = D.tv_filter(y, "lp", np.minimum(cut, 9000), 1.1, sr=sr, block=128)
	y = D.saturate(y * 1.8, 1.0)
	breath = D.butter(D.white(n, rng), "band", (800, 3000), 2, sr) * 0.03
	return (y + breath) * env * vel


def staccato_strings(midi: float, rng: np.random.Generator, vel: float = 0.8, dur: float = 0.16, sr: int = SR) -> np.ndarray:
	"""Short bowed strings (spiccato) for ostinatos."""
	n = D.ns(dur + 0.12, sr)
	t = D.taxis(n, sr)
	f = D.midi_hz(midi)
	y = D.saw(f, n, sr, rng.uniform(0, 1)) + D.saw(f * 1.006, n, sr, rng.uniform(0, 1)) * 0.8
	env = np.clip(t / 0.006, 0, 1) * np.exp(-t / (dur * 0.45))
	y = D.filt(y, "lp", 1200 + 2200 * vel, 0.9, sr=sr)
	nz = D.butter(D.white(n, rng), "band", (1500, 5000), 2, sr) * np.exp(-t / 0.02) * 0.25
	return (y * 0.5 + nz) * env * vel


def drone(midi: float, dur: float, rng: np.random.Generator, vel: float = 0.5, sr: int = SR, kind: str = "low") -> np.ndarray:
	"""Low sustained drone (bowed bass / throat-like) with slow movement."""
	n = D.ns(dur, sr)
	f = D.midi_hz(midi) * (1 + 0.003 * D.smooth_noise(n, 0.3, rng, sr))
	y = D.saw(f, n, sr) + 0.6 * D.saw(f * 1.5, n, sr) * (0.3 if kind == "fifth" else 0.0) + 0.4 * D.saw(f * 0.5, n, sr)
	cut = 380 + 220 * (1 + D.smooth_noise(n, 0.2, rng, sr))
	y = D.tv_filter(y, "lp", cut, 1.4, sr=sr, block=256)
	return y * vel


def wind_bed(dur: float, rng: np.random.Generator, sr: int = SR, base: float = 500.0, q: float = 1.2) -> np.ndarray:
	"""Musical wind swell used inside the Air Temple / Water Tribe pieces."""
	n = D.ns(dur, sr)
	src = D.pink(n, rng)
	mod = 0.5 + 0.5 * D.smooth_noise(n, 0.25, rng, sr)
	fc = base * 2 ** (1.6 * mod)
	y = D.tv_filter(src, "bp", fc, q, sr=sr, block=256)
	return y * (0.3 + 0.7 * mod)
