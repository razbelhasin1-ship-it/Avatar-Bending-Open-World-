#!/usr/bin/env python3
"""Renders waveform + spectrogram sheets of generated sounds for visual QA.

  python3 tools/audiogen/spectrogram.py OUT.png assets/audio/sfx/fire_*.wav [...] [--cols 3] [--max-sec 4]

Needs matplotlib (pip install matplotlib) and soundfile for .ogg input.
"""
from __future__ import annotations

import argparse
import glob
import os
import sys

import numpy as np
from scipy import signal


def load(path: str):
	if path.endswith(".wav"):
		from scipy.io import wavfile
		sr, x = wavfile.read(path)
		x = x.astype(np.float64) / 32768.0
	else:
		import soundfile as sf
		x, sr = sf.read(path)
	if x.ndim == 2:
		x = x.mean(axis=1)
	return sr, x


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("out")
	ap.add_argument("files", nargs="+")
	ap.add_argument("--cols", type=int, default=3)
	ap.add_argument("--max-sec", type=float, default=0.0)
	ap.add_argument("--title", default="")
	ap.add_argument("--nperseg", type=int, default=0, help="FFT size (default 1024; use 4096+ for music)")
	ap.add_argument("--fmax", type=float, default=0.0)
	ap.add_argument("--start", type=float, default=0.0)
	args = ap.parse_args()
	import matplotlib
	matplotlib.use("Agg")
	import matplotlib.pyplot as plt
	files: list[str] = []
	for f in args.files:
		files += sorted(glob.glob(f)) if any(c in f for c in "*?[") else [f]
	if not files:
		print("no files")
		return 1
	cols = min(args.cols, len(files))
	rows = (len(files) + cols - 1) // cols
	w = 16.0 if cols == 1 else 5.2 * cols
	fig = plt.figure(figsize=(w, 6.0 * rows if cols == 1 else 3.6 * rows), facecolor="#14110f")
	gs = fig.add_gridspec(rows * 3, cols, hspace=0.55, wspace=0.18)
	for i, f in enumerate(files):
		sr, x = load(f)
		if args.start > 0:
			x = x[int(args.start * sr):]
		if args.max_sec > 0:
			x = x[: int(args.max_sec * sr)]
		r, c = divmod(i, cols)
		axw = fig.add_subplot(gs[r * 3, c])
		axs = fig.add_subplot(gs[r * 3 + 1:r * 3 + 3, c])
		t = np.arange(x.size) / sr
		axw.plot(t, x, color="#e7b552", lw=0.5)
		axw.set_xlim(0, t[-1] if t.size else 1)
		axw.set_ylim(-1, 1)
		axw.set_title(os.path.basename(f), color="#efe3c8", fontsize=9)
		axw.axis("off")
		nper = args.nperseg or (1024 if sr >= 32000 else 512)
		fq, tt, S = signal.spectrogram(x, sr, nperseg=nper, noverlap=nper * 3 // 4, scaling="spectrum")
		Sdb = 10 * np.log10(S + 1e-12)
		vmax = Sdb.max()
		axs.pcolormesh(tt + args.start, np.maximum(fq, 20), Sdb, shading="auto", cmap="magma", vmin=vmax - 80, vmax=vmax)
		axs.set_yscale("log")
		axs.set_ylim(30 if not args.fmax else 60, args.fmax or sr / 2)
		axs.tick_params(colors="#bfb39a", labelsize=7)
		axs.set_xlabel("s", color="#bfb39a", fontsize=7)
	if args.title:
		fig.suptitle(args.title, color="#efe3c8", fontsize=13)
	fig.savefig(args.out, dpi=90, facecolor=fig.get_facecolor(), bbox_inches="tight")
	print(args.out)
	return 0


if __name__ == "__main__":
	sys.exit(main())
