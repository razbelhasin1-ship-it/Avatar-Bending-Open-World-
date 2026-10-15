#!/usr/bin/env python3
"""Procedural audio generator for Avatar: The Four Nations.

Synthesizes every sound listed in docs/ARCHITECTURE.md ("Audio names") from
scratch (numpy/scipy only, no samples) and writes them to assets/audio:

  sfx/<name>[_1.._N].wav   16-bit PCM mono one-shots and *_loop sounds (smpl loop chunk)
  sfx/amb_*.ogg            stereo seamless ambience loops (OGG Vorbis)
  music/music_*.ogg        stereo seamless music loops (OGG Vorbis)

Usage:
  python3 tools/audiogen/generate.py                 # everything (~5-10 min on 2 cores)
  python3 tools/audiogen/generate.py --only 'step_*,ui_*' --jobs 2
  python3 tools/audiogen/generate.py --skip-music
  python3 tools/audiogen/generate.py --list

Afterwards run `godot --headless --path . --import` and
`python3 tools/audiogen/set_import_loops.py` (sets loop=true on music/ambience imports).
A loudness/loop analysis of every file is written to tools/audiogen/report.md.
"""
from __future__ import annotations

import argparse
import fnmatch
import importlib
import json
import multiprocessing as mp
import os
import re
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import dsp as D  # noqa: E402
import master as M  # noqa: E402
from registry import CATEGORY_TARGETS, SOUNDS, SoundDef  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio")
MODULES = ["sfx_ui", "sfx_steps", "sfx_body", "sfx_air", "sfx_earth", "sfx_fire", "sfx_water", "sfx_creatures",
	"ambience", "music_tracks"]
REPORT_JSON = os.path.join(HERE, "report.json")
REPORT_MD = os.path.join(HERE, "report.md")
OGG_QUALITY = {"music": 0.32, "amb": 0.28}


def load_modules() -> None:
	for m in MODULES:
		importlib.import_module(m)


def seed_for(name: str, v: int) -> int:
	return zlib.crc32(("%s:%d" % (name, v)).encode())


def out_dir(d: SoundDef) -> str:
	return os.path.join(OUT, "music" if d.kind == "music" else "sfx")


def file_names(d: SoundDef, ext: str) -> list[str]:
	if d.variants == 1:
		return ["%s.%s" % (d.name, ext)]
	return ["%s_%d.%s" % (d.name, i + 1, ext) for i in range(d.variants)]


def clean_stale(d: SoundDef, keep: list[str]) -> None:
	"""Removes files of this sound that the new render will not produce (old
	variant counts / extensions) together with their .import sidecars."""
	folder = out_dir(d)
	if not os.path.isdir(folder):
		return
	pat = re.compile(r"^%s(_[1-9])?\.(wav|ogg|mp3)$" % re.escape(d.name))
	for f in os.listdir(folder):
		if pat.match(f) and f not in keep:
			for p in (os.path.join(folder, f), os.path.join(folder, f + ".import")):
				if os.path.exists(p):
					os.remove(p)


