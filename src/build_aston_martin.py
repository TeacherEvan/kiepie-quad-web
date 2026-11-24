#!/usr/bin/env python3
"""build_aston_martin.py — Procedural Aston Martin F1 ("BIG-BEN") for Kiepie Quad.

Run headless:
    blender -b -noaudio -P src/build_aston_martin.py
    blender -b -noaudio -P src/build_aston_martin.py -- --previews /tmp/aston_previews

Coordinate standard: 1 unit = 1 m, +Z up, -Y forward, ground datum minZ = 0.000.
Exports Aston_Martin.blend (repo root) and godot/assets/Aston_Martin.glb.
"""
import argparse
import math
import os
import sys
import bpy
import bmesh
from mathutils import Vector

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLATE_PATH = os.path.join(REPO_ROOT, "assets", "plate_bigben.png")
BLEND_PATH = os.path.join(REPO_ROOT, "Aston_Martin.blend")
GLB_PATH = os.path.join(REPO_ROOT, "godot", "assets", "Aston_Martin.glb")

# Calibrated arcade-F1 metric dimensions (fits KiepieBike collider & chase cam)
FRONT_AXLE_Y = -0.88
REAR_AXLE_Y = 0.86
FRONT_TRACK_HALF = 0.575
REAR_TRACK_HALF = 0.565
WHEEL_R = 0.255
F_TIRE_W = 0.220
R_TIRE_W = 0.280
# BIG-BEN's floor/diffuser used to sit only ~16 mm off the deck and visibly
# dragged under braking. Lift the whole body shell slightly; the wheels and
# their steering pivots stay on the ground datum (minZ = 0.000).
BODY_LIFT = 0.06


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--previews", default="", help="Optional directory for 5 EEVEE proof PNGs")
    return p.parse_args(argv)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    col = bpy.data.collections.new("AstonMartin")
    scene.collection.children.link(col)
    return scene, col


def make_mat(name, color, metallic=0.0, roughness=0.35, coat=0.0, emission=None, emission_strength=0.0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color[:3], 1.0)
    m.use_nodes = True
    bs = m.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Base Color"].default_value = (*color[:3], 1.0)
    bs.inputs["Metallic"].default_value = metallic
    bs.inputs["Roughness"].default_value = roughness
    if "Coat Weight" in bs.inputs:
        bs.inputs["Coat Weight"].default_value = coat
        bs.inputs["Coat Roughness"].default_value = 0.12
    if emission and "Emission Color" in bs.inputs:
        bs.inputs["Emission Color"].default_value = (*emission[:3], 1.0)
        bs.inputs["Emission Strength"].default_value = emission_strength
    return m


def make_plate_mat(name, img_path):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bs = nt.nodes.get("Principled BSDF")
    bs.inputs["Roughness"].default_value = 0.28
    bs.inputs["Metallic"].default_value = 0.08
    if "Coat Weight" in bs.inputs:
        bs.inputs["Coat Weight"].default_value = 0.40
        bs.inputs["Coat Roughness"].default_value = 0.12
    tex = nt.nodes.new("ShaderNodeTexImage")
    img = bpy.data.images.load(img_path)
    img.pack()
    tex.image = img
    nt.links.new(tex.outputs["Color"], bs.inputs["Base Color"])
    return m


def link_obj(ob, col):
    col.objects.link(ob)
    return ob


def mesh_from_pydata(name, verts, faces, mat, col, smooth=True):
    me = bpy.data.meshes.new(name + "_me")
    me.from_pydata(verts, [], faces)
    me.update()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    link_obj(ob, col)
    if mat:
        me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = smooth
    return ob


def join_objects(name, objs, col):
    objs = [o for o in objs if o is not None]
    if not objs:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    col.objects.link(ob)
    return ob


