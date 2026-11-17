"""
qb_engine.py - Engine, CVT drive, exhaust and cooling for the Kiepie Bike.
"""
import bpy
import math
from mathutils import Vector

from qb_core import (MB, add_cyl, add_box, add_tube, join, to_mesh)
from qb_spec import SPEC

TAU = math.pi * 2.0
R = math.radians


def build_engine(coll, mats):
    parts = []
    cx, cy, cz = SPEC['engine_centre']

    # ---- crankcase / transmission case
    case = add_box('Engine_Case', (0.330, 0.430, 0.250), (0.0, cy + 0.010, 0.330),
                   mat=mats['engine_black'], coll=coll, bevel=0.028)
    parts.append(case)

    # cylinder block with cooling fins
    blk = add_box('Cylinder_Block', (0.185, 0.205, 0.150), (0.0, cy + 0.020, 0.500),
                  mat=mats['engine_black'], coll=coll, bevel=0.012)
    parts.append(blk)
    fins = MB()
    for i in range(7):
        z = 0.442 + i * 0.021
        fins.box((0.0, cy + 0.020, z), (0.235, 0.255, 0.0075))
    finobj = fins.to_object('Cylinder_Fins', mats['engine_black'], coll)
    parts.append(finobj)

    # head + cam cover (tilted forward with the cylinder)
    head = add_box('Cylinder_Head', (0.205, 0.225, 0.075), (0.0, cy + 0.020, 0.600),
                   mat=mats['engine_black'], coll=coll, bevel=0.010)
    parts.append(head)
    cam = add_box('Cam_Cover', (0.160, 0.180, 0.055), (0.0, cy + 0.020, 0.662),
                  mat=mats['alu'], coll=coll, bevel=0.012)
    parts.append(cam)

    # lean the cylinder forward, like a real ATV engine
    from qb_core import rotate_about
    rotate_about([blk, finobj, head, cam], (0.0, cy + 0.020, 0.430), 'X', math.radians(13))

    # spark plug + lead
    plug = add_cyl('Spark_Plug', 0.016, 0.060, (0.075, cy + 0.010, 0.700),
                   axis='Z', seg=12, mat=mats['chrome'], coll=coll)
    parts.append(plug)
    parts.append(add_tube('Plug_Lead', [
        (0.075, cy + 0.010, 0.730), (0.130, cy - 0.040, 0.740),
        (0.150, cy - 0.150, 0.700)], 0.006, mats['plastic_black'], coll))

    # ---- CVT cover (left) and transmission case (right)
    cvc = add_cyl('CVT_Cover', 0.150, 0.070, (-0.205, cy + 0.020, 0.330),
                  axis='X', seg=40, mat=mats['engine_black'], coll=coll)
    parts.append(cvc)
    parts.append(add_cyl('CVT_Boss', 0.075, 0.050, (-0.235, cy + 0.020, 0.330),
                         axis='X', seg=24, mat=mats['engine_black'], coll=coll))
    parts.append(add_cyl('Transmission', 0.115, 0.055, (0.190, cy + 0.020, 0.330),
                         axis='X', seg=28, mat=mats['engine_black'], coll=coll))

    # ---- variator pulley + driven pulley cover (left side)
    var = add_cyl('Variator', 0.086, 0.055, (-0.262, 0.010, 0.330), axis='X',
                  seg=32, mat=mats['chrome_dull'], coll=coll)
    parts.append(var)
    parts.append(add_cyl('Variator_Hub', 0.040, 0.075, (-0.262, 0.010, 0.330),
                         axis='X', seg=16, mat=mats['alu'], coll=coll))

    # ---- rear sprocket (left) with teeth
    teeth = MB()
    nteeth = 26
    for i in range(nteeth):
        a = TAU * i / nteeth
        teeth.box((-0.575, 0.135 * math.cos(a) - 0.0, 0.135 * math.sin(a)),
                  (0.020, 0.016, 0.026), rot=(a, 0, 0))
    t = teeth.to_object('Sprocket_Teeth', mats['engine_black'], coll)
    t.location = (0.0, SPEC['rear_axle_y'], SPEC['rear_axle_z'])
    parts.append(t)
    sp = add_cyl('Rear_Sprocket', 0.125, 0.018, (0, 0, 0), axis='X', seg=36,
                 mat=mats['engine_black'], coll=coll)
    sp.location = (-0.575, SPEC['rear_axle_y'], SPEC['rear_axle_z'])
    parts.append(sp)

    # ---- CVT belt: wraps the variator and the rear sprocket
    parts.append(build_belt(coll, mats))

    # ---- air box + intake snorkel (right hand side, behind the cylinder)
    abox = add_box('Air_Box', (0.110, 0.230, 0.150), (0.210, 0.115, 0.505),
                   mat=mats['plastic_black'], coll=coll, bevel=0.018)
    parts.append(abox)
    parts.append(add_tube('Intake_Snorkel', [
        (0.215, 0.200, 0.570), (0.235, 0.300, 0.600), (0.240, 0.410, 0.625)],
        0.036, mats['plastic_black'], coll))

    # ---- fuel tank under the seat
    tank = add_box('Fuel_Tank', (0.320, 0.400, 0.105), (0.0, 0.240, 0.655),
                   mat=mats['plastic_black'], coll=coll, bevel=0.028)
    parts.append(tank)
    parts.append(add_cyl('Fuel_Cap', 0.035, 0.022, (0.100, 0.330, 0.700),
                         axis='Z', seg=16, mat=mats['alu'], coll=coll))

    # ---- radiator with grille
    rad = add_box('Radiator', (0.330, 0.055, 0.250), (0.0, -0.430, 0.560),
                  mat=mats['engine_black'], coll=coll, bevel=0.010)
    parts.append(rad)
    grille = MB()
    for i in range(9):
        grille.box((0.0, -0.462, 0.450 + i * 0.027), (0.300, 0.012, 0.010))
    gr = grille.to_object('Radiator_Grille', mats['engine_black'], coll)
    parts.append(gr)

    # hoses
    parts.append(add_tube('Hose_Rad_Upper', [
        (0.120, -0.420, 0.660), (0.170, -0.330, 0.640), (0.160, -0.230, 0.600)],
        0.018, mats['plastic_black'], coll))
    parts.append(add_tube('Hose_Rad_Lower', [
        (0.140, -0.420, 0.450), (0.185, -0.330, 0.430), (0.170, -0.240, 0.470)],
        0.018, mats['plastic_black'], coll))
    # fuel line to the carb
    parts.append(add_tube('Fuel_Line', [
        (0.150, -0.200, 0.660), (0.120, -0.320, 0.660), (0.090, -0.400, 0.610)],
        0.008, mats['plastic_black'], coll))

    # ---- carburettor / throttle body
    parts.append(add_box('Carb', (0.110, 0.120, 0.130), (0.060, -0.230, 0.590),
                         mat=mats['alu'], coll=coll, bevel=0.012))

    # ---- engine mount brackets
    for side in (-1, 1):
        parts.append(add_box('Engine_Mount_%d' % side, (0.040, 0.180, 0.090),
                             (side * 0.140, cy + 0.050, 0.430),
                             mat=mats['engine_black'], coll=coll, bevel=0.010))
    return parts


