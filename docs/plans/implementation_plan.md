# Faster Reversing, 1.5s Rocket Reload, Authoritative Cross-Player Damage Numbers, Multi-Stage Particle/Mushroom-Cloud/Death VFX & Nardus Pink Borat Outfit Implementation Plan (Enhanced v2)

> **Agent:** Antigravity / Anti-Gravity Pair
> **Enhanced sub-skills invoked:** writing-plans-enhanced + surgical-building + plastic-surgery + surgical-implementation
> **Verification mode:** Visual / Transform / Test / Browser-observable / 27-Gate Suite

**Goal:** Deliver faster vehicle reversing (`reverse_force = 265.0`), a `1.5s` Rocket Launcher reload cooldown, authoritative cross-player floating damage numbers (with shield-absorption & radial-falloff accuracy across all peers), a multi-stage particle explosion & towering Meteor mushroom-cloud VFX system plus dramatic ragdoll-wreck deaths, and a watertight C2-smooth Blender sculpt of Nardus in a hot-pink Borat mankini with cute, slightly red butt cheeks sticking out.

**Architecture:**
1. **Physics & Arsenal Tuning (`KiepieBike.gd`, `SideCannons.gd`, `ArenaNet.gd`, `build_bike.gd`):** Raise `reverse_force` from `180.0` to `265.0` (+47% reverse thrust) and `forward_speed < 2.5` brake-to-reverse handoff; rebuild `KiepieBike.tscn` via `tools/build_bike.gd` so `check_scene_sync.py` stays green. Lower `SideCannons.ROCKET_COOLDOWN` from `5.0s` to `1.5s` and `ArenaNet.REMOTE_ROCKET_MIN_S` from `4.5s` to `1.15s`.
2. **Authoritative + Immediate Cross-Player Damage Telemetry (`CombatController.gd`, `TaloBackend.gd`, `ArenaNet.gd`, `RocketProjectile.gd`, `MeteorStrike.gd`, `FuelDrum.gd`):**
   - **Immediate Attacker Read:** When the local player hits a remote `NetworkedBike` (via primary cannon/banana, rocket AOE, meteor AOE, or ignited fuel drum), spawn an immediate gold-amber floating damage number (`VfxFactory.damage_number`) and trigger `hit_confirmed`.
   - **Authoritative Victim `"hurt"` Broadcast:** When any player actually takes damage in `CombatController.take_damage()` (after shield/invulnerability checks and radial falloff calculation), broadcast a compact `"hurt"` event (`{"victim": user_id, "attacker": attacker_id, "dmg": roundi(amount)}`) validated by sender alias in `TaloBackend.gd` (`victim == sender_id`, rate-capped) so third-party spectators and peers see exact, non-duplicated damage numbers pop off the victim's vehicle in real time.
3. **Particle Explosion, Meteor Mushroom Cloud & Dramatic Death (`VfxFactory.gd`, `CombatController.gd`, `NetworkedBike.gd`, `MatchHud.gd`):**
   - **`VfxFactory.particle_explosion` (Rocket Launcher & Base Detonations):** 5-layer WebGL2-safe particle burst (expanding 3D plasma core, velocity-aligned radial spark streaks, turbulent alpha-blended fireball, incandescent additive heart, dual shockwave rings, cooling shrapnel chunks, organic scorch).
   - **`VfxFactory.mushroom_cloud_explosion` (Meteor Shower):** 6-stage colossal detonation (`scale = 2.65`): blinding ground flash dome, double concentric ground dust/thermal shockwave rings + 360° ground dust skirt, a towering buoyant fiery **Mushroom Stem** rising to `+7.5m`, a delayed (`t = 0.16s` & `t = 0.34s`) elevated toroidal **Mushroom Cap Canopy** billowing outward at the crown, and a transonic **Wilson Condensation Ring** expanding at mid-stem height.
   - **`VfxFactory.dramatic_death_explosion` (Player Death):** 4-beat death sequence: (1) `55ms` local death hitstop + heavy `0.82` camera shake + red screen death-flash spike + low-pitched sub-boom layered over the explosion SFX, (2) primary `1.65×` particle explosion + upward launch shockwave, (3) spinning, smoking charred vehicle wreck (`RigidBody3D`, `collision_layer = 0`, `MAX_WRECKS = 6` cap) hurled skyward (`vy = 9.5..12.5 m/s`) with a live flame-and-soot particle tail, and (4) two staggered mid-air secondary cook-off explosions (`t = 0.24s` and `t = 0.52s`) tracking the tumbling wreck before it shatters into embers.
