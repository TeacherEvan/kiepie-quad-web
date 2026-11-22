"""
qb_core.py - Core helpers for the Kiepie Bike (sport quad / ATV) build.

Conventions (Blender native, +Z up, -Y forward, +X right):
    1 Blender unit = 1.000 m
    Front of the bike faces -Y
    Wheel axles run along X (lateral)
"""
import bpy
import bmesh
import math
import warnings
from mathutils import Vector, Matrix, Euler

TAU = math.pi * 2.0
R = math.radians


# ---------------------------------------------------------------- scene utils
def purge_scene():
    """Remove every object and orphan datablock so the build is deterministic."""
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in list(bpy.data.collections):
        bpy.data.collections.remove(coll)
    for blocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                   bpy.data.cameras, bpy.data.lights, bpy.data.images):
        for b in list(blocks):
            if b.users == 0:
                blocks.remove(b)


def collection(name, parent=None):
    if name in bpy.data.collections:
        c = bpy.data.collections[name]
    else:
        c = bpy.data.collections.new(name)
    tgt = parent if parent else bpy.context.scene.collection
    if c.name not in [ch.name for ch in tgt.children]:
        try:
            tgt.children.link(c)
        except RuntimeError as exc:
            warnings.warn(f"qb_core.collection: could not link {name!r}: {exc}")
    return c


def link(ob, coll):
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    coll.objects.link(ob)
    return ob


# ------------------------------------------------------------------ materials
def _bsdf(mat):
    for n in mat.node_tree.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            return n
    return None


def make_material(name, color=(0.5, 0.5, 0.5), metallic=0.0, roughness=0.5,
                  coat=0.0, coat_rough=0.05, emission=None, emission_strength=0.0,
                  transmission=0.0, ior=1.45, alpha=1.0, backface=False):
    """Create (or fetch) a Principled BSDF material."""
    if name in bpy.data.materials:
        mat = bpy.data.materials[name]
    else:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    b = _bsdf(mat)
    if b is None:
        return mat

    def setv(key, val):
        if key in b.inputs:
            try:
                b.inputs[key].default_value = val
            except (TypeError, ValueError) as exc:
                warnings.warn(f"qb_core.make_material({name!r}): input {key!r} rejected {val!r}: {exc}")

    setv('Base Color', (color[0], color[1], color[2], 1.0))
    setv('Metallic', metallic)
    setv('Roughness', roughness)
    setv('Coat Weight', coat)
    setv('Coat Roughness', coat_rough)
    setv('Transmission Weight', transmission)
    setv('IOR', ior)
    setv('Alpha', alpha)
    if emission is not None:
        setv('Emission Color', (emission[0], emission[1], emission[2], 1.0))
        setv('Emission Strength', emission_strength)
    mat.diffuse_color = (color[0], color[1], color[2], alpha)
    mat.use_backface_culling = backface
    if alpha < 1.0 or transmission > 0.0:
        if hasattr(mat, 'blend_method'):
            try:
                mat.blend_method = 'BLEND'
            except (AttributeError, TypeError, ValueError) as exc:
                warnings.warn(f"qb_core.make_material({name!r}): blend_method unsupported: {exc}")
    return mat


