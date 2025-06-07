#!/bin/bash

echo "> WatchFlower Windows deployment script"

## VARIABLES ##################################################################

APP_NAME="WatchFlower"
APP_VERSION=$(git describe --tags --always --dirty)
GIT_VERSION=$(git rev-parse --short HEAD)

PROJECT_DIR=$(pwd)
BUILD_DIR="$PROJECT_DIR/build"
BIN_DIR="$PROJECT_DIR/bin"
DEPLOY_DIR="$BIN_DIR/$APP_NAME"

## FUNCTIONS ##################################################################

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --config      : Select build configuration (Release|Debug)"
    echo "  -h, --help        : Show this help message"
}

## ARGUMENT PARSING ###########################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            BUILD_CONFIG="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Set default build configuration
if [ -z "$BUILD_CONFIG" ]; then
    BUILD_CONFIG="Release"
fi

## SETUP ######################################################################

echo "> App name: $APP_NAME"
echo "> App version: $APP_VERSION"
echo "> Git version: $GIT_VERSION"
echo "> Build configuration: $BUILD_CONFIG"
echo "> Project directory: $PROJECT_DIR"
echo "> Build directory: $BUILD_DIR"
echo "> Deployment directory: $DEPLOY_DIR"

## DEPLOYMENT #################################################################

# Remove previous deployment
if [ -d "$DEPLOY_DIR" ]; then
    echo "> Removing previous deployment..."
    rm -rf "$DEPLOY_DIR"
fi

# Create deployment directory
echo "> Creating deployment directory..."
mkdir -p "$DEPLOY_DIR"

# Copy executable
echo "> Copying executable..."
if [ -f "$BUILD_DIR/$BUILD_CONFIG/$APP_NAME.exe" ]; then
    cp "$BUILD_DIR/$BUILD_CONFIG/$APP_NAME.exe" "$DEPLOY_DIR/"
elif [ -f "$BUILD_DIR/$APP_NAME.exe" ]; then
    cp "$BUILD_DIR/$APP_NAME.exe" "$DEPLOY_DIR/"
else
    echo "Error: Cannot find $APP_NAME.exe"
    exit 1
fi

# Find Qt installation path
QT_DIR=""
if [ -n "$Qt6_DIR" ]; then
    QT_DIR="$Qt6_DIR"
elif [ -n "$QT_ROOT_PATH" ]; then
    QT_DIR="$QT_ROOT_PATH"
elif [ -n "$QTDIR" ]; then
    QT_DIR="$QTDIR"
else
    # Try to find Qt in common locations
    for qt_path in "/c/Qt/6.7.3/msvc2022_64" "/d/a/_temp/Qt/6.7.3/msvc2022_64" "$RUNNER_WORKSPACE/Qt/6.7.3/msvc2022_64"; do
        if [ -d "$qt_path" ]; then
            QT_DIR="$qt_path"
            break
        fi
    done
fi

if [ -z "$QT_DIR" ] || [ ! -d "$QT_DIR" ]; then
    echo "Error: Cannot find Qt installation directory"
    echo "Please set Qt6_DIR, QT_ROOT_PATH, or QTDIR environment variable"
    exit 1
fi

echo "> Qt directory: $QT_DIR"

# Convert Windows path to Unix path for windeployqt
QT_BIN_DIR="$QT_DIR/bin"
WINDEPLOYQT="$QT_BIN_DIR/windeployqt.exe"

# Check if windeployqt exists
if [ ! -f "$WINDEPLOYQT" ]; then
    echo "Error: windeployqt.exe not found at $WINDEPLOYQT"
    exit 1
fi

# Run windeployqt
echo "> Running windeployqt..."
cd "$DEPLOY_DIR"

# Convert deployment directory to Windows path for windeployqt
DEPLOY_DIR_WIN=$(cygpath -w "$DEPLOY_DIR" 2>/dev/null || echo "$DEPLOY_DIR")

"$WINDEPLOYQT" \
    --dir "$DEPLOY_DIR_WIN" \
    --release \
    --compiler-runtime \
    --no-translations \
    --no-system-d3d-compiler \
    --no-opengl-sw \
    --qmldir "$PROJECT_DIR/qml" \
    "$APP_NAME.exe"

if [ $? -ne 0 ]; then
    echo "Error: windeployqt failed"
    exit 1
fi

# Copy additional Qt modules if needed
echo "> Copying additional Qt modules..."
QT_PLUGINS_DIR="$QT_DIR/plugins"
DEPLOY_PLUGINS_DIR="$DEPLOY_DIR/plugins"

# Ensure plugins directory exists
mkdir -p "$DEPLOY_PLUGINS_DIR"

# Copy required plugins
if [ -d "$QT_PLUGINS_DIR/bearer" ]; then
    cp -r "$QT_PLUGINS_DIR/bearer" "$DEPLOY_PLUGINS_DIR/"
fi

if [ -d "$QT_PLUGINS_DIR/position" ]; then
    cp -r "$QT_PLUGINS_DIR/position" "$DEPLOY_PLUGINS_DIR/"
fi

# Copy additional DLLs if needed
QT_BIN_DIR_UNIX=$(cygpath -u "$QT_BIN_DIR" 2>/dev/null || echo "$QT_BIN_DIR")
for dll in Qt6Bluetooth.dll Qt6Charts.dll Qt6Positioning.dll; do
    if [ -f "$QT_BIN_DIR_UNIX/$dll" ]; then
        cp "$QT_BIN_DIR_UNIX/$dll" "$DEPLOY_DIR/"
    fi
done

# Create version info file
echo "> Creating version info..."
cat > "$DEPLOY_DIR/version.txt" << EOF
$APP_NAME $APP_VERSION
Git: $GIT_VERSION
Build: $BUILD_CONFIG
Date: $(date)
EOF

# Create deployment info
echo "> Deployment completed successfully!"
echo "> Deployed files:"
find "$DEPLOY_DIR" -type f | head -20
echo "> Total files: $(find "$DEPLOY_DIR" -type f | wc -l)"
echo "> Deployment size: $(du -sh "$DEPLOY_DIR" | cut -f1)"

cd "$PROJECT_DIR"
