#!/usr/bin/env python3
"""Patch Godot's exported index.html so it ships a single WCAG-compliant viewport meta."""
import os
import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_web_html.py <path/to/index.html>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    html = path.read_text(encoding="utf-8")
    desired = '<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">'
    # Replace Godot's default user-scalable=no viewport meta and remove any duplicates.
    pattern = re.compile(r"<meta\s+name=['\"]viewport['\"][^>]*>", re.IGNORECASE)
    matches = list(pattern.finditer(html))
    if not matches:
        print("patch_web_html: no viewport meta tag found", file=sys.stderr)
        return 1
    out = pattern.sub("", html)
    # Re-insert exactly one clean viewport meta right after <meta charset="utf-8">
    out, n = re.subn(
        r'(<meta\s+charset=["\']utf-8["\']\s*/?>)',
        r"\1\n\t\t" + desired,
        out,
        count=1,
        flags=re.IGNORECASE,
    )
    if n != 1:
        print("patch_web_html: could not locate charset meta anchor", file=sys.stderr)
        return 1
    tmp = path.with_suffix(path.suffix + ".tmp")
    try:
        with tmp.open("w", encoding="utf-8") as fh:
            fh.write(out)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise
    print(f"patch_web_html: consolidated {len(matches)} viewport meta(s) -> 1 accessible tag in {path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
