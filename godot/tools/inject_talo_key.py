#!/usr/bin/env python3
"""Inject the Talo *game* key from the repo-root .env into the Godot plugin config.

The admin key (TALO_API_ADMIN) is deliberately ignored — the v1 game API rejects it.
Run before any Web export. The key ends up inside the public .pck by design; it must
be a scoped, disposable dev key, never an admin/service credential.
"""
from pathlib import Path
import os
import sys

HERE = Path(__file__).resolve().parent
GODOT = HERE.parent
ROOT = GODOT.parent
ENV = ROOT / ".env"
OUT = GODOT / "addons/talo/settings.cfg"


def read_env() -> dict:
    values = {}
    if not ENV.exists():
        return values
    for line in ENV.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"\'')
    return values


def main() -> int:
    values = read_env()
    key = values.get("TALO_API_GAME", "")
    if not key.startswith("eyJ"):
        print("inject_talo_key: TALO_API_GAME missing or not a JWT game key (admin keys are rejected)", file=sys.stderr)
        return 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        f'access_key="{key}"\n'
        'api_url="https://api.trytalo.com"\n'
        'socket_url="wss://api.trytalo.com"\n'
        'auto_connect_socket=false\n'   # TaloBackend opens only when real mode is active
        'handle_tree_quit=false\n'      # don't override the game's own quit flow
        '\n[continuity]\n'
        'enabled=false\n',
        encoding="utf-8",
    )
    os.chmod(OUT, 0o600)
    print(f"inject_talo_key: wrote {OUT.relative_to(ROOT)} ({len(key)} char game key)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
