"""Takes the hiss out of an ambience loop: a gentle low-pass done on the whole loop in the frequency domain.

    python tools/audio/soften_loop.py <loop.ogg> <pass_hz> <stop_hz> [--gain-db G]

Everything under `pass_hz` stays, everything over `stop_hz` goes, with a cosine roll-off between them. Filtering
the whole loop at once is circular, so the loop stays seamless (no click where it wraps). Overwrites the file and
keeps a copy of the original in art_src/audio/.
"""
import argparse
import os
import shutil

import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("pass_hz", type=float)
    ap.add_argument("stop_hz", type=float)
    ap.add_argument("--gain-db", type=float, default=0.0)
    a = ap.parse_args()
    keep = os.path.join(ROOT, "art_src", "audio", os.path.basename(a.path))
    os.makedirs(os.path.dirname(keep), exist_ok=True)
    if not os.path.exists(keep):
        shutil.copyfile(a.path, keep)
    x, sr = sf.read(keep, always_2d=True)
    f = np.fft.rfftfreq(x.shape[0], 1.0 / sr)
    t = np.clip((f - a.pass_hz) / (a.stop_hz - a.pass_hz), 0.0, 1.0)
    curve = 0.5 + 0.5 * np.cos(np.pi * t)
    y = np.stack([np.fft.irfft(np.fft.rfft(x[:, c]) * curve, n=x.shape[0]) for c in range(x.shape[1])], axis=1)
    y *= 10.0 ** (a.gain_db / 20.0)
    peak = np.abs(y).max()
    if peak > 0.98:
        y *= 0.98 / peak
    # In small blocks: libsndfile's Vorbis encoder overflows the stack on Windows when handed a long block at once.
    with sf.SoundFile(a.path, "w", sr, y.shape[1], format="OGG", subtype="VORBIS") as out:
        for i in range(0, y.shape[0], 4096):
            out.write(y[i:i + 4096])
    print(os.path.basename(a.path), "low-passed", a.pass_hz, "-", a.stop_hz, "Hz")


if __name__ == "__main__":
    main()
