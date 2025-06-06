#!/usr/bin/env bash
set -euo pipefail

# 1) Ensure we have a Windows .rc stub
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/assets/windows"
mkdir -p "$ASSETS_DIR"
cat > "$ASSETS_DIR/WatchFlower.rc" <<'EOF'
1 ICON "assets/icons/logo.ico"
EOF

# 2) Clean & configure
BUILD_DIR="$SCRIPT_DIR/build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cmake -S "$SCRIPT_DIR" -B "$BUILD_DIR" \
  -G "NMake Makefiles" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$HOME/Qt/6.7.3/msvc2019_64"

# 3) Build
cmake --build "$BUILD_DIR" --config Release

# 4) Bundle with windeployqt
BIN_DIR="$BUILD_DIR/bin/Release"
DEPL_DIR="$SCRIPT_DIR/deploy"
rm -rf "$DEPL_DIR"
mkdir -p "$DEPL_DIR"
cp "$BIN_DIR/WatchFlower.exe" "$DEPL_DIR/"
windeployqt --dir "$DEPL_DIR" "$DEPL_DIR/WatchFlower.exe"

# 5) Package as ZIP
DIST_DIR="$SCRIPT_DIR/dist"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
pushd "$DEPL_DIR"
zip -r "$DIST_DIR/WatchFlower-win64.zip" ./*
popd

echo "Packaged: $DIST_DIR/WatchFlower-win64.zip"

# 6) If `--upload` was passed, place it where CI can pick it up
if [[ "${1:-}" == "--upload" ]]; then
  echo "::set-output name=artifact::$DIST_DIR/WatchFlower-win64.zip"
fi