def MATS():
    """Material library for the bike."""
    m = {}
    # deep royal blue automotive plastic with clear coat
    m['paint_blue'] = make_material('Paint_Blue', (0.018, 0.055, 0.46),
                                    metallic=0.0, roughness=0.18, coat=1.0, coat_rough=0.03)
    m['paint_blue_dark'] = make_material('Paint_Blue_Dark', (0.010, 0.022, 0.20),
                                         metallic=0.0, roughness=0.22, coat=1.0)
    m['paint_blue_light'] = make_material('Paint_Blue_Light', (0.045, 0.13, 0.70),
                                           metallic=0.0, roughness=0.16, coat=1.0)
    m['graphic_lime'] = make_material('Graphic_Lime', (0.42, 0.92, 0.04),
                                       metallic=0.0, roughness=0.22, coat=0.8)
    m['graphic_yellow'] = make_material('Graphic_Yellow', (0.92, 0.80, 0.05),
                                        metallic=0.0, roughness=0.24, coat=0.8)
    m['graphic_white'] = make_material('Graphic_White', (0.88, 0.90, 0.92),
                                        metallic=0.0, roughness=0.25, coat=0.6)
    m['chrome'] = make_material('Chrome', (0.86, 0.87, 0.90),
                                metallic=1.0, roughness=0.07)
    m['chrome_dull'] = make_material('Chrome_Dull', (0.72, 0.73, 0.76),
                                     metallic=1.0, roughness=0.22)
    m['alu'] = make_material('Aluminium', (0.68, 0.69, 0.72),
                              metallic=1.0, roughness=0.28)
    m['engine_black'] = make_material('Engine_Black', (0.035, 0.035, 0.040),
                                      metallic=0.75, roughness=0.42)
    m['plastic_black'] = make_material('Plastic_Black', (0.022, 0.022, 0.026),
                                       metallic=0.0, roughness=0.42)
    m['plastic_grip'] = make_material('Plastic_Grip', (0.014, 0.014, 0.016),
                                      metallic=0.0, roughness=0.72)
    m['rubber'] = make_material('Tyre_Rubber', (0.016, 0.016, 0.018),
                                metallic=0.0, roughness=0.86)
    m['rubber_worn'] = make_material('Tyre_Rubber_Worn', (0.030, 0.030, 0.032),
                                     metallic=0.0, roughness=0.78)
    m['seat'] = make_material('Seat_Vinyl', (0.018, 0.018, 0.022),
                              metallic=0.0, roughness=0.55)
    m['wheel_metal'] = make_material('Wheel_Steel', (0.085, 0.088, 0.095),
                                     metallic=0.85, roughness=0.42)
    m['spring_white'] = make_material('Spring_White', (0.90, 0.91, 0.89),
                                      metallic=0.35, roughness=0.28)
    m['headlight'] = make_material('Headlight_Lens', (0.85, 0.88, 0.92),
                                   metallic=0.0, roughness=0.08, transmission=0.85,
                                   ior=1.52, emission=(1.0, 0.97, 0.90),
                                   emission_strength=0.6)
    m['taillight'] = make_material('Taillight_Lens', (0.55, 0.02, 0.02),
                                   metallic=0.0, roughness=0.10, transmission=0.6,
                                   emission=(0.9, 0.05, 0.03), emission_strength=0.4)
    m['reflector_amber'] = make_material('Reflector_Amber', (0.85, 0.35, 0.03),
                                         metallic=0.0, roughness=0.18)
    m['exhaust_steel'] = make_material('Exhaust_Steel', (0.30, 0.30, 0.32),
                                       metallic=1.0, roughness=0.34)
    m['glass_dark'] = make_material('Instrument_Lens', (0.02, 0.02, 0.03),
                                    metallic=0.0, roughness=0.05, coat=1.0)
    m['led_white'] = make_material('LED_White', (0.9, 0.9, 0.9), metallic=0.0,
                                   roughness=0.2, emission=(1, 1, 1), emission_strength=2.0)
    return m


