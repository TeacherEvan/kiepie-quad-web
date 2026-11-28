#!/usr/bin/env python3
"""
Build the 15-second (360 frames @ 24 fps) action-packed intro splash video for
Kiepie-Quad (`web-assets/kiepie-quad-splash.mp4`, landscape 1280x720, or
`web-assets/kiepie-quad-splash-portrait.mp4`, portrait 720x1280) using Blender 5.3.0
EEVEE + Compositor + 48 kHz stereo SFX/procedural audio mix.

Showcases all five selectable vehicles and their signature weapon kits:
  1. Kiepie Quad (`Kiepie_Bike.glb`) — Twin Autocannons + Massive Cyan-White Lightning Strike
  2. BIG-BEN F1 (`Aston_Martin.glb`) — F1 Autocannons + Small `$` Cash Bag Rockets + Giant `$` Cash Bag Meteor Strike
  3. NARDUS (`Pogo_Nardus.blend`) — Pogo Hop, Turbo Wing-Flap + Banana Cannons + Meteor + Sculpted Nuke Explosion + Nuclear Flash
  4. EVAN THE SKELETON (`Evan_Skeleton.glb`) — Sound Waves + Boomerang Guitar Throw/Catch + Giant Articulated Demon Hand + Engulfing Hellfire Drag-Down
  5. LEA UNICORN (`Lea_Unicorn.glb`) — Horn Sparks + Horn Beam + Wing Spread + Aerial Jump -> Big Hot-Pink Landing Flash
  6. FINALE — Dramatic 3D `"Kiepie -QUAD"` Title Slam + Cinema Solar Flare + All 5 Rides

Usage:
  # Preview key frames and composite overlays/flares:
  blender -b -noaudio -P src/build_intro_splash.py -- \
      --preview-frames 30,90,136,146,156,170,178,182,196,204,214,220,226,232,238,265,278,291,295,299,305,311,325,345 \
      --frames-dir /tmp/kiepie_splash_v6_preview_land
  python3 src/build_intro_splash.py --preview-composite \
      --preview-frames 30,90,136,146,156,170,178,182,196,204,214,220,226,232,238,265,278,291,295,299,305,311,325,345 \
      --frames-dir /tmp/kiepie_splash_v6_preview_land

  # Render full 360 frames (landscape or --portrait) & encode:
  blender -b -noaudio --threads 2 -P src/build_intro_splash.py -- --start 0 --end 179 --frames-dir /tmp/kiepie_splash_v6_land
  blender -b -noaudio --threads 2 -P src/build_intro_splash.py -- --start 180 --end 359 --frames-dir /tmp/kiepie_splash_v6_land
  python3 src/build_intro_splash.py --encode-only --frames-dir /tmp/kiepie_splash_v6_land
"""

from __future__ import annotations

import argparse
import math
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_MP4 = ROOT / "web-assets" / "kiepie-quad-splash.mp4"
OUT_PORTRAIT_MP4 = ROOT / "web-assets" / "kiepie-quad-splash-portrait.mp4"
SFX_DIR = ROOT / "godot" / "assets" / "sfx"
_FONT_CANDIDATES = (
    "/usr/share/fonts/truetype/roboto/unhinted/RobotoTTF/Roboto-Black.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
)
FONT_PATH = next((p for p in _FONT_CANDIDATES if Path(p).is_file()), "")

FPS = 24
TOTAL_FRAMES = 360  # 15 s: five equal vehicle spotlights + dramatic finale
WIDTH = 1280
HEIGHT = 720


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    else:
        argv = argv[1:]
    p = argparse.ArgumentParser(description="Render Kiepie-Quad intro splash video.")
    p.add_argument("--frames-dir", type=str, default=str(Path(tempfile.gettempdir()) / "kiepie_splash_frames"))
    p.add_argument("--start", type=int, default=0)
    p.add_argument("--end", type=int, default=TOTAL_FRAMES - 1)
    p.add_argument("--preview-frames", type=str, default="")
    p.add_argument("--encode-only", action="store_true")
    p.add_argument("--preview-composite", action="store_true", help="Composite overlays+flares onto rendered preview frames.")
    p.add_argument("--portrait", action="store_true", help="Render/encode the mobile 9:16 splash variant.")
    return p.parse_args(argv)


# ---------------------------------------------------------------------------
# Audio synthesis (48 kHz stereo WAV, no bpy required)
# ---------------------------------------------------------------------------

def _read_wav_mono(path: Path, target_rate: int = 48000) -> list[float]:
    if not path.exists():
        return []
    with wave.open(str(path), "rb") as wf:
        ch = wf.getnchannels()
        sw = wf.getsampwidth()
        sr = wf.getframerate()
        n = wf.getnframes()
        raw = wf.readframes(n)
    if sw != 2:
        return []
    samples = struct.unpack(f"<{n * ch}h", raw)
    if ch > 1:
        mono = [sum(samples[i : i + ch]) / (ch * 32768.0) for i in range(0, len(samples), ch)]
    else:
        mono = [s / 32768.0 for s in samples]
    if sr == target_rate:
        return mono
    ratio = target_rate / sr
    out_len = int(len(mono) * ratio)
    if out_len <= 0:
        return []
    return [mono[min(int(i / ratio), len(mono) - 1)] for i in range(out_len)]


def _read_wav_stereo(path: Path, target_rate: int = 48000) -> tuple[list[float], list[float]]:
    if not path.exists():
        return ([], [])
    with wave.open(str(path), "rb") as wf:
        ch = wf.getnchannels()
        sw = wf.getsampwidth()
        sr = wf.getframerate()
        n = wf.getnframes()
        raw = wf.readframes(n)
    if sw != 2:
        return ([], [])
    samples = struct.unpack(f"<{n * ch}h", raw)
    if ch >= 2:
        left = [samples[i] / 32768.0 for i in range(0, len(samples), ch)]
        right = [samples[i + 1] / 32768.0 for i in range(0, len(samples), ch)]
    else:
        left = [s / 32768.0 for s in samples]
        right = left[:]
    if sr == target_rate:
        return (left, right)
    ratio = target_rate / sr
    out_len = int(len(left) * ratio)
    if out_len <= 0:
        return ([], [])
    return (
        [left[min(int(i / ratio), len(left) - 1)] for i in range(out_len)],
        [right[min(int(i / ratio), len(right) - 1)] for i in range(out_len)],
    )


def _mix_clip(
    buf_l: list[float],
    buf_r: list[float],
    clip: list[float],
    start_s: float,
    gain: float = 0.5,
    pan: float = 0.0,
    sr: int = 48000,
) -> None:
    if not clip:
        return
    idx0 = int(start_s * sr)
    gl = gain * math.sqrt(max(0.0, 0.5 * (1.0 - pan)))
    gr = gain * math.sqrt(max(0.0, 0.5 * (1.0 + pan)))
    n = len(buf_l)
    for i, s in enumerate(clip):
        j = idx0 + i
        if 0 <= j < n:
            buf_l[j] += s * gl
            buf_r[j] += s * gr


def _add_thunderclap(
    buf_l: list[float],
    buf_r: list[float],
    start_s: float,
    gain: float = 0.75,
    pan: float = 0.1,
    sr: int = 48000,
    seed: int = 7,
) -> None:
    """Synthesize a sharp electric/portal crack + rolling sub-thunder tail."""
    rng = random.Random(seed)
    dur = 1.35
    n_s = int(dur * sr)
    idx0 = int(start_s * sr)
    gl = gain * math.sqrt(max(0.0, 0.5 * (1.0 - pan)))
    gr = gain * math.sqrt(max(0.0, 0.5 * (1.0 + pan)))
    total = len(buf_l)
    for i in range(n_s):
        j = idx0 + i
        if not (0 <= j < total):
            continue
        dt = i / sr
        snap1 = math.exp(-dt * 42.0) * math.sin(2.0 * math.pi * (1800.0 - 900.0 * dt) * dt)
        snap2 = (math.exp(-(dt - 0.11) * 35.0) * 0.75 if dt >= 0.11 else 0.0) * math.sin(2.0 * math.pi * 1350.0 * dt)
        crackle = (rng.random() * 2.0 - 1.0) * (math.exp(-dt * 12.0) * 0.65 + math.exp(-dt * 2.2) * 0.25)
        rumble = math.exp(-dt * 1.9) * math.sin(2.0 * math.pi * (62.0 * math.exp(-dt * 0.6) + 34.0) * dt) * 0.7
        s = snap1 * 0.6 + snap2 * 0.45 + crackle + rumble
        buf_l[j] += s * gl
        buf_r[j] += s * gr


def _add_whoosh(
    buf_l: list[float],
    buf_r: list[float],
    start_s: float,
    dur_s: float,
    f0: float,
    f1: float,
    gain: float = 0.35,
    pan: float = 0.0,
    sr: int = 48000,
    seed: int = 19,
) -> None:
    """Synthesize a pitched swoosh / meteor whistle / boomerang spin."""
    rng = random.Random(seed)
    n_s = int(dur_s * sr)
    idx0 = int(start_s * sr)
    gl = gain * math.sqrt(max(0.0, 0.5 * (1.0 - pan)))
    gr = gain * math.sqrt(max(0.0, 0.5 * (1.0 + pan)))
    total = len(buf_l)
    phase = 0.0
    for i in range(n_s):
        j = idx0 + i
        if not (0 <= j < total):
            continue
        u = i / max(1, n_s - 1)
        env = math.sin(math.pi * u) ** 0.85
        freq = f0 + (f1 - f0) * (u ** 1.3)
        phase += 2.0 * math.pi * freq / sr
        tone = math.sin(phase) * 0.55 + math.sin(phase * 2.03) * 0.22
        air = (rng.random() * 2.0 - 1.0) * 0.35
        s = env * (tone + air)
        buf_l[j] += s * gl
        buf_r[j] += s * gr


def _add_sub_boom(
    buf_l: list[float],
    buf_r: list[float],
    start_s: float,
    dur_s: float = 1.6,
    gain: float = 0.90,
    sr: int = 48000,
    seed: int = 55,
) -> None:
    """Synthesize a deep sub-bass detonation + shock roar."""
    rng = random.Random(seed)
    n_s = int(dur_s * sr)
    idx0 = int(start_s * sr)
    total = len(buf_l)
    phase = 0.0
    for i in range(n_s):
        j = idx0 + i
        if not (0 <= j < total):
            continue
        dt = i / sr
        freq = 92.0 * math.exp(-dt * 3.8) + 30.0
        phase += 2.0 * math.pi * freq / sr
        sub = math.sin(phase) * math.exp(-dt * 1.45)
        roar = (rng.random() * 2.0 - 1.0) * math.exp(-dt * 2.1) * 0.42
        s = gain * (sub * 0.85 + roar)
        buf_l[j] += s
        buf_r[j] += s


def synthesize_audio(wav_out: Path) -> None:
    sr = 48000
    dur_s = TOTAL_FRAMES / FPS  # 15.0 s
    n_samples = int(dur_s * sr)
    buf_l = [0.0] * n_samples
    buf_r = [0.0] * n_samples

    engine = _read_wav_mono(SFX_DIR / "engine_loop.wav", sr)
    turbo = _read_wav_mono(SFX_DIR / "turbo.wav", sr)
    cannon = _read_wav_mono(SFX_DIR / "cannon_fire.wav", sr)
    pop = _read_wav_mono(SFX_DIR / "pop.wav", sr)
    pickup = _read_wav_mono(SFX_DIR / "pickup.wav", sr)
    explosion = _read_wav_mono(SFX_DIR / "explosion.wav", sr)
    impact = _read_wav_mono(SFX_DIR / "impact.wav", sr)

    # Act 1 (0.0 - 2.5s, f=0..59): Kiepie Quad engine + twin autocannons + Lightning Strike
    _mix_clip(buf_l, buf_r, engine, 0.0, gain=0.45, pan=-0.25, sr=sr)
    _mix_clip(buf_l, buf_r, turbo, 0.25, gain=0.40, pan=-0.1, sr=sr)
    for t in (0.25, 0.42, 0.58, 0.75, 0.92, 1.10, 1.28):
        _mix_clip(buf_l, buf_r, cannon, t, gain=0.48, pan=-0.2, sr=sr)
    _add_thunderclap(buf_l, buf_r, 1.40, gain=0.86, pan=0.15, sr=sr, seed=101)
    _mix_clip(buf_l, buf_r, impact, 1.42, gain=0.55, pan=0.15, sr=sr)

    # Act 2 (2.5 - 5.0s, f=60..119): BIG-BEN F1 rev + cash rockets + giant cash drop (f=93 -> 3.88s)
    _mix_clip(buf_l, buf_r, engine, 2.56, gain=0.48, pan=0.15, sr=sr)
    _mix_clip(buf_l, buf_r, turbo, 2.64, gain=0.54, pan=0.1, sr=sr)
    for idx, t in enumerate((2.78, 3.04, 3.30, 3.55)):
        _mix_clip(buf_l, buf_r, cannon, t, gain=0.46, pan=(-0.2 + 0.12 * idx), sr=sr)
        _mix_clip(buf_l, buf_r, pickup, t + 0.05, gain=0.42, pan=(-0.2 + 0.12 * idx), sr=sr)
    _mix_clip(buf_l, buf_r, explosion, 3.88, gain=0.78, pan=0.15, sr=sr)
    for k, dt in enumerate((0.0, 0.12, 0.24, 0.38)):
        _mix_clip(buf_l, buf_r, pickup, 3.92 + dt, gain=0.62 - 0.1 * k, pan=(-0.25 + 0.18 * k), sr=sr)

    # Act 3 (5.0 - 7.5s, f=120..179): Nardus hop + bananas + meteor whistle + nuke boom (f=146 -> 6.08s) + nuclear flash
    _mix_clip(buf_l, buf_r, turbo, 5.08, gain=0.34, pan=0.12, sr=sr)
    for idx, t in enumerate((5.18, 5.48, 5.78, 6.22, 6.56)):
        _mix_clip(buf_l, buf_r, pop, t, gain=0.62, pan=(-0.15 + 0.08 * idx), sr=sr)
    _add_whoosh(buf_l, buf_r, 5.25, 0.84, 780.0, 210.0, gain=0.38, pan=0.15, sr=sr, seed=21)
    _mix_clip(buf_l, buf_r, explosion, 6.08, gain=0.92, pan=0.12, sr=sr)
    _add_sub_boom(buf_l, buf_r, 6.08, dur_s=1.55, gain=0.86, sr=sr, seed=31)
    _add_whoosh(buf_l, buf_r, 7.15, 0.42, 160.0, 960.0, gain=0.42, pan=0.0, sr=sr, seed=37)

    # Act 4 (7.5 - 10.0s, f=180..239): Evan strum + boomerang guitar loop + catch + Giant Demon Hand + Hellfire drag-down
    _mix_clip(buf_l, buf_r, turbo, 7.58, gain=0.30, pan=-0.1, sr=sr)
    _mix_clip(buf_l, buf_r, cannon, 8.06, gain=0.34, pan=0.1, sr=sr)
    _add_whoosh(buf_l, buf_r, 8.08, 0.84, 340.0, 520.0, gain=0.36, pan=0.2, sr=sr, seed=43)
    _mix_clip(buf_l, buf_r, impact, 8.92, gain=0.58, pan=0.0, sr=sr)
    _mix_clip(buf_l, buf_r, pickup, 8.94, gain=0.48, pan=0.0, sr=sr)
    _add_thunderclap(buf_l, buf_r, 9.00, gain=0.92, pan=0.0, sr=sr, seed=416)
    _mix_clip(buf_l, buf_r, explosion, 9.28, gain=0.76, pan=0.0, sr=sr)
    _add_sub_boom(buf_l, buf_r, 9.42, dur_s=0.75, gain=0.78, sr=sr, seed=47)

    # Act 5 (10.0 - 12.5s, f=240..299): Lea gallop + horn beam + wing soar + landing big pink flash (f=291 -> 12.125s)
    _mix_clip(buf_l, buf_r, turbo, 10.12, gain=0.24, pan=0.1, sr=sr)
    _mix_clip(buf_l, buf_r, pickup, 10.35, gain=0.48, pan=0.1, sr=sr)
    _add_whoosh(buf_l, buf_r, 11.00, 1.08, 220.0, 620.0, gain=0.30, pan=0.0, sr=sr, seed=53)
    _mix_clip(buf_l, buf_r, impact, 12.10, gain=0.68, pan=0.0, sr=sr)
    _mix_clip(buf_l, buf_r, explosion, 12.12, gain=0.86, pan=0.0, sr=sr)
    _add_thunderclap(buf_l, buf_r, 12.14, gain=0.74, pan=0.0, sr=sr, seed=929)

    # Act 6 (12.5 - 15.0s, f=300..359): Solar flare shimmer + "Kiepie -QUAD" slam (f=311 -> 12.96s) + finale chord
    _add_whoosh(buf_l, buf_r, 12.52, 0.46, 240.0, 880.0, gain=0.34, pan=0.0, sr=sr, seed=61)
    _add_sub_boom(buf_l, buf_r, 12.96, dur_s=1.25, gain=0.88, sr=sr, seed=67)
    _mix_clip(buf_l, buf_r, impact, 12.96, gain=0.65, pan=0.0, sr=sr)
    _mix_clip(buf_l, buf_r, pickup, 13.08, gain=0.45, pan=0.0, sr=sr)

    # Electric guitar rock soundtrack (`assets/splash_electric_guitar.wav`), with synthetic fallback
    guitar_l, guitar_r = _read_wav_stereo(ROOT / "assets" / "splash_electric_guitar.wav", sr)
    if guitar_l and guitar_r:
        g_len = min(len(guitar_l), len(guitar_r))
        duck_hits = (6.08, 12.12, 12.96)
        for i in range(n_samples):
            t = i / sr
            fade_in = min(1.0, t / 0.18)
            fade_out = min(1.0, max(0.0, (dur_s - t) / 0.55))
            # Boost guitars during Evan's shred act (7.5-10.0s) and the "Kiepie -QUAD" finale (12.5-15.0s)
            gain = 0.62
            if 7.5 <= t < 10.0 or t >= 12.5:
                gain = 0.78
            # Gentle duck on peak explosions/slams so SFX punch cleanly through
            for hit_t in duck_hits:
                dt_h = t - hit_t
                if 0.0 <= dt_h < 0.65:
                    duck = 1.0 - 0.28 * math.exp(-dt_h * 5.2)
                    gain *= duck
            env = fade_in * fade_out * gain
            gi = min(i, g_len - 1)
            buf_l[i] += guitar_l[gi] * env
            buf_r[i] += guitar_r[gi] * env
    else:
        chords = (
            (73.42, 110.00, 146.83),  # Dm
            (87.31, 130.81, 174.61),  # F
            (58.27, 87.31, 116.54),   # Bb
            (65.41, 98.00, 130.81),   # C
            (73.42, 110.00, 146.83),
            (65.41, 98.00, 146.83),
        )
        melody = (293.66, 349.23, 440.00, 392.00, 349.23, 293.66, 261.63, 293.66)
        for i in range(n_samples):
            t = i / sr
            section = min(len(chords) - 1, int(t / 2.5))
            fade_in = min(1.0, t / 0.35)
            fade_out = min(1.0, max(0.0, (dur_s - t) / 0.7))
            env = fade_in * fade_out
            pad = sum(math.sin(2.0 * math.pi * hz * t) for hz in chords[section]) / 3.0
            beat_phase = t % 0.5
            bass = math.sin(2.0 * math.pi * (48.0 * beat_phase + 14.0 * beat_phase * beat_phase))
            kick = math.exp(-beat_phase * 18.0) * bass * 0.16
            step_phase = t % 0.25
            step = int(t / 0.25) % len(melody)
            pluck = math.exp(-step_phase * 13.0) * math.sin(2.0 * math.pi * melody[step] * step_phase)
            music = env * (0.055 * pad + kick + 0.075 * pluck)
            buf_l[i] += music * 0.96
            buf_r[i] += music * 1.04

    fade_start = int((dur_s - 0.4) * sr)
    pcm = bytearray()
    for i in range(n_samples):
        fade = 1.0 if i < fade_start else max(0.0, 1.0 - (i - fade_start) / (n_samples - fade_start))
        l = math.tanh(buf_l[i] * fade) * 32000.0
        r = math.tanh(buf_r[i] * fade) * 32000.0
        pcm.extend(struct.pack("<hh", int(max(-32767, min(32767, l))), int(max(-32767, min(32767, r)))))

    wav_out.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(wav_out), "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(bytes(pcm))


