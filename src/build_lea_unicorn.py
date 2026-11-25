#!/usr/bin/env python3
"""LEA UNICORN — stylized pastel winged unicorn vehicle stand-in.

Blender source of truth. Never hand-edit Lea_Unicorn.blend or its GLB; edit
this script and rebuild:

    blender -b -noaudio --threads 4 -P src/build_lea_unicorn.py
    blender -b -noaudio --threads 4 -P src/build_lea_unicorn.py -- --previews /tmp/lea

Pipeline (surgical-building, creative-brief branch — no vanishing-point
metrology: the five references are stylized 2D illustrations). An authored
dimension spec is emitted to ``lea_spatial_manifest.json`` at the repo root.

Deliverables
------------
* ``Lea_Unicorn.blend``                     editable source
* ``godot/assets/Lea_Unicorn.glb``          plain GLB (Godot 4.3 here has no
                                            Draco importer), 52-joint creature
                                            rig, 4 baked NLA actions
* ``Lea_Unicorn.stl``                       QA mesh (watertight, minZ = 0)
* ``lea_spatial_manifest.json``             authored dim spec for QA
* optional ``--previews DIR``               material renders

Rig: 52-joint equine/winged creature rig, rigidly bound (weight 1.0) per mesh.
Landmark mesh names are immutable — Godot gates and weapon anchors resolve
them recursively from the glTF import:

    HornTip, HornBase, HornMuzzle_L, HornMuzzle_R,
    Wing_L, Wing_R, ManeForelock, TailRoot,
    Eye_L, Eye_R, Hoof_FL, Hoof_FR, Hoof_RL, Hoof_RR

Coordinate contract: Blender +Z up / -Y forward -> glTF +Y up / -Z forward.
Ground datum AABB bottom = 0.000 m (all four hooves touch the floor).
"""
from __future__ import annotations

from collections import defaultdict
import json
import math
import os
import sys
from typing import Any

import bmesh
import bpy
from mathutils import Matrix, Vector

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SPEC = {
    "width_x": 2.45,   # wingspan at full spread
    "depth_y": 1.85,
    "height_z": 1.94,  # horn tip
}

BONE_COUNT = 52
ACTION_NAMES = (
    "Idle_Breathe",
    "Locomotion_Gallop",
    "Action_WingSpread",
    "UnicornBoom_Flight",
)

LANDMARKS = {
    "HornTip", "HornBase", "HornMuzzle_L", "HornMuzzle_R",
    "Wing_L", "Wing_R", "ManeForelock", "TailRoot",
    "Eye_L", "Eye_R", "Hoof_FL", "Hoof_FR", "Hoof_RL", "Hoof_RR",
    "LeaBrand",
}


def ensure_node_tree(datablock: Any) -> Any:
    """Blender 4.x/5.x safe node-tree access (5.x node trees exist by default)."""
    if bpy.app.version < (5, 0, 0) and hasattr(datablock, "use_nodes"):
        datablock.use_nodes = True
    return datablock.node_tree


def make_mat(name: str, color: tuple[float, float, float], rough: float = 0.6,
             metallic: float = 0.0, emission: float = 0.0,
             coat: float = 0.0, coat_rough: float = 0.15) -> Any:
    m = bpy.data.materials.new(name=name)
    tree = ensure_node_tree(m)
    tree.nodes.clear()
    out = tree.nodes.new("ShaderNodeOutputMaterial")
    bsdf = tree.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    if emission > 0.0 and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    if coat > 0.0 and "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat
        if "Coat Roughness" in bsdf.inputs:
            bsdf.inputs["Coat Roughness"].default_value = coat_rough
    tree.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m


