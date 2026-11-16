# Kiepie Quad — Web

Drive the Kiepie Bike (sport quad, Yamaha Blaster class) in your browser.
Built with Godot 4.3, exported to HTML/WASM, hosted on Vercel.

▶ **Live: https://kiepie-quad-web.vercel.app** · mirror: **https://kiepie-bike.vercel.app**

## Controls
- `W` / `↑` — throttle (4WD)
- `A` / `D` (or `←` / `→`) — steering
- `S` / `↓` — brake, then reverse
- `Space` — handbrake
- `Shift` — **turbo** (hold while throttling): +30 % power, flames from the silencer
- `C` — camera: chase ↔ free orbit (drag / scroll to zoom)
- `R` — reset to spawn (also the on-screen Restart button)

## What's on the pad
- 3 ramps, a cone-ringed start line, and **3 smashable buildings** — drive in at speed,
  they burst into debris; a HUD counter tracks how many you wreck.
- The quad cannot roll over — physics tuned for a Blaster, not a Formula 1 car.

## Notes
- Requires WebGL2 / a modern browser. Chrome, Firefox and Edge recommended.
- Personal, non-commercial interactive model showcase of a Blaster-class sport quad.
- Vehicle is raycast-suspension (4 × VehicleWheel3D) — for games, not for racing lines.
