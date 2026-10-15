"""Small composition engine for the procedural score.

Melodies are written in jianpu (Chinese numbered notation, 1 = do of the key):

	"5, 1 2_ 3_ | 5- 3 2 | ^6 5 3 2~ | 1--- |"

	1..7      scale degree of the major scale of the key (0 = rest)
	#4 b7     accidentals
	'  ,      octave up / down (repeatable)
	_         halves the duration (eighth, sixteenth with __)
	-         adds one beat (tied extension, jianpu dash)
	.         dotted (x1.5)
	^         upper grace note        /  slide up into the note   \\  fall from above
	>         accent                  ~  extra vibrato            *  staccato   t  tremolo (pipa)
	|         bar line (ignored, for readability)

Harmony uses chord symbols on scale degrees ("6m7", "4add9", "5sus4", "1/3",
"2q" quartal, "6m5" open fifth). A `Score` collects melody lines, chord
timelines and generated parts (pads, arpeggios, bass, drum patterns, one-shot
hits) and renders/mixes them into a stereo loop.
"""
from __future__ import annotations

import math
import re
from dataclasses import dataclass, field

import numpy as np

import dsp as D
import instruments as I
from dsp import SR

MAJOR = {1: 0, 2: 2, 3: 4, 4: 5, 5: 7, 6: 9, 7: 11}
TOKEN = re.compile(r"^(?P<pre>[\^/\\>]*)(?P<acc>[#b]?)(?P<deg>[0-7])(?P<rest>[',\-_.~*>t]*)$")
CHORD = re.compile(r"^(?P<acc>[#b]?)(?P<deg>[1-7])(?P<q>[a-z0-9]*)(?:/(?P<bacc>[#b]?)(?P<bass>[1-7]))?$")
QUALITIES = {
	"": [0, 4, 7], "m": [0, 3, 7], "sus2": [0, 2, 7], "sus4": [0, 5, 7], "add9": [0, 4, 7, 14],
	"madd9": [0, 3, 7, 14], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10], "maj7": [0, 4, 7, 11], "5": [0, 7],
	"m5": [0, 7], "q": [0, 5, 10], "dim": [0, 3, 6], "6": [0, 4, 7, 9], "m6": [0, 3, 7, 9], "sus24": [0, 2, 5, 7],
}


@dataclass
class Note:
	beat: float
	dur: float
	midi: float | None
	vel: float = 0.8
	grace: float = 0.0
	slide: float = 0.0
	fall: bool = False
	accent: float = 0.0
	vib: float = 1.0
	stacc: bool = False
	trem: bool = False


def degree_midi(deg: int, acc: str, octv: int, key: int) -> int:
	m = key + MAJOR[deg] + 12 * octv
	if acc == "#":
		m += 1
	elif acc == "b":
		m -= 1
	return m


def jianpu(text: str, key: int, octave: int = 0, vel: float = 0.8) -> list[Note]:
	"""Parses jianpu text into notes (beats relative to the start of the line)."""
	notes: list[Note] = []
	beat = 0.0
	for tok in text.split():
		if tok == "|":
			continue
		m = TOKEN.match(tok)
		if not m:
			raise ValueError("bad jianpu token %r in %r" % (tok, text))
		dur = _token_beats(m["rest"])
		deg = int(m["deg"])
		if deg == 0:
			beat += dur
			continue
		octv = octave + m["rest"].count("'") - m["rest"].count(",")
		midi = degree_midi(deg, m["acc"], octv, key)
		pre, post = m["pre"], m["rest"]
		notes.append(Note(beat, dur, midi, vel, grace=2.0 if "^" in pre else 0.0, slide=0.12 if "/" in pre else 0.0,
			fall="\\" in pre, accent=0.35 if (">" in pre or ">" in post) else 0.0, vib=1.6 if "~" in post else 1.0,
			stacc="*" in post, trem="t" in post))
		beat += dur
	return notes


def _token_beats(rest: str) -> float:
	u = rest.count("_")
	return 0.5 ** u * (1.5 if "." in rest else 1.0) + rest.count("-")


def jianpu_end(text: str) -> float:
	"""Length of a jianpu line in beats."""
	beat = 0.0
	for tok in text.split():
		if tok == "|":
			continue
		m = TOKEN.match(tok)
		if not m:
			raise ValueError("bad jianpu token %r" % tok)
		beat += _token_beats(m["rest"])
	return beat


