#!/usr/bin/env python3
"""NARDUS — the pogo-stick menace: procedural stylized sculpt + export (v3).

Blender source of truth for the Pogo_Nardus vehicle. Never edit the .blend
or the GLB by hand; edit this script and rebuild:

    blender -b -noaudio -P src/build_pogo_nardus.py
    blender -b -noaudio -P src/build_pogo_nardus.py -- --previews /tmp/out

Builds a fresh scene using continuous bmesh-lofted organic limbs and garments,
saves Pogo_Nardus.blend at the repo root, exports godot/assets/Pogo_Nardus.glb
(excludes proof floor/lights/camera) and prints the QA gate (verts, faces,
non_manifold_edges == 0, min_z == 0.0000).

Textures: assets/decal_nardus.png (bold gold NARDUS back-of-shirt print)
is applied to a curved conformal mesh on the shirt back — never text geometry.
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


def loft_tube(name, stations, seg=18, cap_start=True, cap_end=True, material=None):
    """Build a single watertight, smooth-shaded manifold mesh lofted along stations.

    Each station is (Vector_center, rx, ry, tangent_or_None). If tangent is None,
    it is computed from neighboring stations using a stable parallel-transport frame.
    """
    pts = [Vector(s[0]) for s in stations]
    rxs = [s[1] for s in stations]
    rys = [s[2] for s in stations]
    n = len(pts)

    # Compute smooth tangents
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

    # Parallel-transport orthonormal frame (u, v) along the curve
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


def sph(name, loc, scale, seg=18, ring=12, rot=(0, 0, 0), material=None):
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


def cyl(name, loc, radius, depth, rot=(0, 0, 0), seg=16, material=None):
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


def torus(name, loc, major, minor, rot=(0, 0, 0), seg=24, sides=10, material=None):
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
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
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


# ---------------------------------------------------------------- PBR palette (14 materials, <= 16 LOW budget)
SKIN = mat("Skin", (0.78, 0.50, 0.34), rough=0.60, subsurface=0.10)
SKIN_BLUSH = mat("SkinBlush", (0.82, 0.42, 0.32), rough=0.62, subsurface=0.12)
SHIRT = mat("ShirtCrimson", (0.56, 0.035, 0.16), rough=0.78, sheen=0.18)
TRIM_GOLD = mat("TrimGold", (0.98, 0.78, 0.22), rough=0.38, metal=0.22, coat=0.20)
SHORTS = mat("ShortsNavy", (0.09, 0.12, 0.20), rough=0.82, sheen=0.12)
HAIR = mat("HairDark", (0.12, 0.072, 0.042), rough=0.78)
SOCK = mat("SockWhite", (0.93, 0.93, 0.95), rough=0.82)
SANDAL = mat("SandalBrown", (0.36, 0.20, 0.10), rough=0.72)
POGO_CHROME = mat("PogoChrome", (0.88, 0.90, 0.95), rough=0.18, metal=0.90)
POGO_ACCENT = mat("PogoAccent", (0.78, 0.08, 0.30), rough=0.28, metal=0.35, coat=0.60)
RUBBER_DARK = mat("RubberDark", (0.09, 0.09, 0.11), rough=0.88)
EYE_WHITE = mat("EyeWhite", (0.97, 0.97, 0.96), rough=0.22, coat=0.35)
EYE_DARK = mat("EyeDark", (0.04, 0.04, 0.06), rough=0.18, coat=0.60)
MOUTH = mat("MouthCavity", (0.30, 0.07, 0.09), rough=0.58)

rider_parts = []
stick_parts = []

# Facing -Y (glTF +Z forward after export); back faces +Y (chase camera sees +Y).
# ---------------------------------------------------------------- lofted organic legs (slightly bent athletic stance)
for side, x in [("L", -0.118), ("R", 0.118)]:
    # Continuous hip -> thigh -> slightly-forward knee -> sculpted calf -> ankle (zero seams!)
    leg_stations = [
        ((x,  0.005, 0.78), 0.104, 0.106),
        ((x, -0.012, 0.60), 0.092, 0.095),
        ((x, -0.036, 0.43), 0.078, 0.082),  # slightly bent knee forward (-Y)
        ((x, -0.020, 0.30), 0.080, 0.084),  # calf fullness
        ((x, -0.004, 0.16), 0.066, 0.068),  # lower shin into sock
    ]
    rider_parts.append(loft_tube(f"Leg_{side}", leg_stations, seg=16, material=SKIN))

    # Crew sock hugging the lower shin + crisp crimson athletic stripe
    sock_stations = [
        ((x, -0.004, 0.165), 0.071, 0.073),
        ((x, -0.002, 0.110), 0.070, 0.072),
        ((x, -0.005, 0.048), 0.072, 0.078),
    ]
    rider_parts.append(loft_tube(f"Sock_{side}", sock_stations, seg=16, material=SOCK))
    rider_parts.append(torus(f"SockStripe_{side}", (x, -0.003, 0.145), 0.071, 0.006, seg=18, sides=6, material=SHIRT))

    # Grounded chunky sport sandals (bottom strictly at z = 0.0000)
    rider_parts.append(box(f"SandalSole_{side}", (x, -0.042, 0.017), (0.152, 0.262, 0.034), material=RUBBER_DARK, smooth=False))
    rider_parts.append(box(f"SandalBed_{side}", (x, -0.042, 0.040), (0.146, 0.252, 0.014), material=SANDAL, smooth=False))
    rider_parts.append(box(f"SandalStrap_{side}", (x, -0.076, 0.063), (0.144, 0.058, 0.036), material=SANDAL, smooth=True))

# ---------------------------------------------------------------- sporty shorts (continuous pelvis + leg cuffs, ZERO floating rings!)
shorts_pelvis_stations = [
    ((0.0,  0.005, 0.72), 0.205, 0.185),
    ((0.0,  0.010, 0.82), 0.238, 0.212),
    ((0.0,  0.005, 0.91), 0.228, 0.200),
    ((0.0,  0.000, 0.97), 0.202, 0.178),  # snug waistband tucked cleanly under belly
]
rider_parts.append(loft_tube("ShortsPelvis", shorts_pelvis_stations, seg=22, material=SHORTS))
for side, x in [("L", -0.118), ("R", 0.118)]:
    cuff_stations = [
        ((x,  0.002, 0.82), 0.120, 0.122),
        ((x, -0.008, 0.69), 0.110, 0.112),
        ((x, -0.014, 0.62), 0.106, 0.108),
    ]
    rider_parts.append(loft_tube(f"ShortsLeg_{side}", cuff_stations, seg=16, material=SHORTS))
    rider_parts.append(torus(f"ShortsCuff_{side}", (x, -0.014, 0.625), 0.105, 0.008, seg=16, sides=6, material=SHIRT))

# ---------------------------------------------------------------- continuous lofted athletic T-shirt (NO floating hem ring!)
# Profile function for the shirt torso so NardusDecal conforms to the exact surface!
SHIRT_PROFILE = [
    # (z, cy, rx, ry)
    (1.065,  0.012, 0.242, 0.210),  # snug rolled bottom hem
    (1.095,  0.014, 0.268, 0.234),
    (1.160,  0.016, 0.294, 0.258),  # lower-mid back
    (1.235,  0.016, 0.302, 0.266),  # broadest chest/back
    (1.310,  0.012, 0.290, 0.254),  # upper back / shoulders
    (1.375,  0.004, 0.240, 0.208),
    (1.425, -0.006, 0.135, 0.125),  # neckline
]
shirt_stations = [((0.0, cy, z), rx, ry, (0.0, 0.0, 1.0)) for (z, cy, rx, ry) in SHIRT_PROFILE]
rider_parts.append(loft_tube("ShirtTorso", shirt_stations, seg=26, material=SHIRT))

# Flush crew-neck ribbed collar sitting directly on the neckline
rider_parts.append(torus("ShirtCollar", (0.0, -0.008, 1.430), 0.095, 0.018, seg=20, sides=8, material=TRIM_GOLD))

# ---------------------------------------------------------------- dynamic bent-arm pogo pose (lofted sleeves + arms + sculpted hands!)
for side, sgn in [("L", -1), ("R", 1)]:
    # Short fitted sleeve starting tucked inside torso and curving smoothly down-out
    sleeve_stations = [
        ((sgn * 0.170,  0.008, 1.315), 0.078, 0.078),  # tucked inside torso
        ((sgn * 0.240,  0.005, 1.312), 0.106, 0.106),  # rounded deltoid shoulder
        ((sgn * 0.315,  0.001, 1.295), 0.096, 0.096),
        ((sgn * 0.388, -0.004, 1.268), 0.086, 0.086),
    ]
    rider_parts.append(loft_tube(f"Sleeve_{side}", sleeve_stations, seg=16, material=SHIRT))
    # Flush gold athletic cuff band right at the sleeve opening
    sleeve_dir = Vector((sgn * 0.168, -0.009, -0.067)).normalized()
    cuff_rot = sleeve_dir.to_track_quat('Z', 'Y').to_euler()
    rider_parts.append(torus(f"SleeveTrim_{side}", (sgn * 0.386, -0.004, 1.269), 0.085, 0.009,
                             rot=cuff_rot, seg=18, sides=6, material=TRIM_GOLD))

    # Continuous lofted arm: upper arm angling down-out -> bent elbow -> forearm raised forward-up!
    arm_stations = [
        ((sgn * 0.355, -0.002, 1.280), 0.072, 0.070),  # inside sleeve
        ((sgn * 0.445, -0.008, 1.238), 0.064, 0.062),  # mid bicep
        ((sgn * 0.525, -0.022, 1.202), 0.058, 0.056),  # bent elbow!
        ((sgn * 0.578, -0.085, 1.268), 0.054, 0.052),  # mid forearm raised forward-up
        ((sgn * 0.618, -0.150, 1.352), 0.044, 0.042),  # wrist
    ]
    rider_parts.append(loft_tube(f"Arm_{side}", arm_stations, seg=14, material=SKIN))

    # Sculpted energetic fist/hand + thumb at the wrist tip
    hx, hy, hz = sgn * 0.635, -0.175, 1.388
    rider_parts.append(sph(f"Hand_{side}", (hx, hy, hz), (0.056, 0.054, 0.058), seg=14, ring=10, material=SKIN))
    rider_parts.append(sph(f"Knuckles_{side}", (hx - sgn * 0.014, hy - 0.032, hz + 0.012),
                           (0.038, 0.028, 0.034), seg=10, ring=8, material=SKIN))
    rider_parts.append(sph(f"Thumb_{side}", (hx - sgn * 0.042, hy - 0.014, hz + 0.026),
                           (0.024, 0.026, 0.032), seg=10, ring=6, material=SKIN))

# ---------------------------------------------------------------- BELLY (separate Rider/Belly pivot for PogoVisual.gd!)
# Generous round gut peeking hilariously below the tight shirt hem in front (-Y),
# tucked safely forward so it NEVER clips through the back of the shirt!
bm = bmesh.new()
bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
belly_mesh = bpy.data.meshes.new("BellyBody")
bm.to_mesh(belly_mesh)
bm.free()

belly = bpy.data.objects.new("Belly", belly_mesh)
for v in belly.data.vertices:
    v.co.x *= 0.285
    if v.co.y < 0.0:
        v.co.y *= 0.305   # big joyful front gut
    else:
        v.co.y *= 0.145   # tucked cleanly inside shirt/shorts back
    v.co.z = v.co.z * 0.195 - 0.195   # top pivot at local z = 0
belly.data.update()
belly.location = (0.0, -0.055, 1.185)
_link_only(belly)
set_smooth(belly, True)
belly.data.materials.append(SKIN)

# Navel merged into Belly so it bounces WITH the belly!
navel = sph("Navel", (0.0, -0.350, 0.972), (0.019, 0.014, 0.017), seg=12, ring=8, material=MOUTH)
bpy.ops.object.select_all(action="DESELECT")
belly.select_set(True)
navel.select_set(True)
bpy.context.view_layer.objects.active = belly
bpy.ops.object.join()
belly = bpy.context.active_object
belly.name = "Belly"

# ---------------------------------------------------------------- expressive head & matte sculpted hair
# Neck + joyful chubby double-chin
rider_parts.append(cyl("Neck", (0.0, -0.010, 1.462), 0.072, 0.10, seg=14, material=SKIN))
rider_parts.append(sph("DoubleChin", (0.0, -0.062, 1.472), (0.088, 0.062, 0.036), seg=14, ring=8, material=SKIN))
# Smooth stylized cranium
rider_parts.append(sph("Head", (0.0, -0.015, 1.568), (0.138, 0.132, 0.144), seg=20, ring=14, material=SKIN))
# Warm rosy chubby cheeks
for sgn in [-1, 1]:
    rider_parts.append(sph(f"Cheek_{sgn}", (sgn * 0.074, -0.108, 1.538),
                           (0.046, 0.038, 0.036), seg=12, ring=8, material=SKIN_BLUSH))
# Ears
for sgn in [-1, 1]:
    rider_parts.append(sph(f"Ear_{sgn}", (sgn * 0.138, -0.012, 1.564),
                           (0.028, 0.024, 0.046), seg=12, ring=8, material=SKIN))
# Cheeky round nose
rider_parts.append(sph("Nose", (0.0, -0.155, 1.555), (0.030, 0.034, 0.028), seg=12, ring=8, material=SKIN))
# Expressive eyes: sclera + dark iris + bright specular catchlight
for sgn in [-1, 1]:
    rider_parts.append(sph(f"EyeWhite_{sgn}", (sgn * 0.050, -0.136, 1.585),
                           (0.034, 0.018, 0.028), seg=12, ring=8, material=EYE_WHITE))
    rider_parts.append(sph(f"Pupil_{sgn}", (sgn * 0.050, -0.152, 1.585),
                           (0.016, 0.010, 0.018), seg=10, ring=6, material=EYE_DARK))
    rider_parts.append(sph(f"Catchlight_{sgn}", (sgn * 0.056, -0.160, 1.593),
                           (0.0055, 0.004, 0.0055), seg=8, ring=6, material=EYE_WHITE))
# Expressive angled thick eyebrows
for sgn in [-1, 1]:
    rider_parts.append(box(f"Brow_{sgn}", (sgn * 0.052, -0.144, 1.625),
                           (0.060, 0.016, 0.019), rot=(0.0, sgn * math.radians(-10), sgn * math.radians(-8)),
                           material=HAIR, smooth=True))
# Sculpted chevron mustache
for sgn in [-1, 1]:
    rider_parts.append(sph(f"Mustache_{sgn}", (sgn * 0.038, -0.148, 1.525),
                           (0.048, 0.018, 0.018), rot=(0.0, sgn * math.radians(18), sgn * math.radians(-18)),
                           seg=12, ring=8, material=HAIR))
# Laughing open mouth + white teeth strip
rider_parts.append(sph("MouthOpen", (0.0, -0.136, 1.498), (0.052, 0.024, 0.030), seg=12, ring=8, material=MOUTH))
rider_parts.append(box("Teeth", (0.0, -0.148, 1.511), (0.076, 0.014, 0.014), material=EYE_WHITE, smooth=True))

# Matte-satin sculpted hair: crown + nape + sideburns + sculpted bangs/tufts
rider_parts.append(sph("HairCap", (0.0, 0.008, 1.620), (0.148, 0.142, 0.115), seg=20, ring=12, material=HAIR))
rider_parts.append(sph("HairBack", (0.0, 0.058, 1.568), (0.136, 0.104, 0.118), seg=18, ring=10, material=HAIR))
for sgn in [-1, 1]:
    rider_parts.append(sph(f"Sideburn_{sgn}", (sgn * 0.125, -0.045, 1.578),
                           (0.024, 0.032, 0.050), seg=10, ring=6, material=HAIR))
# Sculpted forehead tufts / messy fringe
for idx, (fx, fy, fz, fs) in enumerate([
    (-0.068, -0.105, 1.652, (0.046, 0.042, 0.030)),
    ( 0.000, -0.116, 1.662, (0.054, 0.046, 0.032)),
    ( 0.068, -0.105, 1.652, (0.046, 0.042, 0.030)),
    ( 0.000,  0.015, 1.718, (0.065, 0.055, 0.030)),  # slight crown tuft
]):
    rider_parts.append(sph(f"HairTuft_{idx}", (fx, fy, fz), fs, seg=10, ring=8, material=HAIR))

# ---------------------------------------------------------------- curved conformal NARDUS decal (back of shirt)
# Sampled directly from SHIRT_PROFILE (+Y back) offset +0.008m outward — zero clipping, zero floating!
# Emission driven from the texture itself (strength 0.10) so the dark #140E1E outline stays pitch-black!
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
    bsdf.inputs["Emission Strength"].default_value = 0.10
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
NU, NV = 16, 6
OFFSET = 0.008
PHI_HALF = math.radians(48.0)
Z_BOT, Z_TOP = 1.150, 1.345

grid = []
for j in range(NV + 1):
    v_coord = j / float(NV)
    z_val = Z_BOT + v_coord * (Z_TOP - Z_BOT)
    cy, rx, ry = _sample_shirt_profile(z_val)
    row = []
    for i in range(NU + 1):
        u_coord = i / float(NU)
        # u=0 -> +X (viewer left from back), u=1 -> -X (viewer right from back)
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

# ---------------------------------------------------------------- upgraded pogo stick
# Rubber bumper tip seated cleanly at z = 0.0000
stick_parts.append(loft_tube("PogoTip", [
    ((0.0, 0.0, 0.000), 0.022, 0.022),
    ((0.0, 0.0, 0.048), 0.032, 0.032),
], seg=14, material=RUBBER_DARK))
# Main chrome telescoping shaft
stick_parts.append(cyl("PogoShaft", (0.0, 0.0, 0.50), 0.026, 0.90, seg=14, material=POGO_CHROME))
# Anodized housing collar + spring seats
stick_parts.append(cyl("PogoHousing", (0.0, 0.0, 0.945), 0.038, 0.13, seg=16, material=POGO_ACCENT))
stick_parts.append(cyl("SpringSeatTop", (0.0, 0.0, 0.585), 0.072, 0.024, seg=16, material=POGO_ACCENT))
stick_parts.append(cyl("SpringSeatBot", (0.0, 0.0, 0.155), 0.072, 0.024, seg=16, material=POGO_ACCENT))
# Handlebar tucked cleanly inside belly width
stick_parts.append(cyl("Handlebar", (0.0, 0.0, 0.995), 0.017, 0.34,
                       rot=(0.0, math.radians(90), 0.0), seg=12, material=POGO_CHROME))
for sgn in [-1, 1]:
    stick_parts.append(cyl(f"Grip_{sgn}", (sgn * 0.145, 0.0, 0.995), 0.024, 0.08,
                           rot=(0.0, math.radians(90), 0.0), seg=12, material=RUBBER_DARK))
    stick_parts.append(sph(f"GripCap_{sgn}", (sgn * 0.188, 0.0, 0.995),
                           (0.022, 0.024, 0.024), seg=10, ring=6, material=TRIM_GOLD))
# Dual footplate + rubber grip pad (bottom strictly at z = 0.0000)
stick_parts.append(box("FootPlate", (0.0, -0.02, 0.014), (0.20, 0.13, 0.028), material=POGO_ACCENT, smooth=False))
stick_parts.append(box("FootPad", (0.0, -0.02, 0.031), (0.18, 0.11, 0.008), material=RUBBER_DARK, smooth=False))

# Helical spring curve -> converted to manifold welded mesh
helix_pts = []
for i in range(72):
    t = i / 71.0
    a = t * math.pi * 2 * 5
    helix_pts.append((math.cos(a) * 0.060, math.sin(a) * 0.060, 0.165 + t * 0.41))
curve = bpy.data.curves.new("Spring", "CURVE")
curve.dimensions = '3D'
sp = curve.splines.new("POLY")
sp.points.add(len(helix_pts) - 1)
for i, p in enumerate(helix_pts):
    sp.points[i].co = (p[0], p[1], p[2], 1.0)
curve.bevel_depth = 0.012
curve.bevel_resolution = 2
curve.resolution_u = 1
curve.use_fill_caps = True
spring = bpy.data.objects.new("PogoSpring", curve)
_link_only(spring)
spring.data.materials.append(POGO_CHROME)
bpy.ops.object.select_all(action="DESELECT")
spring.select_set(True)
bpy.context.view_layer.objects.active = spring
bpy.ops.object.convert(target="MESH")
spring = bpy.context.active_object
bm_sp = bmesh.new()
bm_sp.from_mesh(spring.data)
bmesh.ops.remove_doubles(bm_sp, verts=bm_sp.verts, dist=1e-4)
bm_sp.to_mesh(spring.data)
bm_sp.free()
set_smooth(spring, True)
stick_parts.append(spring)

# ---------------------------------------------------------------- consolidate static meshes (draw-call reduction!)
rider_body = join_objects("RiderBody", rider_parts)
stick_body = join_objects("StickBody", stick_parts)

# ---------------------------------------------------------------- muzzle empties (preserved exact names & coords!)
mz_l = bpy.data.objects.new("BananaMuzzle_L", None)
mz_l.empty_display_type = 'PLAIN_AXES'
mz_l.empty_display_size = 0.07
mz_l.location = (-0.235, -0.09, 0.995)
col.objects.link(mz_l)

mz_r = bpy.data.objects.new("BananaMuzzle_R", None)
mz_r.empty_display_type = 'PLAIN_AXES'
mz_r.empty_display_size = 0.07
mz_r.location = (0.235, -0.09, 0.995)
col.objects.link(mz_r)

# ---------------------------------------------------------------- hierarchy: Rider / Stick at scene root
rider = bpy.data.objects.new("Rider", None)
stick = bpy.data.objects.new("Stick", None)
col.objects.link(rider)
col.objects.link(stick)

for ob in (rider_body, belly, decal):
    if ob is not None:
        ob.parent = rider

for ob in (stick_body, mz_l, mz_r):
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
    ("KeyWarm", "AREA", (-2.6, -2.4, 2.6), (1.0, 0.90, 0.78), 420, 1.8),
    ("RimOrange", "SPOT", (3.2, 1.8, 1.8), (1.0, 0.48, 0.14), 1300, 1.0),
    ("RimCyan", "SPOT", (-3.1, 1.6, 1.8), (0.45, 0.85, 1.0), 1200, 1.0),
    ("TopSlate", "AREA", (0.0, 0.4, 4.4), (0.65, 0.75, 1.0), 360, 1.8),
    ("FillBack", "AREA", (0.0, 3.4, 1.55), (1.0, 0.95, 0.90), 340, 2.2),
    ("FillFront", "AREA", (0.0, -3.6, 1.35), (1.0, 0.90, 0.84), 320, 2.2),
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
    ob.rotation_euler = (Vector((0, 0, 1.05)) - ob.location).to_track_quat("-Z", "Y").to_euler()

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
        "front34": ((1.55, -2.55, 1.18), 32, (0.0, 0.0, 0.98)),
        "back34": ((1.55, 2.55, 1.18), 32, (0.0, 0.0, 0.98)),
        "front": ((0.0, -2.95, 1.18), 34, (0.0, 0.0, 0.98)),
        "back": ((0.0, 2.95, 1.18), 34, (0.0, 0.0, 0.98)),
        "back_closeup": ((0.0, 1.35, 1.24), 42, (0.0, 0.0, 1.24)),
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
