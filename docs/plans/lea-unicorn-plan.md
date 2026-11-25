# Lea Unicorn — Implementation Plan (2026-11-25)

> **Method:** `surgical-building` + `writing-plans` + TDD (red-first gates) + `surgical-audit` at the end.
> **Scope:** fifth playable vehicle, Godot 4.3 Web/WASM only. Purely additive: no changes to existing
> vehicle hashes, `PROTOCOL_VERSION = 3`, or any in-flight (uncommitted) Evan work.

## Phase 0 — Alignment (no clarification halt)

| Axis | Value | Evidence |
| :--- | :--- | :--- |
| Platform | Hybrid desktop + two-thumb mobile, Godot 4.3 Web/WASM | `AGENTS.md` |
| Licence | Private / non-commercial portfolio (swap decals before commercial use) | `AGENTS.md` trademarks note |
| Audience | All audiences — stylised pastel fantasy | reference set (5 images) |
| Rig | Articulated 52-joint rig + 4 baked clips (same class as Evan, recommended by `surgical-building` Gate B) | user's "proceed" + wing-spread/flight requirements |
| Runtime budget | < 10k tris, plain GLB (no Draco — Godot 4.3 importer lacks it) | `AGENTS.md`, prior Evan constraint |

**Explicit decision (Gate B):** full articulated rig, not a static prop. The user already approved the
52-bone class for Evan and the ultimate requires wing expansion + flight, so a static sculpt cannot
satisfy the brief. No user pause needed — "proceed" was explicit.

## Phase 1 — Reference synthesis

Five reference images in `docs/plans/Designs/Lea unicorn/` agree on:
- pearlescent **white/ivory body**, slim equine build, gold-tempered hooves;
- **spiralled golden horn** with a bright tip (the muzzle for both horn weapons);
- **pink → lavender mane and tail**, flowing strands;
- **large feathered wings** — pink/blue or rainbow iridescent gradient, individually layered feathers;
- bright **blue eyes**, soft fantasy lighting, no text/logos.

Design locks: body `#F4F1EA` pearlescent, horn gold `#E8B84B` with emissive tip, mane pink `#F06AB5`
→ lavender `#B98BE8`, wing feathers gradient root pink → tip cyan `#6FD6E8`, eyes sapphire `#2E6FD0`,
hooves gold. All materials are procedural PBR (no image textures), so the pck stays small.

## Phase 2 — Model build (`src/build_lea_unicorn.py`)

Mirror `src/build_evan_skeleton.py`: headless `bpy`, `1 unit = 1 m`, `+Z` up in Blender, AABB bottom
at `minZ = 0.000`, plain glTF export. Outputs:
- `Lea_Unicorn.blend` (source), `godot/assets/Lea_Unicorn.glb`, `Lea_Unicorn.stl`
- `lea_spatial_manifest.json` (stylised brief — vanishing-point metrology intentionally skipped)
- `QA_debrief_lea.json` + 4-angle diagnostics (`front_0`, `right_90`, `top_ortho`, `iso_45`)

**52-joint rig** mapped to: body/spine (8), neck + head + jaw + ears + eyes (7), four legs (4 × 5 = 20),
two wings (2 × 7 = 14: scapula, humerus, radius, primary/secondary fan groups), tail (3). All meshes
are batched by bone + material. Landmark names are immutable so gates can find them:
`HornTip`, `HornBase`, `Wing_L`, `Wing_R`, `ManeForelock`, `TailRoot`, `Eye_L`, `Eye_R`,
`Hoof_FL`, `Hoof_FR`, `Hoof_RL`, `Hoof_RR`.

**4 baked clips:** `Idle_Breathe`, `Locomotion_Gallop`, `Action_WingSpread`, `UnicornBoom_Flight`.
QA gate: `non_manifold_edges == 0`, `|minZ| <= 0.005`, verts < 65,535, IoU skipped (no reference
mask) but all 4 diagnostic renders produced and reviewed.

## Phase 3 — Gameplay contracts

Wire kinds stay `"primary"` / `"rocket"` / `"meteor"` — no new net messages, no protocol bump.

| Slot | Script | Behaviour | Authority |
| :--- | :--- | :--- | :--- |
| Primary — horn rapid fire | `HornBoltProjectile.gd` | fast gold/pink spark bolts from `HornTip`, pooled slots, short cooldown | shooter spawns, victim resolves hit |
| Rocket — Horn beam | `HornBeam.gd` | ~0.6 s charge particle vortex in front of the horn, then a straight plasma/laser beam (~0.35 s) that damages everything on the line | direct-hit lethal, small blast; victim authority preserved |
| Ultimate — Unicorn boom | `UnicornBoom.gd` | wing-spread + leap + homing flight to target, landing kill zone | fail-closed `CombatAoe.apply_lethal_blast()` like Evan's hand |

**Trust boundary:** incoming target positions are bounded (finite, within a sane radius of the
shooter) before being used; a remote packet can never assert "you died" — only the victim's own
client resolves lethal contact. Kill tokens use the existing `"<base>:v<victim>"` sub-token form.

## Phase 4 — Integration (additive)

- `VehicleRegistry.gd`: `VEHICLE_UNICORN = &"LeaUnicorn"`, display `"LEA UNICORN"`, **preference-only**
  (NOT in `VEHICLES` FNV deal pool — adding it would change existing hash fixtures).
- `MainMenu.gd` / `build_menus.gd`: fourth selector option; persisted in `Settings.gameplay/vehicle`,
  synced in lobby rows.
- `KiepieBike.gd`: visual swap in `_enter_tree`, recursive `HornTip` anchor lookup, `vehicle_profile = "unicorn"`, identical physics stats.
- `SideCannons.gd`: new `unicorn` profile (rate/damage/muzzle).
- `ArenaNet.gd`: remote reconstruction for all three new shots; extend both hand-maintained vehicle-id
  vocabularies consistently (documented P3 refactor left intact, not expanded).
- `UnicornVisual.gd`: NLA driver — speed-coupled gallop, reverse backpedal, wing-spread on charge,
  expiry springs on landing, `trigger_charge()` / `trigger_boom()` hooks.
- `CombatAoe.gd`: reuse existing `apply_lethal_blast()`; no new public API.

## Phase 5 — Verification (red-first)

1. New gates `verify_lea_unicorn.gd` + `verify_lea_unicorn_weapons.gd` are written and run **before**
   each implementation unit; failure output is recorded in scratch.
2. Add both to `run_gates.sh` (31 → 33 gates) and update the AGENTS.md gate count.
3. Full suite green, `check_web_hygiene.py` OK, QA reviewer APPROVED, glTF budget ≥ 90/100.
4. Local Web bundle refresh only (`deploy_web.sh` dry run + staging copy). **No push / no Vercel deploy
   unless explicitly requested** — a push to `main` auto-deploys.
5. Docs sync: `docs/index.md`, `docs/task-status.md`, `docs/project-plan.md`, constants sweep.

## Phase 6 — Final audit

Run `surgical-audit` on the new vehicle + integration: trust boundary, pooling, lifecycle, wire
compatibility, collision resolution, input/gate vacuity, artifact hashes. Fix P0/P1 before hand-off,
record any deferred P2/P3 with evidence.

## Non-goals / guardrails

- Do not add Unicorn to the FNV deal pool, bump `PROTOCOL_VERSION`, enable Draco, or rename existing
  landmark meshes in other vehicles.
- Do not touch the uncommitted Evan files found in the working tree at task start; stage only paths
  belonging to this vehicle.
- Do not weaken the boomerang/lethal-blast victim guards or introduce fresh per-shot nodes where a
  pooled slot exists.
