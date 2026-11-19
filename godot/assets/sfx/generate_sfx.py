#!/usr/bin/env python3
"""Procedural sound-effect generator for the Kiepie Quad combat game.

Pure stdlib (wave, math, random, struct, os) — no numpy, no ffmpeg, no samples.
Every sound is synthesised sample-by-sample at 22.05 kHz / mono / 16-bit PCM
so the resulting WAVs are tiny enough for the Web export.

Run from anywhere::

    python3 godot/assets/sfx/generate_sfx.py

The WAVs are written next to this script. Re-running is deterministic (fixed
seed), so regenerating the pack never produces a surprise diff.

Design notes
------------
* One-shots use real envelopes (exponential decays, short attacks), noise,
  pitch sweeps and inharmonic partials — not plain sine beeps.
* ``engine_loop.wav`` is built from components that are all periodic over the
  2.0 s buffer (harmonic frequencies are integer multiples of 21 Hz, the
  noise is circularly low-passed with wrap-around windows). The final sample
  is explicitly set equal to the first, so looping has no click.
"""

import math
import os
import random
import struct
import wave

SR = 22050  # Hz — deliberately low: small files, plenty for game SFX
OUT_DIR = os.path.dirname(os.path.abspath(__file__))
random.seed(20261117)  # reproducible pack

TAU = 2.0 * math.pi


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def one_pole_lp(prev, value, cutoff_hz):
    """One-pole low-pass step; cutoff may vary per sample."""
    a = math.exp(-TAU * max(20.0, cutoff_hz) / SR)
    return prev + a * (value - prev)


def clamp(v):
    return -1.0 if v < -1.0 else (1.0 if v > 1.0 else v)


def write_wav(filename, samples, target_peak=0.96):
    """Normalise to target_peak, quantise to int16 and write a mono WAV."""
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = target_peak / peak
    pcm = bytearray()
    for s in samples:
        pcm.extend(struct.pack("<h", int(clamp(s * scale) * 32767.0)))
    path = os.path.join(OUT_DIR, filename)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(pcm))
    return path


def circular_lowpass(src, width):
    """Moving average with wrap-around indices => output stays periodic."""
    n = len(src)
    doubled = src + src
    prefix = [0.0] * (2 * n + 1)
    for i, v in enumerate(doubled):
        prefix[i + 1] = prefix[i] + v
    out = [0.0] * n
    for i in range(n):
        hi = i + n                       # window ends at src[i] in the 2nd copy
        lo = hi - width + 1
        out[i] = (prefix[hi + 1] - prefix[lo]) / width
    return out


# ---------------------------------------------------------------------------
# 1. cannon fire — sharp bang + mechanical click
# ---------------------------------------------------------------------------
def cannon_fire():
    n = int(SR * 0.18)
    out = [0.0] * n
    phase = 0.0
    lp = 0.0
    for i in range(n):
        t = i / SR
        # falling body tone: 190 Hz -> 55 Hz, fast decay
        freq = 55.0 + 135.0 * math.exp(-t / 0.045)
        phase += TAU * freq / SR
        body = math.sin(phase) * math.exp(-t / 0.045)
        # bright noise crack whose brightness collapses quickly
        brightness = 4500.0 * math.exp(-t / 0.028)
        lp = one_pole_lp(lp, random.uniform(-1.0, 1.0), brightness)
        crack = 3.0 * lp * math.exp(-t / 0.022)
        out[i] = 0.85 * body + 0.60 * crack
    # mechanical breech click ~28 ms in
    start = int(0.028 * SR)
    for j in range(int(0.005 * SR)):
        idx = start + j
        if idx >= n:
            break
        tj = j / SR
        env = math.exp(-tj / 0.0009)
        out[idx] += 0.30 * env * (
            0.7 * random.uniform(-1.0, 1.0) + 0.5 * math.sin(TAU * 2600.0 * tj)
        )
    return out


