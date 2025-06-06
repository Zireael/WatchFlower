#!/bin/bash

# WatchFlower Windows deployment script
# This script packages the Windows build for distribution

set -e

echo "================================================================================"
echo "WatchFlower Windows deployment script"
echo "================================================================================"

# Check if we're running on Windows (Git Bash, WSL, or similar)
if [[ "$OSTYPE" != "msys" && "$OSTYPE" != "win32" && "$OSTYPE" != "cygwin" ]]; then
    echo "Warning: This script is designed for Windows environments"
fi

# Configuration
APP_NAME="WatchFlower"
APP_VERSION=$(grep -o 'VERSION [0-9.]*' CMakeLists.txt | head -1 | cut -d' ' -f2 || echo "1.0.0")
BUILD_DIR="build"
DEPLOY_DIR="deploy"
INSTALLER_DIR="installer"
QT_DIR="${QT_ROOT_DIR:-$Qt6_Dir}"

echo "App name: $APP_NAME"
echo "App version: $APP_VERSION"
echo "Build directory: $BUILD_DIR"
echo "Deploy directory: $DEPLOY_DIR"
echo "Qt directory: $QT_DIR"

# Verify Qt installation
if [[ -z "$QT_DIR" ]]; then
    echo "Error: Qt directory not found. Please set QT_ROOT_DIR or Qt6_Dir environment variable"
    exit 1
fi

if [[ ! -f "$QT_DIR/bin/windeployqt.exe" ]]; then
    echo "Error: windeployqt.exe not found at $QT_DIR/bin/"
    exit 1
fi

# Verify build exists
if [[ ! -f "$BUILD_DIR/$APP_NAME.exe" ]]; then
    echo "Error: $APP_NAME.exe not found in $BUILD_DIR"
    echo "Please build the application first"
    exit 1
fi

echo "================================================================================"
echo "Preparing deployment directory"
echo "================================================================================"

# Clean and create deploy directory
rm -rf "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"

# Copy main executable
echo "Copying executable..."
cp "$BUILD_DIR/$APP_NAME.exe" "$DEPLOY_DIR/"

# Copy additional files if they exist
echo "Copying additional files..."
if [[ -f "README.md" ]]; then
    cp "README.md" "$DEPLOY_DIR/"
fi

if [[ -f "LICENSE" || -f "LICENSE.md" ]]; then
    cp LICENSE* "$DEPLOY_DIR/" 2>/dev/null || true
fi

if [[ -f "CHANGELOG.md" ]]; then
    cp "CHANGELOG.md" "$DEPLOY_DIR/"
fi

# Copy assets if they exist
if [[ -d "assets" ]]; then
    echo "Copying assets..."
    cp -r "assets" "$DEPLOY_DIR/" || true
fi

echo "================================================================================"
echo "Running windeployqt"
echo "================================================================================"

# Run windeployqt to gather Qt dependencies
"$QT_DIR/bin/windeployqt.exe" \
    --qmldir . \
    --no-translations \
    --no-system-d3d-compiler \
    --no-opengl-sw \
    --no-compiler-runtime \
    --release \
    "$DEPLOY_DIR/$APP_NAME.exe"

echo "================================================================================"
echo "Deploying Visual C++ runtime libraries"
echo "================================================================================"

