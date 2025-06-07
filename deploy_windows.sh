#!/bin/bash

## This script is meant to be used with GitHub Actions on Windows
## It helps deploy the application and its dependencies in a portable package

echo ">> Deploying WatchFlower for Windows..."

# Check if the application binary exists
if [ ! -f "build/Release/WatchFlower.exe" ]; then
    echo "Error: WatchFlower.exe not found in build/Release/"
    exit 1
fi

# Create deployment directory
echo ">> Creating deployment directory..."
mkdir -p bin/
cp build/Release/WatchFlower.exe bin/

# Deploy Qt libraries and dependencies
echo ">> Deploying Qt libraries..."
windeployqt.exe bin/WatchFlower.exe --qmldir qml/ --force --compiler-runtime

# Copy additional files if they exist
echo ">> Copying additional files..."
if [ -f "README.md" ]; then
    cp README.md bin/
fi

if [ -f "LICENSE" ] || [ -f "LICENSE.md" ]; then
    cp LICENSE* bin/ 2>/dev/null || true
fi

if [ -f "CHANGELOG.md" ]; then
    cp CHANGELOG.md bin/
fi

# Copy assets if they exist
if [ -d "assets" ]; then
    cp -r assets bin/ 2>/dev/null || true
fi

# Verify deployment
echo ">> Verifying deployment..."
ls -la bin/

# Check if the essential files are present
if [ ! -f "bin/WatchFlower.exe" ]; then
    echo "Error: Deployment failed - WatchFlower.exe not found in bin/"
    exit 1
fi

# Check for essential Qt libraries
if [ ! -f "bin/Qt6Core.dll" ]; then
    echo "Warning: Qt6Core.dll not found - this may indicate deployment issues"
fi

echo ">> Windows deployment completed successfully!"
echo ">> Deployment contents:"
find bin/ -type f -name "*.exe" -o -name "*.dll" | head -10
echo ">> Total files deployed: $(find bin/ -type f | wc -l)"