def chord_tones(sym: str, key: int) -> tuple[list[int], int]:
	"""Returns (pitch classes as absolute midi near the key, bass midi)."""
	m = CHORD.match(sym)
	if not m:
		raise ValueError("bad chord %r" % sym)
	root = degree_midi(int(m["deg"]), m["acc"], 0, key)
	q = m["q"]
	if q not in QUALITIES:
		raise ValueError("unknown chord quality %r" % q)
	tones = [root + i for i in QUALITIES[q]]
	bass = root
	if m["bass"]:
		bass = degree_midi(int(m["bass"]), m["bacc"], 0, key)
	return tones, bass


def voice_chord(tones: list[int], center: int, spread: bool = False) -> list[int]:
	"""Places chord tones around `center` (close voicing; `spread` opens it)."""
	out = []
	for t in tones:
		p = t
		while p < center - 7:
			p += 12
		while p > center + 6:
			p -= 12
		out.append(p)
	out = sorted(set(out))
	if spread and len(out) >= 3:
		out[1] -= 12
		out = sorted(out)
	return out


# ---------------------------------------------------------------------------
# Instruments in the mix
# ---------------------------------------------------------------------------

@dataclass
class Inst:
	kind: str                 # pluck | phrase | pad | choir | brass | stacc | drum | fx | wind
	pan: float = 0.0
	gain: float = 1.0
	send: float = 0.25        # reverb send
	echo: float = 0.0         # tempo delay send
	body: str = ""            # body EQ preset for plucks
	params: dict = field(default_factory=dict)


@dataclass
class Event:
	beat: float
	inst: str
	midi: object
	dur: float
	vel: float
	note: Note | None = None
	extra: dict = field(default_factory=dict)