def box_solid(name, center, size, mat, col, rot=(0.0, 0.0, 0.0), smooth=False):
    cx, cy, cz = center
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    verts = [
        (-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
        (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz),
    ]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    ob = mesh_from_pydata(name, verts, faces, mat, col, smooth=smooth)
    ob.location = (cx, cy, cz)
    ob.rotation_euler = rot
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def loft_solid(name, rings, mat, col, cap=True, smooth=True):
    n = len(rings[0][1])
    verts, faces = [], []
    for y, ring in rings:
        for (x, z) in ring:
            verts.append((x, y, z))
    for i in range(len(rings) - 1):
        for j in range(n):
            a = i * n + j
            b = i * n + (j + 1) % n
            c = (i + 1) * n + (j + 1) % n
            d = (i + 1) * n + j
            faces.append((a, b, c, d))
    if cap:
        faces.append(tuple(range(n - 1, -1, -1)))
        faces.append(tuple((len(rings) - 1) * n + j for j in range(n)))
    return mesh_from_pydata(name, verts, faces, mat, col, smooth=smooth)


def swept_wing_solid(name, y0, y1, z_center, width, thickness, sweep_back, camber, mat, col, segs=12):
    """Closed manifold swept V/delta airfoil wing solid."""
    verts, faces = [], []
    half_t = thickness * 0.5
    # 4 cross-section stations around chord: LE_bot, TE_bot, TE_top, LE_top
    for i in range(segs + 1):
        u = -1.0 + 2.0 * i / segs
        x = u * (width * 0.5)
        dy = abs(u) * sweep_back
        dz_tip = abs(u) * 0.012
        yb = y0 + dy
        yt = y1 + dy * 0.75
        zc = z_center + dz_tip
        verts.extend([
            (x, yb, zc - half_t * 0.6),
            (x, yt, zc - half_t * 0.4),
            (x, yt, zc + half_t * 0.4 + camber * 0.3),
            (x, yb, zc + half_t * 0.8 + camber),
        ])
    for i in range(segs):
        b0 = i * 4
        b1 = (i + 1) * 4
        for k in range(4):
            kn = (k + 1) % 4
            faces.append((b0 + k, b1 + k, b1 + kn, b0 + kn))
    # Cap both ends
    faces.append((0, 3, 2, 1))
    last = segs * 4
    faces.append((last, last + 1, last + 2, last + 3))
    return mesh_from_pydata(name, verts, faces, mat, col, smooth=True)


def rod_solid(name, a, b, radius, mat, col, seg=8):
    a, b = Vector(a), Vector(b)
    mid = (a + b) * 0.5
    d = b - a
    length = d.length
    verts, faces = [], []
    for xi in (-length * 0.5, length * 0.5):
        for i in range(seg):
            ang = 2.0 * math.pi * i / seg
            verts.append((xi, radius * math.cos(ang), radius * math.sin(ang)))
    for i in range(seg):
        faces.append((i, (i + 1) % seg, seg + (i + 1) % seg, seg + i))
    faces.append(tuple(range(seg - 1, -1, -1)))
    faces.append(tuple(seg + i for i in range(seg)))
    ob = mesh_from_pydata(name, verts, faces, mat, col, smooth=True)
    ob.location = mid
    ob.rotation_euler = d.to_track_quat("X", "Z").to_euler()
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def lathe_x_solid(name, center, profile, mat, col, seg=28, closed=True):
    cx, cy, cz = center
    verts, faces = [], []
    for (ax, r) in profile:
        for i in range(seg):
            a = 2.0 * math.pi * i / seg
            verts.append((cx + ax, cy + r * math.cos(a), cz + r * math.sin(a)))
    n_prof = len(profile)
    for k in range(n_prof - 1):
        for i in range(seg):
            a = k * seg + i
            b = k * seg + (i + 1) % seg
            c = (k + 1) * seg + (i + 1) % seg
            d = (k + 1) * seg + i
            faces.append((a, b, c, d))
    if closed:
        for i in range(seg):
            a = (n_prof - 1) * seg + i
            b = (n_prof - 1) * seg + (i + 1) % seg
            c = (i + 1) % seg
            d = i
            faces.append((a, b, c, d))
    return mesh_from_pydata(name, verts, faces, mat, col, smooth=True)


def cyl_x_solid(name, center, radius, length, mat, col, seg=20):
    cx, cy, cz = center
    verts, faces = [], []
    for xi in (-length * 0.5, length * 0.5):
        for i in range(seg):
            a = 2.0 * math.pi * i / seg
            verts.append((cx + xi, cy + radius * math.cos(a), cz + radius * math.sin(a)))
    for i in range(seg):
        faces.append((i, (i + 1) % seg, seg + (i + 1) % seg, seg + i))
    faces.append(tuple(range(seg - 1, -1, -1)))
    faces.append(tuple(seg + i for i in range(seg)))
    return mesh_from_pydata(name, verts, faces, mat, col, smooth=True)


def sphere_solid(name, center, rx, ry, rz, mat, col, seg=18, rings=12):
    cx, cy, cz = center
    verts, faces = [], []
    verts.append((cx, cy, cz + rz))
    for j in range(1, rings):
        phi = math.pi * j / rings
        for i in range(seg):
            th = 2.0 * math.pi * i / seg
            verts.append((
                cx + rx * math.sin(phi) * math.cos(th),
                cy + ry * math.sin(phi) * math.sin(th),
                cz + rz * math.cos(phi),
            ))
    verts.append((cx, cy, cz - rz))
    for i in range(seg):
        faces.append((0, 1 + i, 1 + (i + 1) % seg))
    for j in range(rings - 2):
        r0 = 1 + j * seg
        r1 = 1 + (j + 1) * seg
        for i in range(seg):
            faces.append((r0 + i, r1 + i, r1 + (i + 1) % seg, r0 + (i + 1) % seg))
    last = len(verts) - 1
    base = 1 + (rings - 2) * seg
    for i in range(seg):
        faces.append((last, base + (i + 1) % seg, base + i))
    return mesh_from_pydata(name, verts, faces, mat, col, smooth=True)


def build_wheel_assembly(tag, is_left, radius, width, mats, col):
    """Build local-origin (0,0,0) wheel with open 5-spoke rim, outboard lime ring, nut & brake rotor."""
    out_sgn = -1.0 if is_left else 1.0
    hw = width * 0.5
    parts = []

    # Closed rounded-shoulder F1 slick tire
    tire_prof = [
        (-hw, radius * 0.62),
        (-hw, radius * 0.85),
        (-hw + 0.015, radius * 0.96),
        (-hw + 0.045, radius),
        (hw - 0.045, radius),
        (hw - 0.015, radius * 0.96),
        (hw, radius * 0.85),
        (hw, radius * 0.62),
        (hw - 0.02, radius * 0.60),
        (-hw + 0.02, radius * 0.60),
    ]
    parts.append(lathe_x_solid(f"{tag}_Tire", (0, 0, 0), tire_prof, mats["TIRE"], col, seg=28, closed=True))

    # Outboard lime sidewall pinstripe ring
    ring_x = out_sgn * (hw - 0.005)
    ring_prof = [
        (ring_x - 0.004, radius * 0.82),
        (ring_x - 0.004, radius * 0.90),
        (ring_x + 0.004, radius * 0.90),
        (ring_x + 0.004, radius * 0.82),
    ]
    parts.append(lathe_x_solid(f"{tag}_Band", (0, 0, 0), ring_prof, mats["LIME"], col, seg=28, closed=True))

    # Open concave deep-dish rim barrel (hollow so 5 spokes are clearly visible!)
    rim_r_out = radius * 0.61
    rim_r_in = radius * 0.54
    rim_prof = [
        (-hw * 0.86, rim_r_in),
        (-hw * 0.86, rim_r_out),
        (hw * 0.86, rim_r_out),
        (hw * 0.86, rim_r_in),
    ]
    parts.append(lathe_x_solid(f"{tag}_Rim", (0, 0, 0), rim_prof, mats["RIM"], col, seg=24, closed=True))

    # 5 visible split-Y spokes + center-lock hub nut
    spoke_x = out_sgn * (hw * 0.25)
    for k in range(5):
        a = 2.0 * math.pi * k / 5.0
        parts.append(rod_solid(
            f"{tag}_Spoke{k}",
            (spoke_x, 0.0, 0.0),
            (out_sgn * (hw * 0.55), rim_r_in * 0.96 * math.cos(a), rim_r_in * 0.96 * math.sin(a)),
            0.015, mats["RIM"], col, seg=6,
        ))
    parts.append(cyl_x_solid(f"{tag}_Hub", (out_sgn * (hw * 0.35), 0, 0), radius * 0.16, width * 0.42, mats["CHROME"], col, seg=14))

    # Inboard brake rotor disc
    parts.append(cyl_x_solid(f"{tag}_Brake", (-out_sgn * (hw * 0.52), 0, 0), radius * 0.46, 0.022, mats["BRAKE"], col, seg=18))

    return join_objects(f"Wheel_{tag}", parts, col)


def build_aston_martin(previews_dir=""):
    scene, col = clear_scene()

    mats = {
        "GREEN": make_mat("AM_Green", (0.003, 0.105, 0.082), metallic=0.58, roughness=0.20, coat=0.88),
        "GREEN_DARK": make_mat("AM_Green_Dark", (0.002, 0.058, 0.046), metallic=0.45, roughness=0.28, coat=0.60),
        "LIME": make_mat("AM_Lime", (0.58, 0.96, 0.04), metallic=0.12, roughness=0.28, coat=0.50),
        "CARBON": make_mat("Carbon_Satin", (0.022, 0.024, 0.028), metallic=0.32, roughness=0.36, coat=0.40),
        "TIRE": make_mat("Tire_Rubber", (0.015, 0.015, 0.017), metallic=0.0, roughness=0.68),
        "RIM": make_mat("Rim_DarkAlloy", (0.08, 0.085, 0.095), metallic=0.88, roughness=0.24),
        "BRAKE": make_mat("Brake_Steel", (0.32, 0.33, 0.36), metallic=0.92, roughness=0.30),
        "CHROME": make_mat("Chrome_Titanium", (0.72, 0.74, 0.78), metallic=0.96, roughness=0.14),
        "GUNMETAL": make_mat("Gunmetal", (0.16, 0.17, 0.19), metallic=0.82, roughness=0.30),
        "VISOR": make_mat("Visor_Glass", (0.01, 0.03, 0.045), metallic=0.85, roughness=0.06, coat=1.0),
        "RAIN": make_mat("RainLight_Red", (0.95, 0.05, 0.05), emission=(1.0, 0.08, 0.05), emission_strength=4.0),
        "SW_SCREEN": make_mat("SW_Screen", (0.02, 0.45, 0.55), emission=(0.05, 0.70, 0.85), emission_strength=1.5),
        "PLATE": make_plate_mat("BigBenPlate", PLATE_PATH),
    }

    chassis_parts = []

    # 1) Floor, plank, bargeboards & rear diffuser
    chassis_parts.append(box_solid("Floor", (0.0, 0.05, 0.058), (0.96, 2.28, 0.024), mats["CARBON"], col))
    chassis_parts.append(box_solid("FloorEdge_L", (-0.50, 0.08, 0.065), (0.04, 1.85, 0.014), mats["LIME"], col))
    chassis_parts.append(box_solid("FloorEdge_R", (0.50, 0.08, 0.065), (0.04, 1.85, 0.014), mats["LIME"], col))
    for s in (-1, 1):
        chassis_parts.append(box_solid(f"Bargeboard_{s}", (s * 0.48, -0.45, 0.125), (0.018, 0.44, 0.12), mats["CARBON"], col))
    chassis_parts.append(box_solid("Diffuser", (0.0, 1.24, 0.105), (0.64, 0.34, 0.11), mats["CARBON"], col, rot=(math.radians(-12), 0, 0)))
    for i in range(-2, 3):
        chassis_parts.append(box_solid(f"DiffStrake_{i}", (i * 0.12, 1.25, 0.11), (0.010, 0.32, 0.10), mats["CARBON"], col))

    # 2) Monocoque / drooping nose / airbox / shark fin
    def body_ring(y, w, zb, zt, sh=0.06):
        return (y, [
            (-w * 0.55, zb), (w * 0.55, zb), (w, zb + sh),
            (w * 0.92, zt - sh), (w * 0.52, zt), (-w * 0.52, zt),
            (-w * 0.92, zt - sh), (-w, zb + sh),
        ])

    body_rings = [
        body_ring(-1.48, 0.040, 0.105, 0.140, 0.015),
        body_ring(-1.22, 0.065, 0.105, 0.175, 0.022),
        body_ring(-0.88, 0.115, 0.100, 0.235, 0.035),
        body_ring(-0.55, 0.185, 0.095, 0.315, 0.050),
        body_ring(-0.22, 0.265, 0.090, 0.425, 0.070),
        body_ring(0.12, 0.275, 0.090, 0.520, 0.080),
        body_ring(0.45, 0.245, 0.095, 0.505, 0.080),
        body_ring(0.82, 0.195, 0.100, 0.425, 0.070),
        body_ring(1.16, 0.135, 0.110, 0.335, 0.050),
        body_ring(1.36, 0.095, 0.120, 0.290, 0.040),
    ]
    chassis_parts.append(loft_solid("Monocoque", body_rings, mats["GREEN"], col))
    chassis_parts.append(loft_solid("SharkFin", [
        (0.22, [(-0.014, 0.50), (0.014, 0.50), (0.018, 0.58), (-0.018, 0.58)]),
        (0.62, [(-0.016, 0.46), (0.016, 0.46), (0.020, 0.65), (-0.020, 0.65)]),
        (1.02, [(-0.012, 0.36), (0.012, 0.36), (0.015, 0.50), (-0.015, 0.50)]),
    ], mats["GREEN"], col))
    chassis_parts.append(box_solid("Airbox_Lip", (0.0, 0.10, 0.535), (0.16, 0.04, 0.012), mats["LIME"], col))
    chassis_parts.append(box_solid("Airbox_Intake", (0.0, 0.13, 0.545), (0.14, 0.10, 0.055), mats["CARBON"], col))
    chassis_parts.append(box_solid("TCam_Mast", (0.0, 0.13, 0.61), (0.024, 0.05, 0.065), mats["CARBON"], col))
    chassis_parts.append(box_solid("TCam_Bar", (0.0, 0.13, 0.648), (0.14, 0.036, 0.018), mats["LIME"], col))
    chassis_parts.append(box_solid("Nose_Stripe", (0.0, -1.05, 0.215), (0.020, 0.52, 0.008), mats["LIME"], col))

    # 3) Contoured Sidepods + undercut + lime beltline
    def side_ring(y, inn, out, zb, zt, cut=0.0):
        return (y, [
            (inn, zb + cut), (out * 0.86, zb + cut), (out, zb + cut + 0.07),
            (out, zt - 0.06), (out * 0.85, zt), (inn, zt),
        ])

    for s in (-1, 1):
        sp_rings = []
        for (y, inn, out, zb, zt, cut) in [
            (-0.52, 0.22, 0.46, 0.14, 0.40, 0.05),
            (-0.22, 0.24, 0.56, 0.12, 0.44, 0.045),
            (0.15, 0.24, 0.58, 0.11, 0.45, 0.035),
            (0.55, 0.21, 0.49, 0.11, 0.39, 0.02),
            (0.92, 0.17, 0.30, 0.12, 0.30, 0.0),
        ]:
            r = side_ring(y, inn, out, zb, zt, cut)
            sp_rings.append((y, [(s * x, z) for (x, z) in r[1]]))
        chassis_parts.append(loft_solid(f"Sidepod_{s}", sp_rings, mats["GREEN"], col))
        chassis_parts.append(box_solid(f"Inlet_{s}", (s * 0.37, -0.52, 0.31), (0.20, 0.06, 0.16), mats["CARBON"], col))
        chassis_parts.append(box_solid(f"SP_Lime_{s}", (s * 0.52, 0.10, 0.415), (0.016, 0.88, 0.014), mats["LIME"], col))
        chassis_parts.append(box_solid(f"SP_Undercut_{s}", (s * 0.53, -0.05, 0.185), (0.014, 0.65, 0.010), mats["LIME"], col))

    # 4) Swept-back V/delta 3-element Front Wing + curved endplates
    chassis_parts.append(swept_wing_solid("FW_Main", -1.54, -1.36, 0.070, 1.42, 0.018, 0.12, 0.010, mats["CARBON"], col))
    chassis_parts.append(swept_wing_solid("FW_Flap1", -1.46, -1.31, 0.108, 1.38, 0.016, 0.11, 0.014, mats["GREEN"], col))
    chassis_parts.append(swept_wing_solid("FW_Flap2", -1.39, -1.26, 0.145, 1.32, 0.014, 0.10, 0.012, mats["CARBON"], col))
    for s in (-1, 1):
        chassis_parts.append(box_solid(f"FW_Endplate_{s}", (s * 0.71, -1.34, 0.14), (0.016, 0.32, 0.21), mats["CARBON"], col, rot=(0, 0, s * math.radians(6))))
        chassis_parts.append(box_solid(f"FW_EndLime_{s}", (s * 0.718, -1.34, 0.22), (0.008, 0.28, 0.022), mats["LIME"], col, rot=(0, 0, s * math.radians(6))))
        chassis_parts.append(box_solid(f"FW_Foot_{s}", (s * 0.71, -1.36, 0.052), (0.11, 0.22, 0.012), mats["CARBON"], col))

    # 5) Curved Rear Wing + DRS pod + swan-neck pylons + beam wing
    chassis_parts.append(swept_wing_solid("RW_Main", 1.18, 1.34, 0.60, 0.82, 0.020, -0.02, 0.012, mats["CARBON"], col))
    chassis_parts.append(swept_wing_solid("RW_Flap", 1.24, 1.38, 0.69, 0.82, 0.018, -0.02, 0.018, mats["GREEN"], col))
    chassis_parts.append(swept_wing_solid("BeamWing", 1.10, 1.22, 0.32, 0.60, 0.016, 0.0, 0.010, mats["CARBON"], col))
    chassis_parts.append(box_solid("DRS_Pod", (0.0, 1.30, 0.68), (0.14, 0.14, 0.045), mats["GREEN"], col))
    for s in (-1, 1):
        chassis_parts.append(box_solid(f"RW_Endplate_{s}", (s * 0.415, 1.28, 0.64), (0.016, 0.30, 0.24), mats["GREEN"], col))
        chassis_parts.append(box_solid(f"RW_EndLime_{s}", (s * 0.422, 1.28, 0.73), (0.008, 0.26, 0.018), mats["LIME"], col))
        chassis_parts.append(rod_solid(f"RW_Pylon_{s}", (s * 0.08, 1.10, 0.30), (s * 0.08, 1.26, 0.60), 0.018, mats["CARBON"], col))

    # 6) Continuous smooth lofted Halo + Cockpit + Driver + Steering Wheel + Mirrors
    halo_pts = [
        (0.0, -0.46, 0.49), (0.16, -0.34, 0.525), (0.26, -0.14, 0.53),
        (0.24, 0.08, 0.525), (0.09, 0.24, 0.555),
    ]
    chassis_parts.append(rod_solid("Halo_Pillar", (0.0, -0.46, 0.38), (0.0, -0.46, 0.50), 0.018, mats["GREEN"], col))
    for s in (-1, 1):
        for k in range(len(halo_pts) - 1):
            p0 = (s * halo_pts[k][0], halo_pts[k][1], halo_pts[k][2])
            p1 = (s * halo_pts[k + 1][0], halo_pts[k + 1][1], halo_pts[k + 1][2])
            chassis_parts.append(rod_solid(f"Halo_{s}_{k}", p0, p1, 0.017, mats["GREEN"], col))
        chassis_parts.append(rod_solid(f"MirrorStalk_{s}", (s * 0.24, -0.22, 0.45), (s * 0.40, -0.22, 0.47), 0.009, mats["CARBON"], col))
        chassis_parts.append(box_solid(f"Mirror_{s}", (s * 0.42, -0.22, 0.475), (0.08, 0.04, 0.036), mats["GREEN"], col))

    chassis_parts.append(box_solid("Cockpit_Tub", (0.0, -0.24, 0.44), (0.26, 0.44, 0.03), mats["CARBON"], col))
    chassis_parts.append(box_solid("Driver_Torso", (0.0, -0.16, 0.39), (0.19, 0.22, 0.16), mats["GREEN_DARK"], col))
    chassis_parts.append(box_solid("Driver_Collar", (0.0, -0.20, 0.475), (0.14, 0.12, 0.028), mats["CARBON"], col))
    chassis_parts.append(sphere_solid("Helmet", (0.0, -0.24, 0.535), 0.095, 0.105, 0.095, mats["GREEN"], col))
    chassis_parts.append(sphere_solid("Visor", (0.0, -0.325, 0.540), 0.078, 0.045, 0.048, mats["VISOR"], col))
    chassis_parts.append(box_solid("Helmet_Stripe", (0.0, -0.24, 0.625), (0.024, 0.15, 0.010), mats["LIME"], col))
    chassis_parts.append(box_solid("SteeringWheel", (0.0, -0.40, 0.44), (0.16, 0.025, 0.08), mats["CARBON"], col))
    chassis_parts.append(box_solid("SW_Display", (0.0, -0.386, 0.446), (0.08, 0.006, 0.032), mats["SW_SCREEN"], col))

    # 7) Suspension wishbones
    for s in (-1, 1):
        for axle, yy, half in (("F", FRONT_AXLE_Y, FRONT_TRACK_HALF), ("R", REAR_AXLE_Y, REAR_TRACK_HALF)):
            for dz in (-0.045, 0.045):
                for dy in (-0.11, 0.11):
                    chassis_parts.append(rod_solid(
                        f"Susp_{axle}_{s}_{dz}_{dy}",
                        (s * 0.11, yy + dy, 0.18 + dz),
                        (s * (half - 0.08), yy, WHEEL_R + dz * 0.4),
                        0.010, mats["CARBON"], col, seg=6,
                    ))

    # 8) Central rear titanium exhaust tailpipe + glowing red FIA rain light
    ex_prof = [(0.0, 0.036), (0.12, 0.036), (0.12, 0.028), (0.0, 0.028)]
    ex = lathe_x_solid("ExhaustPipe", (0.0, 0.0, 0.0), ex_prof, mats["CHROME"], col, seg=16, closed=True)
    ex.location = (0.0, 1.32, 0.39)
    ex.rotation_euler = (0, 0, math.pi * 0.5)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    ex.select_set(True)
    bpy.context.view_layer.objects.active = ex
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    chassis_parts.append(ex)
    chassis_parts.append(box_solid("RainLight", (0.0, 1.375, 0.175), (0.032, 0.018, 0.065), mats["RAIN"], col))

    # 9) Twin sleek sidepod-shoulder autocannon pods
    for s in (-1, 1):
        chassis_parts.append(box_solid(f"CannonPod_{s}", (s * 0.46, -0.58, 0.415), (0.095, 0.28, 0.085), mats["GUNMETAL"], col))
        b_rot = (0, 0, math.pi * 0.5)
        barrel = cyl_x_solid(f"CannonBarrel_{s}", (0, 0, 0), 0.026, 0.46, mats["GUNMETAL"], col, seg=12)
        barrel.location = (s * 0.46, -0.82, 0.42)
        barrel.rotation_euler = b_rot
        bpy.context.view_layer.update()
        bpy.ops.object.select_all(action="DESELECT")
        barrel.select_set(True)
        bpy.context.view_layer.objects.active = barrel
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        chassis_parts.append(barrel)
        muzzle_ring = cyl_x_solid(f"CannonRing_{s}", (0, 0, 0), 0.034, 0.04, mats["CHROME"], col, seg=12)
        muzzle_ring.location = (s * 0.46, -1.04, 0.42)
        muzzle_ring.rotation_euler = b_rot
        bpy.context.view_layer.update()
        bpy.ops.object.select_all(action="DESELECT")
        muzzle_ring.select_set(True)
        bpy.context.view_layer.objects.active = muzzle_ring
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        chassis_parts.append(muzzle_ring)

    # Lift the body shell uniformly so nothing scrapes the deck. Suspension
    # rods stay put: they are the visible link between the raised body and the
    # wheel hubs that remain on the ground.
    for ob in chassis_parts:
        if ob is not None and not ob.name.startswith("Susp_"):
            ob.location.z += BODY_LIFT
    bpy.context.view_layer.update()

    chassis = join_objects("Chassis", chassis_parts, col)

    # 10) "BIG-BEN" Back License Plate (closed backing + UV-mapped front face, tilted 12° upward)
    pw, ph, pt = 0.44, 0.13, 0.014
    hw, hh = pw * 0.5, ph * 0.5
    tilt = math.radians(12.0)
    yc, zc = 1.385, 0.295
    # Local plate vertices: +Y faces rear (+Y in Blender), tilted upward toward chase cam
    plate_bm = bmesh.new()
    # Back face (y = -pt) and Front face (y = 0)
    v_fb_bl = plate_bm.verts.new((hw, 0.0, -hh))
    v_fb_br = plate_bm.verts.new((-hw, 0.0, -hh))
    v_fb_tr = plate_bm.verts.new((-hw, 0.0, hh))
    v_fb_tl = plate_bm.verts.new((hw, 0.0, hh))

    v_bb_bl = plate_bm.verts.new((hw, -pt, -hh))
    v_bb_br = plate_bm.verts.new((-hw, -pt, -hh))
    v_bb_tr = plate_bm.verts.new((-hw, -pt, hh))
    v_bb_tl = plate_bm.verts.new((hw, -pt, hh))

    f_front = plate_bm.faces.new((v_fb_bl, v_fb_br, v_fb_tr, v_fb_tl))
    f_front.material_index = 1  # BigBenPlate
    for quad in [
        (v_bb_br, v_bb_bl, v_bb_tl, v_bb_tr),
        (v_bb_bl, v_fb_bl, v_fb_tl, v_bb_tl),
        (v_fb_br, v_bb_br, v_bb_tr, v_fb_tr),
        (v_bb_tl, v_fb_tl, v_fb_tr, v_bb_tr),
        (v_bb_br, v_fb_br, v_fb_bl, v_bb_bl),
    ]:
        f = plate_bm.faces.new(quad)
        f.material_index = 0  # Carbon_Satin

    uv_layer = plate_bm.loops.layers.uv.new("UVMap")
    uvs = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
    for loop, uv in zip(f_front.loops, uvs):
        loop[uv_layer].uv = uv

    bmesh.ops.recalc_face_normals(plate_bm, faces=plate_bm.faces)
    plate_me = bpy.data.meshes.new("RearPlate_BigBen_me")
    plate_bm.to_mesh(plate_me)
    plate_bm.free()
    plate_ob = bpy.data.objects.new("RearPlate_BigBen", plate_me)
    link_obj(plate_ob, col)
    plate_me.materials.append(mats["CARBON"])
    plate_me.materials.append(mats["PLATE"])
    plate_ob.location = (0.0, yc, zc + BODY_LIFT)
    plate_ob.rotation_euler = (tilt, 0.0, 0.0)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    plate_ob.select_set(True)
    bpy.context.view_layer.objects.active = plate_ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # 11) Wheels & Steering Pivots (local (0,0,0) pivots for Godot!)
    for s, tag in ((-1, "FL"), (1, "FR")):
        steer = bpy.data.objects.new(f"Steer_{tag}", None)
        steer.location = (s * FRONT_TRACK_HALF, FRONT_AXLE_Y, WHEEL_R)
        link_obj(steer, col)
        w = build_wheel_assembly(tag, s < 0, WHEEL_R, F_TIRE_W, mats, col)
        w.parent = steer
        # Static brake caliper + duct parented to Steer_F*
        cal = box_solid(f"Cal_{tag}", (-s * (F_TIRE_W * 0.36), -0.07, 0.02), (0.04, 0.08, 0.11), mats["LIME"], col)
        duct = box_solid(f"Duct_{tag}", (-s * (F_TIRE_W * 0.56), 0.04, 0.04), (0.04, 0.14, 0.12), mats["CARBON"], col)
        brake_asm = join_objects(f"BrakeAsm_{tag}", [cal, duct], col)
        brake_asm.parent = steer

    for s, tag in ((-1, "RL"), (1, "RR")):
        w = build_wheel_assembly(tag, s < 0, WHEEL_R, R_TIRE_W, mats, col)
        w.location = (s * REAR_TRACK_HALF, REAR_AXLE_Y, WHEEL_R)

    # 12) Muzzle & Exhaust Empties
    for m_name, m_loc in [
        ("AstonMuzzle_L", (-0.46, -1.06, 0.42)),
        ("AstonMuzzle_R", (0.46, -1.06, 0.42)),
        ("Exhaust_Tip", (0.0, 1.35, 0.39)),
    ]:
        emp = bpy.data.objects.new(m_name, None)
        emp.empty_display_type = "PLAIN_AXES"
        emp.empty_display_size = 0.07
        emp.location = (m_loc[0], m_loc[1], m_loc[2] + BODY_LIFT)
        link_obj(emp, col)

    # 13) QA check + Save .blend + Export .glb
    bpy.context.view_layer.update()
    verts = faces = tris = non_manifold = 0
    min_z = 1e9
    for ob in col.objects:
        if ob.type != "MESH":
            continue
        bm = bmesh.new()
        try:
            bm.from_mesh(ob.data)
            verts += len(bm.verts)
            faces += len(bm.faces)
            tris += sum(max(1, len(f.verts) - 2) for f in bm.faces)
            bm.edges.ensure_lookup_table()
            non_manifold += sum(1 for e in bm.edges if not e.is_manifold)
            min_z = min(min_z, min((ob.matrix_world @ v.co).z for v in bm.verts))
        finally:
            bm.free()

    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("SAVED", BLEND_PATH)

    bpy.ops.object.select_all(action="DESELECT")
    for ob in col.objects:
        ob.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=GLB_PATH, export_format="GLB", use_selection=True,
        export_yup=True, export_cameras=False, export_lights=False, export_apply=True,
    )
    glb_size = os.path.getsize(GLB_PATH)
    print(f"GLB_SAVED {GLB_PATH} ({glb_size} bytes)")
    print(f"QA verts={verts} faces={faces} tris={tris} non_manifold_edges={non_manifold} min_z={min_z:.4f}")

    assert non_manifold == 0, f"Expected 0 non_manifold_edges, got {non_manifold}"
    assert abs(min_z) <= 0.005, f"Expected |min_z| <= 0.005, got {min_z}"
    assert tris <= 11000, f"Expected tris <= 11000, got {tris}"
    assert glb_size <= 460800, f"Expected GLB <= 450 KB, got {glb_size} bytes"

    # 14) Optional studio proof renders
    if previews_dir:
        os.makedirs(previews_dir, exist_ok=True)
        world = bpy.data.worlds.new("StudioWorld")
        scene.world = world
        world.use_nodes = True
        bg = world.node_tree.nodes.get("Background")
        bg.inputs["Color"].default_value = (0.04, 0.055, 0.065, 1.0)
        bg.inputs["Strength"].default_value = 0.8

        for lname, loc, energy, sz, lcol in [
            ("Key", (3.2, -3.4, 3.6), 900, 3.0, (1.0, 0.98, 0.94)),
            ("Fill", (-3.5, -1.5, 2.2), 450, 3.0, (0.82, 0.92, 1.0)),
            ("Rim", (0.8, 3.6, 2.4), 850, 2.5, (0.85, 1.0, 0.92)),
        ]:
            ld = bpy.data.lights.new(lname, type="AREA")
            ld.energy = energy; ld.size = sz; ld.color = lcol
            lob = bpy.data.objects.new(lname, ld)
            scene.collection.objects.link(lob)
            lob.location = loc
            lob.rotation_euler = (Vector((0, 0, 0.35)) - lob.location).to_track_quat("-Z", "Y").to_euler()

        cam_data = bpy.data.cameras.new("ProofCam")
        cam = bpy.data.objects.new("ProofCam", cam_data)
        scene.collection.objects.link(cam)
        scene.camera = cam

        scene.render.engine = "BLENDER_EEVEE"
        scene.render.resolution_x = 1024
        scene.render.resolution_y = 640
        scene.eevee.taa_render_samples = 24
        try:
            scene.view_settings.view_transform = "AgX"
            scene.view_settings.look = "AgX - Medium High Contrast"
        except Exception as exc:
            import warnings
            warnings.warn(f"build_aston_martin: AgX view transform unavailable: {exc}")

        views = {
            "aston_front34.png": ((2.4, -3.2, 1.15), 42, (0.0, -0.1, 0.30)),
            "aston_back34.png": ((2.2, 3.0, 1.10), 42, (0.0, 0.2, 0.30)),
            "aston_side.png": ((3.6, 0.0, 0.55), 45, (0.0, 0.0, 0.32)),
            "aston_top.png": ((0.0, 0.0, 4.2), 42, (0.0, 0.0, 0.0)),
            "aston_back_plate.png": ((0.0, 2.35, 0.42), 65, (0.0, 1.36, 0.29)),
        }
        for fname, (loc, lens, tgt) in views.items():
            cam.location = loc
            cam_data.lens = lens
            cam.rotation_euler = (Vector(tgt) - cam.location).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = os.path.join(previews_dir, fname)
            bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    args = parse_args()
    build_aston_martin(args.previews)
