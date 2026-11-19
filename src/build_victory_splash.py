#!/usr/bin/env python3
"""
Renders web-assets/kiepie-victory-splash.mp4 — the celebratory Victory Splash
video triggered when a player wins Death Race or Battle Royale.
Loads Pogo_Nardus.blend directly (preserving rich crimson shirt materials and
back-of-shirt NARDUS gold decal), imports Kiepie_Bike.glb beside him on a
checkered winner's podium, animates Nardus hopping and flapping his arms like
a bird (setting rotation_mode = 'XYZ'), and muxes a celebratory synth fanfare.
Run:
    blender -b -noaudio -P src/build_victory_splash.py
"""
import math
import os
import shutil
import struct
import subprocess
import tempfile
import wave
import bpy
from mathutils import Vector

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_MP4 = os.path.join(REPO_ROOT, "web-assets", "kiepie-victory-splash.mp4")
NARDUS_BLEND = os.path.join(REPO_ROOT, "Pogo_Nardus.blend")
BIKE_GLB = os.path.join(REPO_ROOT, "godot", "assets", "Kiepie_Bike.glb")

# Open Pogo_Nardus.blend directly so native Blender materials (crimson shirt + gold decal) are intact!
bpy.ops.wm.open_mainfile(filepath=NARDUS_BLEND)
scene = bpy.context.scene

nardus_rider = bpy.data.objects.get("Rider")
nardus_stick = bpy.data.objects.get("Stick")
arm_l = bpy.data.objects.get("Arm_L")
arm_r = bpy.data.objects.get("Arm_R")
proof_floor = bpy.data.objects.get("ProofFloor")
if proof_floor is not None:
    bpy.data.objects.remove(proof_floor, do_unlink=True)

# Ensure Euler XYZ rotation mode on Rider, Stick, and Arms so animation keyframes/loops take effect!
for ob in (nardus_rider, nardus_stick, arm_l, arm_r):
    if ob is not None:
        ob.rotation_mode = "XYZ"

for ob in (nardus_rider, nardus_stick):
    if ob is not None:
        ob.location.x = 0.72
        ob.location.y = -0.05

# Import Kiepie_Bike.glb on the left side of the podium in a heroic wheelie pose
before_objs = set(bpy.data.objects)
if os.path.exists(BIKE_GLB):
    bpy.ops.import_scene.gltf(filepath=BIKE_GLB)
after_objs = set(bpy.data.objects) - before_objs
bike_root = bpy.data.objects.new("VictoryBikeRoot", None)
scene.collection.objects.link(bike_root)
for ob in after_objs:
    if ob.parent is None:
        ob.parent = bike_root
bike_root.rotation_mode = "XYZ"
bike_root.location = (-0.82, 0.05, 0.14)
bike_root.rotation_euler = (math.radians(16.0), 0.0, math.radians(-22.0))


def make_mat(name, color, rough=0.35, metal=0.6, emit=0.0):
    m = bpy.data.materials.new(name)
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit > 0 and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    return m


gold_mat = make_mat("PodiumGold", (1.0, 0.78, 0.22), rough=0.22, metal=0.88, emit=0.45)
navy_mat = make_mat("StageNavy", (0.03, 0.045, 0.10), rough=0.75, metal=0.15)
white_mat = make_mat("CheckWhite", (0.94, 0.95, 0.98), rough=0.40, metal=0.10)
dark_mat = make_mat("CheckDark", (0.06, 0.07, 0.10), rough=0.45, metal=0.15)
accent_mat = make_mat("ArchOrange", (1.0, 0.44, 0.10), rough=0.28, metal=0.55, emit=1.1)

# Podium base cylinder + golden rim
bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=2.45, depth=0.16, location=(0.0, 0.0, -0.09))
podium = bpy.context.active_object
podium.data.materials.append(navy_mat)

bpy.ops.mesh.primitive_torus_add(major_radius=2.42, minor_radius=0.05, location=(0.0, 0.0, 0.0))
rim = bpy.context.active_object
rim.data.materials.append(gold_mat)

# Checkered winner's strip across the front of the podium
for ix in range(-6, 6):
    for iy in range(2):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(ix * 0.34 + 0.17, -1.25 + iy * 0.34, 0.006))
        tile = bpy.context.active_object
        tile.scale = (0.33, 0.33, 0.012)
        tile.data.materials.append(white_mat if ((ix + iy) % 2 == 0) else dark_mat)

# Golden Victory Arch & Checkered Header behind the champions
for sgn in (-1, 1):
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.11, depth=2.5, location=(sgn * 1.90, 0.95, 1.25))
    post = bpy.context.active_object
    post.data.materials.append(gold_mat)

bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.95, 2.48))
bar = bpy.context.active_object
bar.scale = (4.1, 0.20, 0.32)
bar.data.materials.append(accent_mat)

for ix in range(-5, 5):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(ix * 0.38 + 0.19, 0.83, 2.48))
    ct = bpy.context.active_object
    ct.scale = (0.36, 0.04, 0.24)
    ct.data.materials.append(white_mat if (ix % 2 == 0) else dark_mat)

