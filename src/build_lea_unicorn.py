#!/usr/bin/env python3
"""LEA UNICORN — heroic AAA-stylized Pegasus unicorn vehicle stand-in.

Blender source of truth. Never hand-edit Lea_Unicorn.blend or its GLB; edit
this script and rebuild:

    blender -b -noaudio --threads 4 -P src/build_lea_unicorn.py
    blender -b -noaudio --threads 4 -P src/build_lea_unicorn.py -- --previews /tmp/lea

Pipeline (surgical-building, creative-brief branch — stylized 2D references in
docs/plans/Designs/Lea unicorn/). Emits ``lea_spatial_manifest.json`` at root.

Deliverables
------------
* ``Lea_Unicorn.blend``                     editable source
* ``godot/assets/Lea_Unicorn.glb``          plain non-Draco GLB, 52-joint rig,
                                            4 baked NLA actions
* ``Lea_Unicorn.stl``                       QA mesh (watertight, minZ = 0)
* ``lea_spatial_manifest.json``             authored dim spec for QA
* optional ``--previews DIR``               6-angle material proof renders

Coordinate contract: Blender +Z up / -Y forward -> glTF +Y up / -Z forward.
Ground datum AABB bottom = 0.000 m (all four golden hooves rest flat on z=0).
"""
from __future__ import annotations

from collections import defaultdict
import json
import math
import os
import sys
from typing import Any, Callable

import bmesh
import bpy
from mathutils import Matrix, Vector

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

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


def make_mat(name: str, color: tuple[float, float, float], rough: float = 0.45,
             metallic: float = 0.0, emission: float = 0.0,
             coat: float = 0.0, coat_rough: float = 0.14) -> Any:
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