def build_lea(argv: list[str] | None = None) -> dict[str, Any]:
    if argv is None:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    previews = None
    if "--previews" in argv:
        _idx = argv.index("--previews")
        if _idx + 1 >= len(argv) or not argv[_idx + 1].strip():
            raise SystemExit("--previews requires a non-empty directory argument")
        previews = argv[_idx + 1]
    if previews:
        os.makedirs(previews, exist_ok=True)

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.length_unit = "METERS"

    # -------------------------------------------------------------- scaffold
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.curves,
                bpy.data.cameras, bpy.data.lights, bpy.data.actions,
                bpy.data.images, bpy.data.armatures):
        for x in list(blk):
            blk.remove(x)

    col = bpy.data.collections.new("LeaUnicorn")
    scene.collection.children.link(col)

    def link_only(ob: Any) -> Any:
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        col.objects.link(ob)
        return ob

    def smooth(ob: Any) -> Any:
        if ob.type == "MESH" and ob.data.polygons:
            ob.data.polygons.foreach_set("use_smooth", [True] * len(ob.data.polygons))
            ob.data.update()
        return ob

    # -------------------------------------------------------------- palette
    # Pastel reference: pearlescent ivory coat, pink/lavender mane, rainbow
    # feather gradients, gold horn and hooves, sapphire eyes.
    # Plastic Surgery skin pass: the references show an iridescent blue-white
    # pearlescent coat, not a warm white. Keep luminance high (~0.90) so the
    # body still reads against the dark arena backdrop. Geometry, rig and all
    # landmark material names are untouched — this is albedo/roughness only.
    coat = make_mat("PearlCoat", (0.89, 0.92, 0.99), 0.30, emission=0.045, coat=0.45, coat_rough=0.14)
    coat_shade = make_mat("CoatShadow", (0.70, 0.74, 0.88), 0.46, coat=0.20)
    muzzle_mat = make_mat("MuzzleVelvet", (0.74, 0.66, 0.68), 0.66)
    mane_pink = make_mat("ManePink", (0.97, 0.38, 0.73), 0.32, emission=0.075, coat=0.22)
    mane_lav = make_mat("ManeLavender", (0.75, 0.54, 0.96), 0.34, emission=0.065, coat=0.22)
    feather_pink = make_mat("FeatherPink", (0.99, 0.52, 0.78), 0.34, emission=0.06, coat=0.22)
    feather_lav = make_mat("FeatherLavender", (0.72, 0.58, 0.96), 0.34, emission=0.06, coat=0.22)
    feather_cyan = make_mat("FeatherCyan", (0.42, 0.85, 0.96), 0.30, emission=0.08, coat=0.22)
    feather_gold = make_mat("FeatherGold", (0.99, 0.78, 0.34), 0.32, emission=0.06, coat=0.22)
    gold = make_mat("HornGold", (0.96, 0.74, 0.24), 0.18, metallic=0.85, emission=0.08, coat=0.35)
    horn_glow = make_mat("HornGlow", (1.0, 0.94, 0.62), 0.16, emission=0.85)
    hoof_gold = make_mat("HoofGold", (0.92, 0.68, 0.22), 0.22, metallic=0.78, emission=0.05)
    eye_blue = make_mat("EyeSapphire", (0.12, 0.42, 0.86), 0.14, emission=0.14, coat=0.50)
    pupil_dark = make_mat("PupilDark", (0.012, 0.016, 0.028), 0.35)

    lea_brand_mat = bpy.data.materials.new(name="LeaBrandMat")
    _lb_tree = ensure_node_tree(lea_brand_mat)
    _lb_tree.nodes.clear()
    _lb_out = _lb_tree.nodes.new("ShaderNodeOutputMaterial")
    _lb_bsdf = _lb_tree.nodes.new("ShaderNodeBsdfPrincipled")
    _lb_bsdf.inputs["Roughness"].default_value = 0.28
    _lb_bsdf.inputs["Metallic"].default_value = 0.35
    _lb_tex_path = os.path.join(REPO_ROOT, "assets", "decal_lea_brand.png")
    if os.path.exists(_lb_tex_path):
        _lb_tex = _lb_tree.nodes.new("ShaderNodeTexImage")
        _lb_img = bpy.data.images.load(_lb_tex_path, check_existing=True)
        _lb_img.pack()
        _lb_tex.image = _lb_img
        _lb_tree.links.new(_lb_tex.outputs["Color"], _lb_bsdf.inputs["Base Color"])
        _lb_tree.links.new(_lb_tex.outputs["Alpha"], _lb_bsdf.inputs["Alpha"])
        if "Emission Color" in _lb_bsdf.inputs:
            _lb_tree.links.new(_lb_tex.outputs["Color"], _lb_bsdf.inputs["Emission Color"])
            _lb_bsdf.inputs["Emission Strength"].default_value = 0.16
    if hasattr(lea_brand_mat, "blend_method"):
        lea_brand_mat.blend_method = "CLIP"
    if hasattr(lea_brand_mat, "alpha_threshold"):
        lea_brand_mat.alpha_threshold = 0.45
    lea_brand_mat.use_backface_culling = True
    _lb_tree.links.new(_lb_bsdf.outputs["BSDF"], _lb_out.inputs["Surface"])

    # -------------------------------------------------------------- primitives
    def box(name: str, loc: tuple[float, float, float], dims: tuple[float, float, float],
            material: Any, rot: tuple[float, float, float] | None = None) -> Any:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
        ob = link_only(bpy.context.active_object)
        ob.name = name
        ob.scale = dims
        if rot:
            ob.rotation_euler = rot
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        ob.data.materials.append(material)
        return ob

    def sphere(name: str, loc: tuple[float, float, float], scale: tuple[float, float, float],
               material: Any, seg: int = 12, rings: int = 8,
               rot: tuple[float, float, float] | None = None) -> Any:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings,
                                             radius=1.0, location=loc)
        ob = link_only(bpy.context.active_object)
        ob.name = name
        ob.scale = scale
        if rot:
            ob.rotation_euler = rot
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        ob.data.materials.append(material)
        return smooth(ob)

    def cyl(name: str, loc: tuple[float, float, float], radius: float, depth: float,
            material: Any, rot: tuple[float, float, float] | None = None,
            vertices: int = 10, radius2: float | None = None) -> Any:
        if radius2 is None:
            bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
                                                 depth=depth, location=loc)
        else:
            bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius,
                                             radius2=radius2, depth=depth, location=loc)
        ob = link_only(bpy.context.active_object)
        ob.name = name
        if rot:
            ob.rotation_euler = rot
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=False)
        ob.data.materials.append(material)
        return ob

    def _orthonormal_frame(axis: Vector) -> tuple[Vector, Vector]:
        ref = Vector((0.0, 1.0, 0.0)) if abs(axis.y) < 0.9 else Vector((1.0, 0.0, 0.0))
        u = axis.cross(ref).normalized()
        v = axis.cross(u).normalized()
        return u, v

    def tube(name: str, points: list[Vector], radius_x: float, material: Any,
             seg: int = 6, radius_y: float | None = None,
             taper_tail: float = 1.0) -> Any:
        """Watertight lofted tube (oval cross-section, optional tail taper)."""
        ry = radius_x if radius_y is None else radius_y
        pts = [Vector(p) for p in points]
        n = len(pts)
        tans: list[Vector] = []
        for i in range(n):
            if i == 0:
                tans.append((pts[1] - pts[0]).normalized())
            elif i == n - 1:
                tans.append((pts[-1] - pts[-2]).normalized())
            else:
                tans.append((pts[i + 1] - pts[i - 1]).normalized())
        u, _ = _orthonormal_frame(tans[0])
        frames = [(u, tans[0].cross(u).normalized())]
        for i in range(1, n):
            axis = tans[i - 1].cross(tans[i])
            if axis.length > 1e-6:
                rot = Matrix.Rotation(tans[i - 1].angle(tans[i]), 3, axis.normalized())
                u = (rot @ u).normalized()
            frames.append((u, tans[i].cross(u).normalized()))
        bm = bmesh.new()
        rings = []
        for i, c in enumerate(pts):
            u_i, v_i = frames[i]
            s = 1.0 + (taper_tail - 1.0) * (i / max(1, n - 1))
            ring = [bm.verts.new(c + u_i * (math.cos(2 * math.pi * j / seg) * radius_x * s)
                                 + v_i * (math.sin(2 * math.pi * j / seg) * ry * s))
                    for j in range(seg)]
            rings.append(ring)
        for i in range(n - 1):
            for j in range(seg):
                jn = (j + 1) % seg
                bm.faces.new((rings[i][j], rings[i][jn], rings[i + 1][jn], rings[i + 1][j]))
        c0 = bm.verts.new(pts[0])
        c1 = bm.verts.new(pts[-1])
        for j in range(seg):
            jn = (j + 1) % seg
            bm.faces.new((c0, rings[0][jn], rings[0][j]))
            bm.faces.new((c1, rings[-1][j], rings[-1][jn]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh = bpy.data.meshes.new(name + "_Mesh")
        bm.to_mesh(mesh)
        bm.free()
        ob = bpy.data.objects.new(name, mesh)
        link_only(ob)
        ob.data.materials.append(material)
        return smooth(ob)

    # -------------------------------------------------------------- 52-joint rig
    def bone_spec() -> list[dict[str, Any]]:
        bones: list[dict[str, Any]] = [
            {"name": "Hips", "head": (0.0, 0.20, 0.92), "tail": (0.0, 0.12, 1.04), "parent": None},
            {"name": "Spine", "head": (0.0, 0.12, 1.04), "tail": (0.0, -0.02, 1.20), "parent": "Hips"},
            {"name": "Chest", "head": (0.0, -0.02, 1.20), "tail": (0.0, -0.16, 1.34), "parent": "Spine"},
            {"name": "Withers", "head": (0.0, -0.16, 1.34), "tail": (0.0, -0.26, 1.44), "parent": "Chest"},
            {"name": "Neck1", "head": (0.0, -0.26, 1.44), "tail": (0.0, -0.40, 1.58), "parent": "Withers"},
            {"name": "Neck2", "head": (0.0, -0.40, 1.58), "tail": (0.0, -0.52, 1.68), "parent": "Neck1"},
            {"name": "Skull", "head": (0.0, -0.52, 1.68), "tail": (0.0, -0.66, 1.72), "parent": "Neck2"},
            {"name": "Jaw", "head": (0.0, -0.60, 1.62), "tail": (0.0, -0.76, 1.56), "parent": "Skull"},
        ]
        for side, sx in (("L", 1.0), ("R", -1.0)):
            # Foreleg (shoulder -> hoof)
            fore = [
                ("ForeShoulder", (0.19, -0.14, 1.26), (0.22, -0.14, 1.10)),
                ("ForeUpper", (0.22, -0.14, 1.10), (0.23, -0.18, 0.78)),
                ("Forearm", (0.23, -0.18, 0.78), (0.23, -0.19, 0.44)),
                ("ForeCannon", (0.23, -0.19, 0.44), (0.235, -0.20, 0.20)),
                ("ForeFetlock", (0.235, -0.20, 0.20), (0.235, -0.21, 0.10)),
                ("ForeHoof", (0.235, -0.21, 0.10), (0.235, -0.25, 0.035)),
            ]
            # Hind leg (haunch -> hoof)
            hind = [
                ("HindHaunch", (0.19, 0.22, 1.00), (0.22, 0.24, 0.86)),
                ("HindThigh", (0.22, 0.24, 0.86), (0.23, 0.34, 0.60)),
                ("HindGaskin", (0.23, 0.34, 0.60), (0.235, 0.27, 0.34)),
                ("HindCannon", (0.235, 0.27, 0.34), (0.235, 0.24, 0.17)),
                ("HindFetlock", (0.235, 0.24, 0.17), (0.235, 0.22, 0.09)),
                ("HindHoof", (0.235, 0.22, 0.09), (0.235, 0.19, 0.035)),
            ]
            for chain, parent in ((fore, "Chest"), (hind, "Hips")):
                prev = parent
                for stem, head, tail in chain:
                    name = f"{stem}.{side}"
                    bones.append({"name": name,
                                  "head": (sx * head[0], head[1], head[2]),
                                  "tail": (sx * tail[0], tail[1], tail[2]),
                                  "parent": prev})
                    prev = name
            wing = [
                ("WingScapula", (0.18, -0.02, 1.34), (0.34, 0.04, 1.46)),
                ("WingHumerus", (0.34, 0.04, 1.46), (0.62, 0.02, 1.58)),
                ("WingRadius", (0.62, 0.02, 1.58), (0.92, 0.06, 1.62)),
                ("WingHand", (0.92, 0.06, 1.62), (1.16, 0.12, 1.60)),
                ("PrimaryFan1", (1.00, 0.06, 1.60), (1.34, 0.16, 1.72)),
                ("PrimaryFan2", (1.00, 0.06, 1.60), (1.30, 0.20, 1.50)),
                ("SecondaryFan", (0.60, 0.04, 1.52), (0.88, 0.22, 1.42)),
                ("WingCoverts", (0.36, 0.03, 1.44), (0.66, 0.20, 1.40)),
            ]
            prev = "Withers"
            for stem, head, tail in wing:
                name = f"{stem}.{side}"
                bones.append({"name": name,
                              "head": (sx * head[0], head[1], head[2]),
                              "tail": (sx * tail[0], tail[1], tail[2]),
                              "parent": prev})
                prev = name
        bones.extend([
            # Bone stems intentionally differ from the landmark mesh names
            # (ManeForelock / TailRoot / TailTip) so glTF node names stay unique
            # and Godot's recursive find_child() cannot resolve the wrong node.
            {"name": "ManeLock", "head": (0.0, -0.28, 1.48), "tail": (0.0, -0.46, 1.64), "parent": "Withers"},
            {"name": "ManeTuft", "head": (0.0, -0.58, 1.70), "tail": (0.0, -0.62, 1.84), "parent": "Skull"},
            {"name": "TailBase", "head": (0.0, 0.26, 1.04), "tail": (0.0, 0.38, 1.00), "parent": "Hips"},
            {"name": "TailEnd", "head": (0.0, 0.38, 1.00), "tail": (0.0, 0.52, 0.88), "parent": "TailBase"},
        ])
        return bones

    spec = bone_spec()
    assert len(spec) == BONE_COUNT, f"rig spec has {len(spec)} bones, expected {BONE_COUNT}"
    heads = {b["name"]: Vector(b["head"]) for b in spec}
    tails = {b["name"]: Vector(b["tail"]) for b in spec}

    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    arm = link_only(bpy.context.active_object)
    arm.name = "LeaRig"
    arm.data.name = "LeaRig_Creature52"
    for b in list(arm.data.edit_bones):
        arm.data.edit_bones.remove(b)
    created: dict[str, Any] = {}
    for item in spec:
        eb = arm.data.edit_bones.new(item["name"])
        eb.head = Vector(item["head"])
        eb.tail = Vector(item["tail"])
        if item["parent"]:
            eb.parent = created[item["parent"]]
        # Deterministic bone rolls: axial bones align local +Y with world +Z,
        # wing bones use world +X as reference so flap rotations are predictable.
        ref = Vector((1.0, 0.0, 0.0)) if "Wing" in item["name"] or "Fan" in item["name"] \
            else Vector((0.0, -1.0, 0.0))
        eb.align_roll(ref)
        created[item["name"]] = eb
    bpy.ops.object.mode_set(mode="OBJECT")

    parts: list[tuple[Any, str]] = []

    def bind(ob: Any, bone: str) -> Any:
        parts.append((ob, bone))
        return ob

    # -------------------------------------------------------------- barrel & neck
    bind(sphere("Barrel", (0.0, 0.02, 1.06), (0.275, 0.46, 0.28), coat, 14, 10), "Spine")
    bind(sphere("ChestMass", (0.0, -0.30, 1.16), (0.255, 0.26, 0.27), coat, 12, 9), "Chest")
    bind(sphere("HaunchMass", (0.0, 0.30, 1.02), (0.29, 0.27, 0.29), coat, 12, 9), "Hips")
    bind(sphere("ShoulderMass_L", (0.185, -0.20, 1.15), (0.115, 0.16, 0.20), coat, 10, 7), "Chest")
    bind(sphere("ShoulderMass_R", (-0.185, -0.20, 1.15), (0.115, 0.16, 0.20), coat, 10, 7), "Chest")
    bind(sphere("GirthShadow", (0.0, -0.08, 0.90), (0.215, 0.32, 0.10), coat_shade, 12, 8), "Spine")
    bind(tube("NeckSculpt", [Vector((0, -0.24, 1.36)), Vector((0, -0.36, 1.50)),
                             Vector((0, -0.48, 1.62)), Vector((0, -0.56, 1.70))],
              0.105, coat, 10, radius_y=0.125, taper_tail=0.72), "Neck1")
    bind(sphere("WithersCrest", (0.0, -0.22, 1.45), (0.10, 0.13, 0.075), coat, 10, 7), "Withers")

    # -------------------------------------------------------------- head / muzzle
    bind(sphere("SkullMass", (0.0, -0.62, 1.71), (0.115, 0.155, 0.125), coat, 12, 9), "Skull")
    bind(sphere("MuzzleMass", (0.0, -0.79, 1.585), (0.072, 0.092, 0.064), muzzle_mat, 12, 8,
                rot=(math.radians(-14), 0, 0)), "Skull")
    bind(sphere("NoseBlaze", (0.0, -0.875, 1.60), (0.052, 0.026, 0.035), coat_shade, 10, 7), "Skull")
    bind(tube("JawSculpt", [Vector((0, -0.66, 1.60)), Vector((0, -0.76, 1.565)),
                            Vector((0, -0.84, 1.56))], 0.055, muzzle_mat, 8, 0.070, 0.80), "Jaw")
    for side, sx in (("L", 1.0), ("R", -1.0)):
        bind(cyl(f"Ear_{side}", (sx * 0.070, -0.575, 1.82), 0.030, 0.105, coat,
                 vertices=8, radius2=0.003,
                 rot=(math.radians(-12), 0, sx * math.radians(-16))), "Skull")
        eye = sphere(f"Eye_{side}", (sx * 0.103, -0.688, 1.735), (0.027, 0.032, 0.027),
                     eye_blue, 10, 7)
        bind(eye, "Skull")
        bind(sphere(f"Pupil_{side}", (sx * 0.126, -0.703, 1.738), (0.011, 0.014, 0.014),
                    pupil_dark, 8, 6), "Skull")
        bind(sphere(f"EyeGlint_{side}", (sx * 0.132, -0.713, 1.747), (0.005, 0.006, 0.005),
                    coat, 6, 5), "Skull")

    # -------------------------------------------------------------- spiralled horn
    horn_base = Vector((0.0, -0.715, 1.795))
    horn_tip = Vector((0.0, -0.905, 2.075))
    horn_axis = (horn_tip - horn_base).normalized()
    h_u, h_v = _orthonormal_frame(horn_axis)
    bind(cyl("HornBase", tuple(horn_base), 0.048, 0.036, gold, vertices=10,
             rot=tuple(horn_axis.to_track_quat("Z", "Y").to_euler())), "Skull")
    bind(cyl("HornCollar", tuple(horn_base - horn_axis * 0.008), 0.054, 0.020, gold, vertices=12,
             rot=tuple(horn_axis.to_track_quat("Z", "Y").to_euler())), "Skull")
    for i in range(9):
        t0 = i / 9.0
        t1 = (i + 1) / 9.0
        r0 = 0.043 * (1.0 - t0 * 0.94)
        r1 = 0.043 * (1.0 - t1 * 0.94)
        c0 = horn_base + (horn_tip - horn_base) * t0
        c1 = horn_base + (horn_tip - horn_base) * t1
        ang = t0 * math.pi * 5.0
        c0 += (h_u * math.cos(ang) + h_v * math.sin(ang)) * r0 * 0.34
        c1 += (h_u * math.cos(ang + math.pi * 0.55)
               + h_v * math.sin(ang + math.pi * 0.55)) * r1 * 0.34
        seg = cyl(f"HornSpiral_{i:02d}", tuple((c0 + c1) * 0.5), max(r0, 0.004),
                  (c1 - c0).length * 1.06, gold, vertices=8, radius2=max(r1, 0.002),
                  rot=tuple((c1 - c0).normalized().to_track_quat("Z", "Y").to_euler()))
        bind(seg, "Skull")
    bind(sphere("HornTip", tuple(horn_tip), (0.013, 0.013, 0.017), horn_glow, 8, 6), "Skull")
    for side, sx in (("L", 1.0), ("R", -1.0)):
        bind(sphere(f"HornMuzzle_{side}", (sx * 0.026, -0.724, 1.806),
                    (0.010, 0.010, 0.010), horn_glow, 8, 6), "Skull")

    # -------------------------------------------------------------- legs & hooves
    for side, sx in (("L", 1.0), ("R", -1.0)):
        for tag, chain in (("F", ("ForeShoulder", "ForeUpper", "Forearm", "ForeCannon", "ForeFetlock")),
                           ("R", ("HindHaunch", "HindThigh", "HindGaskin", "HindCannon", "HindFetlock"))):
            for stem in chain:
                name = f"{stem}.{side}"
                h, t = heads[name], tails[name]
                ax = (t - h).normalized()
                radius = 0.054 if "Shoulder" in stem or "Haunch" in stem else \
                    (0.046 if "Upper" in stem or "Thigh" in stem else 0.028)
                if "Cannon" in stem or "Fetlock" in stem:
                    radius = 0.022
                ob = cyl(f"Leg_{name}", tuple((h + t) * 0.5), radius, (t - h).length * 1.02,
                         coat, vertices=8, radius2=radius * 0.82,
                         rot=tuple(ax.to_track_quat("Z", "Y").to_euler()))
                bind(ob, name)
            hoof_name = f"{'ForeHoof' if tag == 'F' else 'HindHoof'}.{side}"
            h, t = heads[hoof_name], tails[hoof_name]
            hoof = cyl(f"Hoof_{'F' if tag == 'F' else 'R'}{side}",
                       tuple((h + t) * 0.5), 0.047, (t - h).length * 1.06, hoof_gold,
                       vertices=8, radius2=0.055,
                       rot=tuple((t - h).normalized().to_track_quat("Z", "Y").to_euler()))
            bind(hoof, hoof_name)
            bind(cyl(f"FetlockTuft_{tag}{side}", (h.x, h.y + 0.006, h.z + 0.018),
                     0.038, 0.052, coat_shade, vertices=8, radius2=0.022), hoof_name)
            bind(sphere(f"FetlockGem_{tag}{side}", (h.x, h.y, h.z + 0.035),
                        (0.016, 0.016, 0.016), mane_lav, 8, 6), hoof_name)

    # -------------------------------------------------------------- wings
    feather_mats = (feather_pink, feather_lav, feather_cyan, feather_gold)
    for side, sx in (("L", 1.0), ("R", -1.0)):
        # Leading-edge membrane/coverts landmark (Wing_L / Wing_R).
        coverts_pts = [Vector((sx * 0.30, 0.02, 1.42)),
                       Vector((sx * 0.58, 0.02, 1.54)),
                       Vector((sx * 0.90, 0.06, 1.60)),
                       Vector((sx * 1.16, 0.12, 1.58))]
        bind(tube(f"Wing_{side}", coverts_pts, 0.045, coat_shade, 8, 0.075, 0.90),
             f"WingHand.{side}")
        # Layered feather fan: 12 long primaries + 8 secondaries per wing,
        # each split into a root and a tip segment for the colour gradient.
        feather_specs: list[tuple[Vector, Vector, str, Any, Any]] = []
        for i in range(12):
            u = i / 11.0
            root = Vector((sx * (0.98 + u * 0.20), 0.07 + u * 0.05, 1.62 - u * 0.10))
            tip = Vector((sx * (1.24 + u * 0.42), 0.22 + u * 0.30, 1.74 - u * 0.52))
            bone = "PrimaryFan1" if i < 6 else "PrimaryFan2"
            mat_a = feather_mats[i % 2]
            mat_b = feather_cyan if i % 3 else feather_gold
            feather_specs.append((root, tip, bone, mat_a, mat_b))
        for i in range(8):
            u = i / 7.0
            root = Vector((sx * (0.48 + u * 0.40), 0.08, 1.50 - u * 0.06))
            tip = Vector((sx * (0.72 + u * 0.44), 0.30 + u * 0.14, 1.36 - u * 0.24))
            bone = "SecondaryFan" if i < 5 else "WingCoverts"
            feather_specs.append((root, tip, bone, feather_pink, feather_lav))
        for fi, (root, tip, bone, mat_root, mat_tip) in enumerate(feather_specs):
            mid = root + (tip - root) * 0.56
            bind(tube(f"FeatherRoot_{side}_{fi:02d}",
                      [root, root + (mid - root) * 0.5, mid],
                      0.014, mat_root, 5, 0.048, 0.78), f"{bone}.{side}")
            bind(tube(f"FeatherTip_{side}_{fi:02d}",
                      [mid, mid + (tip - mid) * 0.5, tip],
                      0.011, mat_tip, 5, 0.040, 0.24), f"{bone}.{side}")
        # Small shoulder covert row hides the wing-root hinge.
        for i in range(5):
            u = i / 4.0
            root = Vector((sx * (0.28 + u * 0.06), 0.02, 1.40 + u * 0.045))
            tip = Vector((sx * (0.46 + u * 0.10), 0.20 + u * 0.03, 1.36 + u * 0.05))
            bind(tube(f"Covert_{side}_{i}", [root, (root + tip) * 0.5, tip],
                      0.010, feather_pink if i % 2 else feather_lav, 5, 0.028, 0.34),
                 f"WingScapula.{side}")
        bind(sphere(f"WingBridge_{side}", (sx * 0.21, -0.02, 1.32),
                    (0.075, 0.11, 0.075), coat, 8, 6), f"WingScapula.{side}")

    # -------------------------------------------------------------- "Lea" brand on right butt cheek
    # Conforms to the right (-X, +Y) flank of HaunchMass ((0, 0.30, 1.02), radii=(0.29, 0.27, 0.29)).
    # phi goes 60 deg (closer to tail = viewer's left 'L') -> 12 deg (right flank = viewer's right 'a').
    LB_NU, LB_NV = 10, 6
    bm_lb = bmesh.new()
    uv_lb = bm_lb.loops.layers.uv.new("UVMap")
    lb_out_grid: list[list[Any]] = []
    lb_in_grid: list[list[Any]] = []
    for j in range(LB_NV + 1):
        v_c = j / float(LB_NV)
        theta = math.radians(-12.0 + v_c * 44.0)
        orow: list[Any] = []
        irow: list[Any] = []
        for i in range(LB_NU + 1):
            u_c = i / float(LB_NU)
            phi = math.radians(60.0 - u_c * 48.0)
            ct, st = math.cos(theta), math.sin(theta)
            cp, sp = math.cos(phi), math.sin(phi)
            vo = bm_lb.verts.new((-0.29 * 1.018 * ct * cp, 0.30 + 0.27 * 1.018 * ct * sp, 1.02 + 0.29 * 1.018 * st))
            vi = bm_lb.verts.new((-0.29 * 0.985 * ct * cp, 0.30 + 0.27 * 0.985 * ct * sp, 1.02 + 0.29 * 0.985 * st))
            orow.append((vo, u_c, v_c))
            irow.append(vi)
        lb_out_grid.append(orow)
        lb_in_grid.append(irow)

    for j in range(LB_NV):
        for i in range(LB_NU):
            vo00, u00, w00 = lb_out_grid[j][i]
            vo10, u10, w10 = lb_out_grid[j][i + 1]
            vo11, u11, w11 = lb_out_grid[j + 1][i + 1]
            vo01, u01, w01 = lb_out_grid[j + 1][i]
            fo = bm_lb.faces.new((vo00, vo10, vo11, vo01))
            fo.smooth = True
            for loop, uv in zip(fo.loops, [(u00, w00), (u10, w10), (u11, w11), (u01, w01)]):
                loop[uv_lb].uv = uv
            fi = bm_lb.faces.new((lb_in_grid[j + 1][i], lb_in_grid[j + 1][i + 1],
                                  lb_in_grid[j][i + 1], lb_in_grid[j][i]))
            for loop in fi.loops:
                loop[uv_lb].uv = (0.01, 0.01)

    for i in range(LB_NU):
        for f_rim in (
            bm_lb.faces.new((lb_in_grid[0][i], lb_in_grid[0][i + 1],
                             lb_out_grid[0][i + 1][0], lb_out_grid[0][i][0])),
            bm_lb.faces.new((lb_out_grid[LB_NV][i][0], lb_out_grid[LB_NV][i + 1][0],
                             lb_in_grid[LB_NV][i + 1], lb_in_grid[LB_NV][i])),
        ):
            for loop in f_rim.loops:
                loop[uv_lb].uv = (0.01, 0.01)
    for j in range(LB_NV):
        for f_rim in (
            bm_lb.faces.new((lb_out_grid[j][0][0], lb_out_grid[j + 1][0][0],
                             lb_in_grid[j + 1][0], lb_in_grid[j][0])),
            bm_lb.faces.new((lb_in_grid[j][LB_NU], lb_in_grid[j + 1][LB_NU],
                             lb_out_grid[j + 1][LB_NU][0], lb_out_grid[j][LB_NU][0])),
        ):
            for loop in f_rim.loops:
                loop[uv_lb].uv = (0.01, 0.01)

    bmesh.ops.recalc_face_normals(bm_lb, faces=bm_lb.faces)
    lb_mesh = bpy.data.meshes.new("LeaBrand_Mesh")
    bm_lb.to_mesh(lb_mesh)
    bm_lb.free()
    lb_ob = bpy.data.objects.new("LeaBrand", lb_mesh)
    link_only(lb_ob)
    lb_ob.data.materials.append(lea_brand_mat)
    smooth(lb_ob)
    bind(lb_ob, "Hips")

    # -------------------------------------------------------------- mane & tail
    for i in range(15):
        u = i / 14.0
        y0 = -0.28 - u * 0.32
        z0 = 1.45 + u * 0.26
        root = Vector((math.sin(u * math.pi) * 0.085, y0, z0 + 0.012))
        mid = root + Vector((math.sin(u * 6.0) * 0.055, 0.060, -0.080))
        tip = mid + Vector((math.sin(u * 6.0 + 1.0) * 0.075, 0.060, -0.18 - 0.10 * u))
        bone = "ManeLock" if i < 11 else "ManeTuft"
        bind(tube(f"ManeStrand_{i:02d}", [root, mid, tip], 0.021,
                  mane_pink if i % 3 else mane_lav, 5, 0.034, 0.22), bone)
    bind(tube("ManeForelock", [Vector((0, -0.57, 1.72)), Vector((0.01, -0.60, 1.80)),
                               Vector((0.02, -0.64, 1.86))], 0.020, mane_pink, 6, 0.032, 0.30),
         "ManeTuft")
    for i in range(11):
        u = i / 10.0
        root = Vector((math.sin(u * 4.0) * 0.035, 0.28, 1.03 - u * 0.02))
        mid = root + Vector((math.sin(u * 5.0) * 0.06, 0.16, -0.035))
        tip = mid + Vector((math.sin(u * 5.0 + 0.8) * 0.10, 0.20 + u * 0.05, -0.14 - u * 0.06))
        bone = "TailBase" if i < 6 else "TailEnd"
        bind(tube(f"TailStrand_{i:02d}", [root, mid, tip], 0.023,
                  mane_pink if i % 3 else mane_lav, 5, 0.038, 0.20), bone)
    bind(tube("TailRoot", [Vector((0, 0.26, 1.05)), Vector((0, 0.38, 1.00)),
                           Vector((0, 0.50, 0.90))], 0.031, mane_lav, 7, 0.045, 0.44),
         "TailBase")

    # -------------------------------------------------------------- rigid skin binding
    for ob, bone_name in parts:
        vg = ob.vertex_groups.new(name=bone_name)
        vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
        ob.parent = arm
        mod = ob.modifiers.new(name="LeaSkin", type="ARMATURE")
        mod.object = arm
        mod.use_vertex_groups = True
        mod.use_bone_envelopes = False

    # -------------------------------------------------------------- batch by bone + material
    batches: dict[tuple[str, str], list[Any]] = defaultdict(list)
    merged: list[tuple[Any, str]] = []
    for ob, bone_name in parts:
        if ob.name in LANDMARKS:
            merged.append((ob, bone_name))
            continue
        mat_name = ob.data.materials[0].name if ob.data.materials else ""
        batches[(bone_name, mat_name)].append(ob)
    for (bone_name, mat_name), obs in batches.items():
        target_name = f"Lea_{bone_name}_{mat_name}"
        if len(obs) == 1:
            obs[0].name = target_name
            merged.append((obs[0], bone_name))
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for o in obs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        bpy.ops.object.join()
        joined = obs[0]
        joined.name = target_name
        merged.append((joined, bone_name))
    parts = merged
    print(f"[QA] batched into {len(parts)} skinned meshes")

    # -------------------------------------------------------------- 4 baked NLA actions
    pose = arm.pose.bones
    for pb in pose:
        pb.rotation_mode = "XYZ"

    # Axis assertions: body local +Y must lift the hips in world +Z; foreleg
    # +X must swing the knee forward (-Y); wing +Z must lift the wingtip.
    pose["Hips"].location = (0.0, 0.10, 0.0)
    bpy.context.view_layer.update()
    assert pose["Hips"].head.z > heads["Hips"].z + 0.05, "Hips local +Y is not world +Z"
    pose["Hips"].location = (0.0, 0.0, 0.0)

    pose["ForeUpper.L"].rotation_euler = (0.5, 0.0, 0.0)
    bpy.context.view_layer.update()
    assert pose["ForeUpper.L"].tail.y < tails["ForeUpper.L"].y - 0.08, \
        "ForeUpper.L +X did not swing the knee forward (-Y)"
    pose["ForeUpper.L"].rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()

    ANIMATED = (
        "Hips", "Spine", "Chest", "Withers", "Neck1", "Neck2", "Skull", "Jaw",
        "ManeLock", "ManeTuft", "TailBase", "TailEnd",
    )
    for side in ("L", "R"):
        ANIMATED += tuple(
            f"{stem}.{side}" for stem in (
                "ForeShoulder", "ForeUpper", "Forearm", "ForeCannon", "ForeFetlock", "ForeHoof",
                "HindHaunch", "HindThigh", "HindGaskin", "HindCannon", "HindFetlock", "HindHoof",
                "WingScapula", "WingHumerus", "WingRadius", "WingHand",
                "PrimaryFan1", "PrimaryFan2", "SecondaryFan", "WingCoverts",
            )
        )

    def _periodic(u: float, knots: tuple[float, ...]) -> float:
        n = len(knots)
        s = (u % 1.0) * n
        i = int(math.floor(s)) % n
        t = s - math.floor(s)
        p0, p1 = knots[(i - 1) % n], knots[i]
        p2, p3 = knots[(i + 1) % n], knots[(i + 2) % n]
        t2, t3 = t * t, t * t * t
        return 0.5 * ((2 * p1) + (-p0 + p2) * t
                      + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                      + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)

    def commit(action_name: str, frame_end: int, evaluator: Any) -> None:
        act = bpy.data.actions.new(name=action_name)
        arm.animation_data_create()
        arm.animation_data.action = act
        denom = max(1, frame_end - 1)
        for f in range(1, frame_end + 1):
            scene.frame_set(f)
            u = (f - 1) / denom
            for pb in pose:
                pb.rotation_euler = (0.0, 0.0, 0.0)
                pb.location = (0.0, 0.0, 0.0)
            evaluator(pose, u)
            for bname in ANIMATED:
                pose[bname].keyframe_insert(data_path="rotation_euler", frame=f)
            pose["Hips"].keyframe_insert(data_path="location", frame=f)
        track = arm.animation_data.nla_tracks.new()
        track.name = action_name
        track.strips.new(action_name, 1, act)
        arm.animation_data.action = None

    def _wing_fold(pb: Any, amount: float, flap: float = 0.0) -> None:
        """amount 0 = relaxed, 1 = fully expanded; flap is a global up/down stroke."""
        for side in ("L", "R"):
            sign = 1.0 if side == "L" else -1.0
            pb[f"WingScapula.{side}"].rotation_euler = (0.0, 0.0, sign * (0.10 + 0.22 * amount))
            pb[f"WingHumerus.{side}"].rotation_euler = (
                -0.16 * amount - flap * 0.55, sign * 0.10 * amount, sign * 0.12 * amount)
            pb[f"WingRadius.{side}"].rotation_euler = (
                0.18 * (1.0 - amount) + flap * 0.40, 0.0, sign * 0.06 * amount)
            pb[f"WingHand.{side}"].rotation_euler = (-0.10 * amount, 0.0, sign * 0.08 * amount)
            pb[f"PrimaryFan1.{side}"].rotation_euler = (0.0, 0.0, sign * 0.14 * amount)
            pb[f"PrimaryFan2.{side}"].rotation_euler = (0.0, 0.0, -sign * 0.10 * amount)
            pb[f"SecondaryFan.{side}"].rotation_euler = (0.0, 0.0, sign * 0.08 * amount)
            pb[f"WingCoverts.{side}"].rotation_euler = (0.0, 0.0, sign * 0.06 * amount)

    def _flow(pb: Any, u: float, amp: float = 1.0) -> None:
        t = u * 2.0 * math.pi
        pb["ManeLock"].rotation_euler = (0.12 * math.sin(t) * amp, 0.0, 0.10 * math.sin(t * 0.5))
        pb["ManeTuft"].rotation_euler = (-0.16 * math.sin(t) * amp, 0.0, 0.0)
        pb["TailBase"].rotation_euler = (0.0, 0.0, 0.20 * math.sin(t) * amp)
        pb["TailEnd"].rotation_euler = (0.0, 0.0, 0.14 * math.sin(t + 0.7) * amp)

    def idle(pb: Any, u: float) -> None:
        t = u * 2.0 * math.pi
        breath = 0.5 - 0.5 * math.cos(2.0 * t)
        pb["Hips"].location = (0.0, -0.010 * breath, 0.0)
        pb["Spine"].rotation_euler = (0.018 * breath, 0.0, 0.0)
        pb["Chest"].rotation_euler = (-0.02 * breath, 0.0, 0.0)
        pb["Neck2"].rotation_euler = (0.05 * math.sin(t), 0.0, 0.0)
        pb["Skull"].rotation_euler = (-0.05 * breath, 0.04 * math.sin(t * 0.5), 0.0)
        pb["Jaw"].rotation_euler = (0.05 * breath, 0.0, 0.0)
        _wing_fold(pb, 0.32, flap=0.04 * math.sin(t))
        _flow(pb, u, 0.55)

    # Four-beat gallop knots: fore L/R then hind L/R, phase shifted per leg.
    FORE_KNOTS = (0.72, 0.18, -0.62, -0.38, 0.10, 0.86, 1.02, 0.84)
    HIND_KNOTS = (-0.30, -0.58, -0.12, 0.82, 1.06, 0.62, -0.10, -0.34)
    CANNON_KNOTS = (0.08, 0.22, -0.30, -0.52, -0.18, 0.14, 0.20, 0.10)

    def gallop(pb: Any, u: float) -> None:
        t = u * 2.0 * math.pi
        bounce = -math.sin(4.0 * math.pi * u) * 0.055 + 0.008
        pb["Hips"].location = (0.012 * math.sin(t), bounce, 0.0)
        pb["Hips"].rotation_euler = (0.10, -0.03 * math.sin(t), 0.04 * math.sin(2.0 * t))
        pb["Spine"].rotation_euler = (-0.06, 0.04 * math.sin(t), -0.03 * math.sin(2.0 * t))
        pb["Chest"].rotation_euler = (-0.10, 0.03 * math.sin(t), 0.0)
        pb["Neck2"].rotation_euler = (0.14 * math.sin(2.0 * t), 0.0, 0.0)
        pb["Skull"].rotation_euler = (-0.14, 0.0, 0.0)
        for side, phase in (("L", 0.0), ("R", 0.28)):
            p = (u + phase) % 1.0
            q = (p + 0.52) % 1.0
            pb[f"ForeShoulder.{side}"].rotation_euler = (_periodic(p, FORE_KNOTS) * 0.55, 0, 0)
            pb[f"ForeUpper.{side}"].rotation_euler = (_periodic(p, FORE_KNOTS), 0, 0)
            pb[f"Forearm.{side}"].rotation_euler = (min(-0.1, _periodic(p, CANNON_KNOTS)), 0, 0)
            pb[f"ForeCannon.{side}"].rotation_euler = (_periodic(p, CANNON_KNOTS) * 0.6, 0, 0)
            pb[f"ForeFetlock.{side}"].rotation_euler = (0.16 * math.sin(4.0 * math.pi * p), 0, 0)
            pb[f"ForeHoof.{side}"].rotation_euler = (-0.10 * math.sin(4.0 * math.pi * p), 0, 0)
            pb[f"HindHaunch.{side}"].rotation_euler = (_periodic(q, HIND_KNOTS) * 0.55, 0, 0)
            pb[f"HindThigh.{side}"].rotation_euler = (_periodic(q, HIND_KNOTS), 0, 0)
            pb[f"HindGaskin.{side}"].rotation_euler = (min(-0.1, _periodic(q, CANNON_KNOTS)), 0, 0)
            pb[f"HindCannon.{side}"].rotation_euler = (_periodic(q, CANNON_KNOTS) * 0.6, 0, 0)
            pb[f"HindFetlock.{side}"].rotation_euler = (0.14 * math.sin(4.0 * math.pi * q), 0, 0)
            pb[f"HindHoof.{side}"].rotation_euler = (-0.10 * math.sin(4.0 * math.pi * q), 0, 0)
        _wing_fold(pb, 0.48, flap=0.05 * math.sin(2.0 * t))
        _flow(pb, u, 1.0)

    def wingspread(pb: Any, u: float) -> None:
        """Charge-up pose: wings expand and the horn levels at the target."""
        env = math.sin(min(u, 1.0) * math.pi)
        pb["Hips"].location = (0.0, 0.045 * env, 0.0)
        pb["Chest"].rotation_euler = (-0.16 * env, 0.0, 0.0)
        pb["Neck2"].rotation_euler = (0.24 * env, 0.0, 0.0)
        pb["Skull"].rotation_euler = (-0.20 * env, 0.0, 0.0)
        pb["Jaw"].rotation_euler = (0.22 * env, 0.0, 0.0)
        _wing_fold(pb, 0.30 + 0.70 * env)
        _flow(pb, u * 0.5, 0.8)

    def boom(pb: Any, u: float) -> None:
        """Leap -> full wing expansion -> powered flight -> strike touchdown."""
        env = math.sin(min(u, 1.0) * math.pi)
        flight = min(1.0, u / 0.35) if u < 0.72 else max(0.0, (1.0 - u) / 0.28)
        pb["Hips"].location = (0.0, 0.36 * env, 0.0)
        pb["Hips"].rotation_euler = (-0.16 * flight, 0.0, 0.0)
        pb["Chest"].rotation_euler = (-0.20 * flight, 0.0, 0.0)
        pb["Neck2"].rotation_euler = (0.22 * flight, 0.0, 0.0)
        pb["Skull"].rotation_euler = (-0.24 * flight, 0.0, 0.0)
        flap = math.sin(u * 4.0 * math.pi) * 0.85
        _wing_fold(pb, 0.32 + 0.68 * flight, flap=flap)
        for side in ("L", "R"):
            pb[f"ForeUpper.{side}"].rotation_euler = (0.85 * flight, 0.0, 0.0)
            pb[f"Forearm.{side}"].rotation_euler = (-1.05 * flight, 0.0, 0.0)
            pb[f"HindThigh.{side}"].rotation_euler = (-0.70 * flight, 0.0, 0.0)
            pb[f"HindGaskin.{side}"].rotation_euler = (1.05 * flight, 0.0, 0.0)
        _flow(pb, u * 2.0, 1.3)

    commit("Idle_Breathe", 48, idle)
    commit("Locomotion_Gallop", 24, gallop)
    commit("Action_WingSpread", 24, wingspread)
    commit("UnicornBoom_Flight", 36, boom)

    # World-space proof: at the charge peak the wings must expand outward and
    # lift relative to the relaxed idle pose (guards against flipped bone axes).
    arm.animation_data.use_nla = False
    for pb in pose:
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
    wingspread(pose, 0.5)
    bpy.context.view_layer.update()
    spread_z = pose["WingHand.L"].tail.z
    spread_x = pose["WingHand.L"].tail.x
    for pb in pose:
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
    idle(pose, 0.0)
    bpy.context.view_layer.update()
    relaxed_z = pose["WingHand.L"].tail.z
    assert spread_z > relaxed_z + 0.03, \
        f"WingSpread did not lift the wingtip: {spread_z:.3f} vs {relaxed_z:.3f}"
    assert spread_x > 1.0, f"WingSpread wingtip collapsed inward: x={spread_x:.3f}"
    for pb in pose:
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
    arm.animation_data.use_nla = True
    scene.frame_set(1)

    # -------------------------------------------------------------- proof studio
    world = bpy.data.worlds.new("LeaWorld")
    scene.world = world
    wt = ensure_node_tree(world)
    wt.nodes.clear()
    bg = wt.nodes.new("ShaderNodeBackground")
    bg.inputs["Color"].default_value = (0.10, 0.11, 0.18, 1.0)
    out = wt.nodes.new("ShaderNodeOutputWorld")
    wt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    for name, typ, loc, lc, energy in (
        ("KeyWarm", "AREA", (-2.2, -2.6, 3.0), (1.0, 0.93, 0.86), 520),
        ("RimPink", "SPOT", (3.2, 1.4, 2.2), (1.0, 0.40, 0.78), 1000),
        ("RimCyan", "SPOT", (-3.0, 1.8, 2.0), (0.48, 0.88, 1.0), 950),
    ):
        data = bpy.data.lights.new(name, typ)
        data.color = lc
        data.energy = energy
        if typ == "AREA":
            data.size = 2.0
        else:
            data.spot_size = math.radians(38)
        ob = bpy.data.objects.new(name, data)
        col.objects.link(ob)
        ob.location = loc
        ob.rotation_euler = (Vector((0, 0, 1.2)) - ob.location).to_track_quat("-Z", "Y").to_euler()
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    col.objects.link(cam)
    scene.camera = cam
    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in \
        bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items.keys() else "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.view_settings.look = "AgX - Base Contrast"

    # -------------------------------------------------------------- QA metrics
    arm.animation_data.use_nla = False
    for pb in pose:
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    verts = faces = non_manifold = 0
    gmin = Vector((float("inf"),) * 3)
    gmax = Vector((float("-inf"),) * 3)
    for ob, _ in parts:
        bm = bmesh.new()
        bm.from_object(ob, depsgraph)
        bm.transform(ob.matrix_world)
        verts += len(bm.verts)
        faces += len(bm.faces)
        non_manifold += sum(1 for e in bm.edges if not e.is_manifold)
        for v in bm.verts:
            for i in range(3):
                gmin[i] = min(gmin[i], v.co[i])
                gmax[i] = max(gmax[i], v.co[i])
        bm.free()
    arm.animation_data.use_nla = True
    dims = [round(gmax[i] - gmin[i], 6) for i in range(3)]
    print(f"[QA] verts={verts} faces={faces} non_manifold_edges={non_manifold} "
          f"minZ={gmin.z:.4f} bbox={dims}")
    assert faces < 10000, f"Lea mesh exceeded 10k tri budget ({faces} faces)"

    ground_shift = -gmin.z
    if abs(ground_shift) > 1e-9:
        arm.location.z += ground_shift
        gmin.z = 0.0
        gmax.z += ground_shift
        print(f"[QA] ground-seated by +{ground_shift:.4f} m -> minZ=0.0000")

    # -------------------------------------------------------------- author manifest
    manifest = {
        "image_resolution": [512, 512],
        "camera_telemetry": {
            "focal_length_px": None,
            "horizontal_fov_deg": None,
            "vanishing_points": None,
            "note": "Stylized 2D illustrations — vanishing-point metrology intentionally skipped.",
        },
        "metric_dimensions_m": {
            "width_x": dims[0], "depth_y": dims[1], "height_z": dims[2],
            "estimated_stories": 1, "roof_pitch_deg": 0.0,
            "wall_thickness_ext": 0.0, "wall_thickness_int": 0.0,
        },
        "pbr_palette_srgb": ["#dee6f7", "#f25cb5", "#bd85ef", "#6fd8f4", "#f2b83d"],
        "rig": {
            "bone_count": BONE_COUNT, "profile": "creature-winged-equine",
            "actions": list(ACTION_NAMES), "skinning": "rigid-1.0-vertex-groups",
        },
        "notes": ("Authored dimension spec for the stylized Lea Unicorn references in "
                  "docs/plans/Designs/Lea unicorn/. Winged unicorn vehicle stand-in, "
                  "ground datum minZ=0.000."),
    }
    manifest_path = os.path.join(REPO_ROOT, "lea_spatial_manifest.json")
    tmp_manifest = manifest_path + ".tmp"
    with open(tmp_manifest, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp_manifest, manifest_path)

    # -------------------------------------------------------------- save / export
    blend_path = os.path.join(REPO_ROOT, "Lea_Unicorn.blend")
    _filepaths = bpy.context.preferences.filepaths
    _prev_versions = _filepaths.save_version
    try:
        _filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    finally:
        _filepaths.save_version = _prev_versions
    print("SAVED", blend_path)

    bpy.ops.object.select_all(action="DESELECT")
    for ob, _ in parts:
        ob.select_set(True)
    arm.select_set(True)
    glb_path = os.path.join(REPO_ROOT, "godot/assets/Lea_Unicorn.glb")
    bpy.ops.export_scene.gltf(
        filepath=glb_path, export_format="GLB", use_selection=True, export_yup=True,
        export_cameras=False, export_lights=False, export_animations=True,
        export_nla_strips=True, export_draco_mesh_compression_enable=False,
    )
    print("GLB_SAVED", glb_path)

    # QA exports the REST pose: the GLB above is authored at frame 1 with NLA
    # strips active, so leaving that evaluated pose in the armature would make
    # the STL bbox disagree with the manifest (the QA reviewer rejects >2.5%).
    arm.animation_data.use_nla = False
    for pb in pose:
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    for ob, _ in parts:
        ob.select_set(True)
    stl_path = os.path.join(REPO_ROOT, "Lea_Unicorn.stl")
    if hasattr(bpy.ops.wm, "stl_export"):
        bpy.ops.wm.stl_export(filepath=stl_path, export_selected_objects=True,
                              up_axis="Z", forward_axis="Y")
    else:
        bpy.ops.export_mesh.stl(filepath=stl_path, use_selection=True)
    arm.animation_data.use_nla = True
    print("STL_SAVED", stl_path)

    if previews:
        arm.animation_data.use_nla = False
        views = {
            "front": ((0.0, -3.4, 1.25), 40, (0, 0, 1.15)),
            "side": ((3.4, 0.0, 1.20), 40, (0, 0, 1.10)),
            "back": ((0.0, 3.4, 1.25), 40, (0, 0, 1.15)),
            "right_cheek": ((-1.65, 1.15, 1.12), 48, (-0.18, 0.36, 1.04)),
            "iso": ((2.6, -3.0, 2.1), 42, (0, 0, 1.15)),
        }
        cam.data.lens = 40
        for name, (loc, lens, target) in views.items():
            cam.location = loc
            cam.data.lens = lens
            cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = os.path.join(previews, f"lea_{name}.png")
            bpy.ops.render.render(write_still=True)
            print("PREVIEW", scene.render.filepath)
        arm.animation_data.use_nla = True

    return {
        "verts": verts, "faces": faces, "non_manifold": non_manifold,
        "dims": dims, "bones": len(spec), "clips": list(ACTION_NAMES),
        "meshes": len(parts), "glb": glb_path, "stl": stl_path,
    }


if __name__ == "__main__":
    result = build_lea()
    print("LEA_BUILD_OK", json.dumps(result, sort_keys=True))
