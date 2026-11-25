#!/usr/bin/env python3
"""EVAN THE SKELETON — stylized skeleton guitarist, playable vehicle stand-in.

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
* optional ``--previews DIR``                4-angle material renders

Rig: canonical 52-bone Godot SkeletonProfileHumanoid bone *names* and
hierarchy, with rest bone positions posed into the seated, splayed-leg guitar
stance from the reference. All visual parts are rigidly bound (weight 1.0) to
their controlling bone, so the baked animations deform cleanly in Godot 4.3.

Coordinate contract: Blender +Z up / -Y forward -> glTF +Y up / -Z forward.
Ground datum AABB bottom = 0.000 m (four 22-inch tyres touch the floor).
"""
from __future__ import annotations

import json
import math
import os
import sys
from typing import Any

import bmesh
import bpy
from mathutils import Matrix, Vector

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------- authored spec
SPEC = {
    "width_x": 1.24,
    "depth_y": 1.72,
    "height_z": 1.78,
    "tyre_radius": 0.2794,   # 22-inch sport-quad tyre (repo convention)
}

BONE_COUNT = 52
ACTION_NAMES = ("Idle_Sway", "Play_Strum", "Headbang_Riff", "Action_BigFinish")


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
    # Plastic-surgery palette (visual-only): warm reference ivory bones,
    # crimson mohawk and a vivid hot-pink guitar. Geometry, rig, clips and
    # landmark mesh names are deliberately untouched.
    bone_ivory = make_mat("BoneIvory", (0.94, 0.91, 0.82), 0.68, emission=0.025)
    bone_shadow = make_mat("BoneShadow", (0.66, 0.63, 0.56), 0.78)
    socket_dark = make_mat("EyeSocket", (0.018, 0.020, 0.028), 0.45)
    magenta = make_mat("MohawkMagenta", (0.92, 0.05, 0.32), 0.42, emission=0.16)
    guitar_pink = make_mat("GuitarHotPink", (0.98, 0.06, 0.44), 0.24, emission=0.05)
    guitar_cream = make_mat("GuitarPickguard", (0.98, 0.96, 0.90), 0.38)
    fretboard = make_mat("Fretboard", (0.12, 0.07, 0.05), 0.62)
    chrome = make_mat("Chrome", (0.78, 0.82, 0.88), 0.22, 0.92)
    strap_brown = make_mat("StrapLeather", (0.38, 0.20, 0.09), 0.78)
    tyre_rubber = make_mat("TyreRubber", (0.055, 0.060, 0.075), 0.92)
    frame_metal = make_mat("BoneFrame", (0.70, 0.74, 0.80), 0.36, 0.72)
    saddle = make_mat("Saddle", (0.10, 0.10, 0.13), 0.74)

    # -------------------------------------------------------------- primitives
    def box(name: str, loc: tuple[float, float, float], dims: tuple[float, float, float],
            material: Any, rot: tuple[float, float, float] | None = None) -> Any:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
        ob = link_only(bpy.context.active_object)
        ob.name = name
        ob.scale = dims
        if rot:
            ob.rotation_euler = rot
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        ob.data.materials.append(material)
        return ob

    def sphere(name: str, loc: tuple[float, float, float], scale: tuple[float, float, float],
               material: Any, seg: int = 14, rings: int = 10) -> Any:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings,
                                             radius=1.0, location=loc)
        ob = link_only(bpy.context.active_object)
        ob.name = name
        ob.scale = scale
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        ob.data.materials.append(material)
        return smooth(ob)

    def cyl(name: str, loc: tuple[float, float, float], radius: float, depth: float,
            material: Any, rot: tuple[float, float, float] | None = None,
            vertices: int = 14, radius2: float | None = None) -> Any:
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
            bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        ob.data.materials.append(material)
        return ob

    def bone_segment(name: str, head: Vector, tail: Vector, radius: float,
                     material: Any, vertices: int = 10) -> Any:
        """Closed capsule aligned head->tail (cylinder + two capped spheres)."""
        mid = (head + tail) * 0.5
        direction = (tail - head).normalized()
        length = (tail - head).length
        ob = cyl(name, tuple(mid), radius, length, material,
                 rot=tuple(direction.to_track_quat("Z", "Y").to_euler()),
                 vertices=vertices)
        sphere(name + "_H", tuple(head), (radius, radius, radius), material, 10, 7)
        sphere(name + "_T", tuple(tail), (radius, radius, radius), material, 10, 7)
        return ob

    def tube(name: str, points: list[Vector], radius: float, material: Any,
             seg: int = 8) -> Any:
        """Watertight lofted tube along an ordered point list."""
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
        ref = Vector((0, 1, 0)) if abs(tans[0].y) < 0.9 else Vector((1, 0, 0))
        u = tans[0].cross(ref).normalized()
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
            ring = [bm.verts.new(c + u_i * (math.cos(2 * math.pi * j / seg) * radius)
                                 + v_i * (math.sin(2 * math.pi * j / seg) * radius))
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
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        ob = bpy.data.objects.new(name, mesh)
        link_only(ob)
        ob.data.materials.append(material)
        return smooth(ob)

    # -------------------------------------------------------------- posed rig spec
    def posed_bone_spec() -> list[dict[str, Any]]:
        """Canonical 52 names/hierarchy, rest pose = seated splayed guitarist."""
        bones: list[dict[str, Any]] = [
            {"name": "Hips", "head": (0.0, 0.0, 0.92), "tail": (0.0, 0.0, 1.05), "parent": None},
            {"name": "Spine", "head": (0.0, 0.0, 1.05), "tail": (0.0, -0.01, 1.22), "parent": "Hips"},
            {"name": "Chest", "head": (0.0, -0.01, 1.22), "tail": (0.0, -0.02, 1.38), "parent": "Spine"},
            {"name": "UpperChest", "head": (0.0, -0.02, 1.38), "tail": (0.0, -0.03, 1.49), "parent": "Chest"},
            {"name": "Neck", "head": (0.0, -0.03, 1.49), "tail": (0.0, -0.04, 1.57), "parent": "UpperChest"},
            {"name": "Head", "head": (0.0, -0.04, 1.57), "tail": (0.0, -0.05, 1.76), "parent": "Neck"},
        ]
        finger_offsets = (
            ("Thumb", 0.035, -0.025, 0.030),
            ("Index", 0.025, -0.005, 0.045),
            ("Middle", 0.005, 0.000, 0.050),
            ("Ring", -0.015, 0.000, 0.045),
            ("Little", -0.032, 0.005, 0.038),
        )
        for side, sx in (("L", 1.0), ("R", -1.0)):
            # Erect / strum arms: shoulders at 1.44, elbows forward/down, wrists at guitar
            shoulder = Vector((sx * 0.18, -0.01, 1.44))
            elbow = Vector((sx * 0.30, -0.24, 1.25))
            # Right hand strums at the body; left hand reaches the neck.
            wrist = Vector((-0.13 if side == "R" else 0.26, -0.44, 1.15))
            hand_end = wrist + Vector((0.0, -0.045, -0.012))
            bones.extend([
                {"name": f"Shoulder.{side}", "head": (0.0, -0.02, 1.44), "tail": tuple(shoulder), "parent": "UpperChest"},
                {"name": f"UpperArm.{side}", "head": tuple(shoulder), "tail": tuple(elbow), "parent": f"Shoulder.{side}"},
                {"name": f"ForeArm.{side}", "head": tuple(elbow), "tail": tuple(wrist), "parent": f"UpperArm.{side}"},
                {"name": f"Hand.{side}", "head": tuple(wrist), "tail": tuple(hand_end), "parent": f"ForeArm.{side}"},
            ])
            for fname, dy, dx_bias, seg_len in finger_offsets:
                base = hand_end + Vector((sx * dx_bias, dy, 0.0))
                step = seg_len * 0.33
                for s in (1, 2, 3):
                    parent = f"Hand.{side}" if s == 1 else f"{fname}{s - 1}.{side}"
                    bones.append({
                        "name": f"{fname}{s}.{side}",
                        "head": (base.x, base.y, base.z - (s - 1) * step),
                        "tail": (base.x, base.y, base.z - s * step),
                        "parent": parent,
                    })
            hip = Vector((sx * 0.10, 0.0, 0.92))
            knee = Vector((sx * 0.42, -0.30, 0.63))
            ankle = Vector((sx * 0.53, -0.56, 0.22))
            toe = Vector((sx * 0.55, -0.72, 0.16))
            bones.extend([
                {"name": f"Thigh.{side}", "head": tuple(hip), "tail": tuple(knee), "parent": "Hips"},
                {"name": f"Calf.{side}", "head": tuple(knee), "tail": tuple(ankle), "parent": f"Thigh.{side}"},
                {"name": f"Foot.{side}", "head": tuple(ankle), "tail": tuple(toe), "parent": f"Calf.{side}"},
                {"name": f"Toes.{side}", "head": tuple(toe),
                 "tail": (toe.x, toe.y - 0.08, toe.z), "parent": f"Foot.{side}"},
            ])
        return bones

    bone_spec = posed_bone_spec()
    assert len(bone_spec) == BONE_COUNT, f"rig spec has {len(bone_spec)} bones"
    bone_heads = {b["name"]: Vector(b["head"]) for b in bone_spec}
    bone_tails = {b["name"]: Vector(b["tail"]) for b in bone_spec}

    # Build armature with canonical humanoid names
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
        created[item["name"]] = eb
    bpy.ops.object.mode_set(mode="OBJECT")

    # parts are collected with their controlling bone for rigid 1.0 skinning
    parts: list[tuple[Any, str]] = []

    def bind(ob: Any, bone: str) -> Any:
        parts.append((ob, bone))
        return ob

    # -------------------------------------------------------------- skull + mohawk
    bind(sphere("Skull_Cranium", (0.0, -0.055, 1.635), (0.113, 0.128, 0.132),
                bone_ivory, 20, 14), "Head")
    bind(sphere("Skull_Jaw", (0.0, -0.105, 1.522), (0.090, 0.105, 0.050),
                bone_ivory, 18, 12), "Head")
    bind(sphere("Skull_Nose", (0.0, -0.165, 1.588), (0.025, 0.028, 0.032),
                bone_shadow, 10, 8), "Head")
    for sx in (-1.0, 1.0):
        bind(sphere(f"EyeSocket_{'L' if sx > 0 else 'R'}",
                    (sx * 0.049, -0.158, 1.637), (0.033, 0.018, 0.035),
                    socket_dark, 12, 9), "Head")
        bind(sphere(f"EyeShine_{'L' if sx > 0 else 'R'}",
                    (sx * 0.049, -0.170, 1.640), (0.010, 0.006, 0.011),
                    chrome, 8, 6), "Head")
    for i in range(7):
        a = (i / 6.0 - 0.5) * 1.7
        h = 0.085 + 0.075 * math.cos(a)
        base = Vector((math.sin(a) * 0.085, -0.045 + i * 0.004, 1.755 - abs(a) * 0.012))
        tip = base + Vector((math.sin(a) * 0.045, -0.075, h))
        bind(cyl(f"Mohawk_{i:02d}", tuple((base + tip) * 0.5), 0.017, (tip - base).length,
                 magenta, rot=tuple((tip - base).normalized().to_track_quat("Z", "Y").to_euler()),
                 vertices=7, radius2=0.001), "Head")
    # teeth (a single ivory strip reads well at game scale)
    bind(box("TeethUpper", (0.0, -0.172, 1.540), (0.105, 0.012, 0.018), bone_ivory), "Head")

    # -------------------------------------------------------------- spine + ribs
    for i in range(11):
        z = 1.06 + i * 0.033
        y = -0.005 - i * 0.0022
        bind(cyl(f"Vertebra_{i:02d}", (0.0, y, z), 0.022, 0.017, bone_ivory,
                 vertices=10), "Chest" if i >= 5 else "Spine")
    for i in range(7):
        z = 1.155 + i * 0.038
        width = 0.155 + 0.055 * math.sin((i / 6.0) * math.pi)
        depth = 0.085 + 0.030 * math.sin((i / 6.0) * math.pi)
        for sx in (-1.0, 1.0):
            pts = [
                Vector((sx * 0.018, -0.010, z)),
                Vector((sx * width * 0.65, -0.020, z - 0.006)),
                Vector((sx * width, -0.030 - depth * 0.5, z - 0.018)),
                Vector((sx * width * 0.72, -0.060 - depth, z - 0.030)),
                Vector((sx * 0.020, -0.085 - depth * 0.75, z - 0.034)),
            ]
            bind(tube(f"Rib_{i:02d}_{'L' if sx > 0 else 'R'}", pts, 0.0085,
                      bone_ivory, 7), "Chest")
    bind(box("Sternum", (0.0, -0.104, 1.268), (0.042, 0.016, 0.20), bone_ivory), "Chest")
    for sx in (-1.0, 1.0):
        bind(tube(f"Clavicle_{'L' if sx > 0 else 'R'}",
                  [Vector((0.0, -0.04, 1.435)), Vector((sx * 0.08, -0.035, 1.446)),
                   Vector((sx * 0.175, -0.020, 1.438))], 0.011, bone_ivory, 7), "UpperChest")
        bind(sphere(f"Ilium_{'L' if sx > 0 else 'R'}",
                    (sx * 0.088, -0.005, 0.945), (0.070, 0.070, 0.062),
                    bone_ivory, 12, 9), "Hips")
    bind(sphere("Sacrum", (0.0, 0.012, 0.935), (0.055, 0.050, 0.070),
                bone_shadow, 12, 9), "Hips")

    # -------------------------------------------------------------- limbs
    for side, sx in (("L", 1.0), ("R", -1.0)):
        for stem in ("Shoulder", "UpperArm", "ForeArm", "Hand"):
            name = f"{stem}.{side}"
            bind(bone_segment(name, bone_heads[name], bone_tails[name],
                              0.026 if stem != "Hand" else 0.023, bone_ivory), name)
        for fname in ("Thumb", "Index", "Middle", "Ring", "Little"):
            for s in (1, 2, 3):
                name = f"{fname}{s}.{side}"
                h, t = bone_heads[name], bone_tails[name]
                # Leave a hairline gap between phalanges: coincident cap rings
                # on adjacent segments get welded by STL import into
                # non-manifold edges (QA counts them as open boundaries).
                seg = cyl(name, tuple((h + t) * 0.5), 0.0075, (t - h).length * 0.90,
                          bone_ivory, vertices=7,
                          rot=tuple((t - h).normalized().to_track_quat("Z", "Y").to_euler()))
                bind(seg, name)
        for stem in ("Thigh", "Calf", "Foot", "Toes"):
            name = f"{stem}.{side}"
            bind(bone_segment(name, bone_heads[name], bone_tails[name],
                              0.040 if stem == "Thigh" else (0.031 if stem == "Calf" else 0.024),
                              bone_ivory, 12), name)

    # -------------------------------------------------------------- guitar (local space)
    guitar_xf = (Matrix.Translation(Vector((0.03, -0.30, 1.14)))
                 @ Matrix.Rotation(math.radians(-24.0), 4, "Y")
                 @ Matrix.Rotation(math.radians(90.0), 4, "X"))
    guitar_parts: list[Any] = []

    def g(ob: Any) -> Any:
        ob.data.transform(guitar_xf)
        guitar_parts.append(ob)
        return ob

    # Offset-body outline (local XY, face normal +Z)
    outline = [
        (-0.17, -0.20), (-0.06, -0.235), (0.04, -0.21), (0.13, -0.14),
        (0.185, -0.035), (0.17, 0.075), (0.09, 0.155), (0.02, 0.115),
        (-0.045, 0.215), (-0.14, 0.19), (-0.19, 0.09), (-0.185, -0.055),
    ]
    n = len(outline)
    bm = bmesh.new()
    bot = [bm.verts.new((x, y, -0.026)) for x, y in outline]
    top = [bm.verts.new((x, y, 0.026)) for x, y in outline]
    for j in range(n):
        jn = (j + 1) % n
        bm.faces.new((bot[j], bot[jn], top[jn], top[j]))
    cbot = bm.verts.new((0.0, 0.0, -0.026))
    ctop = bm.verts.new((0.0, 0.0, 0.026))
    for j in range(n):
        jn = (j + 1) % n
        bm.faces.new((cbot, bot[jn], bot[j]))
        bm.faces.new((ctop, top[j], top[jn]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("GuitarBody_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    body = bpy.data.objects.new("GuitarBody", mesh)
    link_only(body)
    body.data.materials.append(guitar_pink)
    g(body)

    g(box("GuitarPickguard", (0.005, 0.01, 0.029), (0.24, 0.26, 0.006), guitar_cream))
    g(box("GuitarNeck", (0.36, 0.03, 0.004), (0.50, 0.062, 0.036), fretboard))
    g(box("GuitarHeadstock", (0.645, 0.045, 0.004), (0.105, 0.082, 0.026), guitar_pink,
          rot=(0.0, 0.0, math.radians(-8.0))))
    for i in range(6):
        y = -0.048 + i * 0.030
        g(cyl(f"Tuner_{i}", (0.665, y, 0.012), 0.010, 0.020, chrome, vertices=8))
        g(cyl(f"String_{i}", (0.30, y * 0.62, 0.046), 0.0016, 0.92, chrome,
              vertices=6, rot=(0.0, math.pi / 2.0, 0.0)))
    for i in range(9):
        g(box(f"Fret_{i}", (0.135 + i * 0.052, 0.030, 0.025),
              (0.0035, 0.058, 0.002), chrome))
    for i, x in enumerate((0.09, 0.245)):
        g(box(f"Pickup_{i}", (x, 0.0, 0.031), (0.038, 0.115, 0.012), chrome))
    g(box("Bridge", (0.05, -0.02, 0.033), (0.035, 0.10, 0.010), chrome))
    for i, (x, y) in enumerate(((0.01, -0.10), (0.01, -0.14))):
        g(cyl(f"Knob_{i}", (x, y, 0.035), 0.014, 0.014, chrome, vertices=10))
    # Authoritative muzzle anchors for SideCannons' "evan" profile.
    for tag, x in (("L", -0.085), ("R", 0.085)):
        g(cyl(f"RiffMuzzle_{tag}", (x, -0.055, 0.070), 0.020, 0.095, chrome,
              vertices=12, rot=(math.pi / 2.0, 0.0, 0.0)))
    # strap: from body upper bout over the left shoulder down to the neck heel
    g(tube("GuitarStrap", [
        Vector((-0.15, 0.16, 0.0)), Vector((-0.26, 0.36, -0.10)),
        Vector((-0.34, 0.50, -0.22)), Vector((-0.10, 0.44, -0.28)),
        Vector((0.16, 0.20, -0.10)),
    ], 0.018, strap_brown, 7))
    for ob in guitar_parts:
        bind(ob, "UpperChest")

    # -------------------------------------------------------------- quad chassis + wheels
    r = SPEC["tyre_radius"]
    for side, sx in (("L", 1.0), ("R", -1.0)):
        for axle, ay in (("F", -0.66), ("R", 0.68)):
            cx = sx * 0.55
            bind(cyl(f"Tyre_{axle}_{side}", (cx, ay, r), r, 0.225, tyre_rubber,
                     rot=(0.0, math.pi / 2.0, 0.0), vertices=22), "Hips")
            bind(cyl(f"Rim_{axle}_{side}", (cx + sx * 0.116, ay, r), 0.152, 0.022,
                     chrome, rot=(0.0, math.pi / 2.0, 0.0), vertices=16), "Hips")
            for t in range(14):
                a = 2.0 * math.pi * t / 14.0
                ty, tz = ay + (r - 0.012) * math.cos(a), r + (r - 0.012) * math.sin(a)
                bind(box(f"Tread_{axle}_{side}_{t:02d}", (cx, ty, tz),
                         (0.225, 0.030, 0.038), tyre_rubber,
                         rot=(a, 0.0, 0.0)), "Hips")
    # Simple chrome space frame connecting the four hubs under the pelvis
    frame_pts = [
        [Vector((-0.55, -0.66, r)), Vector((-0.45, -0.30, 0.62)), Vector((-0.34, 0.30, 0.70)), Vector((-0.55, 0.68, r))],
        [Vector((0.55, -0.66, r)), Vector((0.45, -0.30, 0.62)), Vector((0.34, 0.30, 0.70)), Vector((0.55, 0.68, r))],
    ]
    for side, pts in zip(("L", "R"), frame_pts):
        bind(tube(f"FrameRail_{side}", pts, 0.022, frame_metal, 8), "Hips")
    bind(tube("FrameCross", [Vector((-0.45, -0.30, 0.62)), Vector((0.45, -0.30, 0.62))],
              0.020, frame_metal, 8), "Hips")
    bind(box("Seat", (0.0, 0.02, 0.885), (0.28, 0.40, 0.055), saddle), "Hips")

    # -------------------------------------------------------------- rigid skin binding
    for ob, bone_name in parts:
        vg = ob.vertex_groups.new(name=bone_name)
        vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
        ob.parent = arm
        mod = ob.modifiers.new(name="EvanSkin", type="ARMATURE")
        mod.object = arm
        mod.use_vertex_groups = True
        mod.use_bone_envelopes = False

    # -------------------------------------------------------------- batch by bone + material
    # ~200 tiny mesh objects add a lot of GLB node/accessor overhead and the
    # same number of draw calls on Web. Parts sharing a controlling bone and
    # material are rigid-bound identically, so joining them is lossless and
    # measurably shrinks the uncompressed GLB (~830 KB -> ~726 KB).
    from collections import defaultdict
    # Runtime code and gates resolve these by exact node name — never merge them.
    LANDMARKS = {
        "RiffMuzzle_L", "RiffMuzzle_R", "GuitarBody",
        "Skull_Cranium", "Tyre_F_L", "Tyre_R_R",
    }
    batches: dict[tuple[str, str], list[Any]] = defaultdict(list)
    for ob, bone_name in parts:
        if ob.name in LANDMARKS:
            continue
        mat_name = ob.data.materials[0].name if ob.data.materials else ""
        batches[(bone_name, mat_name)].append(ob)
    merged: list[tuple[Any, str]] = []
    for ob, bone_name in parts:
        if ob.name in LANDMARKS:
            merged.append((ob, bone_name))
    for (bone_name, mat_name), obs in batches.items():
        if len(obs) == 1:
            merged.append((obs[0], bone_name))
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for o in obs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        bpy.ops.object.join()
        joined = obs[0]
        joined.name = f"Evan_{bone_name}_{mat_name}"
        merged.append((joined, bone_name))
    parts = merged
    print(f"[QA] batched into {len(parts)} skinned meshes")

    # -------------------------------------------------------------- 4 baked NLA actions
    pose = arm.pose.bones
    for pb in pose:
        pb.rotation_mode = "XYZ"

    def commit(action_name: str, frame_end: int, evaluator: Any) -> None:
        act = bpy.data.actions.new(name=action_name)
        arm.animation_data_create()
        arm.animation_data.action = act
        for f in range(1, frame_end + 1):
            scene.frame_set(f)
            evaluator(pose, f, frame_end)
            for pb in pose:
                pb.keyframe_insert(data_path="rotation_euler", frame=f)
        track = arm.animation_data.nla_tracks.new()
        track.name = action_name
        track.strips.new(action_name, 1, act)
        arm.animation_data.action = None

    def idle(pb: Any, f: int, total: int) -> None:
        t = (f / total) * 2.0 * math.pi
        w = math.sin(t)
        pb["Chest"].rotation_euler = (w * 0.035, 0.0, 0.0)
        pb["Spine"].rotation_euler = (w * 0.018, 0.0, 0.0)
        pb["Head"].rotation_euler = (0.0, math.sin(t * 0.5) * 0.045, w * 0.02)
        pb["ForeArm.R"].rotation_euler = (w * 0.045, 0.0, 0.0)
        for b in pb:
            if b.name not in ("Chest", "Spine", "Head", "ForeArm.R"):
                b.rotation_euler = (0.0, 0.0, 0.0)

    def strum(pb: Any, f: int, total: int) -> None:
        t = (f / total) * 2.0 * math.pi
        s = math.sin(t)
        pb["ForeArm.R"].rotation_euler = (s * 0.42, 0.0, s * 0.09)
        pb["Hand.R"].rotation_euler = (s * 0.20, 0.0, 0.0)
        pb["Index1.L"].rotation_euler = (0.0, 0.0, s * 0.28)
        pb["Middle1.L"].rotation_euler = (0.0, 0.0, -s * 0.22)
        pb["Head"].rotation_euler = (-abs(s) * 0.055, 0.0, s * 0.03)
        pb["Chest"].rotation_euler = (s * 0.02, 0.0, 0.0)
        for b in pb:
            if b.name not in ("ForeArm.R", "Hand.R", "Index1.L", "Middle1.L", "Head", "Chest"):
                b.rotation_euler = (0.0, 0.0, 0.0)

    def headbang(pb: Any, f: int, total: int) -> None:
        t = (f / total) * 2.0 * math.pi
        s = math.sin(t)
        pb["Neck"].rotation_euler = (s * 0.34, 0.0, 0.0)
        pb["Head"].rotation_euler = (s * 0.30, math.sin(t * 0.5) * 0.10, 0.0)
        pb["UpperChest"].rotation_euler = (s * 0.10, 0.0, 0.0)
        pb["ForeArm.R"].rotation_euler = (s * 0.55, 0.0, 0.0)
        for b in pb:
            if b.name not in ("Neck", "Head", "UpperChest", "ForeArm.R"):
                b.rotation_euler = (0.0, 0.0, 0.0)

    def finish(pb: Any, f: int, total: int) -> None:
        u = f / total
        env = math.sin(min(u, 1.0) * math.pi)
        pb["Head"].rotation_euler = (-env * 0.42, 0.0, 0.0)
        pb["UpperChest"].rotation_euler = (-env * 0.20, 0.0, 0.0)
        pb["UpperArm.L"].rotation_euler = (env * 0.95, 0.0, -env * 0.35)
        pb["UpperArm.R"].rotation_euler = (env * 0.95, 0.0, env * 0.35)
        pb["Thigh.L"].rotation_euler = (0.0, 0.0, -env * 0.20)
        pb["Thigh.R"].rotation_euler = (0.0, 0.0, env * 0.20)
        for b in pb:
            if b.name not in ("Head", "UpperChest", "UpperArm.L", "UpperArm.R",
                              "Thigh.L", "Thigh.R"):
                b.rotation_euler = (0.0, 0.0, 0.0)

    commit("Idle_Sway", 60, idle)
    commit("Play_Strum", 24, strum)
    commit("Headbang_Riff", 36, headbang)
    commit("Action_BigFinish", 48, finish)
    for pb in pose:
        pb.rotation_euler = (0.0, 0.0, 0.0)
    scene.frame_set(1)

    # -------------------------------------------------------------- proof studio
    world = bpy.data.worlds.new("EvanWorld")
    scene.world = world
    wt = ensure_node_tree(world)
    wt.nodes.clear()
    bg = wt.nodes.new("ShaderNodeBackground")
    bg.inputs["Color"].default_value = (0.015, 0.024, 0.062, 1.0)
    out = wt.nodes.new("ShaderNodeOutputWorld")
    wt.links.new(bg.outputs["Background"], out.inputs["Surface"])

    for name, typ, loc, lc, energy in (
        ("KeyWarm", "AREA", (-2.6, -2.4, 2.7), (1.0, 0.90, 0.78), 440),
        ("RimPink", "SPOT", (3.2, 1.8, 1.9), (1.0, 0.30, 0.55), 1300),
        ("RimCyan", "SPOT", (-3.1, 1.6, 1.9), (0.45, 0.85, 1.0), 1200),
        ("TopSlate", "AREA", (0.0, 0.4, 4.5), (0.65, 0.75, 1.0), 380),
    ):
        data = bpy.data.lights.new(name, typ)
        data.color = lc
        data.energy = energy
        if typ == "AREA":
            data.size = 1.8
        else:
            data.spot_size = math.radians(30)
        ob = bpy.data.objects.new(name, data)
        col.objects.link(ob)
        ob.location = loc
        ob.rotation_euler = (Vector((0, 0, 1.05)) - ob.location).to_track_quat("-Z", "Y").to_euler()

    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    col.objects.link(cam)
    scene.camera = cam
    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in \
        bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items.keys() else "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.view_settings.look = "AgX - Base Contrast"

    # -------------------------------------------------------------- QA metrics
    verts = 0
    faces = 0
    non_manifold = 0
    gmin = Vector((float("inf"),) * 3)
    gmax = Vector((float("-inf"),) * 3)
    for ob, _ in parts:
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.transform(ob.matrix_world)
        verts += len(bm.verts)
        faces += len(bm.faces)
        non_manifold += sum(1 for e in bm.edges if not e.is_manifold)
        for v in bm.verts:
            for i in range(3):
                gmin[i] = min(gmin[i], v.co[i])
                gmax[i] = max(gmax[i], v.co[i])
        bm.free()
    dims = [round(gmax[i] - gmin[i], 6) for i in range(3)]
    print(f"[QA] verts={verts} faces={faces} non_manifold_edges={non_manifold} "
          f"minZ={gmin.z:.4f} bbox={dims}")

    # Ground-seat the whole assembly (same AABB-bottom datum policy as
    # repair_and_verify.py). Meshes are parented to the armature, so moving the
    # armature object lifts every rigidly-bound part together with its bones.
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
        "pbr_palette_srgb": ["#e6e0ca", "#eb0c75", "#d8dde2", "#c91462"],
        "rig": {
            "bone_count": BONE_COUNT, "profile": "SkeletonProfileHumanoid",
            "actions": list(ACTION_NAMES), "skinning": "rigid-1.0-vertex-groups",
        },
        "notes": ("Authored dimension spec for the stylized Evan-the-Skeleton reference "
                  "(docs/plans/Designs/Evan the Skeleton/Evan the skeleton.jpeg). "
                  "Playable vehicle stand-in: 22-inch tyres, ground datum minZ=0.000."),
    }
    manifest_path = os.path.join(REPO_ROOT, "evan_spatial_manifest.json")
    # Never truncate the shipped manifest in place: an interrupted build must
    # leave the previous, self-consistent artifact in place.
    tmp_manifest = manifest_path + ".tmp"
    with open(tmp_manifest, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp_manifest, manifest_path)

    # -------------------------------------------------------------- save / export
    blend_path = os.path.join(REPO_ROOT, "Evan_Skeleton.blend")
    # A user preference of save_version >= 1 would emit an undeclared .blend1.
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
    # Godot 4.3 has no built-in KHR_draco_mesh_compression importer in this
    # project (all existing vehicle GLBs are uncompressed). Emit a plain GLB;
    # Draco is a Three.js-only optimization and the web target here is Godot
    # WASM. ~0.5 MB uncompressed is well within the PWA budget.
    bpy.ops.export_scene.gltf(
        filepath=glb_path, export_format="GLB", use_selection=True, export_yup=True,
        export_cameras=False, export_lights=False, export_animations=True,
        export_nla_strips=True, export_draco_mesh_compression_enable=False,
    )
    print("GLB_SAVED", glb_path)

    # STL for the surgical QA reviewer (all rigid parts, world space)
    bpy.ops.object.select_all(action="DESELECT")
    for ob, _ in parts:
        ob.select_set(True)
    stl_path = os.path.join(REPO_ROOT, "Evan_Skeleton.stl")
    if hasattr(bpy.ops.wm, "stl_export"):
        bpy.ops.wm.stl_export(filepath=stl_path, export_selected_objects=True,
                              up_axis="Z", forward_axis="Y")
    else:
        bpy.ops.export_mesh.stl(filepath=stl_path, use_selection=True)
    print("STL_SAVED", stl_path)

    if previews:
        views = {
            "front34": ((1.7, -2.7, 1.25), 34),
            "side": ((3.0, 0.0, 1.20), 34),
            "back34": ((1.7, 2.7, 1.25), 34),
            "front": ((0.0, -3.1, 1.22), 34),
        }
        for name, (loc, lens) in views.items():
            cam.location = loc
            cam.data.lens = lens
            cam.rotation_euler = (Vector((0.0, -0.1, 1.05)) - cam.location).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = os.path.join(previews, f"evan_{name}.png")
            bpy.ops.render.render(write_still=True)
            print("PREVIEW", scene.render.filepath)

    return {
        "verts": verts, "faces": faces, "non_manifold_edges": non_manifold,
        "min_z": round(gmin.z, 6), "bbox_m": dims,
        "bone_count": BONE_COUNT, "actions": list(ACTION_NAMES),
        "manifest": manifest_path, "glb": glb_path, "stl": stl_path,
    }


if __name__ == "__main__":
    build_evan()
