"""
qb_spec.py - Master dimension spec for the Kiepie Bike.

A racing sport quad (Yamaha Blaster class), built to real-world metric
dimensions so it drives correctly in Godot on a custom race track.
All values in metres. Origin = ground centre, bike centre line = X=0,
front of the bike faces -Y.
"""

SPEC = {
    # ---- wheels ------------------------------------------------------------
    'front_tyre_r': 0.280,          # outer radius of front carcass (22" tyre)
    'front_tyre_hw': 0.098,         # half width
    'rear_tyre_r': 0.280,
    'rear_tyre_hw': 0.120,
    'rim_r': 0.152,                 # bead seat radius (12 inch rim)
    'front_hub_x': 0.545,           # half track, front
    'rear_hub_x': 0.575,            # half track, rear
    'front_axle_y': -0.680,
    'rear_axle_y': 0.660,
    'front_axle_z': 0.280,
    'rear_axle_z': 0.280,

    # ---- frame / body ------------------------------------------------------
    'seat_top_z': 0.720,
    'seat_front_y': -0.130,
    'seat_rear_y': 0.360,
    'handlebar_z': 1.000,
    'handlebar_y': -0.360,
    'handlebar_x': 0.520,

    # ---- engine / drivetrain ------------------------------------------------
    'engine_centre': (0.0, -0.080, 0.400),
    'silencer_front': (-0.278, 0.075, 0.480),
    # The can is built level, so the rear Z matches the front Z (the old
    # 0.505 value was never read by build_exhaust()).
    'silencer_rear': (-0.278, 0.655, 0.480),
    'silencer_r': 0.086,

    # ---- suspension ---------------------------------------------------------
    'shock_top_z': 0.790,
    'shock_top_y': -0.420,
    'lower_arm_z': 0.245,
    'upper_arm_z': 0.420,
    'lower_pivot_x': 0.115,
    'upper_pivot_x': 0.105,

    # ---- foot pegs -----------------------------------------------------------
    'peg_x': 0.395,
    'peg_y': -0.020,
    'peg_z': 0.360,

    # ---- side-mounted cannons ------------------------------------------------
    # Blaser-class quad gets two symmetric cannons flanking the nose.  Barrels
    # point forward (Blender -Y).  Kept inside the existing AABB so the
    # photo-matched manifest dims (1.48 x 2.14 x 1.08 m) stay unchanged.
    'cannon_side_x': 0.400,          # half-track of the cannon mount (X)
    'cannon_mount_y': -0.460,        # bracket centre / barrel breech (Y)
    'cannon_barrel_z': 0.560,        # barrel centreline height (Z)
    'cannon_barrel_r': 0.050,        # closed barrel cylinder radius
    'cannon_barrel_len': 0.520,      # barrel length (tip at mount_y - len)
    'cannon_muzzle_ring_r': 0.064,   # muzzle collar outer radius
    'cannon_muzzle_ring_depth': 0.032,
    'cannon_breech_r': 0.060,        # recoil collar at barrel rear
    'cannon_breech_len': 0.072,
    'cannon_bracket_w': 0.100,       # bracket size (X, Y/depth, Z/height)
    'cannon_bracket_depth': 0.130,
    'cannon_bracket_h': 0.130,
    'cannon_arm_r': 0.014,           # support arms back to the frame
    'cannon_rib_r': 0.058,           # cooling ribs along the barrel
    'cannon_rib_depth': 0.018,
    'cannon_bolt_r': 0.014,          # bolt heads on the bracket outboard face
    'cannon_bolt_len': 0.030,
    'cannon_bore_r': 0.031,          # dark bore inset at the muzzle face
    'cannon_bore_depth': 0.016,
}
