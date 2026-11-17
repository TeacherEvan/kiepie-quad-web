"""
qb_body.py - Frame, body plastics, seat, handlebars and controls.
"""
import math
from mathutils import Vector

from qb_core import (MB, add_cyl, add_box, add_tube, helix, join, to_mesh,
                     smooth_by_angle, set_origin)
from qb_spec import SPEC

TAU = math.pi * 2.0
R = math.radians


# ------------------------------------------------------------------- frame
def build_frame(coll, mats):
    """Chromed perimeter frame + skid plate + subframe."""
    parts = []
    for side in (-1, 1):
        s = 'L' if side < 0 else 'R'
        # upper perimeter rail: steering head -> down -> back -> rear subframe
        rail = [
            (side * 0.075, -0.330, 0.735),
            (side * 0.150, -0.470, 0.600),
            (side * 0.165, -0.520, 0.420),
            (side * 0.170, -0.100, 0.470),
            (side * 0.165, 0.300, 0.470),
            (side * 0.175, 0.620, 0.520),
            (side * 0.205, 0.960, 0.605),
        ]
        parts.append(add_tube('Frame_Rail_' + s, rail, 0.023, mats['chrome_dull'], coll))
        # lower cradle rail
        cradle = [
            (side * 0.140, -0.430, 0.300),
            (side * 0.160, -0.180, 0.245),
            (side * 0.165, 0.150, 0.250),
            (side * 0.165, 0.430, 0.330),
        ]
        parts.append(add_tube('Frame_Cradle_' + s, cradle, 0.021, mats['chrome_dull'], coll))
        # front down tube from steering head to front crossmember
        parts.append(add_tube('Frame_Down_' + s, [
            (side * 0.075, -0.330, 0.735),
            (side * 0.135, -0.420, 0.560),
            (side * 0.150, -0.470, 0.340),
        ], 0.022, mats['chrome_dull'], coll))
        # rear subframe brace
        parts.append(add_tube('Frame_Brace_' + s, [
            (side * 0.170, 0.300, 0.470),
            (side * 0.190, 0.880, 0.585),
        ], 0.017, mats['chrome_dull'], coll))

    # cross members
    for y, z, half, r in ((-0.470, 0.340, 0.155, 0.021),
                          (-0.180, 0.250, 0.165, 0.019),
                          (0.150, 0.252, 0.168, 0.019),
                          (0.430, 0.330, 0.168, 0.019),
                          (-0.300, 0.720, 0.080, 0.020)):
        parts.append(add_tube('Frame_Cross_%d' % int(abs(y) * 1000), [
            (-half, y, z), (half, y, z)], r, mats['chrome_dull'], coll))

    # steering head
    parts.append(add_tube('Steering_Head', [
        (0.0, -0.365, 0.560), (0.0, -0.280, 0.820)], 0.032, mats['chrome_dull'], coll))
    # bash plate
    plate = add_box('Bash_Plate', (0.300, 0.640, 0.014), (0.0, -0.120, 0.230),
                    mat=mats['engine_black'], coll=coll, bevel=0.010)
    parts.append(plate)
    return parts



def build_front_bumper(coll, mats):
    """Chrome tubular front bumper / brush guard."""
    parts = []
    hoop = [
        (-0.320, -0.700, 0.290),
        (-0.330, -0.960, 0.330),
        (-0.290, -1.090, 0.430),
        (-0.150, -1.140, 0.475),
        (0.000, -1.155, 0.485),
        (0.150, -1.140, 0.475),
        (0.290, -1.090, 0.430),
        (0.330, -0.960, 0.330),
        (0.320, -0.700, 0.290),
    ]
    parts.append(add_tube('Bumper_Hoop', hoop, 0.023, mats['chrome'], coll))
    # lower cross tube
    parts.append(add_tube('Bumper_Low', [
        (-0.270, -1.045, 0.215), (0.270, -1.045, 0.215)], 0.020, mats['chrome'], coll))
    # mid cross tube
    parts.append(add_tube('Bumper_Mid', [
        (-0.315, -0.960, 0.330), (0.315, -0.960, 0.330)], 0.018, mats['chrome'], coll))
    # back stays to frame
    for side in (-1, 1):
        parts.append(add_tube('Bumper_Stay_%d' % side, [
            (side * 0.318, -0.715, 0.295),
            (side * 0.210, -0.560, 0.320),
            (side * 0.165, -0.470, 0.360)], 0.020, mats['chrome'], coll))
    return parts



