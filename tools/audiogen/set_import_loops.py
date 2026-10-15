#!/usr/bin/env python3
"""Marks looping audio in Godot's .import files, then you re-run the import.

  godot --headless --path . --import          # creates the .import files
  python3 tools/audiogen/set_import_loops.py   # flips loop flags (prints changes)
  godot --headless --path . --import          # re-imports the changed files

* music/*.ogg and sfx/amb_*.ogg      -> loop=true
* sfx/*_loop[_N].wav                 -> edit/loop_mode=2 (forward), whole file
  (the WAVs also carry a 'smpl' loop chunk, so "Detect from WAV" works too)

Audio._set_loop() enables looping at runtime as well, so a missing flag never
breaks playback; the import flags make the assets correct in the editor too.
"""
from __future__ import annotations

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))


def patch(path: str, rules: list[tuple[str, str]]) -> bool:
	with open(path) as f:
		text = f.read()
	new = text
	for key, value in rules:
		pat = re.compile(r"^%s=.*$" % re.escape(key), re.M)
		if pat.search(new):
			new = pat.sub("%s=%s" % (key, value), new)
		else:
			new = new.replace("[params]\n", "[params]\n\n%s=%s\n" % (key, value), 1)
	if new != text:
		with open(path, "w") as f:
			f.write(new)
		return True
	return False


def main() -> int:
	changed = 0
	music = os.path.join(ROOT, "assets", "audio", "music")
	sfx = os.path.join(ROOT, "assets", "audio", "sfx")
	for folder, pred, rules in (
		(music, lambda n: n.endswith(".ogg.import"), [("loop", "true")]),
		(sfx, lambda n: n.startswith("amb_") and n.endswith(".ogg.import"), [("loop", "true")]),
		(sfx, lambda n: re.search(r"_loop(_\d)?\.wav\.import$", n) is not None,
			[("edit/loop_mode", "2"), ("edit/loop_begin", "0"), ("edit/loop_end", "-1")]),
	):
		if not os.path.isdir(folder):
			continue
		for n in sorted(os.listdir(folder)):
			if pred(n) and patch(os.path.join(folder, n), rules):
				print("loop flags set:", n)
				changed += 1
	print("%d import files changed" % changed)
	return 0


if __name__ == "__main__":
	sys.exit(main())