# ---------------------------------------------------------------------------
# 2. impact — metallic hit + spark crackle
# ---------------------------------------------------------------------------
def impact():
    n = int(SR * 0.16)
    out = [0.0] * n
    # deliberately inharmonic metal partials, faster decay up the spectrum
    partials = [
        (587.0, 0.100, 1.00),
        (879.0, 0.070, 0.72),
        (1320.0, 0.050, 0.55),
        (1860.0, 0.034, 0.42),
        (2530.0, 0.020, 0.30),
    ]
    for i in range(n):
        t = i / SR
        bend = 1.0 - 0.025 * min(1.0, t / 0.08)  # tiny downward chirp
        v = 0.0
        for freq, tau, amp in partials:
            v += amp * math.sin(TAU * freq * bend * t) * math.exp(-t / tau)
        out[i] = 0.92 * v
    # sparse sparks: random very short high-noise bursts in the first 110 ms
    for _ in range(28):
        start = random.randrange(0, int(0.11 * SR))
        amp = random.uniform(0.15, 0.45)
        tau = random.uniform(0.0015, 0.0045)
        for j in range(int(0.018 * SR)):
            idx = start + j
            if idx >= n:
                break
            out[idx] += 0.55 * amp * random.uniform(-1.0, 1.0) * math.exp(-(j / SR) / tau)
    return out


# ---------------------------------------------------------------------------
# 3. explosion — low boom + rolling noise tail
# ---------------------------------------------------------------------------
def explosion():
    n = int(SR * 0.9)
    out = [0.0] * n
    phase = 0.0
    lp = 0.0
    for i in range(n):
        t = i / SR
        freq = 32.0 + 70.0 * math.exp(-t / 0.10)
        phase += TAU * freq / SR
        boom = math.sin(phase) * math.exp(-t / 0.16)
        sub = math.sin(TAU * 44.0 * t) * math.exp(-t / 0.30) * 0.50
        # noise tail darkens from ~2.5 kHz to ~300 Hz as it fades
        lp = one_pole_lp(lp, random.uniform(-1.0, 1.0),
                         300.0 + 2200.0 * math.exp(-t / 0.22))
        tail = 2.2 * lp * math.exp(-t / 0.32)
        tail *= 0.75 + 0.25 * math.sin(TAU * 7.0 * t)  # slow rumble
        crack = random.uniform(-1.0, 1.0) * math.exp(-t / 0.012)
        out[i] = 0.80 * boom + 0.50 * sub + 0.55 * tail + 0.35 * crack
    return out


# ---------------------------------------------------------------------------
# 4. pickup — rising four-note bell arpeggio
# ---------------------------------------------------------------------------
def pop():
    n = int(SR * 0.22)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        freq = 720.0 - 380.0 * math.exp(-t / 0.060)   # squeaky pitch drop
        vib = 1.0 + 0.08 * math.sin(TAU * 27.0 * t)   # cartoon wobble
        env = math.exp(-t / 0.055)
        tone = math.sin(TAU * freq * vib * t) * env
        tone += 0.4 * math.sin(TAU * freq * 1.5 * vib * t) * math.exp(-t / 0.04)
        out[i] = 0.80 * tone
    return out


def pickup():
    n = int(SR * 0.4)
    out = [0.0] * n
    notes = [
        (523.25, 0.000, 0.20),   # C5
        (659.25, 0.055, 0.20),   # E5
        (783.99, 0.110, 0.23),   # G5
        (1046.50, 0.165, 0.28),  # C6
    ]
    for freq, start, tau in notes:
        s = int(start * SR)
        for i in range(s, n):
            t = (i - s) / SR
            if t > 0.34:
                break
            env = math.exp(-t / tau) * min(1.0, t / 0.004)
            w = TAU * freq * t
            # sine + octave + slightly detuned third partial = bell timbre
            v = math.sin(w) + 0.35 * math.sin(2 * w) + 0.14 * math.sin(3.01 * w)
            out[i] += env * v * 0.62
    # gentle overall tail fade
    for i in range(n):
        remain = 0.4 - i / SR
        out[i] *= min(1.0, remain / 0.05)
    return out