# Floating golden celebration stars/confetti prisms around the podium
confetti_objs = []
for i in range(18):
    ang = (i / 18.0) * math.tau
    r = 1.45 + (i % 3) * 0.35
    z0 = 0.65 + (i % 5) * 0.32
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.045,
                                          location=(math.cos(ang) * r, math.sin(ang) * r * 0.7, z0))
    star = bpy.context.active_object
    star.rotation_mode = "XYZ"
    star.data.materials.append(gold_mat if (i % 2 == 0) else accent_mat)
    confetti_objs.append((star, z0, ang))


def write_victory_fanfare_wav(wav_path: str, duration_s: float = 2.0, sr: int = 22050) -> None:
    """Synthesizes a bright major-triad brass/synth victory fanfare (C5 -> E5 -> G5 -> C6)."""
    notes = [(0.0, 0.22, 523.25), (0.22, 0.44, 659.25), (0.44, 0.68, 783.99), (0.68, 2.0, 1046.50)]
    total_samples = int(duration_s * sr)
    samples = []
    for n in range(total_samples):
        t = n / float(sr)
        val = 0.0
        for t0, t1, freq in notes:
            if t0 <= t <= t1:
                local_t = t - t0
                env = min(1.0, local_t / 0.02) * math.exp(-local_t * (1.4 if t1 > 1.0 else 3.2))
                # Rich triad harmony on the final sustained chord
                val += env * (
                    0.50 * math.sin(math.tau * freq * t)
                    + 0.25 * math.sin(math.tau * freq * 2.0 * t)
                    + 0.20 * math.sin(math.tau * (freq * 0.5) * t)
                )
                if t1 > 1.0:
                    val += env * 0.22 * math.sin(math.tau * 659.25 * t)
                    val += env * 0.22 * math.sin(math.tau * 783.99 * t)
        s16 = max(-32767, min(32767, int(val * 16000)))
        samples.append(struct.pack("<h", s16))
    with wave.open(wav_path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(b"".join(samples))


cam = scene.camera
cam.rotation_mode = "XYZ"
cam.data.lens = 34
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 960
scene.render.resolution_y = 540
scene.view_settings.look = "AgX - Base Contrast"
scene.eevee.taa_render_samples = 16

TOTAL_FRAMES = 48
tmpdir = tempfile.mkdtemp(prefix="kiepie_victory_")
try:
    base_rider_z = nardus_rider.location.z if nardus_rider else 0.0
    for f in range(TOTAL_FRAMES):
        t = f / float(TOTAL_FRAMES)
        # Camera sweeps around so both the front celebration and Nardus's back decal are showcased
        ang = math.radians(-24.0 + 48.0 * t)
        dist = 3.45 - 0.22 * math.sin(t * math.pi)
        cam.location = (math.sin(ang) * dist, -math.cos(ang) * dist, 1.18 + 0.12 * math.sin(t * math.pi))
        cam.rotation_euler = (Vector((0.0, 0.0, 0.96)) - cam.location).to_track_quat("-Z", "Y").to_euler()

        # Nardus hops joyfully & flaps his arms in a big +-55 deg bird-flap arc!
        if nardus_rider is not None:
            hop = abs(math.sin(t * math.tau * 3.0)) * 0.16
            nardus_rider.location.z = base_rider_z + hop
            nardus_rider.rotation_euler = (0.0, 0.0, math.sin(t * math.tau * 2.0) * 0.22)
        # Use non-integer-aligned phase sampling so every frame shows distinct wing elevation
        flap_phase = f * 0.65
        flap = math.sin(flap_phase) * 0.95  # ~54 deg up/down bird flap!
        sweep = math.cos(flap_phase) * 0.26
        if arm_l is not None:
            arm_l.rotation_euler = (0.0, -flap, sweep)
        if arm_r is not None:
            arm_r.rotation_euler = (0.0, flap, -sweep)

        # Quad wheelie bob
        bike_root.rotation_euler = (
            math.radians(14.0 + 5.0 * math.sin(t * math.tau * 2.0)),
            0.0,
            math.radians(-22.0),
        )

        for star, z0, c_ang in confetti_objs:
            star.location.z = z0 + 0.18 * math.sin(t * math.tau * 2.0 + c_ang)
            star.rotation_euler = (t * 6.0, t * 4.0, c_ang)

        scene.render.filepath = os.path.join(tmpdir, f"frame_{f:03d}.png")
        bpy.ops.render.render(write_still=True)

    wav_path = os.path.join(tmpdir, "fanfare.wav")
    write_victory_fanfare_wav(wav_path, duration_s=TOTAL_FRAMES / 24.0)

    os.makedirs(os.path.dirname(OUT_MP4), exist_ok=True)
    subprocess.check_call([
        "ffmpeg", "-y",
        "-framerate", "24", "-i", os.path.join(tmpdir, "frame_%03d.png"),
        "-i", wav_path,
        "-c:v", "libx264", "-preset", "fast", "-crf", "25",
        "-c:a", "aac", "-b:a", "96k",
        "-pix_fmt", "yuv420p", "-shortest", "-movflags", "+faststart",
        OUT_MP4,
    ])
    print("VICTORY_SPLASH_SAVED", OUT_MP4, os.path.getsize(OUT_MP4))
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)
