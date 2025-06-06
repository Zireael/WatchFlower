#!/bin/bash

# WatchFlower Windows Deployment Script
# Fixed version for CI/CD environments

set -e  # Exit on any error
set -x  # Print commands for debugging

# Configuration
APP_NAME="WatchFlower"
APP_VERSION=${APP_VERSION:-"1.0.0"}
BUILD_TYPE=${BUILD_TYPE:-"Release"}
QT_VERSION=${QT_VERSION:-"6.7"}
MSVC_VERSION=${MSVC_VERSION:-"2022"}

# Paths - using forward slashes (Git Bash handles this correctly)
PROJECT_DIR="$(pwd)"
BUILD_DIR="${PROJECT_DIR}/build-windows"
DIST_DIR="${PROJECT_DIR}/dist-windows"
DEPLOY_DIR="${PROJECT_DIR}/deploy-windows"

echo "=== WatchFlower Windows Deployment Script ==="
echo "Project Directory: ${PROJECT_DIR}"
echo "Build Directory: ${BUILD_DIR}"
echo "Distribution Directory: ${DIST_DIR}"
echo "Deployment Directory: ${DEPLOY_DIR}"
echo "Qt Version: ${QT_VERSION}"
echo "MSVC Version: ${MSVC_VERSION}"
echo "Build Type: ${BUILD_TYPE}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to find Qt installation
find_qt_installation() {
    # GitHub Actions Qt installation paths
    local qt_dirs=(
        "${Qt6_DIR}"
        "${QTDIR}"
        "${QT_ROOT_DIR}"
        "${RUNNER_WORKSPACE}/Qt/${QT_VERSION}/msvc2019_64"
        "C:/Qt/${QT_VERSION}/msvc2019_64"
        "C:/Qt/${QT_VERSION}/msvc2022_64"
        "C:/Qt/Tools/QtCreator/bin"
        "/c/Qt/${QT_VERSION}/msvc2019_64"
        "/c/Qt/${QT_VERSION}/msvc2022_64"
    )
    
    # Also check PATH for qmake
    if command_exists qmake; then
        local qmake_path
        qmake_path=$(which qmake)
        if [[ -n "$qmake_path" ]]; then
            # Get directory containing qmake, then parent directory
            local qt_bin_dir
            qt_bin_dir=$(dirname "$qmake_path")
            local qt_root
            qt_root=$(dirname "$qt_bin_dir")
            if [[ -d "$qt_root" && -f "$qt_root/bin/qmake.exe" ]]; then
                echo "$qt_root"
                return 0
            fi
        fi
    fi
    
    for qt_dir in "${qt_dirs[@]}"; do
        if [[ -n "$qt_dir" && -d "$qt_dir" && -f "$qt_dir/bin/qmake.exe" ]]; then
            echo "$qt_dir"
            return 0
        fi
    done
    
    return 1
}

