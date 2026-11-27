#!/usr/bin/env python3
"""
Build the 15-second (360 frames @ 24 fps, 1280x720) action-packed intro splash
video for Kiepie-Quad (`web-assets/kiepie-quad-splash.mp4`) using Blender 5.3.0
EEVEE + Compositor + 48 kHz stereo SFX/procedural audio mix.

Showcases all five selectable vehicles and their signature weapon kits:
  1. Kiepie Quad (`Kiepie_Bike.glb`) — Twin Autocannons + Massive Cyan-White Lightning Strike
  2. NARDUS (`Pogo_Nardus.blend`) — Pogo Hop, Turbo Wing-Flap + Banana Cannons + Fiery Meteor Shower
  3. BIG-BEN F1 (`Aston_Martin.glb`) — F1 Autocannons + Small `$` Cash Bag Rockets + Giant `$` Cash Bag Meteor Strike
  4. EVAN THE SKELETON (`Evan_Skeleton.glb`) — Sound Waves + Boomerang Guitar + Devil Hand
  5. LEA UNICORN (`Lea_Unicorn.glb`) — Horn Sparks + Horn Beam + Unicorn Boom

Usage:
  # Preview the centre frame of each vehicle beat and the finale:
  blender -b -noaudio -P src/build_intro_splash.py -- \
      --preview-frames 30,90,150,210,270,330 --frames-dir /tmp/kiepie_splash_preview

  # Render frame range (e.g. parallel shards):
  blender -b -noaudio -P src/build_intro_splash.py -- --start 0 --end 99 --frames-dir /tmp/kiepie_splash_frames
  blender -b -noaudio -P src/build_intro_splash.py -- --start 100 --end 199 --frames-dir /tmp/kiepie_splash_frames
  blender -b -noaudio -P src/build_intro_splash.py -- --start 200 --end 299 --frames-dir /tmp/kiepie_splash_frames

  # Encode frames + audio to web-assets/kiepie-quad-splash.mp4:
  python3 src/build_intro_splash.py --encode-only --frames-dir /tmp/kiepie_splash_frames
"""

from __future__ import annotations

import argparse
import math
import os
import random
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_MP4 = ROOT / "web-assets" / "kiepie-quad-splash.mp4"
SFX_DIR = ROOT / "godot" / "assets" / "sfx"
_FONT_CANDIDATES = (
    "/usr/share/fonts/truetype/roboto/unhinted/RobotoTTF/Roboto-Black.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
)
FONT_PATH = next((p for p in _FONT_CANDIDATES if Path(p).is_file()), "")

FPS = 24
TOTAL_FRAMES = 360  # 15 s: five equal vehicle spotlights + a clear finale
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
    return p.parse_args(argv)


# ---------------------------------------------------------------------------
# Audio synthesis & FFmpeg encoding (no bpy required)
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


def _mix_clip(buf_l: list[float], buf_r: list[float], clip: list[float], start_s: float,
              gain: float = 0.5, pan: float = 0.0, sr: int = 48000) -> None:
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


def _add_thunderclap(buf_l: list[float], buf_r: list[float], start_s: float,
                     gain: float = 0.75, pan: float = 0.1, sr: int = 48000, seed: int = 7) -> None:
    """Synthesize a sharp electric crack + rolling sub-thunder tail."""
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
        # High-voltage arc snap in first 90 ms + secondary crack at 140 ms
        snap1 = math.exp(-dt * 42.0) * math.sin(2.0 * math.pi * (1800.0 - 900.0 * dt) * dt)
        snap2 = (math.exp(-(dt - 0.11) * 35.0) * 0.75 if dt >= 0.11 else 0.0) * math.sin(2.0 * math.pi * 1350.0 * dt)
        crackle = (rng.random() * 2.0 - 1.0) * (math.exp(-dt * 12.0) * 0.65 + math.exp(-dt * 2.2) * 0.25)
        rumble = math.exp(-dt * 1.9) * math.sin(2.0 * math.pi * (62.0 * math.exp(-dt * 0.6) + 34.0) * dt) * 0.7
        s = snap1 * 0.6 + snap2 * 0.45 + crackle + rumble
        buf_l[j] += s * gl
        buf_r[j] += s * gr


