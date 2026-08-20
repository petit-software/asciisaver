#!/bin/bash
#
# Builds ASCIISaver.saver and, with --install, copies it into
# ~/Library/Screen Savers/.
#
# Usage:
#   ./build.sh              build only
#   ./build.sh --install    build, then install for the current user
#
set -euo pipefail

cd "$(dirname "$0")"

PRODUCT="ASCIISaver.saver"
BUILD_DIR="build"
INSTALL_DIR="$HOME/Library/Screen Savers"

# Regenerate the Xcode project from project.yml when xcodegen is available.
if command -v xcodegen >/dev/null 2>&1; then
	xcodegen generate >/dev/null
fi

xcodebuild \
	-project ASCIISaver.xcodeproj \
	-scheme ASCIISaver \
	-configuration Release \
	-derivedDataPath "$BUILD_DIR" \
	build | grep -E "error:|BUILD" || true

BUILT="$BUILD_DIR/Build/Products/Release/$PRODUCT"

if [ ! -d "$BUILT" ]; then
	echo "Build failed: $BUILT not found" >&2
	exit 1
fi

echo "Built $BUILT"

if [ "${1:-}" = "--install" ]; then
	mkdir -p "$INSTALL_DIR"
	# The saver host caches the loaded bundle; remove before copying so the
	# new build is picked up.
	rm -rf "${INSTALL_DIR:?}/$PRODUCT"
	cp -R "$BUILT" "$INSTALL_DIR/"
	echo "Installed to $INSTALL_DIR/$PRODUCT"
	echo
	echo "Open System Settings > Screen Saver and pick \"ASCIISaver\"."
	echo "If it was already selected, choose another saver and back again so"
	echo "the host reloads the bundle."
fi