4. **Nardus Pink Borat Mankini & Cute Slightly Red Butt Cheeks (`src/build_pogo_nardus.py`):**
   - Replace the crimson shirt and navy shorts with a continuous bare-skin torso/pelvis (`SKIN`), a conformal hot-pink Borat mankini (`MankiniPink`: front pouch, high-cut hip V-slings flanking his overhanging fat belly, over-the-shoulder straps, Y-back straps framing `NardusDecal`, and a rear vertical thong strap), and two plump, C2-smooth, cute **slightly red butt cheeks** (`ButtCheek_L`, `ButtCheek_R` in warm rosy-red `ButtCheekRed`) sticking out on each side of the thong strap directly in the chase camera's line of sight.

**Anti-Gravity boundary:** Internal repository and artifact changes only. `.env` (`TALO_API_GAME`) is never read or printed; all 27 gates run offline under `KIEPIE_MOCK_BACKEND=1`.

---

## Goal Description & Why v2 Improves on v1

A rigorous review of v1 identified **five subtle architectural edge cases** that v2 now solves cleanly:
1. **`scene_sync` Gate Protection on `KiepieBike.tscn`:** `KiepieBike.gd` exports `reverse_force`. Changing a default `@export` value in `KiepieBike.gd` without re-running `tools/build_bike.gd` (or if `build_bike.gd` serializes properties into `KiepieBike.tscn`) can trip `check_scene_sync.py`. v2 explicitly runs all 5 scene builders (`build_bike.gd`, `build_testride.gd`, `build_menus.gd`, `build_arena.gd`, `build_deathrace.gd`) and verifies `check_scene_sync.py`.
2. **True Multi-Peer Damage Visibility & Anti-Duplication:**
   - In v1, remote rocket/meteor clones (`ArenaNet._spawn_remote_shot`) had `owner_id != local_uid`, and remote `NetworkedBike` proxies don't have a `CombatController` child. Furthermore, if a remote victim had an active **Shield** pickup (`_shield_until`), a naive client-side hit check would show `-60` damage even though the victim absorbed `0` damage!
   - In v2, we combine **immediate attacker feedback** (when you shoot an enemy) with a **victim-authoritative `"hurt"` wire broadcast** from `CombatController.take_damage()` (validated in `TaloBackend.gd` with `victim == sender_id`, and deduplicated on the attacker via a 250 ms per-victim timestamp guard so the shooter never sees a double number, while every other player in the arena sees exact damage numbers whenever any player hurts any other player — including hazard pits and drums!).
3. **Conformal Mankini Geometry (Zero Z-Fighting or Floating Straps):**
   - Instead of placing primitive boxes or toruses that either sink inside Nardus's bare torso or float above his skin, v2 uses a **parametric surface-offset loft** (`_sample_torso_profile(z, phi)`) so the hot-pink Borat mankini straps hug his bare chest, shoulders, upper back (around `NardusDecal`), and gluteal cleft at a constant `+0.009m` conformal offset with zero non-manifold edges and zero Z-fighting.
4. **Physically Staged Mushroom Cloud Anatomy:**
   - Instead of just scaling up a spherical explosion, v2's `mushroom_cloud_explosion` models the four distinct physical features of a real mushroom cloud: (a) **Mach Ground Skirt & Double Dust Wave**, (b) **Buoyant Thermal Stem** (narrow spread `14°`, strong upward acceleration `gravity = Vector3(0, 5.2, 0)`), (c) **Elevated Toroidal Cap Canopy** (spawned at the stem apex `y = +2.3 * scale` with outward radial curl and long `3.5s` lifetime), and (d) **Mid-Stem Wilson Condensation Ring** (expanding flat vapor annulus at `y = +1.15 * scale`).