def build_belt(coll, mats):
    """CVT belt looping from the variator to the rear sprocket."""
    c1 = Vector((0.010, 0.330))    # (y, z) of the variator
    r1 = 0.088
    c2 = Vector((SPEC['rear_axle_y'], SPEC['rear_axle_z']))
    r2 = 0.138
    x1, x2 = -0.268, -0.575

    d = c2 - c1
    dist = d.length
    phi = math.atan2(d.y, d.x)
    beta = math.pi / 2.0 + math.asin(max(-1.0, min(1.0, (r2 - r1) / dist)))

    pts = []       # (y, z, x)
    na = 18

    def on_circle(c, r, a):
        return (c.x + r * math.cos(a), c.y + r * math.sin(a))

    # wrap around the front pulley (away from the sprocket)
    a_start = phi + beta
    a_end = phi - beta + TAU
    for i in range(na + 1):
        a = a_start + (a_end - a_start) * i / na
        y, z = on_circle(c1, r1, a)
        pts.append((y, z, x1))
    # run back to the sprocket
    y, z = on_circle(c2, r2, phi - beta)
    y0, z0 = pts[-1][0], pts[-1][1]
    for i in range(1, 9):
        t = i / 9.0
        pts.append((y0 + (y - y0) * t, z0 + (z - z0) * t, x1 + (x2 - x1) * t))
    # wrap around the rear sprocket
    a_start = phi - beta
    a_end = phi + beta
    for i in range(1, na + 1):
        a = a_start + (a_end - a_start) * i / na
        y, z = on_circle(c2, r2, a)
        pts.append((y, z, x2))
    # close back to the front pulley
    y, z = on_circle(c1, r1, phi + beta)
    y0, z0 = pts[-1][0], pts[-1][1]
    for i in range(1, 9):
        t = i / 9.0
        pts.append((y0 + (y - y0) * t, z0 + (z - z0) * t, x2 + (x1 - x2) * t))

    # closed solid band: outer wall, inner wall, both edge walls
    hw = 0.026
    th = 0.010
    verts, faces = [], []
    n = len(pts)
    for i, (y, z, x) in enumerate(pts):
        nxt = (i + 1) % n
        yn = pts[nxt][1] - pts[i - 1][1] if i > 0 else pts[1][1] - pts[0][1]
        zn = pts[nxt][2] - pts[i - 1][2] if i > 0 else pts[1][2] - pts[0][2]
        ln = math.hypot(yn, zn) or 1.0
        ny_, nz_ = yn / ln, zn / ln
        verts += [(x - hw, y + ny_ * th / 2.0, z + nz_ * th / 2.0),
                  (x + hw, y + ny_ * th / 2.0, z + nz_ * th / 2.0),
                  (x + hw, y - ny_ * th / 2.0, z - nz_ * th / 2.0),
                  (x - hw, y - ny_ * th / 2.0, z - nz_ * th / 2.0)]
    for i in range(n):
        j = (i + 1) % n
        b = i * 4
        c = j * 4
        faces += [
            [b + 0, c + 0, c + 1, b + 1],   # outer wall
            [b + 2, c + 2, c + 3, b + 3],   # inner wall
            [b + 3, c + 3, c + 0, b + 0],   # left edge
            [b + 1, c + 1, c + 2, b + 2],   # right edge
        ]
    me = bpy.data.meshes.new('CVT_Belt')
    me.from_pydata(verts, [], faces)
    me.validate()
    me.update()
    ob = bpy.data.objects.new('CVT_Belt', me)
    ob.data.materials.append(mats['plastic_black'])
    coll.objects.link(ob)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.update()
    return ob


