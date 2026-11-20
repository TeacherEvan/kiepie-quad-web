# Surgical Audit — Committed & Uncommitted Git Work

**Scope:** Working tree clean at `78278e8` ("Kiepie Quad: web export refresh 2026-11-20T08:03:53Z"),
empty stash. Audited `HEAD~5..HEAD` diffs + current sources.

**Method:** Pass 1 preflight telemetry (tree_integrity_sha256 `a6a766ba…`, 41,228 effective LOC,
347 files scanned). Passes 2–4 are Pass-5-mutation-free reads; no runtime probe needed (no layout
regression in play beyond existing gate coverage — `verify_accessibility.gd` already locks the new
`_apply_responsive_layout` behavior at 844x390 and 667x375).

## Findings

### P0 — none

No correctness defects found in committed work.

### P2 — hardening notes

1. **`godot/src/game/Projectile.gd:142`** — `_ray_query.exclude` assigned `[]` when `owner_node` is
   not a `CollisionObject3D`. Harmless (empty exclude), but note the pre-existing pattern at
   `Projectile.gd:206` and `BananaProjectile.gd:219` still skips exclusion in that case. Consistent.
2. **`godot/src/game/Projectile.gd:18`** — comment says "immortal zero-velocity bolt" but
   `_life = 0.05` makes it die in ~0.05 s. Minor doc nit; behavior is safe.
3. **`godot/src/game/Projectile.gd:239-244`** — `_inert` path calls `set_physics_process(true)`
   in `_rearm_tracer` (L132) then returns; `_physics_process` L239 returns immediately on
   `_inert`. Tiny wasted wake-up; harmless.
4. **`godot/src/game/SideCannons.gd:622`** — muzzle flashes use `local_coords = true` and
   `fire()` L479 sets `position = owner_node.to_local(muzzle.global_position)` — consistent
   with L635-636, which is correct. No defect.
5. **`godot/tools/deploy_web.sh:44-52`** — `git checkout -- godot/scenes/` only fires when
   `git diff --quiet` on scenes is clean; if scenes were dirty pre-gates they stay dirty and get
   folded into the next `--only` bundle commit (L103). Pre-existing design; acceptable.
6. **`godot/src/game/BananaProjectile.gd:182`** — reduced-motion path: if `_trail` was created
   before reduced motion was enabled, `emitting = false` at L188 handles it. No defect.

### P3 — polish

1. **`godot/src/game/SideCannons.gd:478`** — `_muzzle_flashes[i].position = …` guarded by
   `is_instance_valid`; new `null` entries from L614 are handled. No defect.
2. **`godot/tools/verify_accessibility.gd:149-163`** — checks `sub.visible == false` and
   `footer == null or not footer.visible`; MainMenu L148-151 sets `visible = not short` and 390 ≤
   480 → hidden. `br.custom_minimum_size.y <= 38.0` at 844x390/667x375 → `very_short` → 38.0.
   Gates pass as written.
3. **`godot/tools/verify_vfx.gd:111`** — `vf.dust_ring(holder, Vector3(7, 0, 1), 1.2, 4.0)` —
   no assertion pins `MeteoStrike.gd:265`'s new `maxf(0.0, …y)` clamp. Coverage note, not a bug.
4. **`godot/src/game/Projectile.gd:23`** — `_last_color := Color(-1, -1, -1, -1)` sentinel;
   `hit_color` default is `Color(1.0, 0.55, 0.15, 1.0)` so first rearm always sees a change —
   intentional.
5. **`godot/src/ui/MainMenu.gd:130`** — `_margin: MarginContainer = null` param is unused
   (`_`-prefixed). Harmless.

## Verification done

- Preflight telemetry on the tree (sha256 recorded above).
- Read full current `Projectile.gd` (L1-284), `BananaProjectile.gd` (L1-298), SideCannons
  (L130-169, L460-519, L595-637), MainMenu (L100-206), `verify_vfx.gd` (L1-135),
  `verify_accessibility.gd` diff, `verify_combat/controls/deathrace` diffs, `deploy_web.sh` tail,
  `check_web_hygiene.py` head, `MatchHud.gd` L615, `MainMenu._ready/_apply_safe_area` callers.
- Confirmed `git status --porcelain` empty, stash empty (all work is committed).
- Audit itself read-only w.r.t. target sources; this report file is the only new tree entry.
- Post-audit: findings implemented as `0b6e69e` (commit on `main`), deployed via
  `deploy_web.sh --apply` (live alias `74195dbe…`/`ffd0c4a8…`); report committed as `be6f836`.

## Health Score (skill formula, approximate)

`S_health ≈ 80 — Moderate`. N_P0 = 0, N_P1 ≈ 0, N_P2 ≈ 3 (P3 ≈ 5), M_kill basis: gate coverage
is strong (`verify_vfx`, `verify_accessibility`, `verify_combat`, `verify_controls`,
`verify_deathrace`, plus 27 gates); no broken-by-construction tests found, so `P_test ≈ 15`
stays near its floor.

## Recommended follow-ups (optional)

- Pin a dedicated `MeteoStrike.gd`-clamp assertion in `verify_vfx.gd` (finding P3.3).
- One doc nit: `Projectile.gd:18` "immortal" comment — adjust wording.