# ------------------------------------------------------------- mesh building
class MB:
    """Small accumulator that builds one mesh from many primitive pieces."""

    def __init__(self):
        self.v = []
        self.f = []

    # -- helpers
    def _push(self, verts, faces):
        o = len(self.v)
        self.v.extend(verts)
        self.f.extend([[i + o for i in fc] for fc in faces])

    def box(self, center, size, rot=(0, 0, 0), bevel=0.0):
        """Axis aligned box (optionally rotated), optional simple chamfer."""
        sx, sy, sz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
        corners = [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, -sz), (-sx, sy, -sz),
                   (-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)]
        faces = [[0, 1, 2, 3], [7, 6, 5, 4], [4, 5, 1, 0],
                 [5, 6, 2, 1], [6, 7, 3, 2], [7, 4, 0, 3]]
        mrot = Euler(rot, 'XYZ').to_matrix()
        c = Vector(center)
        verts = [tuple(mrot @ Vector(p) + c) for p in corners]
        self._push(verts, faces)

    def cylinder(self, center, r, depth, axis='Z', seg=24, rot=(0, 0, 0), caps=True):
        """Cylinder aligned to a world axis, optionally rolled about that axis."""
        verts, faces = [], []
        for i in range(seg):
            a = TAU * i / seg
            for end in (-depth / 2.0, depth / 2.0):
                if axis == 'X':
                    p = (end, r * math.cos(a), r * math.sin(a))
                elif axis == 'Y':
                    p = (r * math.cos(a), end, r * math.sin(a))
                else:
                    p = (r * math.cos(a), r * math.sin(a), end)
                verts.append(p)
        for i in range(seg):
            j = (i + 1) % seg
            faces.append([i * 2, j * 2, j * 2 + 1, i * 2 + 1])
        if caps:
            faces.append([i * 2 for i in range(seg)][::-1])
            faces.append([i * 2 + 1 for i in range(seg)])
        mrot = Euler(rot, 'XYZ').to_matrix()
        c = Vector(center)
        out = [tuple(mrot @ Vector(p) + c) for p in verts]
        self._push(out, faces)

    def revolve(self, profile, center, axis='X', seg=48, rot=(0, 0, 0)):
        """Revolve a closed 2D profile [(radius, axial_offset), ...] about an axis."""
        n = len(profile)
        verts, faces = [], []
        for i in range(seg):
            a = TAU * i / seg
            ca, sa = math.cos(a), math.sin(a)
            for (rr, ax) in profile:
                if axis == 'X':
                    p = (ax, rr * ca, rr * sa)
                elif axis == 'Y':
                    p = (rr * ca, ax, rr * sa)
                else:
                    p = (rr * ca, rr * sa, ax)
                verts.append(p)
        for i in range(seg):
            j = (i + 1) % seg
            for k in range(n):
                l = (k + 1) % n
                faces.append([i * n + k, j * n + k, j * n + l, i * n + l])
        mrot = Euler(rot, 'XYZ').to_matrix()
        c = Vector(center)
        out = [tuple(mrot @ Vector(p) + c) for p in verts]
        self._push(out, faces)

    def shell(self, pts_grid, close_u=False):
        """Build a surface from a 2D grid of points [u][v]."""
        verts, faces = [], []
        nu = len(pts_grid)
        nv = len(pts_grid[0])
        for row in pts_grid:
            verts.extend(row)
        for i in range(nu - 1):
            for j in range(nv - 1):
                faces.append([i * nv + j, (i + 1) * nv + j,
                              (i + 1) * nv + j + 1, i * nv + j + 1])
        if close_u:
            for j in range(nv - 1):
                faces.append([(nu - 1) * nv + j, 0 * nv + j,
                              0 * nv + j + 1, (nu - 1) * nv + j + 1])
        self._push(verts, faces)

    def tube(self, pts, radius, seg=10):
        """Watertight round tube swept along a polyline."""
        from mathutils import Vector as _V
        n = len(pts)
        verts, faces = [], []
        for i, p in enumerate(pts):
            p = _V(p)
            if i == 0:
                t = _V(pts[1]) - _V(pts[0])
            elif i == n - 1:
                t = _V(pts[-1]) - _V(pts[-2])
            else:
                t = _V(pts[i + 1]) - _V(pts[i - 1])
            t = t.normalized()
            ref = _V((0, 0, 1)) if abs(t.z) < 0.9 else _V((1, 0, 0))
            u = t.cross(ref).normalized()
            v = t.cross(u).normalized()
            for j in range(seg):
                a = TAU * j / seg
                d = u * math.cos(a) + v * math.sin(a)
                verts.append((p.x + radius * d.x, p.y + radius * d.y, p.z + radius * d.z))
        for i in range(n - 1):
            for j in range(seg):
                a = i * seg + j
                b = i * seg + (j + 1) % seg
                c = (i + 1) * seg + (j + 1) % seg
                d = (i + 1) * seg + j
                faces.append([a, b, c, d])
        c0 = len(verts)
        verts.append(tuple(_V(pts[0])))
        for j in range(seg):
            faces.append([c0, (j + 1) % seg, j])
        c1 = len(verts)
        verts.append(tuple(_V(pts[n - 1])))
        base = (n - 1) * seg
        for j in range(seg):
            faces.append([c1, base + j, base + (j + 1) % seg])
        self._push(verts, faces)

    def to_object(self, name, mat=None, coll=None, smooth=False):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.v, [], self.f)
        me.validate(verbose=False)
        me.update()
        if smooth:
            for p in me.polygons:
                p.use_smooth = True
        ob = bpy.data.objects.new(name, me)
        if mat:
            ob.data.materials.append(mat)
        (coll or bpy.context.scene.collection).objects.link(ob)
        return ob


# ----------------------------------------------------------- object helpers
def add_cyl(name, r, depth, loc, axis='Z', rot=(0, 0, 0), seg=32, mat=None,
            coll=None, smooth=True, caps=True):
    mb = MB()
    mb.cylinder((0, 0, 0), r, depth, axis=axis, seg=seg, caps=caps)
    ob = mb.to_object(name, mat, coll)
    ob.location = loc
    ob.rotation_euler = Euler(rot, 'XYZ')
    if smooth:
        _smooth_cyl(ob, axis)
    return ob