def build_nerf_bars(coll, mats):
    """Chrome side nerf bars / engine guards."""
    parts = []
    for side in (-1, 1):
        s = 'L' if side < 0 else 'R'
        bar = [
            (side * 0.330, -0.690, 0.250),
            (side * 0.348, -0.700, 0.360),
            (side * 0.352, -0.620, 0.500),
            (side * 0.348, -0.400, 0.545),
            (side * 0.340, -0.180, 0.530),
            (side * 0.330, -0.030, 0.440),
            (side * 0.320, 0.040, 0.320),
        ]
        parts.append(add_tube('Nerf_' + s, bar, 0.021, mats['chrome'], coll))
        # mounting tabs back to the frame
        parts.append(add_tube('Nerf_Tab_' + s, [
            (side * 0.345, -0.680, 0.330), (side * 0.190, -0.600, 0.300)],
            0.014, mats['chrome_dull'], coll))
        parts.append(add_tube('Nerf_Tab2_' + s, [
            (side * 0.330, 0.020, 0.330), (side * 0.190, 0.080, 0.320)],
            0.014, mats['chrome_dull'], coll))
    return parts


def fender_grid(center, r_f, phi0, phi1, x_in, x_out, nphi=16, nx=7,
                taper=0.25, drop=0.0, arc_boost=0.0, dome=0.028, skirt=0.070):
    """Fender shell over a wheel (axle along X).

    The shell is a section of a cylinder of radius r_f about the axle so it
    hugs the tyre, with a crowned cross section and a down-turned outer lip.
    phi: 0 = top of the wheel, negative = front of the wheel.
    """
    cx, cy, cz = center
    xc = (x_in + x_out) / 2.0
    hw = (x_out - x_in) / 2.0
    grid = []
    for i in range(nphi):
        t = i / (nphi - 1.0)
        phi = phi0 + (phi1 - phi0) * t
        end = abs(2.0 * t - 1.0) ** 2.0        # 0 centre .. 1 at the arc ends
        shrink = 1.0 - taper * end
        row = []
        for j in range(nx):
            u = j / (nx - 1.0)
            x = xc + (2.0 * u - 1.0) * hw * shrink
            y = cy + r_f * math.sin(phi)
            z = cz + r_f * math.cos(phi)
            z += dome * (1.0 - (2.0 * u - 1.0) ** 2)      # crowned cross section
            if u > 0.72:                                  # outer lip turns down
                z -= skirt * ((u - 0.72) / 0.28) ** 1.6
            z -= 0.030 * end                              # rolled ends
            row.append((x, y, z))
        grid.append(row)
    return grid


def build_fender(name, center, r_f, phi0, phi1, x_in, x_out, coll, mat,
                 thickness=0.012, **kw):
    grid = fender_grid(center, r_f, phi0, phi1, x_in, x_out, **kw)
    mb = MB()
    mb.shell(grid)
    ob = mb.to_object(name, mat, coll)
    m = ob.modifiers.new('Solidify', 'SOLIDIFY')
    m.thickness = thickness
    m.offset = 0.0
    smooth_by_angle(ob, 40)
    return ob



