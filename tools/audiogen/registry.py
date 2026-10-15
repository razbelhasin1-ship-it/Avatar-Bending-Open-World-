"""Sound registry: every generated asset is declared with a decorator.

	@sfx("ui_click", "ui", variants=3)
	def ui_click(rng, v): ...            # returns mono float array

	@sfx("fire_loop", "loop", loop=(6.0, 0.8))
	def fire_loop(rng, v): ...           # returns >= loop+xfade seconds; made seamless

	@ambience("amb_rain", seconds=40.0)  # stereo (2, n) loop, OGG
	@music("music_menu")                 # handled by music.py (returns MusicRender)
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from dsp import SR

# Mastering targets (LUFS). One-shots use max short-term loudness (300 ms),
# loops/ambience/music use integrated loudness.
CATEGORY_TARGETS = {
	"ui": -21.0,
	"step": -24.0,
	"body": -19.0,
	"impact": -17.0,
	"bending": -17.0,
	"creature": -17.0,
	"stinger": -17.0,
	"loop": -22.0,
	"amb": -26.0,
	"music": -19.0,
}


# Output sample rates. Everything is synthesized at 44.1 kHz: bright SFX
# (UI bells, snow/ice/fire/water/air detail) are written at 44.1 kHz, sounds
# whose content sits below ~10 kHz (earth, creatures, body hits) are resampled
# to 22.05 kHz to respect the size budget.
SFX_RATE = 44100
LOW_RATE = 22050
LOW_RATE_PREFIXES = ("earth_", "rock_", "bison_", "dog_", "dragon_", "wing_", "badgermole_", "creature_", "punch_",
	"kick_", "hit_", "body_", "block_", "gong", "step_heavy", "land_heavy")


@dataclass
class SoundDef:
	name: str
	fn: Callable
	category: str
	kind: str = "sfx"            # sfx | amb | music
	variants: int = 1
	sr: int = SR                 # output sample rate
	loop: tuple | None = None    # (loop_seconds, crossfade_seconds)
	gain_db: float = 0.0
	stereo: bool = False
	cost: float = 1.0            # scheduling hint (bigger first)


SOUNDS: list[SoundDef] = []


def sfx(name: str, category: str, variants: int = 1, sr: int = SFX_RATE, loop: tuple | None = None, gain_db: float = 0.0,
		cost: float = 1.0):
	if sr == SFX_RATE and name.startswith(LOW_RATE_PREFIXES):
		sr = LOW_RATE

	def deco(fn):
		SOUNDS.append(SoundDef(name, fn, category, "sfx", variants, sr, loop, gain_db, False, cost))
		return fn
	return deco


def ambience(name: str, seconds: float = 40.0, xfade: float = 3.0, gain_db: float = 0.0, sr: int = SR):
	def deco(fn):
		SOUNDS.append(SoundDef(name, lambda rng, v: fn(rng), "amb", "amb", 1, sr, (seconds, xfade), gain_db, True, 6.0))
		return fn
	return deco


def music(name: str, gain_db: float = 0.0):
	def deco(fn):
		SOUNDS.append(SoundDef(name, fn, "music", "music", 1, SR, None, gain_db, True, 30.0))
		return fn
	return deco
