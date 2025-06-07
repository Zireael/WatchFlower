#!/bin/bash

# WatchFlower Windows Deployment Script
# Fixed version to resolve CI build issues

echo "Starting Windows deployment for WatchFlower..."

# Set error handling
set -e

# Define variables
APP_NAME="WatchFlower"
BUILD_DIR="build"
DEPLOY_DIR="deploy"

# Clean previous builds
echo "Cleaning previous builds..."
rm -rf ${BUILD_DIR}
rm -rf ${DEPLOY_DIR}

# Create build directory
mkdir -p ${BUILD_DIR}
mkdir -p ${DEPLOY_DIR}

# Set Qt environment variables
echo "Setting up Qt environment..."
if [ -z "$Qt6_DIR" ]; then
    # Try to find Qt installation
    if [ -d "C:/Qt/6.6.0/msvc2019_64" ]; then
        export Qt6_DIR="C:/Qt/6.6.0/msvc2019_64"
    elif [ -d "C:/Qt/6.5.0/msvc2019_64" ]; then
        export Qt6_DIR="C:/Qt/6.5.0/msvc2019_64"
    elif [ -d "C:/Qt/6.4.0/msvc2019_64" ]; then
        export Qt6_DIR="C:/Qt/6.4.0/msvc2019_64"
    else
        echo "Warning: Qt6_DIR not set and no Qt installation found in standard locations"
    fi
fi

if [ -n "$Qt6_DIR" ]; then
    echo "Using Qt6_DIR: $Qt6_DIR"
    export PATH="$Qt6_DIR/bin:$PATH"
    export CMAKE_PREFIX_PATH="$Qt6_DIR:$CMAKE_PREFIX_PATH"
fi

# Configure CMake
echo "Configuring CMake..."
cd ${BUILD_DIR}

cmake .. \
    -G "Visual Studio 17 2022" \
    -A x64 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$Qt6_DIR" \
    -DQT_VERSION=6

# Build the application
echo "Building application..."
cmake --build . --config Release --parallel

# Find the executable
EXE_PATH=$(find . -name "*.exe" -path "*/Release/*" | head -1)
if [ -z "$EXE_PATH" ]; then
    echo "Error: Could not find built executable"
    exit 1
fi

echo "Found executable: $EXE_PATH"

# Create deployment directory and copy executable
echo "Preparing deployment..."
cd ..
mkdir -p ${DEPLOY_DIR}
cp "$BUILD_DIR/$EXE_PATH" ${DEPLOY_DIR}/

# Get the executable name without path
EXE_NAME=$(basename "$EXE_PATH")

# Deploy Qt dependencies
echo "Deploying Qt dependencies..."
cd ${DEPLOY_DIR}

# Try to find windeployqt
WINDEPLOYQT=""
if [ -n "$Qt6_DIR" ] && [ -f "$Qt6_DIR/bin/windeployqt.exe" ]; then
    WINDEPLOYQT="$Qt6_DIR/bin/windeployqt.exe"
elif command -v windeployqt.exe >/dev/null 2>&1; then
    WINDEPLOYQT="windeployqt.exe"
else
    echo "Error: windeployqt.exe not found"
    exit 1
fi

echo "Using windeployqt: $WINDEPLOYQT"

# Run windeployqt with appropriate flags
"$WINDEPLOYQT" \
    --release \
    --no-translations \
    --no-system-d3d-compiler \
    --no-opengl-sw \
    --qmldir ../qml \
    "$EXE_NAME"

# Check if deployment was successful
if [ $? -eq 0 ]; then
    echo "Qt deployment successful"
else
    echo "Qt deployment failed, trying alternative approach..."
    
    # Alternative: manually copy essential Qt DLLs
    if [ -n "$Qt6_DIR" ]; then
        echo "Copying Qt DLLs manually..."
        
        # Core Qt DLLs
        cp "$Qt6_DIR/bin/Qt6Core.dll" . 2>/dev/null || true
        cp "$Qt6_DIR/bin/Qt6Gui.dll" . 2>/dev/null || true
        cp "$Qt6_DIR/bin/Qt6Widgets.dll" . 2>/dev/null || true
        cp "$Qt6_DIR/bin/Qt6Quick.dll" . 2>/dev/null || true
        cp "$Qt6_DIR/bin/Qt6Qml.dll" . 2>/dev/null || true
        cp "$Qt6_DIR/bin/Qt6QuickControls2.dll" . 2>/dev/null || true
        cp "$Qt6_DIR/bin/Qt6QuickTemplates2.dll" . 2>/dev/null || true
        cp "$Qt6_DIR/bin/Qt6Network.dll" . 2>/dev/null || true
        cp "$Qt6_DIR/bin/Qt6Bluetooth.dll" . 2>/dev/null || true
        cp "$Qt6_DIR/bin/Qt6Svg.dll" . 2>/dev/null || true
        
        # Platform plugins
        mkdir -p platforms
        cp "$Qt6_DIR/plugins/platforms/qwindows.dll" platforms/ 2>/dev/null || true
        
        # Image format plugins
        mkdir -p imageformats
        cp "$Qt6_DIR/plugins/imageformats"/*.dll imageformats/ 2>/dev/null || true
        
        # QML modules
        if [ -d "$Qt6_DIR/qml" ]; then
            mkdir -p qml
            cp -r "$Qt6_DIR/qml/QtQuick" qml/ 2>/dev/null || true
            cp -r "$Qt6_DIR/qml/QtQuick.2" qml/ 2>/dev/null || true
            cp -r "$Qt6_DIR/qml/QtQml" qml/ 2>/dev/null || true
        fi
    fi
fi

# Copy additional resources if they exist
if [ -d "../assets" ]; then
    echo "Copying assets..."
    cp -r ../assets .
fi

if [ -d "../i18n" ]; then
    echo "Copying translations..."
    cp -r ../i18n .
fi

# Create a simple batch file to run the application
cat > run.bat << 'EOF'
@echo off
echo Starting WatchFlower...
%~dp0WatchFlower.exe
pause
EOF

# List deployed files
echo "Deployment complete. Files in deploy directory:"
ls -la

echo "Windows deployment finished successfully!"
echo "Deployment location: $(pwd)"