def build_fender_stripe(name, center, r_f, phi0, phi1, x_in, x_out, coll,
                         mat, thickness=0.004, swoosh=0.0, offset=0.008, **kw):
    """Graphic stripe lying just proud of the fender surface.

    swoosh > 0 slides the inner edge of the stripe along the arc, which gives
    the swept "flame" look used on the reference bodywork.
    """
    nphi = kw.pop('nphi', 14)
    nx = kw.pop('nx', 8)
    grid = []
    cx, cy, cz = center
    xc = (x_in + x_out) / 2.0
    hw = (x_out - x_in) / 2.0
    for i in range(nphi):
        t = i / (nphi - 1.0)
        phi = phi0 + (phi1 - phi0) * t
        shift = swoosh * t
        row = []
        for j in range(nx):
            u = j / (nx - 1.0)
            x = xc + (2.0 * u - 1.0) * hw + shift
            y = cy + (r_f + offset) * math.sin(phi)
            z = cz + (r_f + offset) * math.cos(phi)
            z += kw.get('dome', 0.03) * (1.0 - (2.0 * u - 1.0) ** 2)
            if u > 0.72:
                z -= kw.get('skirt', 0.075) * ((u - 0.72) / 0.28) ** 1.6
            row.append((x, y, z))
        grid.append(row)
    mb = MB()
    mb.shell(grid)
    ob = mb.to_object(name, mat, coll)
    m = ob.modifiers.new('Solidify', 'SOLIDIFY')
    m.thickness = thickness
    m.offset = 1.0
    return ob


