#!/usr/bin/env python3
"""Verify Web deploy hygiene: .vercelignore allowlist, vercel.json security headers, index.html viewport, and every-launch splash."""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    failures: list[str] = []

    # 1. .vercelignore must allow ONLY index.*, favicon.ico, web-assets/**
    vi = ROOT / ".vercelignore"
    shipped: list[str] = []
    if not vi.is_file():
        failures.append("missing .vercelignore")
    else:
        try:
            files = subprocess.check_output(["git", "ls-files"], cwd=ROOT, stderr=subprocess.DEVNULL).decode().splitlines()
            p = subprocess.run(
                ["git", "-c", f"core.excludesfile={vi}", "check-ignore", "--no-index", "--stdin"],
                cwd=ROOT,
                input="\n".join(files) + "\n",
                text=True,
                capture_output=True,
            )
            ignored = set(p.stdout.splitlines())
            shipped = [f for f in files if f not in ignored]
            disallowed = [
                f for f in shipped
                if not (f.startswith("index.") or f == "favicon.ico" or f.startswith("web-assets/"))
            ]
            if disallowed:
                failures.append(f".vercelignore leaks non-runtime files: {disallowed[:5]}")
        except (subprocess.CalledProcessError, FileNotFoundError):
            # Outside a .git worktree (e.g., git archive export): verify runtime files exist on disk.
            shipped = [
                p.relative_to(ROOT).as_posix()
                for p in ROOT.rglob("*")
                if p.is_file() and (p.name.startswith("index.") or p.name == "favicon.ico" or "web-assets/" in p.relative_to(ROOT).as_posix())
            ]
            print("web_hygiene NOTE: not a git worktree; skipped git check-ignore")

    # Apply the allowlist/count checks to BOTH the git and git-archive paths.
    if shipped:
        leaked = [
            f for f in shipped
            if not (f.startswith("index.") or f == "favicon.ico" or f.startswith("web-assets/"))
        ]
        if leaked:
            failures.append(f"shipped file allowlist leaks non-runtime files: {leaked[:5]}")
        if len(shipped) < 13:
            failures.append(f"too few runtime files shipped ({len(shipped)})")

    # 2. vercel.json must define COOP, COEP, nosniff, Referrer-Policy per route rule
    vj = ROOT / "vercel.json"
    if not vj.is_file():
        failures.append("missing vercel.json")
    else:
        try:
            cfg = json.loads(vj.read_text(encoding="utf-8"))
            headers_rules = cfg.get("headers", [])
            valid_coep = {"unsafe-none", "require-corp", "credentialless"}
            root_rule_headers: dict[str, str] | None = None
            for rule in headers_rules:
                rmap = {h["key"].lower(): h["value"] for h in rule.get("headers", [])}
                if "cross-origin-embedder-policy" in rmap and rmap["cross-origin-embedder-policy"] not in valid_coep:
                    failures.append(
                        f"vercel.json rule {rule.get('source')} has invalid COEP value: {rmap['cross-origin-embedder-policy']!r}"
                    )
                if rule.get("source") == "/(.*)":
                    root_rule_headers = rmap
            if root_rule_headers is None:
                failures.append("vercel.json missing root /(.*) header rule")
            else:
                if root_rule_headers.get("cross-origin-opener-policy") != "same-origin":
                    failures.append(
                        f"vercel.json /(.*) expected COOP='same-origin', got {root_rule_headers.get('cross-origin-opener-policy')!r}"
                    )
                if root_rule_headers.get("cross-origin-embedder-policy") != "require-corp":
                    failures.append(
                        f"vercel.json /(.*) expected COEP='require-corp', got {root_rule_headers.get('cross-origin-embedder-policy')!r}"
                    )
                if root_rule_headers.get("x-content-type-options") != "nosniff":
                    failures.append(
                        f"vercel.json /(.*) expected X-Content-Type-Options='nosniff', got {root_rule_headers.get('x-content-type-options')!r}"
                    )
                if "referrer-policy" not in root_rule_headers:
                    failures.append("vercel.json /(.*) missing header: referrer-policy")
                if root_rule_headers.get("cross-origin-resource-policy") != "same-origin":
                    failures.append("vercel.json /(.*) expected CORP='same-origin'")
            asset_rules = [r for r in headers_rules if r.get("source") == "/web-assets/(.*)"]
            if not asset_rules:
                failures.append("vercel.json missing /web-assets/(.*) header rule")
            else:
                amap = {h["key"].lower(): h["value"] for h in asset_rules[0].get("headers", [])}
                if "immutable" not in amap.get("cache-control", ""):
                    failures.append("vercel.json /web-assets/(.*) missing immutable Cache-Control")
        except Exception as exc:
            failures.append(f"vercel.json parse error: {exc}")

    # 3. index.html must ship exactly 1 accessible viewport meta tag (no user-scalable=no)
    idx = ROOT / "index.html"
    if not idx.is_file():
        failures.append("missing index.html")
    else:
        html = idx.read_text(encoding="utf-8")
        metas = re.findall(r"<meta\s+name=['\"]viewport['\"][^>]*>", html, flags=re.IGNORECASE)
        if len(metas) != 1:
            failures.append(f"index.html expected 1 viewport meta tag, found {len(metas)}")
        elif "user-scalable=no" in metas[0].lower():
            failures.append(f"index.html viewport meta still contains user-scalable=no: {metas[0]}")
        else:
            meta = metas[0].lower()
            if "width=device-width" not in meta or "initial-scale" not in meta:
                failures.append(f"index.html viewport must set width=device-width and initial-scale: {metas[0]}")

        # 4. index.html must play the intro splash on every launch (no localStorage suppression or ?splash=1 hack)
        splash_tag = re.search(r"<video[^>]*kiepie-quad-splash\.mp4[^>]*>", html, flags=re.IGNORECASE)
        if splash_tag is None:
            failures.append("index.html missing intro splash video reference")
        else:
            tag = splash_tag.group(0).lower()
            if "autoplay" not in tag or "muted" not in tag:
                failures.append("index.html splash video must be autoplay+muted for Web autoplay policy")
        if "prefers-reduced-motion" not in html:
            failures.append("index.html missing prefers-reduced-motion splash bypass")
        if "kiepie_splash_seen" in html:
            failures.append("index.html still suppresses intro splash via localStorage (kiepie_splash_seen)")
        if "splash=1" in html:
            failures.append("index.html still contains ?splash=1 query workaround")
        if "getElementById('victory-skip')" not in html or "addEventListener('click',drop)" not in html:
            failures.append("index.html missing WCAG 2.1.1 click listener on splash skip buttons")

    # 6. Shipped-artifact proof: policy-file checks alone cannot catch an
    #    export filter that silently drops Evan's GLB or compiled scripts.
    pck = ROOT / "index.pck"
    REQUIRED_PCK_PATHS = [
        "res://assets/Evan_Skeleton.glb",
        "res://src/game/EvanVisual.gdc",
        "res://src/game/SoundWaveProjectile.gdc",
        "res://src/game/BoomerangGuitar.gdc",
        "res://src/game/DevilHandStrike.gdc",
        "res://assets/Lea_Unicorn.glb",
        "res://src/game/LeaVisual.gdc",
        "res://src/game/HornBoltProjectile.gdc",
        "res://src/game/HornBeam.gdc",
        "res://src/game/UnicornBoom.gdc",
    ]
    if not pck.is_file():
        failures.append("missing index.pck")
    else:
        pck_bytes = pck.read_bytes()
        for path in REQUIRED_PCK_PATHS:
            if path.encode("utf-8") not in pck_bytes:
                failures.append(f"index.pck is missing shipped artifact: {path}")
    sw = ROOT / "index.service.worker.js"
    if not sw.is_file():
        failures.append("missing index.service.worker.js")
    else:
        worker = sw.read_text(encoding="utf-8")
        precached = set(re.findall(r"['\"](index\.[A-Za-z0-9.]+)['\"]", worker))
        for name in sorted(precached):
            if not (ROOT / name).is_file():
                failures.append(f"service worker precaches missing file: {name}")

    # 5. patch_web_sw.py must fail fast on template drift or double-patching
    try:
        sys.dont_write_bytecode = True
        tools_dir = str(Path(__file__).resolve().parent)
        if tools_dir not in sys.path:
            sys.path.insert(0, tools_dir)
        import test_patch_web_sw
        test_patch_web_sw.run_tests()
    except Exception as exc:
        failures.append(f"test_patch_web_sw failed: {exc}")

    if failures:
        for f in failures:
            print(f"FAIL web_hygiene: {f}", file=sys.stderr)
        return 1
    print(f"web_hygiene OK (.vercelignore={len(shipped)} runtime files, vercel.json headers, single WCAG viewport, every-launch splash)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
