#!/usr/bin/env python3
"""PRINCESS — the Borat pogo-stick menace: procedural stylized sculpt + export.

Blender source of truth for the Pogo_Princess vehicle. Never edit the .blend
or the GLB by hand; edit this script and rebuild:

    blender -b -noaudio -P src/build_pogo_princess.py
    blender -b -noaudio -P src/build_pogo_princess.py -- --previews /tmp/out

Builds a fresh scene from primitives (mirroring src/build_quad.py), saves
Pogo_Princess.blend at the repo root, exports godot/assets/Pogo_Princess.glb
(excludes proof floor/lights/camera) and prints the QA gate (verts,
faces, non-manifold edges, minZ). The character mesh budget is ~5k verts —
the GLB must stay well under the web pck 4 MB gate.

Textures: assets/decal_princess.png (gold PRINCESS, correct reading orientation)
is applied as an image-texture quad on the mankini back — never text geometry.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEWS = None
if "--previews" in argv:
    PREVIEWS = argv[argv.index("--previews") + 1]
    os.makedirs(PREVIEWS, exist_ok=True)
OUT = REPO_ROOT

# ---------------------------------------------------------------- scaffold
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.length_unit = 'METERS'
# fresh file
for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.cameras, bpy.data.lights):
    for x in list(blk):
        blk.remove(x)

col = bpy.data.collections.new("PogoPrincess")
scene.collection.children.link(col)


def add(name, build_fn, coll=col):
    ob = build_fn(name)
    ob.name = name
    coll.objects.link(ob)
    return ob


def sph(name, loc, scale, seg=18, ring=11):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=ring, radius=1.0,
                                         location=loc)
    t = bpy.context.active_object
    t.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    t.name = name
    for c in list(t.users_collection):
        c.objects.unlink(t)
    col.objects.link(t)
    return t


def cyl(name, loc, radius, depth, rot=(0, 0, 0), seg=14):
    bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=radius, depth=depth,
                                        location=loc, rotation=rot)
    t = bpy.context.active_object
    t.name = name
    for c in list(t.users_collection):
        c.objects.unlink(t)
    col.objects.link(t)
    return t


def box(name, loc, size, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    t = bpy.context.active_object
    t.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    t.name = name
    for c in list(t.users_collection):
        c.objects.unlink(t)
    col.objects.link(t)
    return t


def torus(name, loc, major, minor, rot=(0, 0, 0), seg=32, sides=8):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     major_segments=seg, minor_segments=sides,
                                     location=loc, rotation=rot)
    t = bpy.context.active_object
    t.name = name
    for c in list(t.users_collection):
        c.objects.unlink(t)
    col.objects.link(t)
    return t


def _srgb(c):
    # display sRGB -> scene-linear (Blender shader inputs want linear)
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def mat(name, base, rough=0.55, metal=0.0, subsurface=0.0, sheen=0.0, coat=0.0,
        emission=None, emission_strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
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
        for key in ("Emission Strength",):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = emission_strength
                break
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m


SKIN = mat("Skin", (0.72, 0.45, 0.27), rough=0.6, subsurface=0.08)
MANKINI = mat("MankiniHotPink", (1.0, 0.25, 0.60), rough=0.32, coat=0.6, sheen=0.15)
MANKINI_DEEP = mat("MankiniDeep", (0.95, 0.13, 0.45), rough=0.4, coat=0.35)
HAIR = mat("HairDark", (0.15, 0.09, 0.05), rough=0.45)
SOCK = mat("SockPink", (0.98, 0.55, 0.75), rough=0.7)
SANDAL = mat("SandalBrown", (0.42, 0.25, 0.12), rough=0.68)
NAVEL = mat("Navel", (0.45, 0.26, 0.19), rough=0.6)
POGO = mat("PogoChrome", (0.86, 0.83, 0.95), rough=0.22, metal=0.85)
POGO_PINK = mat("PogoPink", (1.0, 0.25, 0.62), rough=0.28, metal=0.35, coat=0.6)
SPRING = mat("SpringSteel", (0.55, 0.55, 0.62), rough=0.2, metal=0.9)
EYE_W = mat("EyeWhite", (0.96, 0.96, 0.94), rough=0.25)
EYE_B = mat("EyeDark", (0.05, 0.05, 0.06), rough=0.3)
BROW = mat("Brow", (0.11, 0.06, 0.03), rough=0.5)
MOUTH = mat("MouthCavity", (0.23, 0.07, 0.08), rough=0.55)
TEETH = mat("Teeth", (0.94, 0.9, 0.82), rough=0.3)


def face_assign(ob, m):
    ob.data.materials.append(m)
    return ob


# facing -Y (glTF +Z forward after export); back faces +Y
# ---------------------------------------------------------------- legs
for side, x in [("L", -0.115), ("R", 0.115)]:
    cyl(f"Thigh_{side}", (x, 0.0, 0.60), 0.098, 0.46, seg=20).data.materials.append(SKIN)
    cyl(f"Shin_{side}", (x, 0.0, 0.205), 0.076, 0.30, seg=20).data.materials.append(SKIN)
    cyl(f"Sock_{side}", (x, 0.0, 0.075), 0.082, 0.15, seg=20).data.materials.append(SOCK)
    box(f"Sandal_{side}", (x, -0.045, 0.0275), (0.17, 0.27, 0.055)).data.materials.append(SANDAL)

# ---------------------------------------------------------------- pelvis + torso (pear)
sph("Pelvis", (0.0, 0.0, 0.88), (0.19, 0.17, 0.17)).data.materials.append(SKIN)
torso = sph("Torso", (0.0, 0.0, 1.13), (0.255, 0.23, 0.235))
torso.data.materials.append(SKIN)
sph("Chest", (0.0, 0.0, 1.27), (0.275, 0.24, 0.20)).data.materials.append(SKIN)

# BELLY: its own object, origin at the TOP attach point so Godot can swing it
import bmesh
from mathutils import Matrix
bm = bmesh.new()
bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
belly = bpy.data.objects.new("Belly", bpy.data.meshes.new("BellyBody"))
bm.to_mesh(belly.data)
bm.free()
for v in belly.data.vertices:
    v.co.x *= 0.35
    v.co.y *= 0.33
    v.co.z = v.co.z * 0.30 - 0.30     # squash z then drop so origin sits at top
belly.data.update()
belly.location = (0.0, -0.045, 1.39)   # top attach at chest/belly junction
col.objects.link(belly)
belly.data.materials.append(SKIN)

# navel
sph("Navel", (0.0, -0.352, 0.99), (0.021, 0.021, 0.021)).data.materials.append(NAVEL)

# ---------------------------------------------------------------- mankini
# waistband: torus hugging the belly bottom
torus("Waistband", (0.0, -0.01, 0.975), 0.295, 0.042,
      rot=(math.radians(90), 0.0, 0.0)).data.materials.append(MANKINI_DEEP)
# front brief "arrow"
cp = sph("BriefFront", (0.0, -0.19, 0.93), (0.165, 0.10, 0.14))
cp.data.materials.append(MANKINI)
# spine strap: hot-pink vertical strap neck->waist (the Borat signature)
box("SpineStrap", (0.0, 0.253, 1.185), (0.125, 0.024, 0.46),
    rot=(math.radians(-3), 0.0, 0.0)).data.materials.append(MANKINI)
# shoulder straps (over-the-shoulder)
for i, sgn in enumerate([-1, 1]):
    box("ShoulderStrap_%d" % i, (sgn * 0.155, 0.0, 1.33),
        (0.085, 0.44, 0.042), rot=(math.radians(13), 0.0, math.radians(sgn * 9))).data.materials.append(MANKINI)

# ---------------------------------------------------------------- head
sph("Head", (0.0, -0.02, 1.505), (0.135, 0.125, 0.135)).data.materials.append(SKIN)
# ears
for sgn in [-1, 1]:
    sph("Ear_%d" % sgn, (sgn * 0.133, -0.02, 1.50), (0.03, 0.022, 0.045)).data.materials.append(SKIN)
# nose
sph("Nose", (0.0, -0.158, 1.49), (0.03, 0.034, 0.03)).data.materials.append(SKIN)
# mouth cavity: flattened dark ellipse + teeth strip
m = sph("MouthOpen", (0.0, -0.140, 1.443), (0.058, 0.024, 0.034))
m.data.materials.append(MOUTH)
box("Teeth", (0.0, -0.152, 1.455), (0.092, 0.017, 0.017)).data.materials.append(TEETH)
# eyes
for sgn in [-1, 1]:
    sph("EyeWhite_%d" % sgn, (sgn * 0.052, -0.139, 1.512), (0.037, 0.015, 0.022)).data.materials.append(EYE_W)
    sph("Pupil_%d" % sgn, (sgn * 0.052, -0.1525, 1.512), (0.015, 0.0085, 0.015)).data.materials.append(EYE_B)
# unibrow: one wide angled box
box("Unibrow", (0.0, -0.143, 1.555), (0.125, 0.011, 0.026),
    rot=(0.0, 0.0, math.radians(4))).data.materials.append(BROW)
# mustache: two squashed wings angled down
for sgn in [-1, 1]:
    box("Mustache_%d" % sgn, (sgn * 0.043, -0.149, 1.466),
        (0.068, 0.013, 0.026), rot=(0.0, 0.0, math.radians(sgn * -26))).data.materials.append(HAIR)
# bowl cut: cap sphere + fringe ring of bumps
cap = sph("HairCap", (0.0, 0.015, 1.548), (0.147, 0.136, 0.125))
cap.data.materials.append(HAIR)
cap = sph("HairBack", (0.0, 0.058, 1.508), (0.133, 0.103, 0.125))
cap.data.materials.append(HAIR)

# ---------------------------------------------------------------- arms (spread wide, Borat preen)
for side, sgn in [("L", -1), ("R", 1)]:
    cyl(f"UpperArm_{side}", (sgn * 0.335, 0.0, 1.255), 0.070, 0.31,
        rot=(0.0, math.radians(71), 0.0)).data.materials.append(SKIN)
    cyl(f"Forearm_{side}", (sgn * 0.55, 0.0, 1.265), 0.058, 0.29,
        rot=(0.0, math.radians(71), 0.0)).data.materials.append(SKIN)
    sph(f"Hand_{side}", (sgn * 0.715, 0.0, 1.27), (0.062, 0.058, 0.066)).data.materials.append(SKIN)

# ---------------------------------------------------------------- pogo stick
cyl("PogoShaft", (0.0, 0.0, 0.46), 0.028, 0.92, seg=16).data.materials.append(POGO)
cyl("PogoHandTop", (0.0, 0.0, 0.965), 0.036, 0.11, seg=16).data.materials.append(POGO_PINK)
# handlebar
cyl("Handlebar", (0.0, 0.0, 0.995), 0.016, 0.46, rot=(0.0, math.radians(90), 0.0),
    seg=12).data.materials.append(POGO)
for sgn in [-1, 1]:
    sph("Grip_%d" % sgn, (sgn * 0.235, 0.0, 0.995), (0.034, 0.034, 0.034)).data.materials.append(POGO_PINK)
# foot plate
box("FootPlate", (0.0, -0.02, 0.014), (0.16, 0.12, 0.028)).data.materials.append(POGO_PINK)
# spring: helix curve with bevel
helix_pts = []
for i in range(90):
    t = i / 89.0
    a = t * math.pi * 2 * 5
    helix_pts.append((math.cos(a) * 0.062, math.sin(a) * 0.062, 0.16 + t * 0.42))
curve = bpy.data.curves.new("Spring", "CURVE")
curve.dimensions = '3D'
sp = curve.splines.new("POLY")
sp.points.add(len(helix_pts) - 1)
for i, p in enumerate(helix_pts):
    sp.points[i].co = (p[0], p[1], p[2], 1.0)
curve.bevel_depth = 0.013
curve.bevel_resolution = 3
curve.resolution_u = 2
spring = bpy.data.objects.new("PogoSpring", curve)
col.objects.link(spring)
spring.data.materials.append(SPRING)

# ---------------------------------------------------------------- muzzle empties + belly pivot note
mz = bpy.data.objects.new("BananaMuzzle_L", None)
mz.empty_display_type = 'PLAIN_AXES'
mz.empty_display_size = 0.07
mz.location = (-0.235, -0.09, 0.995)
col.objects.link(mz)
mz = bpy.data.objects.new("BananaMuzzle_R", None)
mz.empty_display_type = 'PLAIN_AXES'
mz.empty_display_size = 0.07
mz.location = (0.235, -0.09, 0.995)
col.objects.link(mz)

# ---------------------------------------------------------------- PRINCESS decal (back)
dec_img = bpy.data.images.load(os.path.join(REPO_ROOT, "assets/decal_princess.png"))
dec_mat = mat("DecalPrincess", (1.0, 1.0, 1.0), rough=0.3,
              emission=(1.0, 0.78, 0.25), emission_strength=0.6)
tex = dec_mat.node_tree.nodes.new("ShaderNodeTexImage")
tex.image = dec_img
bsdf = next(n for n in dec_mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
dec_mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
if "Alpha" in tex.outputs and "Alpha" in bsdf.inputs:
    dec_mat.node_tree.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
dec_mat.blend_method = 'CLIP'
bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0.0, 0.305, 1.16),
                                 rotation=(math.radians(-90), 0.0, 0.0))
decal = bpy.context.active_object
decal.name = "PrincessDecal"
decal.scale = (0.36, 0.14, 1.0)
for c in list(decal.users_collection):
    c.objects.unlink(decal)
col.objects.link(decal)
decal.data.materials.append(dec_mat)

# smooth-shade the sculpt (fat-guy read, no faceted icosahedron)
for ob in col.objects:
    if ob.type == "MESH" and ob.name != "PrincessDecal":
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.shade_smooth()

# split rider (bobs in Godot) vs stick (the pogo — stays planted)
rider = bpy.data.objects.new("Rider", None)
stick = bpy.data.objects.new("Stick", None)
col.objects.link(rider)
col.objects.link(stick)
STICK_PREFIXES = ("PogoShaft", "PogoHandTop", "Handlebar", "Grip_", "FootPlate",
                  "PogoSpring", "BananaMuzzle_")
for ob in list(col.objects):
    if ob in (rider, stick):
        continue
    if ob.name.startswith(STICK_PREFIXES):
        ob.parent = stick
    elif ob.type in {"LIGHT", "CAMERA"} or ob.name == "ProofFloor":
        pass
    else:
        ob.parent = rider

# Rider/Stick stay at the scene root: the GLB imports one level flat
# (file root -> Rider/Stick), matching the bike GLB's layout.

# ---------------------------------------------------------------- world/lights/cam
world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
wt = world.node_tree
wt.nodes.clear()
bg = wt.nodes.new("ShaderNodeBackground")
bg.inputs["Color"].default_value = (0.012, 0.02, 0.055, 1.0)
bg.inputs["Strength"].default_value = 1.0
out = wt.nodes.new("ShaderNodeOutputWorld")
wt.links.new(bg.outputs["Background"], out.inputs["Surface"])

lights = [
    ("KeyWarm", "AREA", (-2.6, -2.4, 2.6), (1.0, 0.87, 0.74), 380, 1.6),
    ("RimOrange", "SPOT", (3.2, 1.8, 1.6), (1.0, 0.42, 0.09), 1700, 1.0),
    ("RimLime", "SPOT", (-3.1, 1.6, 1.7), (0.42, 1.0, 0.55), 1550, 1.0),
    ("TopSlate", "AREA", (0.0, 0.4, 4.4), (0.55, 0.66, 1.0), 400, 1.7),
    ("FillFront", "AREA", (0.0, -3.6, 1.35), (1.0, 0.88, 0.82), 300, 2.2),
]
for name, typ, loc, lc, energy, size in lights:
    data = bpy.data.lights.new(name, typ)
    data.color = lc
    data.energy = energy
    if typ == "AREA":
        data.size = size
    else:
        data.spot_size = math.radians(28)
        data.spot_blend = 0.35
    ob = bpy.data.objects.new(name, data)
    col.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (Vector((0, 0, 1.0)) - ob.location).to_track_quat("-Z", "Y").to_euler()

cam_data = bpy.data.cameras.new("Camera")
cam = bpy.data.objects.new("Camera", cam_data)
col.objects.link(cam)
scene.camera = cam

# floor disc (proof only — not exported to game GLB; hidden during export is fine)
bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=1.4, depth=0.02, location=(0, 0, -0.01))
floor = bpy.context.active_object
floor.name = "ProofFloor"
for c in list(floor.users_collection):
    c.objects.unlink(floor)
col.objects.link(floor)
floor.data.materials.append(mat("FloorNavy", (0.018, 0.028, 0.085), rough=0.95))

scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1600
scene.render.resolution_y = 900
scene.view_settings.look = "AgX - Base Contrast"
scene.eevee.taa_render_samples = 64

if PREVIEWS:
    views = {
        "front34": ((1.6, -2.6, 1.15), 30),
        "back34": ((1.6, 2.6, 1.15), 30),
        "front": ((0.0, -3.0, 1.15), 32),
        "back": ((0.0, 3.0, 1.15), 32),
    }
    for name, (loc, lens) in views.items():
        cam.location = loc
        cam.data.lens = lens
        tgt = Vector((0.0, 0.0, 0.98))
        cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(PREVIEWS, "princess_%s.png" % name)
        bpy.ops.render.render(write_still=True)

# save blend (includes proof floor/lights/cam — fine for source file)
blend_path = os.path.join(REPO_ROOT, "Pogo_Princess.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend_path)
print("SAVED", blend_path)


# ---------------------------------------------------------------- export GLB
EXCLUDE = {"ProofFloor", "KeyWarm", "RimOrange", "RimLime", "TopSlate", "FillFront", "Camera"}
bpy.ops.object.select_all(action="DESELECT")
for ob in col.objects:
    if ob.name not in EXCLUDE:
        ob.select_set(True)
glb_path = os.path.join(REPO_ROOT, "godot/assets/Pogo_Princess.glb")
try:
    bpy.ops.export_scene.gltf(filepath=glb_path, export_format="GLB",
                              use_selection=True, export_yup="Y",
                              export_cameras=False, export_lights=False)
except TypeError:
    bpy.ops.export_scene.gltf(filepath=glb_path, export_format="GLB",
                              use_selection=True,
                              export_cameras=False, export_lights=False)
print("GLB_SAVED", glb_path)

# ---------------------------------------------------------------- QA stats
import bmesh
verts = tris = 0
non_manifold = 0
min_z = 1e9
for ob in col.objects:
    if ob.name in EXCLUDE or ob.type != "MESH":
        continue
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    verts += len(bm.verts)
    tris += len(bm.faces)  # glTF triangulates; this is the raw ngon count
    bm.edges.ensure_lookup_table()
    if ob.name == "PrincessDecal":
        continue  # 2D print plane, open boundary by design
    non_manifold += sum(1 for e in bm.edges if not e.is_manifold)
    min_z = min(min_z, min((ob.matrix_world @ v.co).z for v in bm.verts))
    bm.free()
print("QA verts=%d faces=%d non_manifold_edges=%d min_z=%.4f" % (verts, tris, non_manifold, min_z))