def build_plastics(coll, mats):
    parts = []
    # ---- front fenders: slim wings over the front wheels (photo-matched)
    for side in (-1, 1):
        s = 'L' if side < 0 else 'R'
        c = (side * SPEC['front_hub_x'], SPEC['front_axle_y'], SPEC['front_axle_z'])
        r_f = SPEC['front_tyre_r'] + 0.030
        x_in, x_out = side * 0.430, side * 0.655
        parts.append(build_fender('Fender_Front_' + s, c, r_f,
                                  R(-48), R(30), min(x_in, x_out), max(x_in, x_out),
                                  coll, mats['paint_blue'], thickness=0.012,
                                  nphi=20, nx=10, taper=0.40, dome=0.026,
                                  skirt=0.055))
        lo, hi = min(x_in, x_out), max(x_in, x_out)
        w = hi - lo
        parts.append(build_fender_stripe('Stripe_Front_' + s, c, r_f,
                                         R(-46), R(26), lo + 0.05 * w, lo + 0.34 * w,
                                         coll, mats['graphic_lime'],
                                         nphi=16, nx=6, swoosh=-0.055 * side, dome=0.030,
                                         skirt=0.075))
        parts.append(build_fender_stripe('Stripe2_Front_' + s, c, r_f,
                                         R(-16), R(14), lo + 0.38 * w, lo + 0.52 * w,
                                         coll, mats['graphic_white'],
                                         nphi=12, nx=5, swoosh=0.045 * side, dome=0.030,
                                         skirt=0.075))
        # fender support strut down to the frame
        parts.append(add_tube('Fender_Strut_F' + s, [
            (side * 0.360, SPEC['front_axle_y'] + 0.040, SPEC['front_axle_z'] + 0.115),
            (side * 0.320, SPEC['front_axle_y'] + 0.030, SPEC['front_axle_z'] + 0.010)],
            0.013, mats['chrome_dull'], coll))

    # ---- rear fenders: slim arch shells, wheel stays visible from behind
    for side in (-1, 1):
        s = 'L' if side < 0 else 'R'
        c = (side * SPEC['rear_hub_x'], SPEC['rear_axle_y'], SPEC['rear_axle_z'])
        r_f = SPEC['rear_tyre_r'] + 0.036
        x_in, x_out = side * 0.400, side * 0.735
        parts.append(build_fender('Fender_Rear_' + s, c, r_f,
                                  R(-50), R(66), min(x_in, x_out), max(x_in, x_out),
                                  coll, mats['paint_blue'], thickness=0.013,
                                  nphi=24, nx=11, taper=0.36, dome=0.028,
                                  skirt=0.062))
        lo, hi = min(x_in, x_out), max(x_in, x_out)
        w = hi - lo
        parts.append(build_fender_stripe('Stripe_Rear_' + s, c, r_f,
                                         R(-28), R(56), lo + 0.06 * w, lo + 0.36 * w,
                                         coll, mats['graphic_lime'],
                                         nphi=16, nx=6, swoosh=-0.070 * side, dome=0.032,
                                         skirt=0.080))
        parts.append(build_fender_stripe('Stripe2_Rear_' + s, c, r_f,
                                         R(-6), R(40), lo + 0.40 * w, lo + 0.54 * w,
                                         coll, mats['graphic_white'],
                                         nphi=12, nx=5, swoosh=0.060 * side, dome=0.032,
                                         skirt=0.080))
        parts.append(add_tube('Fender_Strut_R' + s, [
            (side * 0.340, SPEC['rear_axle_y'] - 0.060, SPEC['rear_axle_z'] + 0.120),
            (side * 0.300, SPEC['rear_axle_y'] - 0.090, SPEC['rear_axle_z'] + 0.010)],
            0.013, mats['chrome_dull'], coll))

    # ---- small side panels in front of the rear fenders
    for side in (-1, 1):
        s = 'L' if side < 0 else 'R'
        panel = MB()
        rows = []
        ny, nz = 9, 5
        for i in range(ny):
            ty = i / (ny - 1.0)
            y = -0.105 + ty * 0.330
            row = []
            for j in range(nz):
                tz = j / (nz - 1.0)
                z = 0.440 + tz * 0.190
                bulge = 0.040 * math.sin(math.pi * min(1.0, max(0.0, ty))) \
                    * (1.0 - abs(2.0 * tz - 1.0))
                x = side * (0.215 + bulge)
                row.append((x, y, z))
            rows.append(row)
        panel.shell(rows)
        ob = panel.to_object('Side_Panel_' + s, mats['paint_blue'], coll)
        m = ob.modifiers.new('Solidify', 'SOLIDIFY')
        m.thickness = 0.010
        smooth_by_angle(ob, 40)
        parts.append(ob)

        stripe = MB()
        rows = []
        for i in range(7):
            ty = i / 6.0
            y = -0.060 + ty * 0.240
            row = []
            for j in range(3):
                tz = j / 2.0
                z = 0.500 + tz * 0.090
                bulge = 0.040 * math.sin(math.pi * min(1.0, max(0.0, (y + 0.105) / 0.330))) \
                    * (1.0 - abs(2.0 * tz - 1.0))
                x = side * (0.215 + bulge + 0.007)
                row.append((x, y, z))
            rows.append(row)
        stripe.shell(rows)
        st = stripe.to_object('Side_Stripe_' + s, mats['graphic_lime'], coll)
        m2 = st.modifiers.new('Solidify', 'SOLIDIFY')
        m2.thickness = 0.004
        parts.append(st)

    # ---- nose cowl carrying the headlight
    cowl = MB()
    rows = []
    ny, nx = 10, 11
    for i in range(ny):
        t = i / (ny - 1.0)
        y = -0.585 + t * 0.280
        row = []
        for j in range(nx):
            u = j / (nx - 1.0)
            x = -0.175 + u * 0.350
            edge = math.cos(math.pi * (u - 0.5)) ** 0.8
            z = 0.600 + 0.165 * (1.0 - t) ** 1.5 + 0.075 * edge
            row.append((x, y, z))
        rows.append(row)
    cowl.shell(rows)
    cob = cowl.to_object('Nose_Cowl', mats['paint_blue'], coll)
    m = cob.modifiers.new('Solidify', 'SOLIDIFY')
    m.thickness = 0.012
    smooth_by_angle(cob, 40)
    parts.append(cob)

    # ---- rear centre section (behind the seat) with tail light
    tail = MB()
    rows = []
    ny, nx = 7, 7
    for i in range(ny):
        t = i / (ny - 1.0)
        y = 0.330 + t * 0.150
        row = []
        for j in range(nx):
            u = j / (nx - 1.0)
            x = -0.150 + u * 0.300
            z = 0.680 - 0.065 * t ** 1.6 + 0.025 * (1.0 - abs(2.0 * u - 1.0) ** 2)
            row.append((x, y, z))
        rows.append(row)
    tail.shell(rows)
    tob = tail.to_object('Rear_Centre', mats['paint_blue'], coll)
    m = tob.modifiers.new('Solidify', 'SOLIDIFY')
    m.thickness = 0.012
    smooth_by_angle(tob, 40)
    parts.append(tob)

    return parts



