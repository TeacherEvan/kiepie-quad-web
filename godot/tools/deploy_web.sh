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
WEB_FILES=(
	index.html index.js index.wasm index.pck index.manifest.json index.service.worker.js
	index.audio.worklet.js index.offline.html index.png favicon.ico index.144x144.png
	index.180x180.png index.512x512.png
)
SYNC_OK=0
BUNDLE_BAK=""

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
	SETTINGS_BAK="$(mktemp "${TMPDIR:-/tmp}/talo-settings.XXXXXX")" || exit 1
	cp -p "$SETTINGS_CFG" "$SETTINGS_BAK" || exit 1
fi
cleanup() {
	if [ -n "$SETTINGS_BAK" ]; then
		mv -f "$SETTINGS_BAK" "$SETTINGS_CFG"
	else
		rm -f "$SETTINGS_CFG"
	fi
	# A partial sync must never leave a mixed wasm/pck pair in the served root.
	if [ "$APPLY" -eq 1 ] && [ "$SYNC_OK" -eq 0 ] && [ -n "$BUNDLE_BAK" ]; then
		for f in "${WEB_FILES[@]}"; do
			[ -f "$BUNDLE_BAK/$f" ] || continue
			cp -p "$BUNDLE_BAK/$f" "$ROOT/.$f.rollback" && mv -f "$ROOT/.$f.rollback" "$ROOT/$f"
		done
		echo "DEPLOY: restored pre-sync bundle from $BUNDLE_BAK" >&2
	fi
	[ -n "$BUNDLE_BAK" ] && rm -rf "$BUNDLE_BAK"
}
trap cleanup EXIT

echo "== gates"
SCENES_CLEAN=0
if git diff --quiet -- godot/scenes/ && git diff --cached --quiet -- godot/scenes/; then
	SCENES_CLEAN=1
fi
bash godot/tools/run_gates.sh || { echo "DEPLOY ABORTED: gates failed"; exit 1; }
if [ "$SCENES_CLEAN" -eq 1 ]; then
	git checkout -- godot/scenes/
fi

echo "== talo key"
python3 godot/tools/inject_talo_key.py || { echo "DEPLOY ABORTED: no Talo game key"; exit 1; }

echo "== web export (staging: web/ — git-ignored)"
# Start from a clean slate: leftover chunks from an older export would mix in.
rm -rf "$ROOT/web"
mkdir -p "$ROOT/web"
timeout --foreground 240 "$GODOT" --headless --path godot --export-release "Web" "$ROOT/web/index.html" || {
	echo "DEPLOY ABORTED: export failed"; exit 1;
}
PCK="$ROOT/web/index.pck"
SIZE=$(stat -c %s "$PCK" 2>/dev/null || echo 0)
echo "   index.pck: $((SIZE / 1024 / 1024)) MB ($SIZE bytes)"
# Budget raised 4 MiB -> 4.5 MiB on 2026-11-25 for EVAN THE SKELETON: his
# Godot-compatible (non-Draco) GLB adds ~0.7 MB to the pck. LEA UNICORN's plain
# GLB adds ~0.58 MB more; measured export is ~4.47 MB / 4,685,856 bytes with
# only ~32 KB of headroom under this guard — raise it before adding another
# non-Draco vehicle GLB.
if [ "$SIZE" -lt 1048576 ] || [ "$SIZE" -gt 4718592 ]; then
	echo "DEPLOY ABORTED: pck size out of range [1 MiB, 4.5 MiB] (saw $SIZE)"
	exit 1
fi
for f in index.html index.js index.wasm index.pck index.manifest.json index.service.worker.js index.audio.worklet.js index.offline.html; do
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
BUNDLE_BAK="$(mktemp -d "${TMPDIR:-/tmp}/kiepie-bundle-backup.XXXXXX")" || exit 1
for f in "${WEB_FILES[@]}"; do
	[ -f "$ROOT/$f" ] && cp -p "$ROOT/$f" "$BUNDLE_BAK/$f"
done
for f in "${WEB_FILES[@]}"; do
	[ -f "$ROOT/web/$f" ] || continue
	cp "$ROOT/web/$f" "$ROOT/.$f.tmp" || { echo "DEPLOY ABORTED: staging $f failed"; exit 1; }
	mv -f "$ROOT/.$f.tmp" "$ROOT/$f" || { echo "DEPLOY ABORTED: replace $f failed"; exit 1; }
	STAGED_MD5=$(md5sum "$ROOT/web/$f" | awk '{print $1}')
	ROOT_MD5=$(md5sum "$ROOT/$f" | awk '{print $1}')
	[ "$STAGED_MD5" = "$ROOT_MD5" ] || { echo "DEPLOY ABORTED: $f hash mismatch after sync"; exit 1; }
done
SYNC_OK=1
echo "== web hygiene"
python3 "$HERE/check_web_hygiene.py" || { echo "DEPLOY ABORTED: web hygiene failed"; exit 1; }
BUNDLE_FILES=("${WEB_FILES[@]}")
if git diff --quiet -- "${BUNDLE_FILES[@]}" && git diff --cached --quiet -- "${BUNDLE_FILES[@]}"; then
	echo "   (nothing to commit — bundle identical)"
else
	# --only commits exactly these paths even if unrelated files are staged already.
	git commit --only -m "Kiepie Quad: web export refresh $(date -u +%Y-%m-%dT%H:%M:%SZ)" -- \
		"${BUNDLE_FILES[@]}" || { echo "DEPLOY ABORTED: commit failed"; exit 1; }
fi
git push origin main || { echo "DEPLOY ABORTED: push failed"; exit 1; }

echo "== verify Vercel auto-deploy (live alias)"
# The SW serves index.pck Cache-First, so html+sw alone cannot prove the game
# assets changed. Compare every runtime bundle file, with a cache-buster.
VERIFY_FILES=(
	index.html index.js index.wasm index.pck index.manifest.json
	index.service.worker.js index.audio.worklet.js index.offline.html
)
BUILD_SHA="$(git rev-parse --short HEAD)"
LOCAL_HASHES=""
for f in "${VERIFY_FILES[@]}"; do
	LOCAL_HASHES+="$f:$(md5sum "$ROOT/$f" | awk '{print $1}')"$'\n'
done
for i in $(seq 1 24); do
	sleep 5
	ALL_MATCH=1
	while IFS=: read -r f expected; do
		[ -z "$f" ] && continue
		live="$(curl --fail --max-time 10 -s "https://kiepie-quad-web.vercel.app/$f?v=$BUILD_SHA" | md5sum | awk '{print $1}')" || live=""
		[ "$live" = "$expected" ] || ALL_MATCH=0
	done <<< "$LOCAL_HASHES"
	if [ "$ALL_MATCH" -eq 1 ]; then
		echo "DEPLOY OK — live alias serves the pushed build (verified ${#VERIFY_FILES[@]} bundle files, sha=$BUILD_SHA)"
		exit 0
	fi
done
echo "DEPLOY WARNING: live alias did not match the pushed bundle after 120 s" >&2
exit 1