class Score:
	"""Collects events on a beat grid and renders a seamless stereo loop."""

	def __init__(self, bpm: float, bars: int, key: int, beats_per_bar: int = 4, swing: float = 0.0):
		self.bpm = bpm
		self.bars = bars
		self.key = key
		self.bpb = beats_per_bar
		self.swing = swing
		self.events: list[Event] = []
		self.insts: dict[str, Inst] = {}
		self.chords: dict[int, list[tuple[float, str]]] = {}
		self.reverb = dict(seconds=3.0, t60_low=2.6, t60_high=1.3, predelay=0.025, brightness=6500.0, wet=0.28)
		self.echo_time = 60.0 / bpm * 0.75

	# --- timing -----------------------------------------------------------------
	@property
	def beat_s(self) -> float:
		return 60.0 / self.bpm

	@property
	def loop_seconds(self) -> float:
		return self.bars * self.bpb * self.beat_s

	def bar_beat(self, bar: float) -> float:
		return bar * self.bpb

	def sec(self, beat: float) -> float:
		if self.swing > 0:
			frac = beat % 1.0
			if abs(frac - 0.5) < 1e-6:
				beat += self.swing * 0.5
		return beat * self.beat_s

	# --- writing -----------------------------------------------------------------
	def inst(self, name: str, kind: str, **kw) -> None:
		self.insts[name] = Inst(kind, **kw)

	def melody(self, inst: str, bar: float, text: str, octave: int = 0, vel: float = 0.8, transpose: int = 0) -> float:
		"""Adds a jianpu line starting at `bar`. Returns the bar after the line."""
		b0 = self.bar_beat(bar)
		# Every bar written with '|' must be full: catches rhythm typos early.
		for i, chunk in enumerate(text.split("|")):
			if chunk.strip() and abs(jianpu_end(chunk) - self.bpb) > 1e-6:
				raise ValueError("%s bar %d of line at bar %s has %.2f beats: %r" % (inst, i + 1, bar, jianpu_end(chunk), chunk))
		for nt in jianpu(text, self.key + transpose, octave, vel):
			self.events.append(Event(b0 + nt.beat, inst, nt.midi, nt.dur, nt.vel, nt))
		return bar + jianpu_end(text) / self.bpb

	def progression(self, bar: int, symbols: str, bars_each: float = 1.0) -> None:
		"""Sets chords from `bar`: 'symbol symbol ...' each lasting bars_each bars.
		A symbol 'A:B' splits the bar in half."""
		b = float(bar)
		for sym in symbols.split():
			parts = sym.split(":")
			for k, p in enumerate(parts):
				start = b + k * bars_each / len(parts)
				self.chords.setdefault(int(math.floor(start + 1e-6)), []).append((start, p))
			b += bars_each

	def chord_at(self, bar_pos: float) -> str:
		best = None
		for bb in sorted(self.chords):
			for start, sym in self.chords[bb]:
				if start <= bar_pos + 1e-6:
					best = sym
		return best or "1"

	def chord_spans(self, bar: int, nbars: int) -> list[tuple[float, float, str]]:
		"""(start_bar, end_bar, symbol) segments covering [bar, bar+nbars)."""
		starts = sorted({s for v in self.chords.values() for s, _ in v if bar <= s < bar + nbars} | {float(bar)})
		out = []
		for i, s in enumerate(starts):
			e = starts[i + 1] if i + 1 < len(starts) else float(bar + nbars)
			out.append((s, e, self.chord_at(s)))
		return out

	def pad(self, inst: str, bar: int, nbars: int, vel: float = 0.5, center: int | None = None, spread: bool = False,
			octave: int = 0) -> None:
		center = center if center is not None else self.key + 2
		for s, e, sym in self.chord_spans(bar, nbars):
			tones, _ = chord_tones(sym, self.key)
			v = voice_chord(tones, center + 12 * octave, spread)
			self.events.append(Event(self.bar_beat(s), inst, v, (e - s) * self.bpb, vel))

	def arp(self, inst: str, bar: int, nbars: int, pattern: list, step: float = 0.5, vel: float = 0.6,
			center: int | None = None, accent_every: int = 0) -> None:
		"""Arpeggiates the chord timeline. `pattern` items index the voiced chord
		(0 = lowest); +10 adds an octave, None rests."""
		center = center if center is not None else self.key
		b = self.bar_beat(bar)
		end = self.bar_beat(bar + nbars)
		i = 0
		while b < end - 1e-6:
			sym = self.chord_at(b / self.bpb)
			tones, _ = chord_tones(sym, self.key)
			v = voice_chord(tones, center)
			p = pattern[i % len(pattern)]
			if p is not None:
				o, idx = divmod(p, 10)
				m = v[idx % len(v)] + 12 * (o + idx // len(v))
				acc = 1.15 if accent_every and i % accent_every == 0 else 1.0
				self.events.append(Event(b, inst, m, step, vel * acc))
			b += step
			i += 1

	def bass(self, inst: str, bar: int, nbars: int, rhythm: list[tuple[float, float]], vel: float = 0.7,
			octave: int = -2, fifth_on: tuple = ()) -> None:
		"""Bass on chord roots. rhythm = [(beat_in_bar, dur_beats), ...]; indices in
		`fifth_on` play the fifth instead of the root."""
		for k in range(nbars):
			for j, (bt, du) in enumerate(rhythm):
				pos = self.bar_beat(bar + k) + bt
				sym = self.chord_at(pos / self.bpb)
				tones, bass = chord_tones(sym, self.key)
				m = bass + 12 * octave
				if j in fifth_on:
					m += 7
				while m > 50:   # keep the bass between C2 and D3
					m -= 12
				while m < 36:
					m += 12
				self.events.append(Event(pos, inst, m, du, vel))

	def drums(self, inst: str, bar: int, nbars: int, pattern: str, vel: float = 0.8, steps_per_beat: int = 4,
			ramp: tuple | None = None, **extra) -> None:
		"""Step pattern per bar: X accent, x normal, o ghost, . rest (spaces ignored).
		`ramp` = (v0, v1) scales velocity across the bars (crescendo)."""
		pat = pattern.replace(" ", "")
		for k in range(nbars):
			r = 1.0 if ramp is None else ramp[0] + (ramp[1] - ramp[0]) * (k / max(nbars - 1, 1))
			for i, ch in enumerate(pat):
				if ch == ".":
					continue
				lv = {"X": 1.0, "x": 0.72, "o": 0.4}.get(ch, 0.7)
				pos = self.bar_beat(bar + k) + i / steps_per_beat
				self.events.append(Event(pos, inst, None, 0.25, vel * lv * r, extra=dict(extra)))

	def hit(self, inst: str, bar: float, beat: float = 0.0, vel: float = 0.8, midi=None, dur: float = 4.0, **extra) -> None:
		self.events.append(Event(self.bar_beat(bar) + beat, inst, midi, dur, vel, extra=dict(extra)))

	def gliss(self, inst: str, bar: float, beat: float, degrees: list[int], span: float, vel: float = 0.5, octave: int = 0) -> None:
		"""Guzheng-style glissando across pentatonic degrees within `span` beats."""
		k = len(degrees)
		for i, dgr in enumerate(degrees):
			o, d = divmod(dgr - 1, 7) if dgr > 0 else (-1, (dgr - 1) % 7)
			m = degree_midi(d + 1, "", octave + o, self.key)
			self.events.append(Event(self.bar_beat(bar) + beat + span * i / k, inst, m, 1.0, vel * (0.7 + 0.3 * i / k)))

	# --- rendering ---------------------------------------------------------------
	def render(self, rng: np.random.Generator, tail: float = 7.0) -> np.ndarray:
		total = self.loop_seconds + tail
		n = D.ns(total)
		buses: dict[str, np.ndarray] = {name: np.zeros(n) for name in self.insts}
		cache: dict = {}
		by_inst: dict[str, list[Event]] = {}
		for ev in self.events:
			if ev.inst not in self.insts:
				raise KeyError("instrument %r not declared" % ev.inst)
			by_inst.setdefault(ev.inst, []).append(ev)
		for name, evs in by_inst.items():
			ins = self.insts[name]
			evs.sort(key=lambda e: e.beat)
			if ins.kind == "phrase":
				self._render_phrases(buses[name], evs, ins, rng)
				continue
			for ev in evs:
				t = self.sec(ev.beat)
				jitter = rng.normal(0, 0.004 if ins.kind == "drum" else 0.007)
				t = max(0.0, t + jitter)
				vel = float(np.clip(ev.vel * (1 + rng.normal(0, 0.05)), 0.05, 1.3))
				sig = self._render_event(ins, ev, vel, rng, cache)
				if sig is not None:
					D.place(buses[name], sig, D.ns(t))
		# Mix: bodies, pans, reverb/echo sends.
		dry = np.zeros((2, n))
		send = np.zeros((2, n))
		echo = np.zeros((2, n))
		for name, buf in buses.items():
			ins = self.insts[name]
			if ins.body:
				buf = I.body(buf, ins.body)
			st = D.pan(buf, ins.pan) * ins.gain
			dry += st
			if ins.send > 0:
				send += st * ins.send
			if ins.echo > 0:
				echo += st * ins.echo
		if np.any(echo):
			e = np.stack([D.echo(echo[0], self.echo_time, 0.42, 1.0, damp_hz=3500.0) - echo[0],
				D.echo(echo[1], self.echo_time * 1.5, 0.38, 1.0, damp_hz=3500.0) - echo[1]])
			dry += e * 0.6
			send += e * 0.3
		rv = self.reverb
		ir = D.make_ir(rv["seconds"], rng, t60_low=rv["t60_low"], t60_high=rv["t60_high"], predelay=rv["predelay"],
			brightness=rv["brightness"])
		wet = D.reverb(send, ir, 1.0, 0.0, tail=False)
		mix = dry + wet * rv["wet"] * 3.0
		mix = D.butter(mix, "high", 28.0, 2)
		return D.fold_tail(mix, D.ns(self.loop_seconds))

	def _render_event(self, ins: Inst, ev: Event, vel: float, rng, cache) -> np.ndarray | None:
		k = ins.kind
		p = ins.params
		vb = round(vel * 4) / 4
		var = int(rng.integers(0, 3))
		if k == "pluck":
			synth = p.get("synth", "guzheng")
			nt = ev.note
			ring = p.get("ring", 1.6)
			dur_s = float(np.clip(ev.dur * self.beat_s + ring, 0.5, p.get("max_len", 4.5)))
			dur_s = round(dur_s * 2) / 2
			trem = nt is not None and nt.trem
			bend = nt is not None and (nt.slide > 0 or nt.vib > 1.2 or nt.fall)
			key = (synth, ev.midi, vb, dur_s, var, trem, bend)
			if key not in cache:
				f = D.midi_hz(ev.midi)
				if synth == "pipa":
					cache[key] = I.pipa(f, dur_s, rng, vb, tremolo=14.0 if trem else 0.0)
				elif synth == "harp":
					cache[key] = I.harp(f, dur_s, rng, vb)
				elif synth == "bass":
					cache[key] = I.pluck_bass(f, dur_s, rng, vb)
				else:
					bc = None
					if bend:
						m = D.ns(dur_s)
						tt = D.taxis(m)
						if nt.slide > 0:  # press up into the note from below
							bc = -180.0 * np.exp(-tt / 0.09)
						elif nt.fall:
							bc = -150.0 * np.clip((tt - 0.35) / 0.4, 0, 1)
						else:  # left-hand vibrato (rou xian)
							bc = 30.0 * np.sin(2 * math.pi * 5.2 * tt) * np.clip((tt - 0.15) / 0.3, 0, 1)
					cache[key] = I.guzheng(f, dur_s, rng, vb, bend_cents=bc)
			return cache[key] * vel / max(vb, 0.05)
		if k in ("pad", "choir"):
			dur_s = ev.dur * self.beat_s
			if k == "pad":
				return I.string_pad(ev.midi, dur_s, rng, vel, attack=p.get("attack", 1.0), release=p.get("release", 1.4),
					bright=p.get("bright", 1600.0))
			return I.choir_pad(ev.midi, dur_s, rng, vel, vowel=p.get("vowel", "a"), attack=p.get("attack", 1.4))
		if k == "brass":
			return I.brass(ev.midi, ev.dur * self.beat_s * p.get("legato", 0.9), rng, vel)
		if k == "stacc":
			key = ("st", ev.midi, vb, var)
			if key not in cache:
				cache[key] = I.staccato_strings(ev.midi, rng, vb, p.get("len", 0.16))
			return cache[key] * vel / max(vb, 0.05)
		if k == "drum":
			synth = p.get("synth", "taiko")
			key = (synth, p.get("size"), vb, var)
			if key not in cache:
				if synth == "taiko":
					cache[key] = I.taiko(p.get("size", "nagado"), rng, vb)
				elif synth == "tsuzumi":
					cache[key] = I.tsuzumi(rng, vb, p.get("high", False))
				elif synth == "frame":
					cache[key] = I.frame_drum(rng, vb)
				elif synth == "woodblock":
					cache[key] = I.woodblock(p.get("freq", 800.0), rng, vb, t60=p.get("t60", 0.09))
				elif synth == "clapper":
					cache[key] = I.clapper(rng, vb)
				elif synth == "cymbal":
					cache[key] = I.cymbal(rng, vb, p.get("t60", 1.0), choke=p.get("choke", 0.0))
				elif synth == "bowl":
					cache[key] = I.gong("bowl", rng, vb, dur=p.get("dur", 5.0))
				else:
					raise ValueError(synth)
			return cache[key] * vel / max(vb, 0.05)
		if k == "fx":
			synth = p.get("synth", "tamtam")
			if synth in ("tamtam", "opera_low", "opera_high", "bowl"):
				return I.gong(synth, rng, vel, dur=ev.extra.get("dur", p.get("dur")))
			if synth == "bell":
				return I.bell(D.midi_hz(ev.midi), p.get("dur", 3.0), rng, p.get("type", "small"), vel)
			if synth == "drone":
				return I.drone(ev.midi, ev.dur * self.beat_s, rng, vel, kind=p.get("type", "low")) * D.fades(
					np.ones(D.ns(ev.dur * self.beat_s)), 1.5, 2.0)
			if synth == "wind":
				return I.wind_bed(ev.dur * self.beat_s, rng, base=p.get("base", 500.0)) * vel * D.fades(
					np.ones(D.ns(ev.dur * self.beat_s)), 2.0, 2.5)
			raise ValueError(synth)
		raise ValueError(k)

	def _render_phrases(self, bus: np.ndarray, evs: list[Event], ins: Inst, rng) -> None:
		spec = {"dizi": I.DIZI, "xiao": I.XIAO, "erhu": I.ERHU, "horn": I.HORN}[ins.params.get("voice", "dizi")]
		gap_break = ins.params.get("gap_break", 0.75)
		phrases: list[list[Event]] = []
		cur: list[Event] = []
		for ev in evs:
			if cur:
				prev = cur[-1]
				gap = ev.beat - (prev.beat + prev.dur)
				if gap > gap_break:
					phrases.append(cur)
					cur = []
			cur.append(ev)
		if cur:
			phrases.append(cur)
		for ph in phrases:
			t0 = self.sec(ph[0].beat)
			notes = []
			for i, ev in enumerate(ph):
				nt = ev.note or Note(ev.beat, ev.dur, ev.midi, ev.vel)
				t = self.sec(ev.beat) - t0
				d = ev.dur * self.beat_s
				if nt.stacc:
					d *= 0.5
				prev_end = None if i == 0 else self.sec(ph[i - 1].beat + ph[i - 1].dur) - t0
				legato = prev_end is not None and abs(prev_end - t) < 0.02 and not nt.stacc and not (ph[i - 1].note and ph[i - 1].note.stacc)
				slide = nt.slide if nt.slide > 0 else 0.0
				notes.append(I.PNote(t, d, float(ev.midi), float(np.clip(ev.vel * (1 + rng.normal(0, 0.04)), 0.1, 1.2)),
					slide=slide, vib=nt.vib, legato=legato, grace=nt.grace, accent=nt.accent))
			sig = I.render_phrase(notes, spec, rng)
			D.place(bus, sig, D.ns(t0 + rng.normal(0, 0.004)) if t0 > 0.01 else 0)
