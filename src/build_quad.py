"""
build_quad.py - Assemble the Kiepie Bike in Blender, export for Godot,
and render diagnostic views.

Usage (inside Blender):
    import sys; sys.path.append('<project>/src')
    import build_quad; build_quad.main()
"""
import bpy
import math
import os
import sys
from mathutils import Vector, Euler, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from qb_core import (purge_scene, collection, MATS, empty, parent_to, join,
                     set_origin)
from qb_spec import SPEC
import qb_wheels as W
import qb_body as B
import qb_engine as E
import qb_weapons as WP

PROJECT = os.path.abspath(os.path.join(HERE, '..'))
BLEND = os.path.join(PROJECT, 'Kiepie_Bike.blend')
GLB = os.path.join(PROJECT, 'Kiepie_Bike.glb')
RENDERS = os.path.join(PROJECT, 'renders')


def build_bike():
    purge_scene()
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
    scene.unit_settings.length_unit = 'METERS'

    root_coll = collection('KiepieBike')
    c_frame = collection('KB_Frame', root_coll)
    c_body = collection('KB_Body', root_coll)
    c_wheels = collection('KB_Wheels', root_coll)
    c_engine = collection('KB_Engine', root_coll)
    c_ctrl = collection('KB_Controls', root_coll)
    c_weapons = collection('KB_Weapons', root_coll)

    mats = MATS()

    # ---------------------------------------------------------------- frame
    B.build_frame(c_frame, mats)
    B.build_front_bumper(c_frame, mats)
    B.build_nerf_bars(c_frame, mats)

    # ---------------------------------------------------------------- body
    B.build_plastics(c_body, mats)
    B.build_seat(c_body, mats)
    B.build_lights(c_body, mats)

    # ------------------------------------------------------------ controls
    B.build_controls(c_ctrl, mats)
    B.build_cables(c_ctrl, mats)
    B.build_footpegs(c_ctrl, mats)
    B.build_decals(c_ctrl, mats)
    B.build_number_plates(c_ctrl, mats)

    # -------------------------------------------------------------- engine
    E.build_engine(c_engine, mats)
    E.build_exhaust(c_engine, mats)

    # ------------------------------------------------------------- weapons
    WP.build_cannons(c_weapons, mats)

    # -------------------------------------------------------------- wheels
    wheels = {}
    knuckles = {}
    for side in (-1, 1):
        s = 'L' if side < 0 else 'R'
        w, cal = W.build_wheel(side, True, c_wheels, mats)
        wheels['F' + s] = (w, cal)
        w2, cal2 = W.build_wheel(side, False, c_wheels, mats)
        wheels['R' + s] = (w2, cal2)
        knuckles['F' + s] = W.build_front_suspension(side, c_wheels, mats)
        W.build_rear_suspension(side, c_wheels, mats)

    # ------------------------------------------------------------ rig / pivot
    root = empty('Bike_Root', (0, 0, 0), root_coll, size=0.5, kind='ARROWS')
    steer = {}
    for side in (-1, 1):
        s = 'L' if side < 0 else 'R'
        cx = SPEC['front_hub_x']
        kn = empty('Steer_F' + s, (side * cx, SPEC['front_axle_y'], SPEC['front_axle_z']),
                   c_wheels, size=0.25, kind='SINGLE_ARROW')
        parent_to(kn, root)
        steer[s] = kn
        w, cal = wheels['F' + s]
        parent_to(w, kn)
        parent_to(cal, kn)
        parent_to(knuckles['F' + s], kn)

    for key, (w, cal) in wheels.items():
        if key.startswith('R'):
            parent_to(w, root)
            parent_to(cal, root)

    # parent every remaining bike part to the root (weapons included, so the
    # Muzzle_L / Muzzle_R empties become children of Bike_Root for Godot)
    for coll in (c_frame, c_body, c_ctrl, c_engine, c_weapons):
        for ob in coll.objects:
            if ob.parent is None and ob.name not in ('Bike_Root',):
                parent_to(ob, root)

    # deterministic ground datum: AABB bottom sits exactly on z = 0
    gmin = float('inf')
    for c in root_coll.children_recursive:
        for ob in c.objects:
            if ob.type != 'MESH':
                continue
            for corner in ob.bound_box:
                w = ob.matrix_world @ Vector(corner)
                gmin = min(gmin, w.z)
    if gmin != float('inf') and abs(gmin) > 1e-6:
        dz = -gmin
        # gmin is a WORLD-space measurement: shift object origins, not mesh
        # vertices. Transforming local Z moves rotated parts sideways.
        for ob in bpy.data.objects:
            if ob.type == 'MESH':
                ob.location.z += dz
        bpy.context.view_layer.update()
        print('seated bike to ground: dz', round(dz, 5))

    return root, root_coll


