#!/usr/bin/env python3
"""
Renders web-assets/kiepie-victory-splash.mp4 — the celebratory Victory Splash
video triggered when a player wins Death Race or Battle Royale.
Features NARDUS flapping his arms in celebration alongside KIEPIE QUAD on a
golden checkered podium under stadium spotlights.
Run:
    blender -b -noaudio -P src/build_victory_splash.py
"""
import math
import os
import shutil
import subprocess
import tempfile
import bpy
from mathutils import Vector

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_MP4 = os.path.join(REPO_ROOT, "web-assets", "kiepie-victory-splash.mp4")

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# Import Pogo_Nardus.glb and Kiepie_Bike.glb
nardus_glb = os.path.join(REPO_ROOT, "godot", "assets", "Pogo_Nardus.glb")
bike_glb = os.path.join(REPO_ROOT, "godot", "assets", "Kiepie_Bike.glb")

if os.path.exists(nardus_glb):
    bpy.ops.import_scene.gltf(filepath=nardus_glb)
nardus_rider = bpy.data.objects.get("Rider")
nardus_stick = bpy.data.objects.get("Stick")
arm_l = bpy.data.objects.get("Arm_L")
arm_r = bpy.data.objects.get("Arm_R")

# Offset Nardus to the right side of the podium
for ob in (nardus_rider, nardus_stick):
    if ob is not None and ob.parent is None:
        ob.location.x += 0.72
        ob.location.y -= 0.10

# Import Kiepie Bike on the left side of the podium
before_objs = set(bpy.data.objects)
if os.path.exists(bike_glb):
    bpy.ops.import_scene.gltf(filepath=bike_glb)
after_objs = set(bpy.data.objects) - before_objs
bike_root = bpy.data.objects.new("VictoryBikeRoot", None)
scene.collection.objects.link(bike_root)
for ob in after_objs:
    if ob.parent is None:
        ob.parent = bike_root
bike_root.location = (-0.82, 0.08, 0.0)
bike_root.rotation_euler = (0.0, 0.0, math.radians(-24.0))

# Build a golden checkered winner podium & arch
def make_mat(name, color, rough=0.35, metal=0.6, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit > 0 and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    return m

gold_mat = make_mat("PodiumGold", (1.0, 0.78, 0.22), rough=0.25, metal=0.85, emit=0.35)
navy_mat = make_mat("StageNavy", (0.03, 0.045, 0.10), rough=0.80, metal=0.1)
accent_mat = make_mat("ArchOrange", (1.0, 0.42, 0.10), rough=0.3, metal=0.5, emit=0.8)

bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=2.4, depth=0.16, location=(0.0, 0.0, -0.08))
podium = bpy.context.active_object
podium.data.materials.append(navy_mat)

bpy.ops.mesh.primitive_torus_add(major_radius=2.38, minor_radius=0.045, location=(0.0, 0.0, 0.0))
rim = bpy.context.active_object
rim.data.materials.append(gold_mat)

# Victory arch behind the champions
for sgn in (-1, 1):
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.12, depth=2.6, location=(sgn * 1.95, 0.85, 1.3))
    post = bpy.context.active_object
    post.data.materials.append(gold_mat)

bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.85, 2.55))
bar = bpy.context.active_object
bar.scale = (4.2, 0.22, 0.28)
bar.data.materials.append(accent_mat)

# World & lighting
world = bpy.data.worlds.new("VictoryWorld")
scene.world = world
world.use_nodes = True
bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs["Color"].default_value = (0.02, 0.03, 0.08, 1.0)
bg.inputs["Strength"].default_value = 1.1

lights = [
    ("KeyGold", "AREA", (-2.5, -3.2, 2.8), (1.0, 0.90, 0.72), 550.0),
    ("FillCyan", "AREA", (2.8, -2.8, 2.2), (0.50, 0.84, 1.0), 420.0),
    ("RimWarm", "AREA", (0.0, 3.0, 2.6), (1.0, 0.55, 0.18), 600.0),
]
for lname, ltype, loc, col, energy in lights:
    ld = bpy.data.lights.new(lname, ltype)
    ld.color = col
    ld.energy = energy
    ld.size = 2.2
    lo = bpy.data.objects.new(lname, ld)
    scene.collection.objects.link(lo)
    lo.location = loc
    lo.rotation_euler = (Vector((0.0, 0.0, 1.0)) - lo.location).to_track_quat("-Z", "Y").to_euler()

cam_data = bpy.data.cameras.new("VictoryCam")
cam_data.lens = 34
cam = bpy.data.objects.new("VictoryCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

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
        # Camera orbits gently in a heroic low-angle arc
        ang = math.radians(-16.0 + 32.0 * t)
        dist = 3.55 - 0.25 * math.sin(t * math.pi)
        cam.location = (math.sin(ang) * dist, -math.cos(ang) * dist, 1.18 + 0.10 * math.sin(t * math.pi))
        cam.rotation_euler = (Vector((0.0, 0.0, 0.96)) - cam.location).to_track_quat("-Z", "Y").to_euler()

        # Nardus bounces joyfully & flaps his arms like a bird!
        if nardus_rider is not None:
            hop = abs(math.sin(t * math.tau * 3.0)) * 0.14
            nardus_rider.location.z = base_rider_z + hop
        flap = math.sin(t * math.tau * 6.0) * 0.68
        sweep = math.cos(t * math.tau * 6.0) * 0.18
        if arm_l is not None:
            arm_l.rotation_euler = (0.0, -flap, sweep)
        if arm_r is not None:
            arm_r.rotation_euler = (0.0, flap, -sweep)

        scene.render.filepath = os.path.join(tmpdir, f"frame_{f:03d}.png")
        bpy.ops.render.render(write_still=True)

    os.makedirs(os.path.dirname(OUT_MP4), exist_ok=True)
    subprocess.check_call([
        "ffmpeg", "-y", "-framerate", "24",
        "-i", os.path.join(tmpdir, "frame_%03d.png"),
        "-c:v", "libx264", "-preset", "fast", "-crf", "26",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        OUT_MP4,
    ])
    print("VICTORY_SPLASH_SAVED", OUT_MP4, os.path.getsize(OUT_MP4))
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)
