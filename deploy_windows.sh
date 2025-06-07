#!/bin/bash

## Deploy script for Windows
## This script builds and packages WatchFlower for Windows distribution

set -e  # Exit on any error

echo "========================================="
echo "WatchFlower Windows deployment script"
echo "========================================="

# Configuration
APP_NAME="WatchFlower"
APP_VERSION=$(git describe --tags --always)
BUILD_DIR="build"
DEPLOY_DIR="deploy"
INSTALLER_DIR="installer"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're on Windows
if [[ "$OSTYPE" != "msys" && "$OSTYPE" != "cygwin" ]]; then
    print_error "This script is designed to run on Windows with Git Bash or similar environment"
    exit 1
fi

# Check for required tools
print_info "Checking for required tools..."

if ! command -v qmake &> /dev/null; then
    print_error "qmake not found. Please ensure Qt is properly installed and in PATH."
    exit 1
fi

if ! command -v nmake &> /dev/null; then
    print_error "nmake not found. Please ensure Visual Studio Build Tools are installed."
    exit 1
fi

if ! command -v windeployqt &> /dev/null; then
    print_error "windeployqt not found. Please ensure Qt tools are in PATH."
    exit 1
fi

print_success "All required tools found"

# Clean previous builds
print_info "Cleaning previous builds..."
rm -rf "$BUILD_DIR" "$DEPLOY_DIR" "$INSTALLER_DIR"
mkdir -p "$BUILD_DIR" "$DEPLOY_DIR" "$INSTALLER_DIR"

# Get Qt version and info
QT_VERSION=$(qmake -query QT_VERSION)
QT_HOST_BINS=$(qmake -query QT_HOST_BINS)
QT_INSTALL_PREFIX=$(qmake -query QT_INSTALL_PREFIX)

print_info "Using Qt version: $QT_VERSION"
print_info "Qt installation: $QT_INSTALL_PREFIX"

# Build the application
print_info "Building $APP_NAME..."
cd "$BUILD_DIR"

# Generate Makefile
print_info "Running qmake..."
qmake ../WatchFlower.pro \
    CONFIG+=release \
    CONFIG+=force_debug_info \
    CONFIG+=separate_debug_info \
    DEFINES+=QT_DEPRECATED_WARNINGS

if [ $? -ne 0 ]; then
    print_error "qmake failed"
    exit 1
fi

# Build
print_info "Compiling application..."
nmake

if [ $? -ne 0 ]; then
    print_error "Build failed"
    exit 1
fi

print_success "Build completed successfully"

# Go back to root directory
cd ..

# Deploy the application
print_info "Deploying application..."

# Copy the executable
if [ -f "$BUILD_DIR/release/$APP_NAME.exe" ]; then
    cp "$BUILD_DIR/release/$APP_NAME.exe" "$DEPLOY_DIR/"
    print_success "Copied main executable"
else
    print_error "Could not find $APP_NAME.exe in $BUILD_DIR/release/"
    exit 1
fi

# Copy debug symbols if they exist
if [ -f "$BUILD_DIR/release/$APP_NAME.pdb" ]; then
    cp "$BUILD_DIR/release/$APP_NAME.pdb" "$DEPLOY_DIR/"
    print_info "Copied debug symbols"
fi

# Run windeployqt
print_info "Running windeployqt..."
windeployqt \
    --release \
    --qmldir qml \
    --compiler-runtime \
    --verbose 2 \
    "$DEPLOY_DIR/$APP_NAME.exe"

if [ $? -ne 0 ]; then
    print_error "windeployqt failed"
    exit 1
fi

print_success "Qt deployment completed"

# Copy additional resources if they exist
if [ -d "assets" ]; then
    print_info "Copying assets..."
    cp -r assets "$DEPLOY_DIR/"
fi

if [ -f "README.md" ]; then
    cp README.md "$DEPLOY_DIR/"
fi

if [ -f "LICENSE" ]; then
    cp LICENSE "$DEPLOY_DIR/"
fi

# Verify deployment
print_info "Verifying deployment..."
if [ ! -f "$DEPLOY_DIR/$APP_NAME.exe" ]; then
    print_error "Deployment verification failed: $APP_NAME.exe not found"
    exit 1
fi

# Check for Qt DLLs
QT_DLLS=("Qt6Core.dll" "Qt6Gui.dll" "Qt6Widgets.dll" "Qt6Network.dll" "Qt6Bluetooth.dll")
for dll in "${QT_DLLS[@]}"; do
    if [ ! -f "$DEPLOY_DIR/$dll" ]; then
        print_warning "$dll not found in deployment directory"
    fi
done

# Get deployment size
DEPLOY_SIZE=$(du -sh "$DEPLOY_DIR" | cut -f1)
print_info "Deployment size: $DEPLOY_SIZE"

# Create installer package (optional)
if command -v 7z &> /dev/null; then
    print_info "Creating ZIP package..."
    PACKAGE_NAME="${APP_NAME}-${APP_VERSION}-Windows-x64.zip"
    cd "$DEPLOY_DIR"
    7z a "../$INSTALLER_DIR/$PACKAGE_NAME" ./*
    cd ..
    
    if [ -f "$INSTALLER_DIR/$PACKAGE_NAME" ]; then
        PACKAGE_SIZE=$(du -sh "$INSTALLER_DIR/$PACKAGE_NAME" | cut -f1)
        print_success "Package created: $PACKAGE_NAME ($PACKAGE_SIZE)"
    fi
else
    print_warning "7z not found, skipping ZIP package creation"
fi

# Final verification
print_info "Running final verification..."
file_count=$(find "$DEPLOY_DIR" -type f | wc -l)
print_info "Deployment contains $file_count files"

# List deployment contents
print_info "Deployment directory contents:"
ls -la "$DEPLOY_DIR"

print_success "========================================="
print_success "Windows deployment completed successfully!"
print_success "========================================="
print_info "Deployment location: $(pwd)/$DEPLOY_DIR"
print_info "Application: $APP_NAME.exe"
print_info "Version: $APP_VERSION"
print_info "Qt Version: $QT_VERSION"

if [ -f "$INSTALLER_DIR/$PACKAGE_NAME" ]; then
    print_info "Package: $INSTALLER_DIR/$PACKAGE_NAME"
fi

print_info "You can now run the application from: $DEPLOY_DIR/$APP_NAME.exe"