def _smooth_cyl(ob, axis='Z'):
    """Smooth the barrel of a cylinder, keep the caps flat."""
    me = ob.data
    n = len(me.polygons)
    if n < 2:
        return
    side = n - 2 if len(me.polygons[0].vertices) > 4 else n
    for i, p in enumerate(me.polygons):
        p.use_smooth = (len(p.vertices) == 4 and i < side)


def add_box(name, size, loc, rot=(0, 0, 0), mat=None, coll=None, bevel=0.0,
            segs=2):
    mb = MB()
    mb.box((0, 0, 0), size)
    ob = mb.to_object(name, mat, coll)
    ob.location = loc
    ob.rotation_euler = Euler(rot, 'XYZ')
    if bevel > 0:
        m = ob.modifiers.new('Bevel', 'BEVEL')
        m.width = bevel
        m.segments = segs
        m.limit_method = 'ANGLE'
        m.angle_limit = R(40)
    return ob


def add_tube(name, pts, radius, mat=None, coll=None, res=6, smooth=True):
    """Round tube through a list of points."""
    mb = MB()
    mb.tube(pts, radius, seg=max(6, res + 4))
    ob = mb.to_object(name, mat, coll, smooth=smooth)
    return ob


def helix(name, start, end, radius, turns, wire, mat=None, coll=None, seg=16):
    """Coil-over spring: helix between two points."""
    a = Vector(start)
    b = Vector(end)
    d = (b - a)
    L = d.length
    axis = d.normalized()
    ref = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
    u = axis.cross(ref).normalized()
    v = axis.cross(u).normalized()
    n = max(8, int(turns * seg))
    pts = []
    for i in range(n + 1):
        t = i / n
        ang = TAU * turns * t
        p = a + d * t + (u * math.cos(ang) + v * math.sin(ang)) * radius
        pts.append(tuple(p))
    return add_tube(name, pts, wire, mat, coll, res=4)


def to_mesh(ob):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target='MESH')
    return bpy.context.view_layer.objects.active


def apply_modifiers(ob):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except RuntimeError as exc:
            warnings.warn(
                f"qb_core.apply_modifiers: failed to apply {m.name} on {ob.name}: {exc}",
                RuntimeWarning,
            )
            ob.modifiers.remove(m)
    return ob


def rotate_about(objs, pivot, axis, angle):
    """Rotate objects about a world-space pivot, preserving world placement.

    Objects carry their own location/rotation, so the world rotation has to be
    conjugated into each mesh's local space. Applying ``rm`` directly to local
    vertices displaced any part whose origin was away from the pivot.
    """
    bpy.context.view_layer.update()
    piv = Vector(pivot)
    rm = (Matrix.Translation(piv) @ Matrix.Rotation(angle, 4, axis)
          @ Matrix.Translation(-piv))
    for o in objs:
        mw = o.matrix_world.copy()
        o.data.transform(mw.inverted() @ rm @ mw)
    return objs


