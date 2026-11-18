#!/usr/bin/env bash
# Kiepie Quad — full Web build + deploy helper.
# Dry-run by default: runs gates, rebuilds the export and checks the pck.
# Pass --apply to commit/push web/ and run the production Vercel deploy.
# Pushes to web/ do NOT auto-deploy (no Vercel git hook) — see AGENTS.md.
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

echo "== web export"
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
WASM_HASH=$(sha256sum "$ROOT/web/index.wasm" | cut -c1-12)
PCK_HASH=$(sha256sum "$ROOT/web/index.pck" | cut -c1-12)
python3 "$HERE/patch_web_sw.py" "$ROOT/web/index.service.worker.js" || {
	echo "DEPLOY ABORTED: failed to patch service worker"; exit 1;
}
echo "   web bundle complete (wasm=$WASM_HASH pck=$PCK_HASH)"

if [ "$APPLY" -ne 1 ]; then
	echo "DRY RUN only. Re-run with --apply to commit, push and deploy."
	exit 0
fi

echo "== commit + push web/"
cd "$ROOT/web"
if [ -n "$(git status --porcelain)" ]; then
	git add -A
	git status --short
	git commit -m "deploy(web): wasm=$WASM_HASH pck=$PCK_HASH" || { echo "DEPLOY ABORTED: commit failed"; exit 1; }
else
	echo "   web bundle unchanged — nothing to commit"
fi
git push origin main || { echo "DEPLOY ABORTED: push failed"; exit 1; }

echo "== vercel deploy"
vercel deploy --prod --yes --scope teacher-evans-projects --name kiepie-quad-web || {
	echo "DEPLOY ABORTED: vercel deploy failed"; exit 1;
}
CODE=$(curl -s -o /dev/null -w "%{http_code}" https://kiepie-quad-web.vercel.app)
echo "live alias HTTP $CODE"
[ "$CODE" = "200" ] || { echo "DEPLOY WARNING: live alias did not return 200"; exit 1; }
echo "DEPLOY OK"
