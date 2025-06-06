#!/bin/bash

# Windows deployment script for WatchFlower
# This script builds and packages the Windows version of WatchFlower

set -e  # Exit on any error

# Configuration
PROJECT_NAME="WatchFlower"
SOURCE_DIR=$(pwd)
BUILD_DIR="$SOURCE_DIR/build-windows"
DIST_DIR="$SOURCE_DIR/dist-windows"
DEPLOY_DIR="$SOURCE_DIR/deploy-windows"
BUILD_TYPE="Release"
QT_VERSION_MAJOR=6
APP_VERSION=${APP_VERSION:-"1.0.0"}

echo "=== Deployment Summary ==="
echo "Project Directory: $SOURCE_DIR"
echo "Build Directory: $BUILD_DIR"
echo "Distribution Directory: $DIST_DIR"
echo "Deployment Directory: $DEPLOY_DIR"
echo "Qt Version: ${Qt6_DIR##*/}"
echo "MSVC Version: 2022"
echo "Build Type: $BUILD_TYPE"
echo "App Version: $APP_VERSION"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to find Qt installation
find_qt_installation() {
    if [ -n "$Qt6_DIR" ] && [ -d "$Qt6_DIR" ]; then
        echo "$Qt6_DIR"
        return 0
    fi
    
    # Try to find Qt in common locations
    local qt_paths=(
        "D:/a/WatchFlower/Qt/6.7.3/msvc2019_64"
        "C:/Qt/6.7.3/msvc2019_64"
        "C:/Qt/6.7.2/msvc2019_64"
    )
    
    for path in "${qt_paths[@]}"; do
        if [ -d "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

echo "=== Setting up Qt Environment ==="
QT_INSTALL_PATH=$(find_qt_installation)
if [ $? -ne 0 ] || [ -z "$QT_INSTALL_PATH" ]; then
    echo "ERROR: Qt installation not found!"
    echo "Please ensure Qt is installed and Qt6_DIR is set correctly."
    exit 1
fi

export Qt6_DIR="$QT_INSTALL_PATH"
export PATH="$QT_INSTALL_PATH/bin:$PATH"

echo "Environment variables:"
echo "  Qt6_DIR: $Qt6_DIR"
echo "  QTDIR: ${QTDIR:-'not set'}"
echo "  QT_ROOT_DIR: ${QT_ROOT_DIR:-'not set'}"

# Verify Qt installation and required modules
echo "Qt tools found in PATH"
if command_exists qmake; then
    qmake -version
else
    echo "ERROR: qmake not found in PATH"
    exit 1
fi

echo "Qt installation detected at: $QT_INSTALL_PATH"

# Check for required Qt modules
REQUIRED_MODULES=(
    "Qt6Bluetooth"
    "Qt6Core"
    "Qt6Gui"
    "Qt6Widgets"
    "Qt6Quick"
    "Qt6Charts"
    "Qt6Positioning"
)

echo "Checking for required Qt modules..."
for module in "${REQUIRED_MODULES[@]}"; do
    module_path="$QT_INSTALL_PATH/lib/cmake/$module"
    if [ -d "$module_path" ]; then
        echo "  ✓ $module found"
    else
        echo "  ✗ $module NOT found at $module_path"
        if [ "$module" = "Qt6Bluetooth" ]; then
            echo "ERROR: Qt6Bluetooth module is required but not found!"
            echo "Please install Qt with the Connectivity module (qtconnectivity)."
            exit 1
        fi
    fi
done

echo "=== Setting up MSVC Environment ==="
# Find MSVC installation
MSVC_PATHS=(
    "C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Auxiliary/Build/vcvars64.bat"
    "C:/Program Files/Microsoft Visual Studio/2022/Professional/VC/Auxiliary/Build/vcvars64.bat"
    "C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Auxiliary/Build/vcvars64.bat"
    "C:/Program Files (x86)/Microsoft Visual Studio/2019/Enterprise/VC/Auxiliary/Build/vcvars64.bat"
    "C:/Program Files (x86)/Microsoft Visual Studio/2019/Professional/VC/Auxiliary/Build/vcvars64.bat"
    "C:/Program Files (x86)/Microsoft Visual Studio/2019/Community/VC/Auxiliary/Build/vcvars64.bat"
)

MSVC_BAT=""
for path in "${MSVC_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MSVC_BAT="$path"
        break
    fi
done

if [ -n "$MSVC_BAT" ]; then
    echo "Found MSVC at: $MSVC_BAT"
else
    echo "WARNING: Could not find MSVC installation, assuming environment is already set up"
fi

echo "=== Cleaning Previous Builds ==="
rm -rf "$BUILD_DIR" "$DIST_DIR" "$DEPLOY_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR" "$DEPLOY_DIR"
echo "Clean completed"

echo "=== Configuring CMake Build ==="
cd "$BUILD_DIR" || exit 1

# Use Visual Studio generator for better compatibility
echo "Using Visual Studio 2022 generator"

CMAKE_ARGS=(
    "-DCMAKE_BUILD_TYPE=$BUILD_TYPE"
    "-DCMAKE_INSTALL_PREFIX=$DIST_DIR"
    "-DQT_VERSION_MAJOR=$QT_VERSION_MAJOR"
    "-DCMAKE_PREFIX_PATH=$QT_INSTALL_PATH"
    "-G" "Visual Studio 17 2022"
    "-A" "x64"
)

echo "Running CMake with arguments: ${CMAKE_ARGS[*]}"
cmake "${CMAKE_ARGS[@]}" "$SOURCE_DIR"

if [ $? -ne 0 ]; then
    echo "ERROR: CMake configuration failed"
    exit 1
fi

echo "=== Building Application ==="
cmake --build . --config "$BUILD_TYPE" --parallel

if [ $? -ne 0 ]; then
    echo "ERROR: Build failed"
    exit 1
fi

echo "=== Installing Application ==="
cmake --install . --config "$BUILD_TYPE"

if [ $? -ne 0 ]; then
    echo "ERROR: Installation failed"
    exit 1
fi

echo "=== Deploying Qt Dependencies ==="
cd "$DIST_DIR" || exit 1

# Find the executable
EXECUTABLE_NAME="WatchFlower.exe"
if [ ! -f "$EXECUTABLE_NAME" ]; then
    # Try to find it in bin subdirectory
    if [ -f "bin/$EXECUTABLE_NAME" ]; then
        EXECUTABLE_NAME="bin/$EXECUTABLE_NAME"
    else
        echo "ERROR: Could not find WatchFlower.exe"
        ls -la .
        exit 1
    fi
fi

echo "Found executable: $EXECUTABLE_NAME"

# Run windeployqt
WINDEPLOYQT="$QT_INSTALL_PATH/bin/windeployqt.exe"
if [ ! -f "$WINDEPLOYQT" ]; then
    echo "ERROR: windeployqt.exe not found at $WINDEPLOYQT"
    exit 1
fi

echo "Running windeployqt..."
"$WINDEPLOYQT" --qmldir "$SOURCE_DIR/qml" --release --compiler-runtime "$EXECUTABLE_NAME"

if [ $? -ne 0 ]; then
    echo "ERROR: windeployqt failed"
    exit 1
fi

echo "=== Creating Final Package ==="
cp -r "$DIST_DIR"/* "$DEPLOY_DIR/"

# Add version info file
cat > "$DEPLOY_DIR/version.txt" << EOF
WatchFlower v$APP_VERSION
Build Date: $(date)
Qt Version: $(qmake -version | grep "Using Qt version" | cut -d' ' -f4)
Build Type: $BUILD_TYPE
EOF

echo "=== Deployment Complete ==="
echo "Deployment package created in: $DEPLOY_DIR"
echo "Executable: $DEPLOY_DIR/$(basename "$EXECUTABLE_NAME")"

# List the contents of deploy directory
echo ""
echo "Package contents:"
ls -la "$DEPLOY_DIR"