def _catmull_rom(pts: list[Vector], samples: int) -> list[Vector]:
    """Smooth Catmull-Rom interpolation through control points."""
    if len(pts) < 2 or samples <= len(pts):
        return [Vector(p) for p in pts]
    padded = [pts[0] + (pts[0] - pts[1])] + list(pts) + [pts[-1] + (pts[-1] - pts[-2])]
    n_seg = len(pts) - 1
    out: list[Vector] = []
    for k in range(samples):
        s = (k / (samples - 1)) * n_seg
        i = min(int(math.floor(s)), n_seg - 1)
        t = s - i
        p0, p1, p2, p3 = padded[i], padded[i + 1], padded[i + 2], padded[i + 3]
        t2, t3 = t * t, t * t * t
        v = 0.5 * ((2.0 * p1) + (-p0 + p2) * t
                   + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
                   + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
        out.append(v)
    return out


def _orthonormal_frame(axis: Vector, hint: Vector | None = None) -> tuple[Vector, Vector]:
    if hint is not None:
        u = hint - axis * hint.dot(axis)
        if u.length > 1e-5:
            u.normalize()
            return u, axis.cross(u).normalized()
    ref = Vector((0.0, 1.0, 0.0)) if abs(axis.y) < 0.9 else Vector((1.0, 0.0, 0.0))
    u = axis.cross(ref).normalized()
    v = axis.cross(u).normalized()
    return u, v


def _parallel_frames(pts: list[Vector], hint: Vector | None = None) -> list[tuple[Vector, Vector, Vector]]:
    n = len(pts)
    tans: list[Vector] = []
    for i in range(n):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == n - 1:
            t = pts[-1] - pts[-2]
        else:
            t = pts[i + 1] - pts[i - 1]
        tans.append(t.normalized() if t.length > 1e-7 else Vector((0, 0, 1)))
    u, v = _orthonormal_frame(tans[0], hint)
    frames = [(tans[0], u, v)]
    for i in range(1, n):
        axis = tans[i - 1].cross(tans[i])
        if axis.length > 1e-6:
            rot = Matrix.Rotation(tans[i - 1].angle(tans[i]), 3, axis.normalized())
            u = (rot @ u).normalized()
        v = tans[i].cross(u).normalized()
        frames.append((tans[i], u, v))
    return frames


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

    def finalize_bmesh(name: str, bm: bmesh.types.BMesh, material: Any) -> Any:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh = bpy.data.meshes.new(name + "_Mesh")
        bm.to_mesh(mesh)
        bm.free()
        ob = bpy.data.objects.new(name, mesh)
        link_only(ob)
        ob.data.materials.append(material)
        return smooth(ob)

    # -------------------------------------------------------------- palette (anti-blowout PBR)
    coat = make_mat("PearlCoat", (0.73, 0.791, 0.93), 0.44, emission=0.0, coat=0.22, coat_rough=0.27)
    muzzle_mat = make_mat("MuzzleVelvet", (0.86, 0.74, 0.84), 0.48, emission=0.0)
    ear_inner_mat = make_mat("EarInnerBlush", (0.94, 0.66, 0.82), 0.44, emission=0.02)
    dark_detail = make_mat("PupilDark", (0.015, 0.014, 0.032), 0.20, coat=0.48)
    eye_blue = make_mat("EyeSapphire", (0.028, 0.16, 0.631), 0.10, emission=0.05, coat=0.72)
    mane_pink = make_mat("ManePink", (0.871, 0.145, 0.456), 0.34, emission=0.01, coat=0.20, coat_rough=0.24)
    mane_lav = make_mat("ManeLavender", (0.497, 0.258, 0.807), 0.34, emission=0.01, coat=0.20, coat_rough=0.24)
    mane_cyan = make_mat("ManeCyan", (0.16, 0.673, 0.807), 0.32, emission=0.01, coat=0.20, coat_rough=0.24)
    feather_pearl = make_mat("FeatherPearl", (0.62, 0.78, 0.98), 0.36, emission=0.005, coat=0.18, coat_rough=0.24)
    feather_pink = mane_pink
    feather_lav = mane_lav
    feather_cyan = mane_cyan
    feather_gold = make_mat("FeatherGold", (0.86, 0.60, 0.12), 0.30, metallic=0.45, emission=0.015, coat=0.24)
    gold = make_mat("HornGold", (0.807, 0.479, 0.066), 0.18, metallic=0.88, emission=0.01, coat=0.35)
    horn_glow = make_mat("HornGlow", (1.00, 0.94, 0.58), 0.12, emission=1.18, coat=0.35)
    # Horn and hoof gold are the same visual material family. Sharing the
    # horn's gold keeps the metallic read consistent and saves one GLB slot.
    hoof_gold = gold

    lea_brand_mat = bpy.data.materials.new(name="LeaBrandMat")
    _lb_tree = ensure_node_tree(lea_brand_mat)
    _lb_tree.nodes.clear()
    _lb_out = _lb_tree.nodes.new("ShaderNodeOutputMaterial")
    _lb_bsdf = _lb_tree.nodes.new("ShaderNodeBsdfPrincipled")
    _lb_bsdf.inputs["Roughness"].default_value = 0.22
    _lb_bsdf.inputs["Metallic"].default_value = 0.28
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
            _lb_bsdf.inputs["Emission Strength"].default_value = 0.30
    if hasattr(lea_brand_mat, "blend_method"):
        lea_brand_mat.blend_method = "CLIP"
    if hasattr(lea_brand_mat, "alpha_threshold"):
        lea_brand_mat.alpha_threshold = 0.45
    lea_brand_mat.use_backface_culling = True
    _lb_tree.links.new(_lb_bsdf.outputs["BSDF"], _lb_out.inputs["Surface"])

    # -------------------------------------------------------------- sculpted geometry builders
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

    def loft_sculpted(
        name: str,
        stations: list[tuple[Vector, Vector, Vector, Callable[[float], tuple[float, float]]]],
        material: Any,
        seg: int = 16,
        weights_per_station: list[dict[str, float]] | None = None,
        cap_start_offset: Vector | None = None,
        cap_end_offset: Vector | None = None,
    ) -> tuple[Any, dict[int, dict[str, float]]]:
        """Watertight organic loft where each station carries an explicit 2D contour fn(ang)->(u, v)."""
        bm = bmesh.new()
        rings: list[list[Any]] = []
        v_weights: dict[int, dict[str, float]] = {}
        for c, u_ax, v_ax, shape_fn in stations:
            ring = []
            for j in range(seg):
                ang = 2.0 * math.pi * j / seg
                du, dv = shape_fn(ang)
                ring.append(bm.verts.new(c + u_ax * du + v_ax * dv))
            rings.append(ring)
        for i in range(len(rings) - 1):
            for j in range(seg):
                jn = (j + 1) % seg
                bm.faces.new((rings[i][j], rings[i][jn], rings[i + 1][jn], rings[i + 1][j]))
        c0_pos = stations[0][0] + (cap_start_offset if cap_start_offset is not None else Vector())
        c1_pos = stations[-1][0] + (cap_end_offset if cap_end_offset is not None else Vector())
        c0 = bm.verts.new(c0_pos)
        c1 = bm.verts.new(c1_pos)
        for j in range(seg):
            jn = (j + 1) % seg
            bm.faces.new((c0, rings[0][jn], rings[0][j]))
            bm.faces.new((c1, rings[-1][j], rings[-1][jn]))
        bm.verts.index_update()
        bm.verts.ensure_lookup_table()
        if weights_per_station:
            for si, ring in enumerate(rings):
                w_map = weights_per_station[si]
                for vert in ring:
                    v_weights[vert.index] = w_map
            v_weights[c0.index] = weights_per_station[0]
            v_weights[c1.index] = weights_per_station[-1]
        return finalize_bmesh(name, bm, material), v_weights

    def hair_ribbon(
        name: str,
        ctrl_pts: list[Vector],
        width_base: float,
        thick_base: float,
        material: Any,
        samples: int = 8,
        seg: int = 6,
        twist_rad: float = 0.0,
        hint: Vector | None = None,
    ) -> Any:
        """Watertight S-curved volumetric hair lock with lenticular cross-section & tapered wisp tip."""
        pts = _catmull_rom(ctrl_pts, samples)
        frames = _parallel_frames(pts, hint)
        bm = bmesh.new()
        rings: list[list[Any]] = []
        n = len(pts)
        for i, c in enumerate(pts):
            t = i / max(1, n - 1)
            _, u0, v0 = frames[i]
            tw = twist_rad * t
            ct, st = math.cos(tw), math.sin(tw)
            u = u0 * ct + v0 * st
            v = -u0 * st + v0 * ct
            env_w = (0.86 + 0.34 * math.sin(min(t, 0.5) * math.pi)) * (1.0 - 0.86 * (t ** 1.45))
            env_th = (0.90 + 0.18 * math.sin(min(t, 0.4) * math.pi)) * (1.0 - 0.84 * (t ** 1.35))
            rw = max(0.003, width_base * env_w)
            rt = max(0.0025, thick_base * env_th)
            ring = []
            for j in range(seg):
                ang = 2.0 * math.pi * j / seg
                ca, sa = math.cos(ang), math.sin(ang)
                camber = 0.20 * rt * (1.0 - ca * ca)
                ring.append(bm.verts.new(c + u * (ca * rw) + v * (sa * rt + camber)))
            rings.append(ring)
        for i in range(n - 1):
            for j in range(seg):
                jn = (j + 1) % seg
                bm.faces.new((rings[i][j], rings[i][jn], rings[i + 1][jn], rings[i + 1][j]))
        d0 = (pts[1] - pts[0]).normalized()
        d1 = (pts[-1] - pts[-2]).normalized()
        c0 = bm.verts.new(pts[0] - d0 * 0.004)
        c1 = bm.verts.new(pts[-1] + d1 * 0.012)
        for j in range(seg):
            jn = (j + 1) % seg
            bm.faces.new((c0, rings[0][jn], rings[0][j]))
            bm.faces.new((c1, rings[-1][j], rings[-1][jn]))
        return finalize_bmesh(name, bm, material)

    def feather_blade(
        name: str,
        root: Vector,
        mid: Vector,
        tip: Vector,
        width: float,
        thickness: float,
        blade_normal: Vector,
        material: Any,
        n_stations: int = 5,
    ) -> Any:
        """Watertight slender sculpted curved angelic feather blade with cambered diamond airfoil."""
        pts = _catmull_rom([root, mid, tip], n_stations)
        n_ref = blade_normal.normalized()
        bm = bmesh.new()
        rings: list[list[Any]] = []
        # 4-point cambered feather airfoil (leading edge, upper rachis, trailing edge, lower rachis)
        # Clean, crisp individual feather silhouette at lean tri cost (40 tris per feather!)
        profile = [
            (-1.00, 0.00),
            (0.00, 0.52),
            (1.00, -0.04),
            (0.00, -0.32),
        ]
        n = len(pts)
        for i, c in enumerate(pts):
            t = i / max(1, n - 1)
            tan = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
            w_dir = tan.cross(n_ref)
            if w_dir.length < 1e-5:
                w_dir = Vector((0.0, 0.0, 1.0))
            w_dir.normalize()
            n_dir = w_dir.cross(tan).normalized()
            # Graceful quill-to-vane swell then long tapered angelic feather point (NOT a blunt slab!)
            if t < 0.22:
                wf = 0.45 + 0.55 * (t / 0.22)
            elif t < 0.50:
                wf = 1.0 + 0.06 * math.sin(((t - 0.22) / 0.28) * math.pi)
            else:
                k = (t - 0.50) / 0.50
                wf = max(0.14, (1.0 - k * 0.86) ** 0.85)
            thf = max(0.28, 1.0 - 0.65 * t)
            rw = width * 0.5 * wf
            rt = thickness * 0.5 * thf
            ring = [bm.verts.new(c + w_dir * (px * rw) + n_dir * (py * rt)) for px, py in profile]
            rings.append(ring)
        seg = len(profile)
        for i in range(n - 1):
            for j in range(seg):
                jn = (j + 1) % seg
                bm.faces.new((rings[i][j], rings[i][jn], rings[i + 1][jn], rings[i + 1][j]))
        d0 = (pts[1] - pts[0]).normalized()
        d1 = (pts[-1] - pts[-2]).normalized()
        c0 = bm.verts.new(pts[0] - d0 * 0.004)
        c1 = bm.verts.new(pts[-1] + d1 * max(0.015, width * 0.35))
        for j in range(seg):
            jn = (j + 1) % seg
            bm.faces.new((c0, rings[0][jn], rings[0][j]))
            bm.faces.new((c1, rings[-1][j], rings[-1][jn]))
        return finalize_bmesh(name, bm, material)

    # -------------------------------------------------------------- 52-joint rig
    def bone_spec() -> list[dict[str, Any]]:
        bones: list[dict[str, Any]] = [
            {"name": "Hips", "head": (0.0, 0.36, 0.98), "tail": (0.0, 0.36, 1.14), "parent": None},
            {"name": "Spine", "head": (0.0, 0.22, 0.98), "tail": (0.0, -0.06, 0.98), "parent": "Hips"},
            {"name": "Chest", "head": (0.0, -0.06, 0.98), "tail": (0.0, -0.34, 1.04), "parent": "Spine"},
            {"name": "Withers", "head": (0.0, -0.34, 1.04), "tail": (0.0, -0.50, 1.16), "parent": "Chest"},
            {"name": "Neck1", "head": (0.0, -0.50, 1.16), "tail": (0.0, -0.64, 1.38), "parent": "Withers"},
            {"name": "Neck2", "head": (0.0, -0.64, 1.38), "tail": (0.0, -0.76, 1.56), "parent": "Neck1"},
            {"name": "Skull", "head": (0.0, -0.76, 1.56), "tail": (0.0, -1.00, 1.44), "parent": "Neck2"},
            {"name": "Jaw", "head": (0.0, -0.84, 1.45), "tail": (0.0, -1.08, 1.33), "parent": "Skull"},
        ]
        for side, sx in (("L", 1.0), ("R", -1.0)):
            fore = [
                ("ForeShoulder", (0.145, -0.34, 0.96), (0.168, -0.28, 0.74)),
                ("ForeUpper", (0.168, -0.28, 0.74), (0.172, -0.32, 0.45)),
                ("Forearm", (0.172, -0.32, 0.45), (0.174, -0.31, 0.26)),
                ("ForeCannon", (0.174, -0.31, 0.26), (0.174, -0.30, 0.16)),
                ("ForeFetlock", (0.174, -0.30, 0.16), (0.176, -0.345, 0.088)),
                ("ForeHoof", (0.176, -0.345, 0.088), (0.176, -0.380, 0.008)),
            ]
            hind = [
                ("HindHaunch", (0.150, 0.39, 0.96), (0.175, 0.34, 0.72)),
                ("HindThigh", (0.175, 0.34, 0.72), (0.178, 0.48, 0.45)),
                ("HindGaskin", (0.178, 0.48, 0.45), (0.178, 0.45, 0.25)),
                ("HindCannon", (0.178, 0.45, 0.25), (0.178, 0.44, 0.16)),
                ("HindFetlock", (0.178, 0.44, 0.16), (0.178, 0.398, 0.088)),
                ("HindHoof", (0.178, 0.398, 0.088), (0.178, 0.365, 0.008)),
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

            # Compact, flush-tucked Pegasus wing arm (~1.09 m arc length ending right at croup y=+0.72!).
            # Hugs upper back cleanly at rest (ZERO jetpack overhang, ZERO pipe gap!), and sweeps
            # wide & high in UnicornBoom_Flight to |WingHand.tail.x| > 1.20 m!
            wing_entries = [
                ("WingScapula", (0.16, -0.34, 1.15), (0.22, -0.06, 1.24), "Withers"),
                ("WingHumerus", (0.22, -0.06, 1.24), (0.25, 0.22, 1.23), f"WingScapula.{side}"),
                ("WingRadius", (0.25, 0.22, 1.23), (0.24, 0.48, 1.20), f"WingHumerus.{side}"),
                ("WingHand", (0.24, 0.48, 1.20), (0.20, 0.72, 1.14), f"WingRadius.{side}"),
                ("WingCoverts", (0.20, -0.18, 1.21), (0.25, 0.22, 1.17), f"WingHumerus.{side}"),
                ("SecondaryFan", (0.25, 0.18, 1.22), (0.25, 0.54, 1.14), f"WingRadius.{side}"),
                ("PrimaryFan2", (0.24, 0.40, 1.20), (0.22, 0.72, 1.12), f"WingHand.{side}"),
                ("PrimaryFan1", (0.23, 0.48, 1.19), (0.20, 0.84, 1.14), f"WingHand.{side}"),
            ]
            for stem, head, tail, parent in wing_entries:
                bones.append({"name": f"{stem}.{side}",
                              "head": (sx * head[0], head[1], head[2]),
                              "tail": (sx * tail[0], tail[1], tail[2]),
                              "parent": parent})

        bones.extend([
            {"name": "ManeLock", "head": (0.0, -0.44, 1.26), "tail": (0.0, -0.66, 1.54), "parent": "Withers"},
            {"name": "ManeTuft", "head": (0.0, -0.76, 1.60), "tail": (0.0, -0.86, 1.74), "parent": "Skull"},
            {"name": "TailBase", "head": (0.0, 0.64, 1.09), "tail": (0.0, 0.84, 1.11), "parent": "Hips"},
            {"name": "TailEnd", "head": (0.0, 0.84, 1.11), "tail": (0.0, 1.04, 0.78), "parent": "TailBase"},
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
        ref = Vector((0.0, 0.0, 1.0)) if ("Wing" in item["name"] or "Fan" in item["name"]) \
            else Vector((0.0, -1.0, 0.0))
        eb.align_roll(ref)
        created[item["name"]] = eb
    bpy.ops.object.mode_set(mode="OBJECT")

    parts: list[tuple[Any, str]] = []
    multi_weights: dict[Any, dict[int, dict[str, float]]] = {}

    def bind(ob: Any, bone: str, wmap: dict[int, dict[str, float]] | None = None) -> Any:
        parts.append((ob, bone))
        if wmap is not None:
            multi_weights[ob] = wmap
        return ob

    # -------------------------------------------------------------- 1. Athletic, smooth, high-craft equine body & arched neck
    # 19 dense smoothly-graded stations with rounded 4-ring hemispherical rump dome (zero pointy butt,
    # zero dark seam above tail!), athletic tucked flank (not a pear/blimp!), deep muscular chest,
    # and thick arched Andalusian neck flowing seamlessly into the head/throatlatch!
    # Tuple: (y, z, rx, r_top, r_bot, pitch_deg, top_pinch, bot_full, furrow, weights)
    BODY_SPEC = [
        # Smooth convex hemispherical rounded buttocks dome (progressive gentle radii -> ZERO rear crease!)
        (0.66, 0.99, 0.068, 0.062, 0.062, 0.0, 0.00, 0.02, 0.00, {"Hips": 1.0}),
        (0.62, 1.00, 0.145, 0.124, 0.135, 0.0, 0.01, 0.05, 0.00, {"Hips": 1.0}),
        (0.55, 1.00, 0.218, 0.172, 0.186, 0.0, 0.02, 0.08, 0.00, {"Hips": 1.0}),
        (0.47, 1.00, 0.254, 0.194, 0.214, 0.0, 0.03, 0.11, 0.00, {"Hips": 0.94, "Spine": 0.06}),
        # Full rounded muscular croup / hindquarters descending smoothly to meet thigh (zero shelf!)
        (0.36, 0.99, 0.260, 0.200, 0.222, 0.0, 0.03, 0.11, 0.00, {"Hips": 0.78, "Spine": 0.22}),
        # Athletic tucked waist / flank + graceful concave saddle dip
        (0.18, 0.97, 0.240, 0.176, 0.196, 0.0, 0.03, 0.03, 0.00, {"Hips": 0.35, "Spine": 0.65}),
        (0.02, 0.96, 0.242, 0.178, 0.218, 1.0, 0.02, 0.05, 0.00, {"Spine": 0.85, "Chest": 0.15}),
        # Deep athletic ribcage / heart-girth (vertical oval, not a fat blimp!)
        (-0.14, 0.96, 0.260, 0.214, 0.242, 4.0, 0.04, 0.08, 0.00, {"Spine": 0.30, "Chest": 0.70}),
        (-0.28, 0.97, 0.268, 0.242, 0.256, 10.0, 0.07, 0.11, 0.01, {"Chest": 0.85, "Withers": 0.15}),
        # Broad muscular chest / prominent withers sweeping smoothly into proud brisket
        (-0.40, 1.00, 0.256, 0.252, 0.244, 20.0, 0.10, 0.10, 0.02, {"Chest": 0.70, "Withers": 0.30}),
        (-0.49, 1.07, 0.224, 0.240, 0.228, 34.0, 0.15, 0.08, 0.02, {"Chest": 0.35, "Withers": 0.65}),
        # Proud arched muscular horse neck (PERPENDICULAR positive pitch frames -> lush crested arch!)
        (-0.56, 1.19, 0.184, 0.214, 0.186, 46.0, 0.20, 0.05, 0.00, {"Withers": 0.65, "Neck1": 0.35}),
        (-0.63, 1.33, 0.156, 0.192, 0.154, 50.0, 0.24, 0.03, 0.00, {"Withers": 0.22, "Neck1": 0.78}),
        (-0.69, 1.45, 0.136, 0.168, 0.128, 44.0, 0.22, 0.01, 0.00, {"Neck1": 0.72, "Neck2": 0.28}),
        (-0.75, 1.53, 0.118, 0.136, 0.112, 26.0, 0.15, 0.00, 0.00, {"Neck1": 0.24, "Neck2": 0.76}),
        # Soft tapered poll tucked seamlessly INSIDE the head cavity (zero throatlatch crease!)
        (-0.79, 1.56, 0.104, 0.114, 0.104, 6.0, 0.08, 0.00, 0.00, {"Neck2": 0.55, "Skull": 0.45}),
        (-0.83, 1.55, 0.085, 0.092, 0.085, -10.0, 0.04, 0.00, 0.00, {"Neck2": 0.20, "Skull": 0.80}),
    ]

    def _body_shape_fn(rx: float, r_top: float, r_bot: float,
                       top_pinch: float, bot_full: float, furrow: float) -> Callable[[float], tuple[float, float]]:
        def _fn(ang: float) -> tuple[float, float]:
            ca, sa = math.cos(ang), math.sin(ang)
            rv = r_top if sa >= 0.0 else r_bot
            x_mod = 1.0 - top_pinch * max(0.0, sa) ** 1.6 + bot_full * max(0.0, -sa) ** 1.4 * (abs(ca) ** 0.7)
            v_mod = 1.0 - furrow * max(0.0, -sa) ** 2.2 * (1.0 - abs(ca))
            return ca * rx * x_mod, sa * rv * v_mod
        return _fn

    u_x = Vector((1.0, 0.0, 0.0))
    body_stations = []
    body_w = []
    for py, pz, rx, rzt, rzb, p_deg, t_pinch, b_full, furrow, bw in BODY_SPEC:
        pr = math.radians(p_deg)
        v_ax = Vector((0.0, math.sin(pr), math.cos(pr)))
        body_stations.append((Vector((0.0, py, pz)), u_x, v_ax,
                              _body_shape_fn(rx, rzt, rzb, t_pinch, b_full, furrow)))
        body_w.append(bw)
    body_ob, body_wmap = loft_sculpted(
        "EquineBody", body_stations, coat, seg=18, weights_per_station=body_w,
        cap_start_offset=Vector((0.0, 0.014, 0.0)),
        cap_end_offset=Vector((0.0, -0.015, 0.0)),
    )
    bind(body_ob, "Spine", body_wmap)

    # -------------------------------------------------------------- 2. Noble sculpted equine head, deeply recessed eyes, sculpted eyelids/muzzle & helical golden horn
    # Station: (y, z, rx, r_top, r_bot, pitch_deg, jowl, brow_pinch, eye_recess, nostril_flare)
    HEAD_SPEC = [
        (-0.73, 1.56, 0.092, 0.100, 0.094, -8.0, 0.04, 0.06, 0.00, 0.00),
        (-0.79, 1.57, 0.120, 0.122, 0.126, -20.0, 0.15, 0.04, 0.00, 0.00),
        # Rounded horse jowl/cheekbone curving smoothly over throatlatch
        (-0.86, 1.53, 0.125, 0.118, 0.144, -32.0, 0.20, 0.00, 0.00, 0.00),
        # Sculpted forehead + deeper orbital socket recess so eyes stay 100% INSIDE cheek profile!
        (-0.93, 1.49, 0.112, 0.108, 0.112, -40.0, 0.08, -0.08, 0.20, 0.00),
        (-0.99, 1.44, 0.090, 0.088, 0.088, -42.0, 0.02, 0.04, 0.08, 0.00),
        # Graceful slightly dished Arabian nasal bridge
        (-1.06, 1.38, 0.072, 0.070, 0.073, -42.0, 0.00, 0.08, 0.00, 0.00),
        # Flared sculptural nostril wings & soft muzzle
        (-1.13, 1.33, 0.071, 0.068, 0.067, -38.0, 0.04, 0.04, 0.00, 0.12),
        (-1.185, 1.298, 0.056, 0.052, 0.050, -30.0, 0.00, 0.00, 0.00, 0.00),
    ]

    def _head_shape_fn(rx: float, rt: float, rb: float,
                       jowl: float, brow: float, recess: float,
                       n_flare: float) -> Callable[[float], tuple[float, float]]:
        def _fn(ang: float) -> tuple[float, float]:
            ca, sa = math.cos(ang), math.sin(ang)
            rv = rt if sa >= 0.0 else rb
            x_mod = 1.0 + jowl * max(0.0, -sa) * (abs(ca) ** 0.8) - brow * max(0.0, sa) ** 1.5
            eye_bell = math.exp(-((sa - 0.28) ** 2) / 0.065) * (abs(ca) ** 2.2)
            x_mod -= recess * eye_bell
            # Sculpted flared upper-side nostril wings
            nostril_bell = math.exp(-((sa - 0.18) ** 2) / 0.08) * (abs(ca) ** 2.0)
            x_mod += n_flare * nostril_bell
            v_mod = 1.0 - 0.05 * max(0.0, sa) ** 3.0
            return ca * rx * x_mod, sa * rv * v_mod
        return _fn

    head_stations = []
    for py, pz, rx, rzt, rzb, p_deg, jowl, brow, recess, n_flare in HEAD_SPEC:
        pr = math.radians(p_deg)
        v_ax = Vector((0.0, math.sin(pr), math.cos(pr)))
        head_stations.append((Vector((0.0, py, pz)), u_x, v_ax,
                              _head_shape_fn(rx, rzt, rzb, jowl, brow, recess, n_flare)))
    head_ob, _ = loft_sculpted(
        "EquineHead", head_stations, coat, seg=14,
        cap_start_offset=Vector((0.0, 0.018, 0.0)),
        cap_end_offset=Vector((0.0, -0.014, -0.005)),
    )
    bind(head_ob, "Skull")

    # Flush blended soft velvet muzzle cap + subtle mouth contour
    bind(sphere("MuzzleVelvetTip", (0.0, -1.178, 1.298), (0.056, 0.036, 0.048),
                muzzle_mat, 10, 6, rot=(math.radians(-30), 0, 0)), "Skull")

    for side, sx in (("L", 1.0), ("R", -1.0)):
        # Sculpted dark teardrop nostril tucked cleanly into flared nostril wing
        bind(sphere(f"Nostril_{side}", (sx * 0.048, -1.142, 1.326), (0.011, 0.022, 0.014),
                    dark_detail, 8, 5, rot=(math.radians(-26), 0.0, sx * math.radians(26))), "Skull")

        # Expressive enlarged sapphire eyes (tucked inside cheek silhouette, vivid in side/iso!)
        bind(sphere(f"Eye_{side}", (sx * 0.086, -0.930, 1.515), (0.024, 0.046, 0.040),
                    eye_blue, 10, 6, rot=(math.radians(-10), 0.0, sx * math.radians(22))), "Skull")
        bind(sphere(f"Pupil_{side}", (sx * 0.100, -0.942, 1.516), (0.013, 0.025, 0.027),
                    dark_detail, 8, 5, rot=(math.radians(-10), 0.0, sx * math.radians(22))), "Skull")
        bind(sphere(f"EyeGlint_{side}", (sx * 0.110, -0.951, 1.531), (0.007, 0.009, 0.008),
                    coat, 6, 4), "Skull")
        # Sculpted upper pearl brow eyelid + dark arched lash line cradling the recessed eye
        lid_pts = [
            Vector((sx * 0.086, -0.892, 1.533)),
            Vector((sx * 0.104, -0.932, 1.552)),
            Vector((sx * 0.090, -0.971, 1.524)),
        ]
        bind(hair_ribbon(f"EyelidUpper_{side}", lid_pts, 0.017, 0.011, coat, samples=5, seg=4,
                         hint=Vector((0, 0, 1))), "Skull")
        lash_pts = [
            Vector((sx * 0.087, -0.895, 1.527)),
            Vector((sx * 0.103, -0.934, 1.545)),
            Vector((sx * 0.090, -0.971, 1.520)),
        ]
        bind(hair_ribbon(f"Eyelash_{side}", lash_pts, 0.015, 0.008, dark_detail, samples=5, seg=4,
                         hint=Vector((0, 0, 1))), "Skull")

        # Sculpted cupped curved horse ears
        ear_ctrl = [
            Vector((sx * 0.068, -0.795, 1.635)),
            Vector((sx * 0.088, -0.810, 1.712)),
            Vector((sx * 0.084, -0.838, 1.788)),
            Vector((sx * 0.072, -0.858, 1.828)),
        ]
        bind(hair_ribbon(f"Ear_{side}", ear_ctrl, 0.036, 0.018, coat, samples=6, seg=6,
                         twist_rad=sx * -0.22, hint=Vector((sx * 0.35, -0.94, 0.0))), "Skull")
        ear_in_ctrl = [
            Vector((sx * 0.070, -0.806, 1.652)),
            Vector((sx * 0.084, -0.822, 1.720)),
            Vector((sx * 0.078, -0.844, 1.780)),
        ]
        bind(hair_ribbon(f"EarInner_{side}", ear_in_ctrl, 0.020, 0.007, ear_inner_mat, samples=5, seg=4,
                         twist_rad=sx * -0.20, hint=Vector((sx * 0.35, -0.94, 0.0))), "Skull")

    # TRUE continuous helically-fluted golden spiral horn tapering seamlessly to glowing razor tip!
    horn_base = Vector((0.0, -0.865, 1.615))
    horn_tip = Vector((0.0, -1.255, 2.020))
    horn_vec = horn_tip - horn_base
    horn_axis = horn_vec.normalized()
    h_u, h_v = _orthonormal_frame(horn_axis, Vector((1.0, 0.0, 0.0)))

    def _build_spiral_horn_part(name: str, t_start: float, t_end: float,
                                n_rings: int, seg: int, material: Any,
                                r_base: float = 0.044, flutes: int = 3, turns: float = 4.6) -> Any:
        bm = bmesh.new()
        rings: list[list[Any]] = []
        for i in range(n_rings):
            u = i / max(1, n_rings - 1)
            t = t_start + (t_end - t_start) * u
            c = horn_base + horn_vec * t
            r_nom = r_base * max(0.032, (1.0 - t) ** 0.88)
            flute_amp = 0.24 * (1.0 - 0.35 * t)
            ring = []
            for j in range(seg):
                ang = 2.0 * math.pi * j / seg
                r = r_nom * (1.0 + flute_amp * math.cos(flutes * ang - 2.0 * math.pi * turns * t))
                ring.append(bm.verts.new(c + h_u * (math.cos(ang) * r) + h_v * (math.sin(ang) * r)))
            rings.append(ring)
        for i in range(n_rings - 1):
            for j in range(seg):
                jn = (j + 1) % seg
                bm.faces.new((rings[i][j], rings[i][jn], rings[i + 1][jn], rings[i + 1][j]))
        c0 = bm.verts.new(horn_base + horn_vec * (t_start - 0.004))
        c1 = bm.verts.new(horn_base + horn_vec * min(1.015, t_end + (0.015 if t_end >= 0.99 else 0.004)))
        for j in range(seg):
            jn = (j + 1) % seg
            bm.faces.new((c0, rings[0][jn], rings[0][j]))
            bm.faces.new((c1, rings[-1][j], rings[-1][jn]))
        return finalize_bmesh(name, bm, material)

    bind(_build_spiral_horn_part("HornBase", -0.02, 0.06, 4, 10, gold, r_base=0.052, flutes=6, turns=0.5), "Skull")
    bind(_build_spiral_horn_part("HornShaft", 0.04, 0.82, 15, 12, gold, r_base=0.044, flutes=3, turns=4.6), "Skull")
    bind(_build_spiral_horn_part("HornTip", 0.80, 1.00, 5, 12, horn_glow, r_base=0.044, flutes=3, turns=4.6), "Skull")
    for side, sx in (("L", 1.0), ("R", -1.0)):
        bind(sphere(f"HornMuzzle_{side}", (sx * 0.032, -0.885, 1.635),
                    (0.008, 0.008, 0.008), horn_glow, 6, 4), "Skull")

    # -------------------------------------------------------------- 3. Tangent-blended muscular equine legs, golden hooves & plush fetlock tufts
    # Key AAA fix: upper shoulder & haunch curve TANGENTIALLY up along the athletic torso flanks
    # (outer wall matches body flank curvature seamlessly — ZERO flat peg-leg top caps poking out!).
    v_fwd = Vector((0.0, -1.0, 0.0))

    def _leg_shape_fn(rx: float, r_fwd: float, r_back: float,
                      outer_flat: float = 0.0, side_sign: float = 1.0) -> Callable[[float], tuple[float, float]]:
        def _fn(ang: float) -> tuple[float, float]:
            ca, sa = math.cos(ang), math.sin(ang)
            ry = r_fwd if sa >= 0.0 else r_back
            # Optional gentle flattening on the inner side so upper shoulder/thigh hugs the torso seamlessly
            x_scale = 1.0 - outer_flat * max(0.0, -ca * side_sign)
            return ca * rx * x_scale, sa * ry
        return _fn

    for side, sx in (("L", 1.0), ("R", -1.0)):
        # FORELEG: 13 smooth anatomical stations tucked INSIDE chest envelope at z=0.82..1.05 (ZERO protruding shelf!)
        fore_stations_spec = [
            (Vector((sx * 0.115, -0.32, 1.05)), 0.030, 0.072, 0.070, {"Chest": 0.94, f"ForeShoulder.{side}": 0.06}),
            (Vector((sx * 0.142, -0.32, 0.96)), 0.072, 0.112, 0.102, {"Chest": 0.72, f"ForeShoulder.{side}": 0.28}),
            (Vector((sx * 0.154, -0.315, 0.87)), 0.076, 0.118, 0.106, {"Chest": 0.40, f"ForeShoulder.{side}": 0.56, f"ForeUpper.{side}": 0.04}),
            (Vector((sx * 0.162, -0.305, 0.78)), 0.070, 0.104, 0.094, {"Chest": 0.14, f"ForeShoulder.{side}": 0.68, f"ForeUpper.{side}": 0.18}),
            (Vector((sx * 0.167, -0.292, 0.68)), 0.056, 0.082, 0.078, {f"ForeShoulder.{side}": 0.26, f"ForeUpper.{side}": 0.74}),
            (Vector((sx * 0.172, -0.305, 0.57)), 0.048, 0.060, 0.058, {f"ForeUpper.{side}": 0.88, f"Forearm.{side}": 0.12}),
            (Vector((sx * 0.173, -0.318, 0.46)), 0.042, 0.047, 0.046, {f"ForeUpper.{side}": 0.45, f"Forearm.{side}": 0.55}),
            (Vector((sx * 0.174, -0.314, 0.35)), 0.035, 0.040, 0.041, {f"Forearm.{side}": 0.86, f"ForeCannon.{side}": 0.14}),
            (Vector((sx * 0.174, -0.308, 0.25)), 0.032, 0.036, 0.037, {f"Forearm.{side}": 0.45, f"ForeCannon.{side}": 0.55}),
            (Vector((sx * 0.174, -0.305, 0.175)), 0.034, 0.037, 0.044, {f"ForeCannon.{side}": 0.62, f"ForeFetlock.{side}": 0.38}),
            (Vector((sx * 0.175, -0.320, 0.130)), 0.035, 0.038, 0.042, {f"ForeCannon.{side}": 0.22, f"ForeFetlock.{side}": 0.78}),
            (Vector((sx * 0.176, -0.345, 0.088)), 0.033, 0.037, 0.035, {f"ForeFetlock.{side}": 0.75, f"ForeHoof.{side}": 0.25}),
            (Vector((sx * 0.176, -0.358, 0.058)), 0.035, 0.039, 0.036, {f"ForeFetlock.{side}": 0.35, f"ForeHoof.{side}": 0.65}),
        ]
        f_st = [(c, u_x, v_fwd, _leg_shape_fn(rx, rf, rb, 0.28 if idx < 4 else 0.0, sx))
                for idx, (c, rx, rf, rb, _) in enumerate(fore_stations_spec)]
        f_w = [bw for _, _, _, _, bw in fore_stations_spec]
        f_ob, f_wmap = loft_sculpted(
            f"LegChain_F{side}", f_st, coat, seg=12, weights_per_station=f_w,
            cap_start_offset=Vector((-sx * 0.02, 0.0, 0.02)),
        )
        bind(f_ob, f"ForeShoulder.{side}", f_wmap)

        # HINDLEG: 13 smooth anatomical stations tucked INSIDE deepened croup envelope (ZERO shelf under LeaBrand!)
        hind_stations_spec = [
            (Vector((sx * 0.112, 0.40, 1.04)), 0.032, 0.078, 0.078, {"Hips": 0.95, f"HindHaunch.{side}": 0.05}),
            (Vector((sx * 0.142, 0.395, 0.95)), 0.074, 0.124, 0.118, {"Hips": 0.74, f"HindHaunch.{side}": 0.26}),
            (Vector((sx * 0.154, 0.382, 0.86)), 0.080, 0.134, 0.124, {"Hips": 0.42, f"HindHaunch.{side}": 0.54, f"HindThigh.{side}": 0.04}),
            (Vector((sx * 0.164, 0.368, 0.77)), 0.072, 0.116, 0.108, {"Hips": 0.14, f"HindHaunch.{side}": 0.68, f"HindThigh.{side}": 0.18}),
            (Vector((sx * 0.169, 0.362, 0.67)), 0.058, 0.092, 0.086, {f"HindHaunch.{side}": 0.28, f"HindThigh.{side}": 0.72}),
            (Vector((sx * 0.175, 0.415, 0.55)), 0.049, 0.068, 0.074, {f"HindThigh.{side}": 0.86, f"HindGaskin.{side}": 0.14}),
            (Vector((sx * 0.178, 0.476, 0.44)), 0.042, 0.046, 0.058, {f"HindThigh.{side}": 0.42, f"HindGaskin.{side}": 0.58}),
            (Vector((sx * 0.178, 0.464, 0.34)), 0.036, 0.041, 0.048, {f"HindGaskin.{side}": 0.86, f"HindCannon.{side}": 0.14}),
            (Vector((sx * 0.178, 0.448, 0.24)), 0.032, 0.037, 0.039, {f"HindGaskin.{side}": 0.42, f"HindCannon.{side}": 0.58}),
            (Vector((sx * 0.178, 0.438, 0.175)), 0.035, 0.037, 0.045, {f"HindCannon.{side}": 0.62, f"HindFetlock.{side}": 0.38}),
            (Vector((sx * 0.178, 0.418, 0.128)), 0.035, 0.038, 0.042, {f"HindCannon.{side}": 0.22, f"HindFetlock.{side}": 0.78}),
            (Vector((sx * 0.178, 0.398, 0.088)), 0.034, 0.038, 0.036, {f"HindFetlock.{side}": 0.75, f"HindHoof.{side}": 0.25}),
            (Vector((sx * 0.178, 0.382, 0.058)), 0.036, 0.040, 0.037, {f"HindFetlock.{side}": 0.35, f"HindHoof.{side}": 0.65}),
        ]
        h_st = [(c, u_x, v_fwd, _leg_shape_fn(rx, rf, rb, 0.28 if idx < 4 else 0.0, sx))
                for idx, (c, rx, rf, rb, _) in enumerate(hind_stations_spec)]
        h_w = [bw for _, _, _, _, bw in hind_stations_spec]
        h_ob, h_wmap = loft_sculpted(
            f"LegChain_R{side}", h_st, coat, seg=12, weights_per_station=h_w,
            cap_start_offset=Vector((-sx * 0.02, 0.0, 0.02)),
        )
        bind(h_ob, f"HindHaunch.{side}", h_wmap)

        # Sculpted flared golden hooves + lush curved fetlock feather tufts hugging the pastern!
        for tag, hx, hy_top, hy_sole, hoof_bone, fet_bone in (
            ("F", sx * 0.176, -0.345, -0.375, f"ForeHoof.{side}", f"ForeFetlock.{side}"),
            ("R", sx * 0.178, 0.398, 0.365, f"HindHoof.{side}", f"HindFetlock.{side}"),
        ):
            hoof_stations = [
                (Vector((hx, hy_top, 0.095)), u_x, v_fwd, _leg_shape_fn(0.037, 0.043, 0.037)),
                (Vector((hx, hy_top + (hy_sole - hy_top) * 0.35, 0.068)), u_x, v_fwd, _leg_shape_fn(0.042, 0.051, 0.039)),
                (Vector((hx, hy_sole, 0.008)), u_x, v_fwd, _leg_shape_fn(0.050, 0.062, 0.044)),
                (Vector((hx, hy_sole + 0.002, 0.000)), u_x, v_fwd, _leg_shape_fn(0.044, 0.054, 0.038)),
            ]
            hoof_ob, _ = loft_sculpted(f"Hoof_{tag}{side}", hoof_stations, hoof_gold, seg=10)
            bind(hoof_ob, hoof_bone)

            # Plush, fuller curved fetlock plume hugging the back of the ankle & sweeping softly around the heel!
            f_root = Vector((hx, hy_top + 0.036, 0.220))
            for li, (dx, dy_mid, dy_tip, z_mid, z_tip, w_tuft, fmat) in enumerate((
                (0.000, 0.034, 0.072, 0.120, 0.046, 0.046, mane_lav),
                (sx * 0.022, 0.028, 0.060, 0.132, 0.068, 0.036, mane_pink),
                (-sx * 0.020, 0.026, 0.056, 0.136, 0.074, 0.034, mane_cyan),
            )):
                ctrl = [
                    f_root + Vector((dx * 0.15, -0.015, 0.020)),
                    Vector((hx + dx * 0.65, hy_top + 0.036 + dy_mid * 0.65, z_mid)),
                    Vector((hx + dx * 0.95, hy_top + 0.036 + dy_tip * 0.85, (z_mid + z_tip) * 0.46)),
                    Vector((hx + dx * 1.05, hy_top + 0.036 + dy_tip, z_tip)),
                ]
                bind(hair_ribbon(f"FetlockFeather_{tag}{side}_{li}", ctrl, w_tuft, w_tuft * 0.50, fmat,
                                 samples=6, seg=5, hint=Vector((sx, 0, 0))), fet_bone)

    # -------------------------------------------------------------- 4. Angelic multi-layered Pegasus wings
    # CLOSED at rest: compact, sleek swan mantle hugging the upper back & ending neatly around the croup
    # (NO jet-pack overhang past butt, NO bare white pipe gap, 100% above LeaBrand!).
    # OPEN in UnicornBoom_Flight: cohesive soaring fan of 39 overlapping tapered feathers per wing!
    for side, sx in (("L", 1.0), ("R", -1.0)):
        # Low-profile cyan leading edge blends into the layered feather fan.
        arm_spec = [
            (Vector((sx * 0.12, -0.32, 1.13)), 0.034, 0.038, {"Withers": 0.45, f"WingScapula.{side}": 0.55}),
            (Vector((sx * 0.18, -0.14, 1.20)), 0.026, 0.028, {f"WingScapula.{side}": 0.65, f"WingHumerus.{side}": 0.35}),
            (Vector((sx * 0.22, 0.06, 1.21)), 0.022, 0.024, {f"WingHumerus.{side}": 1.0}),
            (Vector((sx * 0.23, 0.22, 1.21)), 0.020, 0.022, {f"WingHumerus.{side}": 0.50, f"WingRadius.{side}": 0.50}),
            (Vector((sx * 0.23, 0.36, 1.20)), 0.017, 0.019, {f"WingRadius.{side}": 1.0}),
            (Vector((sx * 0.22, 0.48, 1.19)), 0.015, 0.016, {f"WingRadius.{side}": 0.50, f"WingHand.{side}": 0.50}),
            (Vector((sx * 0.21, 0.60, 1.17)), 0.012, 0.013, {f"WingHand.{side}": 1.0}),
            (Vector((sx * 0.19, 0.72, 1.14)), 0.008, 0.009, {f"WingHand.{side}": 1.0}),
        ]
        arm_pts = [p for p, _, _, _ in arm_spec]
        arm_frames = _parallel_frames(arm_pts, Vector((0, 0, 1)))
        arm_stations = []
        arm_w = []
        for idx, (pt, rx, rz, bw) in enumerate(arm_spec):
            _, u_a, v_a = arm_frames[idx]
            arm_stations.append((pt, u_a, v_a, _leg_shape_fn(rx, rz, rz)))
            arm_w.append(bw)
        wing_arm_ob, wing_arm_wmap = loft_sculpted(
            f"Wing_{side}", arm_stations, feather_cyan, seg=8, weights_per_station=arm_w
        )
        bind(wing_arm_ob, f"WingHand.{side}", wing_arm_wmap)

        out_n = Vector((sx * 0.92, 0.0, 0.38)).normalized()

        # Row 1: Plush Overlapping Shoulder & Leading-Edge Coverts (10 scalloped feathers directly cloaking the wing bar!)
        for i in range(10):
            u = i / 9.0
            root = Vector((sx * (0.15 + 0.095 * u), -0.25 + u * 0.47, 1.215 + 0.045 * math.sin(u * math.pi)))
            length = 0.26 + 0.09 * math.sin(u * math.pi * 0.85)
            lat = sx * (0.026 + 0.008 * (i % 2))
            drop = 0.065 + 0.015 * (1.0 - u)
            mid = root + Vector((lat * 1.15, length * 0.52, drop * 0.40))
            tip = root + Vector((lat * 0.55, length, drop))
            mat = feather_pearl if i < 7 else feather_cyan
            bind(feather_blade(f"Covert_{side}_{i:02d}", root, mid, tip,
                               width=0.105, thickness=0.016, blade_normal=out_n,
                               material=mat, n_stations=4),
                 f"WingCoverts.{side}")

        # Row 2: Slender Overlapping Secondaries (8 graceful curved feathers on SecondaryFan, clear above LeaBrand!)
        for i in range(8):
            u = i / 7.0
            root = Vector((sx * (0.252 - 0.012 * u), 0.16 + u * 0.32, 1.235 - 0.028 * u))
            length = 0.34 + 0.08 * u
            drop = -0.120 + 0.040 * u
            lat = sx * (0.024 - 0.018 * u + 0.006 * (i % 2))
            mid = root + Vector((lat * 1.2, length * 0.52, drop * 0.45))
            tip = root + Vector((lat * 0.4 - sx * 0.018 * u, length, drop))
            mat = (feather_cyan, feather_cyan, feather_cyan, feather_lav, feather_lav, feather_pink, feather_pink, feather_pink)[i]
            bind(feather_blade(f"Secondary_{side}_{i:02d}", root, mid, tip,
                               width=0.087, thickness=0.014, blade_normal=out_n,
                               material=mat, n_stations=5),
                 f"SecondaryFan.{side}")

        # Inner tertials bridge the exposed leading edge into a broad, layered fan.
        # These reuse existing PrimaryFan2 bones/materials, so they add surface area
        # without adding draw calls or changing any runtime landmark.
        root_mats = (feather_cyan, feather_cyan, feather_lav,
                     feather_lav, feather_pink, feather_pink)
        for i, mat in enumerate(root_mats):
            u = i / 5.0
            root = Vector((sx * (0.145 + 0.080 * u), -0.20 + u * 0.42,
                           1.225 + 0.022 * math.sin(u * math.pi)))
            length = 0.31 + 0.06 * u
            drop = 0.045 + 0.025 * u
            lat = sx * (0.028 + 0.006 * (i % 2))
            mid = root + Vector((lat * 1.05, length * 0.52, drop * 0.45))
            tip = root + Vector((lat * 0.45 - sx * 0.012 * u, length, drop))
            bind(feather_blade(f"PrimaryRoot_{side}_{i:02d}", root, mid, tip,
                               width=0.078, thickness=0.013, blade_normal=out_n,
                               material=mat, n_stations=5),
                 f"PrimaryFan2.{side}")

        # Row 3: Slender Inner Primaries (7 arched feathers on PrimaryFan2 bridging cleanly with ZERO gap!)
        for i in range(7):
            u = i / 6.0
            root = Vector((sx * (0.244 - 0.020 * u), 0.38 + u * 0.24, 1.210 - 0.036 * u))
            length = 0.36 + 0.09 * u
            drop = -0.125 + 0.090 * u
            lat = sx * (0.016 - 0.016 * u + 0.006 * (i % 2))
            mid = root + Vector((lat * 1.1, length * 0.52, drop * 0.45))
            tip = root + Vector((lat * 0.2 - sx * 0.025 * u, length, drop))
            mat = (feather_cyan, feather_lav, feather_lav, feather_pink, feather_pink, feather_pink, feather_lav)[i]
            bind(feather_blade(f"PrimaryInner_{side}_{i:02d}", root, mid, tip,
                               width=0.082, thickness=0.013, blade_normal=out_n,
                               material=mat, n_stations=5),
                 f"PrimaryFan2.{side}")

        # Row 4: Slender Sweeping Angelic Outer Primaries (8 staggered tapered flight feathers on PrimaryFan1!)
        for i in range(8):
            u = i / 7.0
            root = Vector((sx * (0.236 - 0.034 * u), 0.48 + u * 0.24, 1.198 - 0.052 * u))
            length = 0.30 + 0.16 * math.sin((0.15 + 0.78 * u) * math.pi)
            drop = -0.110 + 0.120 * u
            lat = sx * (0.012 - 0.022 * u + 0.007 * (i % 2))
            mid = root + Vector((lat * 1.1, length * 0.54, drop * 0.42))
            tip = root + Vector((-sx * (0.015 + 0.030 * u), length, drop + 0.024 * u))
            mat = (feather_pink, feather_pink, feather_lav, feather_lav, feather_cyan, feather_cyan, feather_gold, feather_gold)[i]
            bind(feather_blade(f"PrimaryOuter_{side}_{i:02d}", root, mid, tip,
                               width=0.072, thickness=0.012, blade_normal=out_n,
                               material=mat, n_stations=5),
                 f"PrimaryFan1.{side}")

    # -------------------------------------------------------------- 5. Lush sculptural S-curved flowing mane & sweeping tail
    # Romantic curled forelock landmark sweeping across crown & framing left temple cleanly behind eye!
    bind(hair_ribbon(
        "ManeForelock",
        [
            Vector((0.00, -0.78, 1.65)),
            Vector((0.054, -0.85, 1.68)),
            Vector((0.110, -0.89, 1.62)),
            Vector((0.128, -0.89, 1.52)),
            Vector((0.112, -0.87, 1.43)),
        ],
        width_base=0.058, thick_base=0.028, material=mane_pink, samples=7, seg=6,
        twist_rad=0.40, hint=Vector((1, 0, 0)),
    ), "ManeTuft")

    bind(hair_ribbon(
        "ManeForelock_R",
        [
            Vector((0.00, -0.79, 1.65)),
            Vector((-0.050, -0.85, 1.66)),
            Vector((-0.102, -0.89, 1.59)),
            Vector((-0.106, -0.88, 1.50)),
        ],
            width_base=0.040, thick_base=0.021, material=mane_lav, samples=5, seg=5,
        twist_rad=-0.35, hint=Vector((-1, 0, 0)),
    ), "ManeTuft")

    # 10 lush flowing S-wave mane locks cascading cleanly outside the arched neck & shoulder (zero belly poke!)
    mane_mats = (mane_pink, mane_lav, mane_pink, mane_cyan, mane_pink, mane_lav)
    for i in range(10):
        u = i / 9.0
        y0 = -0.75 + u * 0.36
        z0 = 1.65 - u * 0.34 + 0.075 * math.sin(u * math.pi)
        side_x = 1.0 if i % 4 != 3 else -0.70
        wave = math.sin(u * 4.5 + i * 0.65)
        c0 = Vector((side_x * 0.016, y0, z0))
        c1 = Vector((side_x * (0.128 + 0.022 * wave), y0 + 0.05, z0 - 0.04))
        c2 = Vector((side_x * (0.205 + 0.030 * math.cos(u * 3.8)), y0 + 0.12, z0 - 0.16))
        c3 = Vector((side_x * (0.210 + 0.034 * wave), y0 + 0.18, z0 - 0.28 - 0.04 * u))
        c4 = Vector((side_x * (0.245 + 0.025 * wave), y0 + 0.24, z0 - 0.34 - 0.05 * u))
        bone = "ManeTuft" if i < 3 else "ManeLock"
        bind(hair_ribbon(
            f"ManeStrand_{i:02d}", [c0, c1, c2, c3, c4],
            width_base=0.072 if side_x > 0 else 0.052,
            thick_base=0.031 if side_x > 0 else 0.024,
            material=mane_mats[i % len(mane_mats)],
            samples=7, seg=5, twist_rad=side_x * 0.46, hint=Vector((side_x, 0, 0)),
        ), bone)

    # Voluptuous sweeping S-curved arched tail fountain (dock tucked seamlessly inside rounded rump dome!)
    bind(hair_ribbon(
        "TailRoot",
        [
            Vector((0.0, 0.50, 1.05)),
            Vector((0.0, 0.70, 1.11)),
            Vector((0.0, 0.94, 1.01)),
            Vector((0.0, 1.06, 0.72)),
            Vector((0.0, 1.22, 0.42)),
        ],
        width_base=0.084, thick_base=0.054, material=mane_lav, samples=10, seg=10,
        hint=Vector((1, 0, 0)),
    ), "TailBase")

    for i in range(8):
        u = (i / 7.0) * 2.0 - 1.0
        layer = i % 3
        spread_x = u * (0.074 + 0.025 * layer)
        arch_z = 1.12 + 0.032 * (1.0 - abs(u)) - 0.022 * layer
        c0 = Vector((spread_x * 0.12, 0.58, 1.06 - 0.015 * layer))
        c1 = Vector((spread_x * 0.52, 0.81 + 0.02 * layer, arch_z))
        c2 = Vector((spread_x * 0.90 + 0.020 * math.sin(i * 1.4), 1.00 + 0.04 * layer, 0.93 - 0.04 * layer))
        c3 = Vector((spread_x * 0.80 - 0.025 * math.sin(i * 1.4), 1.09 + 0.06 * layer, 0.64 - 0.05 * layer))
        c4 = Vector((spread_x * 1.12 + 0.034 * math.cos(i * 1.1), 1.28 + 0.10 * layer, 0.36 - 0.04 * layer))
        bone = "TailBase" if i < 4 else "TailEnd"
        bind(hair_ribbon(
            f"TailStrand_{i:02d}", [c0, c1, c2, c3, c4],
            width_base=0.072, thick_base=0.032,
            material=mane_mats[i % len(mane_mats)],
            samples=7, seg=5, twist_rad=u * 0.40, hint=Vector((1, 0, 0)),
        ), bone)

    # -------------------------------------------------------------- 6. BOLD, CRISP, UNOBSTRUCTED "Lea" brand on right (-X) butt cheek
    LB_NU, LB_NV = 10, 6
    bm_lb = bmesh.new()
    uv_lb = bm_lb.loops.layers.uv.new("UVMap")
    lb_out_grid: list[list[Any]] = []
    lb_in_grid: list[list[Any]] = []

    _CROUP_STATIONS = BODY_SPEC[2:6]  # y = 0.55, 0.47, 0.36, 0.18

    def _croup_pt(u_c: float, v_c: float, offset_m: float) -> Vector:
        y = 0.52 - u_c * 0.30
        s_a, s_b = _CROUP_STATIONS[0], _CROUP_STATIONS[1]
        for k in range(len(_CROUP_STATIONS) - 1):
            if _CROUP_STATIONS[k][0] >= y >= _CROUP_STATIONS[k + 1][0]:
                s_a, s_b = _CROUP_STATIONS[k], _CROUP_STATIONS[k + 1]
                break
        f = max(0.0, min(1.0, (s_a[0] - y) / max(1e-6, s_a[0] - s_b[0])))
        zc = s_a[1] + (s_b[1] - s_a[1]) * f
        rx = s_a[2] + (s_b[2] - s_a[2]) * f
        rzt = s_a[3] + (s_b[3] - s_a[3]) * f
        rzb = s_a[4] + (s_b[4] - s_a[4]) * f
        t_pinch = s_a[6] + (s_b[6] - s_a[6]) * f
        b_full = s_a[7] + (s_b[7] - s_a[7]) * f
        # Centered cleanly on the rounded right butt cheek: above thigh blend, below folded wing!
        phi = math.radians(-30.0 + v_c * 66.0)
        ang = math.pi - phi
        dx, dz = _body_shape_fn(rx, rzt, rzb, t_pinch, b_full, 0.0)(ang)
        nx, nz = -math.cos(phi), math.sin(phi)
        n_len = math.hypot(nx, nz)
        return Vector((dx + offset_m * (nx / n_len), y, zc + dz + offset_m * (nz / n_len)))

    for j in range(LB_NV + 1):
        v_c = j / float(LB_NV)
        orow: list[Any] = []
        irow: list[Any] = []
        for i in range(LB_NU + 1):
            u_c = i / float(LB_NU)
            vo = bm_lb.verts.new(_croup_pt(u_c, v_c, 0.0055))
            vi = bm_lb.verts.new(_croup_pt(u_c, v_c, -0.0045))
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

    lb_ob = finalize_bmesh("LeaBrand", bm_lb, lea_brand_mat)
    bind(lb_ob, "Hips")

    # -------------------------------------------------------------- skin binding (multi-bone + rigid)
    for ob, bone_name in parts:
        if ob in multi_weights:
            w_by_bone: dict[str, list[tuple[int, float]]] = defaultdict(list)
            for vi, bmap in multi_weights[ob].items():
                assert vi >= 0, f"Invalid negative vertex index in multi_weights for {ob.name}"
                for bname, wval in bmap.items():
                    w_by_bone[bname].append((vi, wval))
            for bname, entries in w_by_bone.items():
                vg = ob.vertex_groups.new(name=bname)
                for vi, wval in entries:
                    vg.add([vi], wval, "REPLACE")
        else:
            vg = ob.vertex_groups.new(name=bone_name)
            vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
        ob.parent = arm
        mod = ob.modifiers.new(name="LeaSkin", type="ARMATURE")
        mod.object = arm
        mod.use_vertex_groups = True
        mod.use_bone_envelopes = False

    # -------------------------------------------------------------- batch by bone + material
    KEEP_SEPARATE = LANDMARKS | {"EquineBody", "EquineHead", "LegChain_FL", "LegChain_FR", "LegChain_RL", "LegChain_RR"}
    batches: dict[tuple[str, str], list[Any]] = defaultdict(list)
    merged: list[tuple[Any, str]] = []
    for ob, bone_name in parts:
        if ob.name in KEEP_SEPARATE or ob in multi_weights:
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

    def _wing_fold(pb: Any, open_amount: float = 0.0, flap: float = 0.0) -> None:
        """Rest pose is CLOSED/FOLDED compactly along upper back above LeaBrand.
        open_amount=0 keeps wings strictly CLOSED; open_amount=1 unfolds the soaring
        angelic span (>1.18 m hand reach!) with ONE seamless continuous fan of slender feathers!"""
        for side in ("L", "R"):
            sign = 1.0 if side == "L" else -1.0
            out = open_amount
            # Heroic wide & soaring angelic V-span. The larger scapula sweep
            # gives the flight pose a clear silhouette beyond the body width.
            pb[f"WingScapula.{side}"].rotation_euler = (
                0.10 * out + flap * 0.26,
                sign * (0.34 * out),
                -sign * (0.02 + 1.24 * out),
            )
            pb[f"WingHumerus.{side}"].rotation_euler = (
                0.62 * out + flap * 0.34,
                sign * (0.08 * out),
                -sign * (0.01 + 0.34 * out),
            )
            pb[f"WingRadius.{side}"].rotation_euler = (
                0.14 * out + flap * 0.24,
                0.0,
                -sign * (0.01 + 0.12 * out),
            )
            pb[f"WingHand.{side}"].rotation_euler = (
                0.10 * out + flap * 0.18,
                0.0,
                -sign * (0.01 + 0.06 * out),
            )
            # SEAMLESS CONTINUOUS FAN: smooth closely-spaced tier pitches (-0.42 -> -0.44 -> -0.26 -> -0.09)
            # so all layered feathers form ONE cohesive angelic Pegasus wing (zero paddle gaps!)
            pb[f"WingCoverts.{side}"].rotation_euler = (
                -0.42 * out + flap * 0.10,
                sign * (-0.18 * out),
                sign * (0.16 * out),
            )
            pb[f"SecondaryFan.{side}"].rotation_euler = (
                -0.44 * out + flap * 0.14,
                sign * (-0.16 * out),
                sign * (0.20 * out),
            )
            pb[f"PrimaryFan2.{side}"].rotation_euler = (
                -0.26 * out + flap * 0.16,
                sign * (-0.12 * out),
                sign * (0.12 * out),
            )
            pb[f"PrimaryFan1.{side}"].rotation_euler = (
                -0.09 * out + flap * 0.20,
                sign * (-0.05 * out),
                sign * (0.04 * out),
            )

    def _flow(pb: Any, u: float, amp: float = 1.0) -> None:
        t = u * 2.0 * math.pi
        pb["ManeLock"].rotation_euler = (0.10 * math.sin(t) * amp, 0.0, 0.08 * math.sin(t * 0.5))
        pb["ManeTuft"].rotation_euler = (-0.12 * math.sin(t) * amp, 0.0, 0.0)
        pb["TailBase"].rotation_euler = (0.04 * math.sin(t) * amp, 0.0, 0.18 * math.sin(t) * amp)
        pb["TailEnd"].rotation_euler = (0.06 * math.sin(t + 0.6) * amp, 0.0, 0.16 * math.sin(t + 0.8) * amp)

    def idle(pb: Any, u: float) -> None:
        t = u * 2.0 * math.pi
        breath = 0.5 - 0.5 * math.cos(2.0 * t)
        pb["Hips"].location = (0.0, -0.010 * breath, 0.0)
        pb["Spine"].rotation_euler = (0.018 * breath, 0.0, 0.0)
        pb["Chest"].rotation_euler = (-0.020 * breath, 0.0, 0.0)
        pb["Neck2"].rotation_euler = (0.045 * math.sin(t), 0.0, 0.0)
        pb["Skull"].rotation_euler = (-0.045 * breath, 0.035 * math.sin(t * 0.5), 0.0)
        pb["Jaw"].rotation_euler = (0.04 * breath, 0.0, 0.0)
        _wing_fold(pb, 0.0, flap=0.010 * math.sin(t))
        _flow(pb, u, 0.55)

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
            pb[f"ForeShoulder.{side}"].rotation_euler = (_periodic(p, FORE_KNOTS) * 0.45, 0, 0)
            pb[f"ForeUpper.{side}"].rotation_euler = (_periodic(p, FORE_KNOTS), 0, 0)
            pb[f"Forearm.{side}"].rotation_euler = (min(-0.1, _periodic(p, CANNON_KNOTS)), 0, 0)
            pb[f"ForeCannon.{side}"].rotation_euler = (_periodic(p, CANNON_KNOTS) * 0.6, 0, 0)
            pb[f"ForeFetlock.{side}"].rotation_euler = (0.16 * math.sin(4.0 * math.pi * p), 0, 0)
            pb[f"ForeHoof.{side}"].rotation_euler = (-0.10 * math.sin(4.0 * math.pi * p), 0, 0)
            pb[f"HindHaunch.{side}"].rotation_euler = (_periodic(q, HIND_KNOTS) * 0.45, 0, 0)
            pb[f"HindThigh.{side}"].rotation_euler = (_periodic(q, HIND_KNOTS), 0, 0)
            pb[f"HindGaskin.{side}"].rotation_euler = (min(-0.1, _periodic(q, CANNON_KNOTS)), 0, 0)
            pb[f"HindCannon.{side}"].rotation_euler = (_periodic(q, CANNON_KNOTS) * 0.6, 0, 0)
            pb[f"HindFetlock.{side}"].rotation_euler = (0.14 * math.sin(4.0 * math.pi * q), 0, 0)
            pb[f"HindHoof.{side}"].rotation_euler = (-0.10 * math.sin(4.0 * math.pi * q), 0, 0)
        _wing_fold(pb, 0.0, flap=0.018 * math.sin(2.0 * t))
        _flow(pb, u, 1.0)

    def wingspread(pb: Any, u: float) -> None:
        # 2nd special (HornBeam charge): wings MUST stay strictly CLOSED; lowers horn forward to aim.
        env = math.sin(min(u, 1.0) * math.pi)
        pb["Hips"].location = (0.0, 0.036 * env, 0.0)
        pb["Chest"].rotation_euler = (-0.14 * env, 0.0, 0.0)
        pb["Neck2"].rotation_euler = (0.22 * env, 0.0, 0.0)
        pb["Skull"].rotation_euler = (-0.18 * env, 0.0, 0.0)
        pb["Jaw"].rotation_euler = (0.18 * env, 0.0, 0.0)
        _wing_fold(pb, 0.0, flap=0.022 * env)
        _flow(pb, u * 0.5, 0.8)

    def boom(pb: Any, u: float) -> None:
        # 3rd special (UnicornBoom): ONLY time wings unfurl wide open and flap heroically!
        env = math.sin(min(u, 1.0) * math.pi)
        flight = min(1.0, u / 0.22) if u < 0.80 else max(0.0, (1.0 - u) / 0.20)
        pb["Hips"].location = (0.0, 0.36 * env, 0.0)
        pb["Hips"].rotation_euler = (-0.14 * flight, 0.0, 0.0)
        pb["Chest"].rotation_euler = (-0.16 * flight, 0.0, 0.0)
        pb["Neck2"].rotation_euler = (0.16 * flight, 0.0, 0.0)
        pb["Skull"].rotation_euler = (-0.18 * flight, 0.0, 0.0)
        flap = math.sin(u * 4.0 * math.pi) * 0.38 * flight
        _wing_fold(pb, flight, flap=flap)
        # Smooth, natural rearing/flying horse leg tuck (no awkward shoulder kink!)
        for side in ("L", "R"):
            pb[f"ForeShoulder.{side}"].rotation_euler = (0.38 * flight, 0.0, 0.0)
            pb[f"ForeUpper.{side}"].rotation_euler = (0.48 * flight, 0.0, 0.0)
            pb[f"Forearm.{side}"].rotation_euler = (-0.98 * flight, 0.0, 0.0)
            pb[f"ForeFetlock.{side}"].rotation_euler = (-0.25 * flight, 0.0, 0.0)
            pb[f"HindHaunch.{side}"].rotation_euler = (-0.26 * flight, 0.0, 0.0)
            pb[f"HindThigh.{side}"].rotation_euler = (-0.52 * flight, 0.0, 0.0)
            pb[f"HindGaskin.{side}"].rotation_euler = (0.82 * flight, 0.0, 0.0)
        _flow(pb, u * 2.0, 1.3)

    commit("Idle_Breathe", 48, idle)
    commit("Locomotion_Gallop", 24, gallop)
    commit("Action_WingSpread", 24, wingspread)
    commit("UnicornBoom_Flight", 36, boom)

    # Hard kinematic verification of closed vs open wings!
    arm.animation_data.use_nla = False
    for label, fn, u_val in (("idle", idle, 0.0), ("gallop", gallop, 0.25), ("wingspread", wingspread, 0.5)):
        for pb in pose:
            pb.rotation_euler = (0.0, 0.0, 0.0)
            pb.location = (0.0, 0.0, 0.0)
        fn(pose, u_val)
        bpy.context.view_layer.update()
        wx = abs(pose["WingHand.L"].tail.x)
        assert wx < 0.55, f"{label} wings must stay closed, got |x|={wx:.3f}"
    for pb in pose:
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
    idle(pose, 0.0)
    bpy.context.view_layer.update()
    idle_z = pose["WingHand.L"].tail.z
    for pb in pose:
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
    boom(pose, 0.45)
    bpy.context.view_layer.update()
    boom_lx = pose["WingHand.L"].tail.x
    boom_rx = pose["WingHand.R"].tail.x
    boom_z = pose["WingHand.L"].tail.z
    print(f"[QA] boom WingHand L.x={boom_lx:.3f} R.x={boom_rx:.3f} z={boom_z:.3f} (idle_z={idle_z:.3f})")
    assert boom_lx > 1.20 and boom_rx < -1.20, \
        f"UnicornBoom_Flight did not open wings wide (>1.20m): L.x={boom_lx:.3f}, R.x={boom_rx:.3f}"
    assert boom_z > idle_z + 0.30, \
        f"UnicornBoom_Flight did not lift wings high: {boom_z:.3f} vs {idle_z:.3f}"
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
    bg.inputs["Color"].default_value = (0.11, 0.12, 0.20, 1.0)
    out = wt.nodes.new("ShaderNodeOutputWorld")
    wt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    for name, typ, loc, lc, energy in (
        ("KeyWarm", "AREA", (-2.6, -2.8, 3.2), (1.0, 0.95, 0.90), 580),
        ("FillCool", "AREA", (2.8, -2.2, 2.2), (0.86, 0.92, 1.0), 340),
        ("RimPink", "SPOT", (3.2, 1.8, 2.4), (1.0, 0.42, 0.80), 950),
        ("RimCyan", "SPOT", (-3.2, 1.8, 2.2), (0.46, 0.88, 1.0), 900),
    ):
        data = bpy.data.lights.new(name, typ)
        data.color = lc
        data.energy = energy
        if typ == "AREA":
            data.size = 2.4
        else:
            data.spot_size = math.radians(42)
        ob = bpy.data.objects.new(name, data)
        col.objects.link(ob)
        ob.location = loc
        ob.rotation_euler = (Vector((0, 0, 1.15)) - ob.location).to_track_quat("-Z", "Y").to_euler()
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
    verts = faces = tris = non_manifold = 0
    gmin = Vector((float("inf"),) * 3)
    gmax = Vector((float("-inf"),) * 3)
    for ob, _ in parts:
        bm = bmesh.new()
        bm.from_object(ob, depsgraph)
        bm.transform(ob.matrix_world)
        verts += len(bm.verts)
        faces += len(bm.faces)
        tris += sum(max(1, len(f.verts) - 2) for f in bm.faces)
        non_manifold += sum(1 for e in bm.edges if not e.is_manifold)
        for v in bm.verts:
            for i in range(3):
                gmin[i] = min(gmin[i], v.co[i])
                gmax[i] = max(gmax[i], v.co[i])
        bm.free()
    arm.animation_data.use_nla = True
    dims = [round(gmax[i] - gmin[i], 6) for i in range(3)]
    print(f"[QA] verts={verts} faces={faces} tris={tris} non_manifold_edges={non_manifold} "
          f"minZ={gmin.z:.4f} bbox={dims}")
    assert tris < 10000, f"Lea mesh exceeded 10k tri budget ({tris} tris, {faces} faces)"
    assert non_manifold == 0, f"Lea mesh has {non_manifold} non-manifold edges"

    ground_shift = -gmin.z
    if abs(ground_shift) > 1e-9:
        arm.location.z += ground_shift
        gmin.z = 0.0
        gmax.z += ground_shift
        print(f"[QA] ground-seated by +{ground_shift:.4f} m -> minZ=0.0000")

    horn_tip_world = horn_tip + Vector((0.0, 0.0, ground_shift))
    print(f"[QA] HornTip Blender=({horn_tip_world.x:.4f}, {horn_tip_world.y:.4f}, {horn_tip_world.z:.4f}) "
          f"glTF=({horn_tip_world.x:.4f}, {horn_tip_world.z:.4f}, {-horn_tip_world.y:.4f})")

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
        "pbr_palette_srgb": ["#DEE6F7", "#F06AB5", "#B98BE8", "#6FD6E8", "#E8B84B"],
        "rig": {
            "bone_count": BONE_COUNT, "profile": "creature-winged-equine",
            "actions": list(ACTION_NAMES), "skinning": "smooth-sculpted-loft",
        },
        "notes": ("Authored dimension spec for the stylized Lea Unicorn references in "
                  "docs/plans/Designs/Lea unicorn/. Heroic sculpted Pegasus unicorn, "
                  "wings folded compactly at rest, ground datum minZ=0.000."),
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
            "front": ((0.0, -3.7, 1.15), 40, (0, 0, 1.05)),
            "side": ((3.7, 0.0, 1.12), 40, (0, 0.02, 1.05)),
            "back": ((0.0, 3.7, 1.15), 40, (0, 0, 1.05)),
            "right_cheek": ((-1.65, 0.85, 1.04), 46, (-0.25, 0.36, 0.96)),
            "iso": ((2.9, -3.3, 2.0), 42, (0, -0.05, 1.08)),
        }
        for name, (loc, lens, target) in views.items():
            cam.location = loc
            cam.data.lens = lens
            cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = os.path.join(previews, f"lea_{name}.png")
            bpy.ops.render.render(write_still=True)
            print("PREVIEW", scene.render.filepath)
        for pb in pose:
            pb.rotation_euler = (0.0, 0.0, 0.0)
            pb.location = (0.0, 0.0, 0.0)
        boom(pose, 0.45)
        bpy.context.view_layer.update()
        cam.location = (3.4, -3.8, 2.5)
        cam.data.lens = 34
        cam.rotation_euler = (Vector((0, 0.15, 1.45)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(previews, "lea_boom_open.png")
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", scene.render.filepath)
        for pb in pose:
            pb.rotation_euler = (0.0, 0.0, 0.0)
            pb.location = (0.0, 0.0, 0.0)
        arm.animation_data.use_nla = True

    return {
        "verts": verts, "faces": faces, "tris": tris, "non_manifold": non_manifold,
        "dims": dims, "bones": len(spec), "clips": list(ACTION_NAMES),
        "meshes": len(parts), "glb": glb_path, "stl": stl_path,
        "horn_tip_blender": [round(horn_tip_world.x, 4), round(horn_tip_world.y, 4), round(horn_tip_world.z, 4)],
        "horn_tip_gltf": [round(horn_tip_world.x, 4), round(horn_tip_world.z, 4), round(-horn_tip_world.y, 4)],
    }


if __name__ == "__main__":
    result = build_lea()
    print("LEA_BUILD_OK", json.dumps(result, sort_keys=True))
