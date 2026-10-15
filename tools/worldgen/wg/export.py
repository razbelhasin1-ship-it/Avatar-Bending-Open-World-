"""Writers for the runtime data in assets/world/.

Heightmap encoding (must match src/world/data/world_constants.gd and the shader include):
    raw    = round((height - HEIGHT_MIN) / HEIGHT_SCALE)          (uint16, little endian, clamped)
    height = raw * HEIGHT_SCALE + HEIGHT_MIN                      (HEIGHT_SCALE = 1/32 m, HEIGHT_MIN = -256 m)
Rows are z (north -> south), columns x (west -> east), texel centres at
    x = -4096 + (i + 0.5) * 2,  z = -4096 + (j + 0.5) * 2.
The stream is a zlib (RFC 1950) stream: PackedByteArray.decompress(size, FileAccess.COMPRESSION_DEFLATE).
"""
from __future__ import annotations

import json
import os
import zlib

import numpy as np
from PIL import Image

HEIGHT_MIN = -256.0
HEIGHT_SCALE = 1.0 / 32.0
HEIGHT_MAX = HEIGHT_MIN + 65535 * HEIGHT_SCALE


def quantize_height(h: np.ndarray) -> np.ndarray:
    raw = np.round((h.astype(np.float64) - HEIGHT_MIN) / HEIGHT_SCALE)
    return np.clip(raw, 0, 65535).astype("<u2")


def dequantize(raw: np.ndarray) -> np.ndarray:
    return raw.astype(np.float64) * HEIGHT_SCALE + HEIGHT_MIN


def write_heightmap(path: str, h: np.ndarray) -> dict:
    raw = quantize_height(h)
    data = raw.tobytes(order="C")
    comp = zlib.compress(data, 9)
    with open(path, "wb") as fh:
        fh.write(comp)
    return {"raw_size": len(data), "compressed_size": len(comp), "raw": raw}


def write_png(path: str, arr: np.ndarray, mode: str) -> int:
    if arr.dtype != np.uint8:
        arr = np.clip(np.round(arr * 255.0), 0, 255).astype(np.uint8)
    Image.fromarray(arr, mode=mode).save(path, optimize=True, compress_level=9)
    return os.path.getsize(path)


def write_keep_import(path: str) -> None:
    """Marks a data file as 'Keep File (exported as is)' so Godot never re-encodes it."""
    with open(path + ".import", "w") as fh:
        fh.write('[remap]\n\nimporter="keep"\n')


def write_json(path: str, data: dict) -> int:
    with open(path, "w") as fh:
        json.dump(data, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    return os.path.getsize(path)