# ------------------------------------------------------------------- studio
def build_studio():
    studio = collection('Studio')
    # ground
    from qb_core import MB, make_material
    gm = make_material('Studio_Ground', (0.16, 0.165, 0.175), roughness=0.65)
    mb = MB()
    mb.box((0, 0, -0.02), (30, 30, 0.04))
    ground = mb.to_object('Ground', gm, studio)

    world = bpy.context.scene.world
    if world is None:
        world = bpy.data.worlds.new('World')
        bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get('Background')
    if bg:
        bg.inputs[0].default_value = (0.045, 0.050, 0.062, 1.0)
        bg.inputs[1].default_value = 1.0

    target = empty('Cam_Target', (0.0, 0.02, 0.58), studio, size=0.2)

    def area(name, loc, energy, size, rot=(0, 0, 0), color=(1, 1, 1)):
        d = bpy.data.lights.new(name, 'AREA')
        d.energy = energy
        d.size = size
        d.color = color
        ob = bpy.data.objects.new(name, d)
        ob.location = loc
        ob.rotation_euler = Euler(rot, 'XYZ')
        studio.objects.link(ob)
        c = ob.constraints.new('TRACK_TO')
        c.target = target
        c.track_axis = 'TRACK_NEGATIVE_Z'
        c.up_axis = 'UP_Y'
        return ob

    area('Key', (-2.4, -3.2, 3.4), 900, 3.0, color=(1.0, 0.97, 0.92))
    area('Fill', (3.4, -1.8, 2.0), 420, 3.5, color=(0.85, 0.90, 1.0))
    area('Rim', (0.4, 3.6, 2.6), 700, 3.0, color=(0.90, 0.95, 1.0))

    sun = bpy.data.lights.new('Sun', 'SUN')
    sun.energy = 2.0
    sun.angle = math.radians(6)
    so = bpy.data.objects.new('Sun', sun)
    so.rotation_euler = Euler((math.radians(52), 0, math.radians(-40)), 'XYZ')
    studio.objects.link(so)

    cam_data = bpy.data.cameras.new('Camera')
    cam_data.lens = 55
    cam = bpy.data.objects.new('Camera', cam_data)
    studio.objects.link(cam)
    cam.constraints.new('TRACK_TO').target = target
    bpy.context.scene.camera = cam
    return studio, cam, target


def set_camera(cam, target, loc, ortho=None):
    cam.location = loc
    if ortho:
        cam.data.type = 'ORTHO'
        cam.data.ortho_scale = ortho
    else:
        cam.data.type = 'PERSP'
    bpy.context.view_layer.update()


