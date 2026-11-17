"""
qb_wheels.py - Tyres, rims, hubs, brakes and suspension for the Kiepie Bike.
"""
import math
from mathutils import Vector

from qb_core import (MB, add_cyl, add_box, add_tube, helix, join, to_mesh,
                     smooth_by_angle, set_origin)
from qb_spec import SPEC

TAU = math.pi * 2.0
R = math.radians


# ------------------------------------------------------------------- tyre

def build_tyre(name, center, r_out, hw, coll, mats, rows=2, per_row=16,
               lug_ax=0.058, lug_tan=0.050, lug_rad=0.026, seg=56):
    """Knobby quad tyre: tall sidewall carcass + staggered tread blocks."""
    rr = SPEC['rim_r']
    prof = [
        (rr + 0.004, -hw * 0.60),
        (rr + 0.040, -hw * 0.84),
        (r_out - 0.060, -hw * 1.00),
        (r_out - 0.020, -hw * 0.97),
        (r_out - 0.004, -hw * 0.82),
        (r_out, -hw * 0.70),
        (r_out, hw * 0.70),
        (r_out - 0.004, hw * 0.82),
        (r_out - 0.020, hw * 0.97),
        (r_out - 0.060, hw * 1.00),
        (rr + 0.040, hw * 0.84),
        (rr + 0.004, hw * 0.60),
    ]
    mb = MB()
    mb.revolve(prof, (0, 0, 0), axis='X', seg=seg)
    carcass = mb.to_object(name + '_Carcass', mats['rubber'], coll, smooth=True)

    # --- tread blocks: staggered rows across the crown
    lugs = MB()
    offs = [-0.44, 0.44] if rows == 2 else [-0.44, 0.0, 0.44]
    for ri, off in enumerate(offs):
        # Only the centre row of a THREE-row tyre is staggered at half count.
        # With two rows, ri==1 is the whole right flank and must stay symmetric.
        n = (per_row // 2 if rows == 3 and ri == 1 else per_row)
        phase = (ri % 2) * (TAU / per_row) * 0.5
        for k in range(n):
            a = TAU * k / n + phase
            rr_ = r_out - lug_rad * 0.30
            p = (off * hw, rr_ * math.cos(a), rr_ * math.sin(a))
            lugs.box(p, (lug_ax, lug_tan, lug_rad), rot=(a - math.pi / 2, 0, 0))
    # shoulder blocks
    for ri, off in enumerate((-0.72, 0.72)):
        n = per_row // 2
        phase = (ri % 2) * (TAU / per_row) * 0.5
        for k in range(n):
            a = TAU * k / n + phase
            rr_ = r_out - 0.018
            p = (off * hw, rr_ * math.cos(a), rr_ * math.sin(a))
            lugs.box(p, (lug_ax * 0.8, lug_tan * 0.85, 0.020),
                     rot=(a - math.pi / 2, 0, 0))
    blocks = lugs.to_object(name + '_Tread', mats['rubber'], coll)
    tyre = join([carcass, blocks], name)
    tyre.location = center
    smooth_by_angle(tyre, 40)
    return tyre




def build_rim(name, center, width, coll, mats):
    """Steel quad wheel: flat dished centre panel, hub, beadlock bolt ring."""
    rr = SPEC['rim_r']
    hw = width / 2.0
    mb = MB()
    prof = [
        (rr - 0.018, -hw),
        (rr, -hw + 0.008),
        (rr, hw - 0.008),
        (rr - 0.018, hw),
        (rr - 0.034, hw - 0.012),
        (rr - 0.034, -hw + 0.012),
    ]
    mb.revolve(prof, (0, 0, 0), axis='X', seg=48)
    barrel = mb.to_object(name + '_Barrel', mats['wheel_metal'], coll, smooth=True)
    barrel.location = center
    parts = [barrel]

    # flat outboard face (the big dark disc seen in the reference photos)
    face = add_cyl(name + '_Face', rr - 0.008, 0.013, (0, 0, 0), axis='X', seg=44,
                   mat=mats['wheel_metal'], coll=coll)
    face.location = center + Vector((hw - 0.020, 0, 0))
    parts.append(face)

    # dished centre (inboard)
    panel = add_cyl(name + '_Panel', rr - 0.030, 0.012, (0, 0, 0), axis='X',
                    seg=40, mat=mats['wheel_metal'], coll=coll)
    panel.location = center + Vector((-hw + 0.018, 0, 0))
    parts.append(panel)

    hub = add_cyl(name + '_Hub', 0.052, 0.140, (0, 0, 0), axis='X', seg=24,
                  mat=mats['wheel_metal'], coll=coll)
    hub.location = center
    parts.append(hub)

    hubcap = add_cyl(name + '_HubCap', 0.058, 0.020, (0, 0, 0), axis='X', seg=20,
                     mat=mats['alu'], coll=coll)
    hubcap.location = center + Vector((hw - 0.005, 0, 0))
    parts.append(hubcap)

    # beadlock style bolt ring on the outboard face
    bolts = MB()
    for i in range(16):
        a = TAU * i / 16.0
        bolts.cylinder((0.0, (rr - 0.030) * math.cos(a), (rr - 0.030) * math.sin(a)),
                       0.0105, 0.022, axis='X', seg=8)
    ring = bolts.to_object(name + '_Bolts', mats['alu'], coll)
    ring.location = center + Vector((hw - 0.014, 0, 0))
    parts.append(ring)

    # outer lip (a ring, not a solid disc)
    lipmb = MB()
    lipmb.revolve([(rr - 0.010, -0.010), (rr, -0.008), (rr, 0.008),
                   (rr - 0.010, 0.010), (rr - 0.016, 0.006),
                   (rr - 0.016, -0.006)], (0, 0, 0), axis='X', seg=44)
    lip = lipmb.to_object(name + '_Lip', mats['alu'], coll, smooth=True)
    lip.location = center + Vector((hw - 0.004, 0, 0))
    parts.append(lip)

    # wheel nuts
    nuts = MB()
    for i in range(4):
        a = TAU * i / 4.0 + 0.4
        nuts.cylinder((0.0, 0.036 * math.cos(a), 0.036 * math.sin(a)),
                      0.012, 0.022, axis='X', seg=6)
    nutobj = nuts.to_object(name + '_Nuts', mats['alu'], coll)
    nutobj.location = center + Vector((hw - 0.028, 0, 0))
    parts.append(nutobj)

    rim = join(parts, name)
    smooth_by_angle(rim, 35)
    return rim


def build_brake(name, center, coll, mats, r=0.098, side=1):
    disc = add_cyl(name + '_Disc', r, 0.007, (0, 0, 0), axis='X', seg=36,
                   mat=mats['alu'], coll=coll)
    disc.location = center
    cal = add_box(name + '_Caliper', (0.045, 0.075, 0.115),
                  (center.x + side * 0.028, center.y - r * 0.75, center.z),
                  rot=(0, 0, 0), mat=mats['engine_black'], coll=coll, bevel=0.006)
    return disc, cal


# ------------------------------------------------------------------ wheel
def build_wheel(side, front, coll, mats):
    """side: -1 = left, +1 = right. Returns (wheel_obj, knuckle_obj|None)."""
    tag = ('F' if front else 'R') + ('L' if side < 0 else 'R')
    if front:
        cx = SPEC['front_hub_x']
        cy = SPEC['front_axle_y']
        cz = SPEC['front_axle_z']
        r_out = SPEC['front_tyre_r']
        hw = SPEC['front_tyre_hw']
        rows, per_row = 2, 15
    else:
        cx = SPEC['rear_hub_x']
        cy = SPEC['rear_axle_y']
        cz = SPEC['rear_axle_z']
        r_out = SPEC['rear_tyre_r']
        hw = SPEC['rear_tyre_hw']
        rows, per_row = 2, 17

    center = Vector((side * cx, cy, cz))
    tyre = build_tyre('Tyre_' + tag, center, r_out, hw, coll, mats,
                      rows=rows, per_row=per_row,
                      lug_ax=0.056 if front else 0.062,
                      lug_tan=0.048 if front else 0.052,
                      lug_rad=0.024 if front else 0.028)
    rim = build_rim('Rim_' + tag, center, hw * 1.30, coll, mats)
    disc, cal = build_brake('Brake_' + tag, center, coll, mats, side=side)
    axle = add_cyl('Axle_' + tag, 0.030, 0.150, (0, 0, 0), axis='X', seg=16,
                   mat=mats['alu'], coll=coll)
    axle.location = center + Vector((-side * 0.055, 0, 0))

    wheel = join([tyre, rim, disc, axle], 'Wheel_' + tag)
    wheel.location = center
    set_origin(wheel, center)
    return wheel, cal


# ------------------------------------------------------------- suspension
def build_front_suspension(side, coll, mats):
    """Double A-arm front suspension with coil-over shock (white spring)."""
    tag = 'L' if side < 0 else 'R'
    cx = SPEC['front_hub_x']
    ay = SPEC['front_axle_y']
    az = SPEC['front_axle_z']
    lz = SPEC['lower_arm_z']
    uz = SPEC['upper_arm_z']
    lpx = SPEC['lower_pivot_x']
    upx = SPEC['upper_pivot_x']

    knuckle_c = Vector((side * (cx - 0.085), ay, az + 0.03))
    knuckle = add_box('Knuckle_F' + tag, (0.075, 0.115, 0.230),
                      tuple(knuckle_c), mat=mats['alu'], coll=coll, bevel=0.010)

    # lower A-arm (V shape)
    lp = Vector((side * lpx, ay + 0.115, lz))
    la1 = Vector((side * (cx - 0.075), ay - 0.085, lz))
    la2 = Vector((side * (cx - 0.075), ay + 0.085, lz))
    add_tube('Arm_Lower_F' + tag, [tuple(lp), tuple(la1)], 0.022, mats['chrome_dull'], coll)
    add_tube('Arm_Lower_F' + tag + '_b', [tuple(lp), tuple(la2)], 0.022, mats['chrome_dull'], coll)
    add_cyl('Pivot_Lower_F' + tag, 0.026, 0.075, tuple(lp), axis='X', seg=14,
            mat=mats['chrome'], coll=coll)

    # upper A-arm
    up = Vector((side * upx, ay + 0.100, uz))
    ua1 = Vector((side * (cx - 0.085), ay - 0.060, uz))
    ua2 = Vector((side * (cx - 0.085), ay + 0.060, uz))
    add_tube('Arm_Upper_F' + tag, [tuple(up), tuple(ua1)], 0.018, mats['chrome_dull'], coll)
    add_tube('Arm_Upper_F' + tag + '_b', [tuple(up), tuple(ua2)], 0.018, mats['chrome_dull'], coll)

    # coil-over shock: chrome body + white spring
    top = Vector((side * 0.300, SPEC['shock_top_y'], SPEC['shock_top_z']))
    bot = Vector((side * (cx - 0.055), ay + 0.030, az + 0.115))
    add_tube('Shock_Body_F' + tag, [tuple(top), tuple(bot)], 0.030,
             mats['chrome_dull'], coll)
    helix('Shock_Spring_F' + tag, top.lerp(bot, 0.12), top.lerp(bot, 0.72),
          0.062, 8.0, 0.0135, mats['spring_white'], coll)
    add_cyl('Shock_Mount_Top_F' + tag, 0.032, 0.070, tuple(top), axis='X', seg=14,
            mat=mats['alu'], coll=coll)
    add_cyl('Shock_Mount_Bot_F' + tag, 0.030, 0.060, tuple(bot), axis='X', seg=14,
            mat=mats['alu'], coll=coll)

    # steering tie rod
    tie_a = Vector((side * 0.085, ay + 0.185, uz + 0.085))
    tie_b = Vector((side * (cx - 0.100), ay + 0.030, uz - 0.030))
    add_tube('TieRod_F' + tag, [tuple(tie_a), tuple(tie_b)], 0.012,
             mats['chrome'], coll)

    return knuckle


def build_rear_suspension(side, coll, mats):
    """Solid rear axle on dual trailing arms + single left shock."""
    tag = 'L' if side < 0 else 'R'
    cx = SPEC['rear_hub_x']
    ay = SPEC['rear_axle_y']
    az = SPEC['rear_axle_z']

    upper = Vector((side * 0.150, 0.300, 0.430))
    lower = Vector((side * 0.160, 0.290, 0.290))
    axle_a = Vector((side * (cx - 0.060), ay + 0.020, az + 0.030))
    axle_b = Vector((side * (cx - 0.060), ay - 0.020, az + 0.030))
    add_tube('Arm_Rear_Up_' + tag, [tuple(upper), tuple(axle_a)], 0.020,
             mats['chrome_dull'], coll)
    add_tube('Arm_Rear_Lo_' + tag, [tuple(lower), tuple(axle_b)], 0.020,
             mats['chrome_dull'], coll)
    add_cyl('Pivot_Rear_Up_' + tag, 0.024, 0.070, tuple(upper), axis='X', seg=14,
            mat=mats['alu'], coll=coll)

    # rear shock (left hand side, as per the reference bike)
    if side < 0:
        top = Vector((-0.190, 0.300, 0.690))
        bot = Vector((-(cx - 0.070), ay - 0.020, az + 0.045))
        add_tube('Shock_Body_R', [tuple(top), tuple(bot)], 0.028,
                 mats['chrome_dull'], coll)
        helix('Shock_Spring_R', top.lerp(bot, 0.12), top.lerp(bot, 0.70),
              0.058, 7.5, 0.0130, mats['spring_white'], coll)
    return None