5. **Bounded Dramatic Death Physics & Sensory Punch:**
   - v2 caps concurrent death wrecks (`MAX_WRECKS = 6`, `collision_layer = 0`, `collision_mask = 0`, `SHADOW_CASTING_SETTING_OFF`) so simultaneous multi-kills in a 8-player match never lag WebGL2 physics, and pairs the visual wreck launch with a `55ms` local death hitstop, a crimson HUD vignette spike, and a sub-bass (`0.58×` pitch) secondary explosion boom.

---

## User Review Required

> [!IMPORTANT]
> **Surgical-Building Gate B — Nardus Character Sculpt & Outfit Specification:**
> - **Runtime Target & Budgets:** Godot 4.3 `godot/assets/Pogo_Nardus.glb`, `< 9,000` triangles (~5.4k tris), `<= 16` materials (`15` materials total), `0` non-manifold edges, `minZ == 0.0000`.
> - **Articulated Hierarchy (Immutable):** `Rider/RiderBody`, `Rider/Belly`, `Rider/Head`, `Rider/Arm_L`, `Rider/Arm_R`, `Rider/NardusDecal`, `Stick/StickLower`, `Stick/SpringCoil`, `Stick/StickUpper`, `Stick/BananaMuzzle_L`, `Stick/BananaMuzzle_R`.
> - **4 Procedural Animations (`PogoVisual.gd`):** `Idle_Breathe`, `Locomotion_Hop`, `Jump_Arc`, `Action_TurboFlap` (symmetric bird-wing flapping on turbo).
> - **Pink Borat Mankini & Cute Slightly Red Butt Cheeks:**
>   - Bare skin torso, chest, back, and upper thighs (`Skin`).
>   - Conformal hot-pink Borat mankini (`MankiniPink`, sRGB `(1.0, 0.10, 0.58)`): front pouch + twin V-slings climbing inside his overhanging belly, over the shoulders, converging into a Y-back below the `NardusDecal` back print, and diving as a narrow pink thong strap between his butt cheeks.
>   - Two plump, cute, **slightly red butt cheeks** (`ButtCheek_L` & `ButtCheek_R` in `ButtCheekRed`, sRGB `(0.88, 0.38, 0.34)` — a warm, slightly red / rosy blush contrast against his `(0.81, 0.54, 0.37)` skin) sticking out on either side of the rear pink thong strap.

---

## Proposed Changes

### Component 1: Faster Vehicle Reversing & 1.5s Rocket Launcher Reload

#### [MODIFY] [KiepieBike.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/src/KiepieBike.gd)
- Raise `reverse_force` from `180.0` to `265.0` (+47% reverse thrust) and allow reverse thrust to engage as soon as `forward_speed < 2.5` (up from `2.0`) so braking-into-reverse feels immediate and reversing reaches ~32% higher top reverse speed.

```gdscript
# godot/src/KiepieBike.gd (lines 18-20, 396-400)
@export var coast_brake := 0.01      ## rolling drag fraction of brake_force when coasting
@export var reverse_force := 265.0
...
		elif throttle < 0.0:
			var forward_speed := linear_velocity.dot(global_transform.basis.z)
			if forward_speed < 2.5:
				w.engine_force = -reverse_force * -throttle
			else:
				w.brake = brake_force
```

#### [MODIFY] [SideCannons.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/src/game/SideCannons.gd)
- Update `ROCKET_COOLDOWN` from `5.0` to `1.5` seconds (and update header doc comments).

```gdscript
# godot/src/game/SideCannons.gd (lines 22-25)
const WEAPON_ORDER := ["primary", "rocket", "meteor"]
const ROCKET_COOLDOWN := 1.5
const ROCKET_DAMAGE_MULT := 2.0
const ROCKET_BLAST_RADIUS := 4.5
```

#### [MODIFY] [ArenaNet.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/src/game/ArenaNet.gd)
- Lower `REMOTE_ROCKET_MIN_S` from `4.5` to `1.15` seconds so remote rockets fired on the `1.5s` reload cadence are never dropped under network jitter.

```gdscript
# godot/src/game/ArenaNet.gd (lines 21-22)
const REMOTE_ROCKET_MIN_S := 1.15
const REMOTE_METEOR_MIN_S := 5.5
```

---

### Component 2: Cross-Player Floating Damage Numbers (Attacker + All Peers)