def render_views(cam, target):
    os.makedirs(RENDERS, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 780
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = False

    views = [
        ('front_0', (0.0, -4.10, 0.80), None),
        ('right_90', (4.10, 0.0, 0.80), None),
        ('rear_135', (2.60, 2.80, 1.70), None),
        ('iso_45', (3.00, -3.00, 2.10), None),
        ('top_ortho', (0.0, 0.02, 5.0), 2.6),
        ('detail_engine', (-1.35, -1.25, 0.85), None),
    ]
    out = []
    for name, loc, ortho in views:
        set_camera(cam, target, loc, ortho)
        scene.render.filepath = os.path.join(RENDERS, 'kiepie_%s.png' % name)
        bpy.ops.render.render(write_still=True)
        out.append(scene.render.filepath)
    return out


def preview(views=None, res=(760, 540), suffix="_prev"):
    """Fast Workbench preview renders for shape iteration."""
    os.makedirs(RENDERS, exist_ok=True)
    scene = bpy.context.scene
    prev_engine = scene.render.engine
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.image_settings.file_format = 'PNG'
    cam = scene.camera
    target = bpy.data.objects.get('Cam_Target')
    if views is None:
        views = [('right', (5.20, 0.0, 0.85), None),
                 ('left', (-5.20, 0.0, 0.85), None),
                 ('front', (0.0, -5.20, 0.85), None),
                 ('iso', (3.60, -3.60, 2.30), None),
                 ('top', (0.0, 0.02, 6.0), 2.9)]
    out = []
    for name, loc, ortho in views:
        set_camera(cam, target, loc, ortho)
        scene.render.filepath = os.path.join(RENDERS, 'kiepie%s_%s.png' % (suffix, name))
        bpy.ops.render.render(write_still=True)
        out.append(scene.render.filepath)
    scene.render.engine = prev_engine
    return out


def finalize(coll):
    """Apply every modifier so the saved scene is watertight."""
    import bpy
    objs = [ob for c in coll.children_recursive for ob in c.objects if ob.type == 'MESH']
    for ob in objs:
        if not ob.modifiers:
            continue
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        for m in list(ob.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except Exception:
                try:
                    ob.modifiers.remove(m)
                except Exception:
                    pass
    bpy.ops.object.select_all(action='DESELECT')
    return coll


def export_glb(root_coll, filepath=None, draco=False):
    """Export the whole bike hierarchy (meshes + steering pivots) to glTF."""
    filepath = filepath or GLB
    wanted = set()
    for c in root_coll.children_recursive:
        for ob in c.objects:
            wanted.add(ob.name)
    wanted.add('Bike_Root')
    bpy.ops.object.select_all(action='DESELECT')
    n = 0
    for ob in bpy.data.objects:
        if ob.name in wanted and ob.type in {'MESH', 'EMPTY'}:
            ob.select_set(True)
            n += 1
    bpy.context.view_layer.objects.active = bpy.data.objects.get('Bike_Root')
    kw = dict(filepath=filepath, export_format='GLB', use_selection=True,
              export_apply=True, export_yup=True, export_materials='EXPORT',
              export_cameras=False, export_lights=False, export_animations=True,
              export_extras=True)
    if draco:
        kw.update(export_draco_mesh_compression_enable=True,
                  export_draco_mesh_compression_level=6)
    bpy.ops.export_scene.gltf(**kw)
    print('exported %d objects -> %s' % (n, filepath))
    return filepath


def stats():
    tv = 0
    tf = 0
    for ob in bpy.data.objects:
        if ob.type == 'MESH':
            tv += len(ob.data.vertices)
            tf += len(ob.data.polygons)
    mn = [1e9] * 3
    mx = [-1e9] * 3
    for ob in bpy.data.objects:
        if ob.type == 'MESH':
            for c in ob.bound_box:
                w = ob.matrix_world @ Vector(c)
                for i in range(3):
                    mn[i] = min(mn[i], w[i])
                    mx[i] = max(mx[i], w[i])
    return {'objects': len(bpy.data.objects), 'verts': tv, 'faces': tf,
            'min': [round(v, 4) for v in mn], 'max': [round(v, 4) for v in mx],
            'size': [round(mx[i] - mn[i], 4) for i in range(3)]}


def main(do_render=True, do_export=True):
    root, coll = build_bike()
    finalize(coll)
    studio, cam, target = build_studio()
    bpy.context.view_layer.update()
    s = stats()
    print('BIKE STATS', s)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    if do_export:
        print('EXPORTED', export_glb(coll))
    if do_render:
        print('RENDERED', render_views(cam, target))
    return s


if __name__ == '__main__':
    main()