# Function to setup Qt environment
setup_qt_environment() {
    echo "=== Setting up Qt Environment ==="
    
    # Print environment variables for debugging
    echo "Environment variables:"
    echo "  Qt6_DIR: ${Qt6_DIR:-'not set'}"
    echo "  QTDIR: ${QTDIR:-'not set'}"
    echo "  QT_ROOT_DIR: ${QT_ROOT_DIR:-'not set'}"
    echo "  PATH: ${PATH}"
    
    # Check if Qt tools are already in PATH
    if command_exists qmake && command_exists windeployqt; then
        echo "Qt tools found in PATH"
        qmake --version
        windeployqt --version
        
        # Get Qt installation directory from qmake
        local qmake_path
        qmake_path=$(which qmake)
        QT_DIR=$(dirname $(dirname "$qmake_path"))
        export QTDIR="$QT_DIR"
        echo "Qt installation detected at: $QT_DIR"
        return 0
    fi
    
    # Try to find Qt installation
    QT_DIR=$(find_qt_installation)
    if [[ -z "$QT_DIR" ]]; then
        echo "ERROR: Qt installation not found!"
        echo "Available Qt installations:"
        find /c/Qt* -name "qmake.exe" 2>/dev/null || true
        find /d/a -name "qmake.exe" 2>/dev/null || true
        echo "Please install Qt ${QT_VERSION} with MSVC support"
        echo "Or set Qt6_DIR/QTDIR environment variable"
        exit 1
    fi
    
    echo "Found Qt at: ${QT_DIR}"
    
    # Add Qt to PATH
    export PATH="${QT_DIR}/bin:${PATH}"
    export QTDIR="${QT_DIR}"
    
    # Verify Qt tools
    if ! command_exists qmake; then
        echo "ERROR: qmake not found in PATH after adding ${QT_DIR}/bin"
        exit 1
    fi
    
    if ! command_exists windeployqt; then
        echo "ERROR: windeployqt not found in PATH after adding ${QT_DIR}/bin"
        exit 1
    fi
    
    echo "Qt tools verified successfully"
    qmake --version
    windeployqt --version
}

# Function to setup MSVC environment
setup_msvc_environment() {
    echo "=== Setting up MSVC Environment ==="
    
    # Common MSVC installation paths
    local msvc_paths=(
        "C:/Program Files/Microsoft Visual Studio/${MSVC_VERSION}/Enterprise/VC/Auxiliary/Build/vcvars64.bat"
        "C:/Program Files/Microsoft Visual Studio/${MSVC_VERSION}/Professional/VC/Auxiliary/Build/vcvars64.bat"
        "C:/Program Files/Microsoft Visual Studio/${MSVC_VERSION}/Community/VC/Auxiliary/Build/vcvars64.bat"
        "C:/Program Files (x86)/Microsoft Visual Studio/${MSVC_VERSION}/Enterprise/VC/Auxiliary/Build/vcvars64.bat"
        "C:/Program Files (x86)/Microsoft Visual Studio/${MSVC_VERSION}/Professional/VC/Auxiliary/Build/vcvars64.bat"
        "C:/Program Files (x86)/Microsoft Visual Studio/${MSVC_VERSION}/Community/VC/Auxiliary/Build/vcvars64.bat"
    )
    
    for vcvars_path in "${msvc_paths[@]}"; do
        if [[ -f "$vcvars_path" ]]; then
            echo "Found MSVC at: ${vcvars_path}"
            # Note: In CI environments, MSVC is usually pre-configured
            # If not, you'd need to call this bat file
            return 0
        fi
    done
    
    # Check if cl.exe is already available
    if command_exists cl; then
        echo "MSVC compiler found in PATH"
        cl 2>&1 | head -1 || true
        return 0
    fi
    
    echo "WARNING: MSVC not found. Assuming it's configured in CI environment."
}

# Function to clean previous builds
clean_build() {
    echo "=== Cleaning Previous Builds ==="
    
    if [[ -d "$BUILD_DIR" ]]; then
        echo "Removing existing build directory..."
        rm -rf "$BUILD_DIR"
    fi
    
    if [[ -d "$DIST_DIR" ]]; then
        echo "Removing existing distribution directory..."
        rm -rf "$DIST_DIR"
    fi
    
    if [[ -d "$DEPLOY_DIR" ]]; then
        echo "Removing existing deployment directory..."
        rm -rf "$DEPLOY_DIR"
    fi
    
    echo "Clean completed"
}

# Function to configure CMake build
configure_build() {
    echo "=== Configuring CMake Build ==="
    
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # CMake configuration
    cmake_args=(
        "-DCMAKE_BUILD_TYPE=${BUILD_TYPE}"
        "-DCMAKE_PREFIX_PATH=${QTDIR}"
        "-DCMAKE_INSTALL_PREFIX=${DIST_DIR}"
        "-DQT_VERSION_MAJOR=6"
    )
    
    # Add platform-specific arguments
    if [[ -n "${CMAKE_GENERATOR:-}" ]]; then
        cmake_args+=("-G" "${CMAKE_GENERATOR}")
    else
        cmake_args+=("-G" "Visual Studio 17 2022")
    fi
    
    cmake_args+=("-A" "x64")
    
    echo "Running CMake with arguments: ${cmake_args[*]}"
    cmake "${cmake_args[@]}" "$PROJECT_DIR"
    
    cd "$PROJECT_DIR"
}

