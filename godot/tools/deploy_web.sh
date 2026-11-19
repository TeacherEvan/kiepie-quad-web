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

# Serialize deploys: two overlapping runs interleave web/ artifacts and push
# mismatched bundles. Fail fast instead of racing.
# per-machine lock in /tmp — never a repo artifact
LOCK="${TMPDIR:-/tmp}/kiepie-quad-web-deploy.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
	echo "DEPLOY ABORTED: another deploy_web.sh run is in progress (lock: $LOCK)"
	exit 1
fi

# inject_talo_key.py rewrites the git-ignored addons/talo/settings.cfg with the
# live production key. Back it up up front and restore/remove on exit so the
# key never lingers in the working tree after the export.
SETTINGS_CFG="$ROOT/godot/addons/talo/settings.cfg"
SETTINGS_BAK=""
if [ -f "$SETTINGS_CFG" ]; then
	SETTINGS_BAK="$(mktemp "${TMPDIR:-/tmp}/talo-settings.XXXXXX")"
	cp -p "$SETTINGS_CFG" "$SETTINGS_BAK"
fi
cleanup() {
	if [ -n "$SETTINGS_BAK" ]; then
		mv -f "$SETTINGS_BAK" "$SETTINGS_CFG"
	else
		rm -f "$SETTINGS_CFG"
	fi
}
trap cleanup EXIT

echo "== gates"
bash godot/tools/run_gates.sh || { echo "DEPLOY ABORTED: gates failed"; exit 1; }

echo "== talo key"
python3 godot/tools/inject_talo_key.py || { echo "DEPLOY ABORTED: no Talo game key"; exit 1; }

echo "== web export (staging: web/ — git-ignored)"
# Start from a clean slate: leftover chunks from an older export would mix in.
rm -rf "$ROOT/web"
mkdir -p "$ROOT/web"
"$GODOT" --headless --path godot --export-release "Web" "$ROOT/web/index.html" || {
	echo "DEPLOY ABORTED: export failed"; exit 1;
}
PCK="$ROOT/web/index.pck"
SIZE=$(stat -c %s "$PCK" 2>/dev/null || echo 0)
echo "   index.pck: $((SIZE / 1024 / 1024)) MB ($SIZE bytes)"
if [ "$SIZE" -gt 4194304 ]; then
	echo "DEPLOY ABORTED: pck unexpectedly large (expected ~3.4 MB, saw $SIZE)"
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
python3 "$HERE/patch_web_html.py" "$ROOT/web/index.html" || {
	echo "DEPLOY ABORTED: failed to patch index.html"; exit 1;
}
echo "   web bundle complete"

if [ "$APPLY" -ne 1 ]; then
	echo "DRY RUN only. Re-run with --apply to sync, commit, push and verify the live alias."
	exit 0
fi

echo "== sync web/ -> repo root"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || {
	echo "DEPLOY ABORTED: --apply must run from branch 'main' (on $(git rev-parse --abbrev-ref HEAD))"
	exit 1
}
cp -f "$ROOT/web/"* "$ROOT/" || { echo "DEPLOY ABORTED: sync failed"; exit 1; }
BUNDLE_FILES=(
	index.html index.js index.wasm index.pck index.manifest.json index.service.worker.js
	index.audio.worklet.js index.offline.html index.png favicon.ico index.144x144.png
	index.180x180.png index.512x512.png
)
if git diff --quiet -- "${BUNDLE_FILES[@]}" && git diff --cached --quiet -- "${BUNDLE_FILES[@]}"; then
	echo "   (nothing to commit — bundle identical)"
else
	# --only commits exactly these paths even if unrelated files are staged already.
	git commit --only -m "Kiepie Quad: web export refresh $(date -u +%Y-%m-%dT%H:%M:%SZ)" -- \
		"${BUNDLE_FILES[@]}" || { echo "DEPLOY ABORTED: commit failed"; exit 1; }
fi
git push origin main || { echo "DEPLOY ABORTED: push failed"; exit 1; }

echo "== verify Vercel auto-deploy (live alias)"
LOCAL_HTML_MD5=$(md5sum "$ROOT/index.html" | awk '{print $1}')
LOCAL_SW_MD5=$(md5sum "$ROOT/index.service.worker.js" | awk '{print $1}')
for i in $(seq 1 24); do
	sleep 5
	LIVE_HTML_MD5=$(curl --fail --max-time 10 -s https://kiepie-quad-web.vercel.app/index.html | md5sum | awk '{print $1}') || LIVE_HTML_MD5=""
	LIVE_SW_MD5=$(curl --fail --max-time 10 -s https://kiepie-quad-web.vercel.app/index.service.worker.js | md5sum | awk '{print $1}') || LIVE_SW_MD5=""
	if [ -n "$LIVE_HTML_MD5" ] && [ "$LIVE_HTML_MD5" = "$LOCAL_HTML_MD5" ] \
			&& [ -n "$LIVE_SW_MD5" ] && [ "$LIVE_SW_MD5" = "$LOCAL_SW_MD5" ]; then
		echo "DEPLOY OK — live alias serves the pushed build (html=$LIVE_HTML_MD5 sw=$LIVE_SW_MD5)"
		exit 0
	fi
done
echo "DEPLOY WARNING: live alias did not match the pushed build after 120 s" >&2
exit 1
