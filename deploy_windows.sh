#!/bin/bash

# WatchFlower Windows deployment script
# Fixed version addressing common MSYS2/windeployqt issues

set -e

echo "Starting Windows deployment..."

# Ensure we're in the correct directory
cd "$(dirname "$0")"

# Set up MSYS2 environment variables
export MSYSTEM=MINGW64
export PATH="/mingw64/bin:$PATH"

# Check if windeployqt is available
if ! command -v windeployqt &> /dev/null; then
    echo "Error: windeployqt not found. Installing qt5-tools..."
    pacman -Sy --noconfirm mingw-w64-x86_64-qt5-tools
fi

# Verify the executable exists
if [ ! -f "WatchFlower.exe" ]; then
    echo "Error: WatchFlower.exe not found. Please build the application first."
    exit 1
fi

# Create deployment directory
DEPLOY_DIR="WatchFlower_deploy"
rm -rf "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"

# Copy the executable
cp WatchFlower.exe "$DEPLOY_DIR/"

# Deploy Qt dependencies with explicit paths and options
echo "Deploying Qt dependencies..."
windeployqt \
    --dir "$DEPLOY_DIR" \
    --qmldir src/qml \
    --verbose 2 \
    --compiler-runtime \
    --no-translations \
    --no-system-d3d-compiler \
    --no-opengl-sw \
    "$DEPLOY_DIR/WatchFlower.exe"

# Copy additional MSYS2 runtime dependencies that windeployqt might miss
echo "Copying additional runtime dependencies..."
cp /mingw64/bin/libgcc_s_seh-1.dll "$DEPLOY_DIR/" 2>/dev/null || true
cp /mingw64/bin/libwinpthread-1.dll "$DEPLOY_DIR/" 2>/dev/null || true
cp /mingw64/bin/libstdc++-6.dll "$DEPLOY_DIR/" 2>/dev/null || true

# Copy any additional application resources
if [ -d "assets" ]; then
    cp -r assets "$DEPLOY_DIR/"
fi

echo "Windows deployment completed successfully!"
echo "Deployment directory: $DEPLOY_DIR"
