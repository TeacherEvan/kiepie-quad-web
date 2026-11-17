#!/usr/bin/env bash
# Kiepie Bike — one-command headless gate suite.
# Rebuilds both scenes, runs every gate in tools/, prints a per-gate verdict
# plus key evidence lines, and exits non-zero if any gate fails.
#
# Usage:  godot/tools/run_gates.sh              (full suite incl. scene rebuild)
#         godot/tools/run_gates.sh --no-build   (reuse existing scenes)
#         GODOT=/path/to/godot-4.3 godot/tools/run_gates.sh
#
# Deliberately NOT included: Web export / deploy. Exports and Vercel deploys
# stay in the documented manual flow (AGENTS.md).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"
GODOT="${GODOT:-godot-4.3}"
# Gates must stay offline: never touch the live Talo account from CI.
export KIEPIE_MOCK_BACKEND=1
BUILD=1
[ "${1:-}" = "--no-build" ] && BUILD=0

LOGDIR="$(mktemp -d /tmp/opencode/gates.XXXXXX)"
PASS=0; FAILED=()

note() { printf '%s\n' "$*"; }

verdict() {
	local name="$1" log="$2" rc="$3"
	# failure = non-zero exit, explicit FAIL/FAILED marker line, or script error
	if [ "$rc" -ne 0 ] || grep -qE '(^|[[:space:]])(FAIL|FAILED)([[:space:]]|:|$)' "$log" || grep -q "SCRIPT ERROR" "$log"; then
		note "   FAIL  (rc=$rc; log: $log)"
		FAILED+=("$name")
		return
	fi
	note "   ok"
	pass_lines="$(grep -E 'MIN_UP_Y|t=300|TOUCH VERIFY|TOUCH MULTITOUCH|PRACTICE:|STABILITY:|SMASH_IMPACT|UP_Y_AFTER_SMASH|TURBO:|DEBRIS|hud ready|smashed' "$log" | tail -6 || true)"
	[ -n "$pass_lines" ] && printf '%s\n' "$pass_lines" | sed 's/^/     /'
	PASS=$((PASS + 1))
}

run_gate() {
	local name="$1" tool="$2"
	local log="$LOGDIR/$name.log"
	note "== $name"
	# wall-clock budget: a wedged await must not hang the suite forever
	timeout --foreground 150 "$GODOT" --headless --path godot --script "tools/$tool" </dev/null >"$log" 2>&1
	verdict "$name" "$log" $?
}

# GUI hit-testing needs a real window: headless' dummy driver pins the viewport
# to 64x64, so synthesized touches land outside every button. Used only for the
# multi-touch gate (same mechanism as tools/vfx_showcase.gd).
run_gate_windowed() {
	local name="$1" tool="$2"
	local log="$LOGDIR/$name.log"
	note "== $name (xvfb)"
	if ! command -v xvfb-run >/dev/null 2>&1; then
		note "   FAIL  xvfb-run not present — multi-touch gate cannot run (install xvfb)"
		FAILED+=("$name")
		return
	fi
	timeout --foreground 240 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --resolution 1280x720 \
		--path godot --script "tools/$tool" </dev/null >"$log" 2>&1
	verdict "$name" "$log" $?
}

