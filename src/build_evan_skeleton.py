#!/usr/bin/env python3
"""EVAN THE SKELETON — stylized punk-rock running skeleton guitarist.

Blender source of truth. Never hand-edit Evan_Skeleton.blend or its GLB; edit
this script and rebuild:

    blender -b -noaudio --threads 4 -P src/build_evan_skeleton.py
    blender -b -noaudio --threads 4 -P src/build_evan_skeleton.py -- --previews /tmp/evan

Pipeline (surgical-building, creative-brief branch — no vanishing-point
metrology: the reference is a 2D stylized illustration, not a street-view
photo). A concrete authored dimension spec is emitted to
``evan_spatial_manifest.json`` next to the script output.

Deliverables
------------
* ``Evan_Skeleton.blend``                    editable source
* ``godot/assets/Evan_Skeleton.glb``         plain GLB (Godot 4.3 here has no
                                             Draco importer), 52-bone humanoid
                                             rig, 4 baked NLA actions
* ``Evan_Skeleton.stl``                      QA mesh (watertight, minZ = 0)
* ``evan_spatial_manifest.json``             authored dim spec for QA
* optional ``--previews DIR``                6-angle/pose material renders

Rig: canonical 52-bone Godot SkeletonProfileHumanoid bone *names* and
hierarchy, posed in an upright athletic guitarist stance. All visual parts are
rigidly bound (weight 1.0) to their controlling bone, so the baked running and
scissor-kick animations deform cleanly in Godot 4.3.

Coordinate contract: Blender +Z up / -Y forward -> glTF +Y up / -Z forward.
Ground datum AABB bottom = 0.000 m (skeleton feet touch the floor).
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
from mathutils import Euler, Matrix, Vector

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------- authored spec
SPEC = {
    "width_x": 0.90,
    "depth_y": 0.72,
    "height_z": 1.82,
}

BONE_COUNT = 52
ACTION_NAMES = (
    "Idle_Sway",
    "Play_Strum",
    "Headbang_Riff",
    "Action_BigFinish",
    "Run_NoGuitar",
    "Action_GuitarThrow",
    "Action_GuitarCatch",
)


def ensure_node_tree(datablock: Any) -> Any:
    """Blender 4.x/5.x safe node-tree access (5.x node trees exist by default)."""
    if bpy.app.version < (5, 0, 0) and hasattr(datablock, "use_nodes"):
        datablock.use_nodes = True
    return datablock.node_tree


def make_mat(name: str, color: tuple[float, float, float], rough: float = 0.6,
             metallic: float = 0.0, emission: float = 0.0) -> Any:
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
    tree.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m


def build_evan(argv: list[str] | None = None) -> dict[str, Any]:
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

    col = bpy.data.collections.new("EvanSkeleton")
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

    # -------------------------------------------------------------- materials
    bone_ivory = make_mat("BoneIvory", (0.95, 0.92, 0.83), 0.64, emission=0.02)
    bone_shadow = make_mat("BoneShadow", (0.62, 0.58, 0.50), 0.78)
    socket_dark = make_mat("EyeSocket", (0.012, 0.014, 0.018), 0.85)
    magenta = make_mat("MohawkMagenta", (0.94, 0.04, 0.34), 0.42, emission=0.18)
    mohawk_tip = make_mat("MohawkTipDark", (0.14, 0.02, 0.07), 0.58, emission=0.02)
    guitar_pink = make_mat("GuitarHotPink", (0.98, 0.05, 0.43), 0.18, metallic=0.05, emission=0.06)
    guitar_cream = make_mat("GuitarCream", (0.96, 0.94, 0.88), 0.36)
    fretboard = make_mat("Fretboard", (0.14, 0.08, 0.05), 0.58)
    chrome = make_mat("Chrome", (0.82, 0.85, 0.90), 0.20, 0.92)
    strap_brown = make_mat("StrapLeather", (0.40, 0.21, 0.10), 0.76)

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
               material: Any, seg: int = 14, rings: int = 10,
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
            vertices: int = 12, radius2: float | None = None) -> Any:
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

    def anatomical_bone(name: str, head: Vector, tail: Vector, mid_r: float,
                        end_r: float, material: Any, seg: int = 8,
                        condyle_split: bool = True) -> Any:
        """Watertight lofted long bone: flared epiphyses, tapered shaft, double condyle."""
        vec = tail - head
        length = vec.length
        if length < 1e-5:
            return sphere(name, tuple(head), (mid_r, mid_r, mid_r), material, seg, 6)
        axis = vec.normalized()
        u, v = _orthonormal_frame(axis)
        # 7 stations along the bone axis (t in [0..1])
        profile = [
            (0.02, end_r * 0.72, 1.05),
            (0.08, end_r * 1.15, 1.18),
            (0.22, mid_r * 1.02, 0.95),
            (0.50, mid_r * 0.88, 0.92),
            (0.78, mid_r * 1.04, 0.96),
            (0.92, end_r * 1.22, 1.25 if condyle_split else 1.05),
            (0.98, end_r * 0.76, 1.10),
        ]
        bm = bmesh.new()
        rings = []
        for t, r_base, u_squash in profile:
            center = head + axis * (t * length)
            ring = []
            for j in range(seg):
                ang = 2.0 * math.pi * j / seg
                # Slight double-condyle pinch on the distal/proximal ends
                pinch = 1.0
                if condyle_split and t >= 0.88:
                    pinch = 1.0 - 0.14 * abs(math.sin(ang))
                elif condyle_split and t <= 0.12:
                    pinch = 1.0 - 0.10 * abs(math.sin(ang))
                offset = (u * (math.cos(ang) * r_base * u_squash * pinch)
                          + v * (math.sin(ang) * r_base * pinch))
                ring.append(bm.verts.new(center + offset))
            rings.append(ring)
        for i in range(len(rings) - 1):
            for j in range(seg):
                jn = (j + 1) % seg
                bm.faces.new((rings[i][j], rings[i][jn], rings[i + 1][jn], rings[i + 1][j]))
        c0 = bm.verts.new(head)
        c1 = bm.verts.new(tail)
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

    def tube(name: str, points: list[Vector], radius_x: float, material: Any,
             seg: int = 6, radius_y: float | None = None,
             taper_tail: float = 1.0) -> Any:
        """Watertight lofted tube (supports oval ribbon cross-sections & tail taper)."""
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

    def ribbon(name: str, points: list[Vector], half_w: float, half_t: float,
               material: Any) -> Any:
        """Watertight flat strap ribbon along an ordered point list."""
        pts = [Vector(p) for p in points]
        n = len(pts)
        bm = bmesh.new()
        rings = []
        for i, c in enumerate(pts):
            tan = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
            out_dir = Vector((c.x, c.y, 0.0))
            if out_dir.length < 1e-4:
                out_dir = Vector((0.0, -1.0, 0.0))
            out_dir.normalize()
            side = tan.cross(out_dir).normalized()
            nrm = side.cross(tan).normalized()
            ring = [
                bm.verts.new(c - side * half_w - nrm * half_t),
                bm.verts.new(c + side * half_w - nrm * half_t),
                bm.verts.new(c + side * half_w + nrm * half_t),
                bm.verts.new(c - side * half_w + nrm * half_t),
            ]
            rings.append(ring)
        for i in range(n - 1):
            for j in range(4):
                jn = (j + 1) % 4
                bm.faces.new((rings[i][j], rings[i][jn], rings[i + 1][jn], rings[i + 1][j]))
        bm.faces.new((rings[0][3], rings[0][2], rings[0][1], rings[0][0]))
        bm.faces.new((rings[-1][0], rings[-1][1], rings[-1][2], rings[-1][3]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh = bpy.data.meshes.new(name + "_Mesh")
        bm.to_mesh(mesh)
        bm.free()
        ob = bpy.data.objects.new(name, mesh)
        link_only(ob)
        ob.data.materials.append(material)
        return ob

    # -------------------------------------------------------------- posed rig spec
    def posed_bone_spec() -> list[dict[str, Any]]:
        """Canonical 52 names/hierarchy, rest pose = athletic standing guitarist."""
        bones: list[dict[str, Any]] = [
            {"name": "Hips", "head": (0.0, 0.0, 0.94), "tail": (0.0, 0.0, 1.07), "parent": None},
            {"name": "Spine", "head": (0.0, 0.0, 1.07), "tail": (0.0, -0.01, 1.22), "parent": "Hips"},
            {"name": "Chest", "head": (0.0, -0.01, 1.22), "tail": (0.0, -0.02, 1.38), "parent": "Spine"},
            {"name": "UpperChest", "head": (0.0, -0.02, 1.38), "tail": (0.0, -0.02, 1.49), "parent": "Chest"},
            {"name": "Neck", "head": (0.0, -0.02, 1.49), "tail": (0.0, -0.03, 1.57), "parent": "UpperChest"},
            {"name": "Head", "head": (0.0, -0.03, 1.57), "tail": (0.0, -0.04, 1.77), "parent": "Neck"},
        ]
        finger_offsets = (
            ("Thumb", 0.030, -0.022, 0.032),
            ("Index", 0.020, -0.005, 0.046),
            ("Middle", 0.004, 0.000, 0.050),
            ("Ring", -0.013, 0.000, 0.045),
            ("Little", -0.028, 0.005, 0.038),
        )
        for side, sx in (("L", 1.0), ("R", -1.0)):
            shoulder = Vector((sx * 0.185, 0.0, 1.43))
            if side == "R":
                elbow = Vector((-0.29, -0.08, 1.19))
                wrist = Vector((-0.10, -0.25, 1.07))
                hand_end = wrist + Vector((0.02, -0.04, -0.015))
            else:
                elbow = Vector((0.26, -0.15, 1.20))
                wrist = Vector((0.35, -0.28, 1.21))
                hand_end = wrist + Vector((0.03, -0.035, 0.01))
            bones.extend([
                {"name": f"Shoulder.{side}", "head": (0.0, -0.02, 1.43), "tail": tuple(shoulder), "parent": "UpperChest"},
                {"name": f"UpperArm.{side}", "head": tuple(shoulder), "tail": tuple(elbow), "parent": f"Shoulder.{side}"},
                {"name": f"ForeArm.{side}", "head": tuple(elbow), "tail": tuple(wrist), "parent": f"UpperArm.{side}"},
                {"name": f"Hand.{side}", "head": tuple(wrist), "tail": tuple(hand_end), "parent": f"ForeArm.{side}"},
            ])
            for fname, dy, dx_bias, seg_len in finger_offsets:
                base = hand_end + Vector((sx * dx_bias, dy * 0.55, 0.0))
                step = seg_len * 0.33
                for s in (1, 2, 3):
                    parent = f"Hand.{side}" if s == 1 else f"{fname}{s - 1}.{side}"
                    curl_y = -0.008 * s if side == "L" else -0.004 * s
                    bones.append({
                        "name": f"{fname}{s}.{side}",
                        "head": (base.x, base.y + curl_y * 0.5, base.z - (s - 1) * step),
                        "tail": (base.x, base.y + curl_y, base.z - s * step),
                        "parent": parent,
                    })
            hip = Vector((sx * 0.105, 0.0, 0.92))
            knee = Vector((sx * 0.135, -0.05, 0.50))
            ankle = Vector((sx * 0.145, 0.02, 0.095))
            toe = Vector((sx * 0.155, -0.10, 0.032))
            bones.extend([
                {"name": f"Thigh.{side}", "head": tuple(hip), "tail": tuple(knee), "parent": "Hips"},
                {"name": f"Calf.{side}", "head": tuple(knee), "tail": tuple(ankle), "parent": f"Thigh.{side}"},
                {"name": f"Foot.{side}", "head": tuple(ankle), "tail": tuple(toe), "parent": f"Calf.{side}"},
                {"name": f"Toes.{side}", "head": tuple(toe),
                 "tail": (sx * 0.160, -0.19, 0.022), "parent": f"Foot.{side}"},
            ])
        return bones

    bone_spec = posed_bone_spec()
    assert len(bone_spec) == BONE_COUNT, f"rig spec has {len(bone_spec)} bones"
    bone_heads = {b["name"]: Vector(b["head"]) for b in bone_spec}
    bone_tails = {b["name"]: Vector(b["tail"]) for b in bone_spec}

    # Build armature with canonical humanoid names and deterministic bone rolls
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    arm = link_only(bpy.context.active_object)
    arm.name = "EvanRig"
    arm.data.name = "EvanRig_Humanoid52"
    for b in list(arm.data.edit_bones):
        arm.data.edit_bones.remove(b)
    created: dict[str, Any] = {}
    for item in bone_spec:
        eb = arm.data.edit_bones.new(item["name"])
        eb.head = Vector(item["head"])
        eb.tail = Vector(item["tail"])
        if item["parent"]:
            eb.parent = created[item["parent"]]
        # Align Z-axis forward (-Y) on torso, head, arm, and leg chains so
        # local X/Y/Z axes are deterministic across the entire rig.
        if any(item["name"].startswith(p) for p in (
            "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
            "Shoulder", "UpperArm", "ForeArm", "Hand",
            "Thigh", "Calf", "Foot", "Toes",
        )):
            eb.align_roll(Vector((0.0, -1.0, 0.0)))
        created[item["name"]] = eb
    bpy.ops.object.mode_set(mode="OBJECT")

    parts: list[tuple[Any, str]] = []

    def bind(ob: Any, bone: str) -> Any:
        parts.append((ob, bone))
        return ob

    # -------------------------------------------------------------- skull + laughing jaw + mohawk
    bind(sphere("Skull_Cranium", (0.0, -0.045, 1.648), (0.106, 0.124, 0.122),
                bone_ivory, 16, 12), "Head")
    # Smooth brow ridge + subtle sculpted zygomatic cheekbones
    bind(sphere("Skull_Brow", (0.0, -0.146, 1.662), (0.072, 0.022, 0.015),
                bone_ivory, 12, 8), "Head")
    for sx in (-1.0, 1.0):
        bind(sphere(f"Cheekbone_{'L' if sx > 0 else 'R'}",
                    (sx * 0.062, -0.132, 1.598), (0.024, 0.024, 0.018),
                    bone_ivory, 10, 7), "Head")
        bind(sphere(f"EyeSocket_{'L' if sx > 0 else 'R'}",
                    (sx * 0.041, -0.148, 1.633), (0.030, 0.022, 0.031),
                    socket_dark, 10, 7, rot=(0.0, sx * 0.14, 0.0)), "Head")
    bind(sphere("Skull_Nose", (0.0, -0.165, 1.592), (0.020, 0.020, 0.028),
                socket_dark, 8, 6), "Head")
    # Upper maxilla + 7 individual ivory upper teeth
    bind(sphere("UpperMaxilla", (0.0, -0.140, 1.564), (0.068, 0.048, 0.022),
                bone_ivory, 12, 8), "Head")
    for ti in range(-3, 4):
        ang = ti * 0.20
        tx = math.sin(ang) * 0.056
        ty = -0.132 - math.cos(ang) * 0.046
        bind(box(f"ToothUpper_{ti + 3}", (tx, ty, 1.546), (0.011, 0.010, 0.016),
                 bone_ivory, rot=(0.0, 0.0, -ang)), "Head")

    # Wide-open laughing / screaming mandible (hinged down ~22 deg) + dark mouth cavity
    bind(sphere("MouthVoid", (0.0, -0.128, 1.534), (0.052, 0.044, 0.036),
                socket_dark, 10, 7), "Head")
    jaw_pts = [
        Vector((-0.072, -0.088, 1.558)),
        Vector((-0.062, -0.138, 1.505)),
        Vector((0.0, -0.172, 1.488)),
        Vector((0.062, -0.138, 1.505)),
        Vector((0.072, -0.088, 1.558)),
    ]
    bind(tube("Skull_Jaw", jaw_pts, 0.018, bone_ivory, 7, radius_y=0.014), "Head")
    for ti in range(-2, 3):
        ang = ti * 0.24
        tx = math.sin(ang) * 0.048
        ty = -0.125 - math.cos(ang) * 0.044
        bind(box(f"ToothLower_{ti + 2}", (tx, ty, 1.505), (0.010, 0.009, 0.014),
                 bone_ivory, rot=(0.0, 0.0, -ang)), "Head")

    # Two-tone spiky punk mohawk: 11 tall central spikes + 14 feathered side spikes
    for i in range(11):
        u = (i / 10.0 - 0.5) * 1.95
        base = Vector((0.0, -0.045 + math.sin(u) * 0.11, 1.655 + math.cos(u) * 0.115))
        radial = (base - Vector((0.0, -0.045, 1.648))).normalized()
        h = 0.135 + 0.065 * math.cos(u * 0.85)
        mid = base + radial * (h * 0.62)
        tip = base + radial * h + Vector((0.0, 0.018 * u, 0.0))
        bind(cyl(f"MohawkB_{i:02d}", tuple((base + mid) * 0.5), 0.017, (mid - base).length,
                 magenta, rot=tuple((mid - base).normalized().to_track_quat("Z", "Y").to_euler()),
                 vertices=5, radius2=0.008), "Head")
        bind(cyl(f"MohawkT_{i:02d}", tuple((mid + tip) * 0.5), 0.0085, (tip - mid).length,
                 mohawk_tip, rot=tuple((tip - mid).normalized().to_track_quat("Z", "Y").to_euler()),
                 vertices=5, radius2=0.001), "Head")
    for sx in (-1.0, 1.0):
        for i in range(7):
            u = (i / 6.0 - 0.5) * 1.55
            base = Vector((sx * 0.026, -0.045 + math.sin(u) * 0.10, 1.652 + math.cos(u) * 0.108))
            radial = (base - Vector((0.0, -0.045, 1.648))).normalized()
            radial = (radial + Vector((sx * 0.35, 0.0, 0.0))).normalized()
            h = 0.085 + 0.035 * math.cos(u)
            tip = base + radial * h
            bind(cyl(f"MohawkSide_{'L' if sx > 0 else 'R'}_{i}", tuple((base + tip) * 0.5),
                     0.012, h, magenta if i % 2 == 0 else mohawk_tip,
                     rot=tuple(radial.to_track_quat("Z", "Y").to_euler()),
                     vertices=5, radius2=0.001), "Head")

    # -------------------------------------------------------------- spine, scapulae, ribs & pelvis
    for i in range(12):
        z = 1.06 + i * 0.040
        y = -0.004 - i * 0.0022
        bname = "Neck" if i >= 10 else ("UpperChest" if i >= 8 else ("Chest" if i >= 4 else "Spine"))
        bind(cyl(f"Vertebra_{i:02d}", (0.0, y, z), 0.022, 0.020, bone_ivory, vertices=8), bname)
        bind(cyl(f"VertDisc_{i:02d}", (0.0, y, z + 0.018), 0.017, 0.010, bone_shadow, vertices=8), bname)
        # Prominent rear spinous process (reads crisply from third-person chase cam)
        bind(box(f"Spinous_{i:02d}", (0.0, y + 0.028, z - 0.004), (0.012, 0.032, 0.016),
                 bone_ivory, rot=(0.25, 0.0, 0.0)), bname)

    for i in range(8):
        z = 1.155 + i * 0.035
        t_rib = i / 7.0
        width = 0.145 + 0.055 * math.sin(t_rib * math.pi)
        depth = 0.082 + 0.028 * math.sin(t_rib * math.pi)
        floating = i < 2
        for sx in (-1.0, 1.0):
            pts = [
                Vector((sx * 0.018, -0.008, z)),
                Vector((sx * width * 0.65, -0.016, z - 0.006)),
                Vector((sx * width, -0.030 - depth * 0.45, z - 0.016)),
            ]
            if not floating:
                pts.extend([
                    Vector((sx * width * 0.72, -0.058 - depth, z - 0.026)),
                    Vector((sx * 0.022, -0.085 - depth * 0.72, z - 0.030)),
                ])
            else:
                pts.append(Vector((sx * width * 0.80, -0.048 - depth * 0.70, z - 0.024)))
            bind(tube(f"Rib_{i:02d}_{'L' if sx > 0 else 'R'}", pts, 0.0065,
                      bone_ivory, 5, radius_y=0.011), "Chest")

    # 3-piece sternum + clavicles + rear scapulae
    bind(box("Manubrium", (0.0, -0.105, 1.375), (0.052, 0.018, 0.048), bone_ivory), "Chest")
    bind(box("SternumBody", (0.0, -0.112, 1.280), (0.034, 0.016, 0.125), bone_ivory), "Chest")
    bind(box("Xiphoid", (0.0, -0.106, 1.198), (0.020, 0.012, 0.032), bone_shadow), "Chest")
    for sx in (-1.0, 1.0):
        bind(tube(f"Clavicle_{'L' if sx > 0 else 'R'}",
                  [Vector((sx * 0.020, -0.095, 1.402)), Vector((sx * 0.095, -0.065, 1.430)),
                   Vector((sx * 0.180, -0.010, 1.432))], 0.011, bone_ivory, 6), "UpperChest")
        bind(box(f"Scapula_{'L' if sx > 0 else 'R'}",
                 (sx * 0.095, 0.052, 1.355), (0.088, 0.014, 0.125),
                 bone_ivory, rot=(0.08, sx * 0.16, sx * -0.12)), "UpperChest")
        # Sculpted pelvis iliac wing + ischial arch
        bind(sphere(f"Ilium_{'L' if sx > 0 else 'R'}",
                    (sx * 0.092, -0.012, 0.962), (0.068, 0.082, 0.068),
                    bone_ivory, 10, 7, rot=(0.2, sx * 0.35, sx * 0.22)), "Hips")
        bind(tube(f"Ischium_{'L' if sx > 0 else 'R'}",
                  [Vector((sx * 0.095, -0.02, 0.92)),
                   Vector((sx * 0.065, -0.035, 0.875)),
                   Vector((sx * 0.018, -0.040, 0.905))], 0.014, bone_shadow, 6), "Hips")
    bind(sphere("Sacrum", (0.0, 0.022, 0.942), (0.052, 0.036, 0.068),
                bone_shadow, 10, 7), "Hips")

    # -------------------------------------------------------------- anatomical limbs
    for side, sx in (("L", 1.0), ("R", -1.0)):
        # Arms: Humerus, paired Radius + Ulna, Carpal/Metacarpal hand, 15 phalanges
        u_h = bone_heads[f"UpperArm.{side}"]
        u_t = bone_tails[f"UpperArm.{side}"]
        bind(anatomical_bone(f"UpperArm.{side}", u_h, u_t, 0.022, 0.032, bone_ivory, 8),
             f"UpperArm.{side}")

        f_h = bone_heads[f"ForeArm.{side}"]
        f_t = bone_tails[f"ForeArm.{side}"]
        f_dir = (f_t - f_h).normalized()
        fu, fv = _orthonormal_frame(f_dir)
        bind(anatomical_bone(f"Radius.{side}", f_h + fu * 0.013, f_t + fu * 0.013,
                             0.013, 0.019, bone_ivory, 6, False), f"ForeArm.{side}")
        bind(anatomical_bone(f"Ulna.{side}", f_h - fu * 0.013, f_t - fu * 0.013,
                             0.012, 0.018, bone_shadow, 6, False), f"ForeArm.{side}")

        h_h = bone_heads[f"Hand.{side}"]
        h_t = bone_tails[f"Hand.{side}"]
        bind(anatomical_bone(f"Hand.{side}", h_h, h_t, 0.022, 0.026, bone_ivory, 6, False),
             f"Hand.{side}")
        for fname in ("Thumb", "Index", "Middle", "Ring", "Little"):
            for s in (1, 2, 3):
                name = f"{fname}{s}.{side}"
                h, t = bone_heads[name], bone_tails[name]
                # Hairline 10% gap prevents STL coincident cap-ring welding.
                seg = cyl(name, tuple((h + t) * 0.5), 0.0068, (t - h).length * 0.90,
                          bone_ivory, vertices=6,
                          rot=tuple((t - h).normalized().to_track_quat("Z", "Y").to_euler()))
                bind(seg, name)

        # Legs: Femur + Patella, paired Tibia + Fibula, Heel Calcaneus + Foot + 5 Toes
        th_h = bone_heads[f"Thigh.{side}"]
        th_t = bone_tails[f"Thigh.{side}"]
        bind(anatomical_bone(f"Thigh.{side}", th_h, th_t, 0.030, 0.044, bone_ivory, 8),
             f"Thigh.{side}")
        bind(sphere(f"Patella.{side}", (th_t.x, th_t.y - 0.042, th_t.z + 0.01),
                    (0.028, 0.018, 0.030), bone_ivory, 8, 6), f"Thigh.{side}")

        ca_h = bone_heads[f"Calf.{side}"]
        ca_t = bone_tails[f"Calf.{side}"]
        bind(anatomical_bone(f"Tibia.{side}", ca_h, ca_t, 0.024, 0.036, bone_ivory, 8),
             f"Calf.{side}")
        bind(anatomical_bone(f"Fibula.{side}", ca_h + Vector((sx * 0.024, 0.010, -0.02)),
                             ca_t + Vector((sx * 0.020, 0.008, 0.01)),
                             0.010, 0.014, bone_shadow, 6, False), f"Calf.{side}")

        ft_h = bone_heads[f"Foot.{side}"]
        ft_t = bone_tails[f"Foot.{side}"]
        bind(sphere(f"Calcaneus.{side}", (ft_h.x, ft_h.y + 0.024, ft_h.z - 0.045),
                    (0.024, 0.034, 0.026), bone_ivory, 8, 6), f"Foot.{side}")
        bind(anatomical_bone(f"Foot.{side}", ft_h, ft_t, 0.022, 0.028, bone_ivory, 6, False),
             f"Foot.{side}")
        to_h = bone_heads[f"Toes.{side}"]
        to_t = bone_tails[f"Toes.{side}"]
        for ti in range(5):
            off_x = (ti - 2) * 0.014 * sx
            toe_len_scale = 1.0 - ti * 0.07
            t_end = to_h + (to_t - to_h) * toe_len_scale + Vector((off_x, 0.0, 0.0))
            bind(cyl(f"ToeRay_{side}_{ti}", tuple((to_h + Vector((off_x, 0.0, 0.0)) + t_end) * 0.5),
                     0.0075, (t_end - to_h).length * 0.88, bone_ivory, vertices=6,
                     rot=tuple((t_end - to_h).normalized().to_track_quat("Z", "Y").to_euler())),
                 f"Toes.{side}")

    # -------------------------------------------------------------- reference hot-pink guitar
    guitar_xf = (Matrix.Translation(Vector((0.02, -0.22, 1.08)))
                 @ Matrix.Rotation(math.radians(-22.0), 4, "Y")
                 @ Matrix.Rotation(math.radians(90.0), 4, "X"))
    guitar_parts: list[Any] = []

    def g(ob: Any) -> Any:
        ob.data.transform(guitar_xf)
        guitar_parts.append(ob)
        return ob

    # Smooth 21-vertex beveled double-cutaway contour (horns point +X toward neck!)
    outline_raw = [
        (-0.165, -0.175), (-0.095, -0.225), (0.000, -0.235), (0.085, -0.205),
        (0.145, -0.145), (0.175, -0.070), (0.145, -0.010), (0.090, 0.035),
        (0.135, 0.085), (0.155, 0.140), (0.115, 0.160), (0.055, 0.115),
        (0.028, 0.085), (-0.028, 0.085), (-0.055, 0.155), (-0.110, 0.215),
        (-0.165, 0.195), (-0.185, 0.125), (-0.145, 0.045), (-0.165, -0.030),
        (-0.190, -0.105),
    ]
    # Rotate +90° clockwise in 2D: (x, y) -> (y, -x) so horns (+y) point along +X (neck)
    outline = [(y, -x) for x, y in outline_raw]
    n_out = len(outline)
    bm = bmesh.new()
    bot_outer = [bm.verts.new((x, y, -0.022)) for x, y in outline]
    top_outer = [bm.verts.new((x, y, 0.022)) for x, y in outline]
    bot_bevel = [bm.verts.new((x * 0.94, y * 0.94, -0.028)) for x, y in outline]
    top_bevel = [bm.verts.new((x * 0.94, y * 0.94, 0.028)) for x, y in outline]
    for j in range(n_out):
        jn = (j + 1) % n_out
        bm.faces.new((bot_outer[j], bot_outer[jn], top_outer[jn], top_outer[j]))
        bm.faces.new((top_outer[j], top_outer[jn], top_bevel[jn], top_bevel[j]))
        bm.faces.new((bot_bevel[j], bot_bevel[jn], bot_outer[jn], bot_outer[j]))
    cbot = bm.verts.new((-0.02, 0.0, -0.028))
    ctop = bm.verts.new((-0.02, 0.0, 0.028))
    for j in range(n_out):
        jn = (j + 1) % n_out
        bm.faces.new((cbot, bot_bevel[jn], bot_bevel[j]))
        bm.faces.new((ctop, top_bevel[j], top_bevel[jn]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    gmesh = bpy.data.meshes.new("GuitarBody_Mesh")
    bm.to_mesh(gmesh)
    bm.free()
    body = bpy.data.objects.new("GuitarBody", gmesh)
    link_only(body)
    body.data.materials.append(guitar_pink)
    g(body)

    # Rosewood neck + angled 6-in-line hot-pink headstock
    g(box("GuitarNeck", (0.285, 0.0, 0.008), (0.46, 0.056, 0.030), fretboard))
    g(box("GuitarHeadstock", (0.575, 0.008, 0.008), (0.125, 0.072, 0.024), guitar_pink,
          rot=(0.0, 0.0, math.radians(-8.0))))
    # Single cream pickup + 6 pole pieces + chrome bridge + 2 knobs
    g(box("Pickup_0", (0.015, 0.0, 0.031), (0.040, 0.105, 0.012), guitar_cream))
    for pi in range(6):
        g(cyl(f"Pole_{pi}", (0.015, -0.035 + pi * 0.014, 0.038), 0.0032, 0.004, chrome, vertices=6))
    g(box("Bridge", (-0.095, 0.0, 0.032), (0.026, 0.095, 0.012), chrome))
    for ki, (kx, ky) in enumerate(((-0.065, -0.105), (-0.115, -0.125))):
        g(cyl(f"Knob_{ki}", (kx, ky, 0.034), 0.013, 0.014, chrome, vertices=10))
    # 12 frets + 4 pearl inlays
    for fi in range(12):
        g(box(f"Fret_{fi}", (0.075 + fi * 0.036, 0.0, 0.024), (0.003, 0.052, 0.002), chrome))
    for ii in range(4):
        g(cyl(f"Inlay_{ii}", (0.128 + ii * 0.096, 0.0, 0.0245), 0.005, 0.002, guitar_cream, vertices=8))
    # 6 tuning pegs along top edge of headstock + 6 precision strings (bridge -> nut)
    for si in range(6):
        sy = -0.025 + si * 0.010
        g(cyl(f"Tuner_{si}", (0.528 + si * 0.018, 0.050, 0.010), 0.0065, 0.022, chrome,
              vertices=6, rot=(math.pi / 2.0, 0.0, 0.0)))
        s_start = Vector((-0.095, sy, 0.040))
        s_end = Vector((0.510, -0.020 + si * 0.008, 0.027))
        s_mid = (s_start + s_end) * 0.5
        s_dir = (s_end - s_start).normalized()
        g(cyl(f"String_{si}", tuple(s_mid), 0.0014, (s_end - s_start).length, chrome,
              vertices=5, rot=tuple(s_dir.to_track_quat("Z", "Y").to_euler())))

    # Authoritative muzzle anchors for SideCannons' "evan" profile
    for tag, x in (("L", -0.085), ("R", 0.085)):
        g(cyl(f"RiffMuzzle_{tag}", (x, -0.035, 0.058), 0.018, 0.075, chrome,
              vertices=10, rot=(math.pi / 2.0, 0.0, 0.0)))

    # Leather strap over left shoulder + 1/4" jack & trailing cable
    g(ribbon("GuitarStrap", [
        Vector((0.08, 0.14, 0.00)),
        Vector((0.04, 0.30, -0.08)),
        Vector((0.12, 0.42, -0.20)),
        Vector((0.20, 0.34, -0.24)),
        Vector((0.16, 0.12, -0.10)),
        Vector((0.02, 0.02, -0.02)),
    ], 0.020, 0.004, strap_brown))
    g(cyl("GuitarJack", (-0.195, -0.115, 0.0), 0.008, 0.032, chrome,
          vertices=8, rot=(0.0, math.radians(-50.0), math.radians(40.0))))
    for ob in guitar_parts:
        bind(ob, "UpperChest")

    # Sinuous trailing cable bound to Hips
    cable_ob = bind(tube("GuitarCable", [
        Vector((-0.17, -0.20, 0.90)),
        Vector((-0.24, -0.16, 0.72)),
        Vector((-0.21, -0.06, 0.52)),
        Vector((-0.26, 0.04, 0.34)),
        Vector((-0.20, 0.12, 0.16)),
        Vector((-0.22, 0.16, 0.04)),
    ], 0.0055, strap_brown, 6), "Hips")
    guitar_set = set(guitar_parts) | {cable_ob}

    # -------------------------------------------------------------- rigid skin binding
    for ob, bone_name in parts:
        vg = ob.vertex_groups.new(name=bone_name)
        vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
        ob.parent = arm
        mod = ob.modifiers.new(name="EvanSkin", type="ARMATURE")
        mod.object = arm
        mod.use_vertex_groups = True
        mod.use_bone_envelopes = False

    # -------------------------------------------------------------- batch by bone + material + guitar
    LANDMARKS = {
        "RiffMuzzle_L", "RiffMuzzle_R", "GuitarBody",
        "Skull_Cranium", "Skull_Jaw", "GuitarStrap", "GuitarCable",
    }
    batches: dict[tuple[str, str, bool], list[Any]] = defaultdict(list)
    for ob, bone_name in parts:
        if ob.name in LANDMARKS:
            continue
        mat_name = ob.data.materials[0].name if ob.data.materials else ""
        batches[(bone_name, mat_name, ob in guitar_set)].append(ob)
    merged: list[tuple[Any, str]] = []
    for ob, bone_name in parts:
        if ob.name in LANDMARKS:
            merged.append((ob, bone_name))
    for (bone_name, mat_name, is_guitar), obs in batches.items():
        target_name = f"GuitarPart_{mat_name}" if is_guitar else f"Evan_{bone_name}_{mat_name}"
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

    # -------------------------------------------------------------- 7 baked NLA actions
    pose = arm.pose.bones
    for pb in pose:
        pb.rotation_mode = "XYZ"

    # Biomechanical axis verification assertions (local +Y = World +Z UP on Hips)
    pose["Hips"].location = (0.0, 0.10, 0.0)
    bpy.context.view_layer.update()
    assert pose["Hips"].head.z > bone_heads["Hips"].z + 0.05, \
        f"Hips local +Y did not move world +Z: {pose['Hips'].head.z} vs {bone_heads['Hips'].z}"
    pose["Hips"].location = (0.0, 0.0, 0.0)

    pose["Thigh.L"].rotation_euler = (0.5, 0.0, 0.0)
    bpy.context.view_layer.update()
    assert pose["Thigh.L"].tail.y < bone_tails["Thigh.L"].y - 0.10, \
        f"Thigh.L +X did not swing knee forward (-Y): {pose['Thigh.L'].tail.y} vs {bone_tails['Thigh.L'].y}"
    pose["Thigh.L"].rotation_euler = (0.0, 0.0, 0.0)

    pose["Calf.L"].rotation_euler = (-0.8, 0.0, 0.0)
    bpy.context.view_layer.update()
    assert pose["Calf.L"].tail.y > bone_tails["Calf.L"].y + 0.10, \
        f"Calf.L -X did not flex knee backward (+Y): {pose['Calf.L'].tail.y} vs {bone_tails['Calf.L'].y}"
    pose["Calf.L"].rotation_euler = (0.0, 0.0, 0.0)

    pose["Foot.L"].rotation_euler = (0.4, 0.0, 0.0)
    bpy.context.view_layer.update()
    assert pose["Foot.L"].tail.z > bone_tails["Foot.L"].z + 0.02, \
        f"Foot.L +X did not dorsiflex toes UP (+Z): {pose['Foot.L'].tail.z} vs {bone_tails['Foot.L'].z}"
    pose["Foot.L"].rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()

    ANIMATED_BONES = (
        "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
        "Shoulder.L", "UpperArm.L", "ForeArm.L", "Hand.L", "Index1.L", "Middle1.L",
        "Shoulder.R", "UpperArm.R", "ForeArm.R", "Hand.R",
        "Thigh.L", "Calf.L", "Foot.L", "Toes.L",
        "Thigh.R", "Calf.R", "Foot.R", "Toes.R",
    )

    def _periodic_curve(u: float, knots: tuple[float, ...]) -> float:
        """C1-smooth periodic Catmull-Rom spline over u in [0, 1)."""
        n = len(knots)
        scaled = (u % 1.0) * n
        i1 = int(math.floor(scaled)) % n
        t = scaled - math.floor(scaled)
        p0 = knots[(i1 - 1) % n]
        p1 = knots[i1]
        p2 = knots[(i1 + 1) % n]
        p3 = knots[(i1 + 2) % n]
        t2 = t * t
        t3 = t2 * t
        return 0.5 * (
            (2.0 * p1)
            + (-p0 + p2) * t
            + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
            + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
        )

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
            for bname in ANIMATED_BONES:
                pose[bname].keyframe_insert(data_path="rotation_euler", frame=f)
            pose["Hips"].keyframe_insert(data_path="location", frame=f)
        track = arm.animation_data.nla_tracks.new()
        track.name = action_name
        track.strips.new(action_name, 1, act)
        arm.animation_data.action = None

    def idle(pb: Any, u: float) -> None:
        t = u * 2.0 * math.pi
        w = math.sin(t)
        bounce = 0.5 - 0.5 * math.cos(2.0 * t)
        # Hips local +Y = world +Z UP
        pb["Hips"].location = (0.012 * w, -0.024 * bounce, 0.0)
        pb["Hips"].rotation_euler = (0.03 * bounce, 0.04 * w, 0.03 * w)
        pb["Thigh.L"].rotation_euler = (0.14 * bounce, 0.0, 0.0)
        pb["Calf.L"].rotation_euler = (-0.28 * bounce, 0.0, 0.0)
        pb["Foot.L"].rotation_euler = (0.14 * bounce, 0.0, 0.0)
        pb["Thigh.R"].rotation_euler = (0.14 * bounce, 0.0, 0.0)
        pb["Calf.R"].rotation_euler = (-0.28 * bounce, 0.0, 0.0)
        pb["Foot.R"].rotation_euler = (0.14 * bounce, 0.0, 0.0)
        pb["Chest"].rotation_euler = (0.04 * w, -0.03 * w, 0.0)
        pb["Head"].rotation_euler = (-0.08 * bounce, math.sin(t * 0.5) * 0.05, 0.03 * w)
        pb["ForeArm.R"].rotation_euler = (0.10 * math.sin(t * 2.0), 0.0, 0.0)
        pb["Index1.L"].rotation_euler = (0.0, 0.0, 0.16 * w)

    # 8-knot periodic gait curves (u=0.0 heel strike -> u=0.25 toe-off -> u=0.625 high-knee swing)
    THIGH_KNOTS = (0.58, 0.06, -0.66, -0.48, 0.12, 0.88, 1.04, 0.82)
    CALF_KNOTS = (-0.24, -0.46, -0.14, -1.55, -1.82, -1.25, -0.55, -0.20)
    FOOT_KNOTS = (0.18, 0.34, -0.52, -0.30, 0.12, 0.26, 0.22, 0.14)
    TOES_KNOTS = (0.05, 0.10, 0.48, 0.05, 0.00, 0.00, 0.00, 0.02)

    def _apply_run_legs(pb: Any, u: float, stride_scale: float, tuck_scale: float,
                        bounce_amp: float, lean: float) -> None:
        t = u * 2.0 * math.pi
        # Hips local +Y = World +Z UP; lowest at mid-stance (u=0.125,0.625), highest in flight (u=0.375,0.875)
        bounce_y = -math.sin(4.0 * math.pi * u) * bounce_amp + bounce_amp * 0.15
        sway_x = math.sin(t) * 0.028
        pb["Hips"].location = (sway_x, bounce_y, 0.0)
        pelvis_yaw = -math.cos(t) * 0.16 * stride_scale
        pelvis_drop = math.sin(t) * 0.08
        pb["Hips"].rotation_euler = (lean * 0.30, pelvis_yaw, pelvis_drop)
        # Torso counter-twist against pelvis + sprinter forward lean
        pb["Spine"].rotation_euler = (lean * 0.36, -pelvis_yaw * 0.45, -pelvis_drop * 0.4)
        pb["Chest"].rotation_euler = (lean * 0.34, -pelvis_yaw * 0.55, -pelvis_drop * 0.4)
        pb["UpperChest"].rotation_euler = (0.04 * math.sin(2.0 * t), -pelvis_yaw * 0.30, 0.0)
        # Head counter-pitch keeps gaze forward while sprinting
        pb["Neck"].rotation_euler = (-lean * 0.36, 0.0, 0.0)
        pb["Head"].rotation_euler = (-lean * 0.36 + 0.06 * math.cos(2.0 * t), math.sin(t) * 0.05, -pelvis_drop * 0.3)

        for side, phase_u in (("L", u), ("R", (u + 0.5) % 1.0)):
            hip_x = _periodic_curve(phase_u, THIGH_KNOTS) * stride_scale
            knee_x = min(-0.08, _periodic_curve(phase_u, CALF_KNOTS) * tuck_scale)
            foot_x = _periodic_curve(phase_u, FOOT_KNOTS)
            toes_x = _periodic_curve(phase_u, TOES_KNOTS)
            pb[f"Thigh.{side}"].rotation_euler = (hip_x, 0.0, 0.0)
            pb[f"Calf.{side}"].rotation_euler = (knee_x, 0.0, 0.0)
            pb[f"Foot.{side}"].rotation_euler = (foot_x, 0.0, 0.0)
            pb[f"Toes.{side}"].rotation_euler = (toes_x, 0.0, 0.0)

    def strum(pb: Any, u: float) -> None:
        t = u * 2.0 * math.pi
        _apply_run_legs(pb, u, stride_scale=0.92, tuck_scale=0.95, bounce_amp=0.065, lean=0.22)
        s = math.sin(t * 2.0)
        pb["ForeArm.R"].rotation_euler = (s * 0.42, 0.0, s * 0.08)
        pb["Hand.R"].rotation_euler = (s * 0.22, 0.0, 0.0)
        pb["Index1.L"].rotation_euler = (0.0, 0.0, s * 0.25)
        pb["Middle1.L"].rotation_euler = (0.0, 0.0, -s * 0.20)
        pb["Head"].rotation_euler = (
            pb["Head"].rotation_euler[0] + math.cos(2.0 * t) * 0.06,
            pb["Head"].rotation_euler[1],
            math.sin(t) * 0.05,
        )

    def headbang(pb: Any, u: float) -> None:
        t = u * 2.0 * math.pi
        _apply_run_legs(pb, u, stride_scale=1.12, tuck_scale=1.08, bounce_amp=0.088, lean=0.34)
        s2 = math.sin(t * 2.0)
        pb["Neck"].rotation_euler = (-0.08 + 0.26 * s2, 0.0, 0.0)
        pb["Head"].rotation_euler = (-0.08 + 0.34 * s2, math.sin(t) * 0.12, 0.0)
        pb["UpperChest"].rotation_euler = (0.10 * s2, pb["UpperChest"].rotation_euler[1], 0.0)
        pb["ForeArm.R"].rotation_euler = (s2 * 0.55, 0.0, 0.0)

    def finish(pb: Any, u: float) -> None:
        # Iconic mid-air punk rock scissor-kick leap matching Evan the skeleton.jpeg!
        env = math.sin(min(u, 1.0) * math.pi)
        pb["Hips"].location = (0.0, 0.28 * env, 0.0)
        pb["Hips"].rotation_euler = (-0.08 * env, 0.0, -0.10 * env)
        pb["Chest"].rotation_euler = (-0.12 * env, 0.0, 0.0)
        pb["Head"].rotation_euler = (-0.32 * env, 0.12 * env, 0.0)
        # Front leg (L) kicks high forward; rear leg (R) extends back with tucked heel
        pb["Thigh.L"].rotation_euler = (1.05 * env, 0.0, 0.12 * env)
        pb["Calf.L"].rotation_euler = (-0.42 * env, 0.0, 0.0)
        pb["Foot.L"].rotation_euler = (-0.25 * env, 0.0, 0.0)
        pb["Thigh.R"].rotation_euler = (-0.75 * env, 0.0, -0.10 * env)
        pb["Calf.R"].rotation_euler = (-1.38 * env, 0.0, 0.0)
        pb["Foot.R"].rotation_euler = (0.35 * env, 0.0, 0.0)
        pb["ForeArm.R"].rotation_euler = (0.65 * math.sin(u * 2.0 * math.pi), 0.0, 0.0)

    def run_noguitar(pb: Any, u: float) -> None:
        """Full 100m sprinter arm-pumping in anti-phase with legs while guitar is in flight."""
        _apply_run_legs(pb, u, stride_scale=1.02, tuck_scale=1.02, bounce_amp=0.078, lean=0.28)
        t = u * 2.0 * math.pi
        # Left arm drives forward when Right thigh drives forward (-cos(t) = +1 at u=0.5)
        arm_swing = math.cos(t)
        # Un-cross rest guitar pose so elbows clear the ribcage cleanly
        pb["Shoulder.L"].rotation_euler = (0.0, 0.08 * arm_swing, 0.05)
        pb["UpperArm.L"].rotation_euler = (-0.65 * arm_swing + 0.10, 0.0, 0.22)
        pb["ForeArm.L"].rotation_euler = (0.95 - 0.35 * arm_swing, -0.25, -0.18)
        pb["Hand.L"].rotation_euler = (0.15, 0.0, 0.0)

        pb["Shoulder.R"].rotation_euler = (0.0, -0.08 * arm_swing, -0.05)
        pb["UpperArm.R"].rotation_euler = (0.65 * arm_swing + 0.10, 0.0, -0.26)
        pb["ForeArm.R"].rotation_euler = (1.15 + 0.35 * arm_swing, 0.35, 0.42)
        pb["Hand.R"].rotation_euler = (0.15, 0.0, 0.0)

    def guitar_throw(pb: Any, u: float) -> None:
        """Explosive sidearm boomerang guitar hurl while keeping athletic leg drive."""
        _apply_run_legs(pb, (u * 0.65) % 1.0, stride_scale=0.88, tuck_scale=0.88, bounce_amp=0.055, lean=0.24)
        if u < 0.24:
            # Coiled wind-up: torso twists right, right arm draws back
            k = math.sin((u / 0.24) * math.pi * 0.5)
            twist = -0.52 * k
            arm_fwd = -0.45 * k
            arm_out = -0.78 * k
            elbow_ext = 0.20 * k
            l_back = 0.35 * k
        elif u < 0.58:
            # Whip forward & release toward -Y (world forward)
            k = (u - 0.24) / 0.34
            s = math.sin(k * math.pi * 0.5)
            twist = -0.52 + 1.06 * s
            arm_fwd = -0.45 + 1.95 * s
            arm_out = -0.78 + 0.62 * s
            elbow_ext = 0.20 + 0.35 * s
            l_back = 0.35 - 0.95 * s
        else:
            # Follow-through settling into sprinter posture
            k = (u - 0.58) / 0.42
            s = 1.0 - math.sin(k * math.pi * 0.5)
            twist = 0.54 * s
            arm_fwd = 1.50 * s + 0.20 * (1.0 - s)
            arm_out = -0.16 * s - 0.24 * (1.0 - s)
            elbow_ext = 0.55 * s + 0.95 * (1.0 - s)
            l_back = -0.60 * s + 0.15 * (1.0 - s)

        pb["Chest"].rotation_euler = (pb["Chest"].rotation_euler[0] + 0.10, twist * 0.55, 0.0)
        pb["UpperChest"].rotation_euler = (0.05, twist * 0.45, 0.0)
        pb["Head"].rotation_euler = (-0.18, -twist * 0.45, 0.0)
        pb["UpperArm.R"].rotation_euler = (arm_fwd, 0.0, arm_out)
        pb["ForeArm.R"].rotation_euler = (elbow_ext, 0.45, 0.38)
        pb["Hand.R"].rotation_euler = (0.20, 0.0, 0.0)
        pb["UpperArm.L"].rotation_euler = (l_back, 0.0, 0.28)
        pb["ForeArm.L"].rotation_euler = (0.85, -0.25, -0.15)

    def guitar_catch(pb: Any, u: float) -> None:
        """Reach out and absorb the returning guitar back into playing stance."""
        _apply_run_legs(pb, (u * 0.45) % 1.0, stride_scale=0.68, tuck_scale=0.72, bounce_amp=0.04, lean=0.14)
        if u < 0.32:
            k = math.sin((u / 0.32) * math.pi * 0.5)
            reach = 0.85 * k
            recoil = 0.0
        elif u < 0.68:
            k = (u - 0.32) / 0.36
            reach = 0.85 * (1.0 - k)
            recoil = math.sin(k * math.pi)
        else:
            k = (u - 0.68) / 0.32
            reach = 0.0
            recoil = 0.0 * (1.0 - k)

        pb["Hips"].location = (pb["Hips"].location[0], pb["Hips"].location[1] - 0.045 * recoil, 0.0)
        pb["Chest"].rotation_euler = (pb["Chest"].rotation_euler[0] - 0.14 * recoil, 0.0, 0.0)
        pb["Head"].rotation_euler = (-0.12 * recoil, 0.0, 0.0)
        pb["UpperArm.R"].rotation_euler = (reach * 0.90, 0.0, -0.15 * reach)
        pb["ForeArm.R"].rotation_euler = (reach * 0.55 + 0.30 * recoil, 0.25 * reach, 0.22 * reach)
        pb["UpperArm.L"].rotation_euler = (reach * 0.65, 0.0, 0.12 * reach)
        pb["ForeArm.L"].rotation_euler = (reach * 0.45 + 0.20 * recoil, -0.15 * reach, 0.0)

    commit("Idle_Sway", 48, idle)
    commit("Play_Strum", 24, strum)
    commit("Headbang_Riff", 24, headbang)
    commit("Action_BigFinish", 36, finish)
    commit("Run_NoGuitar", 24, run_noguitar)
    commit("Action_GuitarThrow", 20, guitar_throw)
    commit("Action_GuitarCatch", 16, guitar_catch)

    # Pose-world verification assertions for Run_NoGuitar & Action_GuitarThrow
    arm.animation_data.use_nla = False
    for pb in pose:
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
    run_noguitar(pose, 0.0)
    bpy.context.view_layer.update()
    assert abs(pose["Hand.L"].tail.x) >= 0.14 and abs(pose["Hand.R"].tail.x) >= 0.14, \
        f"Run_NoGuitar arms clip torso: L.x={pose['Hand.L'].tail.x:.3f}, R.x={pose['Hand.R'].tail.x:.3f}"
    assert pose["Hand.R"].tail.y < pose["Hand.L"].tail.y, \
        f"Run_NoGuitar u=0 should swing R arm forward (-Y) vs L: R.y={pose['Hand.R'].tail.y:.3f}, L.y={pose['Hand.L'].tail.y:.3f}"

    for pb in pose:
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
    guitar_throw(pose, 0.52)
    bpy.context.view_layer.update()
    assert pose["Hand.R"].tail.y < -0.32, \
        f"Action_GuitarThrow release frame did not extend Hand.R forward (-Y): y={pose['Hand.R'].tail.y:.3f}"

    for pb in pose:
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
    arm.animation_data.use_nla = True
    scene.frame_set(1)

    # -------------------------------------------------------------- proof studio
    world = bpy.data.worlds.new("EvanWorld")
    scene.world = world
    wt = ensure_node_tree(world)
    wt.nodes.clear()
    bg = wt.nodes.new("ShaderNodeBackground")
    bg.inputs["Color"].default_value = (0.035, 0.042, 0.068, 1.0)
    out = wt.nodes.new("ShaderNodeOutputWorld")
    wt.links.new(bg.outputs["Background"], out.inputs["Surface"])

    for name, typ, loc, lc, energy in (
        ("KeyWarm", "AREA", (-2.6, -2.4, 2.7), (1.0, 0.92, 0.82), 460),
        ("RimPink", "SPOT", (3.2, 1.8, 1.9), (1.0, 0.25, 0.55), 1100),
        ("RimCyan", "SPOT", (-3.1, 1.6, 1.9), (0.45, 0.85, 1.0), 1000),
        ("TopSlate", "AREA", (0.0, 0.4, 4.5), (0.65, 0.75, 1.0), 420),
    ):
        data = bpy.data.lights.new(name, typ)
        data.color = lc
        data.energy = energy
        if typ == "AREA":
            data.size = 1.8
        else:
            data.spot_size = math.radians(32)
        ob = bpy.data.objects.new(name, data)
        col.objects.link(ob)
        ob.location = loc
        ob.rotation_euler = (Vector((0, 0, 1.0)) - ob.location).to_track_quat("-Z", "Y").to_euler()

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
    verts = 0
    faces = 0
    non_manifold = 0
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
    assert faces < 10000, f"Evan mesh exceeded 10k tri budget ({faces} faces)"

    ground_shift = -gmin.z
    if abs(ground_shift) > 1e-9:
        arm.location.z += ground_shift
        gmin.z = 0.0
        gmax.z += ground_shift
        print(f"[QA] ground-seated by +{ground_shift:.4f} m -> minZ=0.0000")

    # -------------------------------------------------------------- author manifest
    manifest = {
        "image_resolution": [404, 443],
        "camera_telemetry": {
            "focal_length_px": None,
            "horizontal_fov_deg": None,
            "vanishing_points": None,
            "note": "Stylized 2D illustration — vanishing-point metrology intentionally skipped.",
        },
        "metric_dimensions_m": {
            "width_x": dims[0], "depth_y": dims[1], "height_z": dims[2],
            "estimated_stories": 1, "roof_pitch_deg": 0.0,
            "wall_thickness_ext": 0.0, "wall_thickness_int": 0.0,
        },
        "pbr_palette_srgb": ["#f2ebd4", "#f00a57", "#fa0d6e", "#66361a"],
        "rig": {
            "bone_count": BONE_COUNT, "profile": "SkeletonProfileHumanoid",
            "actions": list(ACTION_NAMES), "skinning": "rigid-1.0-vertex-groups",
        },
        "notes": ("Authored dimension spec for the stylized Evan-the-Skeleton reference "
                  "(docs/plans/Designs/Evan the Skeleton/Evan the skeleton.jpeg). "
                  "On-foot running skeleton guitarist, ground datum minZ=0.000."),
    }
    manifest_path = os.path.join(REPO_ROOT, "evan_spatial_manifest.json")
    tmp_manifest = manifest_path + ".tmp"
    with open(tmp_manifest, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp_manifest, manifest_path)

    # -------------------------------------------------------------- save / export
    blend_path = os.path.join(REPO_ROOT, "Evan_Skeleton.blend")
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
    glb_path = os.path.join(REPO_ROOT, "godot/assets/Evan_Skeleton.glb")
    bpy.ops.export_scene.gltf(
        filepath=glb_path, export_format="GLB", use_selection=True, export_yup=True,
        export_cameras=False, export_lights=False, export_animations=True,
        export_nla_strips=True, export_draco_mesh_compression_enable=False,
    )
    print("GLB_SAVED", glb_path)

    arm.animation_data.use_nla = False
    for pb in pose:
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    for ob, _ in parts:
        ob.select_set(True)
    stl_path = os.path.join(REPO_ROOT, "Evan_Skeleton.stl")
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
            "front34": ((1.7, -2.5, 1.15), 36, None),
            "side": ((2.8, 0.0, 1.05), 36, None),
            "back34": ((1.7, 2.5, 1.15), 36, None),
            "front": ((0.0, -2.9, 1.10), 36, None),
            "run_stride": ((2.4, -1.2, 1.08), 36, (strum, 0.625)),
            "run_pushoff": ((2.6, -0.5, 1.05), 36, (strum, 0.25)),
            "run_noguitar": ((2.3, -1.4, 1.08), 36, (run_noguitar, 0.50)),
            "throw": ((1.9, -2.1, 1.15), 36, (guitar_throw, 0.52)),
            "bigfinish_leap": ((1.1, -2.6, 1.18), 36, (finish, 0.50)),
        }
        for name, (loc, lens, pose_spec) in views.items():
            for pb in pose:
                pb.rotation_euler = (0.0, 0.0, 0.0)
                pb.location = (0.0, 0.0, 0.0)
            if pose_spec is not None:
                fn, u_val = pose_spec
                fn(pose, u_val)
            bpy.context.view_layer.update()
            cam.location = loc
            cam.data.lens = lens
            cam.rotation_euler = (Vector((0.0, -0.05, 0.96)) - cam.location).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = os.path.join(previews, f"evan_{name}.png")
            bpy.ops.render.render(write_still=True)
            print("PREVIEW", scene.render.filepath)
        arm.animation_data.use_nla = True

    return {
        "verts": verts, "faces": faces, "non_manifold_edges": non_manifold,
        "min_z": round(gmin.z, 6), "bbox_m": dims,
        "bone_count": BONE_COUNT, "actions": list(ACTION_NAMES),
        "manifest": manifest_path, "glb": glb_path, "stl": stl_path,
    }


if __name__ == "__main__":
    build_evan()
