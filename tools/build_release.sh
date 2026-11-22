#!/usr/bin/env bash
# T020: builds the desktop release packages.
#   tools/build_release.sh            -> build/EverydayCity-<version>-linux-x86_64.zip
#                                        build/EverydayCity-<version>-windows-x86_64.zip
# Needs the official Godot export templates for the pinned engine (4.7.2.stable), installed via
# the editor (Editor → Manage Export Templates) or by unpacking
# Godot_v4.7.2-stable_export_templates.tpz into the templates folder printed below.
# Runs tools/check.sh first and smoke-tests the Linux binary after exporting.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
ENGINE="4.7.2.stable"
VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
case "$(uname -s)" in
	Linux*)  TEMPLATES="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$ENGINE" ;;
	Darwin*) TEMPLATES="$HOME/Library/Application Support/Godot/export_templates/$ENGINE" ;;
	*)       TEMPLATES="${APPDATA:-}/Godot/export_templates/$ENGINE" ;;
esac
for f in linux_release.x86_64 windows_release_x86_64.exe; do
	if [ ! -f "$TEMPLATES/$f" ]; then
		echo "Missing export template: $TEMPLATES/$f"
		echo "Install the Godot $ENGINE export templates first (see the header of this script)."
		exit 2
	fi
done

if [ "${SKIP_CHECKS:-0}" != "1" ]; then
	./tools/check.sh >/dev/null || { echo "tools/check.sh failed; not building a release."; exit 1; }
fi

rm -rf build/linux build/windows
mkdir -p build/linux build/windows
"$GODOT" --headless --path . --export-release "Linux" build/linux/EverydayCity.x86_64
"$GODOT" --headless --path . --export-release "Windows" build/windows/EverydayCity.exe
chmod +x build/linux/EverydayCity.x86_64

# Smoke-test the real Linux binary from an empty folder (no editor, no project files).
SMOKE_DIR="$(mktemp -d)"
( cd "$SMOKE_DIR" && "$OLDPWD/build/linux/EverydayCity.x86_64" --headless -- --smoke-test ) | tee build/linux_smoke.log
grep -q "SMOKE OK" build/linux_smoke.log || { echo "Linux binary smoke test failed"; exit 1; }
rm -rf "$SMOKE_DIR"

for os in linux windows; do
	cp docs/RELEASE_README.txt "build/$os/README.txt"
	(cd build/$os && zip -qr "../EverydayCity-$VERSION-$os-x86_64.zip" .)
done
ls -la build/*.zip
echo "Release $VERSION built. The Windows build was not run here; run 'EverydayCity.exe -- --smoke-test' on Windows to check it."