# Function to build the application
build_application() {
    echo "=== Building Application ==="
    
    cd "$BUILD_DIR"
    
    # Build using CMake
    cmake --build . --config "$BUILD_TYPE" --parallel
    
    # Install to distribution directory
    cmake --install . --config "$BUILD_TYPE"
    
    cd "$PROJECT_DIR"
    
    echo "Build completed successfully"
}

# Function to deploy Qt dependencies
deploy_qt_dependencies() {
    echo "=== Deploying Qt Dependencies ==="
    
    # Find the executable
    local exe_path
    if [[ -f "${DIST_DIR}/bin/${APP_NAME}.exe" ]]; then
        exe_path="${DIST_DIR}/bin/${APP_NAME}.exe"
    elif [[ -f "${DIST_DIR}/${APP_NAME}.exe" ]]; then
        exe_path="${DIST_DIR}/${APP_NAME}.exe"
    else
        echo "ERROR: Application executable not found!"
        find "$DIST_DIR" -name "*.exe" -type f || true
        exit 1
    fi
    
    echo "Found executable at: ${exe_path}"
    
    # Create deployment directory
    mkdir -p "$DEPLOY_DIR"
    
    # Copy executable to deployment directory
    cp "$exe_path" "$DEPLOY_DIR/"
    
    # Run windeployqt
    cd "$DEPLOY_DIR"
    
    local windeployqt_args=(
        "--${BUILD_TYPE,,}"  # Convert to lowercase
        "--qmldir" "${PROJECT_DIR}/qml"
        "--no-translations"  # Skip if not needed
        "--no-system-d3d-compiler"
        "--no-opengl-sw"
        "${APP_NAME}.exe"
    )
    
    echo "Running windeployqt with arguments: ${windeployqt_args[*]}"
    windeployqt "${windeployqt_args[@]}"
    
    cd "$PROJECT_DIR"
    
    echo "Qt dependencies deployed successfully"
}

# Function to copy additional resources
copy_resources() {
    echo "=== Copying Additional Resources ==="
    
    # Copy assets if they exist
    if [[ -d "${PROJECT_DIR}/assets" ]]; then
        echo "Copying assets..."
        cp -r "${PROJECT_DIR}/assets" "$DEPLOY_DIR/"
    fi
    
    # Copy documentation
    local docs=("README.md" "LICENSE" "LICENSE.md" "CHANGELOG.md")
    for doc in "${docs[@]}"; do
        if [[ -f "${PROJECT_DIR}/${doc}" ]]; then
            echo "Copying ${doc}..."
            cp "${PROJECT_DIR}/${doc}" "$DEPLOY_DIR/"
        fi
    done
    
    echo "Resources copied successfully"
}

