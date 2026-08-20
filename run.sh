#!/bin/bash
#
# Builds the saver and runs it in a preview host, so you can see it without
# changing your System Settings screen saver selection.
#
# Usage:
#   ./run.sh              full screen
#   ./run.sh --window     in a 1280x800 window
#
# Quit with Esc, any key, or a click. Auto-quits after 5 minutes.
#
set -euo pipefail

cd "$(dirname "$0")"

./build.sh >/dev/null

SAVER="build/Build/Products/Release/ASCIISaver.saver"
HOST="build/RunSaver"

mkdir -p build
swiftc -O Tools/RunSaver/main.swift -o "$HOST"

exec "$HOST" "$SAVER" "$@"