note "Kiepie Bike gate suite — root: $ROOT"
if [ "$BUILD" -eq 1 ]; then
	note "== build (KiepieBike.tscn + TestRide.tscn)"
	"$GODOT" --headless --path godot --script tools/build_bike.gd >"$LOGDIR/build_bike.log" 2>&1
	_bike_rc=$?
	if [ "$_bike_rc" -ne 0 ]; then
		note "   WARN build_bike rc=$_bike_rc (log: $LOGDIR/build_bike.log)"
		FAILED+=("build_bike")
	fi
	if ! grep -q "saved" "$LOGDIR/build_bike.log"; then
		note "   FAIL bike rebuild did not save (log: $LOGDIR/build_bike.log)"
		FAILED+=("build_bike")
	fi
	"$GODOT" --headless --path godot --script tools/build_testride.gd >"$LOGDIR/build_testride.log" 2>&1
	_testride_rc=$?
	if [ "$_testride_rc" -ne 0 ]; then
		note "   WARN build_testride rc=$_testride_rc (log: $LOGDIR/build_testride.log)"
		FAILED+=("build")
	fi
	if grep -q "saved" "$LOGDIR/build_testride.log"; then
		note "   scenes saved"
	else
		note "   FAIL scene rebuild did not save (log: $LOGDIR/build_testride.log)"
		FAILED+=("build")
	fi
	if [ -f godot/tools/build_menus.gd ]; then
		"$GODOT" --headless --path godot --script tools/build_menus.gd >"$LOGDIR/build_menus.log" 2>&1
		_menus_rc=$?
		if [ "$_menus_rc" -ne 0 ]; then
			note "   WARN build_menus rc=$_menus_rc (log: $LOGDIR/build_menus.log)"
			FAILED+=("build_menus")
		fi
		if grep -q "saved" "$LOGDIR/build_menus.log"; then
			note "   menus saved"
		else
			note "   FAIL menu rebuild did not save"
			FAILED+=("build_menus")
		fi
	fi
	if [ -f godot/tools/build_arena.gd ]; then
		"$GODOT" --headless --path godot --script tools/build_arena.gd >"$LOGDIR/build_arena.log" 2>&1
		_arena_rc=$?
		if [ "$_arena_rc" -ne 0 ]; then
			note "   WARN build_arena rc=$_arena_rc (log: $LOGDIR/build_arena.log)"
			FAILED+=("build_arena")
		fi
		if grep -q "saved" "$LOGDIR/build_arena.log"; then
			note "   arena saved"
		else
			note "   FAIL arena rebuild did not save"
			FAILED+=("build_arena")
		fi
	fi
fi

run_gate_gdunit() {
	local log="$LOGDIR/gdunit.log"
	note "== gdunit"
	timeout --foreground 240 "$GODOT" --headless --path godot -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
		--ignoreHeadlessMode -a res://tests </dev/null >"$log" 2>&1
	local rc=$?
	# gdUnit4 exit codes: 0 = all pass, 100 = failure, 101 = pass with orphan
	# warnings (dummy-renderer RIDs in headless; benign here), 103/104 = env errors
	if [ "$rc" -eq 0 ] || [ "$rc" -eq 101 ]; then
		note "   ok  (exit $rc$([ $rc -eq 101 ] && printf ' — pass with orphan warnings (headless RIDs)'))"
		grep -E "PASSED|Statistics" "$log" | tail -2 | sed 's/^/     /'
		PASS=$((PASS + 1))
	else
		note "   FAIL  (rc=$rc; log: $log)"
		FAILED+=("gdunit")
	fi
}

run_gate truth          truth_test.gd
run_gate stability      verify_stability.gd
run_gate touch          verify_touch.gd
run_gate features       verify_features.gd
run_gate smash_impact   verify_smash_impact.gd
run_gate diag2          diag2.gd
run_gate cannons        verify_cannons.gd
run_gate settings       verify_settings.gd
run_gate match_rules    verify_match_rules.gd
run_gate combat         verify_combat.gd
run_gate kill_flow      verify_kill_flow.gd
run_gate appeal         verify_appeal.gd
run_gate accessibility  verify_accessibility.gd
run_gate talo_backend   verify_talo_backend.gd
run_gate audit_regressions verify_audit_regressions.gd
run_gate controls        verify_controls.gd
run_gate dodge           verify_dodge.gd
run_gate vfx             verify_vfx.gd
run_gate practice        verify_practice.gd
run_gate_windowed touch_multitouch verify_touch_multitouch.gd
run_gate_gdunit

note ""
if [ "${#FAILED[@]}" -gt 0 ]; then
	note "GATE SUITE: FAIL — ${#FAILED[@]} failing: ${FAILED[*]}"
	note "logs in $LOGDIR"
	exit 1
fi
note "GATE SUITE: PASS — all $PASS gates green"
exit 0
