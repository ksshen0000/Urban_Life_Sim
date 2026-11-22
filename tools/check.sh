#!/usr/bin/env bash
# One-shot verification used by agents and CI:
#   1. import project (builds .godot class cache), 2. run headless tests,
#   3. boot the main scene for a few frames and fail on any engine/script error,
#   4. export the game data pack and run the release smoke test from it, outside the project
#      (no export templates needed; tools/build_release.sh builds the real binaries).
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
LOG_DIR="${TMPDIR:-/tmp}/everyday_city_check"
mkdir -p "$LOG_DIR"
status=0

scan_errors() { # $1 = log file, $2 = step name
	if grep -E "^(ERROR|SCRIPT ERROR|USER ERROR|Parse Error)" "$1" >/dev/null; then
		echo "[$2] engine errors detected:"; grep -E -A2 "^(ERROR|SCRIPT ERROR|USER ERROR|Parse Error)" "$1"; return 1
	fi
	# Leaked objects usually mean RefCounted cycles (e.g. a lambda capturing its owner).
	if grep -E "instances were leaked|still in use at exit" "$1" >/dev/null; then
		echo "[$2] leaks detected:"; grep -E "instances were leaked|still in use at exit" "$1"; return 1
	fi
	return 0
}

echo "== import"
"$GODOT" --headless --path . --import >"$LOG_DIR/import.log" 2>&1 || { echo "import failed"; cat "$LOG_DIR/import.log"; status=1; }
scan_errors "$LOG_DIR/import.log" import || status=1

echo "== tests"
"$GODOT" --headless --path . -s res://tests/run_tests.gd -- "$@" 2>&1 | tee "$LOG_DIR/tests.log"
[ "${PIPESTATUS[0]}" -eq 0 ] || status=1
scan_errors "$LOG_DIR/tests.log" tests || status=1

echo "== boot main scene (headless, 30 frames)"
"$GODOT" --headless --path . --quit-after 30 >"$LOG_DIR/boot.log" 2>&1 || { echo "boot exited non-zero"; status=1; }
scan_errors "$LOG_DIR/boot.log" boot || status=1

echo "== city world scene (headless, 60 frames; starts a new game via GameSession)"
"$GODOT" --headless --path . res://scenes/world/city_world.tscn --quit-after 60 >"$LOG_DIR/world.log" 2>&1 || { echo "world exited non-zero"; status=1; }
scan_errors "$LOG_DIR/world.log" world || status=1

echo "== release pack smoke test (exported .pck, run outside the project folder)"
PACK_DIR="$LOG_DIR/pack"
rm -rf "$PACK_DIR"; mkdir -p "$PACK_DIR/run"
if "$GODOT" --headless --path . --export-pack "Linux" "$PACK_DIR/EverydayCity.pck" >"$LOG_DIR/export.log" 2>&1; then
	( cd "$PACK_DIR/run" && "$GODOT" --headless --main-pack "$PACK_DIR/EverydayCity.pck" -- --smoke-test ) >"$LOG_DIR/smoke.log" 2>&1 \
		|| { echo "smoke test failed:"; cat "$LOG_DIR/smoke.log"; status=1; }
	scan_errors "$LOG_DIR/smoke.log" smoke || status=1
	grep "SMOKE OK" "$LOG_DIR/smoke.log" || status=1
else
	echo "pack export failed:"; tail -20 "$LOG_DIR/export.log"; status=1
fi

[ $status -eq 0 ] && echo "ALL CHECKS PASSED" || echo "CHECKS FAILED (logs in $LOG_DIR)"
exit $status