def synthesize_audio(wav_out: Path) -> None:
    sr = 48000
    dur_s = TOTAL_FRAMES / FPS  # 15 s
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

    # Act 1 (0.0 - 2.5s, f=0..59): Kiepie Quad engine + twin autocannons + Massive Lightning Strike
    _mix_clip(buf_l, buf_r, engine, 0.0, gain=0.45, pan=-0.25, sr=sr)
    _mix_clip(buf_l, buf_r, turbo, 0.25, gain=0.40, pan=-0.1, sr=sr)
    for t in (0.25, 0.42, 0.58, 0.75, 0.92, 1.10, 1.28):
        _mix_clip(buf_l, buf_r, cannon, t, gain=0.48, pan=-0.2, sr=sr)
    # Massive Lightning Strike thunderclap at f=34 (1.42s)
    _add_thunderclap(buf_l, buf_r, 1.40, gain=0.88, pan=0.15, sr=sr, seed=101)
    _mix_clip(buf_l, buf_r, impact, 1.42, gain=0.55, pan=0.15, sr=sr)

    # Act 2 (2.5 - 5.0s, f=60..119): Nardus pogo bounce + banana cannons + meteor shower
    _mix_clip(buf_l, buf_r, turbo, 2.58, gain=0.38, pan=0.15, sr=sr)
    for idx, t in enumerate((2.72, 3.04, 3.36, 3.68, 4.00, 4.32, 4.64)):
        _mix_clip(buf_l, buf_r, pop, t, gain=0.68, pan=(-0.15 + 0.08 * idx), sr=sr)
    _mix_clip(buf_l, buf_r, explosion, 4.42, gain=0.55, pan=-0.25, sr=sr)

    # Act 3 (5.0 - 7.5s, f=120..179): BIG-BEN F1 high-rev + cash-bag rockets + cash meteor
    _mix_clip(buf_l, buf_r, engine, 5.08, gain=0.50, pan=0.15, sr=sr)
    _mix_clip(buf_l, buf_r, turbo, 5.14, gain=0.58, pan=0.1, sr=sr)
    for idx, t in enumerate((5.30, 5.55, 5.80, 6.05)):
        _mix_clip(buf_l, buf_r, cannon, t, gain=0.46, pan=(-0.2 + 0.12 * idx), sr=sr)
        _mix_clip(buf_l, buf_r, pickup, t + 0.05, gain=0.42, pan=(-0.2 + 0.12 * idx), sr=sr)
    # Giant Cash Bag impact & ka-ching cash shower at f=156 (6.50s)
    _mix_clip(buf_l, buf_r, explosion, 6.50, gain=0.80, pan=0.15, sr=sr)
    for k, dt in enumerate((0.0, 0.12, 0.24, 0.38)):
        _mix_clip(buf_l, buf_r, pickup, 6.53 + dt, gain=0.65 - 0.1 * k, pan=(-0.25 + 0.18 * k), sr=sr)

    # Act 4 (7.5 - 10s): Evan's guitar launch and devil-hand impact.
    _mix_clip(buf_l, buf_r, turbo, 7.60, gain=0.38, pan=-0.15, sr=sr)
    _mix_clip(buf_l, buf_r, cannon, 7.90, gain=0.36, pan=-0.15, sr=sr)
    _mix_clip(buf_l, buf_r, impact, 8.50, gain=0.46, pan=0.0, sr=sr)
    _mix_clip(buf_l, buf_r, pickup, 9.08, gain=0.50, pan=0.15, sr=sr)
    _mix_clip(buf_l, buf_r, pop, 9.42, gain=0.40, pan=0.15, sr=sr)
    _mix_clip(buf_l, buf_r, explosion, 9.72, gain=0.48, pan=0.15, sr=sr)

    # Act 5 (10 - 12.5s): Lea's horn beam, wing spread and unicorn boom.
    _mix_clip(buf_l, buf_r, turbo, 10.10, gain=0.22, pan=0.1, sr=sr)
    _mix_clip(buf_l, buf_r, pickup, 10.82, gain=0.48, pan=0.15, sr=sr)
    _mix_clip(buf_l, buf_r, explosion, 11.82, gain=0.56, pan=0.1, sr=sr)

    # Act 6 (12.5 - 15s): five-vehicle lineup and theme resolution.
    _mix_clip(buf_l, buf_r, turbo, 12.58, gain=0.16, pan=0.0, sr=sr)
    _mix_clip(buf_l, buf_r, pickup, 13.14, gain=0.38, pan=0.0, sr=sr)

    # Original arcade-orchestral pulse: warm chord pad, low trailer thump and
    # bright eighth-note arpeggio. This gives the SFX a musical spine without
    # requiring a stock or licensed track.
    chords = (
        (73.42, 110.00, 146.83),  # Dm
        (58.27, 87.31, 116.54),   # Bb
        (87.31, 130.81, 174.61),  # F
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

    for i in range(int(12.5 * sr), n_samples):
        t = i / sr
        elapsed = t - 12.5
        fade_in = min(1.0, elapsed / 0.45)
        fade_out = min(1.0, max(0.0, (15.0 - t) / 0.7))
        s = fade_in * fade_out * (
            0.07 * math.sin(2.0 * math.pi * 196.0 * elapsed)
            + 0.045 * math.sin(2.0 * math.pi * 293.66 * elapsed)
        )
        buf_l[i] += s
        buf_r[i] += s

    # Soft-clip & fade out last 0.4s
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


def encode_video(frames_dir: Path) -> None:
    wav_path = frames_dir / "splash_audio.wav"
    synthesize_audio(wav_path)
    OUT_MP4.parent.mkdir(parents=True, exist_ok=True)
    tmp_mp4 = OUT_MP4.with_suffix(".tmp.mp4")
    # Keep type in the open upper-left area and render cards as transparent PNGs.
    # This also works with FFmpeg builds that omit the drawtext filter.
    cards = [
        (0.00, 2.50, "KIEPIE QUAD", (("PRIMARY", "Twin autocannons"), ("SPECIAL", "Finned rocket"), ("ULTIMATE", "Lightning strike")), (56, 205, 235)),
        (2.50, 5.00, "NARDUS", (("PRIMARY", "Banana cannons"), ("SPECIAL", "Cigar launcher"), ("ULTIMATE", "Meteor shower")), (250, 113, 186)),
        (5.00, 7.50, "BIG-BEN F1", (("PRIMARY", "F1 autocannon"), ("SPECIAL", "Cash bag"), ("ULTIMATE", "Cash drop")), (164, 220, 102)),
        (7.50, 10.00, "EVAN THE SKELETON", (("PRIMARY", "Sound waves"), ("SPECIAL", "Boomerang guitar"), ("ULTIMATE", "Devil hand")), (246, 102, 168)),
        (10.00, 12.50, "LEA UNICORN", (("PRIMARY", "Horn sparks"), ("SPECIAL", "Horn beam"), ("ULTIMATE", "Unicorn boom")), (246, 208, 111)),
        (12.50, 15.00, "KIEPIE-QUAD", (), (164, 183, 255)),
    ]
    from PIL import Image, ImageDraw, ImageFont

    overlay_dir = frames_dir / "overlays"
    overlay_dir.mkdir(parents=True, exist_ok=True)
    font_path = FONT_PATH or "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    title_font = ImageFont.truetype(font_path, 38)
    category_font = ImageFont.truetype(font_path, 15)
    detail_font = ImageFont.truetype(font_path, 21)
    final_title_font = ImageFont.truetype(font_path, 46)
    final_detail_font = ImageFont.truetype(font_path, 22)
    vehicle_accents = (
        (56, 205, 235), (250, 113, 186), (164, 220, 102),
        (246, 102, 168), (246, 208, 111),
    )
    for frame in range(TOTAL_FRAMES):
        t = frame / FPS
        card = next((c for c in cards if c[0] <= t < c[1]), None)
        overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
        if card:
            start, end, title, abilities, accent = card
            draw = ImageDraw.Draw(overlay)
            panel = (44, 28, 478, 254) if abilities else (44, 28, 1236, 174)
            draw.rounded_rectangle(panel, radius=18, fill=(5, 13, 27, 225), outline=(255, 255, 255, 32), width=1)
            draw.rounded_rectangle((44, 28, 53, panel[3]), radius=4, fill=(*accent, 255))
            if abilities:
                index = cards.index(card) + 1
                draw.text((76, 42), f"SELECTABLE RIDE     /     {index:02d} OF 05", font=category_font, fill=(*accent, 255))
                draw.text((76, 61), title, font=title_font, fill=(255, 255, 255, 255))
                for col, (kind, ability) in enumerate(abilities):
                    y = 110 + col * 41
                    draw.rounded_rectangle((68, y, 454, y + 34), radius=8, fill=(255, 255, 255, 14), outline=(255, 255, 255, 24), width=1)
                    draw.text((80, y + 8), kind, font=category_font, fill=(*accent, 255))
                    draw.text((177, y + 5), ability, font=detail_font, fill=(245, 248, 255, 255))
            else:
                eyebrow = "FIVE RIDES     /     ONE ARENA"
                title_box = draw.textbbox((0, 0), title, font=final_title_font)
                eyebrow_box = draw.textbbox((0, 0), eyebrow, font=category_font)
                draw.text(((WIDTH - (eyebrow_box[2] - eyebrow_box[0])) / 2, 38), eyebrow, font=category_font, fill=(*accent, 255))
                draw.text(((WIDTH - (title_box[2] - title_box[0])) / 2, 55), title, font=final_title_font, fill=(255, 255, 255, 255))
                for i, color in enumerate(vehicle_accents):
                    x0 = 76 + i * 224
                    draw.rounded_rectangle((x0, 129, x0 + 208, 139), radius=5, fill=(*color, 255))
            progress = max(0.0, min(1.0, (t - start) / (end - start)))
            progress_left, progress_right, progress_y = (66, 456, 245) if abilities else (66, 1214, 168)
            draw.rounded_rectangle((progress_left, progress_y, progress_right, progress_y + 3), radius=2, fill=(255, 255, 255, 35))
            draw.rounded_rectangle((progress_left, progress_y, progress_left + int((progress_right - progress_left) * progress), progress_y + 3), radius=2, fill=(*accent, 220))
        overlay.save(overlay_dir / f"overlay_{frame:04d}.png", optimize=True)
    cmd = [
        "ffmpeg",
        "-y",
        "-framerate", str(FPS),
        "-i", str(frames_dir / "frame_%04d.png"),
        "-framerate", str(FPS),
        "-i", str(overlay_dir / "overlay_%04d.png"),
        "-i", str(wav_path),
        "-filter_complex", "[0:v][1:v]overlay=0:0:format=auto[v]",
        "-map", "[v]",
        "-map", "2:a",
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-crf", "28",
        "-preset", "slow",
        "-movflags", "+faststart",
        "-c:a", "aac",
        "-b:a", "96k",
        "-shortest",
        str(tmp_mp4),
    ]
    try:
        subprocess.run(cmd, check=True, timeout=120)
        os.replace(tmp_mp4, OUT_MP4)
    except BaseException:
        tmp_mp4.unlink(missing_ok=True)
        raise
    print(f"Encoded {OUT_MP4} ({OUT_MP4.stat().st_size / 1024:.1f} KiB)")


# ---------------------------------------------------------------------------
# Blender 5.3.0 Scene & VFX Builder
# ---------------------------------------------------------------------------

def build_and_render(args: argparse.Namespace) -> None:
    import bpy
    from mathutils import Vector

    frames_dir = Path(args.frames_dir)
    frames_dir.mkdir(parents=True, exist_ok=True)

    # 1. Start from Pogo_Nardus.blend so Nardus + articulated pivots/materials are intact
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

    # 4. Import both preference-only vehicles for their feature beats and finale.
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
    scene.render.resolution_x = WIDTH
    scene.render.resolution_y = HEIGHT
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
        bg.inputs[0].default_value = (0.035, 0.050, 0.078, 1.0)
        bg.inputs[1].default_value = 0.65

    # Blender 5.3.0 Compositor: Fast Bloom -> NodeGroupOutput
    scene.use_nodes = True
    ng = bpy.data.node_groups.new("SplashComp", "CompositorNodeTree")
    ng.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    scene.compositing_node_group = ng
    rl = ng.nodes.new("CompositorNodeRLayers")
    g_bloom = ng.nodes.new("CompositorNodeGlare")
    g_bloom.inputs["Type"].default_value = "Bloom"
    g_bloom.inputs["Threshold"].default_value = 2.8
    out = ng.nodes.new("NodeGroupOutput")
    ng.links.new(rl.outputs["Image"], g_bloom.inputs["Image"])
    ng.links.new(g_bloom.outputs["Image"], out.inputs["Image"])

    loaded_font = bpy.data.fonts.load(FONT_PATH) if Path(FONT_PATH).exists() else None

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

    def make_pbr(name: str, base: tuple[float, float, float, float],
                 roughness: float = 0.4, metallic: float = 0.0,
                 emit_color: tuple[float, float, float, float] | None = None,
                 emit_strength: float = 0.0):
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
    mat_banana = make_emissive("BananaMat", (1.0, 0.86, 0.05, 1.0), 1.7)
    mat_meteor = make_emissive("MeteorMat", (1.0, 0.30, 0.04, 1.0), 10.0)
    mat_flare = make_emissive("SolarFlareMat", (1.0, 0.92, 0.68, 1.0), 9.0)
    mat_nuke = make_emissive("NukeFireMat", (1.0, 0.34, 0.04, 1.0), 2.8)
    mat_shock = make_emissive("ShockRingMat", (1.0, 0.68, 0.22, 1.0), 2.4)

    # Lightning Strike Materials (Kiepie Quad signature ultimate)
    mat_bolt_core = make_emissive("BoltCoreMat", (0.58, 0.96, 1.0, 1.0), 7.0)
    mat_bolt_halo = make_emissive("BoltHaloMat", (0.08, 0.65, 1.0, 1.0), 2.2)
    mat_bolt_ring = make_emissive("BoltRingMat", (0.18, 0.85, 1.0, 1.0), 2.7)

    # New vehicle accents use the same clean, restrained glow as the older kit VFX.
    mat_evan_wave = make_emissive("EvanWaveMat", (1.0, 0.10, 0.48, 1.0), 3.8)
    mat_lea_beam = make_emissive("LeaBeamMat", (1.0, 0.80, 0.22, 1.0), 4.8)
    mat_lea_boom = make_emissive("LeaBoomMat", (0.78, 0.45, 1.0, 1.0), 3.2)

    # A machined round stage gives each featured vehicle a visible ground plane,
    # soft rim light and a consistent color cue without filling the frame with VFX.
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

    stage_accents = (
        make_emissive("StageAccentCyan", (0.12, 0.82, 1.0, 1.0), 1.6),
        make_emissive("StageAccentPink", (1.0, 0.16, 0.54, 1.0), 1.6),
        make_emissive("StageAccentGreen", (0.48, 1.0, 0.30, 1.0), 1.6),
        make_emissive("StageAccentMagenta", (1.0, 0.18, 0.46, 1.0), 1.6),
        make_emissive("StageAccentGold", (1.0, 0.68, 0.14, 1.0), 1.6),
    )
    stage_rim.data.materials[0] = stage_accents[0]
    stage_halo.data.materials[0] = stage_accents[0]

    # Cash Bag Materials (BIG-BEN F1 signature rockets & ultimate)
    mat_burlap = make_pbr(
        "CashBurlapMat",
        (0.76, 0.60, 0.36, 1.0),
        roughness=0.72,
        metallic=0.05,
        emit_color=(0.76, 0.60, 0.36, 1.0),
        emit_strength=0.28,
    )
    mat_rope = make_pbr(
        "CashRopeMat",
        (0.90, 0.68, 0.16, 1.0),
        roughness=0.35,
        metallic=0.45,
        emit_color=(1.0, 0.78, 0.18, 1.0),
        emit_strength=0.8,
    )
    mat_dollar_sign = make_pbr(
        "CashDollarSignMat",
        (0.03, 0.42, 0.12, 1.0),
        roughness=0.25,
        metallic=0.35,
        emit_color=(0.06, 0.72, 0.22, 1.0),
        emit_strength=1.15,
    )
    mat_dollar_bill = make_pbr(
        "DollarBillMat",
        (0.12, 0.76, 0.26, 1.0),
        roughness=0.35,
        metallic=0.1,
        emit_color=(0.14, 0.85, 0.28, 1.0),
        emit_strength=2.1,
    )
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
        """Build a jagged 3D Lightning Megabolt with core, plasma sheath, 4 branches, ground orb & 2 shock rings."""
        root = bpy.data.objects.new(f"{prefix}_Root", None)
        scene.collection.objects.link(root)

        main_pts = [
            (0.0, 0.0, 14.5),
            (0.55, -0.25, 12.6),
            (-0.65, 0.30, 10.8),
            (0.75, -0.20, 9.1),
            (-0.50, -0.35, 7.4),
            (0.85, 0.25, 5.8),
            (-0.70, 0.15, 4.2),
            (0.55, -0.25, 2.7),
            (-0.40, 0.10, 1.3),
            (0.0, 0.0, 0.0),
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

        rings = []
        for r_idx in range(2):
            bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.025, location=(0.0, 0.0, -50.0))
            ring = bpy.context.active_object
            ring.name = f"{prefix}_Ring_{r_idx}"
            ring.data.materials.append(mat_bolt_ring)
            rings.append(ring)

        return {"root": root, "orb": orb, "rings": rings}

    lightning_1 = build_lightning_assembly("Lightning1")
    lightning_2 = build_lightning_assembly("Lightning2")

    def build_cash_bag(name: str, scale_mult: float = 1.0):
        """Build a 3D stuffed burlap Cash Bag with rope collar, green bills on top, and extruded '$' emblems."""
        root = bpy.data.objects.new(name, None)
        scene.collection.objects.link(root)

        # Plump burlap sack body
        bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=14, radius=0.46, location=(0.0, 0.0, 0.42))
        body = bpy.context.active_object
        body.name = f"{name}_Body"
        body.scale = (1.06, 0.86, 1.02)
        body.data.materials.append(mat_burlap)
        body.parent = root

        # Cinched gold rope collar torus at neck
        bpy.ops.mesh.primitive_torus_add(major_radius=0.25, minor_radius=0.055, location=(0.0, 0.0, 0.78))
        collar = bpy.context.active_object
        collar.name = f"{name}_Collar"
        collar.scale = (1.02, 0.88, 1.0)
        collar.data.materials.append(mat_rope)
        collar.parent = root

        # Flared ruffled burlap crown top
        bpy.ops.mesh.primitive_cone_add(vertices=14, radius1=0.20, radius2=0.38, depth=0.28, location=(0.0, 0.0, 0.93))
        crown = bpy.context.active_object
        crown.name = f"{name}_Crown"
        crown.scale = (1.0, 0.86, 1.0)
        crown.data.materials.append(mat_burlap)
        crown.parent = root

        # Crisp green dollar bills poking out of top crown
        for b_idx, (bx, by, rz, rx) in enumerate([
            (-0.11, 0.02, 18.0, -14.0),
            (-0.03, -0.03, 6.0, 12.0),
            (0.05, 0.03, -8.0, -10.0),
            (0.12, -0.02, -22.0, 15.0),
        ]):
            bpy.ops.mesh.primitive_cube_add(size=0.22, location=(bx, by, 1.07))
            bill = bpy.context.active_object
            bill.name = f"{name}_TopBill_{b_idx}"
            bill.scale = (0.72, 0.14, 0.95)
            bill.rotation_euler = (math.radians(rx), math.radians(rz), math.radians(rz))
            bill.data.materials.append(mat_dollar_bill)
            bill.parent = root

        # Bold 3D extruded '$' dollar sign on front (-Y) and back (+Y)
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
        pts = [
            (-0.28, 0.0, -0.14),
            (-0.15, 0.0, 0.05),
            (0.0, 0.0, 0.12),
            (0.15, 0.0, 0.05),
            (0.28, 0.0, -0.14),
        ]
        ob = make_poly_curve(name, pts, 0.095, mat_banana)
        return ob

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
    meteors = spawn_pool("Meteor", 6, "sphere", mat_meteor)
    evan_waves = spawn_pool("EvanWave", 3, "torus", mat_evan_wave)
    lea_boom_ring = spawn_pool("LeaBoomRing", 1, "torus", mat_lea_boom)
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.045, depth=1.0, location=(0.0, 0.0, -50.0))
    lea_beam = bpy.context.active_object
    lea_beam.name = "LeaHornBeam"
    lea_beam.data.materials.append(mat_lea_beam)

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0, location=(0, 26, -50))
    solar_sphere = bpy.context.active_object
    solar_sphere.name = "SolarFlareSphere"
    solar_sphere.data.materials.append(mat_flare)

    # Mushroom cloud parts
    bpy.ops.mesh.primitive_cylinder_add(radius=1.1, depth=1.0, location=(0, 24, -50))
    nuke_stem = bpy.context.active_object
    nuke_stem.name = "NukeStem"
    nuke_stem.data.materials.append(mat_nuke)

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0, location=(0, 24, -50))
    nuke_cap = bpy.context.active_object
    nuke_cap.name = "NukeCap"
    nuke_cap.data.materials.append(mat_nuke)

    bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.03, location=(0, 24, -50))
    shock_ring = bpy.context.active_object
    shock_ring.name = "ShockRing"
    shock_ring.data.materials.append(mat_shock)

    # A readable, stylized claw silhouette for Evan's ultimate, built from a
    # few clean forms so it reads at splash-video size rather than as a particle.
    mat_demon = make_pbr(
        "DemonHandObsidian", (0.035, 0.020, 0.060, 1.0), roughness=0.24, metallic=0.72,
        emit_color=(0.22, 0.025, 0.11, 1.0), emit_strength=0.45,
    )
    mat_demon_nail = make_emissive("DemonHandNail", (1.0, 0.08, 0.27, 1.0), 2.8)
    demon_root = bpy.data.objects.new("EvanDemonHandRoot", None)
    scene.collection.objects.link(demon_root)

    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.32, depth=1.12, location=(0.0, 0.0, 0.48))
    demon_forearm = bpy.context.active_object
    demon_forearm.name = "DemonHand_Forearm"
    demon_forearm.data.materials.append(mat_demon)
    demon_forearm.parent = demon_root

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.55, location=(0.0, -0.02, 1.18))
    demon_palm = bpy.context.active_object
    demon_palm.name = "DemonHand_Palm"
    demon_palm.scale = (1.10, 0.55, 0.82)
    demon_palm.data.materials.append(mat_demon)
    demon_palm.parent = demon_root

    for i, x in enumerate((-0.38, -0.13, 0.13, 0.38)):
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.085, depth=0.62 - 0.09 * abs(i - 1.5), location=(x, -0.02, 1.74))
        finger = bpy.context.active_object
        finger.name = f"DemonHand_Finger_{i}"
        finger.rotation_euler.y = math.radians((i - 1.5) * 8.0)
        finger.data.materials.append(mat_demon)
        finger.parent = demon_root

        bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.09, radius2=0.008, depth=0.24, location=(x, -0.04, 2.13 - 0.04 * abs(i - 1.5)))
        nail = bpy.context.active_object
        nail.name = f"DemonHand_Nail_{i}"
        nail.rotation_euler.x = math.radians(12.0)
        nail.data.materials.append(mat_demon_nail)
        nail.parent = demon_root

    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.09, depth=0.44, location=(0.54, -0.02, 1.15))
    demon_thumb = bpy.context.active_object
    demon_thumb.name = "DemonHand_Thumb"
    demon_thumb.rotation_euler.y = math.radians(-48.0)
    demon_thumb.data.materials.append(mat_demon)
    demon_thumb.parent = demon_root

    # 3D Title: "Kiepie-Quad" (dark obsidian metallic front + glowing fiery gold rim backing)
    bpy.ops.object.text_add(location=(0.0, 4.0, -50.0))
    title_obj = bpy.context.active_object
    title_obj.name = "KiepieQuadTitle"
    title_obj.data.body = "Kiepie-Quad"
    title_obj.data.align_x = "CENTER"
    title_obj.data.align_y = "CENTER"
    title_obj.data.extrude = 0.14
    title_obj.data.bevel_depth = 0.022
    title_obj.data.size = 1.28
    if loaded_font:
        title_obj.data.font = loaded_font
    title_obj.rotation_euler = (math.radians(90), 0.0, 0.0)
    title_mat = make_pbr(
        "TitleMat",
        (0.18, 0.24, 0.34, 1.0),
        roughness=0.16,
        metallic=0.92,
        emit_color=(0.72, 0.84, 1.0, 1.0),
        emit_strength=0.32,
    )
    title_obj.data.materials.append(title_mat)

    bpy.ops.object.text_add(location=(0.0, 0.0, -0.10))
    title_rim = bpy.context.active_object
    title_rim.name = "KiepieQuadTitleRim"
    title_rim.data.body = "Kiepie-Quad"
    title_rim.data.align_x = "CENTER"
    title_rim.data.align_y = "CENTER"
    title_rim.data.extrude = 0.04
    title_rim.data.bevel_depth = 0.038
    title_rim.data.size = 1.28
    if loaded_font:
        title_rim.data.font = loaded_font
    title_rim.data.materials.append(make_emissive("TitleRimMat", (1.0, 0.45, 0.05, 1.0), 2.2))
    title_rim.parent = title_obj

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

    def place_cash_explosion(center: tuple[float, float, float], progress: float, f: int, bill_count: int = 36):
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
        for grp in (tracers, bananas, cash_rockets, cash_trails, dollar_bills, gold_coins, cash_rings, meteors, evan_waves, lea_boom_ring):
            for o in grp:
                o.location = (0.0, 0.0, -50.0)
        lea_beam.location = (0.0, 0.0, -50.0)
        giant_cash_bag_1.location = (0.0, 0.0, -50.0)
        giant_cash_bag_2.location = (0.0, 0.0, -50.0)
        demon_root.location = (0.0, 0.0, -80.0)
        hide_lightning(lightning_1)
        hide_lightning(lightning_2)
        solar_sphere.location = (0.0, 26.0, -50.0)
        nuke_stem.location = (0.0, 24.0, -50.0)
        nuke_cap.location = (0.0, 24.0, -50.0)
        shock_ring.location = (0.0, 24.0, -50.0)
        title_obj.location = (0.0, 4.0, -50.0)
        flare_data.energy = 0.0
        flare_data.color = (1.0, 0.82, 0.42)

    def spin_wheels(wheels: list, f: int, rate: float = 0.48):
        for w in wheels:
            w.rotation_euler.x = -f * rate

    def play_rig_action(rig, action_name: str, phase: float) -> None:
        """Play one imported glTF NLA clip at a normalized point in its range."""
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
        stage_halo.hide_render = False
        stage_rim.data.materials[0] = accent
        stage_halo.data.materials[0] = accent

    def apply_frame(f: int) -> None:
        hide_all_vfx()
        cam_data.lens = 42.0
        quad_root.location = (0.0, 0.0, -50.0)
        nardus_root.location = (0.0, 0.0, -50.0)
        aston_root.location = (0.0, 0.0, -50.0)
        evan_root.location = (0.0, 0.0, -50.0)
        lea_root.location = (0.0, 0.0, -50.0)
        stage_root.location = (0.0, 0.0, -80.0)
        stage_halo.hide_render = True
        demon_root.location = (0.0, 0.0, -80.0)
        if nardus_arm_l:
            nardus_arm_l.rotation_euler = (0.0, 0.0, 0.0)
        if nardus_arm_r:
            nardus_arm_r.rotation_euler = (0.0, 0.0, 0.0)

        if f < 60:
            # -----------------------------------------------------------------
            # Act 1 (f = 0..59): KIEPIE QUAD — TWIN CANNONS & LIGHTNING STRIKE.
            # -----------------------------------------------------------------
            t = f / 59.0
            quad_root.location = (-0.55 + 1.1 * t, -0.35 + 0.55 * t, 0.01)
            quad_root.rotation_euler = (
                0.0,
                math.radians(-5.0 * math.sin(t * math.pi)),
                math.radians(150.0 - 18.0 * t),
            )
            spin_wheels(quad_wheels, f, 0.52)
            show_hero_stage(quad_root.location, 0)
            bpy.context.view_layer.update()

            cam_obj.location = (quad_root.location.x + 1.85, quad_root.location.y - 3.2, 2.15)
            cam_target.location = (quad_root.location.x + 0.10, quad_root.location.y + 0.10, 0.82)
            cam_data.lens = 40.0

            # Twin cyan autocannon tracers
            for i, tr in enumerate(tracers):
                phase = ((f * 0.42 + i * 0.25) % 1.0)
                side = -0.42 if i % 2 == 0 else 0.42
                fwd = quad_root.matrix_world.to_quaternion() @ Vector((side, -1.0 - 10.0 * phase, 0.58))
                tr.location = quad_root.location + fwd
                tr.rotation_euler = (math.radians(90), 0.0, quad_root.rotation_euler.z)

            # Lightning arrives behind and to one side of the bike, inside frame.
            if f >= 25:
                lp = min(1.0, (f - 25) / 30.0)
                strike_pos = (quad_root.location.x + 1.65, quad_root.location.y + 1.45, 0.0)
                place_lightning(lightning_1, strike_pos, lp, f, scale=0.46)
                flare_light.location = (strike_pos[0], strike_pos[1], 3.5)
                flare_data.color = (0.45, 0.94, 1.0)
                flare_data.energy = 400.0 * (1.0 - 0.35 * lp) * (0.75 + 0.25 * abs(math.sin(f * 2.3)))

        elif f < 120:
            # -----------------------------------------------------------------
            # Act 2 (f = 60..119): NARDUS — POGO HOP, BANANAS & METEOR SHOWER.
            # -----------------------------------------------------------------
            t = (f - 60) / 59.0
            hop = abs(math.sin(t * math.pi * 3.0)) * 0.62
            nardus_root.location = (-0.45 + 0.9 * t, -0.18, 0.01 + hop)
            nardus_root.rotation_euler = (
                math.radians(9.0 * math.cos(t * math.pi * 4.0)),
                0.0,
                math.radians(-8.0 + 16.0 * t),
            )
            flap = math.sin(f * 0.85) * 0.65
            if nardus_arm_l:
                nardus_arm_l.rotation_euler = (0.0, flap, 0.0)
            if nardus_arm_r:
                nardus_arm_r.rotation_euler = (0.0, -flap, 0.0)

            show_hero_stage(nardus_root.location, 1)
            cam_obj.location = (nardus_root.location.x + 1.55, nardus_root.location.y - 4.0, 2.15)
            cam_target.location = (nardus_root.location.x, nardus_root.location.y + 0.08, 1.36 + hop * 0.30)
            cam_data.lens = 31.5
            # Hold Nardus's front-facing source pose while the shot uses its own hop.
            scene.frame_set(120)

            for i, bn in enumerate(bananas):
                phase = (((f - 60) * 0.22 + i * 0.14) % 1.0)
                side = (-1.0 if i % 2 == 0 else 1.0) * (0.55 + 0.22 * (i % 3))
                bn.location = nardus_root.location + Vector((
                    side - 1.0 * phase,
                    0.5 + 2.2 * phase,
                    0.95 + 0.65 * math.sin(phase * math.pi),
                ))
                bn.rotation_euler = (f * 0.35 + i, f * 0.28, f * 0.45 + i * 0.5)
                bn.scale = (0.34, 0.34, 0.34)

            # A clear shower of small hot meteors drops behind the pogo rider.
            for i, meteor in enumerate(meteors):
                phase = ((t * 1.5 + i / len(meteors)) % 1.0)
                xoff = (-1.8, -1.05, -0.3, 0.45, 1.1, 1.8)[i]
                meteor.location = (nardus_root.location.x + xoff, 1.15, 5.4 - phase * 4.6)
                meteor.scale = (0.18, 0.18, 0.38)
                meteor.rotation_euler = (f * 0.12 + i, f * 0.21, f * 0.17)
            shock_ring.location = (nardus_root.location.x + 0.8, 1.05, 0.04)
            ring_p = max(0.0, min(1.0, ((f - 88) / 26.0)))
            shock_ring.scale = (0.55 + ring_p * 1.85, 0.55 + ring_p * 1.85, 0.16)

        elif f < 180:
            # -----------------------------------------------------------------
            # Act 3 (f = 120..179): BIG-BEN F1 — CASH-BAG ROCKETS & METEOR DROP.
            # -----------------------------------------------------------------
            t = (f - 120) / 59.0
            aston_root.location = (-0.45 + 0.9 * t, -0.3 + 0.35 * t, 0.01)
            aston_root.rotation_euler = (
                0.0,
                math.radians(-3.5 * math.sin(t * math.pi * 2.0)),
                math.radians(-135.0 + 12.0 * t),
            )
            spin_wheels(aston_wheels, f, 0.62)
            show_hero_stage(aston_root.location, 2)
            bpy.context.view_layer.update()

            cam_obj.location = (aston_root.location.x - 1.9, aston_root.location.y - 3.45, 1.95)
            cam_target.location = (aston_root.location.x, aston_root.location.y + 0.05, 0.72)
            cam_data.lens = 38.0

            # Small '$' Cash Bag Rockets fired horizontally from BIG-BEN F1's front muzzles
            for i, bag_rk in enumerate(cash_rockets):
                phase = (((f - 120) * 0.11 + i * 0.24) % 1.0)
                side = -0.38 if i % 2 == 0 else 0.38
                local_offset = Vector((side, -1.35 - 7.2 * phase, 0.42 + 0.25 * math.sin(phase * math.pi)))
                world_pos = aston_root.location + (aston_root.matrix_world.to_quaternion() @ local_offset)
                bag_rk.location = world_pos
                bag_rk.rotation_euler = (
                    math.radians(18.0 * math.sin(f * 0.3 + i)),
                    math.radians(14.0 * math.cos(f * 0.25 + i)),
                    aston_root.rotation_euler.z,
                )
                tr = cash_trails[i]
                trail_off = Vector((side, -0.55 - 7.2 * phase, 0.42 + 0.25 * math.sin(phase * math.pi)))
                tr.location = aston_root.location + (aston_root.matrix_world.to_quaternion() @ trail_off)
                tr.rotation_euler = (math.radians(90), 0.0, aston_root.rotation_euler.z)

            # The cash meteor lands behind the car, then opens into a tight readable shower.
            strike_xy = (aston_root.location.x + 1.8, aston_root.location.y + 1.45)
            if f >= 138:
                if f < 153:
                    drop_p = (f - 138) / 15.0
                    gz = 6.2 * (1.0 - drop_p ** 1.6)
                    giant_cash_bag_1.location = (strike_xy[0], strike_xy[1], max(0.0, gz))
                    giant_cash_bag_1.rotation_euler = (0.0, 0.0, math.radians(-22.0))
                else:
                    exp_p = min(1.0, (f - 153) / 24.0)
                    squash = 1.0 + 0.14 * math.sin(exp_p * math.pi * 2.0) * (1.0 - exp_p)
                    giant_cash_bag_1.location = (strike_xy[0], strike_xy[1], 0.0)
                    giant_cash_bag_1.scale = (2.35 * squash, 2.35 * squash, 2.35 / squash)
                    giant_cash_bag_1.rotation_euler = (0.0, 0.0, math.radians(-20.0))
                    place_cash_explosion((strike_xy[0], strike_xy[1], 0.0), exp_p, f, bill_count=30)
                    flare_light.location = (strike_xy[0], strike_xy[1], 3.0)
                    flare_data.color = (0.35, 1.0, 0.45)
                    flare_data.energy = 400.0 * (1.0 - 0.45 * exp_p)

        elif f < 300:
            # -----------------------------------------------------------------
            # Acts 4-5 (f = 180..299): EVAN and LEA get equal animated spotlights.
            # -----------------------------------------------------------------
            if f < 240:
                t = (f - 180) / 59.0
                evan_root.location = (0.0, -0.18 + 0.35 * t, 0.01 + 0.06 * abs(math.sin(t * math.pi * 2.0)))
                evan_root.scale = (0.96, 0.96, 0.96)
                evan_root.rotation_euler = (0.0, 0.0, math.radians(5.0 * math.sin(t * math.pi)))
                show_hero_stage(evan_root.location, 3)
                cam_obj.location = (1.75, -3.55, 1.88)
                cam_target.location = (0.0, -0.05, 1.12)
                cam_data.lens = 40.0

                if t < 0.40:
                    play_rig_action(evan_rig, "Play_Strum", (t / 0.40 * 2.0) % 1.0)
                elif t < 0.76:
                    play_rig_action(evan_rig, "Action_GuitarThrow", (t - 0.40) / 0.36)
                else:
                    play_rig_action(evan_rig, "Action_GuitarCatch", (t - 0.76) / 0.24)

                for i, wave_ring in enumerate(evan_waves):
                    wave_ring.location = (0.15, 0.24 + 0.32 * i, 1.16)
                    wave_ring.rotation_euler = (math.radians(90), 0.0, 0.0)
                    size = 0.18 + ((t * 1.4 + i * 0.38) % 1.0) * 0.32
                    wave_ring.scale = (size, size, size)

                if t >= 0.56:
                    demon_root.location = (1.08, 1.0, -0.18 + 0.18 * min(1.0, (t - 0.56) / 0.22))
                    demon_root.scale = (0.84, 0.84, 0.84)
                    shock_ring.location = (1.08, 0.92, 0.04)
                    shock_ring.data.materials[0] = mat_evan_wave
                    rp = min(1.0, (t - 0.56) / 0.32)
                    shock_ring.scale = (0.45 + 1.55 * rp, 0.45 + 1.55 * rp, 0.16)
            else:
                t = (f - 240) / 59.0
                lea_root.location = (0.0, -0.16 + 0.25 * t, 0.01 + 0.10 * abs(math.sin(t * math.pi * 1.5)))
                lea_root.scale = (0.98, 0.98, 0.98)
                lea_root.rotation_euler = (0.0, 0.0, math.radians(-4.0 + 7.0 * t))
                show_hero_stage(lea_root.location, 4)
                cam_obj.location = (1.75, -3.95, 2.10)
                cam_target.location = (0.0, -0.04, 1.30)
                cam_data.lens = 34.0

                if t < 0.25:
                    play_rig_action(lea_rig, "Locomotion_Gallop", t / 0.25)
                elif t < 0.48:
                    play_rig_action(lea_rig, "Action_WingSpread", (t - 0.25) / 0.23)
                else:
                    play_rig_action(lea_rig, "UnicornBoom_Flight", (t - 0.48) / 0.52)

                if 0.20 <= t <= 0.60:
                    beam_strength = max(0.18, math.sin(math.pi * (t - 0.20) / 0.40))
                    lea_beam.location = (0.0, -0.95, 1.25)
                    lea_beam.rotation_euler = (math.radians(90), 0.0, 0.0)
                    lea_beam.scale = (1.0, 1.0, 1.95 * beam_strength)
                lea_boom_ring[0].location = (0.0, 0.24, 0.055)
                ring_size = 0.55 + 1.65 * max(0.0, min(1.0, (t - 0.54) / 0.40))
                lea_boom_ring[0].scale = (ring_size, ring_size, 0.12)

        else:
            # -----------------------------------------------------------------
            # Act 6 (f = 300..359): all five rides in one clean closing lineup.
            # -----------------------------------------------------------------
            cam_obj.location = (0.0, -12.2, 3.35)
            cam_target.location = (0.0, -1.1, 1.12)
            cam_data.lens = 40.0

            quad_root.location = (-3.8, -1.4, 0.01)
            quad_root.rotation_euler = (0.0, 0.0, math.radians(-25.0))
            quad_root.scale = (0.86, 0.86, 0.86)
            nardus_root.location = (-1.9, -1.4, 0.01 + 0.10 * abs(math.sin((f - 300) * 0.22)))
            nardus_root.rotation_euler = (0.0, 0.0, math.radians(4.0))
            nardus_root.scale = (0.80, 0.80, 0.80)
            aston_root.location = (0.0, -1.4, 0.01)
            aston_root.rotation_euler = (0.0, 0.0, math.radians(24.0))
            aston_root.scale = (0.70, 0.70, 0.70)
            evan_root.location = (1.9, -1.4, 0.01)
            evan_root.rotation_euler = (0.0, 0.0, math.radians(5.0))
            evan_root.scale = (0.88, 0.88, 0.88)
            lea_root.location = (3.8, -1.4, 0.01)
            lea_root.rotation_euler = (0.0, 0.0, math.radians(90.0))
            lea_root.scale = (0.82, 0.82, 0.82)
            spin_wheels(quad_wheels, f, 0.55)
            spin_wheels(aston_wheels, f, 0.58)

            p = min(1.0, max(0.0, (f - 300) / 59.0))
            flare_light.location = (0.0, 2.0, 4.0)
            flare_data.color = (0.58, 0.72, 1.0)
            flare_data.energy = 200.0 + 90.0 * math.sin(math.pi * p)
            shock_ring.location = (0.0, 1.7, 0.08)
            shock_ring.data.materials[0] = mat_bolt_ring
            ring_size = 3.8 + 0.16 * math.sin(f * 0.12)
            shock_ring.scale = (ring_size, ring_size, 0.12)

            # The imported rig clips keep the finale alive but subtle.
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
    if args.encode_only:
        encode_video(Path(args.frames_dir))
    else:
        build_and_render(args)


if __name__ == "__main__":
    main()