# ---------------------------------------------------------------------------
# 5. turbo — band-passed whoosh, pitch up then down
# ---------------------------------------------------------------------------
def turbo():
    n = int(SR * 0.6)
    out = [0.0] * n
    x1 = x2 = y1 = y2 = 0.0
    phase = 0.0
    for i in range(n):
        t = i / SR
        u = t / 0.6
        sweep = math.sin(math.pi * u) ** 1.3          # 0 -> 1 -> 0
        center = 300.0 + 2200.0 * sweep
        q = 1.7
        w0 = TAU * center / SR
        alpha = math.sin(w0) / (2.0 * q)
        a0 = 1.0 + alpha
        b0 = alpha / a0
        b2 = -alpha / a0
        a1 = (-2.0 * math.cos(w0)) / a0
        a2 = (1.0 - alpha) / a0
        x = random.uniform(-1.0, 1.0)
        y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, x
        y2, y1 = y1, y
        phase += TAU * (200.0 + 620.0 * sweep) / SR
        env = math.sin(math.pi * u) ** 0.6
        out[i] = env * (1.5 * y + 0.28 * math.sin(phase))
    return out


# ---------------------------------------------------------------------------
# 6. kill — two-note power sting
# ---------------------------------------------------------------------------
def kill():
    n = int(SR * 0.55)
    out = [0.0] * n
    # punchy low thump under the first note
    for i in range(int(0.10 * SR)):
        t = i / SR
        out[i] += 0.55 * math.sin(TAU * (70.0 + 60.0 * math.exp(-t / 0.03)) * t) \
            * math.exp(-t / 0.035)

    notes = [
        (587.33, 0.000, 0.18, 0.90),  # D5, short
        (880.00, 0.140, 0.36, 1.00),  # A5, longer resolution
    ]
    for freq, start, tau, amp in notes:
        s = int(start * SR)
        for i in range(s, n):
            t = (i - s) / SR
            if t > 0.42:
                break
            env = min(1.0, t / 0.003) * math.exp(-t / tau)
            w = TAU * freq * t
            # modest saw-like stack: strong fundamental + harmonics
            v = math.sin(w) + 0.45 * math.sin(2 * w) + 0.28 * math.sin(3 * w) \
                + 0.16 * math.sin(4 * w) + 0.09 * math.sin(5 * w)
            out[i] += amp * env * v * 0.46
    for i in range(n):
        remain = 0.55 - i / SR
        out[i] *= min(1.0, remain / 0.03)
    return out


# ---------------------------------------------------------------------------
# 7. UI click — soft, tiny
# ---------------------------------------------------------------------------
def ui_click():
    n = int(SR * 0.07)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        nz = random.uniform(-1.0, 1.0) * math.exp(-t / 0.0035)
        ping = math.sin(TAU * 1400.0 * t) * math.exp(-t / 0.018)
        out[i] = 0.50 * nz + 0.42 * ping
        remain = 0.07 - t
        out[i] *= min(1.0, remain / 0.010)
    return out


# ---------------------------------------------------------------------------
# 8. respawn — rising beam + shimmer
# ---------------------------------------------------------------------------
def respawn():
    n = int(SR * 0.5)
    out = [0.0] * n
    phase = 0.0
    lp = 0.0
    for i in range(n):
        t = i / SR
        u = t / 0.5
        freq = 320.0 + 1180.0 * (u ** 0.8)
        phase += TAU * freq / SR
        beam = math.sin(phase * (1.0 + 0.006 * math.sin(TAU * 11.0 * t)))
        shimmer = 0.50 * math.sin(phase * 2.01) + 0.30 * math.sin(phase * 3.03 + 0.7)
        trem = 0.75 + 0.25 * math.sin(TAU * 17.0 * t)
        lp = one_pole_lp(lp, random.uniform(-1.0, 1.0), 600.0 + 3000.0 * u)
        env = min(1.0, t / 0.06) * min(1.0, (0.5 - t) / 0.14)
        out[i] = env * (0.55 * beam + 0.25 * trem * shimmer + 0.30 * lp)
    return out


