#!/usr/bin/env python3
"""Extract a brightness trace (.f32) from a Morse video recording.

This is the fixture-generation half of the video decoding
pipeline: it mirrors what VideoDecoder does on-device (find the
blinking region, read its mean brightness per frame) so the
committed .f32 fixtures represent the signal the app actually
decodes.

Method (validated against the original hand-tuned fixtures on the
legacy 30 fps recordings — decoded CER within a few points):

1. Decode the video to grayscale frames downscaled to 320x180
   (ffmpeg default bicubic scaling matched the original
   fixtures).
2. High-pass filter each pixel's brightness over time by
   subtracting a ~1 s box moving average. This suppresses static
   structure and slow auto-exposure drift, leaving the blinking
   dot as the dominant activity.
3. Per-pixel temporal variance of the high-passed signal →
   activity map. Block-mean (9x9) of the map → peak block.
4. Refine the block center with a variance-weighted centroid in
   a +-20 px neighbourhood.
5. Trace = mean gray value of the 9x9 region around that center,
   per frame, normalized to 0..1, written as little-endian
   float32.

Optionally verifies the detected region lies inside the central
target area (default 40 %) — new recordings are aimed at the
target, and a region outside it usually means the recording is
not usable as a target-decoding fixture (--require-target fails
loudly in that case).

Usage:
    python3 tools/extract_brightness.py RECORDING.mp4 \
        --wpm 8 --text "HELLO, WORLD!" \
        [--out test/assets/recordings/video] \
        [--name 8wpm_60fps.mp4] [--require-target] [--no-manifest]

Updates the manifest entry (creating it if needed) with the
brightness filename, fps, frame count, duration, expected WPM and
text, and the detected region.

Requires: ffmpeg + ffprobe on PATH, numpy.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

ANALYSIS_W = 320
ANALYSIS_H = 180
REGION = 9           # brightness-reading region side (px)
REFINE_R = 20        # centroid refinement half-window (px)
HIGHPASS_FRAMES = 31  # ~1 s at 30 fps; scaled by fps below
TARGET_FRACTION = 0.4  # central target area, like VideoDecoder


def probe(path: Path) -> dict:
    """Return fps, nb_frames, duration, width, height via ffprobe."""
    out = subprocess.check_output([
        'ffprobe', '-v', 'error', '-select_streams', 'v:0',
        '-show_entries',
        'stream=width,height,r_frame_rate,nb_frames:format=duration',
        '-of', 'json', str(path),
    ])
    meta = json.loads(out)
    stream = meta['streams'][0]
    num, den = stream['r_frame_rate'].split('/')
    return {
        'fps': float(num) / float(den),
        'nb_frames': int(stream['nb_frames']),
        'duration_s': float(meta['format']['duration']),
        'width': int(stream['width']),
        'height': int(stream['height']),
    }


def decode_frames(path: Path, n: int) -> np.ndarray:
    """Decode the video to (n, H, W) float32 grayscale frames."""
    cmd = [
        'ffmpeg', '-v', 'error', '-i', str(path),
        '-vf', f'scale={ANALYSIS_W}:{ANALYSIS_H},format=gray',
        '-f', 'rawvideo', '-',
    ]
    raw = subprocess.check_output(cmd)
    frame_bytes = ANALYSIS_W * ANALYSIS_H
    if len(raw) < n * frame_bytes:
        # Some containers misreport nb_frames; use what we got.
        n = len(raw) // frame_bytes
    frames = np.frombuffer(
        raw, dtype=np.uint8, count=n * frame_bytes,
    )
    return frames.reshape(n, ANALYSIS_H, ANALYSIS_W).astype(np.float32)


def box_moving_avg(x: np.ndarray, k: int) -> np.ndarray:
    """Box moving average along axis 0 with edge padding."""
    pad = k // 2
    xp = np.pad(x, ((pad, pad), (0, 0), (0, 0)), mode='edge')
    c = np.cumsum(xp, axis=0)
    zero = np.zeros((1,) + c.shape[1:], dtype=c.dtype)
    c = np.concatenate([zero, c], axis=0)
    return (c[k:] - c[:-k]) / k


def target_bounds(fraction: float) -> tuple[int, int, int, int]:
    """Central target area bounds at analysis resolution."""
    x0 = int(ANALYSIS_W * (1 - fraction) / 2)
    y0 = int(ANALYSIS_H * (1 - fraction) / 2)
    return x0, ANALYSIS_W - x0, y0, ANALYSIS_H - y0


def detect_region(
    frames: np.ndarray,
    k: int,
    restrict_target: bool = False,
) -> tuple[int, int, int, int]:
    """Find the blinking region. Returns (x0, x1, y0, y1)."""
    n, h, w = frames.shape
    hp = frames - box_moving_avg(frames, k)
    var = hp.var(axis=0)

    if restrict_target:
        tx0, tx1, ty0, ty1 = target_bounds(TARGET_FRACTION)
        mask = np.zeros_like(var)
        mask[ty0:ty1, tx0:tx1] = 1
        var = var * mask

    win = sliding_window_view(var, (REGION, REGION)).mean(axis=(2, 3))
    by, bx = np.unravel_index(np.argmax(win), win.shape)

    # Centroid refinement around the block peak.
    y0 = max(0, by - REFINE_R)
    y1 = min(h, by + REFINE_R + 1)
    x0 = max(0, bx - REFINE_R)
    x1 = min(w, bx + REFINE_R + 1)
    v = var[y0:y1, x0:x1]
    wgt = np.clip(v - np.percentile(v, 50), 0, None)
    tot = wgt.sum()
    if tot > 0:
        cx = int(round((wgt.sum(axis=0) @ np.arange(x0, x1)) / tot))
        cy = int(round((wgt.sum(axis=1) @ np.arange(y0, y1)) / tot))
    else:
        cx, cy = bx + REGION // 2, by + REGION // 2

    r = REGION // 2
    cx = min(max(cx, r), w - r - 1)
    cy = min(max(cy, r), h - r - 1)
    return cx - r, cx + r, cy - r, cy + r


def main() -> int:
    ap = argparse.ArgumentParser(
        description='Extract a brightness .f32 trace from a video.',
    )
    ap.add_argument('video', type=Path, help='path to the .mp4 recording')
    ap.add_argument('--wpm', type=int, required=True,
                    help='expected sending speed')
    ap.add_argument('--text', required=True,
                    help='expected decoded text, e.g. "HELLO, WORLD!"')
    ap.add_argument('--max-cer', type=float, default=None,
                    help='optional per-fixture CER budget override')
    ap.add_argument('--name', default=None,
                    help='manifest key (defaults to the video filename)')
    ap.add_argument('--out', type=Path,
                    default=Path('test/assets/recordings/video'),
                    help='directory for the .f32 output')
    ap.add_argument('--manifest', type=Path, default=None,
                    help='manifest.json path (default: <out>/manifest.json)')
    ap.add_argument('--no-manifest', action='store_true',
                    help='do not update the manifest')
    ap.add_argument('--require-target', action='store_true',
                    help='fail if the detected region lies outside the '
                         'central target area')
    args = ap.parse_args()

    if not args.video.exists():
        print(f'error: {args.video} not found', file=sys.stderr)
        return 1
    args.out.mkdir(parents=True, exist_ok=True)
    manifest_path = args.manifest or args.out / 'manifest.json'

    meta = probe(args.video)
    fps = meta['fps']
    frames = decode_frames(args.video, meta['nb_frames'])
    n = frames.shape[0]
    k = max(3, int(round(HIGHPASS_FRAMES * fps / 30)))

    x0, x1, y0, y1 = detect_region(frames, k)
    trace = frames[:, y0:y1 + 1, x0:x1 + 1].mean(axis=(1, 2)) / 255.0

    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    tx0, tx1, ty0, ty1 = target_bounds(TARGET_FRACTION)
    in_target = tx0 <= cx <= tx1 and ty0 <= cy <= ty1
    if args.require_target and not in_target:
        print(
            f'error: detected region center ({cx},{cy}) is outside the '
            f'central target area ({tx0}..{tx1}, {ty0}..{ty1}) — the '
            f'recording is not aimed at the target and is not a valid '
            f'fixture for target-area decoding.',
            file=sys.stderr,
        )
        return 1

    key = args.name or args.video.name
    stem = Path(key).stem
    bright_name = f'{stem}_brightness.f32'
    bright_path = args.out / bright_name
    trace.astype('<f4').tofile(bright_path)

    print(f'{key}:')
    print(f'  {meta["width"]}x{meta["height"]} @ {fps:g} fps, '
          f'{n} frames, {meta["duration_s"]:.2f} s')
    print(f'  region x={x0}-{x1} y={y0}-{y1} '
          f'({"inside" if in_target else "OUTSIDE"} the central target area)')
    print(f'  trace {bright_path} '
          f'({bright_path.stat().st_size} bytes, '
          f'min={trace.min():.3f} max={trace.max():.3f})')

    if not args.no_manifest:
        manifest = {}
        if manifest_path.exists():
            manifest = json.loads(manifest_path.read_text())
        entry = {
            'brightness_file': bright_name,
            'fps': fps,
            'n_frames': n,
            'duration_s': round(meta['duration_s'], 2),
            'expected_wpm': args.wpm,
            'expected_text': args.text,
            f'dot_region_{ANALYSIS_W}x{ANALYSIS_H}': {
                'x': [x0, x1], 'y': [y0, y1],
            },
        }
        if args.max_cer is not None:
            entry['max_cer'] = args.max_cer
        manifest[key] = entry
        manifest_path.write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
        print(f'  manifest updated: {manifest_path}')

    return 0


if __name__ == '__main__':
    raise SystemExit(main())