def resample(x: np.ndarray, sr_in: int, sr_out: int, circular: bool = False) -> np.ndarray:
	"""Polyphase resampling; `circular` wraps the edges so loops stay seamless."""
	if sr_in == sr_out:
		return x
	from math import gcd

	from scipy import signal as S
	g = gcd(sr_in, sr_out)
	up, down = sr_out // g, sr_in // g
	if not circular:
		return S.resample_poly(x, up, down, axis=-1)
	p = down * max(1, 4096 // down)
	xp = np.concatenate([x[..., -p:], x, x[..., :p]], axis=-1)
	y = S.resample_poly(xp, up, down, axis=-1)
	q = p * up // down
	n_out = x.shape[-1] * up // down
	return y[..., q:q + n_out]


def render_sound(d: SoundDef) -> list[tuple[str, dict]]:
	results = []
	stereo_ogg = d.kind in ("music", "amb")
	ext = "ogg" if stereo_ogg and M.ogg_backend() else "wav"
	names = file_names(d, ext)
	folder = out_dir(d)
	os.makedirs(folder, exist_ok=True)
	clean_stale(d, names)
	target = CATEGORY_TARGETS[d.category] + d.gain_db
	for v, fname in enumerate(names):
		rng = np.random.default_rng(seed_for(d.name, v))
		sr = d.sr
		is_loop = d.loop is not None or d.kind == "music"
		if d.kind == "music":
			x = d.fn(rng)
			y = M.master_loop(x, D.SR, target, -1.5)
		elif d.loop is not None:
			loop_s, xf_s = d.loop
			x = d.fn(rng, v)
			ln, xf = D.ns(loop_s), D.ns(xf_s)
			y = resample(D.crossfade_loop(x, ln, xf), D.SR, sr, circular=True)
			y = M.master_loop(y, sr, target, -1.5 if stereo_ogg else -1.0)
		else:
			x = resample(d.fn(rng, v), D.SR, sr)
			# Hits and bending transients may be limited a little harder (dense, punchy).
			gr = 5.0 if d.category in ("impact", "bending") else 3.0
			y = M.master_oneshot(x, sr, target, -1.0, max_gr_db=gr)
		path = os.path.join(folder, fname)
		if ext == "ogg":
			if sr != D.SR:
				raise ValueError("ogg sounds are rendered at 44.1 kHz")
			M.write_ogg(path, y, sr, OGG_QUALITY.get(d.kind, 0.3))
			try:
				import soundfile as sf
				dec, _ = sf.read(path, always_2d=True)
				y_an = dec.T
			except Exception:
				y_an = y
		else:
			if stereo_ogg:  # no OGG encoder: fall back to 22.05 kHz WAV to stay within budget
				from scipy import signal as S
				y = S.resample_poly(y, 1, 2, axis=-1)
				sr = sr // 2
			M.write_wav(path, y, sr, loop=is_loop, seed=seed_for(d.name, v))
			y_an = y
		a = M.analyze(y_an, sr, is_loop)
		a["category"] = d.category
		a["target_lufs"] = target
		a["bytes"] = os.path.getsize(path)
		results.append((os.path.relpath(path, ROOT), a))
	return results


def _job(name: str):
	load_modules()
	d = next(s for s in SOUNDS if s.name == name)
	t0 = time.time()
	try:
		res = render_sound(d)
	except Exception:
		import traceback
		return name, None, traceback.format_exc()
	return name, res, time.time() - t0


def write_report(entries: dict) -> None:
	with open(REPORT_JSON, "w") as f:
		json.dump(entries, f, indent=1, sort_keys=True)
	lines = ["# Audio analysis report", "",
		"Generated by `tools/audiogen/generate.py`. Loudness per ITU-R BS.1770 (K-weighted).",
		"`M max` = max momentary loudness (400 ms), `I` = integrated. Loop metrics: `jump` = boundary",
		"sample step / 99.5th-percentile step (< 1 means the wrap is smaller than normal sample-to-sample",
		"motion), `dRMS` = RMS change across the loop point (dB) next to the 95th percentile of the same",
		"measure between adjacent 50 ms windows inside the file (music that restarts on a downbeat hit",
		"legitimately steps up at the wrap). OGG rows are measured on the decoded file.", ""]
	total = sum(e["bytes"] for e in entries.values())
	lines.append("Files: %d, total size: %.2f MB" % (len(entries), total / 1e6))
	lines.append("")
	cats: dict = {}
	for path, e in entries.items():
		cats.setdefault(e["category"], []).append((path, e))
	for cat in sorted(cats):
		items = sorted(cats[cat])
		lines += ["## %s (target %.0f LUFS)" % (cat, CATEGORY_TARGETS.get(cat, 0)), "",
			"| file | Hz | dur s | ch | peak dBFS | true peak | RMS dB | M max | I | centroid Hz | loop jump | loop dRMS (p95) |",
			"|---|---|---|---|---|---|---|---|---|---|---|---|"]
		for path, e in items:
			lines.append("| %s | %d | %.2f | %d | %.1f | %.1f | %.1f | %.1f | %.1f | %.0f | %s | %s |" % (
				os.path.basename(path), e["sr"], e["duration"], e["channels"], e["peak_db"], e["true_peak_db"], e["rms_db"],
				e["lufs_m_max"], e["lufs_i"], e["centroid_hz"],
				"%.2f" % e["loop_jump_ratio"] if "loop_jump_ratio" in e else "",
				"%.2f (%.2f)" % (e["loop_rms_step_db"], e.get("loop_rms_p95_db", 0.0)) if "loop_rms_step_db" in e else ""))
		lines.append("")
	with open(REPORT_MD, "w") as f:
		f.write("\n".join(lines))


def main() -> int:
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--only", default="", help="comma separated glob patterns of sound names")
	ap.add_argument("--jobs", type=int, default=2)
	ap.add_argument("--skip-music", action="store_true")
	ap.add_argument("--list", action="store_true")
	ap.add_argument("--report-only", action="store_true", help="rewrite report.md from report.json")
	args = ap.parse_args()
	if args.report_only:
		with open(REPORT_JSON) as f:
			write_report(json.load(f))
		return 0
	load_modules()
	defs = list(SOUNDS)
	if args.only:
		pats = [p.strip() for p in args.only.split(",") if p.strip()]
		defs = [d for d in defs if any(fnmatch.fnmatch(d.name, p) for p in pats)]
	if args.skip_music:
		defs = [d for d in defs if d.kind != "music"]
	if args.list:
		for d in defs:
			print("%-24s %-9s %-6s variants=%d%s" % (d.name, d.category, d.kind, d.variants, " loop" if d.loop else ""))
		print("%d sounds" % len(defs))
		return 0
	if not M.ogg_backend():
		print("warning: no OGG encoder (pip install soundfile or install ffmpeg); music/ambience fall back to 22 kHz WAV")
	entries = {}
	if os.path.exists(REPORT_JSON):
		with open(REPORT_JSON) as f:
			entries = json.load(f)
	defs.sort(key=lambda d: -d.cost * d.variants)
	t0 = time.time()
	names = [d.name for d in defs]
	failed: list[str] = []

	def collect(name, res, dt):
		if res is None:
			failed.append(name)
			print("FAILED %s\n%s" % (name, dt), flush=True)
			return
		for path, a in res:
			entries[path] = a
		print("%-24s %5.1fs  %s" % (name, dt, ", ".join(os.path.basename(p) for p, _ in res)), flush=True)

	if args.jobs > 1 and len(names) > 1:
		with mp.get_context("fork").Pool(args.jobs) as pool:
			for name, res, dt in pool.imap_unordered(_job, names):
				collect(name, res, dt)
	else:
		for name in names:
			collect(*_job(name))
	entries = {p: e for p, e in entries.items() if os.path.exists(os.path.join(ROOT, p))}
	write_report(entries)
	total = sum(e["bytes"] for e in entries.values())
	print("done: %d sounds in %.1fs; assets/audio total %.2f MB" % (len(names), time.time() - t0, total / 1e6))
	if failed:
		print("FAILED: %s" % ", ".join(failed))
		return 1
	return 0


if __name__ == "__main__":
	sys.exit(main())