# ---------------------------------------------------------------------------
# 9. dink — crisp metallic ping for light/soft impacts
# ---------------------------------------------------------------------------
def dink():
    n = int(SR * 0.07)
    out = [0.0] * n
    lp = 0.0
    for i in range(n):
        t = i / SR
        ping = math.sin(TAU * (2100.0 + 1400.0 * math.exp(-t / 0.04)) * t) * math.exp(-t / 0.10)
        lp = one_pole_lp(lp, random.uniform(-1.0, 1.0), 3400.0 * math.exp(-t / 0.007))
        out[i] = 0.55 * ping + 0.30 * lp
    return out


# ---------------------------------------------------------------------------
# 9b. scrape — low-velocity slide rumble (wheels scraping ground)
# ---------------------------------------------------------------------------
def scrape():
    n = int(SR * 0.35)
    out = [0.0] * n
    phase = 0.0
    lp = 0.0
    for i in range(n):
        t = i / SR
        u = min(1.0, t / 0.35)
        sweep = 700.0 - 640.0 * u
        lp = one_pole_lp(lp, random.uniform(-1.0, 1.0), sweep)
        out[i] = 0.40 * lp
        phase += TAU * (0.55 * sweep + 45.0) / SR
        out[i] += 0.20 * math.sin(phase) * math.exp(-t / 0.9)
    return out


# ---------------------------------------------------------------------------
# 10. engine loop — 2.0 s seamless quad rumble
# ---------------------------------------------------------------------------
def engine_loop():
    n = int(SR * 2.0)
    f0 = 21.0  # 42 whole cycles in 2 s -> every harmonic is periodic
    harmonics = [
        (1, 0.35), (2, 0.75), (3, 0.45), (4, 0.55), (5, 0.25),
        (6, 0.32), (7, 0.16), (8, 0.20), (10, 0.12), (12, 0.09),
        (16, 0.05),
    ]
    # white noise -> three wrap-around moving averages = circular rumble
    noise = [random.uniform(-1.0, 1.0) for _ in range(n)]
    noise = circular_lowpass(noise, 5)
    noise = circular_lowpass(noise, 7)
    noise = circular_lowpass(noise, 9)
    noise = [v * 6.0 for v in noise]

    out = [0.0] * n
    for i in range(n):
        t = i / SR
        am = 0.72 + 0.28 * (0.5 + 0.5 * math.cos(TAU * f0 * t))  # putt-putt
        v = 0.0
        for h, amp in harmonics:
            v += amp * math.sin(TAU * f0 * h * t + 0.3 * h)
        out[i] = am * (v + 0.22 * noise[i])

    mean = sum(out) / n
    out = [s - mean for s in out]
    out[-1] = out[0]  # exact seam match — no click when looped
    return out


SOUNDS = [
    ("cannon_fire.wav", cannon_fire, 0.96),
    ("impact.wav", impact, 0.96),
    ("explosion.wav", explosion, 0.96),
    ("pop.wav", pop, 0.92),
    ("pickup.wav", pickup, 0.94),
    ("turbo.wav", turbo, 0.92),
    ("kill.wav", kill, 0.95),
    ("ui_click.wav", ui_click, 0.85),
    ("respawn.wav", respawn, 0.92),
    ("engine_loop.wav", engine_loop, 0.70),  # quieter: it loops forever
    ("dink.wav", dink, 0.85),
    ("scrape.wav", scrape, 0.85),
]


def main():
    print("Generating Kiepie Quad SFX into", OUT_DIR)
    for filename, fn, peak in SOUNDS:
        path = write_wav(filename, fn(), peak)
        print("  %-18s %7d bytes" % (filename, os.path.getsize(path)))
    print("Done: %d WAVs @ %d Hz mono 16-bit" % (len(SOUNDS), SR))


if __name__ == "__main__":
    main()
