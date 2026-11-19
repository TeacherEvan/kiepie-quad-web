#!/usr/bin/env python3
"""Verify Web deploy hygiene: .vercelignore allowlist, vercel.json security headers, and index.html viewport."""
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
    if not vi.is_file():
        failures.append("missing .vercelignore")
    else:
        files = subprocess.check_output(["git", "ls-files"], cwd=ROOT).decode().splitlines()
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
        if len(shipped) < 13:
            failures.append(f".vercelignore ships too few runtime files ({len(shipped)})")

    # 2. vercel.json must define COOP, COEP, nosniff, Referrer-Policy
    vj = ROOT / "vercel.json"
    if not vj.is_file():
        failures.append("missing vercel.json")
    else:
        try:
            cfg = json.loads(vj.read_text(encoding="utf-8"))
            keys = {
                h["key"].lower(): h["value"]
                for rule in cfg.get("headers", [])
                for h in rule.get("headers", [])
            }
            for req in [
                "cross-origin-opener-policy",
                "cross-origin-embedder-policy",
                "x-content-type-options",
                "referrer-policy",
            ]:
                if req not in keys:
                    failures.append(f"vercel.json missing header: {req}")
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

    if failures:
        for f in failures:
            print(f"FAIL web_hygiene: {f}", file=sys.stderr)
        return 1
    print(f"web_hygiene OK (.vercelignore={len(shipped)} runtime files, vercel.json headers, single WCAG viewport)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
