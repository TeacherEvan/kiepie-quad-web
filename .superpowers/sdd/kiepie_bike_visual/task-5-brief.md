# Task 5 — Touch overlay (mobile playability) — surgical-orchestration Step 1a (single scope)

```agentplan
@META id=BP-2026-1116-05|repo=kiepie-bike|branch=local(not a git repo)|only web/ versioned
@STACK gdscript|godot-4.3|headless SceneTree tools|vercel
@GATE scenebuild=godot-4.3 --headless --path godot --script tools/build_testride.gd|truth=tools/truth_test.gd|features=tools/verify_features.gd|touch=tools/verify_touch.gd
@ENTRY builder called once -> res://scenes/TestRide.tscn, then Web export, vercel deploy x2 urls
@FACT F1 TestRide.tscn is BUILDER-GENERATED; edit build_testride.gd never the .tscn|godot/tools/build_testride.gd:55
@FACT F2 HUD is a CanvasLayer sibling of KiepieBike added via root.add_child(layer); buttons FOCUS_NONE + _style_button(btn, accent)|build_testride.gd:166-248
@FACT F3 InputMap frozen actions: move_forward/back, steer_left/right, brake, turbo, reset_bike|godot/project.godot [input]
@FACT F4 KiepieBike reads Input.is_action_pressed in _physics_process; reset via is_action_just_pressed(reset_bike)|src/KiepieBike.gd:106-133
@FACT F5 HUD resets bike by direct call bike.reset_bike() through ../KiepieBike|src/Hud.gd _on_restart
@FACT F6 builder buttons need mouse_filter sane + focus FOCUS_NONE; rebuild PackedScene via scene.pack()|build_testride.gd:248-262
@GAP G1 no touch UI anywhere|conf=high|checked=grep -ri "touch" src tools scenes project.godot export_presets.cfg (only a ramp comment matched)
@RISK R1 stuck action (finger slides off button) -> quad throttles forever|blast=wide|mitigate=per-frame is_pressed reconcile + release-all on hide/exit
@RISK R2 overlay covers HUD/smash counter at 390px|blast=narrow|mitigate=anchors bottom-left/right, offsets below Restart/View; verify 390px screenshot
@RISK R3 touchscreen detection false on dev desktop -> overlay unreachable|blast=med|mitigate=TOUCH toggle button force-shows/hides (also needed for headless verify)

@JOB J1 [ ] scope=godot/src|goal=TouchControls.gd: CanvasLayer autodetect+TOUCH toggle+hold actions+stuck-key reconcile|gate=verify_touch.gd
@JOB J2 [ ] scope=godot/tools|goal=builder _add_touch_controls: steer/GAS/BRAKE/TURBO + TOUCH toggle, anchored bottom corners
# RULING (post-review, self-amend): RST omitted by design - HUD RestartBtn (136x44, tap-ok) is the reset path; sign-off recorded here. Sizes: >=44px is the binding floor (gate-enforced); ~96px main axis is preferred but infeasible in the 390px budget with two steer + three action buttons (overlap), so steer/brake/turbo stay 84-100px x 66-110px. Brief J3 44px wins; J2 amended accordingly.|gate=build_testride.gd saved
@JOB J3 [ ] scope=godot/tools|goal=verify_touch.gd: emit button_down/up, assert Input state, toggle logic, focus NONE, sizes >=44|gate=verify_touch.gd PASS
@JOB J4 [ ] scope=web/|goal=reexport, deploy kiepie-quad-web + kiepie-bike, 390px verify overlay visible, commit+push main|gate=console clean + screenshot
@JOB J5 [ ] scope=godot/ (read-only)|goal=dual-lane FE/AMBIGUOUS review of J1-J3 diff; compose <=2 recs + <=2 sugg; park minors|gate=review verdicts
@SEQ J1->J2->J3->J4->J5
@BAN hand-edit web/index.html|hand-edit TestRide.tscn|touch export_presets.cfg head_include|rename KB_* nodes|alter InputMap
```

User (2026-11-16): "@surgical-orchestration plan and implement" — implements the touch-overlay gap flagged in the best-practices close-out. Single-scope => Step 1a: direct build, no WORKER/VERIFIER fan-out; Step 5 read-only post-build review instead.