def _cap_holes(ob):
    """Fill every boundary loop with an n-gon (watertight tubes/pipes)."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    boundary = [e for e in bm.edges if len(e.link_faces) <= 1]
    if boundary:
        bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
    # fallback: walk each remaining loop and make an n-gon face
    boundary = [e for e in bm.edges if len(e.link_faces) <= 1]
    if boundary:
        from collections import defaultdict as _default
        vmap = _default(list)
        for e in boundary:
            vmap[e.verts[0]].append(e)
            vmap[e.verts[1]].append(e)
        remaining = list(boundary)
        used_edges = set()
        for start in list(boundary):
            if start in used_edges:
                continue
            loop_verts = [start.verts[0]]
            current_edge = start
            current_vert = start.verts[1]
            start_vert = start.verts[0]
            used = {start}
            while current_vert != start_vert:
                nxt = None
                for e2 in vmap.get(current_vert, []):
                    if e2 in used:
                        continue
                    nxt = e2
                    break
                if nxt is None:
                    break
                used.add(nxt)
                if nxt.verts[0] == current_vert:
                    current_vert = nxt.verts[1]
                else:
                    current_vert = nxt.verts[0]
                loop_verts.append(current_vert)
                current_edge = nxt
            used_edges.update(used)
            if len(loop_verts) >= 3 and current_vert == start_vert:
                try:
                    bm.faces.new(loop_verts)
                except ValueError as exc:
                    warnings.warn(f"qb_core.cap_open_loops: skipped degenerate face: {exc}")
    bm.to_mesh(me)
    bm.free()
    me.update()


def smooth_by_angle(ob, angle=35):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    try:
        bpy.ops.object.shade_auto_smooth(angle=R(angle))
    except (AttributeError, RuntimeError) as exc:
        warnings.warn(f"qb_core.smooth_by_angle({ob.name!r}): shade_auto_smooth failed: {exc}")


def mirror_x(ob, new_name=None):
    """Duplicate an object mirrored across X (geometry flipped, normals rebuilt)."""
    me = ob.data.copy()
    dup = bpy.data.objects.new(new_name or (ob.name + '_M'), me)
    for c in ob.users_collection:
        c.objects.link(dup)
    for v in me.vertices:
        v.co.x = -v.co.x
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    dup.location = ob.location.copy()
    dup.location.x = -ob.location.x
    return dup


def set_origin(ob, point):
    """Move object origin to a world point keeping geometry in place."""
    delta = Vector(point) - ob.location
    ob.data.transform(Matrix.Translation(-delta))
    ob.location = Vector(point)


def parent_to(child, parent):
    child.parent = parent
    bpy.context.view_layer.update()
    child.matrix_parent_inverse = parent.matrix_world.inverted()


def empty(name, loc, coll, size=0.15, kind='PLAIN_AXES'):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = kind
    e.empty_display_size = size
    e.location = loc
    coll.objects.link(e)
    return e


def join(objs, name=None):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    if name:
        ob.name = name
    return ob


def make_image_material(name, image_path, emission_strength=0.6):
    """Textured decal material backed by an image (emissive to stay legible)."""
    if name in bpy.data.materials:
        bpy.data.materials.remove(bpy.data.materials[name])
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if bsdf is None:
        return mat
    tex = nt.nodes.new('ShaderNodeTexImage')
    img = bpy.data.images.load(image_path)
    img.colorspace_settings.name = 'sRGB'
    tex.image = img
    bsdf.inputs['Metallic'].default_value = 0.0
    bsdf.inputs['Roughness'].default_value = 0.35
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    if 'Alpha' in bsdf.inputs:
        nt.links.new(tex.outputs['Alpha'], bsdf.inputs['Alpha'])
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Emission Color'])
    bsdf.inputs['Emission Strength'].default_value = emission_strength
    if hasattr(mat, 'surface_render_method'):
        try:
            mat.surface_render_method = 'DITHERED'
        except (AttributeError, TypeError, ValueError) as exc:
            warnings.warn(f"qb_core.make_decal_material({name!r}): surface_render_method failed: {exc}")
    if hasattr(mat, 'blend_method'):
        try:
            mat.blend_method = 'BLEND'
        except (AttributeError, TypeError, ValueError) as exc:
            warnings.warn(f"qb_core.make_decal_material({name!r}): blend_method failed: {exc}")
    return mat


def add_decal_plane(name, size, pos, dir_vec, up_vec, mat, coll):
    """A flat image quad oriented so local +Z is the surface normal."""
    w, h = size
    me = bpy.data.meshes.new(name)
    verts = [(-w / 2.0, -h / 2.0, 0.0), (w / 2.0, -h / 2.0, 0.0),
             (w / 2.0, h / 2.0, 0.0), (-w / 2.0, h / 2.0, 0.0)]
    faces = [(0, 1, 2, 3)]
    me.from_pydata(verts, [], faces)
    uv = me.uv_layers.new(name='UVMap')
    coords = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
    for loop in me.loops:
        uv.data[loop.index].uv = coords[loop.vertex_index]
    ob = bpy.data.objects.new(name, me)
    link(ob, coll)
    d = Vector(dir_vec).normalized()
    u = Vector(up_vec).normalized()
    n = d.cross(u)
    m = Matrix(((d.x, u.x, n.x, 0), (d.y, u.y, n.y, 0), (d.z, u.z, n.z, 0),
                (0, 0, 0, 1)))
    ob.rotation_euler = Euler(m.to_euler(), 'XYZ')
    ob.location = pos
    if mat:
        ob.data.materials.append(mat)
    mod = ob.modifiers.new('Vinyl', 'SOLIDIFY')
    mod.thickness = 0.002
    mod.offset = 0.0
    return ob