def build_lights(coll, mats):
    parts = []
    # headlight recessed in the nose cowl
    bezel = add_box('Headlight_Bezel', (0.190, 0.030, 0.120), (0.0, -0.596, 0.678),
                    rot=(R(-24), 0, 0), mat=mats['chrome_dull'], coll=coll,
                    bevel=0.008)
    lens = add_box('Headlight_Lens', (0.160, 0.022, 0.092), (0.0, -0.610, 0.676),
                   rot=(R(-24), 0, 0), mat=mats['headlight'], coll=coll, bevel=0.006)
    parts += [bezel, lens]
    # small running lights either side of the headlight
    for side in (-1, 1):
        s = 'L' if side < 0 else 'R'
        parts.append(add_box('Marker_F' + s, (0.040, 0.020, 0.050),
                             (side * 0.165, -0.600, 0.700), rot=(R(-24), 0, 0),
                             mat=mats['reflector_amber'], coll=coll, bevel=0.005))
    # tail light on the rear panel
    parts.append(add_box('Taillight', (0.155, 0.026, 0.058), (0.0, 0.500, 0.632),
                         rot=(R(20), 0, 0), mat=mats['taillight'], coll=coll,
                         bevel=0.006))
    parts.append(add_box('Taillight_Bezel', (0.180, 0.020, 0.076), (0.0, 0.490, 0.634),
                         rot=(R(20), 0, 0), mat=mats['plastic_black'], coll=coll,
                         bevel=0.006))
    return parts


def build_seat(coll, mats):
    """Black saddle running between the rear fenders."""
    mb = MB()
    ny, nx = 18, 15
    rows = []
    for i in range(ny):
        t = i / (ny - 1.0)
        y = SPEC['seat_front_y'] + t * (SPEC['seat_rear_y'] - SPEC['seat_front_y'])
        # narrow nose, wide tail
        w = 0.105 + 0.085 * (t ** 0.45)
        row = []
        for j in range(nx):
            u = j / (nx - 1.0)
            x = -w + 2.0 * w * u
            crown = math.cos(math.pi * (u - 0.5)) ** 0.35
            z = SPEC['seat_top_z'] - 0.060 * (1.0 - crown) ** 1.3
            # rider dish
            z -= 0.026 * math.exp(-((u - 0.5) ** 2) / 0.045) * math.sin(math.pi * t)
            # raised nose, slight drop at the tail
            z += 0.020 * (1.0 - t) ** 3.0
            z -= 0.030 * max(0.0, t - 0.80) / 0.20
            row.append((x, y, z))
        rows.append(row)
    mb.shell(rows)
    ob = mb.to_object('Seat', mats['seat'], coll)
    m = ob.modifiers.new('Solidify', 'SOLIDIFY')
    m.thickness = 0.042
    m.offset = -1.0
    smooth_by_angle(ob, 45)
    return [ob]


