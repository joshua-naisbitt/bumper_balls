#!/usr/bin/env python3
"""Synthesise every sound effect in audio/ using only the standard library.

Run from the project root:  python3 tools/make_sfx.py
"""

import math
import os
import random
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio")


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    data = b"".join(
        struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples
    )
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def env(i, n, attack=0.005, curve=3.0):
    """Linear attack into a power-curve decay."""
    a = int(SR * attack) or 1
    if i < a:
        return i / a
    return (1.0 - (i - a) / max(1, n - a)) ** curve


def tone(f, t):
    return math.sin(2 * math.pi * f * t)


def arp(freqs, step, dur):
    n = int(SR * dur)
    out = [0.0] * n
    for k, f in enumerate(freqs):
        start = int(SR * step * k)
        ln = n - start
        for i in range(ln):
            out[start + i] += 0.32 * (tone(f, i / SR) + 0.35 * tone(f * 2, i / SR)) * env(
                i, ln, 0.006, 2.4
            )
    return out


def main():
    random.seed(7)

    # Ball-on-ball thump: a low sine drop with a click of noise on the front.
    n = int(SR * 0.16)
    write("bump", [
        (0.75 * tone(190 - 90 * i / n, i / SR)
         + 0.3 * random.uniform(-1, 1) * (1 - i / n) ** 8) * env(i, n, 0.002, 2.5)
        for i in range(n)
    ])

    # Dash: noise swoosh that brightens as a tone rises through it.
    n = int(SR * 0.22)
    prev = 0.0
    dash = []
    for i in range(n):
        p = i / n
        prev += (random.uniform(-1, 1) - prev) * (0.12 + 0.5 * p)
        dash.append((0.45 * prev + 0.4 * tone(280 + 620 * p, i / SR)) * env(i, n, 0.01, 2.0))
    write("dash", dash)

    # Falling off: a descending wobble into nothing.
    n = int(SR * 0.7)
    write("fall", [
        0.55 * tone((520 - 400 * (i / n)) * (1 + 0.05 * math.sin(2 * math.pi * 7 * i / SR)),
                    i / SR) * env(i, n, 0.01, 1.6)
        for i in range(n)
    ])

    # Countdown blip, then the GO blip an octave up with a fifth on top.
    n = int(SR * 0.13)
    write("beep", [0.5 * tone(560, i / SR) * env(i, n, 0.004, 3.0) for i in range(n)])
    n = int(SR * 0.3)
    write("go", [
        0.5 * (tone(880, i / SR) + 0.5 * tone(1320, i / SR)) * env(i, n, 0.004, 2.2)
        for i in range(n)
    ])

    write("round_win", arp([523, 659, 784], 0.09, 0.5))
    write("match_win", arp([523, 659, 784, 1047, 1319], 0.11, 1.1))

    # Tick for the shrinking arena.
    n = int(SR * 0.1)
    write("warn", [0.38 * tone(320, i / SR) * env(i, n, 0.003, 3.5) for i in range(n)])

    print("wrote 8 sounds to", OUT)


if __name__ == "__main__":
    main()
