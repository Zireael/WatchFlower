#!/usr/bin/env bash
set -euo pipefail

# Where we’ll do our out-of-source build…
BUILD_DIR=build

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Configure with Ninja generator
cmake -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  ..

# Build & run tests (optional)
cmake --build . --config Release
ctest --output-on-failure -C Release

# Deploy your binaries, then bundle with windeployqt
# (whatever you had after this point)
