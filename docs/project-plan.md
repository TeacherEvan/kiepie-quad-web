# Kiepie Quad — Project Plan

Canonical project plan for the single repository `TeacherEvan/kiepie-quad-web`
(Blender source + Godot 4.3 game + Vercel-served Web build at the repo root).

- **Live:** https://kiepie-quad-web.vercel.app · mirror: https://kiepie-bike.vercel.app
- **Navigation hub:** [docs/index.md](index.md) · **Task ledger:** [docs/task-status.md](task-status.md)
- **Toolchain invariants / agent rules:** [AGENTS.md](../AGENTS.md) (authoritative for build/gate/deploy rules)
- **Player-facing overview:** [README.md](../README.md) · **Model/QA source doc:** [SOURCE.md](../SOURCE.md)

## Current state (2026-11-19)

- Sport quad (Yamaha Blaster class) procedurally built in Blender 5.3 from `src/qb_spec.py`;
  QA APPROVED, 0 non-manifold edges, ground datum minZ = 0.000.
- Godot 4.3 game: Dashboard with **Battle Royale** (default, `Arena.tscn` + `TestRide.tscn` practice) and **Death Race** (`DeathRace.tscn` circuit with loops, hazard pits, pit lane, ramps, pickups, ordered checkpoints, finish line, lap counter, and victory splash video), main scene `MainMenu.tscn`.
  Backend: Talo 0.20.0 (vendored), host-authoritative scoring, wire `protocol_version = 2`.
- The 2026-11-18 **10-Principal-Engineer audit**
  ([source report](audits/10%20Principal%20Engineer.txt)) was remediated in commits
  `1494b0d` + `60a8b82`; the final P1 (INP-3 opposing analog arbitration) was fixed and
  gated in `b35bae7`. Web bundles were re-exported and auto-deployed in `f09c80e` and
  `a3ec39c` (live HTTP 200 verified 2026-11-19). Per-finding status:
  [task-status.md](task-status.md).
- Gate suite: **27 gates**, all green (deploy_web.sh runs the full
  suite before export and aborts on any failure).
- **Blocked:** GitHub Actions CI cannot start — the GitHub account is locked for billing
  (run 44373734263 annotation). Code-side CI fixes are already landed; see
  [TS-001](task-status.md#pending-and-blocked).

## Architecture (pointers, not duplicates)

| Area | Source of truth |
| --- | --- |
| Master dimensions | `src/qb_spec.py` (edit here only, then rebuild) |
| Scene generation | `godot/tools/build_*.gd` — `.tscn` files are generated, never hand-edit |
| Gameplay | `godot/src/` (`KiepieBike.gd`, `game/`, `net/`, `ui/`, `audio/`) |
| Backend facade | `godot/src/net/TaloBackend.gd` behind the `Supabase` autoload name |
| Gates | `godot/tools/run_gates.sh` + `verify_*.gd` + GdUnit4 (`godot/tests/`) |
| Deploy | `godot/tools/deploy_web.sh` (gates → key inject → export → bundle check → push) |
| UI skin | `godot/src/ui/UiTheme.gd` |

## Canonical constants table

One table to rule them all — other docs mention these values by reference, not by copy.
Sweep rule: changing any row means grepping the name **and** the old literal across
`godot/`, `README.md`, `AGENTS.md`, `docs/` in the same commit.

| Constant | Value | Defined in |
| --- | --- | --- |
| Gate suite size | **27** (24 headless + 1 xvfb multi-touch + GdUnit4 + scene_sync) | `godot/tools/run_gates.sh` |
| Remote shot rate cap | **24 shots/s** per sender (twin-barrel rapid ≈ 22/s legit) | `godot/src/game/ArenaNet.gd` |
| Cannon cooldown (QUAD / NARDUS) | Primary: 0.20 / 0.09 s normal / 0.40 / 0.18 s rapid · Rocket Launcher: 1.5 s (2× dmg, 4.5 m blast) · Meteor Shower: 6.0 s (2.0 s sky-fall, 3.5× dmg, 7.5 m blast) | `godot/src/game/SideCannons.gd` |
| Kill registration | 1 s per-killer cooldown, 20/min window | `godot/src/net/TaloBackend.gd` |
| Armour / default damage / repair | 100 / 30 / +45 | `CombatController.gd`, `Match` defaults, `Pickup.gd` |
| Dodge | 1.0 s cooldown, 0.72 s duration, ground-only | `godot/src/KiepieBike.gd` |
| Wire protocol | `PROTOCOL_VERSION = 2` (bump only on wire-breaking change) | `godot/src/net/TaloBackend.gd` |
| Web pck size | currently **2.75 MB**; deploy aborts above **4 MB** | root `index.pck`, `deploy_web.sh` |
| Scorch / scar caps | MAX_SCORCH = 12 / MAX_SCAR = 24 | `godot/src/game/VfxFactory.gd` |
| Level counts | Arena 10 ramps / 7 buildings · TestRide 6 ramps / 4 buildings · DeathRace 8 ramps / 2 loops / 3 hazard pits / 4 checkpoints / FinishLine | `build_arena.gd`, `build_testride.gd`, `build_deathrace.gd` |

## Roadmap

### Pending / blocked (operational)

Tracked with IDs and owners in [task-status.md](task-status.md#pending-and-blocked):
TS-001 GitHub billing lock (owner: Evan) is the only hard blocker. Everything else
below is deliberately deferred architectural work, not a defect.

### Deferred architectural work (from the audit, with rationale)

1. **VFX ring-buffer pooling** (audit P1) — needs a dedicated plan + Web frame-time
   profiling; pooling bugs are worse than allocation. Mitigation already landed:
   ramp/curve content caching (`60a8b82`).
2. **HUD single signal bus** (audit P2) — no proven defect remains after the announce
   tween / Turbo label fixes; this is a redesign, not a fix.
3. **Typed DTO wrappers for net payloads** (audit P2) — payload validation gates
   (`verify_audit_regressions.gd`) lock the known malformed shapes; full static typing
   is a refactor.
4. **Velocity-clamped dead reckoning** (audit P2 residual) — monotonic relay ticks +
   stale-drop landed (`60a8b82`); the 250 ms interpolation clamp is not implemented.
5. **Server-side kill validation** — Talo v1 has no SQL RPC; rate caps are the only
   server-side lever. Design constraint, documented in AGENTS.md.
6. **Cannons vs destructible buildings** — auto-fire no longer targets indestructible
   shells; mobile auto-fire has now been removed outright (all shots are manual from the right
   analog's UP gesture). Whether cannons *should* smash buildings is a gameplay decision for the owner.

### Model / asset follow-ups (from README limitations)

- Replace `assets/decal_*.png` (Yamaha marks) before any commercial use.
- Optional KHR_texture_basisu re-bake to shrink the Draco `.glb` further.
- Rider figure / swingarm animation remain out of scope for the showcase.

## Verification policy

- Every behavior change: `bash godot/tools/run_gates.sh` green before commit.
- Every deploy: `deploy_web.sh --apply` (gates run inside it; pushes to `main`
  auto-deploy to Vercel, then curl the live URL).
- Every doc change: the [documentation-maintenance checklist](index.md#maintenance-checklist)
  — plan sync, content docs, legal check, scaffolding, cross-refs, verify.