def build_controls(coll, mats):
    parts = []
    hx = SPEC['handlebar_x']
    hy = SPEC['handlebar_y']
    hz = SPEC['handlebar_z']

    # ---- steering column: stem, triple clamps, bar risers
    stem_top = Vector((0.0, -0.285, 0.815))
    stem_bot = Vector((0.0, -0.360, 0.610))
    parts.append(add_tube('Steering_Stem', [tuple(stem_bot), tuple(stem_top)],
                           0.024, mats['chrome_dull'], coll))
    parts.append(add_box('Triple_Clamp_Bottom', (0.115, 0.085, 0.045),
                          (0.0, -0.352, 0.630), mat=mats['alu'], coll=coll,
                          bevel=0.010))
    parts.append(add_box('Triple_Clamp_Top', (0.135, 0.100, 0.038),
                          (0.0, -0.296, 0.812), mat=mats['alu'], coll=coll,
                          bevel=0.010))
    for side in (-1, 1):
        parts.append(add_tube('Bar_Riser_%d' % side, [
            (side * 0.058, -0.300, 0.820),
            (side * 0.068, -0.330, 0.930),
            (side * 0.075, -0.345, 0.975)], 0.018, mats['chrome_dull'], coll))
        parts.append(add_cyl('Bar_Riser_Clamp_%d' % side, 0.026, 0.036,
                             (side * 0.070, -0.336, 0.945), axis='Y', seg=12,
                             mat=mats['alu'], coll=coll))

    for side in (-1, 1):
        s = 'L' if side < 0 else 'R'
        bar = [
            (side * 0.075, -0.345, 0.978),
            (side * 0.190, -0.330, 0.990),
            (side * 0.330, -0.345, 0.995),
            (side * 0.430, -0.375, 0.985),
            (side * 0.505, -0.405, 0.972),
            (side * 0.545, -0.418, 0.962),
        ]
        parts.append(add_tube('Handlebar_' + s, bar, 0.015, mats['chrome'], coll))
        grip = add_cyl('Grip_' + s, 0.021, 0.120, (0, 0, 0), axis='X', seg=18,
                       mat=mats['plastic_grip'], coll=coll)
        grip.location = (side * 0.492, hy - 0.083, hz - 0.030)
        grip.rotation_euler = (R(96), 0, 0)
        parts.append(grip)
        cap = add_cyl('Bar_End_' + s, 0.022, 0.016, (0, 0, 0), axis='X', seg=16,
                      mat=mats['chrome_dull'], coll=coll)
        cap.location = (side * 0.560, hy - 0.092, hz - 0.032)
        cap.rotation_euler = (R(96), 0, 0)
        parts.append(cap)
        parts.append(add_box('Switch_Housing_' + s, (0.055, 0.065, 0.055),
                             (side * 0.425, hy - 0.062, hz - 0.022),
                             mat=mats['plastic_black'], coll=coll, bevel=0.010))
        lev = [
            (side * 0.450, hy - 0.098, hz - 0.036),
            (side * 0.405, hy - 0.155, hz - 0.050),
            (side * 0.330, hy - 0.185, hz - 0.058),
        ]
        parts.append(add_tube('Lever_' + s, lev, 0.009, mats['chrome_dull'], coll))
        parts.append(add_cyl('Lever_Perch_' + s, 0.021, 0.052,
                             (side * 0.450, hy - 0.090, hz - 0.034), axis='X', seg=12,
                             mat=mats['chrome_dull'], coll=coll))

    # crossbar pad
    parts.append(add_box('Bar_Pad', (0.150, 0.085, 0.042), (0.0, -0.330, 1.005),
                         mat=mats['plastic_black'], coll=coll, bevel=0.014))
    # instrument pod
    parts.append(add_box('Instrument', (0.125, 0.055, 0.072), (0.0, -0.395, 1.030),
                         rot=(R(-20), 0, 0), mat=mats['plastic_black'], coll=coll,
                         bevel=0.010))
    parts.append(add_box('Instrument_Lens', (0.095, 0.010, 0.048),
                         (0.0, -0.425, 1.034), rot=(R(-20), 0, 0),
                         mat=mats['glass_dark'], coll=coll, bevel=0.004))
    # ignition switch
    parts.append(add_cyl('Ignition', 0.021, 0.030, (0.105, -0.360, 0.995),
                         axis='X', seg=14, mat=mats['chrome_dull'], coll=coll))
    return parts


def build_cables(coll, mats):
    """Throttle / brake cables and hoses."""
    parts = []
    hy = SPEC['handlebar_y']
    hz = SPEC['handlebar_z']
    parts.append(add_tube('Throttle_Cable', [
        (0.470, hy - 0.090, hz - 0.055),
        (0.400, hy - 0.180, hz - 0.090),
        (0.300, hy - 0.330, 0.720),
        (0.180, -0.480, 0.660),
        (0.130, -0.380, 0.610)], 0.007, mats['plastic_black'], coll))
    parts.append(add_tube('Brake_Cable_L', [
        (-0.470, hy - 0.090, hz - 0.055),
        (-0.420, hy - 0.200, hz - 0.120),
        (-0.330, hy - 0.330, 0.700),
        (-0.300, -0.520, 0.560),
        (-0.320, -0.640, 0.360),
        (-0.470, -0.700, 0.320)], 0.006, mats['plastic_black'], coll))
    parts.append(add_tube('Brake_Cable_R', [
        (0.470, hy - 0.090, hz - 0.055),
        (0.430, hy - 0.210, hz - 0.130),
        (0.340, hy - 0.340, 0.690),
        (0.330, -0.540, 0.540),
        (0.330, -0.650, 0.340),
        (0.470, -0.700, 0.320)], 0.006, mats['plastic_black'], coll))
    return parts


