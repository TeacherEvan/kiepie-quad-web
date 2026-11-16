# Kiepie Quad — Web

Drive the Kiepie Bike (sport quad, Yamaha Blaster class) in your browser, or fight
other players in the combat arena. Built with Godot 4.3, exported to HTML/WASM,
hosted on Vercel and installable as a PWA.

▶ **Live: https://kiepie-quad-web.vercel.app** · mirror: **https://kiepie-bike.vercel.app**

## Modes

- **Practice** — the original free-ride pad: 3 ramps, a cone-ringed start line
  and 3 smashable buildings with a HUD smash counter.
- **Multiplayer** — Create Lobby / Join Auto / Join by code. `Join Auto` drops you
  into a waiting lobby (or creates one); the host starts the match and picks the
  kill target, rider cap, respawn delay, time limit and damage. First to the kill
  target wins. Until a Supabase project is configured in Settings → Network, the
  game runs against an offline mock backend.

## Controls

- `W` / `↑` — throttle (4WD)
- `A` / `D` (or `←` / `→`) — steering
- `S` / `↓` — brake, then reverse
- `Space` — handbrake
- `Shift` — **turbo** (hold while throttling): +30 % power, flames from the silencer
- `F` / left mouse — **fire both side cannons** in the arena (they overheat if held)
- `C` — camera: chase ↔ free orbit (drag / scroll to zoom)
- `R` — reset to spawn (also the on-screen Restart button)
- On-screen touch overlay — steer/gas/brake/turbo/**FIRE**; auto-appears on touch
  devices, and the **TOUCH** button force-shows/hides it anywhere.

## Combat

Each rider has 100 armour; a kill explodes the bike and respawns it at a random
point after the lobby's respawn delay. The shooter gets the point. The arena has
cover, ramps, destructible buildings, a radar, a scoreboard and a kill feed.

## Mobile / settings

Responsive landscape layout with safe-area support. Settings (persisted on your
device) cover quality presets for slower phones, audio, controls (including FIRE
button size), display name/colour and a diagnostics overlay. Use **Restore
Defaults** to reset.

## Notes

- Requires WebGL2 / a modern browser. Chrome, Firefox and Edge recommended.
- Personal, non-commercial interactive model showcase of a Blaster-class sport quad.
- Vehicle is raycast-suspension (4 × VehicleWheel3D) — for games, not for racing lines.
- The publishable Supabase key is public by design; never put a secret key in Settings.