# Function to find and copy MSVC runtime
deploy_msvc_runtime() {
    local vswhere_path="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
    
    if [[ -f "$vswhere_path" ]]; then
        local vs_install_dir=$("$vswhere_path" -latest -property installationPath)
        local redist_dir="$vs_install_dir/VC/Redist/MSVC"
        
        if [[ -d "$redist_dir" ]]; then
            # Find the latest version
            local latest_version=$(ls "$redist_dir" | sort -V | tail -1)
            local runtime_dir="$redist_dir/$latest_version/x64/Microsoft.VC143.CRT"
            
            if [[ -d "$runtime_dir" ]]; then
                echo "Found MSVC runtime at: $runtime_dir"
                cp "$runtime_dir"/*.dll "$DEPLOY_DIR/" 2>/dev/null || true
                return 0
            fi
        fi
    fi
    
    # Fallback: try to find runtime DLLs in system
    echo "Fallback: searching for MSVC runtime in system directories"
    local system_dirs=("/c/Windows/System32" "/c/Windows/SysWOW64")
    
    for dir in "${system_dirs[@]}"; do
        if [[ -f "$dir/msvcp140.dll" ]]; then
            cp "$dir/msvcp140.dll" "$DEPLOY_DIR/" 2>/dev/null || true
            cp "$dir/vcruntime140.dll" "$DEPLOY_DIR/" 2>/dev/null || true
            cp "$dir/vcruntime140_1.dll" "$DEPLOY_DIR/" 2>/dev/null || true
            echo "Copied MSVC runtime from $dir"
            return 0
        fi
    done
    
    echo "Warning: Could not find MSVC runtime libraries"
    return 1
}

deploy_msvc_runtime

echo "================================================================================"
echo "Creating installer (if NSIS is available)"
echo "================================================================================"

# Check if NSIS is available
NSIS_PATH=""
if command -v makensis >/dev/null 2>&1; then
    NSIS_PATH="makensis"
elif [[ -f "/c/Program Files (x86)/NSIS/makensis.exe" ]]; then
    NSIS_PATH="/c/Program Files (x86)/NSIS/makensis.exe"
elif [[ -f "/c/Program Files/NSIS/makensis.exe" ]]; then
    NSIS_PATH="/c/Program Files/NSIS/makensis.exe"
fi

if [[ -n "$NSIS_PATH" ]]; then
    echo "Found NSIS at: $NSIS_PATH"
    
    # Create installer directory
    mkdir -p "$INSTALLER_DIR"
    
    # Create NSIS script
    cat > "$INSTALLER_DIR/installer.nsi" << EOF
; WatchFlower NSIS installer script
; Generated by deploy_windows.sh

!include "MUI2.nsh"

; General
Name "$APP_NAME"
OutFile "$APP_NAME-$APP_VERSION-Windows-x64-installer.exe"
InstallDir "\$PROGRAMFILES64\\$APP_NAME"
InstallDirRegKey HKCU "Software\\$APP_NAME" ""
RequestExecutionLevel admin

; Interface Settings
!define MUI_ABORTWARNING

; Pages
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "..\\LICENSE"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

; Languages
!insertmacro MUI_LANGUAGE "English"

; Sections
Section "$APP_NAME (required)" SecMain
  SectionIn RO
  
  SetOutPath "\$INSTDIR"
  File /r "..\\$DEPLOY_DIR\\*"
  
  ; Store installation folder
  WriteRegStr HKCU "Software\\$APP_NAME" "" \$INSTDIR
  
  ; Create uninstaller
  WriteUninstaller "\$INSTDIR\\Uninstall.exe"
  
  ; Create shortcuts
  CreateDirectory "\$SMPROGRAMS\\$APP_NAME"
  CreateShortcut "\$SMPROGRAMS\\$APP_NAME\\$APP_NAME.lnk" "\$INSTDIR\\$APP_NAME.exe"
  CreateShortcut "\$SMPROGRAMS\\$APP_NAME\\Uninstall.lnk" "\$INSTDIR\\Uninstall.exe"
  CreateShortcut "\$DESKTOP\\$APP_NAME.lnk" "\$INSTDIR\\$APP_NAME.exe"
  
SectionEnd

; Uninstaller
Section "Uninstall"
  Delete "\$INSTDIR\\Uninstall.exe"
  RMDir /r "\$INSTDIR"
  
  DeleteRegKey /ifempty HKCU "Software\\$APP_NAME"
  
  Delete "\$SMPROGRAMS\\$APP_NAME\\*"
  RMDir "\$SMPROGRAMS\\$APP_NAME"
  Delete "\$DESKTOP\\$APP_NAME.lnk"
SectionEnd
EOF

    echo "Creating installer..."
    cd "$INSTALLER_DIR"
    "$NSIS_PATH" installer.nsi
    cd ..
    
    if [[ -f "$INSTALLER_DIR/$APP_NAME-$APP_VERSION-Windows-x64-installer.exe" ]]; then
        mv "$INSTALLER_DIR/$APP_NAME-$APP_VERSION-Windows-x64-installer.exe" "$DEPLOY_DIR/"
        echo "Installer created successfully!"
    else
        echo "Warning: Installer creation failed"
    fi
else
    echo "NSIS not found, skipping installer creation"
    echo "To create an installer, install NSIS from https://nsis.sourceforge.io/"
fi

echo "================================================================================"
echo "Creating portable archive"
echo "================================================================================"

# Create portable ZIP archive
if command -v 7z >/dev/null 2>&1; then
    echo "Creating 7z archive..."
    7z a "$DEPLOY_DIR/$APP_NAME-$APP_VERSION-Windows-x64-portable.7z" "./$DEPLOY_DIR/*" -x!"*.7z" -x!"*.exe"
elif command -v zip >/dev/null 2>&1; then
    echo "Creating ZIP archive..."
    cd "$DEPLOY_DIR"
    zip -r "$APP_NAME-$APP_VERSION-Windows-x64-portable.zip" . -x "*.zip" "*.exe"
    cd ..
else
    echo "No archive tool found (7z or zip), skipping portable archive creation"
fi

echo "================================================================================"
echo "Deployment summary"
echo "================================================================================"

echo "Deployment completed successfully!"
echo "Files deployed to: $DEPLOY_DIR"
echo ""
echo "Contents:"
ls -la "$DEPLOY_DIR"
echo ""

# Calculate total size
if command -v du >/dev/null 2>&1; then
    TOTAL_SIZE=$(du -sh "$DEPLOY_DIR" | cut -f1)
    echo "Total size: $TOTAL_SIZE"
fi

echo ""
echo "The application is ready for distribution!"
echo "You can run the application with: ./$DEPLOY_DIR/$APP_NAME.exe"
echo "================================================================================"
