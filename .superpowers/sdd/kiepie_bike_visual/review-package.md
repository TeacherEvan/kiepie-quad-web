# Review package — visual overhaul diff (working tree, not the web/ git history)

Read these files in full (small):

- godot/tools/build_testride.gd        (tactile HUD chips/buttons, asphalt+cone textures, facades, lighting; also: removed invalid StaticBody3D.connect)
- godot/tools/build_bike.gd            (unchanged this phase — check nothing broke)
- godot/tools/verify_features.gd       (expect-43 string fix)
- godot/tools/verify_smash_impact.gd   (new — end-to-end impact test)
- godot/src/KiepieBike.gd              (added group "bike" at _ready)
- godot/src/DestructibleBuilding.gd    (Area3D SmashTrigger in _ready, _on_body_entered(body: Node), is_inside_tree guards, deferred collider disable, smash-first notify)
- godot/src/Hud.gd                     (group "hud" in _init, no connect-loop)
- godot/src/FollowCam.gd               (free-orbit mode, FOV kick, camera_toggle input)
- assets/tex_*.png                     (binary, do not parse)
- godot/export_presets.cfg             (unchanged this phase — Task 3 will touch it)

Context (do not re-review, already QA'd): src/qb_body.py fender reshape, number plates,
Model flip revert, every earlier commit through web 2faddd7 (repo web/).

Binding constraints: see task-2-brief.md (behavior freeze, node names, scene APIs, deploy scope).