# Function to create installer (optional)
create_installer() {
    echo "=== Creating Installer ==="
    
    # Check if NSIS is available
    if command_exists makensis; then
        echo "NSIS found, creating installer..."
        
        # Create basic NSIS script if it doesn't exist
        local nsis_script="${PROJECT_DIR}/installer.nsi"
        if [[ ! -f "$nsis_script" ]]; then
            cat > "$nsis_script" << EOF
!define APP_NAME "${APP_NAME}"
!define APP_VERSION "${APP_VERSION}"
!define PUBLISHER "WatchFlower Team"
!define WEB_SITE "https://github.com/emericg/WatchFlower"

Name "\${APP_NAME}"
OutFile "${APP_NAME}-\${APP_VERSION}-setup.exe"
InstallDir "\$PROGRAMFILES64\\\${APP_NAME}"

Page directory
Page instfiles

Section ""
    SetOutPath "\$INSTDIR"
    File /r "${DEPLOY_DIR}\\*"
    WriteUninstaller "\$INSTDIR\\uninstall.exe"
SectionEnd

Section "Uninstall"
    Delete "\$INSTDIR\\uninstall.exe"
    RMDir /r "\$INSTDIR"
SectionEnd
EOF
        fi
        
        # Create installer
        makensis "$nsis_script"
        
        if [[ -f "${APP_NAME}-${APP_VERSION}-setup.exe" ]]; then
            echo "Installer created: ${APP_NAME}-${APP_VERSION}-setup.exe"
        fi
    else
        echo "NSIS not found, skipping installer creation"
    fi
}

# Function to create ZIP archive
create_archive() {
    echo "=== Creating ZIP Archive ==="
    
    local archive_name="${APP_NAME}-${APP_VERSION}-windows-x64.zip"
    
    cd "$(dirname "$DEPLOY_DIR")"
    
    if command_exists 7z; then
        7z a -tzip "$archive_name" "$(basename "$DEPLOY_DIR")/*"
    elif command_exists zip; then
        zip -r "$archive_name" "$(basename "$DEPLOY_DIR")"
    else
        echo "WARNING: No archiving tool found (7z or zip)"
        echo "Deployment files are available in: $DEPLOY_DIR"
        return 0
    fi
    
    if [[ -f "$archive_name" ]]; then
        echo "Archive created: $archive_name"
        echo "Archive size: $(du -h "$archive_name" | cut -f1)"
    fi
    
    cd "$PROJECT_DIR"
}

# Function to verify deployment
verify_deployment() {
    echo "=== Verifying Deployment ==="
    
    local exe_file="${DEPLOY_DIR}/${APP_NAME}.exe"
    
    if [[ ! -f "$exe_file" ]]; then
        echo "ERROR: Executable not found in deployment directory!"
        exit 1
    fi
    
    echo "Executable found: $exe_file"
    echo "Executable size: $(du -h "$exe_file" | cut -f1)"
    
    # List deployment contents
    echo "Deployment contents:"
    find "$DEPLOY_DIR" -type f | head -20
    
    local file_count
    file_count=$(find "$DEPLOY_DIR" -type f | wc -l)
    echo "Total files in deployment: $file_count"
    
    local total_size
    total_size=$(du -sh "$DEPLOY_DIR" | cut -f1)
    echo "Total deployment size: $total_size"
    
    echo "Deployment verification completed successfully"
}

# Main execution
main() {
    echo "Starting Windows deployment process..."
    
    # Check if we're in the right directory
    if [[ ! -f "CMakeLists.txt" ]]; then
        echo "ERROR: CMakeLists.txt not found. Please run this script from the project root."
        exit 1
    fi
    
    # Execute deployment steps
    setup_qt_environment
    setup_msvc_environment
    clean_build
    configure_build
    build_application
    deploy_qt_dependencies
    copy_resources
    verify_deployment
    create_archive
    
    # Optional: create installer
    if [[ "${CREATE_INSTALLER:-false}" == "true" ]]; then
        create_installer
    fi
    
    echo "=== Windows Deployment Completed Successfully ==="
    echo "Deployment directory: $DEPLOY_DIR"
    echo "Ready for distribution!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo "  --clean       Clean only (don't build)"
        echo ""
        echo "Environment variables:"
        echo "  APP_VERSION       Application version (default: 1.0.0)"
        echo "  BUILD_TYPE        Build type (default: Release)"
        echo "  QT_VERSION        Qt version (default: 6.7)"
        echo "  MSVC_VERSION      MSVC version (default: 2022)"
        echo "  CREATE_INSTALLER  Create NSIS installer (default: false)"
        exit 0
        ;;
    --clean)
        clean_build
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