def build_exhaust(coll, mats):
    """Header pipe, big left-hand silencer with heat shield and tip."""
    parts = []
    sy, sz = SPEC['silencer_front'][1], SPEC['silencer_front'][2]
    ey, ez = SPEC['silencer_rear'][1], SPEC['silencer_rear'][2]
    sx = SPEC['silencer_front'][0]
    rr = SPEC['silencer_r']

    # header pipe from the cylinder head up to the silencer
    parts.append(add_tube('Exhaust_Header', [
        (0.075, -0.045, 0.600),
        (0.030, 0.010, 0.660),
        (-0.090, 0.060, 0.660),
        (-0.180, 0.085, 0.615),
        (sx, sy, sz)], 0.030, mats['exhaust_steel'], coll))

    # silencer body
    body = add_cyl('Silencer_Body', rr, ey - sy, (0, 0, 0), axis='Y', seg=32,
                   mat=mats['engine_black'], coll=coll)
    body.location = (sx, (sy + ey) / 2.0, sz)
    parts.append(body)
    # rounded tail cap
    cap = add_cyl('Silencer_Cap', rr * 1.04, 0.055, (0, 0, 0), axis='Y', seg=32,
                  mat=mats['engine_black'], coll=coll)
    cap.location = (sx, ey + 0.020, sz)
    parts.append(cap)
    tip = add_cyl('Silencer_Tip', rr * 0.72, 0.050, (0, 0, 0), axis='Y', seg=24,
                  mat=mats['plastic_black'], coll=coll)
    tip.location = (sx, ey + 0.060, sz)
    parts.append(tip)

    # heat shield (chrome strip wrapped over the top of the can)
    shield = MB()
    prof = []
    n = 13
    for i in range(n):
        a = math.radians(-105 + 210.0 * i / (n - 1))
        prof.append((rr + 0.004, a))
    verts, faces = [], []
    for (r, a) in prof:
        for (yy, rad) in ((sy + 0.030, r), (ey - 0.030, r)):
            verts.append((sx + rad * math.cos(a), yy, sz + rad * math.sin(a)))
    for i in range(n - 1):
        b = i * 2
        faces.append([b, b + 2, b + 3, b + 1])
    me = bpy.data.meshes.new('Heat_Shield')
    me.from_pydata(verts, [], faces)
    me.validate()
    me.update()
    sh = bpy.data.objects.new('Heat_Shield', me)
    sh.data.materials.append(mats['chrome_dull'])
    coll.objects.link(sh)
    sm = sh.modifiers.new('Solidify', 'SOLIDIFY')
    sm.thickness = 0.006
    parts.append(sh)

    # mounting straps
    for yy in (sy + 0.120, ey - 0.110):
        strap = add_cyl('Silencer_Strap', rr + 0.010, 0.022, (0, 0, 0), axis='Y',
                        seg=28, mat=mats['chrome_dull'], coll=coll)
        strap.location = (sx, yy, sz)
        parts.append(strap)

    # spark arrester / tip ring
    parts.append(add_cyl('Silencer_Ring', rr * 0.80, 0.012, (0, 0, 0), axis='Y',
                         seg=24, mat=mats['chrome_dull'], coll=coll))
    parts[-1].location = (sx, ey + 0.088, sz)
    return parts