def build_footpegs(coll, mats):
    parts = []
    for side in (-1, 1):
        s = 'L' if side < 0 else 'R'
        px = SPEC['peg_x']
        py = SPEC['peg_y']
        pz = SPEC['peg_z']
        parts.append(add_cyl('Peg_' + s, 0.017, 0.145, (0, 0, 0), axis='X', seg=14,
                             mat=mats['chrome_dull'], coll=coll))
        parts[-1].location = (side * px, py, pz)
        parts.append(add_box('Peg_Bracket_' + s, (0.070, 0.075, 0.090),
                             (side * (px - 0.075), py, pz - 0.010),
                             mat=mats['chrome_dull'], coll=coll, bevel=0.010))
        parts.append(add_tube('Peg_Link_' + s, [
            (side * (px - 0.050), py, pz), (side * 0.190, py + 0.040, pz - 0.020)],
            0.016, mats['chrome_dull'], coll))
    return parts



def build_decals(coll, mats):
    """Decals as image-textured quads (best practice; no geometry text)."""
    from qb_core import add_decal_plane, make_image_material
    import os, math
    PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    blaster_mat = make_image_material('Decal_Blaster_Mat', os.path.join(PROJECT, 'assets', 'decal_blaster.png'), emission_strength=0.55)
    gaming_mat = make_image_material('Decal_Gaming_Mat', os.path.join(PROJECT, 'assets', 'decal_gaming.png'), emission_strength=0.6)
    parts = []
    for side in (-1, 1):
        s = 'L' if side < 0 else 'R'
        d = (0, 1, 0) if side > 0 else (0, -1, 0)
        # BLASTER across the flanks, reading front-to-back on both sides
        parts.append(add_decal_plane('Decal_BLASTER_' + s, (0.280, 0.060),
                                     (side * 0.266, 0.055, 0.545), d, (0, 0, 1),
                                     blaster_mat, coll))
        # GAMING along the arc tangent of the rear fender's outer flank
        phi = math.radians(20)
        r_f = SPEC['rear_tyre_r'] + 0.036 + 0.008
        px = side * 0.733
        py = SPEC['rear_axle_y'] + r_f * math.sin(phi)
        pz = SPEC['rear_axle_z'] + r_f * math.cos(phi)
        tdir = (0, side * math.cos(phi), -side * math.sin(phi))
        up = (0, math.sin(phi), math.cos(phi))
        parts.append(add_decal_plane('Decal_GAMING_' + s, (0.250, 0.060),
                                     (px, py, pz), tdir, up, gaming_mat, coll))
    return parts


def build_number_plates(coll, mats):
    """'Kie-poesie' number plates, front and rear (image-textured quads)."""
    from qb_core import add_decal_plane, make_image_material, add_box
    import os
    PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    plate_mat = make_image_material('Number_Plate_Mat',
                                    os.path.join(PROJECT, 'assets', 'number_plate.png'),
                                    emission_strength=0.55)
    parts = []
    # front plate: below the headlight, faces forward; width along X, up along Z
    parts.append(add_decal_plane('Plate_Front', (0.300, 0.094),
                                 (0.0, -0.622, 0.548),
                                 (1, 0, 0), (0, 0, 1),
                                 plate_mat, coll))
    parts.append(add_box('Plate_Front_Bracket', (0.240, 0.012, 0.075),
                         (0.0, -0.610, 0.548), rot=(R(-18), 0, 0),
                         mat=mats['plastic_black'], coll=coll, bevel=0.006))
    # rear plate: behind the tail, faces rearward; width along -X so text reads correctly from behind
    parts.append(add_decal_plane('Plate_Rear', (0.300, 0.094),
                                 (0.0, 0.484, 0.572),
                                 (-1, 0, 0), (0, 0, 1),
                                 plate_mat, coll))
    parts.append(add_box('Plate_Rear_Bracket', (0.240, 0.012, 0.075),
                         (0.0, 0.474, 0.572), rot=(R(15), 0, 0),
                         mat=mats['plastic_black'], coll=coll, bevel=0.006))
    return parts
