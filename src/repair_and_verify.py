"""
repair_and_verify.py - Final repair pass for the Kiepie Bike, run headless:
    blender -b -noaudio -P src/repair_and_verify.py

Steps:
  1. Rebuild the bike from the (approved) dimension spec.
  2. Apply all modifiers, then translate the whole mesh so the AABB min-Z is
     exactly 0.000 m (skill's watertight ground datum gate |minZ| <= 0.005m).
  3. Save .blend, export .glb / .glb (draco) / .stl.
  4. Round-trip the .glb with Blender's glTF importer and report bounds,
     minZ, vertex count, open/manifold edge counts.
  5. Render quick workbench previews so the deliverable stays auditable.
"""
import sys
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import bpy
import bmesh
from mathutils import Vector, Matrix

import build_quad
from build_quad import set_camera

PROJECT = build_quad.PROJECT
BLEND = build_quad.BLEND
GLB = build_quad.GLB
DRACO = os.path.join(PROJECT, 'Kiepie_Bike_draco.glb')
RENDERS = os.path.join(PROJECT, 'renders')


def main():
    root, coll = build_quad.build_bike()
    build_quad.finalize(coll)

    # global AABB across the bike, then shift so min-Z sits exactly on the ground
    gmin = [float('inf')] * 3
    gmax = [float('-inf')] * 3
    bike_meshes = [ob for c in coll.children_recursive for ob in c.objects
                   if ob.type == 'MESH']
    for ob in bike_meshes:
        for ch in ob.bound_box:
            w = ob.matrix_world @ Vector(ch)
            for i in range(3):
                gmin[i] = min(gmin[i], w[i])
                gmax[i] = max(gmax[i], w[i])
    dz = -gmin[2]
    print('AABB %s -> %s' % (gmin, gmax), 'shift dz', round(dz, 5))
    if abs(dz) > 1e-6:
        # World-space datum: move origins, not local vertices, so rotated
        # meshes are lifted straight up instead of drifting sideways.
        for ob in bike_meshes:
            if ob.parent is None:
                ob.location.z += dz
        bpy.context.view_layer.update()

    studio, cam, target = build_quad.build_studio()
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    build_quad.export_glb(coll)
    godot_glb = os.path.join(PROJECT, 'godot', 'assets', 'Kiepie_Bike.glb')
    if os.path.isdir(os.path.dirname(godot_glb)):
        shutil.copy2(GLB, godot_glb)
    build_quad.export_glb(coll, filepath=DRACO, draco=True)

    # ---- re-export the STL (bike collection meshes only) for the QA gate ----
    stl_path = os.path.join(PROJECT, 'Kiepie_Bike.stl')
    bpy.ops.object.select_all(action='DESELECT')
    for ob in bike_meshes:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = bike_meshes[0]
    bpy.ops.wm.stl_export(filepath=stl_path, export_selected_objects=True,
                          apply_modifiers=True, global_scale=1.0,
                          forward_axis='Y', up_axis='Z')
    print('exported STL (%d bike meshes) -> %s' % (len(bike_meshes), stl_path))

    # ---------------- verify (factory-empty scene, like the QA reviewer) ----
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB)
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    verts = 0
    gmin = [float('inf')] * 3
    gmax = [float('-inf')] * 3
    open_edges = 0
    non_manifold = 0
    for obj in meshes:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.transform(obj.matrix_world)
        verts += len(bm.verts)
        for ch in obj.bound_box:
            w = obj.matrix_world @ Vector(ch)
            for i in range(3):
                gmin[i] = min(gmin[i], w[i])
                gmax[i] = max(gmax[i], w[i])
        # glTF import splits coincident vertices on UV / normal seams, which
        # makes every seam edge look like a boundary.  Weld them back together
        # before measuring topology so the gate reports the real (watertight)
        # mesh instead of exporter seam duplication.
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
        open_edges += sum(1 for e in bm.edges if len(e.link_faces) <= 1)
        non_manifold += sum(1 for e in bm.edges if not e.is_manifold)
        bm.free()
    print('VERIFY objects %d verts %d' % (len(meshes), verts))
    print('VERIFY bounds [%.3f %.3f %.3f] -> [%.3f %.3f %.3f]' % tuple(gmin + gmax))
    print('VERIFY size [%.3f %.3f %.3f]' % tuple(gmax[i] - gmin[i] for i in range(3)))
    print('VERIFY minZ %.4f  open_edges %d  non_manifold_after_weld %d' % (
        gmin[2], open_edges, non_manifold))

    # ---------------- previews ---------------------------------------------
    bpy.ops.wm.read_homefile(filepath=BLEND)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x, scene.render.resolution_y = 760, 540
    scene.render.image_settings.file_format = 'PNG'
    os.makedirs(RENDERS, exist_ok=True)
    cam = scene.camera
    target = bpy.data.objects.get('Cam_Target')
    views = [('side_wb', (5.2, 0.0, 0.85), None), ('front_wb', (0.0, -5.2, 0.85), None),
             ('iso_wb', (3.6, -3.6, 2.3), None)]
    for name, loc, ortho in views:
        set_camera(cam, target, loc, ortho)
        scene.render.filepath = os.path.join(RENDERS, 'final_%s.png' % name)
        bpy.ops.render.render(write_still=True)
    print('PREVIEWS saved')


if __name__ == '__main__':
    main()