```mermaid
sequenceDiagram
    participant Attacker as "Attacker Client"
    participant Talo as "TaloBackend / MockBackend"
    participant Victim as "Victim Client"
    participant Peer as "Spectator / Other Peers"

    Attacker->>Victim: Projectile / Rocket / Meteor / Drum hit
    Note over Attacker: Immediate local feedback:<br/>VfxFactory.damage_number(-dmg, GOLD)<br/>+ hit_confirmed() + _note_local_dmg(victim_id)
    Victim->>Victim: CombatController.take_damage(amount)<br/>(checks shield / invuln, applies health -= amount)
    Victim->>Talo: Supabase.broadcast("hurt", {victim, attacker, dmg})
    Talo->>Attacker: broadcast_received("hurt", payload)
    Note over Attacker: Deduplicated if within 280ms of<br/>local hit on same victim; otherwise<br/>shows authoritative damage number!
    Talo->>Peer: broadcast_received("hurt", payload)
    Note over Peer: Spawns VfxFactory.damage_number(-dmg)<br/>above Victim's NetworkedBike proxy!
```

#### [MODIFY] [VfxFactory.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/src/game/VfxFactory.gd)
- Upgrade `damage_number(parent: Node3D, pos: Vector3, amount: float, color: Color)` so damage numbers are unmistakable at arena distances:
  - `font_size = 64` (scaled up to `76` when `amount >= 85.0` for meteors/heavy blasts), `outline_size = 14`, `no_depth_test = true` (never clipped inside the vehicle mesh), slight horizontal scatter (`randf_range(-0.28, 0.28)` so twin-barrel hits don't stack on the exact same pixel), and a crisp pop-in scale tween (`Vector3.ONE * 1.35 -> Vector3.ONE`) while floating upward `1.65m` over `0.75s`.

#### [MODIFY] [CombatController.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/src/game/CombatController.gd)
- In `take_damage(amount, attacker_id, point, token, bypass_invuln)`:
  - When damage lands and `!practice_mode`, broadcast `"hurt"`:
    ```gdscript
    if not practice_mode:
        Supabase.broadcast("hurt", {
            "victim": Supabase.user_id,
            "attacker": attacker_id,
            "dmg": int(roundf(amount)),
        })
    ```
- In `_on_projectile_hit(collider, point, projectile)`:
  - When `owner_id == Supabase.user_id` and `target_id != ""` and `target_id != Supabase.user_id`:
    - Spawn `VFX.damage_number(_fx_parent(), point + Vector3(0.0, 0.45, 0.0), float(projectile.get("damage")), Color(1.0, 0.88, 0.26))` immediately so the shooter gets instant zero-latency damage numbers alongside `hit_confirmed.emit()`, and notify `ArenaNet.note_local_damage_shown(target_id)` so the echoed `"hurt"` packet from the victim doesn't double-spawn a second number `60ms` later.

#### [MODIFY] [RocketProjectile.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/src/game/RocketProjectile.gd), [MeteorStrike.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/src/game/MeteorStrike.gd), [FuelDrum.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/src/game/FuelDrum.gd)
- When a rocket, meteor, or ignited fuel drum detonates and damages a bike in group `"bike"` that does **not** have a local `CombatController` child (i.e., a remote `NetworkedBike` proxy or dummy enemy in practice/tests):
  - If `owner_id == local_uid` (or `controller == null`), spawn `VFX.damage_number(fx, bike_node.global_position + Vector3(0.0, 0.55, 0.0), applied_dmg, Color(1.0, 0.85, 0.22))` and notify `ArenaNet.note_local_damage_shown(target_id)` if `ArenaNet` is present.

#### [MODIFY] [TaloBackend.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/src/net/TaloBackend.gd) & [ArenaNet.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/src/game/ArenaNet.gd)
- In `TaloBackend._on_socket_message`: allow `"hurt"` messages where `str(p.get("victim", "")) == sender_id` and `int(p.get("dmg", 0))` is in `1..500`, emitting `broadcast_received.emit("hurt", payload)`. (Backwards-compatible with `PROTOCOL_VERSION = "2"` — older peers simply ignore unknown message kinds).
- In `ArenaNet._on_broadcast`: handle `"hurt"`:
  - Look up `victim` in `_remote`. If valid and visible, and not already displayed locally within the last `280ms` (`_local_dmg_shown_at[victim]`), spawn `VfxFactory.damage_number(self, rb.global_position + Vector3(0.0, 0.65, 0.0), float(dmg), Color(1.0, 0.88, 0.26) if attacker == Supabase.user_id else Color(1.0, 0.48, 0.22))`.

---

### Component 3: Particle Explosion VFX, Meteor Mushroom Cloud & Dramatic Death

#### [MODIFY] [VfxFactory.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/src/game/VfxFactory.gd)

1. **`static func particle_explosion(parent: Node3D, pos: Vector3, color: Color, scale: float = 1.0, mushroom: bool = false) -> void`** (with `explosion(...)` calling `particle_explosion(parent, pos, color, scale, false)`):
   - **Stage 0 (Flash & 3D Plasma Core):** `OmniLight3D` capped by `MAX_IMPACT_LIGHTS = 8` + expanding unshaded additive 3D plasma sphere (`_ensure_plasma_sphere()`) + star flare billboard.
   - **Stage 1 (Combustion Core & Velocity-Aligned Spark Streaks):**
     - Dense alpha-blended turbulent fireball (`tex: "fire"`, 4-stop ramp: white-amber → vermilion → deep crimson → zero-alpha soot).
     - Tight additive white-hot inner fire heart (`tex: "fire"`, `explosiveness = 1.0`).
     - `56` high-velocity ballistic spark streaks (`tex: "streak"`, `align: true`, `speed = 10..24 m/s`, gravity `-13 m/s²`) + buoyant drifting embers.
   - **Stage 2 (Standard / Rocket mode, `mushroom = false`):**
     - Rising dark soot plume, ground-hugging dust skirt, dual shockwave rings (additive thermal + matte dust), `12 * _q()` cooling glowing shrapnel slabs (`_rubble_meshes`), secondary `0.14s` internal detonation beat, and organic ground scorch mark.
   - **Stage 2M (Meteor Mushroom Cloud mode, `mushroom = true`):**
     - **Colossal Ground Shockwave & Mach Dust Skirt:** Two massive expanding ground rings (`grow = 11.5` and `grow = 14.0`) + `34` radial ground-hugging dust-and-ash billows (`spread = 88°`, `flatness = 0.82`) rolling outward across the track.
     - **Buoyant Fiery Mushroom Stem:** Focused vertical thermal column (`amount = 58`, `lifetime = 3.2s`, `spread = 14.5°`, `speed = 3.2..6.8 m/s`, upward buoyancy `gravity = Vector3(0, 4.6, 0)`) rising straight up from the crater center, transitioning from incandescent magma-orange at the base to churning dark volcanic soot higher up.
     - **Toroidal Mushroom Cap Canopy (Delayed Beats at `t = 0.14s` and `t = 0.30s`):** Spawned high above the impact point (`pos + Vector3(0, 2.35 * scale, 0)`) using a wide box emission shape (`box = Vector3(1.15, 0.32, 1.15)`), `amount = 64`, `lifetime = 3.5s`, billowing outward and curling with high angular velocity (`angular = 2.8`) and large scale envelope (`curve: [[0, 0.45], [0.32, 1.45], [0.75, 1.85], [1, 2.25]]`) to form an unmistakable wide mushroom cap overhanging the narrower stem!
     - **Transonic Wilson Condensation Ring (`t = 0.10s`):** Elevated expanding vapor ring (`_ring_quad` at `pos + Vector3(0, 1.25 * scale, 0)`, pale steam-white `Color(0.92, 0.94, 0.98, 0.72)`, `grow = 9.5`, `duration = 0.55s`) encircling the rising stem.

2. **`static func mushroom_cloud_explosion(parent: Node3D, pos: Vector3, color: Color = Color(1.0, 0.26, 0.04), scale: float = 2.65) -> void`:**
   - Calls `particle_explosion(parent, pos, color, scale, true)`.

3. **`static func dramatic_death_explosion(parent: Node3D, pos: Vector3, basis: Basis, color: Color, is_pogo: bool = false) -> void`:**
   - **Beat 1 (Primary Kill Detonation):** Calls `particle_explosion(parent, pos, color, 1.65, false)` + extra vertical launch ring (`_ring_quad` at `pos + Vector3(0, 0.4, 0)`, `grow = 9.2`) + `36` high-velocity golden-orange kill sparks.
   - **Beat 2 (Tumbling Charred Wreck Launch, capped at `MAX_WRECKS = 6`):**
     - If not `Settings.reduced_motion()`, spawns a cosmetic `RigidBody3D` wreck (`collision_layer = 0`, `collision_mask = 0`, `mass = 18.0`) at `pos + Vector3(0, 0.55, 0)`:
       - For **Quad (`!is_pogo`)**: a blackened, ember-glowing chassis silhouette (central frame box + 2 axle crossbars) tumbles end-over-end (`linear_velocity = Vector3(rng.randf_range(-4.5, 4.5), rng.randf_range(9.5, 12.8), rng.randf_range(-4.5, 4.5))`, `angular_velocity = Vector3(rng.randf_range(-14, 14), rng.randf_range(-10, 10), rng.randf_range(-14, 14))`).
       - For **Nardus (`is_pogo`)**: a bent, charred pogo-stick + glowing banana-blaster wreck spins skyward with the same dramatic arc.
     - Attaches a continuous one-shot-false `GPUParticles3D` fire-and-soot plume directly to the flying wreck so it leaves an arc of dark smoke and embers across the sky.
   - **Beat 3 (Staggered Mid-Air Cook-Offs at `t = 0.24s` and `t = 0.52s`):**
     - While the wreck is airborne, triggers two secondary mid-air bursts at `wreck.global_position` (`_flash_billboard` + fiery `_particle` pop + spark shower), then shatters and frees the wreck cleanly at `t = 1.65s`.

#### [MODIFY] [RocketProjectile.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/src/game/RocketProjectile.gd) & [MeteorStrike.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/src/game/MeteorStrike.gd)
- `RocketProjectile._detonate`: calls `VFX.particle_explosion(fx, point, Color(1.0, 0.42, 0.10), 1.55, false)`.
- `MeteorStrike._detonate`: calls `VFX.mushroom_cloud_explosion(fx, target_pos, Color(1.0, 0.26, 0.04), 2.65)`.

#### [MODIFY] [CombatController.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/src/game/CombatController.gd) & [NetworkedBike.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/src/game/NetworkedBike.gd)
- In `CombatController._die(by: String)`:
  - Call `VFX.dramatic_death_explosion(_fx_parent(), bike.global_position, bike.global_transform.basis, player_color, str(bike.get("vehicle_profile")) == "pogo")`.
  - Play layered dual-pitch explosion SFX: `_play_sfx("explosion")` + low sub-boom `sfx.call("play", "explosion", 2.5, 0.58)`.
  - Trigger stronger camera shake `_shake(0.82)` and a brief `0.055s` local death hitstop (`Engine.time_scale = 0.25`, guarded by `Settings.reduced_motion()` and restored safely via tree timer) so being blown up feels weighty and cinematic.
- In `NetworkedBike.set_respawning(value: bool)`:
  - When `value == true`, call `VFX.dramatic_death_explosion(fx_parent, global_position, global_transform.basis, player_color, VehicleRegistry.is_pogo(_assigned_vehicle))` so killing a remote opponent launches their smoking wreck skyward too.

---

### Component 4: Nardus in a Pink Borat Mankini with Cute Slightly Red Butt Cheeks

#### [MODIFY] [build_pogo_nardus.py](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/src/build_pogo_nardus.py)

1. **Material Palette (`15` materials total `<= 16` budget):**
   - Replace `SHIRT` and `SHORTS` with:
     - `MANKINI_PINK = mat("MankiniPink", (1.0, 0.10, 0.58), rough=0.34, sheen=0.28, coat=0.22)` — vibrant hot neon-pink Borat mankini fabric.
     - `BUTT_BLUSH = mat("ButtCheekRed", (0.88, 0.37, 0.33), rough=0.52, subsurface=0.18)` — cute, slightly red / rosy-blushed butt-cheek skin tone that contrasts warmly against his `(0.81, 0.54, 0.37)` body `SKIN`.

2. **Bare Athletic Legs, Pelvis & Barrel Torso (`SKIN`):**
   - **Full Bare Legs (`Leg_L`, `Leg_R`):** Extend the bare thigh loft (`SKIN`) smoothly up to `z = 0.895` where it meets the bare pelvis; keep his white crew socks (`SockWhite` with hot-pink & gold varsity stripes!) and brown sport sandals on the foot-pegs.
   - **Bare Pelvis & Barrel Torso (`BarePelvis`, `BareTorso`):** Lofted in `SKIN` using the smooth barrel profile (`z = 0.780..1.512`) so his bare back, bare flanks, and bare chest form a continuous, muscular-yet-chubby caricature body behind his jiggling `Rider/Belly`.
   - **Bare Shoulders & Arms (`Rider/Arm_L`, `Rider/Arm_R`):** Loft the upper arms and shoulder sockets in `SKIN` (no T-shirt sleeves) and add a sporty hot-pink & gold bicep/wrist sweatband (`ArmBand_L/R` in `MANKINI_PINK` + `TRIM_GOLD`).

3. **Conformal Hot-Pink Borat Mankini (`MankiniPink`):**
   - **Front Pouch & High-Cut Hip V-Straps:**
     - `MankiniPouch`: sculpted front cradle (`z = 0.775..0.955, y = -0.22..-0.26`) wrapping under the pelvis groin.
     - `MankiniStrap_L` & `MankiniStrap_R`: continuous closed manifold tubes (`loft_tube`, `seg = 10`) following the exact torso surface contour (`+0.009m` normal offset):
       - Rise from the front pouch (`x = ±0.085, z = 0.91`), angle outward around the high-cut hips (`x = ±0.215, z = 1.05`) and up the front chest (`x = ±0.175, z = 1.28..1.44`),
       - Wrap smoothly over the bare shoulders (`x = ±0.170, z = 1.495`),
       - Angle inward down the bare upper back (`x = ±0.145 -> ±0.035, z = 1.45..1.04`), framing the `Rider/NardusDecal` back tattoo/print cleanly without overlapping it,
       - Converge at the small of his back (`x = 0.0, y = +0.255, z = 1.035`) into a single vertical **rear pink thong strap** (`MankiniThongBack`) diving straight down the gluteal cleft (`x = 0.0, z = 1.035 -> 0.775`) between his two butt cheeks!
   - **Gold Ring Buckle (`MankiniRing`):** A small `TRIM_GOLD` O-ring clasp at the lower-back Y-junction (`z = 1.035, y = +0.262`) where the two back straps join the thong strap.

4. **Cute Little Slightly Red Butt Cheeks (`ButtCheek_L`, `ButtCheek_R` in `ButtCheekRed`):**
   - Positioned on the rear of the pelvis (`+Y` in Blender, which exports to `-Z` in Godot — directly facing the player's chase camera!):
   - Two plump, rounded, C2-smooth anatomical glute spheres (`ButtCheek_L` at `x = -0.118, y = +0.218, z = 0.895`, `ButtCheek_R` at `x = +0.118, y = +0.218, z = 0.895`, radii `(0.124, 0.118, 0.126)`, slight outward/downward cant `rot = (radians(8), 0, sgn * radians(6))`) using `BUTT_BLUSH` (`ButtCheekRed`).
   - They stick out past the pelvis profile by `~0.085m` on either side of the deep central cleft where the hot-pink thong strap sits, giving Nardus an unmistakably funny silhouette from behind and in 3/4 views while keeping `0` non-manifold edges.

---

### Component 5: Gates, Scene Rebuild & Canonical Documentation Sweep

#### [MODIFY] [verify_deathrace.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/tools/verify_deathrace.gd)
- Update the Rocket Launcher cooldown assertions from `5.0` to `1.5` seconds (`is_equal_approx(max_cooldown_for("rocket"), 1.5)` and `remaining_cooldown("rocket") > 1.1`).
- Assert that Rocket and Meteor detonations on `DummyEnemy` spawn floating `Label3D` damage numbers in the scene.

#### [MODIFY] [verify_vfx.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/tools/verify_vfx.gd)
- Add explicit test coverage for:
  - `vf.particle_explosion(holder, pos, col, 1.55, false)`
  - `vf.mushroom_cloud_explosion(holder, pos, col, 2.65)` (verifying the delayed mushroom cap canopy and stem emitters spawn and clean up without script errors)
  - `vf.dramatic_death_explosion(holder, pos, Basis.IDENTITY, col, false)` and `(..., true)` (verifying the tumbling wreck `RigidBody3D` spawns with `collision_layer == 0` under normal motion and is suppressed under `reduced_motion`).

#### [MODIFY] [verify_pogo.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/tools/verify_pogo.gd)
- Assert that `Rider/RiderBody` in `Pogo_Nardus.glb` carries the `MankiniPink` and `ButtCheekRed` materials, and that `KiepieBike.reverse_force >= 250.0`.

#### [MODIFY] [verify_multiplayer.gd](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/godot/tools/verify_multiplayer.gd)
- Add a check that a `"hurt"` broadcast for a visible remote peer (`peer-2`) spawns a floating `Label3D` damage number above `peer-2`'s proxy, and that `TaloBackend` relays authentic victim-authored `"hurt"` messages while dropping spoofed third-party `"hurt"` messages.

#### [MODIFY] [AGENTS.md](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/AGENTS.md), [README.md](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/README.md), [docs/project-plan.md](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/docs/project-plan.md), [docs/task-status.md](file:///home/leandi-duplessis/github/3D builds/kiepie-quad/kiepie-quad-web/docs/task-status.md)
- Sweep `Rocket Launcher (5.0s cooldown)` → `Rocket Launcher (1.5s cooldown)` across all four files, update Nardus's description (pink Borat mankini with slightly red butt cheeks), and record the milestone in `docs/task-status.md`.

---

## Verification Plan

### Automated Tests
1. **Blender Headless Sculpt, Multi-Angle Render & Godot Import:**
   ```bash
   blender -b -noaudio -P src/build_pogo_nardus.py -- --previews renders/nardus_borat
   godot-4.3 --headless --path godot --import
   ```
   - Verify stdout prints `non_manifold=0` and `min_z=0.0000`.
   - Inspect `renders/nardus_borat/nardus_back_closeup.png`, `nardus_back34.png`, `nardus_front34.png`, and `nardus_side.png` using `read_file`.
2. **Targeted Gate Verification:**
   ```bash
   KIEPIE_MOCK_BACKEND=1 godot-4.3 --headless --path godot -s tools/_check_scripts.gd
   KIEPIE_MOCK_BACKEND=1 godot-4.3 --headless --path godot -s tools/verify_pogo.gd
   KIEPIE_MOCK_BACKEND=1 godot-4.3 --headless --path godot -s tools/verify_vfx.gd
   KIEPIE_MOCK_BACKEND=1 godot-4.3 --headless --path godot -s tools/verify_deathrace.gd
   KIEPIE_MOCK_BACKEND=1 godot-4.3 --headless --path godot -s tools/verify_multiplayer.gd
   KIEPIE_MOCK_BACKEND=1 godot-4.3 --headless --path godot -s tools/verify_combat.gd
   ```
3. **Full 27-Gate Suite + Scene Sync:**
   ```bash
   bash godot/tools/run_gates.sh
   ```

### Verify Visual & Transform Claims
- [ ] **Visual claim 1 (Nardus Pink Borat Mankini & Cute Slightly Red Butt Cheeks):** `renders/nardus_borat/nardus_back_closeup.png` and `nardus_back34.png` show Nardus in a conformal hot-pink Borat mankini sling with cute, plump, slightly red butt cheeks sticking out on either side of the rear pink thong strap.
- [ ] **Visual claim 2 (Particle Explosion, Towering Meteor Mushroom Cloud & Tumbling Wreck Death):** `VfxFactory.particle_explosion`, `mushroom_cloud_explosion`, and `dramatic_death_explosion` produce layered fire/sparks, a tall buoyant stem + delayed toroidal mushroom cap + Wilson condensation ring on meteors, and a skyward tumbling smoking wreck with secondary mid-air detonations on death.
- [ ] **Transform claim:** `KiepieBike.reverse_force == 265.0`, `SideCannons.ROCKET_COOLDOWN == 1.5`, `ArenaNet.REMOTE_ROCKET_MIN_S == 1.15`, and cross-player floating `Label3D` damage numbers appear on all remote player hits (attacker + spectators).
- [ ] **Verification method:** Direct visual inspection of Blender render PNGs via `read_file` + 27/27 PASS in `bash godot/tools/run_gates.sh`.