# ---------------------------------------------------------------------------
# 2D HUD Overlays & Optical Screen-Blend Flares (Pillow-only, no numpy)
# ---------------------------------------------------------------------------

def _draw_radial_burst(
    canvas,
    cx: float,
    cy: float,
    layers: list[tuple[float, tuple[int, int, int], float]],
    rays: int = 0,
    ray_angle: float = 0.0,
    ray_len: float = 0.0,
    ray_color: tuple[int, int, int] = (255, 220, 140),
    ray_width: float = 18.0,
) -> None:
    """Draw smooth radial glow layers + optional starburst rays onto an RGB canvas."""
    from PIL import Image, ImageChops, ImageDraw, ImageFilter

    w, h = canvas.size
    hw, hh = max(1, w // 2), max(1, h // 2)
    layer = Image.new("RGB", (hw, hh), (0, 0, 0))
    draw = ImageDraw.Draw(layer)
    hcx, hcy = cx * 0.5, cy * 0.5

    max_blur = 0.0
    for rad, col, blur in layers:
        hr = max(2.0, rad * 0.5)
        draw.ellipse((hcx - hr, hcy - hr, hcx + hr, hcy + hr), fill=col)
        if blur > max_blur:
            max_blur = blur

    if rays > 0 and ray_len > 4.0:
        hlen = ray_len * 0.5
        hw_ray = max(1.5, ray_width * 0.5)
        for k in range(rays):
            ang = ray_angle + k * (2.0 * math.pi / rays)
            ca, sa = math.cos(ang), math.sin(ang)
            nx, ny = -sa * hw_ray, ca * hw_ray
            p0 = (hcx + nx * 0.35, hcy + ny * 0.35)
            p1 = (hcx - nx * 0.35, hcy - ny * 0.35)
            p2 = (hcx + ca * hlen, hcy + sa * hlen)
            draw.polygon([p0, p2, p1], fill=ray_color)

    if max_blur > 0.5:
        layer = layer.filter(ImageFilter.GaussianBlur(radius=max(1.0, max_blur * 0.5)))

    up = layer.resize((w, h), Image.Resampling.BILINEAR)
    added = ImageChops.add(canvas, up)
    canvas.paste(added)


def build_overlay_image(frame: int, width: int, height: int, portrait: bool, fonts: dict):
    from PIL import Image, ImageDraw

    t = frame / FPS
    cards = [
        (0.00, 2.50, "KIEPIE QUAD", (("PRIMARY", "Twin autocannons"), ("SPECIAL", "Finned rocket"), ("ULTIMATE", "Lightning strike")), (56, 205, 235)),
        (2.50, 5.00, "BIG-BEN F1", (("PRIMARY", "F1 autocannon"), ("SPECIAL", "Cash bag"), ("ULTIMATE", "Cash drop")), (164, 220, 102)),
        (5.00, 7.50, "NARDUS", (("PRIMARY", "Banana cannons"), ("SPECIAL", "Cigar launcher"), ("ULTIMATE", "Meteor nuke")), (250, 113, 186)),
        (7.50, 10.00, "EVAN THE SKELETON", (("PRIMARY", "Sound waves"), ("SPECIAL", "Boomerang guitar"), ("ULTIMATE", "Devil hand")), (246, 102, 168)),
        (10.00, 12.50, "LEA UNICORN", (("PRIMARY", "Horn sparks"), ("SPECIAL", "Horn beam"), ("ULTIMATE", "Unicorn boom")), (246, 208, 111)),
        (12.50, 15.00, "KIEPIE -QUAD", (), (255, 194, 72)),
    ]
    vehicle_accents = (
        (56, 205, 235),
        (164, 220, 102),
        (250, 113, 186),
        (246, 102, 168),
        (246, 208, 111),
    )

    overlay = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    card = next((c for c in cards if c[0] <= t < c[1]), None)
    if not card:
        return overlay

    start, end, title, abilities, accent = card

    # Fade the 2D card out cleanly before full-screen transition flashes
    card_fade = 1.0
    if 173 <= frame <= 183:
        if frame < 176:
            card_fade = max(0.0, (176.0 - frame) / 3.0)
        elif frame <= 181:
            card_fade = 0.0
        else:
            card_fade = min(1.0, (frame - 181.0) / 2.0)
    elif 291 <= frame <= 304:
        if frame < 294:
            card_fade = max(0.0, (294.0 - frame) / 3.0)
        elif frame <= 301:
            card_fade = 0.0
        else:
            card_fade = min(1.0, (frame - 301.0) / 3.0)

    if card_fade <= 0.02:
        return overlay

    layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    progress = max(0.0, min(1.0, (t - start) / (end - start)))

    if abilities:
        index = cards.index(card) + 1
        if portrait:
            panel = (38, 62, 682, 344)
        else:
            panel = (44, 28, 478, 254)
        draw.rounded_rectangle(panel, radius=18, fill=(5, 13, 27, 220), outline=(255, 255, 255, 36), width=1)
        draw.rounded_rectangle((panel[0], panel[1], panel[0] + 9, panel[3]), radius=4, fill=(*accent, 255))
        if portrait:
            card_left, card_top = 38, 62
            draw.text((card_left + 30, card_top + 22), f"SELECTABLE RIDE     /     {index:02d} OF 05", font=fonts["category"], fill=(*accent, 255))
            draw.text((card_left + 30, card_top + 50), title, font=fonts["title"], fill=(255, 255, 255, 255))
            row_y, row_gap, row_left, row_right, label_x, value_x = 156, 52, 58, 662, 78, 204
            progress_left, progress_right, progress_y = 58, 662, 326
        else:
            draw.text((76, 42), f"SELECTABLE RIDE     /     {index:02d} OF 05", font=fonts["category"], fill=(*accent, 255))
            draw.text((76, 61), title, font=fonts["title"], fill=(255, 255, 255, 255))
            row_y, row_gap, row_left, row_right, label_x, value_x = 110, 41, 68, 454, 80, 177
            progress_left, progress_right, progress_y = 66, 456, 245

        for col, (kind, ability) in enumerate(abilities):
            y = row_y + col * row_gap
            row_height = 42 if portrait else 34
            draw.rounded_rectangle((row_left, y, row_right, y + row_height), radius=8, fill=(255, 255, 255, 14), outline=(255, 255, 255, 24), width=1)
            draw.text((label_x, y + (10 if portrait else 8)), kind, font=fonts["category"], fill=(*accent, 255))
            draw.text((value_x, y + (6 if portrait else 5)), ability, font=fonts["detail"], fill=(245, 248, 255, 255))

        draw.rounded_rectangle((progress_left, progress_y, progress_right, progress_y + 3), radius=2, fill=(255, 255, 255, 35))
        draw.rounded_rectangle((progress_left, progress_y, progress_left + int((progress_right - progress_left) * progress), progress_y + 3), radius=2, fill=(*accent, 220))
    else:
        # Act 6: Sleek unobstructed chrome strips at very top/bottom so the 3D "Kiepie -QUAD"
        # title, blazing Solar Flare, and 5-vehicle lineup shine front-and-center.
        eyebrow = "FIVE RIDES     /     ONE ARENA"
        ebox = draw.textbbox((0, 0), eyebrow, font=fonts["category"])
        ew = ebox[2] - ebox[0]
        if portrait:
            pill = (width // 2 - 210, 56, width // 2 + 210, 102)
            draw.rounded_rectangle(pill, radius=22, fill=(6, 12, 26, 200), outline=(255, 200, 90, 90), width=1)
            draw.text(((width - ew) / 2, 68), eyebrow, font=fonts["category"], fill=(255, 208, 105, 255))
            bar_y = 1172
            for i, color in enumerate(vehicle_accents):
                x0 = 60 + i * 124
                draw.rounded_rectangle((x0, bar_y, x0 + 104, bar_y + 7), radius=4, fill=(*color, 235))
            draw.rounded_rectangle((60, bar_y + 18, 660, bar_y + 21), radius=2, fill=(255, 255, 255, 35))
            draw.rounded_rectangle((60, bar_y + 18, 60 + int(600 * progress), bar_y + 21), radius=2, fill=(255, 194, 72, 230))
        else:
            pill = (width // 2 - 200, 22, width // 2 + 200, 58)
            draw.rounded_rectangle(pill, radius=18, fill=(6, 12, 26, 195), outline=(255, 200, 90, 90), width=1)
            draw.text(((width - ew) / 2, 32), eyebrow, font=fonts["category"], fill=(255, 208, 105, 255))
            bar_y = 678
            for i, color in enumerate(vehicle_accents):
                x0 = 140 + i * 204
                draw.rounded_rectangle((x0, bar_y, x0 + 184, bar_y + 6), radius=3, fill=(*color, 235))
            draw.rounded_rectangle((140, bar_y + 14, 1140, bar_y + 17), radius=2, fill=(255, 255, 255, 35))
            draw.rounded_rectangle((140, bar_y + 14, 140 + int(1000 * progress), bar_y + 17), radius=2, fill=(255, 194, 72, 230))

    if card_fade < 0.99:
        r, g, b, a = layer.split()
        a = a.point(lambda px: int(px * card_fade))
        layer = Image.merge("RGBA", (r, g, b, a))
    return layer


def build_flare_image(frame: int, width: int, height: int, portrait: bool):
    """Build RGB screen-blend flare/flash layer on pure black (0,0,0)."""
    from PIL import Image, ImageChops, ImageDraw, ImageFilter

    flare = Image.new("RGB", (width, height), (0, 0, 0))

    # 1. Nuclear Flash Transition (f = 172..185): Nardus nuke -> Evan the Skeleton
    if 172 <= frame <= 185:
        if frame <= 179:
            u = (frame - 172.0) / 7.0
            strength = u ** 1.35
        else:
            u = (frame - 179.0) / 6.0
            strength = max(0.0, (1.0 - u) ** 1.55)
        if strength > 0.01:
            cx = width * (0.55 if portrait else 0.56)
            cy = height * (0.44 if portrait else 0.45)
            max_dim = max(width, height)
            base_glow = int(min(255, 255 * (strength ** 1.15)))
            core_r = max(12.0, max_dim * (0.14 + 0.95 * strength))
            halo_r = max(24.0, max_dim * (0.28 + 1.15 * strength))
            _draw_radial_burst(
                flare,
                cx,
                cy,
                layers=[
                    (halo_r, (int(255 * strength), int(145 * strength), int(48 * strength)), 90.0),
                    (core_r, (int(255 * strength), int(232 * strength), int(170 * strength)), 52.0),
                    (core_r * 0.48, (base_glow, base_glow, int(base_glow * 0.94)), 24.0),
                ],
                rays=10,
                ray_angle=(frame - 172) * 0.05,
                ray_len=max_dim * (0.45 + 0.65 * strength),
                ray_color=(int(255 * strength), int(210 * strength), int(125 * strength)),
                ray_width=24.0 + 36.0 * strength,
            )
            if strength > 0.72:
                fill_k = (strength - 0.72) / 0.28
                veil = Image.new("RGB", (width, height), (int(255 * fill_k), int(248 * fill_k), int(230 * fill_k)))
                flare = ImageChops.screen(flare, veil)

    # 2. Big Hot-Pink Landing Flash Transition (f = 291..306): Lea landing -> "Kiepie -QUAD"
    if 291 <= frame <= 306:
        if frame <= 299:
            u = (frame - 291.0) / 8.0
            strength = u ** 1.15
        else:
            u = (frame - 299.0) / 7.0
            strength = max(0.0, (1.0 - u) ** 1.45)
        if strength > 0.01:
            cx = width * 0.50
            cy = height * (0.58 if portrait else 0.60)
            max_dim = max(width, height)
            hot_r = max(20.0, max_dim * (0.24 + 1.05 * strength))
            core_r = max(12.0, max_dim * (0.08 + 0.48 * strength))
            _draw_radial_burst(
                flare,
                cx,
                cy,
                layers=[
                    (hot_r * 1.25, (int(255 * strength), int(20 * strength), int(165 * strength)), 96.0),
                    (hot_r * 0.72, (int(255 * strength), int(52 * strength), int(200 * strength)), 56.0),
                    (core_r, (int(255 * strength), int(195 * strength), int(240 * strength)), 26.0),
                ],
                rays=14,
                ray_angle=(frame - 291) * 0.06,
                ray_len=max_dim * (0.48 + 0.68 * strength),
                ray_color=(int(255 * strength), int(78 * strength), int(206 * strength)),
                ray_width=20.0 + 34.0 * strength,
            )
            if strength > 0.70:
                fill_k = (strength - 0.70) / 0.30
                veil = Image.new("RGB", (width, height), (int(255 * fill_k), int(68 * fill_k), int(202 * fill_k)))
                flare = ImageChops.screen(flare, veil)

    # 3. Cinema Anamorphic Solar Flare (f = 301..359): sweeps across upper-right crown of "Kiepie -QUAD"
    if frame >= 301:
        sweep = max(0.0, min(1.0, (frame - 301.0) / 26.0))
        ease_sweep = 1.0 - (1.0 - sweep) ** 2.2
        fx = width * (0.36 + 0.38 * ease_sweep)
        fy = height * (0.19 if portrait else 0.18)
        pulse = 1.0 + 0.28 * math.exp(-((frame - 312.0) / 6.5) ** 2) + 0.06 * math.sin(frame * 0.32)
        fade_in = min(1.0, (frame - 301.0) / 7.0)
        k = fade_in * min(1.12, pulse)

        # Sun burst + 8-point diffraction spikes (kept warm golden without whitewashing the 3D title)
        _draw_radial_burst(
            flare,
            fx,
            fy,
            layers=[
                ((200 if portrait else 255) * k, (int(195 * min(1.0, k)), int(92 * min(1.0, k)), int(18 * min(1.0, k))), 72.0),
                ((88 if portrait else 112) * k, (int(245 * min(1.0, k)), int(185 * min(1.0, k)), int(74 * min(1.0, k))), 32.0),
                ((30 if portrait else 38) * k, (255, 244, 205), 12.0),
            ],
            rays=8,
            ray_angle=0.22 + (frame - 301) * 0.018,
            ray_len=(195 if portrait else 270) * k,
            ray_color=(int(215 * min(1.0, k)), int(152 * min(1.0, k)), int(58 * min(1.0, k))),
            ray_width=7.0,
        )

        # Wide anamorphic horizontal optical streak + subtle lens bokeh rings
        streak_layer = Image.new("RGB", (width // 2, height // 2), (0, 0, 0))
        sd = ImageDraw.Draw(streak_layer)
        hfx, hfy = fx * 0.5, fy * 0.5
        span_x = (width * 0.46) * min(1.0, k)
        sd.polygon(
            [(hfx - span_x, hfy), (hfx, hfy - 6.0 * k), (hfx + span_x, hfy), (hfx, hfy + 6.0 * k)],
            fill=(220, 148, 48),
        )
        sd.polygon(
            [(hfx - span_x * 0.65, hfy), (hfx, hfy - 2.2 * k), (hfx + span_x * 0.65, hfy), (hfx, hfy + 2.2 * k)],
            fill=(255, 232, 175),
        )
        cx_mid, cy_mid = width * 0.25, height * 0.25
        dx, dy = cx_mid - hfx, cy_mid - hfy
        for t_ring, rad, col in (
            (0.55, 14, (130, 60, 18)),
            (1.10, 24, (105, 36, 84)),
            (1.62, 16, (58, 108, 132)),
        ):
            bx, by = hfx + dx * t_ring, hfy + dy * t_ring
            sd.ellipse((bx - rad, by - rad, bx + rad, by + rad), outline=col, width=2)
        streak_layer = streak_layer.filter(ImageFilter.GaussianBlur(radius=3.5))
        flare = ImageChops.screen(flare, streak_layer.resize((width, height), Image.Resampling.BILINEAR))

    return flare


def is_flare_active(frame: int) -> bool:
    return (172 <= frame <= 185) or (291 <= frame <= 359)


def _load_pil_fonts(portrait: bool) -> dict:
    from PIL import ImageFont

    font_path = FONT_PATH or "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    return {
        "title": ImageFont.truetype(font_path, 44 if portrait else 38),
        "category": ImageFont.truetype(font_path, 22 if portrait else 15),
        "detail": ImageFont.truetype(font_path, 28 if portrait else 21),
    }


def preview_composite(frames_dir: Path, target_frames: list[int], portrait: bool = False) -> None:
    from PIL import Image, ImageChops

    width, height = (720, 1280) if portrait else (WIDTH, HEIGHT)
    fonts = _load_pil_fonts(portrait)
    comp_dir = frames_dir / "composited"
    comp_dir.mkdir(parents=True, exist_ok=True)
    for frame in target_frames:
        raw_path = frames_dir / f"frame_{frame:04d}.png"
        if not raw_path.is_file():
            continue
        base = Image.open(raw_path).convert("RGBA")
        overlay = build_overlay_image(frame, width, height, portrait, fonts)
        merged = Image.alpha_composite(base, overlay).convert("RGB")
        if is_flare_active(frame):
            flare = build_flare_image(frame, width, height, portrait)
            merged = ImageChops.screen(merged, flare)
        merged.save(comp_dir / f"comp_{frame:04d}.png", optimize=True)
    print(f"Composited {len(target_frames)} preview frames in {comp_dir}")


def encode_video(frames_dir: Path, portrait: bool = False) -> None:
    from PIL import Image

    wav_path = frames_dir / "splash_audio.wav"
    synthesize_audio(wav_path)
    width, height = (720, 1280) if portrait else (WIDTH, HEIGHT)
    output_path = OUT_PORTRAIT_MP4 if portrait else OUT_MP4
    output_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_mp4 = output_path.with_suffix(".tmp.mp4")

    overlay_dir = frames_dir / "overlays"
    flare_dir = frames_dir / "flares"
    overlay_dir.mkdir(parents=True, exist_ok=True)
    flare_dir.mkdir(parents=True, exist_ok=True)

    fonts = _load_pil_fonts(portrait)
    black_flare_path = flare_dir / "_black.png"
    Image.new("RGB", (width, height), (0, 0, 0)).save(black_flare_path, optimize=True)

    for frame in range(TOTAL_FRAMES):
        overlay = build_overlay_image(frame, width, height, portrait, fonts)
        overlay.save(overlay_dir / f"overlay_{frame:04d}.png", optimize=True)

        flare_dst = flare_dir / f"flare_{frame:04d}.png"
        if flare_dst.exists():
            flare_dst.unlink()
        if is_flare_active(frame):
            flare = build_flare_image(frame, width, height, portrait)
            flare.save(flare_dst, optimize=True)
        else:
            try:
                os.link(black_flare_path, flare_dst)
            except OSError:
                shutil.copyfile(black_flare_path, flare_dst)

    cmd = [
        "ffmpeg",
        "-y",
        "-framerate", str(FPS),
        "-i", str(frames_dir / "frame_%04d.png"),
        "-framerate", str(FPS),
        "-i", str(overlay_dir / "overlay_%04d.png"),
        "-framerate", str(FPS),
        "-i", str(flare_dir / "flare_%04d.png"),
        "-i", str(wav_path),
        "-filter_complex",
        "[0:v][1:v]overlay=0:0:format=auto,format=gbrp[base];"
        "[2:v]format=gbrp[flr];"
        "[base][flr]blend=all_mode=screen,format=yuv420p[v]",
        "-map", "[v]",
        "-map", "3:a",
        "-c:v", "libx264",
        "-profile:v", "high",
        "-level:v", "4.2",
        "-pix_fmt", "yuv420p",
        "-colorspace", "bt709",
        "-color_primaries", "bt709",
        "-color_trc", "bt709",
        "-crf", "27",
        "-preset", "slow",
        "-movflags", "+faststart",
        "-c:a", "aac",
        "-b:a", "96k",
        "-shortest",
        "-s", f"{width}x{height}",
        str(tmp_mp4),
    ]
    try:
        subprocess.run(cmd, check=True, timeout=180)
        os.replace(tmp_mp4, output_path)
    except BaseException:
        tmp_mp4.unlink(missing_ok=True)
        raise
    print(f"Encoded {output_path} ({output_path.stat().st_size / 1024:.1f} KiB)")


# ---------------------------------------------------------------------------
# Blender 5.3.0 Scene & VFX Builder
# ---------------------------------------------------------------------------

def build_and_render(args: argparse.Namespace) -> None:
    import bpy
    import bmesh
    from mathutils import Vector

    frames_dir = Path(args.frames_dir)
    frames_dir.mkdir(parents=True, exist_ok=True)

    # 1. Start from Pogo_Nardus.blend so Nardus + articulated pivots/materials stay intact
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / "Pogo_Nardus.blend"))
    scene = bpy.context.scene

    for obj in list(bpy.data.objects):
        if obj.name == "ProofFloor" or obj.type in ("CAMERA", "LIGHT"):
            bpy.data.objects.remove(obj, do_unlink=True)

    nardus_root = bpy.data.objects.new("NardusRoot", None)
    scene.collection.objects.link(nardus_root)
    nardus_objs = [o for o in bpy.data.objects if o != nardus_root]
    for o in nardus_objs:
        o.rotation_mode = "XYZ"
        if o.parent is None:
            o.parent = nardus_root
    nardus_arm_l = bpy.data.objects.get("Arm_L")
    nardus_arm_r = bpy.data.objects.get("Arm_R")

    # 2. Import Kiepie_Bike.glb (QuadRoot)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "godot" / "assets" / "Kiepie_Bike.glb"))
    quad_objs = list(set(bpy.data.objects) - before)
    quad_root = bpy.data.objects.new("QuadRoot", None)
    scene.collection.objects.link(quad_root)
    quad_wheels = []
    for o in quad_objs:
        o.rotation_mode = "XYZ"
        if o.parent is None:
            o.parent = quad_root
        if "Wheel_" in o.name:
            quad_wheels.append(o)

    # 3. Import Aston_Martin.glb (AstonRoot — BIG-BEN F1)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "godot" / "assets" / "Aston_Martin.glb"))
    aston_objs = list(set(bpy.data.objects) - before)
    aston_root = bpy.data.objects.new("AstonRoot", None)
    scene.collection.objects.link(aston_root)
    aston_wheels = []
    for o in aston_objs:
        o.rotation_mode = "XYZ"
        if o.parent is None:
            o.parent = aston_root
        if "Wheel_" in o.name:
            aston_wheels.append(o)

    # 4. Import Evan_Skeleton.glb and Lea_Unicorn.glb
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "godot" / "assets" / "Evan_Skeleton.glb"))
    evan_objs = list(set(bpy.data.objects) - before)
    evan_root = bpy.data.objects.new("EvanRoot", None)
    scene.collection.objects.link(evan_root)
    for o in evan_objs:
        o.rotation_mode = "XYZ"
        if o.parent is None:
            o.parent = evan_root
    evan_rig = next((o for o in evan_objs if o.type == "ARMATURE"), None)
    evan_guitar_parts = [o for o in evan_objs if "guitar" in o.name.lower()]

    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "godot" / "assets" / "Lea_Unicorn.glb"))
    lea_objs = list(set(bpy.data.objects) - before)
    lea_root = bpy.data.objects.new("LeaRoot", None)
    scene.collection.objects.link(lea_root)
    for o in lea_objs:
        o.rotation_mode = "XYZ"
        if o.parent is None:
            o.parent = lea_root
    lea_rig = next((o for o in lea_objs if o.type == "ARMATURE"), None)

    # Configure EEVEE + Render
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = 4
    render_width, render_height = (720, 1280) if args.portrait else (WIDTH, HEIGHT)
    scene.render.resolution_x = render_width
    scene.render.resolution_y = render_height
    scene.render.resolution_percentage = 100
    scene.render.fps = FPS
    scene.frame_start = 0
    scene.frame_end = TOTAL_FRAMES - 1
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.compression = 15
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.25
    scene.view_settings.gamma = 1.0

    # Dark volcanic/cyber arena world
    world = scene.world or bpy.data.worlds.new("SplashWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.032, 0.046, 0.072, 1.0)
        bg.inputs[1].default_value = 0.65

    # Blender 5.3.0 Compositor: Bloom -> NodeGroupOutput
    scene.use_nodes = True
    ng = bpy.data.node_groups.new("SplashComp", "CompositorNodeTree")
    ng.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    scene.compositing_node_group = ng
    rl = ng.nodes.new("CompositorNodeRLayers")
    g_bloom = ng.nodes.new("CompositorNodeGlare")
    g_bloom.inputs["Type"].default_value = "Bloom"
    g_bloom.inputs["Threshold"].default_value = 2.2
    out = ng.nodes.new("NodeGroupOutput")
    ng.links.new(rl.outputs["Image"], g_bloom.inputs["Image"])
    ng.links.new(g_bloom.outputs["Image"], out.inputs["Image"])

    loaded_font = bpy.data.fonts.load(FONT_PATH) if Path(FONT_PATH).exists() else None

    def set_smooth(obj) -> None:
        if obj and obj.type == "MESH" and obj.data:
            for poly in obj.data.polygons:
                poly.use_smooth = True

    def make_emissive(name: str, color: tuple[float, float, float, float], strength: float):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        nodes.clear()
        em = nodes.new("ShaderNodeEmission")
        em.inputs["Color"].default_value = color
        em.inputs["Strength"].default_value = strength
        mo = nodes.new("ShaderNodeOutputMaterial")
        mat.node_tree.links.new(em.outputs["Emission"], mo.inputs["Surface"])
        return mat

    def make_pbr(
        name: str,
        base: tuple[float, float, float, float],
        roughness: float = 0.4,
        metallic: float = 0.0,
        emit_color: tuple[float, float, float, float] | None = None,
        emit_strength: float = 0.0,
    ):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = base
            bsdf.inputs["Roughness"].default_value = roughness
            bsdf.inputs["Metallic"].default_value = metallic
            if emit_color and "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = emit_color
                bsdf.inputs["Emission Strength"].default_value = emit_strength
        return mat

    def make_magma_rock_mat(name: str):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        nt = mat.node_tree
        nodes = nt.nodes
        links = nt.links
        bsdf = nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (0.06, 0.020, 0.015, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.86

        tex = nodes.new("ShaderNodeTexCoord")
        vor = nodes.new("ShaderNodeTexVoronoi")
        vor.feature = "DISTANCE_TO_EDGE"
        vor.inputs["Scale"].default_value = 4.2
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 6.5
        noise.inputs["Detail"].default_value = 5.0

        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.65
        bump.inputs["Distance"].default_value = 0.08
        links.new(tex.outputs["Object"], vor.inputs["Vector"])
        links.new(tex.outputs["Object"], noise.inputs["Vector"])
        links.new(noise.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.00
        ramp.color_ramp.elements[0].color = (1.0, 0.72, 0.14, 1.0)
        e_mid = ramp.color_ramp.elements.new(0.14)
        e_mid.color = (1.0, 0.22, 0.02, 1.0)
        ramp.color_ramp.elements[-1].position = 0.30
        ramp.color_ramp.elements[-1].color = (0.0, 0.0, 0.0, 1.0)
        links.new(vor.outputs["Distance"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 11.0
        return mat

    def make_nuke_fireball_mat(name: str):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        nt = mat.node_tree
        nodes = nt.nodes
        links = nt.links
        bsdf = nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (0.075, 0.028, 0.022, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.92

        tex = nodes.new("ShaderNodeTexCoord")
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 2.8
        noise.inputs["Detail"].default_value = 6.0
        noise.inputs["Roughness"].default_value = 0.65
        links.new(tex.outputs["Object"], noise.inputs["Vector"])

        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.7
        bump.inputs["Distance"].default_value = 0.12
        links.new(noise.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.32
        ramp.color_ramp.elements[0].color = (0.04, 0.01, 0.01, 1.0)
        e1 = ramp.color_ramp.elements.new(0.50)
        e1.color = (0.88, 0.07, 0.01, 1.0)
        e2 = ramp.color_ramp.elements.new(0.66)
        e2.color = (1.0, 0.38, 0.02, 1.0)
        ramp.color_ramp.elements[-1].position = 0.80
        ramp.color_ramp.elements[-1].color = (1.0, 0.94, 0.58, 1.0)
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])

        mult = nodes.new("ShaderNodeMath")
        mult.operation = "MULTIPLY"
        mult.inputs[1].default_value = 8.5
        pw = nodes.new("ShaderNodeMath")
        pw.operation = "POWER"
        pw.inputs[1].default_value = 2.4
        links.new(noise.outputs["Fac"], pw.inputs[0])
        links.new(pw.outputs["Value"], mult.inputs[0])
        links.new(mult.outputs["Value"], bsdf.inputs["Emission Strength"])
        return mat

    def make_nuke_cap_smoke_mat(name: str):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        nt = mat.node_tree
        nodes = nt.nodes
        links = nt.links
        bsdf = nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (0.065, 0.045, 0.048, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.95

        tex = nodes.new("ShaderNodeTexCoord")
        sep = nodes.new("ShaderNodeSeparateXYZ")
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 3.2
        noise.inputs["Detail"].default_value = 6.0
        noise.inputs["Roughness"].default_value = 0.65
        links.new(tex.outputs["Generated"], sep.inputs["Vector"])
        links.new(tex.outputs["Object"], noise.inputs["Vector"])

        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.75
        bump.inputs["Distance"].default_value = 0.12
        links.new(noise.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

        # Combine inverted Z (under-glow) with noise so cap underside glows fiery orange while crown top is dark smoke
        inv_z = nodes.new("ShaderNodeMath")
        inv_z.operation = "SUBTRACT"
        inv_z.inputs[0].default_value = 1.0
        links.new(sep.outputs["Z"], inv_z.inputs[1])

        mix_fac = nodes.new("ShaderNodeMath")
        mix_fac.operation = "MULTIPLY"
        links.new(inv_z.outputs["Value"], mix_fac.inputs[0])
        links.new(noise.outputs["Fac"], mix_fac.inputs[1])

        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.16
        ramp.color_ramp.elements[0].color = (0.02, 0.01, 0.01, 1.0)
        e1 = ramp.color_ramp.elements.new(0.38)
        e1.color = (0.85, 0.10, 0.01, 1.0)
        ramp.color_ramp.elements[-1].position = 0.62
        ramp.color_ramp.elements[-1].color = (1.0, 0.56, 0.08, 1.0)
        links.new(mix_fac.outputs["Value"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])

        em_str = nodes.new("ShaderNodeMath")
        em_str.operation = "MULTIPLY"
        em_str.inputs[1].default_value = 6.5
        links.new(mix_fac.outputs["Value"], em_str.inputs[0])
        links.new(em_str.outputs["Value"], bsdf.inputs["Emission Strength"])
        return mat

    def make_demon_flesh_mat(name: str):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        nt = mat.node_tree
        nodes = nt.nodes
        links = nt.links
        bsdf = nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (0.045, 0.008, 0.012, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.34
        bsdf.inputs["Metallic"].default_value = 0.24

        tex = nodes.new("ShaderNodeTexCoord")
        vor = nodes.new("ShaderNodeTexVoronoi")
        vor.feature = "DISTANCE_TO_EDGE"
        vor.inputs["Scale"].default_value = 3.6
        links.new(tex.outputs["Object"], vor.inputs["Vector"])

        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.45
        bump.inputs["Distance"].default_value = 0.04
        links.new(vor.outputs["Distance"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.00
        ramp.color_ramp.elements[0].color = (1.0, 0.09, 0.02, 1.0)
        e1 = ramp.color_ramp.elements.new(0.016)
        e1.color = (0.72, 0.02, 0.04, 1.0)
        ramp.color_ramp.elements[-1].position = 0.042
        ramp.color_ramp.elements[-1].color = (0.0, 0.0, 0.0, 1.0)
        links.new(vor.outputs["Distance"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.9
        return mat

    def make_hellfire_mat(name: str, core: bool = False):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        nt = mat.node_tree
        nodes = nt.nodes
        links = nt.links
        nodes.clear()

        tex = nodes.new("ShaderNodeTexCoord")
        sep = nodes.new("ShaderNodeSeparateXYZ")
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 4.2
        noise.inputs["Detail"].default_value = 4.0
        links.new(tex.outputs["Generated"], sep.inputs["Vector"])
        links.new(tex.outputs["Object"], noise.inputs["Vector"])

        add = nodes.new("ShaderNodeMath")
        add.operation = "ADD"
        links.new(sep.outputs["Z"], add.inputs[0])
        nmult = nodes.new("ShaderNodeMath")
        nmult.operation = "MULTIPLY"
        nmult.inputs[1].default_value = 0.35
        links.new(noise.outputs["Fac"], nmult.inputs[0])
        links.new(nmult.outputs["Value"], add.inputs[1])

        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.06
        ramp.color_ramp.elements[0].color = (1.0, 0.72, 0.14, 1.0) if core else (1.0, 0.45, 0.04, 1.0)
        e1 = ramp.color_ramp.elements.new(0.42)
        e1.color = (1.0, 0.18, 0.01, 1.0)
        ramp.color_ramp.elements[-1].position = 0.86
        ramp.color_ramp.elements[-1].color = (0.72, 0.02, 0.02, 1.0)
        links.new(add.outputs["Value"], ramp.inputs["Fac"])

        em = nodes.new("ShaderNodeEmission")
        em.inputs["Strength"].default_value = 4.4 if core else 3.0
        links.new(ramp.outputs["Color"], em.inputs["Color"])

        mo = nodes.new("ShaderNodeOutputMaterial")
        links.new(em.outputs["Emission"], mo.inputs["Surface"])
        return mat

    # Arena floor
    bpy.ops.mesh.primitive_plane_add(size=180.0, location=(0.0, 0.0, 0.0))
    floor = bpy.context.active_object
    floor.name = "ArenaFloor"
    floor.data.materials.append(make_pbr("ArenaFloorMat", (0.028, 0.038, 0.060, 1.0), roughness=0.38, metallic=0.22))

    # Lights: ONLY SunKey casts shadows (Blender 5.3 Vulkan shadow buffer rule)
    sun_data = bpy.data.lights.new("SunKey", type="SUN")
    sun_data.energy = 2.8
    sun_data.color = (1.0, 0.94, 0.84)
    sun_data.use_shadow = True
    sun_obj = bpy.data.objects.new("SunKey", sun_data)
    sun_obj.rotation_euler = (math.radians(48), math.radians(15), math.radians(-35))
    scene.collection.objects.link(sun_obj)

    rim_data = bpy.data.lights.new("RimCool", type="AREA")
    rim_data.energy = 740.0
    rim_data.color = (0.28, 0.76, 1.0)
    rim_data.size = 9.0
    rim_data.use_shadow = False
    rim_obj = bpy.data.objects.new("RimCool", rim_data)
    rim_obj.location = (-8.0, 12.0, 6.5)
    rim_obj.rotation_euler = (math.radians(65), 0.0, math.radians(-145))
    scene.collection.objects.link(rim_obj)

    fill_data = bpy.data.lights.new("FrontFill", type="AREA")
    fill_data.energy = 760.0
    fill_data.color = (1.0, 0.90, 0.76)
    fill_data.size = 8.0
    fill_data.use_shadow = False
    fill_obj = bpy.data.objects.new("FrontFill", fill_data)
    fill_obj.location = (6.0, -10.0, 4.5)
    fill_obj.rotation_euler = (math.radians(60), 0.0, math.radians(30))
    scene.collection.objects.link(fill_obj)

    camera_fill_data = bpy.data.lights.new("CameraSoftbox", type="AREA")
    camera_fill_data.energy = 920.0
    camera_fill_data.color = (0.72, 0.86, 1.0)
    camera_fill_data.size = 7.5
    camera_fill_data.use_shadow = False
    camera_fill = bpy.data.objects.new("CameraSoftbox", camera_fill_data)
    camera_fill.location = (0.0, -3.8, 5.0)
    camera_fill.rotation_euler = (math.radians(28), 0.0, 0.0)
    scene.collection.objects.link(camera_fill)

    flare_data = bpy.data.lights.new("FlareLight", type="POINT")
    flare_data.energy = 0.0
    flare_data.color = (1.0, 0.82, 0.42)
    flare_data.use_shadow = False
    flare_light = bpy.data.objects.new("FlareLight", flare_data)
    flare_light.location = (0.0, 26.0, 7.5)
    scene.collection.objects.link(flare_light)

    # Camera + Track-To target
    cam_target = bpy.data.objects.new("CamTarget", None)
    scene.collection.objects.link(cam_target)
    cam_data = bpy.data.cameras.new("SplashCam")
    cam_data.lens = 42.0
    cam_data.sensor_fit = "VERTICAL" if args.portrait else "HORIZONTAL"
    cam_data.clip_end = 500.0
    cam_obj = bpy.data.objects.new("SplashCam", cam_data)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj
    track = cam_obj.constraints.new("TRACK_TO")
    track.target = cam_target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"

    # Shared VFX Materials
    mat_tracer = make_emissive("TracerMat", (0.20, 0.95, 1.0, 1.0), 6.0)
    mat_banana = make_emissive("BananaMat", (1.0, 0.86, 0.05, 1.0), 1.8)
    mat_meteor_rock = make_magma_rock_mat("MeteorMagmaMat")
    mat_meteor_tail = make_emissive("MeteorTailMat", (1.0, 0.36, 0.04, 1.0), 6.2)
    mat_meteor_core = make_emissive("MeteorCoreMat", (1.0, 0.92, 0.48, 1.0), 11.0)
    mat_nuke_fireball = make_nuke_fireball_mat("NukeFireballMat")
    mat_nuke_cap_smoke = make_nuke_cap_smoke_mat("NukeCapSmokeMat")
    mat_nuke_core = make_emissive("NukeCoreMat", (1.0, 0.95, 0.72, 1.0), 14.0)
    mat_nuke_wilson = make_emissive("NukeWilsonMat", (1.0, 0.90, 0.78, 1.0), 3.6)
    mat_shock = make_emissive("ShockRingMat", (1.0, 0.68, 0.22, 1.0), 3.2)

    mat_bolt_core = make_emissive("BoltCoreMat", (0.58, 0.96, 1.0, 1.0), 7.0)
    mat_bolt_halo = make_emissive("BoltHaloMat", (0.08, 0.65, 1.0, 1.0), 2.2)
    mat_bolt_ring = make_emissive("BoltRingMat", (0.18, 0.85, 1.0, 1.0), 2.7)

    mat_evan_wave = make_emissive("EvanWaveMat", (1.0, 0.12, 0.48, 1.0), 3.8)
    mat_hellfire_outer = make_hellfire_mat("HellfireOuterMat", core=False)
    mat_hellfire_core = make_hellfire_mat("HellfireCoreMat", core=True)
    mat_guitar_body = make_pbr(
        "EvanBoomerangBody",
        (0.90, 0.03, 0.04, 1.0),
        roughness=0.14,
        metallic=0.30,
        emit_color=(0.94, 0.06, 0.07, 1.0),
        emit_strength=1.2,
    )
    mat_guitar_neck = make_pbr("EvanBoomerangNeck", (0.14, 0.07, 0.05, 1.0), roughness=0.48, metallic=0.1)
    mat_guitar_chrome = make_pbr("EvanBoomerangChrome", (0.82, 0.85, 0.90, 1.0), roughness=0.18, metallic=0.92)
    mat_guitar_cream = make_pbr("EvanBoomerangCream", (0.96, 0.94, 0.86, 1.0), roughness=0.34, metallic=0.05)
    mat_guitar_slash = make_emissive("EvanGuitarSlashMat", (1.0, 0.16, 0.34, 1.0), 4.6)

    mat_portal_void = make_emissive("HellPortalVoidMat", (0.0, 0.0, 0.0, 1.0), 0.0)
    mat_portal_lava = make_emissive("HellPortalLavaMat", (1.0, 0.24, 0.02, 1.0), 7.0)
    mat_demon_flesh = make_demon_flesh_mat("DemonHandFleshMat")
    mat_demon_talon = make_pbr(
        "DemonHandTalonMat",
        (0.03, 0.008, 0.012, 1.0),
        roughness=0.14,
        metallic=0.36,
        emit_color=(0.45, 0.02, 0.04, 1.0),
        emit_strength=0.45,
    )
    mat_demon_cuticle = make_emissive("DemonHandCuticleMat", (1.0, 0.08, 0.14, 1.0), 4.2)

    mat_lea_beam = make_emissive("LeaBeamMat", (1.0, 0.80, 0.22, 1.0), 4.8)
    mat_lea_boom = make_emissive("LeaBoomMat", (0.96, 0.28, 0.88, 1.0), 3.6)
    mat_pink_flash = make_emissive("PinkSupernovaMat", (1.0, 0.02, 0.56, 1.0), 5.2)
    mat_pink_pillar = make_emissive("PinkPillarMat", (1.0, 0.05, 0.64, 1.0), 3.8)
    mat_solar_core = make_emissive("SolarCoreMat", (1.0, 0.96, 0.80, 1.0), 11.0)
    mat_solar_ray = make_emissive("SolarRayMat", (1.0, 0.68, 0.16, 1.0), 7.5)
    mat_pink_ring = make_emissive("FinalePinkRingMat", (1.0, 0.18, 0.76, 1.0), 4.6)
    mat_gold_ring = make_emissive("FinaleGoldRingMat", (1.0, 0.74, 0.18, 1.0), 4.8)

    # Machined Hero Stage
    stage_root = bpy.data.objects.new("HeroStageRoot", None)
    scene.collection.objects.link(stage_root)
    stage_mat = make_pbr("HeroStageMat", (0.055, 0.072, 0.102, 1.0), roughness=0.32, metallic=0.48)
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=2.28, depth=0.10, location=(0.0, 0.0, -0.045))
    stage_disk = bpy.context.active_object
    stage_disk.name = "HeroStageDisk"
    stage_disk.data.materials.append(stage_mat)
    stage_disk.parent = stage_root
    stage_disk.modifiers.new("Rounded machined edge", "BEVEL").width = 0.055
    stage_disk.modifiers[-1].segments = 3
    stage_disk.modifiers.new("Clean highlight normals", "WEIGHTED_NORMAL")

    bpy.ops.mesh.primitive_torus_add(major_radius=2.08, minor_radius=0.018, location=(0.0, 0.0, 0.016))
    stage_rim = bpy.context.active_object
    stage_rim.name = "HeroStageRim"
    stage_rim.parent = stage_root
    stage_rim.data.materials.append(mat_bolt_ring)

    bpy.ops.mesh.primitive_torus_add(major_radius=1.08, minor_radius=0.010, location=(0.0, 1.82, 1.56))
    stage_halo = bpy.context.active_object
    stage_halo.name = "HeroStageHalo"
    stage_halo.rotation_euler = (math.radians(90), 0.0, 0.0)
    stage_halo.parent = stage_root
    stage_halo.data.materials.append(mat_bolt_ring)

    # Indexed by act: 0=Quad, 1=BIG-BEN, 2=Nardus, 3=Evan, 4=Lea
    stage_accents = (
        make_emissive("StageAccentCyan", (0.12, 0.82, 1.0, 1.0), 1.6),
        make_emissive("StageAccentGreen", (0.48, 1.0, 0.30, 1.0), 1.6),
        make_emissive("StageAccentPink", (1.0, 0.16, 0.54, 1.0), 1.6),
        make_emissive("StageAccentMagenta", (1.0, 0.18, 0.46, 1.0), 1.6),
        make_emissive("StageAccentGold", (1.0, 0.68, 0.14, 1.0), 1.6),
    )
    stage_rim.data.materials[0] = stage_accents[0]
    stage_halo.data.materials[0] = stage_accents[0]

    # Cash Bag Materials (BIG-BEN F1)
    mat_burlap = make_pbr("CashBurlapMat", (0.76, 0.60, 0.36, 1.0), roughness=0.72, metallic=0.05, emit_color=(0.76, 0.60, 0.36, 1.0), emit_strength=0.28)
    mat_rope = make_pbr("CashRopeMat", (0.90, 0.68, 0.16, 1.0), roughness=0.35, metallic=0.45, emit_color=(1.0, 0.78, 0.18, 1.0), emit_strength=0.8)
    mat_dollar_sign = make_pbr("CashDollarSignMat", (0.03, 0.42, 0.12, 1.0), roughness=0.25, metallic=0.35, emit_color=(0.06, 0.72, 0.22, 1.0), emit_strength=1.15)
    mat_dollar_bill = make_pbr("DollarBillMat", (0.12, 0.76, 0.26, 1.0), roughness=0.35, metallic=0.1, emit_color=(0.14, 0.85, 0.28, 1.0), emit_strength=2.1)
    mat_gold_coin = make_emissive("GoldCoinMat", (1.0, 0.82, 0.14, 1.0), 4.5)
    mat_cash_trail = make_emissive("CashTrailMat", (0.18, 0.92, 0.38, 1.0), 7.5)
    mat_cash_ring = make_emissive("CashRingMat", (0.22, 0.92, 0.38, 1.0), 4.5)

    def make_poly_curve(name: str, pts: list[tuple[float, float, float]], bevel_depth: float, mat, parent=None):
        cd = bpy.data.curves.new(name=name + "_curve", type="CURVE")
        cd.dimensions = "3D"
        cd.bevel_depth = bevel_depth
        cd.bevel_resolution = 3
        cd.use_fill_caps = True
        sp = cd.splines.new("POLY")
        sp.points.add(len(pts) - 1)
        for idx, (px, py, pz) in enumerate(pts):
            sp.points[idx].co = (px, py, pz, 1.0)
        ob = bpy.data.objects.new(name, cd)
        ob.data.materials.append(mat)
        scene.collection.objects.link(ob)
        if parent is not None:
            ob.parent = parent
        return ob

    def build_lightning_assembly(prefix: str):
        root = bpy.data.objects.new(f"{prefix}_Root", None)
        scene.collection.objects.link(root)
        main_pts = [
            (0.0, 0.0, 14.5), (0.55, -0.25, 12.6), (-0.65, 0.30, 10.8),
            (0.75, -0.20, 9.1), (-0.50, -0.35, 7.4), (0.85, 0.25, 5.8),
            (-0.70, 0.15, 4.2), (0.55, -0.25, 2.7), (-0.40, 0.10, 1.3), (0.0, 0.0, 0.0),
        ]
        make_poly_curve(f"{prefix}_Core", main_pts, 0.085, mat_bolt_core, parent=root)
        make_poly_curve(f"{prefix}_Halo", main_pts, 0.18, mat_bolt_halo, parent=root)
        branches = [
            [(-0.65, 0.30, 10.8), (-1.65, 0.55, 9.4), (-2.45, 0.25, 8.1), (-3.10, 0.60, 6.9)],
            [(0.75, -0.20, 9.1), (1.80, -0.45, 7.7), (2.55, -0.10, 6.3), (3.25, -0.40, 4.9)],
            [(0.85, 0.25, 5.8), (1.75, 0.60, 4.5), (2.40, 0.25, 3.2), (2.95, 0.50, 1.9)],
            [(-0.70, 0.15, 4.2), (-1.55, -0.30, 2.9), (-2.30, 0.15, 1.6), (-2.75, -0.20, 0.4)],
        ]
        for b_idx, b_pts in enumerate(branches):
            make_poly_curve(f"{prefix}_Branch_{b_idx}", b_pts, 0.048, mat_bolt_core, parent=root)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.45, location=(0.0, 0.0, 0.25))
        orb = bpy.context.active_object
        orb.name = f"{prefix}_ImpactOrb"
        orb.data.materials.append(mat_bolt_core)
        orb.parent = root
        set_smooth(orb)
        rings = []
        for r_idx in range(2):
            bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.025, location=(0.0, 0.0, -50.0))
            ring = bpy.context.active_object
            ring.name = f"{prefix}_Ring_{r_idx}"
            ring.data.materials.append(mat_bolt_ring)
            set_smooth(ring)
            rings.append(ring)
        return {"root": root, "orb": orb, "rings": rings}

    lightning_1 = build_lightning_assembly("Lightning1")
    lightning_2 = build_lightning_assembly("Lightning2")

    def build_cash_bag(name: str, scale_mult: float = 1.0):
        root = bpy.data.objects.new(name, None)
        scene.collection.objects.link(root)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=14, radius=0.46, location=(0.0, 0.0, 0.42))
        body = bpy.context.active_object
        body.name = f"{name}_Body"
        body.scale = (1.06, 0.86, 1.02)
        body.data.materials.append(mat_burlap)
        body.parent = root
        set_smooth(body)

        bpy.ops.mesh.primitive_torus_add(major_radius=0.25, minor_radius=0.055, location=(0.0, 0.0, 0.78))
        collar = bpy.context.active_object
        collar.name = f"{name}_Collar"
        collar.scale = (1.02, 0.88, 1.0)
        collar.data.materials.append(mat_rope)
        collar.parent = root
        set_smooth(collar)

        bpy.ops.mesh.primitive_cone_add(vertices=14, radius1=0.20, radius2=0.38, depth=0.28, location=(0.0, 0.0, 0.93))
        crown = bpy.context.active_object
        crown.name = f"{name}_Crown"
        crown.scale = (1.0, 0.86, 1.0)
        crown.data.materials.append(mat_burlap)
        crown.parent = root
        set_smooth(crown)

        for b_idx, (bx, by, rz, rx) in enumerate([
            (-0.11, 0.02, 18.0, -14.0), (-0.03, -0.03, 6.0, 12.0),
            (0.05, 0.03, -8.0, -10.0), (0.12, -0.02, -22.0, 15.0),
        ]):
            bpy.ops.mesh.primitive_cube_add(size=0.22, location=(bx, by, 1.07))
            bill = bpy.context.active_object
            bill.name = f"{name}_TopBill_{b_idx}"
            bill.scale = (0.72, 0.14, 0.95)
            bill.rotation_euler = (math.radians(rx), math.radians(rz), math.radians(rz))
            bill.data.materials.append(mat_dollar_bill)
            bill.parent = root

        for side_tag, y_pos, rot_z in (("Front", -0.41, 0.0), ("Back", 0.41, math.pi)):
            bpy.ops.object.text_add(location=(0.0, y_pos, 0.42))
            txt = bpy.context.active_object
            txt.name = f"{name}_Dollar_{side_tag}"
            txt.data.body = "$"
            txt.data.align_x = "CENTER"
            txt.data.align_y = "CENTER"
            txt.data.size = 0.56
            txt.data.extrude = 0.055
            txt.data.bevel_depth = 0.014
            if loaded_font:
                txt.data.font = loaded_font
            txt.rotation_euler = (math.radians(90), 0.0, rot_z)
            txt.data.materials.append(mat_dollar_sign)
            txt.parent = root

        root.scale = (scale_mult, scale_mult, scale_mult)
        return root

    def build_crescent_banana(name: str):
        pts = [(-0.28, 0.0, -0.14), (-0.15, 0.0, 0.05), (0.0, 0.0, 0.12), (0.15, 0.0, 0.05), (0.28, 0.0, -0.14)]
        return make_poly_curve(name, pts, 0.095, mat_banana)

    def spawn_pool(name_prefix: str, count: int, kind: str, mat):
        items = []
        for i in range(count):
            if kind == "sphere":
                bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=(0, 0, -50))
            elif kind == "torus":
                bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.025, location=(0, 0, -50))
            elif kind == "cyl":
                bpy.ops.mesh.primitive_cylinder_add(radius=0.055, depth=1.25, location=(0, 0, -50))
            elif kind == "coin":
                bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.19, depth=0.045, location=(0, 0, -50))
            else:
                bpy.ops.mesh.primitive_cube_add(size=0.42, location=(0, 0, -50))
            o = bpy.context.active_object
            o.name = f"{name_prefix}_{i}"
            o.data.materials.append(mat)
            if kind in ("sphere", "torus", "cyl", "coin"):
                set_smooth(o)
            items.append(o)
        return items

    tracers = spawn_pool("Tracer", 8, "cyl", mat_tracer)
    bananas = [build_crescent_banana(f"Banana_{i}") for i in range(7)]
    cash_rockets = [build_cash_bag(f"CashRocket_{i}", 0.58) for i in range(4)]
    cash_trails = spawn_pool("CashTrail", 4, "cyl", mat_cash_trail)
    giant_cash_bag_1 = build_cash_bag("GiantCashBag_1", 2.45)
    giant_cash_bag_2 = build_cash_bag("GiantCashBag_2", 2.15)
    dollar_bills = spawn_pool("DollarBill", 36, "cube", mat_dollar_bill)
    for b in dollar_bills:
        b.scale = (1.15, 0.52, 0.04)
    gold_coins = spawn_pool("GoldCoin", 16, "coin", mat_gold_coin)
    cash_rings = spawn_pool("CashRing", 2, "torus", mat_cash_ring)
    bg_meteors = spawn_pool("BgMeteor", 4, "sphere", mat_meteor_rock)
    evan_waves = spawn_pool("EvanWave", 3, "torus", mat_evan_wave)
    lea_boom_ring = spawn_pool("LeaBoomRing", 1, "torus", mat_lea_boom)
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.045, depth=1.0, location=(0.0, 0.0, -50.0))
    lea_beam = bpy.context.active_object
    lea_beam.name = "LeaHornBeam"
    lea_beam.data.materials.append(mat_lea_beam)
    set_smooth(lea_beam)

    # -----------------------------------------------------------------------
    # Hero Craggy Flaming Meteor (Act 3 - Nardus)
    # -----------------------------------------------------------------------
    hero_meteor_root = bpy.data.objects.new("HeroMeteorRoot", None)
    scene.collection.objects.link(hero_meteor_root)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=0.52, location=(0.0, 0.0, 0.0))
    meteor_rock = bpy.context.active_object
    meteor_rock.name = "HeroMeteorRock"
    for v in meteor_rock.data.vertices:
        disp = 1.0 + 0.19 * math.sin(v.co.x * 8.1 + v.co.y * 5.7) + 0.13 * math.cos(v.co.z * 9.3 - v.co.x * 4.1)
        v.co *= disp
    meteor_rock.data.materials.append(mat_meteor_rock)
    meteor_rock.parent = hero_meteor_root
    set_smooth(meteor_rock)

    bpy.ops.mesh.primitive_cone_add(vertices=20, radius1=0.62, radius2=0.04, depth=2.7, location=(0.0, 0.0, 1.25))
    meteor_tail = bpy.context.active_object
    meteor_tail.name = "HeroMeteorTail"
    meteor_tail.data.materials.append(mat_meteor_tail)
    meteor_tail.parent = hero_meteor_root
    set_smooth(meteor_tail)

    bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=0.34, radius2=0.02, depth=1.8, location=(0.0, 0.0, 0.78))
    meteor_core_cone = bpy.context.active_object
    meteor_core_cone.name = "HeroMeteorCoreTail"
    meteor_core_cone.data.materials.append(mat_meteor_core)
    meteor_core_cone.parent = hero_meteor_root
    set_smooth(meteor_core_cone)

    meteor_embers = spawn_pool("MeteorEmber", 8, "sphere", mat_meteor_core)

    # -----------------------------------------------------------------------
    # Sculpted Mushroom Cloud / Nuke Assembly (Act 3 - Nardus)
    # -----------------------------------------------------------------------
    nuke_root = bpy.data.objects.new("NukeRoot", None)
    scene.collection.objects.link(nuke_root)

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=0.65, location=(0.0, 0.0, 0.55))
    nuke_core_orb = bpy.context.active_object
    nuke_core_orb.name = "NukeCoreOrb"
    nuke_core_orb.data.materials.append(mat_nuke_core)
    nuke_core_orb.parent = nuke_root
    set_smooth(nuke_core_orb)

    # Waisted mushroom stem (flared skirt base -> narrow waist -> flared cap throat)
    stem_mesh = bpy.data.meshes.new("NukeStemMesh")
    bm = bmesh.new()
    rings = 16
    segs = 24
    ring_verts = []
    for iz in range(rings + 1):
        u = iz / rings
        z = u * 2.20
        r = 0.72 * math.exp(-u * 5.2) + 0.30 + 0.32 * (u ** 2.8)
        row = []
        for j in range(segs):
            ang = 2.0 * math.pi * j / segs
            wob = 1.0 + 0.08 * math.sin(ang * 5.0 + u * 7.0) + 0.05 * math.cos(ang * 3.0 - u * 4.0)
            row.append(bm.verts.new((math.cos(ang) * r * wob, math.sin(ang) * r * wob, z)))
        ring_verts.append(row)
    for iz in range(rings):
        for j in range(segs):
            jn = (j + 1) % segs
            bm.faces.new((ring_verts[iz][j], ring_verts[iz][jn], ring_verts[iz + 1][jn], ring_verts[iz + 1][j]))
    bm.to_mesh(stem_mesh)
    bm.free()
    nuke_stem = bpy.data.objects.new("NukeStem", stem_mesh)
    nuke_stem.data.materials.append(mat_nuke_fireball)
    scene.collection.objects.link(nuke_stem)
    nuke_stem.parent = nuke_root
    set_smooth(nuke_stem)

    # Base surge skirt lobes around the stem foot
    nuke_base_lobes = []
    for i in range(10):
        ang = 2.0 * math.pi * i / 10.0
        bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=2,
            radius=0.40 + 0.08 * (i % 2),
            location=(0.62 * math.cos(ang), 0.62 * math.sin(ang), 0.22),
        )
        lobe = bpy.context.active_object
        lobe.name = f"NukeBaseLobe_{i}"
        lobe.scale = (1.15, 1.15, 0.65)
        lobe.data.materials.append(mat_nuke_fireball)
        lobe.parent = nuke_root
        set_smooth(lobe)
        nuke_base_lobes.append(lobe)

    # Wilson condensation collar on mid-upper stem
    bpy.ops.mesh.primitive_torus_add(major_radius=0.68, minor_radius=0.075, location=(0.0, 0.0, 1.48))
    nuke_wilson = bpy.context.active_object
    nuke_wilson.name = "NukeWilsonRing"
    nuke_wilson.scale = (1.0, 1.0, 0.45)
    nuke_wilson.data.materials.append(mat_nuke_wilson)
    nuke_wilson.parent = nuke_root
    set_smooth(nuke_wilson)

    # Mushroom Cap dome + cauliflower lobes
    nuke_cap_root = bpy.data.objects.new("NukeCapRoot", None)
    scene.collection.objects.link(nuke_cap_root)
    nuke_cap_root.parent = nuke_root

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.05, location=(0.0, 0.0, 0.18))
    nuke_cap_dome = bpy.context.active_object
    nuke_cap_dome.name = "NukeCapDome"
    for v in nuke_cap_dome.data.vertices:
        wob = 1.0 + 0.12 * math.sin(v.co.x * 4.5 + v.co.y * 3.9) * math.cos(v.co.z * 5.2)
        v.co.x *= wob
        v.co.y *= wob
        v.co.z *= 0.62 * wob
    nuke_cap_dome.data.materials.append(mat_nuke_cap_smoke)
    nuke_cap_dome.parent = nuke_cap_root
    set_smooth(nuke_cap_dome)

    for i in range(12):
        ang = 2.0 * math.pi * i / 12.0
        bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=2,
            radius=0.46 + 0.09 * (i % 3),
            location=(0.82 * math.cos(ang), 0.82 * math.sin(ang), -0.02 + 0.08 * math.sin(i * 1.7)),
        )
        rim = bpy.context.active_object
        rim.name = f"NukeCapRimLobe_{i}"
        rim.scale = (1.05, 1.05, 0.82)
        rim.data.materials.append(mat_nuke_cap_smoke if i % 2 == 0 else mat_nuke_fireball)
        rim.parent = nuke_cap_root
        set_smooth(rim)

    for i in range(6):
        ang = 2.0 * math.pi * i / 6.0 + 0.25
        bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=2,
            radius=0.42,
            location=(0.45 * math.cos(ang), 0.45 * math.sin(ang), -0.18),
        )
        inner = bpy.context.active_object
        inner.name = f"NukeCapFireLobe_{i}"
        inner.data.materials.append(mat_nuke_fireball)
        inner.parent = nuke_cap_root
        set_smooth(inner)

    bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.032, location=(0, 24, -50))
    shock_ring = bpy.context.active_object
    shock_ring.name = "ShockRing"
    shock_ring.data.materials.append(mat_shock)
    set_smooth(shock_ring)

    bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.022, location=(0, 24, -50))
    shock_ring_2 = bpy.context.active_object
    shock_ring_2.name = "ShockRing2"
    shock_ring_2.data.materials.append(mat_shock)
    set_smooth(shock_ring_2)

    # -----------------------------------------------------------------------
    # Hell-Portal + MUCH BIGGER Articulated 3-Joint Demon Hand (Act 4 - Evan)
    # -----------------------------------------------------------------------
    portal_root = bpy.data.objects.new("HellPortalRoot", None)
    scene.collection.objects.link(portal_root)

    bpy.ops.mesh.primitive_cylinder_add(vertices=36, radius=1.62, depth=0.02, location=(0.0, 0.0, 0.018))
    portal_void = bpy.context.active_object
    portal_void.name = "HellPortalVoid"
    portal_void.data.materials.append(mat_portal_void)
    portal_void.parent = portal_root

    bpy.ops.mesh.primitive_torus_add(major_radius=1.68, minor_radius=0.075, location=(0.0, 0.0, 0.026))
    portal_ring = bpy.context.active_object
    portal_ring.name = "HellPortalLavaRing"
    portal_ring.scale = (1.0, 1.0, 0.35)
    portal_ring.data.materials.append(mat_portal_lava)
    portal_ring.parent = portal_root
    set_smooth(portal_ring)

    for i in range(8):
        ang = 2.0 * math.pi * i / 8.0 + 0.18
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(1.88 * math.cos(ang), 1.88 * math.sin(ang), 0.022))
        crack = bpy.context.active_object
        crack.name = f"HellPortalCrack_{i}"
        crack.scale = (0.55, 0.055, 0.014)
        crack.rotation_euler = (0.0, 0.0, ang)
        crack.data.materials.append(mat_portal_lava)
        crack.parent = portal_root

    def build_curved_talon(name: str, length: float, base_r: float):
        mesh = bpy.data.meshes.new(name + "_Mesh")
        bm = bmesh.new()
        rings = 7
        segs = 10
        ring_v = []
        for i in range(rings + 1):
            u = i / rings
            r = base_r * ((1.0 - 0.88 * u) ** 1.15)
            z = u * length
            y = -0.32 * length * (u ** 2.1)  # hooks forward (-Y toward Evan)
            row = []
            for j in range(segs):
                ang = 2.0 * math.pi * j / segs
                row.append(bm.verts.new((math.cos(ang) * r, y + math.sin(ang) * r * 0.85, z)))
            ring_v.append(row)
        for i in range(rings):
            for j in range(segs):
                jn = (j + 1) % segs
                bm.faces.new((ring_v[i][j], ring_v[i][jn], ring_v[i + 1][jn], ring_v[i + 1][j]))
        bm.faces.new(ring_v[-1])
        bm.to_mesh(mesh)
        bm.free()
        ob = bpy.data.objects.new(name, mesh)
        ob.data.materials.append(mat_demon_talon)
        scene.collection.objects.link(ob)
        set_smooth(ob)
        return ob

    demon_root = bpy.data.objects.new("EvanDemonHandRoot", None)
    scene.collection.objects.link(demon_root)

    # Tapered muscular forearm + spiked wrist cuff
    bpy.ops.mesh.primitive_cone_add(vertices=20, radius1=0.48, radius2=0.36, depth=1.95, location=(0.0, 0.0, 0.96))
    demon_forearm = bpy.context.active_object
    demon_forearm.name = "DemonHand_Forearm"
    demon_forearm.scale = (1.08, 0.72, 1.0)
    demon_forearm.data.materials.append(mat_demon_flesh)
    demon_forearm.parent = demon_root
    set_smooth(demon_forearm)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.44, minor_radius=0.065, location=(0.0, 0.0, 1.82))
    demon_cuff = bpy.context.active_object
    demon_cuff.name = "DemonHand_WristCuff"
    demon_cuff.scale = (1.06, 0.72, 0.8)
    demon_cuff.data.materials.append(mat_demon_talon)
    demon_cuff.parent = demon_root
    set_smooth(demon_cuff)

    # Organic sculpted Palm
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=0.62, location=(0.0, -0.02, 2.38))
    demon_palm = bpy.context.active_object
    demon_palm.name = "DemonHand_Palm"
    demon_palm.scale = (1.12, 0.44, 0.88)
    demon_palm.data.materials.append(mat_demon_flesh)
    demon_palm.parent = demon_root
    set_smooth(demon_palm)

    # Articulated 3-phalanx finger chains (Palm -> Knuckle -> Proximal -> MidJoint -> Middle -> DistalJoint -> Distal -> CurvedTalon)
    demon_finger_specs = [
        (-0.48, 2.80, 14.0, 0.36, 0.26, 0.22, 0.095),   # Index / Outer L
        (-0.16, 2.86, 4.5, 0.42, 0.30, 0.24, 0.102),    # Middle L
        (0.16, 2.86, -4.5, 0.40, 0.29, 0.24, 0.100),    # Ring
        (0.46, 2.78, -14.0, 0.33, 0.24, 0.20, 0.088),   # Pinky
    ]
    demon_finger_joints = []
    for idx, (kx, kz, splay_deg, l1, l2, l3, rad) in enumerate(demon_finger_specs):
        knuckle = bpy.data.objects.new(f"DemonHand_Knuckle_{idx}", None)
        knuckle.rotation_mode = "XYZ"
        knuckle.location = (kx, -0.02, kz)
        knuckle.rotation_euler = (0.0, math.radians(-splay_deg), 0.0)
        scene.collection.objects.link(knuckle)
        knuckle.parent = demon_root

        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=rad * 1.25, location=(0.0, 0.0, 0.0))
        kn_orb = bpy.context.active_object
        kn_orb.name = f"DemonHand_KnuckleOrb_{idx}"
        kn_orb.data.materials.append(mat_demon_flesh)
        kn_orb.parent = knuckle
        set_smooth(kn_orb)

        bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=rad, depth=l1, location=(0.0, 0.0, l1 * 0.5))
        prox = bpy.context.active_object
        prox.name = f"DemonHand_Proximal_{idx}"
        prox.data.materials.append(mat_demon_flesh)
        prox.parent = knuckle
        set_smooth(prox)

        mid_joint = bpy.data.objects.new(f"DemonHand_MidJoint_{idx}", None)
        mid_joint.rotation_mode = "XYZ"
        mid_joint.location = (0.0, 0.0, l1)
        scene.collection.objects.link(mid_joint)
        mid_joint.parent = knuckle

        bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=rad * 0.88, depth=l2, location=(0.0, 0.0, l2 * 0.5))
        mid_seg = bpy.context.active_object
        mid_seg.name = f"DemonHand_Middle_{idx}"
        mid_seg.data.materials.append(mat_demon_flesh)
        mid_seg.parent = mid_joint
        set_smooth(mid_seg)

        dist_joint = bpy.data.objects.new(f"DemonHand_DistalJoint_{idx}", None)
        dist_joint.rotation_mode = "XYZ"
        dist_joint.location = (0.0, 0.0, l2)
        scene.collection.objects.link(dist_joint)
        dist_joint.parent = mid_joint

        bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=rad * 0.76, depth=l3, location=(0.0, 0.0, l3 * 0.5))
        dist_seg = bpy.context.active_object
        dist_seg.name = f"DemonHand_Distal_{idx}"
        dist_seg.data.materials.append(mat_demon_flesh)
        dist_seg.parent = dist_joint
        set_smooth(dist_seg)

        bpy.ops.mesh.primitive_torus_add(major_radius=rad * 0.78, minor_radius=0.018, location=(0.0, 0.0, l3 * 0.86))
        cuticle = bpy.context.active_object
        cuticle.name = f"DemonHand_Cuticle_{idx}"
        cuticle.data.materials.append(mat_demon_cuticle)
        cuticle.parent = dist_joint
        set_smooth(cuticle)

        talon = build_curved_talon(f"DemonHand_Talon_{idx}", length=0.34, base_r=rad * 0.74)
        talon.location = (0.0, 0.0, l3 * 0.85)
        talon.parent = dist_joint

        demon_finger_joints.append((knuckle, mid_joint, dist_joint, splay_deg))

    # Opposable articulated Thumb (2-phalanx + curved talon, on viewer-right +X wrapping forward/inward)
    thumb_base = bpy.data.objects.new("DemonHand_ThumbBase", None)
    thumb_base.rotation_mode = "XYZ"
    thumb_base.location = (0.58, -0.06, 2.26)
    scene.collection.objects.link(thumb_base)
    thumb_base.parent = demon_root

    bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=0.11, depth=0.38, location=(0.0, 0.0, 0.19))
    th_p1 = bpy.context.active_object
    th_p1.name = "DemonHand_ThumbProx"
    th_p1.data.materials.append(mat_demon_flesh)
    th_p1.parent = thumb_base
    set_smooth(th_p1)

    thumb_dist = bpy.data.objects.new("DemonHand_ThumbDistal", None)
    thumb_dist.rotation_mode = "XYZ"
    thumb_dist.location = (0.0, 0.0, 0.38)
    scene.collection.objects.link(thumb_dist)
    thumb_dist.parent = thumb_base

    bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=0.09, depth=0.26, location=(0.0, 0.0, 0.13))
    th_p2 = bpy.context.active_object
    th_p2.name = "DemonHand_ThumbDistMesh"
    th_p2.data.materials.append(mat_demon_flesh)
    th_p2.parent = thumb_dist
    set_smooth(th_p2)

    th_talon = build_curved_talon("DemonHand_ThumbTalon", length=0.30, base_r=0.082)
    th_talon.location = (0.0, 0.0, 0.22)
    th_talon.rotation_euler = (0.0, 0.0, math.radians(-90.0))
    th_talon.parent = thumb_dist

    # -----------------------------------------------------------------------
    # Detailed Double-Cutaway Boomerang Guitar Projectile (Act 4 - Evan)
    # -----------------------------------------------------------------------
    guitar_projectile_root = bpy.data.objects.new("EvanBoomerangGuitarRoot", None)
    scene.collection.objects.link(guitar_projectile_root)

    # 21-point double-cutaway silhouette in XY plane (body centered ~0, neck along +Y)
    g_outline = [
        (-0.165, -0.175), (-0.095, -0.225), (0.000, -0.235),
        (0.085, -0.205), (0.145, -0.145), (0.175, -0.070),
        (0.145, -0.010), (0.090, 0.035), (0.135, 0.085),
        (0.155, 0.140), (0.115, 0.160), (0.055, 0.115),
        (0.028, 0.085), (-0.028, 0.085), (-0.055, 0.155),
        (-0.110, 0.215), (-0.165, 0.195), (-0.185, 0.125),
        (-0.145, 0.045), (-0.165, -0.030), (-0.190, -0.105),
    ]
    g_mesh = bpy.data.meshes.new("BoomerangGuitarBodyMesh")
    gbm = bmesh.new()
    top_vs = [gbm.verts.new((x * 1.15, y * 1.15, 0.028)) for x, y in g_outline]
    bot_vs = [gbm.verts.new((x * 1.15, y * 1.15, -0.028)) for x, y in g_outline]
    gbm.faces.new(top_vs)
    gbm.faces.new(list(reversed(bot_vs)))
    ng_pts = len(g_outline)
    for i in range(ng_pts):
        inext = (i + 1) % ng_pts
        gbm.faces.new((bot_vs[i], bot_vs[inext], top_vs[inext], top_vs[i]))
    gbm.to_mesh(g_mesh)
    gbm.free()
    guitar_body = bpy.data.objects.new("EvanBoomerangGuitarBody", g_mesh)
    guitar_body.data.materials.append(mat_guitar_body)
    scene.collection.objects.link(guitar_body)
    guitar_body.parent = guitar_projectile_root

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.30, 0.008))
    g_neck = bpy.context.active_object
    g_neck.name = "EvanBoomerangNeck"
    g_neck.scale = (0.062, 0.42, 0.028)
    g_neck.data.materials.append(mat_guitar_neck)
    g_neck.parent = guitar_projectile_root

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.56, 0.010))
    g_head = bpy.context.active_object
    g_head.name = "EvanBoomerangHead"
    g_head.scale = (0.088, 0.13, 0.026)
    g_head.rotation_euler = (0.0, 0.0, math.radians(-10.0))
    g_head.data.materials.append(mat_guitar_body)
    g_head.parent = guitar_projectile_root

    for py, mat_p, sx, sy in (
        (-0.08, mat_guitar_chrome, 0.11, 0.025),
        (-0.01, mat_guitar_cream, 0.105, 0.036),
        (0.055, mat_guitar_cream, 0.105, 0.036),
    ):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, py, 0.034))
        pk = bpy.context.active_object
        pk.name = f"EvanBoomerangPart_{py:.2f}"
        pk.scale = (sx, sy, 0.016)
        pk.data.materials.append(mat_p)
        pk.parent = guitar_projectile_root

    for i in range(6):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.13 + i * 0.058, 0.024))
        fr = bpy.context.active_object
        fr.name = f"EvanBoomerangFret_{i}"
        fr.scale = (0.058, 0.006, 0.006)
        fr.data.materials.append(mat_guitar_chrome)
        fr.parent = guitar_projectile_root

    bpy.ops.mesh.primitive_torus_add(major_radius=0.58, minor_radius=0.018, location=(0.0, 0.12, 0.0))
    g_slash = bpy.context.active_object
    g_slash.name = "EvanBoomerangSlashRing"
    g_slash.data.materials.append(mat_guitar_slash)
    g_slash.parent = guitar_projectile_root
    set_smooth(g_slash)
    guitar_projectile_root.location = (0.0, 0.0, -80.0)

    # -----------------------------------------------------------------------
    # Roaring Engulfing Hellfire Tongues & Embers (Act 4 - Evan)
    # -----------------------------------------------------------------------
    def build_flame_tongue(name: str, height: float, radius: float, twist: float, mat):
        mesh = bpy.data.meshes.new(name + "_Mesh")
        bm = bmesh.new()
        rings = 9
        segs = 10
        ring_v = []
        for iz in range(rings + 1):
            u = iz / rings
            z = u * height
            taper = max(0.03, (1.0 - u) ** 0.85) * (1.0 + 0.25 * math.sin(u * math.pi))
            r = radius * taper
            ox = math.sin(u * math.pi * 2.2 + twist) * radius * 0.65 * u
            oy = math.cos(u * math.pi * 1.8 + twist) * radius * 0.45 * u
            row = []
            for j in range(segs):
                ang = 2.0 * math.pi * j / segs + u * 1.4 * (1 if twist >= 0 else -1)
                row.append(bm.verts.new((ox + math.cos(ang) * r, oy + math.sin(ang) * r * 0.72, z)))
            ring_v.append(row)
        for iz in range(rings):
            for j in range(segs):
                jn = (j + 1) % segs
                bm.faces.new((ring_v[iz][j], ring_v[iz][jn], ring_v[iz + 1][jn], ring_v[iz + 1][j]))
        bm.faces.new(ring_v[-1])
        bm.to_mesh(mesh)
        bm.free()
        ob = bpy.data.objects.new(name, mesh)
        ob.data.materials.append(mat)
        scene.collection.objects.link(ob)
        set_smooth(ob)
        return ob

    evan_flames_root = bpy.data.objects.new("EvanFlamesRoot", None)
    scene.collection.objects.link(evan_flames_root)
    evan_flame_objects = []
    # 16 outer flames + 12 inner core flames; slightly lower in front (-Y) so Evan stays visible inside the fire
    for i in range(16):
        ang = 2.0 * math.pi * i / 16.0
        rad = 0.80 + 0.18 * (i % 3)
        x = rad * math.cos(ang)
        y = rad * 0.72 * math.sin(ang)
        front_factor = 0.65 if y < -0.15 else 1.0
        h_flame = (1.35 + 0.42 * (i % 3)) * front_factor
        fl = build_flame_tongue(f"EvanFlameOuter_{i}", h_flame, 0.16, ang, mat_hellfire_outer)
        fl.location = (x, y, 0.0)
        fl.rotation_euler = (0.0, 0.0, ang)
        fl.parent = evan_flames_root
        evan_flame_objects.append((fl, h_flame, i, False))
    for i in range(12):
        ang = 2.0 * math.pi * i / 12.0 + 0.2
        rad = 0.56 + 0.14 * (i % 2)
        x = rad * math.cos(ang)
        y = rad * 0.68 * math.sin(ang)
        front_factor = 0.62 if y < -0.10 else 1.0
        h_flame = (1.05 + 0.30 * (i % 2)) * front_factor
        fl = build_flame_tongue(f"EvanFlameCore_{i}", h_flame, 0.11, -ang, mat_hellfire_core)
        fl.location = (x, y, 0.04)
        fl.rotation_euler = (0.0, 0.0, ang)
        fl.parent = evan_flames_root
        evan_flame_objects.append((fl, h_flame, i, True))
    hell_embers = spawn_pool("HellEmber", 18, "sphere", mat_hellfire_core)
    evan_flames_root.location = (0.0, 0.0, -80.0)

    # -----------------------------------------------------------------------
    # Lea Unicorn Big Pink Landing Flash Assembly (Act 5)
    # -----------------------------------------------------------------------
    pink_flash_root = bpy.data.objects.new("PinkFlashRoot", None)
    scene.collection.objects.link(pink_flash_root)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0, location=(0.0, 0.0, 0.4))
    pink_orb = bpy.context.active_object
    pink_orb.name = "PinkSupernovaOrb"
    pink_orb.data.materials.append(mat_pink_flash)
    pink_orb.parent = pink_flash_root
    set_smooth(pink_orb)

    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.65, depth=14.0, location=(0.0, 0.0, 7.0))
    pink_pillar = bpy.context.active_object
    pink_pillar.name = "PinkSkyPillar"
    pink_pillar.data.materials.append(mat_pink_pillar)
    pink_pillar.parent = pink_flash_root
    set_smooth(pink_pillar)

    pink_rings = spawn_pool("PinkShockRing", 3, "torus", mat_pink_ring)

    # -----------------------------------------------------------------------
    # 3D Finale Title `"Kiepie -QUAD"` + 3D Solar Flare Starburst + Finale Rings
    # -----------------------------------------------------------------------
    bpy.ops.object.text_add(location=(0.0, 4.0, -50.0))
    title_obj = bpy.context.active_object
    title_obj.name = "KiepieQuadTitle"
    title_obj.data.body = "Kiepie -QUAD"
    title_obj.data.align_x = "CENTER"
    title_obj.data.align_y = "CENTER"
    title_obj.data.extrude = 0.16
    title_obj.data.bevel_depth = 0.026
    title_obj.data.size = 1.32
    if loaded_font:
        title_obj.data.font = loaded_font
    title_obj.rotation_euler = (math.radians(90), 0.0, 0.0)
    title_mat = make_pbr(
        "TitleMat",
        (0.11, 0.16, 0.26, 1.0),
        roughness=0.14,
        metallic=0.94,
        emit_color=(0.75, 0.86, 1.0, 1.0),
        emit_strength=0.22,
    )
    title_obj.data.materials.append(title_mat)

    bpy.ops.object.text_add(location=(0.0, 0.0, -0.11))
    title_rim = bpy.context.active_object
    title_rim.name = "KiepieQuadTitleRim"
    title_rim.data.body = "Kiepie -QUAD"
    title_rim.data.align_x = "CENTER"
    title_rim.data.align_y = "CENTER"
    title_rim.data.extrude = 0.05
    title_rim.data.bevel_depth = 0.044
    title_rim.data.size = 1.32
    if loaded_font:
        title_rim.data.font = loaded_font
    title_rim.data.materials.append(make_emissive("TitleRimMat", (1.0, 0.44, 0.06, 1.0), 3.2))
    title_rim.parent = title_obj

    solar_flare_root = bpy.data.objects.new("SolarFlareRoot", None)
    scene.collection.objects.link(solar_flare_root)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=0.68, location=(0.0, 0.0, 0.0))
    solar_core = bpy.context.active_object
    solar_core.name = "SolarFlareCore"
    solar_core.data.materials.append(mat_solar_core)
    solar_core.parent = solar_flare_root
    set_smooth(solar_core)

    bpy.ops.mesh.primitive_torus_add(major_radius=1.22, minor_radius=0.04, location=(0.0, 0.0, 0.0))
    solar_halo = bpy.context.active_object
    solar_halo.name = "SolarCoronaHalo"
    solar_halo.rotation_euler = (math.radians(90), 0.0, 0.0)
    solar_halo.data.materials.append(mat_solar_ray)
    solar_halo.parent = solar_flare_root
    set_smooth(solar_halo)

    solar_ray_wheel = bpy.data.objects.new("SolarRayWheel", None)
    scene.collection.objects.link(solar_ray_wheel)
    solar_ray_wheel.parent = solar_flare_root
    for i in range(12):
        ang = 2.0 * math.pi * i / 12.0
        ray_len = 4.2 if i % 2 == 0 else 2.8
        bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=0.10 if i % 2 == 0 else 0.065, radius2=0.004, depth=ray_len, location=(0.0, 0.0, 0.0))
        ray = bpy.context.active_object
        ray.name = f"SolarRaySpike_{i}"
        ray.data.materials.append(mat_solar_ray)
        ray.rotation_euler = (0.0, math.radians(90), 0.0)
        pivot = bpy.data.objects.new(f"SolarRayPivot_{i}", None)
        pivot.rotation_euler = (0.0, ang, 0.0)
        scene.collection.objects.link(pivot)
        pivot.parent = solar_ray_wheel
        ray.location = (ray_len * 0.5, 0.0, 0.0)
        ray.parent = pivot
        set_smooth(ray)
    solar_flare_root.location = (0.0, 26.0, -80.0)

    finale_gold_ring = spawn_pool("FinaleGoldRing", 1, "torus", mat_gold_ring)[0]
    finale_pink_ring = spawn_pool("FinalePinkRing", 1, "torus", mat_pink_ring)[0]
    finale_sparks = spawn_pool("FinaleSpark", 16, "sphere", mat_solar_core)

    def hide_lightning(lt: dict):
        lt["root"].location = (0.0, 0.0, -80.0)
        for r in lt["rings"]:
            r.location = (0.0, 0.0, -80.0)

    def place_lightning(lt: dict, pos: tuple[float, float, float], progress: float, f: int, scale: float = 1.0):
        px, py, pz = pos
        lt["root"].location = (px, py, pz)
        flicker = 0.85 + 0.30 * abs(math.sin(f * 1.9))
        lt["root"].scale = (scale * flicker, scale * flicker, scale)
        lt["root"].rotation_euler = (0.0, 0.0, (f % 4) * 0.35)
        for r_idx, ring in enumerate(lt["rings"]):
            rp = max(0.0, min(1.0, progress * 1.35 - r_idx * 0.22))
            if rp > 0.01:
                ring.location = (px, py, pz + 0.06 + r_idx * 0.04)
                rs = (0.8 + 4.2 * rp) * scale
                ring.scale = (rs, rs, 0.25)
            else:
                ring.location = (0.0, 0.0, -80.0)

    def place_cash_explosion(center: tuple[float, float, float], progress: float, f: int, bill_count: int = 30):
        cx, cy, cz = center
        p = max(0.0, min(1.0, progress))
        for i in range(min(bill_count, len(dollar_bills))):
            ang = i * (2.0 * math.pi / 12.0) + (i // 12) * 0.55
            tier = (i % 3) + 1
            rad = (0.65 + 3.8 * (p ** 0.72)) * (0.55 + 0.22 * tier)
            lift = max(0.18, 0.5 + (3.6 * p - 2.4 * (p ** 2)) * (0.6 + 0.25 * (i % 4)) + 0.30 * math.sin(f * 0.3 + i))
            b = dollar_bills[i]
            b.location = (cx + math.cos(ang) * rad, cy + math.sin(ang) * rad, cz + lift)
            b.rotation_euler = (f * 0.28 + i * 0.7, f * 0.22 + i * 0.5, ang + f * 0.18)
        for i, coin in enumerate(gold_coins):
            ang = i * (2.0 * math.pi / len(gold_coins)) + 0.3
            rad = (0.5 + 3.2 * (p ** 0.75)) * (0.7 + 0.2 * (i % 2))
            lift = max(0.15, 0.4 + 2.8 * p * (1.0 - 0.65 * p) + 0.25 * (i % 3))
            coin.location = (cx + math.cos(ang) * rad, cy + math.sin(ang) * rad, cz + lift)
            coin.rotation_euler = (math.radians(65) + f * 0.35, f * 0.4, ang)
        for r_idx, ring in enumerate(cash_rings):
            rp = max(0.0, min(1.0, p * 1.3 - r_idx * 0.2))
            if rp > 0.01:
                ring.location = (cx, cy, cz + 0.06 + r_idx * 0.04)
                rs = 0.8 + 4.0 * rp
                ring.scale = (rs, rs, 0.25)

    def hide_all_vfx():
        for grp in (
            tracers, bananas, cash_rockets, cash_trails, dollar_bills, gold_coins,
            cash_rings, bg_meteors, meteor_embers, evan_waves, lea_boom_ring,
            hell_embers, pink_rings, finale_sparks,
        ):
            for o in grp:
                o.location = (0.0, 0.0, -50.0)
        lea_beam.location = (0.0, 0.0, -50.0)
        giant_cash_bag_1.location = (0.0, 0.0, -50.0)
        giant_cash_bag_2.location = (0.0, 0.0, -50.0)
        hero_meteor_root.location = (0.0, 0.0, -80.0)
        nuke_root.location = (0.0, 24.0, -80.0)
        portal_root.location = (0.0, 0.0, -80.0)
        demon_root.location = (0.0, 0.0, -80.0)
        guitar_projectile_root.location = (0.0, 0.0, -80.0)
        evan_flames_root.location = (0.0, 0.0, -80.0)
        pink_flash_root.location = (0.0, 0.0, -80.0)
        solar_flare_root.location = (0.0, 26.0, -80.0)
        finale_gold_ring.location = (0.0, 0.0, -80.0)
        finale_pink_ring.location = (0.0, 0.0, -80.0)
        hide_lightning(lightning_1)
        hide_lightning(lightning_2)
        shock_ring.location = (0.0, 24.0, -50.0)
        shock_ring_2.location = (0.0, 24.0, -50.0)
        title_obj.location = (0.0, 4.0, -50.0)
        flare_data.energy = 0.0
        flare_data.color = (1.0, 0.82, 0.42)

    def spin_wheels(wheels: list, f: int, rate: float = 0.48):
        for w in wheels:
            w.rotation_euler.x = -f * rate

    def play_rig_action(rig, action_name: str, phase: float) -> None:
        if rig is None or rig.animation_data is None:
            return
        anim = rig.animation_data
        anim.use_nla = True
        anim.action = None
        chosen = None
        for track in anim.nla_tracks:
            track.mute = track.name != action_name
            if track.name == action_name:
                chosen = track
        if chosen is None or not chosen.strips:
            return
        strip = chosen.strips[0]
        frame = strip.frame_start + max(0.0, min(1.0, phase)) * (strip.frame_end - strip.frame_start)
        scene.frame_set(int(round(frame)))

    def show_hero_stage(center, accent_index: int) -> None:
        accent = stage_accents[accent_index]
        stage_root.location = (center[0], center[1], 0.0)
        stage_root.scale = (0.72, 0.72, 0.72) if args.portrait else (1.0, 1.0, 1.0)
        stage_halo.hide_render = False
        stage_rim.data.materials[0] = accent
        stage_halo.data.materials[0] = accent

    def apply_frame(f: int) -> None:
        hide_all_vfx()
        cam_data.lens = 42.0
        for knuckle, mid_joint, dist_joint, splay_deg in demon_finger_joints:
            knuckle.rotation_euler = (0.0, math.radians(-splay_deg), 0.0)
            mid_joint.rotation_euler = (0.0, 0.0, 0.0)
            dist_joint.rotation_euler = (0.0, 0.0, 0.0)
        thumb_base.rotation_euler = (0.0, math.radians(-42.0), 0.0)
        thumb_dist.rotation_euler = (0.0, 0.0, 0.0)

        for part in evan_guitar_parts:
            part.hide_render = False
        quad_root.location = (0.0, 0.0, -50.0)
        nardus_root.location = (0.0, 0.0, -50.0)
        aston_root.location = (0.0, 0.0, -50.0)
        evan_root.location = (0.0, 0.0, -50.0)
        lea_root.location = (0.0, 0.0, -50.0)
        stage_root.location = (0.0, 0.0, -80.0)
        stage_halo.hide_render = True
        if nardus_arm_l:
            nardus_arm_l.rotation_euler = (0.0, 0.0, 0.0)
        if nardus_arm_r:
            nardus_arm_r.rotation_euler = (0.0, 0.0, 0.0)

        if f < 60:
            # -----------------------------------------------------------------
            # Act 1 (f = 0..59): KIEPIE QUAD — TWIN CANNONS & LIGHTNING STRIKE
            # -----------------------------------------------------------------
            t = f / 59.0
            quad_root.location = (-0.55 + 1.1 * t, -0.35 + 0.55 * t, 0.01)
            quad_root.rotation_euler = (0.0, math.radians(-5.0 * math.sin(t * math.pi)), math.radians(150.0 - 18.0 * t))
            quad_root.scale = (1.0, 1.0, 1.0)
            spin_wheels(quad_wheels, f, 0.52)
            show_hero_stage(quad_root.location, 0)
            bpy.context.view_layer.update()

            if args.portrait:
                cam_obj.location = (quad_root.location.x + 1.45, quad_root.location.y - 5.75, 3.15)
                cam_target.location = (quad_root.location.x + 0.10, quad_root.location.y + 0.10, 2.05)
                cam_data.lens = 24.0
            else:
                cam_obj.location = (quad_root.location.x + 1.85, quad_root.location.y - 3.2, 2.15)
                cam_target.location = (quad_root.location.x + 0.10, quad_root.location.y + 0.10, 0.82)
                cam_data.lens = 40.0

            for i, tr in enumerate(tracers):
                phase = ((f * 0.42 + i * 0.25) % 1.0)
                side = -0.42 if i % 2 == 0 else 0.42
                fwd = quad_root.matrix_world.to_quaternion() @ Vector((side, -1.0 - 10.0 * phase, 0.58))
                tr.location = quad_root.location + fwd
                tr.rotation_euler = (math.radians(90), 0.0, quad_root.rotation_euler.z)

            if f >= 25:
                lp = min(1.0, (f - 25) / 30.0)
                strike_pos = (quad_root.location.x + 1.65, quad_root.location.y + 1.45, 0.0)
                place_lightning(lightning_1, strike_pos, lp, f, scale=0.46)
                flare_light.location = (strike_pos[0], strike_pos[1], 3.5)
                flare_data.color = (0.45, 0.94, 1.0)
                flare_data.energy = 420.0 * (1.0 - 0.35 * lp) * (0.75 + 0.25 * abs(math.sin(f * 2.3)))

        elif f < 120:
            # -----------------------------------------------------------------
            # Act 2 (f = 60..119): BIG-BEN F1 — CASH-BAG ROCKETS & METEOR DROP
            # -----------------------------------------------------------------
            t = (f - 60) / 59.0
            aston_root.location = (-0.45 + 0.9 * t, -0.3 + 0.35 * t, 0.01)
            aston_root.rotation_euler = (0.0, math.radians(-3.5 * math.sin(t * math.pi * 2.0)), math.radians(-135.0 + 12.0 * t))
            aston_root.scale = (1.0, 1.0, 1.0)
            spin_wheels(aston_wheels, f, 0.62)
            show_hero_stage(aston_root.location, 1)
            bpy.context.view_layer.update()

            if args.portrait:
                cam_obj.location = (aston_root.location.x - 1.5, aston_root.location.y - 5.65, 3.05)
                cam_target.location = (aston_root.location.x, aston_root.location.y + 0.05, 2.0)
                cam_data.lens = 24.0
            else:
                cam_obj.location = (aston_root.location.x - 1.9, aston_root.location.y - 3.45, 1.95)
                cam_target.location = (aston_root.location.x, aston_root.location.y + 0.05, 0.72)
                cam_data.lens = 38.0

            for i, bag_rk in enumerate(cash_rockets):
                phase = (((f - 60) * 0.11 + i * 0.24) % 1.0)
                side = -0.38 if i % 2 == 0 else 0.38
                local_offset = Vector((side, -1.35 - 7.2 * phase, 0.42 + 0.25 * math.sin(phase * math.pi)))
                bag_rk.location = aston_root.location + (aston_root.matrix_world.to_quaternion() @ local_offset)
                bag_rk.rotation_euler = (
                    math.radians(18.0 * math.sin(f * 0.3 + i)),
                    math.radians(14.0 * math.cos(f * 0.25 + i)),
                    aston_root.rotation_euler.z,
                )
                tr = cash_trails[i]
                trail_off = Vector((side, -0.55 - 7.2 * phase, 0.42 + 0.25 * math.sin(phase * math.pi)))
                tr.location = aston_root.location + (aston_root.matrix_world.to_quaternion() @ trail_off)
                tr.rotation_euler = (math.radians(90), 0.0, aston_root.rotation_euler.z)

            strike_xy = (aston_root.location.x + 1.8, aston_root.location.y + 1.45)
            if f >= 78:
                if f < 93:
                    drop_p = (f - 78) / 15.0
                    gz = 6.2 * (1.0 - drop_p ** 1.6)
                    giant_cash_bag_1.location = (strike_xy[0], strike_xy[1], max(0.0, gz))
                    giant_cash_bag_1.scale = (2.45, 2.45, 2.45)
                    giant_cash_bag_1.rotation_euler = (0.0, 0.0, math.radians(-22.0))
                else:
                    exp_p = min(1.0, (f - 93) / 24.0)
                    squash = 1.0 + 0.14 * math.sin(exp_p * math.pi * 2.0) * (1.0 - exp_p)
                    giant_cash_bag_1.location = (strike_xy[0], strike_xy[1], 0.0)
                    giant_cash_bag_1.scale = (2.35 * squash, 2.35 * squash, 2.35 / squash)
                    giant_cash_bag_1.rotation_euler = (0.0, 0.0, math.radians(-20.0))
                    place_cash_explosion((strike_xy[0], strike_xy[1], 0.0), exp_p, f, bill_count=30)
                    flare_light.location = (strike_xy[0], strike_xy[1], 3.0)
                    flare_data.color = (0.35, 1.0, 0.45)
                    flare_data.energy = 420.0 * (1.0 - 0.45 * exp_p)

        elif f < 180:
            # -----------------------------------------------------------------
            # Act 3 (f = 120..179): NARDUS — POGO HOP, CRAGGY METEOR + SCULPTED
            # NUKE MUSHROOM EXPLOSION BEHIND HIM -> NUCLEAR FLASH INTO EVAN
            # -----------------------------------------------------------------
            t = (f - 120) / 59.0
            hop = abs(math.sin(t * math.pi * 3.0)) * 0.62
            nardus_root.location = (-0.35 + 0.7 * t, -0.22, 0.01 + hop)
            nardus_root.rotation_euler = (
                math.radians(8.0 * math.cos(t * math.pi * 4.0)),
                0.0,
                math.radians(-6.0 + 12.0 * t),
            )
            nardus_root.scale = (1.0, 1.0, 1.0)
            flap = math.sin(f * 0.85) * 0.65
            if nardus_arm_l:
                nardus_arm_l.rotation_euler = (0.0, flap, 0.0)
            if nardus_arm_r:
                nardus_arm_r.rotation_euler = (0.0, -flap, 0.0)

            show_hero_stage(nardus_root.location, 2)
            # Subtle camera impact shake on detonation (f = 146..153)
            shake_x = 0.0
            shake_z = 0.0
            if 146 <= f <= 153:
                amp = 0.14 * (1.0 - (f - 146) / 7.0)
                shake_x = amp * math.sin(f * 3.1)
                shake_z = amp * math.cos(f * 4.3)
            if args.portrait:
                cam_obj.location = (nardus_root.location.x + 1.05 + shake_x, nardus_root.location.y - 6.10, 3.35 + shake_z)
                cam_target.location = (nardus_root.location.x + 0.12, nardus_root.location.y + 0.35, 2.28 + hop * 0.15)
                cam_data.lens = 23.0
            else:
                cam_obj.location = (nardus_root.location.x + 1.45 + shake_x, nardus_root.location.y - 4.35, 2.15 + shake_z)
                cam_target.location = (nardus_root.location.x + 0.30, nardus_root.location.y + 0.35, 1.52 + hop * 0.25)
                cam_data.lens = 30.0

            # Bananas
            for i, bn in enumerate(bananas):
                phase = (((f - 120) * 0.22 + i * 0.14) % 1.0)
                side = (-1.0 if i % 2 == 0 else 1.0) * (0.55 + 0.22 * (i % 3))
                bn.location = nardus_root.location + Vector((side - 0.9 * phase, 0.4 + 2.0 * phase, 0.95 + 0.60 * math.sin(phase * math.pi)))
                bn.rotation_euler = (f * 0.35 + i, f * 0.28, f * 0.45 + i * 0.5)
                bn.scale = (0.34, 0.34, 0.34)

            impact_x = nardus_root.location.x + (0.28 if args.portrait else 1.05)
            impact_y = 2.85 if args.portrait else 2.45

            # Background meteor shower + Hero Meteor descent (f = 122..145)
            if f < 146:
                for i, bm_obj in enumerate(bg_meteors):
                    if f >= 122 + i * 3:
                        mp = ((f - 122 - i * 3) / 18.0) % 1.0
                        xoff = (-1.1, -0.4, 0.5, 1.1)[i]
                        bm_obj.location = (impact_x + xoff + 0.7 * (1.0 - mp), impact_y + 0.8, 5.2 * (1.0 - mp) + 0.3)
                        bm_obj.scale = (0.16, 0.16, 0.24)
                        bm_obj.rotation_euler = (f * 0.2 + i, f * 0.15, f * 0.25)

                fall = max(0.0, min(1.0, (f - 124.0) / 21.0))
                fall_ease = fall ** 1.25
                mx = impact_x + 1.05 * (1.0 - fall_ease)
                my = impact_y + 0.95 * (1.0 - fall_ease)
                mz = 5.4 * (1.0 - fall_ease) + 0.42
                hero_meteor_root.location = (mx, my, mz)
                hero_meteor_root.rotation_euler = (math.radians(-14.0), math.radians(-16.0), f * 0.18)
                hero_meteor_root.scale = (1.18, 1.18, 1.18)
                for i, emb in enumerate(meteor_embers):
                    eu = ((f * 0.16 + i * 0.125) % 1.0)
                    emb.location = (mx + 0.40 * eu + 0.14 * math.sin(i * 2.1 + f * 0.3), my + 0.35 * eu, mz + 0.5 + 1.6 * eu)
                    es = 0.085 * (1.0 - 0.65 * eu)
                    emb.scale = (es, es, es)
                flare_light.location = (mx, my - 0.5, mz)
                flare_data.color = (1.0, 0.45, 0.10)
                flare_data.energy = 650.0 + 900.0 * fall
            else:
                # Nuke detonation & towering sculpted Mushroom Cloud (f = 146..179)
                rise_raw = max(0.0, min(1.0, (f - 146.0) / 22.0))
                rise = 1.0 - (1.0 - rise_raw) ** 2.2
                billow = 1.0 + 0.12 * max(0.0, (f - 160.0) / 19.0)
                nuke_root.location = (impact_x, impact_y, 0.0)
                nuke_scale = (0.98 if args.portrait else 1.12) * (0.42 + 0.58 * rise) * billow
                nuke_root.scale = (nuke_scale, nuke_scale, nuke_scale * (0.45 + 0.55 * rise))

                # Core orb flashes bright at impact (f=146..152), then surges blindingly at end (f=172..179)
                end_surge = max(0.0, (f - 172.0) / 7.0) ** 1.6
                orb_s = 1.45 * max(0.35, 1.0 - (f - 146) / 10.0) + 3.2 * end_surge
                nuke_core_orb.scale = (orb_s, orb_s, orb_s)
                nuke_core_orb.location = (0.0, 0.0, 0.55 + 1.15 * end_surge)

                # Cap rises slightly faster than stem for crisp mushroom silhouette
                nuke_cap_root.location = (0.0, 0.0, 1.35 + 0.92 * rise)
                cap_expand = 0.58 + 0.54 * (rise ** 0.75)
                nuke_cap_root.scale = (cap_expand, cap_expand, 0.62 + 0.38 * rise)
                nuke_cap_root.rotation_euler = (0.0, 0.0, (f - 146) * 0.025)

                ring_p = max(0.0, min(1.0, (f - 146.0) / 16.0))
                shock_ring.location = (impact_x, impact_y, 0.05)
                shock_ring.data.materials[0] = mat_shock
                shock_ring.scale = (0.8 + ring_p * 4.5, 0.8 + ring_p * 4.5, 0.22)
                ring_p2 = max(0.0, min(1.0, (f - 149.0) / 18.0))
                if ring_p2 > 0.02:
                    shock_ring_2.location = (impact_x, impact_y, 0.05)
                    shock_ring_2.data.materials[0] = mat_shock
                    shock_ring_2.scale = (0.6 + ring_p2 * 3.8, 0.6 + ring_p2 * 3.8, 0.16)

                flare_light.location = (impact_x, impact_y - 0.8, 2.2)
                flare_data.color = (1.0, 0.72 + 0.24 * end_surge, 0.28 + 0.62 * end_surge)
                flare_data.energy = 1150.0 + 2800.0 * end_surge

        elif f < 240:
            # -----------------------------------------------------------------
            # Act 4 (f = 180..239): EVAN THE SKELETON — BOOMERANG GUITAR THROW
            # & CATCH -> GIANT ARTICULATED DEMON HAND + ENGULFING FLAMES DRAG DOWN
            # -----------------------------------------------------------------
            t = (f - 180) / 59.0
            base_z = 0.01 + 0.05 * abs(math.sin(t * math.pi * 2.0))
            evan_x = 0.0
            evan_y = -0.22 + 0.18 * min(1.0, t / 0.60)
            evan_root.location = (evan_x, evan_y, base_z)
            evan_root.scale = (0.96, 0.96, 0.96)
            evan_root.rotation_euler = (0.0, 0.0, math.radians(4.0 * math.sin(t * math.pi)))
            show_hero_stage((evan_x, evan_y, 0.0), 3)

            # Camera pulls smoothly back for Demon Hand reveal starting after guitar catch (f=216)
            pull = max(0.0, min(1.0, (f - 216.0) / 9.0))
            pull = pull * pull * (3.0 - 2.0 * pull)
            if args.portrait:
                cam_obj.location = (0.95 + 0.12 * pull, -6.20 - 2.45 * pull, 3.05 + 0.65 * pull)
                cam_target.location = (0.0, -0.05, 1.98 + 0.50 * pull)
                cam_data.lens = 23.5 - 3.8 * pull
            else:
                cam_obj.location = (1.55 + 0.35 * pull, -4.15 - 2.55 * pull, 1.95 + 0.55 * pull)
                cam_target.location = (0.0, -0.05, 1.18 + 0.62 * pull)
                cam_data.lens = 36.0 - 8.5 * pull

            # NLA action choreography
            if f < 187:
                play_rig_action(evan_rig, "Play_Strum", ((f - 180) / 6.0) % 1.0)
            elif f < 194:
                play_rig_action(evan_rig, "Action_GuitarThrow", ((f - 187) / 6.0) * 0.52)
            elif f < 199:
                play_rig_action(evan_rig, "Action_GuitarThrow", 0.52 + ((f - 194) / 4.0) * 0.48)
            elif f < 210:
                play_rig_action(evan_rig, "Run_NoGuitar", ((f - 199) / 10.0) % 1.0)
            elif f < 218:
                play_rig_action(evan_rig, "Action_GuitarCatch", min(1.0, (f - 210) / 7.0))
            elif f < 224:
                play_rig_action(evan_rig, "Play_Strum", ((f - 218) / 5.0) % 1.0)
            else:
                play_rig_action(evan_rig, "Action_BigFinish", min(1.0, (f - 224) / 14.0))

            # Sound waves while strumming / before grab
            if f < 222:
                for i, wave_ring in enumerate(evan_waves):
                    wave_ring.location = (0.12, evan_y + 0.24 + 0.32 * i, 1.16 + base_z)
                    wave_ring.rotation_euler = (math.radians(90), 0.0, 0.0)
                    size = 0.18 + ((t * 1.6 + i * 0.38) % 1.0) * 0.32
                    wave_ring.scale = (size, size, size)

            # Boomerang guitar in flight (f = 194..214): hide worn guitar, fly visible loop & catch!
            if 194 <= f <= 214:
                for part in evan_guitar_parts:
                    part.hide_render = True
                u = (f - 194.0) / 20.0
                loop_ang = u * math.pi  # 0 -> pi
                x_span = 0.85 if args.portrait else 1.08
                y_reach = 1.75 if args.portrait else 1.60
                gx = evan_x + 0.12 + x_span * math.sin(loop_ang) * math.cos(loop_ang * 0.45)
                gy = evan_y - 0.36 - y_reach * math.sin(loop_ang)
                gz = base_z + 1.28 + 0.28 * math.sin(loop_ang)
                guitar_projectile_root.location = (gx, gy, gz)
                guitar_projectile_root.rotation_euler = (
                    math.radians(24.0 + 10.0 * math.sin(loop_ang)),
                    math.radians(12.0 * math.cos(loop_ang * 2.0)),
                    (f - 194) * 0.92,
                )
                guitar_projectile_root.scale = (1.0, 1.0, 1.0)
            elif f in (215, 216, 217):
                cp = (f - 215.0) / 2.0
                shock_ring_2.location = (evan_x + 0.12, evan_y - 0.32, 1.35)
                shock_ring_2.rotation_euler = (math.radians(90), 0.0, 0.0)
                shock_ring_2.data.materials[0] = mat_evan_wave
                cs = 0.35 + 0.65 * cp
                shock_ring_2.scale = (cs, cs, 0.25)

            # Giant Demon Hand erupts behind Evan AFTER guitar catch (f >= 216), grabs him, flames engulf, drags straight down!
            if f >= 216:
                emerge = max(0.0, min(1.0, (f - 216.0) / 7.0))
                emerge = emerge * emerge * (3.0 - 2.0 * emerge)
                grab_reach = max(0.0, min(1.0, (f - 222.0) / 5.0))
                grab_reach = grab_reach * grab_reach * (3.0 - 2.0 * grab_reach)
                close = max(0.0, min(1.0, (f - 223.0) / 5.0))
                close = close * close * (3.0 - 2.0 * close)
                drag = max(0.0, min(1.0, (f - 228.0) / 11.0))
                drag = drag ** 1.35

                portal_open = max(0.0, min(1.0, (f - 216.0) / 6.0))
                portal_open = portal_open * portal_open * (3.0 - 2.0 * portal_open)
                portal_root.location = (evan_x, evan_y + 0.25, 0.0)
                ps = 1.08 * portal_open
                portal_root.scale = (ps, ps, 1.0)

                # Evan dragged straight down at FULL scale (never shrink him!) until completely below ground
                evan_root.location.z = base_z - 2.65 * drag
                evan_root.rotation_euler = (
                    math.radians(16.0 * drag),
                    math.radians(6.0 * math.sin(f * 0.9) * close * (1.0 - drag)),
                    math.radians(4.0 * math.sin(t * math.pi)),
                )

                # Giant Demon Hand (scale = 1.48 -> fingertips ~3.8 m tall, ~2x Evan's height, zero top-edge clip!)
                hand_z = -4.80 + 3.15 * emerge - 3.65 * drag
                hand_y = evan_y + 0.66 - 0.34 * grab_reach
                demon_root.location = (evan_x, hand_y, hand_z)
                demon_root.rotation_euler = (math.radians(-6.0 + 10.0 * close), 0.0, math.radians(3.0 * math.sin(f * 0.22)))
                demon_root.scale = (1.48, 1.48, 1.48)

                for knuckle, mid_joint, dist_joint, splay_deg in demon_finger_joints:
                    knuckle.rotation_euler = (
                        math.radians(-46.0 * close),
                        math.radians(-splay_deg * (1.0 - 0.55 * close)),
                        0.0,
                    )
                    mid_joint.rotation_euler = (math.radians(-58.0 * close), 0.0, 0.0)
                    dist_joint.rotation_euler = (math.radians(-48.0 * close), 0.0, 0.0)
                thumb_base.rotation_euler = (math.radians(-26.0 * close), math.radians(-42.0 + 78.0 * close), 0.0)
                thumb_dist.rotation_euler = (math.radians(-38.0 * close), 0.0, 0.0)

                rp = max(0.0, min(1.0, (f - 216.0) / 14.0))
                shock_ring.location = (evan_x, evan_y + 0.25, 0.045)
                shock_ring.data.materials[0] = mat_portal_lava
                shock_ring.scale = (0.65 + 2.4 * rp, 0.65 + 2.4 * rp, 0.20)

                # Roaring engulfing hellfire tongues + rising embers around Evan
                flame_in = max(0.0, min(1.0, (f - 218.0) / 6.0))
                flame_out = 1.0 - 0.35 * max(0.0, (f - 234.0) / 5.0)
                flame_amp = flame_in * flame_out
                if flame_amp > 0.01:
                    evan_flames_root.location = (evan_x, evan_y + 0.05, 0.02)
                    evan_flames_root.rotation_euler = (0.0, 0.0, (f - 218) * 0.06)
                    evan_flames_root.scale = (1.05, 1.05, 1.0)
                    for fl, h_base, idx, is_core in evan_flame_objects:
                        flicker = 0.82 + 0.32 * abs(math.sin(f * 0.65 + idx * 0.85))
                        xy_s = flame_amp * (0.95 + 0.16 * math.sin(f * 0.5 + idx))
                        z_s = flame_amp * flicker * (1.15 if not is_core else 1.05)
                        fl.scale = (xy_s, xy_s, z_s)
                    for idx, emb in enumerate(hell_embers):
                        eu = ((f * 0.09 + idx / len(hell_embers)) % 1.0)
                        ang = idx * (2.0 * math.pi / len(hell_embers)) + f * 0.08
                        rad = (0.45 + 0.65 * (idx % 3)) * (1.0 - 0.35 * eu)
                        emb.location = (evan_x + math.cos(ang) * rad, evan_y + math.sin(ang) * rad * 0.7, 0.15 + 3.2 * eu)
                        es = 0.065 * flame_amp * (1.0 - 0.6 * eu)
                        emb.scale = (es, es, es)

                flare_light.location = (evan_x, evan_y - 0.4, 1.5)
                flare_data.color = (1.0, 0.24, 0.04)
                flare_data.energy = 1500.0 * flame_amp * (0.85 + 0.15 * abs(math.sin(f * 1.6)))

        elif f < 300:
            # -----------------------------------------------------------------
            # Act 5 (f = 240..299): LEA UNICORN — GALLOP, HORN BEAM, WING-SPREAD
            # AERIAL JUMP -> BIG PINK FLASH ON LANDING INTO "Kiepie -QUAD"
            # -----------------------------------------------------------------
            t = (f - 240) / 59.0
            # Jump spans f = 264..290 (t in 0.406..0.847), lands crisply at f = 291!
            jump_phase = max(0.0, min(1.0, (f - 264.0) / 27.0))
            in_air = 264 <= f <= 290
            takeoff_lift = (1.36 if args.portrait else 0.92) * math.sin(math.pi * jump_phase) if in_air else 0.0
            landing_squash = 0.15 * math.exp(-((f - 291.5) / 1.8) ** 2)
            flight_tilt = math.sin(math.pi * jump_phase) if in_air else 0.0

            lea_root.location = (0.0, -0.16 + 0.22 * t, 0.01 + 0.08 * abs(math.sin(t * math.pi * 1.5)) + takeoff_lift)
            lea_root.scale = (0.98 + 0.05 * landing_squash, 0.98 + 0.05 * landing_squash, 0.98 - landing_squash)
            lea_root.rotation_euler = (
                math.radians(-8.0 * flight_tilt) if args.portrait else math.radians(-4.0 * flight_tilt),
                math.radians(5.0 * flight_tilt) if args.portrait else 0.0,
                math.radians(-4.0 + 7.0 * t),
            )
            show_hero_stage(lea_root.location, 4)

            if args.portrait:
                cam_obj.location = (1.28 - 0.26 * flight_tilt, -5.95, 3.25 + 0.24 * flight_tilt)
                cam_target.location = (0.0, -0.04, 2.02 + 0.18 * flight_tilt)
                cam_data.lens = 23.5
            else:
                cam_obj.location = (1.75, -4.35, 2.15 + 0.28 * flight_tilt)
                cam_target.location = (0.0, -0.04, 1.36 + 0.42 * flight_tilt)
                cam_data.lens = 32.5 - 2.5 * flight_tilt

            if f < 254:
                play_rig_action(lea_rig, "Locomotion_Gallop", (f - 240) / 13.0)
            elif f < 264:
                play_rig_action(lea_rig, "Action_WingSpread", (f - 254) / 9.0)
            elif f <= 290:
                play_rig_action(lea_rig, "UnicornBoom_Flight", (f - 264) / 26.0)
            else:
                play_rig_action(lea_rig, "Idle_Breathe", (f - 291) / 47.0)

            if 244 <= f <= 268:
                beam_strength = max(0.18, math.sin(math.pi * (f - 244) / 24.0))
                lea_beam.location = (0.0, -0.95, 1.25)
                lea_beam.rotation_euler = (math.radians(90), 0.0, 0.0)
                lea_beam.scale = (1.0, 1.0, 1.95 * beam_strength)

            lea_boom_ring[0].location = (0.0, 0.20, 0.055)
            ring_size = 0.55 + 1.45 * max(0.0, min(1.0, (f - 264) / 26.0))
            lea_boom_ring[0].scale = (ring_size, ring_size, 0.12)

            # Big Hot-Pink Supernova Flash on landing (f = 291..299)
            if f >= 291:
                land = max(0.0, min(1.0, (f - 291.0) / 8.0))
                land_ease = 1.0 - (1.0 - land) ** 2.0
                lx, ly = lea_root.location.x, lea_root.location.y
                pink_flash_root.location = (lx, ly, 0.0)
                orb_r = 0.35 + 7.2 * (land ** 1.35)
                pink_orb.scale = (orb_r, orb_r, orb_r * 0.85)
                pil_r = 0.35 + 2.2 * land_ease
                pink_pillar.scale = (pil_r, pil_r, 0.4 + 0.85 * land_ease)

                for r_idx, pr in enumerate(pink_rings):
                    rp = max(0.0, min(1.0, land * 1.25 - r_idx * 0.18))
                    if rp > 0.01:
                        pr.location = (lx, ly, 0.055 + r_idx * 0.03)
                        rs = 0.65 + 6.5 * rp
                        pr.scale = (rs, rs, 0.18)

                flare_light.location = (lx, ly - 0.3, 2.2)
                flare_data.color = (1.0, 0.12, 0.74)
                flare_data.energy = 4500.0 * (0.25 + 0.75 * land)

        else:
            # -----------------------------------------------------------------
            # Act 6 (f = 300..359): DRAMATIC "Kiepie -QUAD" TITLE SLAM + SOLAR FLARE
            # + ALL 5 RIDES IN HERO FORMATION (BOTH LANDSCAPE & PORTRAIT!)
            # -----------------------------------------------------------------
            p = min(1.0, max(0.0, (f - 300) / 59.0))
            slam = max(0.0, min(1.0, (f - 300) / 11.0))
            slam_ease = slam ** 2.2
            # Elastic rebound pulse on title lock (f = 311..321)
            bounce = 0.0
            if f >= 311:
                dt_b = (f - 311) / 12.0
                bounce = 0.14 * math.sin(dt_b * math.pi * 2.5) * math.exp(-dt_b * 3.8)
            # Camera impact shake right on slam lock (f = 311..318)
            cshake_x = 0.0
            cshake_z = 0.0
            if 311 <= f <= 318:
                amp = 0.18 * (1.0 - (f - 311) / 7.0)
                cshake_x = amp * math.sin(f * 3.4)
                cshake_z = amp * math.cos(f * 4.1)

            if args.portrait:
                cam_obj.location = (cshake_x, -12.1 + 0.9 * p, 3.80 + cshake_z)
                cam_target.location = (0.0, -0.35, 2.30)
                cam_data.lens = 24.5

                # 2-row V-chevron keeping ALL 5 rides clearly framed in 9:16 portrait!
                quad_root.location = (-1.18, -2.25, 0.01)
                quad_root.rotation_euler = (0.0, 0.0, math.radians(-22.0))
                quad_root.scale = (0.74, 0.74, 0.74)

                nardus_root.location = (0.0, -2.75, 0.01 + 0.10 * abs(math.sin((f - 300) * 0.22)))
                nardus_root.rotation_euler = (0.0, 0.0, math.radians(4.0))
                nardus_root.scale = (0.72, 0.72, 0.72)

                aston_root.location = (1.18, -2.25, 0.01)
                aston_root.rotation_euler = (0.0, 0.0, math.radians(22.0))
                aston_root.scale = (0.62, 0.62, 0.62)

                evan_root.location = (-0.98, -0.05, 0.01)
                evan_root.rotation_euler = (0.0, 0.0, math.radians(-8.0))
                evan_root.scale = (0.80, 0.80, 0.80)

                lea_root.location = (0.98, -0.05, 0.01)
                lea_root.rotation_euler = (0.0, 0.0, math.radians(56.0))
                lea_root.scale = (0.74, 0.74, 0.74)

                stage_root.location = (0.0, -1.15, 0.0)
                stage_root.scale = (1.05, 1.05, 1.0)
                stage_rim.data.materials[0] = stage_accents[0]

                # 3D Title "Kiepie -QUAD" sized cleanly inside 720px width even during slam!
                title_obj.data.size = 0.74
                title_rim.data.size = 0.74
                ty = -2.2 + 2.4 * slam_ease
                tz = 4.35 - 0.30 * slam_ease
                title_obj.location = (0.0, ty, tz)
                tsc = (1.62 - 0.62 * slam_ease) + bounce
                title_obj.scale = (tsc, tsc, tsc)
                title_obj.rotation_euler = (math.radians(90.0 + 16.0 * (1.0 - slam_ease)), 0.0, 0.0)

                solar_flare_root.location = (1.65, 6.4, 5.10)
                solar_flare_root.scale = (0.72, 0.72, 0.72)
            else:
                cam_obj.location = (cshake_x, -11.6 + 0.8 * p, 2.85 + cshake_z)
                cam_target.location = (0.0, 0.0, 1.72)
                cam_data.lens = 38.0

                # Hero 5-ride lineup across the foreground arc
                quad_root.location = (-3.65, -1.35, 0.01)
                quad_root.rotation_euler = (0.0, 0.0, math.radians(-26.0))
                quad_root.scale = (0.84, 0.84, 0.84)

                aston_root.location = (-1.85, -1.45, 0.01)
                aston_root.rotation_euler = (0.0, 0.0, math.radians(-14.0))
                aston_root.scale = (0.68, 0.68, 0.68)

                nardus_root.location = (0.0, -1.55, 0.01 + 0.10 * abs(math.sin((f - 300) * 0.22)))
                nardus_root.rotation_euler = (0.0, 0.0, math.radians(4.0))
                nardus_root.scale = (0.78, 0.78, 0.78)

                evan_root.location = (1.85, -1.40, 0.01)
                evan_root.rotation_euler = (0.0, 0.0, math.radians(8.0))
                evan_root.scale = (0.86, 0.86, 0.86)

                lea_root.location = (3.65, -1.35, 0.01)
                lea_root.rotation_euler = (0.0, 0.0, math.radians(90.0))
                lea_root.scale = (0.80, 0.80, 0.80)

                title_obj.data.size = 1.26
                title_rim.data.size = 1.26
                ty = -2.6 + 3.0 * slam_ease
                tz = 3.70 - 0.55 * slam_ease
                title_obj.location = (0.0, ty, tz)
                tsc = (1.85 - 0.85 * slam_ease) + bounce
                title_obj.scale = (tsc, tsc, tsc)
                title_obj.rotation_euler = (math.radians(90.0 + 16.0 * (1.0 - slam_ease)), 0.0, 0.0)

                solar_flare_root.location = (2.65, 6.8, 4.25)
                solar_flare_root.scale = (0.88, 0.88, 0.88)

            spin_wheels(quad_wheels, f, 0.55)
            spin_wheels(aston_wheels, f, 0.58)

            # Rotate 3D Solar Flare starburst rays & pulse on slam
            solar_ray_wheel.rotation_euler = (0.0, (f - 300) * 0.032, 0.0)
            flare_boost = 1.0 + 0.30 * math.exp(-((f - 312.0) / 6.0) ** 2)
            solar_core.scale = (flare_boost, flare_boost, flare_boost)
            solar_halo.scale = (flare_boost * 1.15, flare_boost * 1.15, flare_boost * 1.15)

            flare_light.location = (1.6, 3.8, 4.0)
            flare_data.color = (1.0, 0.80, 0.36)
            flare_data.energy = 3200.0 + 1400.0 * math.exp(-((f - 312.0) / 8.0) ** 2)

            # Fast expanding slam shockwave rings + radial sparks that clear cleanly after slam (f = 311..328)
            if 311 <= f <= 328:
                rp = min(1.0, (f - 311.0) / 17.0)
                tpos = (title_obj.location.x, title_obj.location.y + 0.8, title_obj.location.z)
                finale_gold_ring.location = tpos
                finale_gold_ring.rotation_euler = (math.radians(90), 0.0, 0.0)
                grs = 0.8 + 7.5 * (rp ** 0.72)
                finale_gold_ring.scale = (grs, grs, 0.16 * (1.0 - 0.65 * rp))

                rp2 = min(1.0, max(0.0, (f - 312.0) / 16.0))
                if rp2 > 0.01:
                    finale_pink_ring.location = (tpos[0], tpos[1] + 0.2, tpos[2])
                    finale_pink_ring.rotation_euler = (math.radians(90), 0.0, 0.0)
                    prs = 0.6 + 6.8 * (rp2 ** 0.75)
                    finale_pink_ring.scale = (prs, prs, 0.14 * (1.0 - 0.65 * rp2))

                sp_p = (f - 311.0) / 17.0
                for idx, spk in enumerate(finale_sparks):
                    ang = idx * (2.0 * math.pi / len(finale_sparks)) + 0.15
                    rad = 0.5 + 5.2 * (sp_p ** 0.65) * (0.75 + 0.25 * (idx % 2))
                    spk.location = (tpos[0] + math.cos(ang) * rad, tpos[1] + 0.3, tpos[2] + math.sin(ang) * rad * 0.55)
                    ss = 0.075 * (1.0 - sp_p)
                    spk.scale = (ss, ss, ss)

            shock_ring.location = (0.0, 1.5, 0.06)
            shock_ring.data.materials[0] = mat_bolt_ring
            ring_size = (2.8 if args.portrait else 4.0) + 0.14 * math.sin(f * 0.12)
            shock_ring.scale = (ring_size, ring_size, 0.12)

            play_rig_action(evan_rig, "Idle_Sway", ((f - 300) % 48) / 47.0)
            play_rig_action(lea_rig, "Idle_Breathe", ((f - 300) % 48) / 47.0)

    if args.preview_frames:
        target_frames = [int(x.strip()) for x in args.preview_frames.split(",") if x.strip()]
    else:
        target_frames = list(range(max(0, args.start), min(TOTAL_FRAMES, args.end + 1)))

    for f in target_frames:
        scene.frame_set(f)
        apply_frame(f)
        scene.render.filepath = str(frames_dir / f"frame_{f:04d}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    args = parse_args()
    if args.preview_composite:
        frames = [int(x.strip()) for x in args.preview_frames.split(",") if x.strip()]
        preview_composite(Path(args.frames_dir), frames, portrait=args.portrait)
    elif args.encode_only:
        encode_video(Path(args.frames_dir), portrait=args.portrait)
    else:
        build_and_render(args)


if __name__ == "__main__":
    main()
