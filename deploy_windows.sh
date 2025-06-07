#!/bin/bash

# Windows deployment script for WatchFlower
# This script should be run from the project root directory

echo "> Windows deployment script"

# Create deployment directory
if [ -d "bin/" ]; then
  rm -rf bin/
fi
mkdir bin/

# Create temporary deployment directory
DEPLOY_DIR="bin/WatchFlower-win64"
mkdir -p "$DEPLOY_DIR"

# Copy the built executable
if [ -f "release/WatchFlower.exe" ]; then
  cp "release/WatchFlower.exe" "$DEPLOY_DIR/"
  echo "✓ Copied WatchFlower.exe"
else
  echo "✗ WatchFlower.exe not found in release/"
  exit 1
fi

# Deploy Qt dependencies
echo "> Deploying Qt dependencies..."
cd "$DEPLOY_DIR"

# Run windeployqt to gather Qt dependencies
windeployqt.exe --qmldir ../../qml --compiler-runtime --force --verbose 2 WatchFlower.exe

if [ $? -ne 0 ]; then
  echo "✗ windeployqt failed"
  exit 1
fi

echo "✓ Qt dependencies deployed"

# Go back to project root
cd ../..

# Create zip archive
echo "> Creating deployment archive..."
cd bin/
7z a "WatchFlower-win64.zip" "WatchFlower-win64/"

if [ $? -eq 0 ]; then
  echo "✓ WatchFlower-win64.zip created successfully"
else
  echo "✗ Failed to create zip archive"
  exit 1
fi

# List contents for verification
echo "> Deployment contents:"
ls -la WatchFlower-win64/

echo "> Windows deployment completed successfully"
