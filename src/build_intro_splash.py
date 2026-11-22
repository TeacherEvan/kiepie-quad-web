#!/usr/bin/env python3
"""
Build the 12.5-second (300 frames @ 24 fps, 1280x720) action-packed intro splash
video for Kiepie-Quad (`web-assets/kiepie-quad-splash.mp4`) using Blender 5.3.0
EEVEE + Compositor + 48 kHz stereo SFX/procedural audio mix.

Usage:
  # Preview 7 keyframes:
  blender -b -noaudio -P src/build_intro_splash.py -- \
      --preview-frames 25,85,145,190,222,250,285 --frames-dir /tmp/kiepie_splash_preview

  # Render frame range (e.g. parallel shards):
  blender -b -noaudio -P src/build_intro_splash.py -- --start 0 --end 149 --frames-dir /tmp/kiepie_splash_frames
  blender -b -noaudio -P src/build_intro_splash.py -- --start 150 --end 299 --frames-dir /tmp/kiepie_splash_frames

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
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_MP4 = ROOT / "web-assets" / "kiepie-quad-splash.mp4"
SFX_DIR = ROOT / "godot" / "assets" / "sfx"
FONT_PATH = "/usr/share/fonts/truetype/roboto/unhinted/RobotoTTF/Roboto-Black.ttf"

FPS = 24
TOTAL_FRAMES = 300  # 12.5 s
WIDTH = 1280
HEIGHT = 720


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    else:
        argv = argv[1:]
    p = argparse.ArgumentParser(description="Render Kiepie-Quad intro splash video.")
    p.add_argument("--frames-dir", type=str, default="/tmp/kiepie_splash_frames")
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


def synthesize_audio(wav_out: Path) -> None:
    sr = 48000
    dur_s = TOTAL_FRAMES / FPS  # 12.5 s
    n_samples = int(dur_s * sr)
    buf_l = [0.0] * n_samples
    buf_r = [0.0] * n_samples

    engine = _read_wav_mono(SFX_DIR / "engine_loop.wav", sr)
    turbo = _read_wav_mono(SFX_DIR / "turbo.wav", sr)
    cannon = _read_wav_mono(SFX_DIR / "cannon_fire.wav", sr)
    pop = _read_wav_mono(SFX_DIR / "pop.wav", sr)
    explosion = _read_wav_mono(SFX_DIR / "explosion.wav", sr)
    impact = _read_wav_mono(SFX_DIR / "impact.wav", sr)

    # Act 1 (0.0 - 2.5s): Engine roar + autocannon bursts
    _mix_clip(buf_l, buf_r, engine, 0.0, gain=0.45, pan=-0.2, sr=sr)
    _mix_clip(buf_l, buf_r, turbo, 0.4, gain=0.40, pan=0.1, sr=sr)
    for t in (0.35, 0.55, 0.75, 0.95, 1.15, 1.35, 1.55, 1.75, 1.95):
        _mix_clip(buf_l, buf_r, cannon, t, gain=0.50, pan=-0.15, sr=sr)

    # Act 2 (2.5 - 5.0s): Pogo pops + banana fire
    for t in (2.6, 3.0, 3.35, 3.7, 4.05, 4.4):
        _mix_clip(buf_l, buf_r, pop, t, gain=0.65, pan=0.2, sr=sr)

    # Act 3 (5.0 - 7.0s): Duel + rockets + explosion
    _mix_clip(buf_l, buf_r, turbo, 5.0, gain=0.50, pan=0.0, sr=sr)
    for t in (5.2, 5.45, 5.7, 6.0):
        _mix_clip(buf_l, buf_r, cannon, t, gain=0.45, pan=-0.3, sr=sr)
    _mix_clip(buf_l, buf_r, explosion, 6.3, gain=0.75, pan=0.1, sr=sr)

    # Act 4 (7.0 - 8.75s): Meteor impacts
    for idx, t in enumerate((7.2, 7.55, 7.9, 8.25)):
        _mix_clip(buf_l, buf_r, impact, t, gain=0.65, pan=(-0.4 + 0.25 * idx), sr=sr)

    # Act 5 (8.75 - 12.5s): Solar flare riser -> Nuclear shockwave boom
    rng = random.Random(42)
    for i in range(int(8.75 * sr), n_samples):
        t = i / sr
        if 8.75 <= t < 9.8:
            # Solar flare high-energy riser
            p = (t - 8.75) / 1.05
            freq = 110.0 + 520.0 * (p ** 2)
            s = 0.35 * p * math.sin(2.0 * math.pi * freq * t)
            buf_l[i] += s
            buf_r[i] += s
        elif t >= 9.8:
            # Nuclear sub-bass + rumble
            dt = t - 9.8
            env = math.exp(-dt * 0.85)
            sub = 0.85 * env * math.sin(2.0 * math.pi * (48.0 * math.exp(-dt * 0.4) + 28.0) * dt)
            noise = 0.35 * math.exp(-dt * 1.4) * (rng.random() * 2.0 - 1.0)
            buf_l[i] += sub + noise
            buf_r[i] += sub + noise

    _mix_clip(buf_l, buf_r, explosion, 9.8, gain=0.95, pan=0.0, sr=sr)
    _mix_clip(buf_l, buf_r, explosion, 10.15, gain=0.60, pan=-0.25, sr=sr)

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
    cmd = [
        "ffmpeg",
        "-y",
        "-framerate", str(FPS),
        "-i", str(frames_dir / "frame_%04d.png"),
        "-i", str(wav_path),
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-crf", "21",
        "-preset", "medium",
        "-movflags", "+faststart",
        "-c:a", "aac",
        "-b:a", "160k",
        "-shortest",
        str(tmp_mp4),
    ]
    subprocess.run(cmd, check=True, timeout=120)
    os.replace(tmp_mp4, OUT_MP4)
    print(f"Encoded {OUT_MP4} ({OUT_MP4.stat().st_size / 1024:.1f} KiB)")


# ---------------------------------------------------------------------------
# Blender 5.3.0 Scene & VFX Builder
# ---------------------------------------------------------------------------

def build_and_render(args: argparse.Namespace) -> None:
    import bpy
    from mathutils import Vector

    frames_dir = Path(args.frames_dir)
    frames_dir.mkdir(parents=True, exist_ok=True)

    # Start from Pogo_Nardus.blend so Nardus + materials are intact
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / "Pogo_Nardus.blend"))
    scene = bpy.context.scene

    # Remove ProofFloor if present
    for obj in list(bpy.data.objects):
        if obj.name == "ProofFloor" or obj.type in ("CAMERA", "LIGHT"):
            bpy.data.objects.remove(obj, do_unlink=True)

    # Group Nardus under an empty root
    nardus_root = bpy.data.objects.new("NardusRoot", None)
    scene.collection.objects.link(nardus_root)
    nardus_objs = [o for o in bpy.data.objects if o != nardus_root]
    for o in nardus_objs:
        o.rotation_mode = "XYZ"
        if o.parent is None:
            o.parent = nardus_root

    # Import Kiepie_Bike.glb
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "godot" / "assets" / "Kiepie_Bike.glb"))
    after = set(bpy.data.objects)
    quad_root = bpy.data.objects.new("QuadRoot", None)
    scene.collection.objects.link(quad_root)
    for o in after - before:
        o.rotation_mode = "XYZ"
        if o.parent is None:
            o.parent = quad_root

    # Configure EEVEE + Render
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = 12
    scene.render.resolution_x = WIDTH
    scene.render.resolution_y = HEIGHT
    scene.render.resolution_percentage = 100
    scene.render.fps = FPS
    scene.frame_start = 0
    scene.frame_end = TOTAL_FRAMES - 1
    scene.render.image_settings.file_format = "PNG"

    # Dark volcanic/cyber arena world
    world = scene.world or bpy.data.worlds.new("SplashWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.015, 0.018, 0.032, 1.0)
        bg.inputs[1].default_value = 0.8

    # Blender 5.3.0 Compositor: Bloom + Streaks + Lensdist -> NodeGroupOutput
    scene.use_nodes = True
    ng = bpy.data.node_groups.new("SplashComp", "CompositorNodeTree")
    ng.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    scene.compositing_node_group = ng
    rl = ng.nodes.new("CompositorNodeRLayers")
    g_bloom = ng.nodes.new("CompositorNodeGlare")
    g_bloom.inputs["Type"].default_value = "Bloom"
    g_bloom.inputs["Threshold"].default_value = 0.85
    g_streaks = ng.nodes.new("CompositorNodeGlare")
    g_streaks.inputs["Type"].default_value = "Streaks"
    g_streaks.inputs["Threshold"].default_value = 1.4
    ld = ng.nodes.new("CompositorNodeLensdist")
    ld.inputs["Dispersion"].default_value = 0.008
    out = ng.nodes.new("NodeGroupOutput")
    ng.links.new(rl.outputs["Image"], g_bloom.inputs["Image"])
    ng.links.new(g_bloom.outputs["Image"], g_streaks.inputs["Image"])
    ng.links.new(g_streaks.outputs["Image"], ld.inputs["Image"])
    ng.links.new(ld.outputs["Image"], out.inputs["Image"])

    # Helper for emissive materials
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

    # Arena floor
    bpy.ops.mesh.primitive_plane_add(size=180.0, location=(0.0, 0.0, 0.0))
    floor = bpy.context.active_object
    floor.name = "ArenaFloor"
    floor_mat = bpy.data.materials.new("ArenaFloorMat")
    floor_mat.use_nodes = True
    bsdf = floor_mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.04, 0.045, 0.06, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.28
        bsdf.inputs["Metallic"].default_value = 0.35
    floor.data.materials.append(floor_mat)

    # Lights: ONLY SunKey casts shadows (Blender 5.3 Vulkan shadow buffer rule)
    sun_data = bpy.data.lights.new("SunKey", type="SUN")
    sun_data.energy = 3.2
    sun_data.color = (1.0, 0.92, 0.80)
    sun_data.use_shadow = True
    sun_obj = bpy.data.objects.new("SunKey", sun_data)
    sun_obj.rotation_euler = (math.radians(48), math.radians(15), math.radians(-35))
    scene.collection.objects.link(sun_obj)

    rim_data = bpy.data.lights.new("RimCool", type="AREA")
    rim_data.energy = 450.0
    rim_data.color = (0.25, 0.72, 1.0)
    rim_data.size = 10.0
    rim_data.use_shadow = False
    rim_obj = bpy.data.objects.new("RimCool", rim_data)
    rim_obj.location = (-8.0, 12.0, 6.0)
    rim_obj.rotation_euler = (math.radians(65), 0.0, math.radians(-145))
    scene.collection.objects.link(rim_obj)

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
    cam_data.lens = 34.0
    cam_data.clip_end = 500.0
    cam_obj = bpy.data.objects.new("SplashCam", cam_data)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj
    track = cam_obj.constraints.new("TRACK_TO")
    track.target = cam_target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"

    # VFX Props
    mat_tracer = make_emissive("TracerMat", (0.2, 0.95, 1.0, 1.0), 18.0)
    mat_banana = make_emissive("BananaMat", (1.0, 0.85, 0.08, 1.0), 6.0)
    mat_rocket = make_emissive("RocketMat", (1.0, 0.35, 0.05, 1.0), 22.0)
    mat_meteor = make_emissive("MeteorMat", (1.0, 0.25, 0.03, 1.0), 26.0)
    mat_flare = make_emissive("SolarFlareMat", (1.0, 0.94, 0.72, 1.0), 85.0)
    mat_nuke = make_emissive("NukeFireMat", (1.0, 0.36, 0.04, 1.0), 10.0)
    mat_shock = make_emissive("ShockRingMat", (1.0, 0.78, 0.35, 1.0), 16.0)

    def spawn_pool(name_prefix: str, count: int, kind: str, mat):
        items = []
        for i in range(count):
            if kind == "sphere":
                bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=(0, 0, -50))
            elif kind == "torus":
                bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.22, location=(0, 0, -50))
            elif kind == "cyl":
                bpy.ops.mesh.primitive_cylinder_add(radius=0.05, depth=1.2, location=(0, 0, -50))
            else:
                bpy.ops.mesh.primitive_cube_add(size=0.35, location=(0, 0, -50))
            o = bpy.context.active_object
            o.name = f"{name_prefix}_{i}"
            o.data.materials.append(mat)
            items.append(o)
        return items

    tracers = spawn_pool("Tracer", 8, "cyl", mat_tracer)
    bananas = spawn_pool("Banana", 6, "cube", mat_banana)
    rockets = spawn_pool("Rocket", 4, "cyl", mat_rocket)
    meteors = spawn_pool("Meteor", 6, "sphere", mat_meteor)

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0, location=(0, 26, 7.5))
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

    bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.14, location=(0, 24, -50))
    shock_ring = bpy.context.active_object
    shock_ring.name = "ShockRing"
    shock_ring.data.materials.append(mat_shock)

    # 3D Title: "Kiepie-Quad"
    bpy.ops.object.text_add(location=(0.0, 4.0, -50.0))
    title_obj = bpy.context.active_object
    title_obj.name = "KiepieQuadTitle"
    title_obj.data.body = "Kiepie-Quad"
    title_obj.data.align_x = "CENTER"
    title_obj.data.align_y = "CENTER"
    title_obj.data.extrude = 0.14
    title_obj.data.bevel_depth = 0.025
    title_obj.data.size = 1.35
    if Path(FONT_PATH).exists():
        title_obj.data.font = bpy.data.fonts.load(FONT_PATH)
    title_obj.rotation_euler = (math.radians(90), 0.0, 0.0)
    title_mat = bpy.data.materials.new("TitleMat")
    title_mat.use_nodes = True
    t_bsdf = title_mat.node_tree.nodes.get("Principled BSDF")
    if t_bsdf:
        t_bsdf.inputs["Base Color"].default_value = (0.04, 0.05, 0.08, 1.0)
        t_bsdf.inputs["Metallic"].default_value = 0.92
        t_bsdf.inputs["Roughness"].default_value = 0.18
    title_obj.data.materials.append(title_mat)

    def hide_all_vfx():
        for grp in (tracers, bananas, rockets, meteors):
            for o in grp:
                o.location = (0.0, 0.0, -50.0)
        solar_sphere.location = (0.0, 26.0, -50.0)
        nuke_stem.location = (0.0, 24.0, -50.0)
        nuke_cap.location = (0.0, 24.0, -50.0)
        shock_ring.location = (0.0, 24.0, -50.0)
        title_obj.location = (0.0, 4.0, -50.0)
        flare_data.energy = 0.0

    def apply_frame(f: int) -> None:
        hide_all_vfx()
        quad_root.location = (0.0, 0.0, -50.0)
        nardus_root.location = (0.0, 0.0, -50.0)

        if f < 60:
            # Act 1: Kiepie Quad + Side Autocannons
            t = f / 59.0
            quad_root.location = (-3.5 + 7.0 * t, -2.0 + 4.0 * t, 0.0)
            quad_root.rotation_euler = (0.0, math.radians(-8.0 * math.sin(t * math.pi)), math.radians(155.0 - 30.0 * t))
            bpy.context.view_layer.update()
            cam_obj.location = (quad_root.location.x + 3.2, quad_root.location.y - 4.2, 1.85)
            cam_target.location = (quad_root.location.x, quad_root.location.y, 0.65)
            for i, tr in enumerate(tracers):
                phase = ((f * 0.38 + i * 0.25) % 1.0)
                side = -0.4 if i % 2 == 0 else 0.4
                fwd = quad_root.matrix_world.to_quaternion() @ Vector((side, -1.2 - 14.0 * phase, 0.57))
                tr.location = quad_root.location + fwd
                tr.rotation_euler = (math.radians(90), 0.0, quad_root.rotation_euler.z)

        elif f < 120:
            # Act 2: Nardus Pogo + Banana Cannons
            t = (f - 60) / 59.0
            hop = abs(math.sin(t * math.pi * 4.0)) * 1.15
            nardus_root.location = (2.5 - 5.0 * t, 0.0, hop)
            nardus_root.rotation_euler = (math.radians(8.0 * math.cos(t * math.pi * 4.0)), 0.0, math.radians(-145.0 + 35.0 * t))
            cam_obj.location = (nardus_root.location.x - 3.4, nardus_root.location.y - 4.0, 2.0)
            cam_target.location = (nardus_root.location.x, nardus_root.location.y, 1.1 + hop * 0.5)
            for i, bn in enumerate(bananas):
                phase = ((f * 0.28 + i * 0.33) % 1.0)
                bn.location = nardus_root.location + Vector(((-1 if i % 2 == 0 else 1) * 0.5, -1.5 - 10.0 * phase, 1.0 + math.sin(phase * math.pi)))
                bn.rotation_euler = (f * 0.4, f * 0.3, f * 0.5)
                bn.scale = (0.6, 1.3, 0.45)

        elif f < 168:
            # Act 3: Head-to-head Duel + Heavy Rockets
            t = (f - 120) / 47.0
            quad_root.location = (-3.2 + 2.0 * t, 1.0, 0.0)
            quad_root.rotation_euler = (0.0, 0.0, math.radians(-110.0))
            nardus_root.location = (3.2 - 2.0 * t, 1.0, abs(math.sin(t * math.pi * 3.0)) * 0.9)
            nardus_root.rotation_euler = (0.0, 0.0, math.radians(105.0))
            cam_obj.location = (0.0, -6.5, 2.6)
            cam_target.location = (0.0, 1.0, 0.9)
            for i, rk in enumerate(rockets):
                phase = ((f * 0.22 + i * 0.25) % 1.0)
                rk.location = Vector((-2.0 + 4.0 * phase, 1.0, 0.8 + 0.3 * math.sin(phase * math.pi)))
                rk.rotation_euler = (0.0, math.radians(90), 0.0)
                rk.scale = (1.6, 1.6, 1.2)

        elif f < 210:
            # Act 4: Meteor Shower
            t = (f - 168) / 41.0
            quad_root.location = (-2.0 + 4.0 * t, -1.0, 0.0)
            quad_root.rotation_euler = (0.0, 0.0, math.radians(-140.0))
            cam_obj.location = (0.0, -9.5, 3.8)
            cam_target.location = (0.0, 2.0, 1.5)
            for i, mt in enumerate(meteors):
                phase = ((f * 0.16 + i * 0.19) % 1.0)
                mx = -6.0 + i * 2.4
                my = 2.0 + (i % 3) * 2.5
                mz = 14.0 * (1.0 - phase)
                mt.location = (mx, my, max(0.3, mz))
                mt.scale = (0.65, 0.65, 0.65)

        else:
            # Act 5: Solar Flare (210-234) -> Nuclear Mushroom Cloud (235-265) -> Title (260-299)
            cam_obj.location = (0.0, -9.5, 2.5)
            cam_target.location = (0.0, 16.0, 4.2)

            if f < 235:
                p = (f - 210) / 24.0
                solar_sphere.location = (0.0, 26.0, 7.5)
                s = 0.6 + 5.5 * (p ** 1.6)
                solar_sphere.scale = (s, s, s)
                flare_data.energy = 15000.0 * (p ** 1.5)
            else:
                p = min(1.0, (f - 235) / 35.0)
                flare_data.energy = max(2500.0, 14000.0 * (1.0 - p * 0.7))
                # Mushroom stem & cap
                stem_h = 1.0 + 7.5 * p
                nuke_stem.location = (0.0, 24.0, stem_h * 0.5)
                nuke_stem.scale = (1.1 + 0.6 * p, 1.1 + 0.6 * p, stem_h)
                nuke_cap.location = (0.0, 24.0, stem_h + 1.2)
                cap_r = 1.8 + 4.2 * (p ** 0.7)
                nuke_cap.scale = (cap_r, cap_r, cap_r * 0.58)
                # Shockwave ring
                shock_ring.location = (0.0, 24.0, 0.25)
                sr_scale = 2.0 + 18.0 * p
                shock_ring.scale = (sr_scale, sr_scale, 0.5)

            if f >= 258:
                tp = min(1.0, (f - 258) / 22.0)
                ease = 1.0 - (1.0 - tp) ** 3
                title_obj.location = (0.0, 2.5, 2.5 + (1.0 - ease) * 3.5)
                sc = 0.4 + 0.65 * ease
                title_obj.scale = (sc, sc, sc)

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
