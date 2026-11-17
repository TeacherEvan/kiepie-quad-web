"""
qb_weapons.py - Two symmetric side-mounted cannons for the Kiepie Bike.

Each assembly is built entirely from closed primitives (capped cylinders,
closed boxes and capped tubes) so the watertight / manifold gates keep
passing.  Barrels point toward the FRONT of the bike (Blender -Y).

The authoritative muzzle anchors are the ``Cannon_Bore_L`` / ``Cannon_Bore_R``
MESHES created below (~line 105); Godot reads their node transforms at runtime
to spawn muzzle flashes and projectiles.  The ``Muzzle_L`` / ``Muzzle_R`` EMPTY
objects are retained as authoring aids / a defensive fallback only — use the
bore meshes, whose transforms survive every export path.

Primary dimensions come from SPEC (qb_spec.py); local offsets are kept inline.
"""
import math

from qb_core import add_box, add_cyl, add_tube, empty
from qb_spec import SPEC

R = math.radians


def build_cannons(coll, mats):
    """Build L/R cannon assemblies plus the two Muzzle spawn empties.

    Returns the list of mesh objects created (the empties are returned via
    their names in ``bpy.data.objects`` and parented by build_bike()).
    """
    x = SPEC['cannon_side_x']
    my = SPEC['cannon_mount_y']
    bz = SPEC['cannon_barrel_z']
    br = SPEC['cannon_barrel_r']
    bl = SPEC['cannon_barrel_len']
    mrr = SPEC['cannon_muzzle_ring_r']
    mrd = SPEC['cannon_muzzle_ring_depth']
    brr = SPEC['cannon_breech_r']
    brl = SPEC['cannon_breech_len']
    bw = SPEC['cannon_bracket_w']
    bd = SPEC['cannon_bracket_depth']
    bh = SPEC['cannon_bracket_h']
    arm_r = SPEC['cannon_arm_r']
    rib_r = SPEC['cannon_rib_r']
    rib_d = SPEC['cannon_rib_depth']
    bolt_r = SPEC['cannon_bolt_r']
    bolt_len = SPEC['cannon_bolt_len']
    bore_r = SPEC['cannon_bore_r']
    bore_d = SPEC['cannon_bore_depth']

    parts = []
    tip_y = my - bl                      # forward (-Y) muzzle face

    for side in (-1, 1):
        s = 'L' if side < 0 else 'R'
        cx = side * x

        # ---- mounting bracket: solid block from the frame out to the gun
        bracket = add_box('Cannon_Bracket_' + s, (bw, bd, bh),
                          (cx, my, bz - 0.02),
                          mat=mats['engine_black'], coll=coll, bevel=0.008)
        parts.append(bracket)

        # ---- support arms tying the bracket back into the chassis rail
        for i, dz in enumerate((-bh * 0.30, bh * 0.30)):
            parts.append(add_tube('Cannon_Arm_%s_%d' % (s, i), [
                (side * (x - 0.02), my + 0.02, bz + dz),
                (side * 0.170, my + 0.10, bz + dz - 0.02),
            ], arm_r, mats['chrome_dull'], coll))

        # ---- bolt heads on the outboard face of the bracket
        for i, oy in enumerate((-bd * 0.28, bd * 0.28)):
            bolt = add_cyl('Cannon_Bolt_%s_%d' % (s, i), bolt_r, bolt_len,
                           (0, 0, 0), axis='X', seg=12,
                           mat=mats['chrome'], coll=coll)
            bolt.location = (cx + side * (bw * 0.5 + bolt_len * 0.25),
                             my + oy, bz - 0.02)
            parts.append(bolt)

        # ---- barrel: one closed cylinder, axis along Y, pointing forward
        barrel = add_cyl('Cannon_Barrel_' + s, br, bl, (0, 0, 0), axis='Y',
                         seg=24, mat=mats['exhaust_steel'], coll=coll)
        barrel.location = (cx, my - bl * 0.5, bz)
        parts.append(barrel)

        # ---- breech / recoil collar at the rear of the barrel
        breech = add_cyl('Cannon_Breech_' + s, brr, brl, (0, 0, 0), axis='Y',
                         seg=24, mat=mats['engine_black'], coll=coll)
        breech.location = (cx, my - brl * 0.5, bz)
        parts.append(breech)

        # ---- cooling ribs running along the barrel
        for i, f in enumerate((0.30, 0.55, 0.78)):
            rib = add_cyl('Cannon_Rib_%s_%d' % (s, i), rib_r, rib_d,
                          (0, 0, 0), axis='Y', seg=24,
                          mat=mats['chrome_dull'], coll=coll)
            rib.location = (cx, my - bl * f, bz)
            parts.append(rib)

        # ---- muzzle ring + dark inset bore at the barrel tip
        ring = add_cyl('Cannon_Muzzle_Ring_' + s, mrr, mrd, (0, 0, 0),
                       axis='Y', seg=24, mat=mats['chrome'], coll=coll)
        ring.location = (cx, tip_y + mrd * 0.5, bz)
        parts.append(ring)

        bore = add_cyl('Cannon_Bore_' + s, bore_r, bore_d, (0, 0, 0),
                       axis='Y', seg=24, mat=mats['plastic_black'], coll=coll)
        bore.location = (cx, tip_y + bore_d * 0.5, bz)
        parts.append(bore)

        # ---- authoring-aid EMPTY at the barrel tip; Blender 5.3 drops childless
        #      EMPTYs on glTF import, so Godot uses the Cannon_Bore mesh above.
        mz = empty('Muzzle_' + s, (cx, tip_y, bz), coll,
                   size=0.08, kind='SINGLE_ARROW')
        mz.rotation_euler = (R(90), 0, 0)

    return parts
