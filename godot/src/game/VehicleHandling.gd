class_name VehicleHandling
extends RefCounted
## Pure vehicle handling, aerodynamics, braking, and stability math.
## Extracted from KiepieBike.gd so physics curves are unit-testable
## without instantiating VehicleBody3D.


static func effective_steer_cap(speed_mps: float, base_max: float, sensitivity: float) -> float:
	if not is_finite(speed_mps) or not is_finite(sensitivity) or not is_finite(base_max):
		return clampf(base_max * 0.4, 0.09, 0.58)
	var s := clampf(absf(speed_mps), 0.0, 50.0)
	var t := clampf((s - 6.0) / 26.0, 0.0, 1.0)
	var speed_scale := lerpf(1.0, 0.24, t * t * (3.0 - 2.0 * t))
	var sens_angle := lerpf(0.60, 1.24, clampf((sensitivity - 0.3) / 1.7, 0.0, 1.0))
	return clampf(base_max * speed_scale * sens_angle, 0.09, 0.62)


static func effective_steer_rate(base_rate: float, sensitivity: float, returning_to_center: bool) -> float:
	if not is_finite(base_rate) or not is_finite(sensitivity):
		return 4.8
	var sens_rate := lerpf(0.60, 1.45, clampf((sensitivity - 0.3) / 1.7, 0.0, 1.0))
	return base_rate * sens_rate * (1.45 if returning_to_center else 1.0)


static func top_speed_cap(turbo_blend: float, overdrive: bool) -> float:
	if overdrive:
		return 36.0
	var tb := clampf(turbo_blend, 0.0, 1.0) if is_finite(turbo_blend) else 0.0
	return lerpf(28.0, 33.0, tb)


static func power_taper(forward_speed: float, max_speed: float) -> float:
	if not is_finite(forward_speed) or not is_finite(max_speed) or max_speed <= 1.0:
		return 1.0
	return clampf(1.0 - maxf(0.0, (forward_speed - max_speed * 0.88) / (max_speed * 0.22)), 0.15, 1.0)


static func aero_drag_accel(vel: Vector3, max_speed: float) -> Vector3:
	if not vel.is_finite() or not is_finite(max_speed):
		return Vector3.ZERO
	var spd := vel.length()
	if spd < 1.0:
		return Vector3.ZERO
	var ms := maxf(max_speed, 10.0)
	var soft_start := ms * 0.82
	var over := maxf(0.0, spd - soft_start)
	var hard := maxf(0.0, spd - ms)
	var decel := over * over * 0.20 + hard * 8.0
	return -vel.normalized() * decel


static func service_brake_for_wheel(base_brake: float, is_front: bool, skidinfo: float, amount: float) -> float:
	if not is_finite(base_brake) or not is_finite(skidinfo) or not is_finite(amount):
		return 0.0
	var abs_mod := clampf(0.45 + 0.55 * clampf(skidinfo, 0.0, 1.0), 0.45, 1.0)
	return maxf(0.0, base_brake) * (1.25 if is_front else 0.75) * abs_mod * clampf(amount, 0.0, 1.0)


static func high_speed_yaw_limits(speed_mps: float, steering_active: bool) -> Vector2:
	if not is_finite(speed_mps):
		return Vector2(3.4, 0.96)
	var hi_t := clampf((absf(speed_mps) - 10.0) / 22.0, 0.0, 1.0)
	var max_yaw := lerpf(3.4, 2.05, hi_t)
	var yaw_keep := lerpf(0.99, 0.90, hi_t) if steering_active else lerpf(0.96, 0.78, hi_t)
	return Vector2(max_yaw, yaw_keep)


static func lateral_slip_keep(speed_mps: float, slip_rad: float) -> float:
	if not is_finite(speed_mps) or not is_finite(slip_rad):
		return 1.0
	var hi_t := clampf((absf(speed_mps) - 10.0) / 22.0, 0.0, 1.0)
	var abs_slip := absf(slip_rad)
	if hi_t <= 0.01 or abs_slip <= 0.14:
		return 1.0
	var excess := clampf((abs_slip - 0.14) / 0.45, 0.0, 1.0)
	return lerpf(0.96, 0.80, excess * hi_t)
