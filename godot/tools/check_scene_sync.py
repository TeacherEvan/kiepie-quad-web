#!/usr/bin/env python3
"""Gate: tracked .tscn files must match their builders.

The scene builders (tools/build_*.gd) are the source of truth for
godot/scenes/*.tscn. Gates rebuild the scenes on every run, which
re-emits resource UIDs/load_steps/format and reshuffles sub_resource
ids — pure churn that must not fail this gate. Anything *else* that
diff appears means either:

  1. someone edited a generated scene in the Inspector (it will be
     silently overwritten on the next rebuild), or
  2. a builder changed output and the scene was not re-committed.

Both are exactly the drift this gate exists to catch (it would have
failed loudly on the historical 2.87 MB KiepieBike.tscn, which baked
duplicate GLB meshes inline).

Run AFTER the builders, i.e. from run_gates.sh's build section.
Exit 0 = in sync (or skipped: --no-build / not a git repo / untracked
scenes). Exit 1 = drift detected (offenders printed).
"""

from __future__ import annotations

import re
import subprocess
import sys
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCENES = [
    "godot/scenes/KiepieBike.tscn",
    "godot/scenes/TestRide.tscn",
    "godot/scenes/Arena.tscn",
    "godot/scenes/DeathRace.tscn",
    "godot/scenes/MainMenu.tscn",
    "godot/scenes/SettingsMenu.tscn",
    "godot/scenes/LobbyMenu.tscn",
]


def _attrs(line: str) -> dict:
    return dict(re.findall(r'([A-Za-z_][\w-]*)="([^"]*)"', line))


def normalize(text: str) -> str:
    raw_lines = text.splitlines()
    # Pass 1: collect the resource-id -> identity map. Collapsing every
    # reference to ExtResource(X) made node property lines indistinguishable,
    # so swapping two script assignments between nodes slipped through.
    ext_map: dict[str, str] = {}
    sub_map: dict[str, str] = {}
    for raw in raw_lines:
        stripped = raw.strip()
        if stripped.startswith("[ext_resource"):
            attrs = _attrs(stripped)
            if "id" in attrs and "path" in attrs:
                ext_map[attrs["id"]] = attrs["path"]
        elif stripped.startswith("[sub_resource"):
            attrs = _attrs(stripped)
            if "id" in attrs:
                sub_map[attrs["id"]] = attrs.get("type", "SubResource")
    out: list[str] = []
    for raw in raw_lines:
        line = raw.rstrip()
        if line.startswith("[gd_scene "):
            # load_steps count and format version are volatile serializer noise
            out.append("[gd_scene]")
            continue
        # volatile resource ids / uuid-ish attributes, but keep everything else
        line = re.sub(r'\bid="[^"]*"', 'id="X"', line)
        line = re.sub(r"load_steps=\d+", "load_steps=N", line)
        line = re.sub(r'ExtResource\("([^"]*)"\)',
                      lambda m: 'ExtResource(%s)' % ext_map.get(m.group(1), "X"), line)
        line = re.sub(r'SubResource\("([^"]*)"\)',
                      lambda m: 'SubResource(%s)' % sub_map.get(m.group(1), "X"), line)
        line = re.sub(r'uid="uid://[^"]*"', 'uid="uid://X"', line)
        out.append(line)
    # collapse runs of blank lines for stability
    joined = "\n".join(out)
    joined = re.sub(r"\n{3,}", "\n\n", joined)
    return joined


def head_content(path: str) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "show", f"HEAD:{path}"], cwd=ROOT, text=True
        )
    except Exception:
        return None


def main() -> int:
    offenders: list[str] = []
    checked = 0
    for scene in SCENES:
        path = os.path.join(ROOT, scene)
        if not os.path.exists(path):
            print(f"scene_sync SKIP {scene} (missing in worktree)")
            continue
        head = head_content(scene)
        if head is None:
            print(f"scene_sync SKIP {scene} (not tracked in HEAD / git unavailable)")
            continue
        checked += 1
        work = normalize(open(path, encoding="utf-8").read())
        base = normalize(head)
        if work != base:
            offenders.append(scene)
    if offenders:
        print("scene_sync FAIL — tracked scene differs from builder output:")
        for scene in offenders:
            print(f"  - {scene}  (commit the rebuilt scene, or revert the hand edit)")
        return 1
    if checked == 0:
        print("scene_sync SKIP — nothing comparable (not a git repo?)")
        return 0
    print(f"scene_sync OK — {checked} generated scenes match HEAD (modulo resource-id churn)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
