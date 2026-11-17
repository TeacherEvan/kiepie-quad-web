#!/usr/bin/env bash
# Kiepie Quad — full Web build + deploy helper (single repo: TeacherEvan/kiepie-quad-web).
# Dry-run by default: runs gates, rebuilds the staging export (git-ignored web/) and checks the pck.
# Pass --apply to sync web/ → repo root, commit index.*, push to main (Vercel auto-deploys) and curl-check the live alias.
# Pushes to main auto-deploy (verified 2026-11-18) — see AGENTS.md.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"
GODOT="${GODOT:-godot-4.3}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

echo "== gates"
bash godot/tools/run_gates.sh || { echo "DEPLOY ABORTED: gates failed"; exit 1; }

echo "== talo key"
python3 godot/tools/inject_talo_key.py || { echo "DEPLOY ABORTED: no Talo game key"; exit 1; }

echo "== web export (staging: web/ — git-ignored)"
"$GODOT" --headless --path godot --export-release "Web" "$ROOT/web/index.html" || {
	echo "DEPLOY ABORTED: export failed"; exit 1;
}
PCK="$ROOT/web/index.pck"
SIZE=$(stat -c %s "$PCK" 2>/dev/null || echo 0)
echo "   index.pck: $((SIZE / 1024 / 1024)) MB ($SIZE bytes)"
if [ "$SIZE" -gt 4194304 ]; then
	echo "DEPLOY ABORTED: pck unexpectedly large (expected ~3.0 MB, saw $SIZE)"
	exit 1
fi
for f in index.html index.js index.wasm index.manifest.json index.service.worker.js; do
	[ -s "$ROOT/web/$f" ] || { echo "DEPLOY ABORTED: missing $f"; exit 1; }
done
# Godot 4.3's generated PWA service worker precaches index.worker.js (missing on
# single-threaded exports) and serves stale index.html/index.pck Cache-First.
python3 "$HERE/patch_web_sw.py" "$ROOT/web/index.service.worker.js" || {
	echo "DEPLOY ABORTED: failed to patch service worker"; exit 1;
}
echo "   web bundle complete"

if [ "$APPLY" -ne 1 ]; then
	echo "DRY RUN only. Re-run with --apply to sync, commit, push and verify the live alias."
	exit 0
fi

echo "== sync web/ -> repo root"
cp -f "$ROOT/web/"* "$ROOT/" || { echo "DEPLOY ABORTED: sync failed"; exit 1; }
git add index.html index.js index.wasm index.pck index.manifest.json index.service.worker.js \
	  index.audio.worklet.js index.offline.html index.png favicon.ico index.144x144.png \
	  index.180x180.png index.512x512.png
git commit -m "Kiepie Quad: web export refresh $(date -u +%Y-%m-%dT%H:%M:%SZ)" || {
	echo "   (nothing to commit — bundle identical)"
}
git push origin main || { echo "DEPLOY ABORTED: push failed"; exit 1; }

echo "== verify Vercel auto-deploy (live alias)"
LOCAL_MD5=$(md5sum "$ROOT/index.html" | awk '{print $1}')
for i in $(seq 1 24); do
	sleep 5
	LIVE_MD5=$(curl -s https://kiepie-quad-web.vercel.app/index.html | md5sum | awk '{print $1}')
	if [ "$LIVE_MD5" = "$LOCAL_MD5" ]; then
		echo "DEPLOY OK — live alias serves the pushed build ($LIVE_MD5)"
		exit 0
	fi
done
echo "DEPLOY WARNING: live alias did not match the pushed build after 120 s" >&2
exit 1
