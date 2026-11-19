#!/usr/bin/env python3
"""NARDUS — the pogo-stick menace: procedural stylized sculpt + export (v4.1).

Blender source of truth for the Pogo_Nardus vehicle. Never edit the .blend
or the GLB by hand; edit this script and rebuild:

    blender -b -noaudio -P src/build_pogo_nardus.py
    blender -b -noaudio -P src/build_pogo_nardus.py -- --previews /path/to/out

v4.1 Plastic-Surgery + Surgical-Building upgrade:
- Noticeably fuller, genuinely heavy caricature silhouette: broad barrel chest,
  C2-smooth gravity-sagged pear-shaped gut with seamless love-handle wrap and
  waistband overhang, rosy chubby jowls & double-chin roll, meatier arms & legs,
  clean back tuck with bold gold NARDUS jersey print.
- Modular articulated pivots for natural PogoVisual.gd motion:
    Rider/RiderBody    (static legs/sandals/shorts/shirt torso)
    Rider/Belly        (top-pivoted heavy gut + navel for 2-axis spring jiggle)
    Rider/Head         (neck-pivoted expressive head for turn-look & impact nod)
    Rider/Arm_L, Arm_R (shoulder-pivoted chubby arms for counterbalance & bird-flap)
    Rider/NardusDecal  (conformal curved back-of-shirt print)
    Stick/StickLower   (rubber tip at z=0.0000 + telescoping chrome piston + lower seat)
    Stick/SpringCoil   (base-pivoted heavy helical spring at z=0.165 for live compression)
    Stick/StickUpper   (hydraulic barrel + foot-yoke/pegs under sandals + flank banana blasters)
    Stick/BananaMuzzle_L, BananaMuzzle_R (exact muzzle anchors at blaster tips)

Saves Pogo_Nardus.blend at the repo root, exports godot/assets/Pogo_Nardus.glb
(excludes proof floor/lights/camera) and prints the QA gate (verts, faces,
non_manifold_edges == 0, min_z == 0.0000).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEWS = None
if "--previews" in argv:
    PREVIEWS = argv[argv.index("--previews") + 1]
    os.makedirs(PREVIEWS, exist_ok=True)

# ---------------------------------------------------------------- scaffold
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.length_unit = 'METERS'

for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.curves,
            bpy.data.cameras, bpy.data.lights, bpy.data.images):
    for x in list(blk):
        blk.remove(x)

col = bpy.data.collections.new("PogoNardus")
scene.collection.children.link(col)


def _link_only(ob, coll=col):
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    coll.objects.link(ob)
    return ob


def set_smooth(ob, smooth=True):
    if ob.type == "MESH" and len(ob.data.polygons) > 0:
        ob.data.polygons.foreach_set("use_smooth", [smooth] * len(ob.data.polygons))
        ob.data.update()
    return ob


def loft_tube(name, stations, seg=16, cap_start=True, cap_end=True, material=None):
    """Build a single watertight, smooth-shaded manifold mesh lofted along stations.

    Each station is (Vector_center, rx, ry[, tangent]).
    """
    pts = [Vector(s[0]) for s in stations]
    rxs = [s[1] for s in stations]
    rys = [s[2] for s in stations]
    n = len(pts)

    tangents = []
    for i in range(n):
        if len(stations[i]) > 3 and stations[i][3] is not None:
            t = Vector(stations[i][3]).normalized()
        elif i == 0:
            t = (pts[1] - pts[0]).normalized()
        elif i == n - 1:
            t = (pts[-1] - pts[-2]).normalized()
        else:
            t = (pts[i + 1] - pts[i - 1]).normalized()
        tangents.append(t)

    ref = Vector((0.0, 1.0, 0.0)) if abs(tangents[0].y) < 0.9 else Vector((1.0, 0.0, 0.0))
    u = tangents[0].cross(ref).normalized()
    v = tangents[0].cross(u).normalized()
    frames = [(u, v)]
    for i in range(1, n):
        t_prev = tangents[i - 1]
        t_cur = tangents[i]
        axis = t_prev.cross(t_cur)
        if axis.length > 1e-6:
            angle = t_prev.angle(t_cur)
            rot = Matrix.Rotation(angle, 3, axis.normalized())
            u = (rot @ u).normalized()
            v = t_cur.cross(u).normalized()
        frames.append((u, v))

    bm = bmesh.new()
    rings = []
    for i in range(n):
        c = pts[i]
        u_i, v_i = frames[i]
        rx, ry = rxs[i], rys[i]
        ring = []
        for j in range(seg):
            a = 2.0 * math.pi * j / seg
            pos = c + u_i * (math.cos(a) * rx) + v_i * (math.sin(a) * ry)
            ring.append(bm.verts.new(pos))
        rings.append(ring)

    for i in range(n - 1):
        r0, r1 = rings[i], rings[i + 1]
        for j in range(seg):
            jn = (j + 1) % seg
            f = bm.faces.new((r0[j], r0[jn], r1[jn], r1[j]))
            f.smooth = True

    if cap_start:
        c0 = bm.verts.new(pts[0])
        r0 = rings[0]
        for j in range(seg):
            jn = (j + 1) % seg
            f = bm.faces.new((c0, r0[jn], r0[j]))
            f.smooth = True
    if cap_end:
        c1 = bm.verts.new(pts[-1])
        r1 = rings[-1]
        for j in range(seg):
            jn = (j + 1) % seg
            f = bm.faces.new((c1, r1[j], r1[jn]))
            f.smooth = True

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    ob = bpy.data.objects.new(name, mesh)
    _link_only(ob)
    if material is not None:
        ob.data.materials.append(material)
    return ob


def sph(name, loc, scale, seg=14, ring=10, rot=(0, 0, 0), material=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=ring, radius=1.0,
                                         location=loc, rotation=rot)
    t = bpy.context.active_object
    t.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    t.name = name
    _link_only(t)
    set_smooth(t, True)
    if material is not None:
        t.data.materials.append(material)
    return t


def cyl(name, loc, radius, depth, rot=(0, 0, 0), seg=14, material=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=radius, depth=depth,
                                        location=loc, rotation=rot)
    t = bpy.context.active_object
    t.name = name
    _link_only(t)
    set_smooth(t, True)
    if material is not None:
        t.data.materials.append(material)
    return t


def box(name, loc, size, rot=(0, 0, 0), material=None, smooth=False):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    t = bpy.context.active_object
    t.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    t.name = name
    _link_only(t)
    set_smooth(t, smooth)
    if material is not None:
        t.data.materials.append(material)
    return t


def torus(name, loc, major, minor, rot=(0, 0, 0), seg=18, sides=8, material=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     major_segments=seg, minor_segments=sides,
                                     location=loc, rotation=rot)
    t = bpy.context.active_object
    t.name = name
    _link_only(t)
    set_smooth(t, True)
    if material is not None:
        t.data.materials.append(material)
    return t


def join_objects(name, objects):
    """Join meshes and bake world location/rotation/scale so origin is strictly (0,0,0)."""
    valid = [o for o in objects if o is not None and o.type == "MESH"]
    if not valid:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for o in valid:
        o.select_set(True)
    bpy.context.view_layer.objects.active = valid[0]
    if len(valid) > 1:
        bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def repivot_object(ob, pivot_vec):
    """Bake current world transform into mesh, then shift vertices to pivot-local space."""
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    pivot = Vector(pivot_vec)
    for v in ob.data.vertices:
        v.co -= pivot
    ob.data.update()
    ob.location = pivot
    return ob


def _srgb(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def mat(name, base, rough=0.55, metal=0.0, subsurface=0.0, sheen=0.0, coat=0.0,
        emission=None, emission_strength=0.0):
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*_srgb(base), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    for key, val in [("Subsurface Weight", subsurface), ("Sheen Weight", sheen),
                     ("Coat Weight", coat)]:
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = val
    if emission is not None:
        for key in ("Emission Color", "Emission"):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = (*_srgb(emission), 1.0)
                break
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m


# ---------------------------------------------------------------- PBR palette (14 + 1 decal = 15 <= 16 LOW budget)
SKIN = mat("Skin", (0.81, 0.54, 0.37), rough=0.56, subsurface=0.12)
SKIN_BLUSH = mat("SkinBlush", (0.86, 0.43, 0.33), rough=0.58, subsurface=0.14)
SHIRT = mat("ShirtCrimson", (0.58, 0.032, 0.14), rough=0.76, sheen=0.22)
TRIM_GOLD = mat("TrimGold", (0.98, 0.78, 0.20), rough=0.34, metal=0.28, coat=0.24)
SHORTS = mat("ShortsNavy", (0.08, 0.11, 0.19), rough=0.80, sheen=0.14)
HAIR = mat("HairDark", (0.11, 0.065, 0.038), rough=0.74, sheen=0.08)
SOCK = mat("SockWhite", (0.94, 0.94, 0.96), rough=0.80)
SANDAL = mat("SandalBrown", (0.38, 0.21, 0.10), rough=0.68)
POGO_CHROME = mat("PogoChrome", (0.88, 0.91, 0.96), rough=0.16, metal=0.92)
POGO_ACCENT = mat("PogoAccent", (0.80, 0.07, 0.26), rough=0.24, metal=0.40, coat=0.65)
RUBBER_DARK = mat("RubberDark", (0.08, 0.08, 0.10), rough=0.88)
EYE_WHITE = mat("EyeWhite", (0.98, 0.98, 0.97), rough=0.20, coat=0.40)
EYE_DARK = mat("EyeDark", (0.04, 0.04, 0.06), rough=0.15, coat=0.65)
MOUTH = mat("MouthCavity", (0.32, 0.065, 0.085), rough=0.55)

rider_parts = []
stick_lower_parts = []
stick_upper_parts = []

# Facing -Y (glTF +Z forward after export); back faces +Y (chase camera sees +Y).
# Feet stand solidly on the heavy-duty pogo FootPegs at z = 0.148!
FOOT_Z = 0.148
LEG_X = 0.164

# ---------------------------------------------------------------- meaty bent athletic legs + sandals planted on foot-pegs
for side, sgn in [("L", -1), ("R", 1)]:
    x = sgn * LEG_X
    leg_stations = [
        ((x * 0.96,  0.012, 0.855), 0.138, 0.140),  # full upper thigh into shorts
        ((x * 0.99, -0.016, 0.675), 0.122, 0.124),  # mid thigh
        ((x,        -0.052, 0.505), 0.102, 0.106),  # bent athletic knee forward (-Y)
        ((x,        -0.022, 0.370), 0.104, 0.108),  # thick round calf
        ((x,        -0.008, 0.245), 0.080, 0.082),  # lower shin into sock
    ]
    rider_parts.append(loft_tube(f"Leg_{side}", leg_stations, seg=14, material=SKIN))

    # Scrunched crew sock with double crimson-gold varsity stripe
    sock_stations = [
        ((x, -0.008, 0.295), 0.087, 0.089),
        ((x, -0.006, 0.255), 0.089, 0.091),
        ((x, -0.006, 0.192), 0.084, 0.088),
    ]
    rider_parts.append(loft_tube(f"Sock_{side}", sock_stations, seg=14, material=SOCK))
    rider_parts.append(torus(f"SockStripeA_{side}", (x, -0.007, 0.280), 0.087, 0.007,
                             seg=16, sides=6, material=SHIRT))
    rider_parts.append(torus(f"SockStripeB_{side}", (x, -0.007, 0.262), 0.088, 0.005,
                             seg=16, sides=6, material=TRIM_GOLD))

    # Chunky sculpted sport sandals planted right on top of the pogo FootPegs
    rider_parts.append(box(f"SandalSole_{side}", (x, -0.036, FOOT_Z + 0.018),
                           (0.166, 0.276, 0.036), material=RUBBER_DARK, smooth=False))
    rider_parts.append(box(f"SandalBed_{side}", (x, -0.036, FOOT_Z + 0.042),
                           (0.158, 0.266, 0.014), material=SANDAL, smooth=False))
    rider_parts.append(sph(f"FootFront_{side}", (x, -0.085, FOOT_Z + 0.068),
                           (0.072, 0.098, 0.042), seg=12, ring=8, material=SOCK))
    rider_parts.append(box(f"SandalStrapFront_{side}", (x, -0.092, FOOT_Z + 0.074),
                           (0.156, 0.056, 0.034), material=SANDAL, smooth=True))
    rider_parts.append(box(f"SandalStrapMid_{side}", (x, -0.025, FOOT_Z + 0.082),
                           (0.156, 0.046, 0.032), rot=(math.radians(-16), 0, 0),
                           material=SANDAL, smooth=True))

# ---------------------------------------------------------------- hefty athletic shorts (smooth hips, clean tuck in back!)
shorts_pelvis_stations = [
    ((0.0,  0.004, 0.780), 0.270, 0.220),
    ((0.0,  0.014, 0.875), 0.312, 0.258),  # plump rounded hips & rear
    ((0.0,  0.018, 0.985), 0.320, 0.266),
    ((0.0,  0.015, 1.095), 0.310, 0.258),  # meets the shirt cleanly on the back; belly overhangs in front!
    ((0.0,  0.010, 1.165), 0.288, 0.240),
]
rider_parts.append(loft_tube("ShortsPelvis", shorts_pelvis_stations, seg=20, material=SHORTS))
for side, sgn in [("L", -1), ("R", 1)]:
    x = sgn * LEG_X
    cuff_stations = [
        ((x * 0.94,  0.010, 0.895), 0.154, 0.156),
        ((x * 0.98, -0.006, 0.760), 0.144, 0.146),
        ((x * 0.99, -0.018, 0.680), 0.138, 0.140),
    ]
    rider_parts.append(loft_tube(f"ShortsLeg_{side}", cuff_stations, seg=14, material=SHORTS))
    rider_parts.append(torus(f"ShortsCuff_{side}", (x * 0.99, -0.018, 0.684), 0.137, 0.009,
                             seg=14, sides=6, material=SHIRT))

# ---------------------------------------------------------------- big jovial barrel T-shirt (stretched snug over gut!)
# Profile function for the shirt torso so NardusDecal conforms to the exact wider surface!
SHIRT_PROFILE = [
    # (z, cy, rx, ry)
    (1.135,  0.014, 0.318, 0.276),  # meets shorts waistband cleanly in back while belly spills out front!
    (1.185,  0.018, 0.352, 0.308),
    (1.260,  0.020, 0.370, 0.324),  # broad lower-mid chest/back
    (1.340,  0.018, 0.365, 0.316),  # broad upper chest
    (1.410,  0.012, 0.338, 0.288),  # thick sloping shoulders
    (1.468,  0.002, 0.268, 0.228),
    (1.512, -0.008, 0.158, 0.142),  # thick athletic neckline
]
shirt_stations = [((0.0, cy, z), rx, ry, (0.0, 0.0, 1.0)) for (z, cy, rx, ry) in SHIRT_PROFILE]
rider_parts.append(loft_tube("ShirtTorso", shirt_stations, seg=22, material=SHIRT))
rider_parts.append(torus("ShirtCollar", (0.0, -0.008, 1.515), 0.122, 0.022,
                         seg=18, sides=8, material=TRIM_GOLD))
rider_parts.append(torus("ShirtHemRoll", (0.0, 0.015, 1.138), 0.312, 0.013,
                         seg=20, sides=6, material=SHIRT))

# ---------------------------------------------------------------- GLORIOUS C2-SMOOTH FAT BELLY (Rider/Belly pivot!)
# Round, heavy, gravity-sagged beer-belly spilling softly over his shorts waistband
# in front and flanks, cleanly tucked inside the back of his shorts/shirt (+Y).
BELLY_PIVOT = Vector((0.0, -0.040, 1.285))


def _belly_deform(x0, y0, z0):
    # Gentle smooth lower-belly fullness (round potbelly curve, zero pointy cone!)
    pear_w = 1.0 + 0.08 * math.exp(-((z0 + 0.28) / 0.65) ** 2)
    # Smooth front-to-back radius transition via tanh (zero side seam!)
    front_t = 0.5 * (1.0 - math.tanh(y0 * 2.2))  # ~1 in front (-Y), ~0 in back (+Y)
    ry = 0.180 + (0.370 - 0.180) * front_t
    rx = 0.382 * pear_w * (0.88 + 0.12 * front_t)  # wide, plush love-handle fullness
    # Soft natural gravity droop downward on the front underside
    front_sag = front_t * 0.044 * math.exp(-((z0 + 0.18) / 0.78) ** 2)
    bx = x0 * rx
    by = y0 * ry * (1.0 + 0.04 * math.exp(-((z0 + 0.22) / 0.68) ** 2))
    bz = z0 * 0.252 - 0.232 - front_sag
    return Vector((bx, by, bz))


bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=22, v_segments=16, radius=1.0)
belly_mesh = bpy.data.meshes.new("BellyBody")
bm.to_mesh(belly_mesh)
bm.free()

belly = bpy.data.objects.new("Belly", belly_mesh)
for v in belly.data.vertices:
    v.co = _belly_deform(v.co.x, v.co.y, v.co.z) + BELLY_PIVOT
belly.data.update()
_link_only(belly)
set_smooth(belly, True)
belly.data.materials.append(SKIN)

# Cute flush-tucked dimpled navel right on the round front gut (zero side protrusion!)
navel_surf = _belly_deform(0.0, -0.97, -0.24) + BELLY_PIVOT
navel = sph("Navel", (navel_surf.x, navel_surf.y + 0.008, navel_surf.z), (0.022, 0.012, 0.019),
            seg=10, ring=6, material=MOUTH)
belly = join_objects("Belly", [belly, navel])
repivot_object(belly, BELLY_PIVOT)

# ---------------------------------------------------------------- shoulder-pivoted chubby arms (Arm_L / Arm_R)
arm_objects = {}
for side, sgn in [("L", -1), ("R", 1)]:
    pivot = Vector((sgn * 0.285, 0.008, 1.385))
    rider_parts.append(sph(f"ShoulderSocket_{side}", pivot,
                           (0.118, 0.114, 0.118), seg=12, ring=8, material=SHIRT))

    limb_parts = []
    sleeve_stations = [
        ((sgn * 0.265,  0.008, 1.388), 0.106, 0.106),
        ((sgn * 0.330,  0.006, 1.382), 0.124, 0.122),
        ((sgn * 0.405,  0.000, 1.362), 0.112, 0.112),
        ((sgn * 0.478, -0.008, 1.330), 0.102, 0.102),
    ]
    limb_parts.append(loft_tube(f"Sleeve_{side}", sleeve_stations, seg=14, material=SHIRT))
    sleeve_dir = Vector((sgn * 0.213, -0.016, -0.058)).normalized()
    cuff_rot = sleeve_dir.to_track_quat('Z', 'Y').to_euler()
    limb_parts.append(torus(f"SleeveTrim_{side}", (sgn * 0.476, -0.008, 1.331), 0.101, 0.011,
                            rot=cuff_rot, seg=16, sides=6, material=TRIM_GOLD))

    arm_stations = [
        ((sgn * 0.440, -0.005, 1.345), 0.090, 0.088),
        ((sgn * 0.532, -0.014, 1.298), 0.084, 0.082),
        ((sgn * 0.612, -0.032, 1.258), 0.074, 0.072),
        ((sgn * 0.662, -0.105, 1.332), 0.068, 0.066),
        ((sgn * 0.696, -0.175, 1.420), 0.054, 0.052),
    ]
    limb_parts.append(loft_tube(f"ArmMesh_{side}", arm_stations, seg=12, material=SKIN))

    hx, hy, hz = sgn * 0.712, -0.200, 1.456
    limb_parts.append(sph(f"Hand_{side}", (hx, hy, hz), (0.064, 0.062, 0.066),
                          seg=12, ring=8, material=SKIN))
    limb_parts.append(sph(f"Knuckles_{side}", (hx - sgn * 0.016, hy - 0.036, hz + 0.012),
                          (0.044, 0.032, 0.038), seg=8, ring=6, material=SKIN))
    limb_parts.append(sph(f"Thumb_{side}", (hx - sgn * 0.048, hy - 0.016, hz + 0.030),
                          (0.028, 0.030, 0.036), seg=8, ring=6, material=SKIN))

    arm_obj = join_objects(f"Arm_{side}", limb_parts)
    repivot_object(arm_obj, pivot)
    arm_objects[side] = arm_obj

# ---------------------------------------------------------------- expressive chubby HEAD (Rider/Head neck pivot!)
head_parts = []
HEAD_PIVOT = Vector((0.0, -0.010, 1.520))
head_parts.append(cyl("Neck", (0.0, -0.010, 1.552), 0.098, 0.115, seg=14, material=SKIN))
head_parts.append(sph("DoubleChin", (0.0, -0.072, 1.554), (0.128, 0.092, 0.052),
                      seg=14, ring=8, material=SKIN))
head_parts.append(sph("UnderChinRoll", (0.0, -0.092, 1.534), (0.102, 0.070, 0.034),
                      seg=12, ring=6, material=SKIN_BLUSH))
head_parts.append(sph("HeadCranium", (0.0, -0.016, 1.668), (0.156, 0.148, 0.154),
                      seg=18, ring=12, material=SKIN))
for sgn in [-1, 1]:
    head_parts.append(sph(f"Jowl_{sgn}", (sgn * 0.092, -0.088, 1.608),
                          (0.078, 0.068, 0.062), seg=12, ring=8, material=SKIN))
    head_parts.append(sph(f"Cheek_{sgn}", (sgn * 0.088, -0.124, 1.638),
                          (0.056, 0.044, 0.042), seg=10, ring=6, material=SKIN_BLUSH))
    head_parts.append(sph(f"Ear_{sgn}", (sgn * 0.154, -0.012, 1.662),
                          (0.030, 0.026, 0.048), seg=10, ring=6, material=SKIN))

head_parts.append(sph("Nose", (0.0, -0.172, 1.654), (0.035, 0.038, 0.032),
                      seg=10, ring=8, material=SKIN_BLUSH))

for sgn in [-1, 1]:
    head_parts.append(sph(f"EyeWhite_{sgn}", (sgn * 0.056, -0.150, 1.688),
                          (0.036, 0.020, 0.030), seg=10, ring=6, material=EYE_WHITE))
    head_parts.append(sph(f"Pupil_{sgn}", (sgn * 0.056, -0.168, 1.688),
                          (0.017, 0.011, 0.020), seg=8, ring=6, material=EYE_DARK))
    head_parts.append(sph(f"Catchlight_{sgn}", (sgn * 0.063, -0.177, 1.696),
                          (0.006, 0.004, 0.006), seg=6, ring=4, material=EYE_WHITE))
    head_parts.append(box(f"Brow_{sgn}", (sgn * 0.058, -0.158, 1.730),
                          (0.066, 0.018, 0.022),
                          rot=(0.0, sgn * math.radians(-11), sgn * math.radians(-9)),
                          material=HAIR, smooth=True))
    head_parts.append(sph(f"Mustache_{sgn}", (sgn * 0.046, -0.166, 1.622),
                          (0.062, 0.024, 0.024),
                          rot=(0.0, sgn * math.radians(18), sgn * math.radians(-20)),
                          seg=10, ring=6, material=HAIR))
    head_parts.append(sph(f"MustacheTip_{sgn}", (sgn * 0.094, -0.152, 1.608),
                          (0.026, 0.018, 0.018), seg=8, ring=6, material=HAIR))

head_parts.append(sph("MouthOpen", (0.0, -0.152, 1.590), (0.060, 0.028, 0.036),
                      seg=10, ring=6, material=MOUTH))
head_parts.append(box("Teeth", (0.0, -0.166, 1.605), (0.086, 0.016, 0.016),
                      material=EYE_WHITE, smooth=True))
head_parts.append(sph("Tongue", (0.0, -0.160, 1.574), (0.036, 0.020, 0.014),
                      seg=8, ring=6, material=SKIN_BLUSH))

head_parts.append(sph("HairCap", (0.0, 0.008, 1.724), (0.166, 0.158, 0.122),
                      seg=18, ring=10, material=HAIR))
head_parts.append(sph("HairBack", (0.0, 0.068, 1.668), (0.152, 0.114, 0.128),
                      seg=16, ring=8, material=HAIR))
for sgn in [-1, 1]:
    head_parts.append(sph(f"Sideburn_{sgn}", (sgn * 0.142, -0.046, 1.680),
                          (0.028, 0.036, 0.056), seg=8, ring=6, material=HAIR))
for idx, (fx, fy, fz, fs, frot) in enumerate([
    (-0.078, -0.118, 1.760, (0.056, 0.048, 0.034), (0.1,  0.2,  0.2)),
    ( 0.000, -0.132, 1.772, (0.068, 0.054, 0.038), (0.2,  0.0,  0.0)),
    ( 0.078, -0.118, 1.760, (0.056, 0.048, 0.034), (0.1, -0.2, -0.2)),
    ( 0.012, -0.020, 1.831, (0.078, 0.064, 0.034), (0.0,  0.15, 0.0)),
]):
    head_parts.append(sph(f"HairTuft_{idx}", (fx, fy, fz), fs, rot=frot,
                          seg=8, ring=6, material=HAIR))

head_obj = join_objects("Head", head_parts)
repivot_object(head_obj, HEAD_PIVOT)

# ---------------------------------------------------------------- curved conformal NARDUS decal (back of shirt)
dec_path = os.path.join(REPO_ROOT, "assets", "decal_nardus.png")
dec_img = bpy.data.images.load(dec_path)
dec_mat = mat("DecalNardus", (1.0, 1.0, 1.0), rough=0.45)
nt = dec_mat.node_tree
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = dec_img
tex.extension = 'CLIP'
bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
if "Emission Color" in bsdf.inputs:
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
if "Emission Strength" in bsdf.inputs:
    bsdf.inputs["Emission Strength"].default_value = 0.12
if "Alpha" in tex.outputs and "Alpha" in bsdf.inputs:
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
dec_mat.blend_method = 'CLIP'


def _sample_shirt_profile(z_val):
    for k in range(len(SHIRT_PROFILE) - 1):
        z0, cy0, rx0, ry0 = SHIRT_PROFILE[k]
        z1, cy1, rx1, ry1 = SHIRT_PROFILE[k + 1]
        if z0 <= z_val <= z1:
            t = (z_val - z0) / max(1e-6, z1 - z0)
            return (cy0 + t * (cy1 - cy0), rx0 + t * (rx1 - rx0), ry0 + t * (ry1 - ry0))
    return SHIRT_PROFILE[3][1:]


bm_dec = bmesh.new()
uv_layer = bm_dec.loops.layers.uv.new("UVMap")
NU, NV = 14, 6
OFFSET = 0.008
PHI_HALF = math.radians(46.0)
Z_BOT, Z_TOP = 1.210, 1.425

grid = []
for j in range(NV + 1):
    v_coord = j / float(NV)
    z_val = Z_BOT + v_coord * (Z_TOP - Z_BOT)
    cy, rx, ry = _sample_shirt_profile(z_val)
    row = []
    for i in range(NU + 1):
        u_coord = i / float(NU)
        phi = PHI_HALF * (1.0 - 2.0 * u_coord)
        px = (rx + OFFSET) * math.sin(phi)
        py = cy + (ry + OFFSET) * math.cos(phi)
        row.append((bm_dec.verts.new((px, py, z_val)), u_coord, v_coord))
    grid.append(row)

for j in range(NV):
    for i in range(NU):
        v00, u00, w00 = grid[j][i]
        v10, u10, w10 = grid[j][i + 1]
        v11, u11, w11 = grid[j + 1][i + 1]
        v01, u01, w01 = grid[j + 1][i]
        face = bm_dec.faces.new((v00, v10, v11, v01))
        face.smooth = True
        for loop, uv in zip(face.loops, [(u00, w00), (u10, w10), (u11, w11), (u01, w01)]):
            loop[uv_layer].uv = uv

dec_mesh = bpy.data.meshes.new("NardusDecalMesh")
bm_dec.to_mesh(dec_mesh)
bm_dec.free()
decal = bpy.data.objects.new("NardusDecal", dec_mesh)
_link_only(decal)
decal.data.materials.append(dec_mat)

# ---------------------------------------------------------------- HEAVY-DUTY TELESCOPING POGO STICK (3 articulated sub-parts!)
# 1) StickLower: stays grounded at z = 0.0000 during spring compression!
stick_lower_parts.append(loft_tube("PogoTip", [
    ((0.0, 0.0, 0.000), 0.044, 0.044),  # beefy rubber traction bumper (strictly min_z == 0.0000!)
    ((0.0, 0.0, 0.022), 0.056, 0.056),
    ((0.0, 0.0, 0.068), 0.046, 0.046),
    ((0.0, 0.0, 0.092), 0.036, 0.036),
], seg=14, material=RUBBER_DARK))
stick_lower_parts.append(cyl("PogoPiston", (0.0, 0.0, 0.420), 0.028, 0.68, seg=14, material=POGO_CHROME))
SPRING_BASE_Z = 0.165
SPRING_TOP_Z = 0.615
stick_lower_parts.append(cyl("SpringSeatBot", (0.0, 0.0, SPRING_BASE_Z - 0.012), 0.086, 0.028,
                             seg=16, material=POGO_ACCENT))
stick_lower_parts.append(torus("SpringSeatBotRing", (0.0, 0.0, SPRING_BASE_Z), 0.086, 0.009,
                               seg=16, sides=6, material=TRIM_GOLD))

# 2) SpringCoil: base-pivoted at (0, 0, SPRING_BASE_Z) so PogoVisual.gd compresses it live!
helix_pts = []
HELIX_STEPS = 58
for i in range(HELIX_STEPS):
    t = i / float(HELIX_STEPS - 1)
    a = t * math.pi * 2.0 * 5.5
    helix_pts.append((math.cos(a) * 0.072, math.sin(a) * 0.072,
                      SPRING_BASE_Z + 0.014 + t * (SPRING_TOP_Z - SPRING_BASE_Z - 0.028)))
curve = bpy.data.curves.new("Spring", "CURVE")
curve.dimensions = '3D'
sp = curve.splines.new("POLY")
sp.points.add(len(helix_pts) - 1)
for i, p in enumerate(helix_pts):
    sp.points[i].co = (p[0], p[1], p[2], 1.0)
curve.bevel_depth = 0.0155
curve.bevel_resolution = 2
curve.resolution_u = 1
curve.use_fill_caps = True
spring_obj = bpy.data.objects.new("SpringCoil", curve)
_link_only(spring_obj)
spring_obj.data.materials.append(POGO_CHROME)
bpy.ops.object.select_all(action="DESELECT")
spring_obj.select_set(True)
bpy.context.view_layer.objects.active = spring_obj
bpy.ops.object.convert(target="MESH")
spring_obj = bpy.context.active_object
bm_sp = bmesh.new()
bm_sp.from_mesh(spring_obj.data)
bmesh.ops.remove_doubles(bm_sp, verts=bm_sp.verts, dist=1e-4)
bm_sp.to_mesh(spring_obj.data)
bm_sp.free()
set_smooth(spring_obj, True)
repivot_object(spring_obj, (0.0, 0.0, SPRING_BASE_Z))

# 3) StickUpper: telescopes down over StickLower during spring compression!
stick_upper_parts.append(cyl("SpringSeatTop", (0.0, 0.0, SPRING_TOP_Z + 0.014), 0.088, 0.030,
                             seg=16, material=POGO_ACCENT))
stick_upper_parts.append(cyl("PreloadCollar", (0.0, 0.0, SPRING_TOP_Z + 0.045), 0.056, 0.036,
                             seg=14, material=TRIM_GOLD))
stick_upper_parts.append(cyl("PogoBarrel", (0.0, 0.0, 0.840), 0.044, 0.42, seg=16, material=POGO_ACCENT))

# Sturdy Foot-Yoke & wide rubberized FootPegs right underneath Nardus's sandals (z = FOOT_Z)!
for sgn in [-1, 1]:
    x_foot = sgn * LEG_X
    strut_stations = [
        ((sgn * 0.076, -0.010, SPRING_TOP_Z + 0.010), 0.015, 0.015),
        ((sgn * 0.092, -0.018, 0.360), 0.014, 0.014),
        ((sgn * 0.100, -0.025, FOOT_Z - 0.014), 0.016, 0.016),
    ]
    stick_upper_parts.append(loft_tube(f"FootStrut_{sgn}", strut_stations, seg=8, material=POGO_CHROME))
    stick_upper_parts.append(box(f"FootPegDeck_{sgn}", (x_foot, -0.034, FOOT_Z - 0.016),
                                 (0.184, 0.185, 0.028), material=POGO_ACCENT, smooth=False))
    stick_upper_parts.append(box(f"FootPegPad_{sgn}", (x_foot, -0.034, FOOT_Z - 0.001),
                                 (0.168, 0.165, 0.008), material=RUBBER_DARK, smooth=False))

    # Flanking side-mounted Banana Blaster pods clearing his wide hips/belly cleanly!
    # Mounted on sleek chrome outrigger arms at x = +-0.385, z = 0.88 so they read clearly in 3/4 & chase view!
    arm_bar = loft_tube(f"BlasterMount_{sgn}", [
        ((sgn * 0.040,  0.000, 0.720), 0.014, 0.014),
        ((sgn * 0.240, -0.020, 0.740), 0.014, 0.014),
        ((sgn * 0.380, -0.060, 0.835), 0.015, 0.015),
    ], seg=8, material=POGO_CHROME)
    stick_upper_parts.append(arm_bar)
    stick_upper_parts.append(cyl(f"BlasterPod_{sgn}", (sgn * 0.385, -0.125, 0.855), 0.040, 0.24,
                                 rot=(math.radians(90), 0.0, 0.0), seg=12, material=POGO_ACCENT))
    stick_upper_parts.append(torus(f"BlasterMuzzleRing_{sgn}", (sgn * 0.385, -0.242, 0.855),
                                   0.040, 0.010, rot=(math.radians(90), 0.0, 0.0),
                                   seg=14, sides=6, material=TRIM_GOLD))

# ---------------------------------------------------------------- consolidate static meshes (minimal draw calls!)
rider_body = join_objects("RiderBody", rider_parts)
stick_lower = join_objects("StickLower", stick_lower_parts)
stick_upper = join_objects("StickUpper", stick_upper_parts)

# ---------------------------------------------------------------- muzzle empties (preserved exact names!)
mz_l = bpy.data.objects.new("BananaMuzzle_L", None)
mz_l.empty_display_type = 'PLAIN_AXES'
mz_l.empty_display_size = 0.07
mz_l.location = (-0.385, -0.252, 0.855)
col.objects.link(mz_l)

mz_r = bpy.data.objects.new("BananaMuzzle_R", None)
mz_r.empty_display_type = 'PLAIN_AXES'
mz_r.empty_display_size = 0.07
mz_r.location = (0.385, -0.252, 0.855)
col.objects.link(mz_r)

# ---------------------------------------------------------------- hierarchy: Rider / Stick at scene root
rider = bpy.data.objects.new("Rider", None)
stick = bpy.data.objects.new("Stick", None)
col.objects.link(rider)
col.objects.link(stick)

for ob in (rider_body, belly, head_obj, decal, arm_objects.get("L"), arm_objects.get("R")):
    if ob is not None:
        ob.parent = rider

for ob in (stick_lower, spring_obj, stick_upper, mz_l, mz_r):
    if ob is not None:
        ob.parent = stick

# ---------------------------------------------------------------- world/lights/cam (proof render studio)
world = bpy.data.worlds.new("World")
scene.world = world
wt = world.node_tree
wt.nodes.clear()
bg = wt.nodes.new("ShaderNodeBackground")
bg.inputs["Color"].default_value = (0.015, 0.024, 0.062, 1.0)
bg.inputs["Strength"].default_value = 1.0
out = wt.nodes.new("ShaderNodeOutputWorld")
wt.links.new(bg.outputs["Background"], out.inputs["Surface"])

lights = [
    ("KeyWarm", "AREA", (-2.6, -2.4, 2.7), (1.0, 0.90, 0.78), 440, 1.8),
    ("RimOrange", "SPOT", (3.2, 1.8, 1.9), (1.0, 0.48, 0.14), 1350, 1.0),
    ("RimCyan", "SPOT", (-3.1, 1.6, 1.9), (0.45, 0.85, 1.0), 1250, 1.0),
    ("TopSlate", "AREA", (0.0, 0.4, 4.5), (0.65, 0.75, 1.0), 380, 1.8),
    ("FillBack", "AREA", (0.0, 3.4, 1.65), (1.0, 0.95, 0.90), 350, 2.2),
    ("FillFront", "AREA", (0.0, -3.6, 1.45), (1.0, 0.90, 0.84), 340, 2.2),
]
for name, typ, loc, lc, energy, size in lights:
    data = bpy.data.lights.new(name, typ)
    data.color = lc
    data.energy = energy
    if typ == "AREA":
        data.size = size
    else:
        data.spot_size = math.radians(30)
        data.spot_blend = 0.4
    ob = bpy.data.objects.new(name, data)
    col.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (Vector((0, 0, 1.08)) - ob.location).to_track_quat("-Z", "Y").to_euler()

cam_data = bpy.data.cameras.new("Camera")
cam = bpy.data.objects.new("Camera", cam_data)
col.objects.link(cam)
scene.camera = cam

bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=1.4, depth=0.02, location=(0, 0, -0.01))
floor = bpy.context.active_object
floor.name = "ProofFloor"
_link_only(floor)
floor.data.materials.append(mat("FloorNavy", (0.022, 0.032, 0.090), rough=0.92))

scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1200
scene.render.resolution_y = 900
scene.view_settings.look = "AgX - Base Contrast"
scene.eevee.taa_render_samples = 32

if PREVIEWS:
    views = {
        "front34": ((1.75, -2.75, 1.24), 32, (0.0, 0.0, 1.02)),
        "side": ((3.05, 0.0, 1.20), 34, (0.0, -0.06, 1.02)),
        "back34": ((1.75, 2.75, 1.24), 32, (0.0, 0.0, 1.02)),
        "front": ((0.0, -3.15, 1.22), 34, (0.0, 0.0, 1.02)),
        "back_closeup": ((0.0, 1.45, 1.32), 42, (0.0, 0.0, 1.32)),
    }
    for name, (loc, lens, tgt_v) in views.items():
        cam.location = loc
        cam.data.lens = lens
        tgt = Vector(tgt_v)
        cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(PREVIEWS, "nardus_%s.png" % name)
        bpy.ops.render.render(write_still=True)

# save blend
blend_path = os.path.join(REPO_ROOT, "Pogo_Nardus.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend_path)
print("SAVED", blend_path)

# ---------------------------------------------------------------- export GLB
EXCLUDE = {"ProofFloor", "KeyWarm", "RimOrange", "RimCyan", "TopSlate", "FillBack", "FillFront", "Camera"}
bpy.ops.object.select_all(action="DESELECT")
for ob in col.objects:
    if ob.name not in EXCLUDE:
        ob.select_set(True)
glb_path = os.path.join(REPO_ROOT, "godot/assets/Pogo_Nardus.glb")
bpy.ops.export_scene.gltf(filepath=glb_path, export_format="GLB",
                          use_selection=True, export_yup=True,
                          export_cameras=False, export_lights=False)
print("GLB_SAVED", glb_path)

# ---------------------------------------------------------------- QA stats (with guaranteed bm.free())
verts = faces = 0
non_manifold = 0
min_z = 1e9
for ob in col.objects:
    if ob.name in EXCLUDE or ob.type != "MESH":
        continue
    bm = bmesh.new()
    try:
        bm.from_mesh(ob.data)
        verts += len(bm.verts)
        faces += len(bm.faces)
        bm.edges.ensure_lookup_table()
        if ob.name != "NardusDecal":
            non_manifold += sum(1 for e in bm.edges if not e.is_manifold)
            min_z = min(min_z, min((ob.matrix_world @ v.co).z for v in bm.verts))
    finally:
        bm.free()
print("QA verts=%d faces=%d non_manifold_edges=%d min_z=%.4f" % (verts, faces, non_manifold, min_z))
