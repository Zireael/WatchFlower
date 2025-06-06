#!/bin/bash

# WatchFlower Windows Deployment Script
# Fixed version for CI/CD builds

set -e  # Exit on any error

# Configuration
APP_NAME="${APP_NAME:-WatchFlower}"
APP_VERSION="${APP_VERSION:-1.0.0}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
QT_VERSION="${QT_VERSION:-6.7.3}"
MSVC_VERSION="${MSVC_VERSION:-2022}"

# Directories
PROJECT_DIR="$(pwd)"
BUILD_DIR="${PROJECT_DIR}/build-windows"
DIST_DIR="${PROJECT_DIR}/dist-windows"
DEPLOY_DIR="${PROJECT_DIR}/deploy-windows"

# Utility functions
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

setup_qt_environment() {
    echo "=== Setting up Qt Environment ==="
    
    # Display environment variables
    echo "Environment variables:"
    echo "  Qt6_DIR: ${Qt6_DIR:-'not set'}"
    echo "  QTDIR: ${QTDIR:-'not set'}"
    echo "  QT_ROOT_DIR: ${QT_ROOT_DIR:-'not set'}"
    
    # Check if Qt tools are available
    if ! command_exists qmake; then
        error_exit "qmake not found in PATH. Qt installation may be incomplete."
    fi
    
    if ! command_exists windeployqt; then
        error_exit "windeployqt not found in PATH. Qt installation may be incomplete."
    fi
    
    echo "Qt tools found in PATH"
    qmake --version
    windeployqt --version
    
    # Set QTDIR if not already set
    if [[ -z "${QTDIR}" ]]; then
        local qmake_path
        qmake_path=$(which qmake)
        if [[ -n "${qmake_path}" ]]; then
            # Convert Windows path to Unix-style path for bash
            qmake_path=$(cygpath -u "${qmake_path}" 2>/dev/null || echo "${qmake_path}")
            QT_DIR=$(dirname "$(dirname "${qmake_path}")")
            export QTDIR="${QT_DIR}"
            echo "Qt installation detected at: ${QT_DIR}"
        fi
    fi
    
    return 0
}

setup_msvc_environment() {
    echo "=== Setting up MSVC Environment ==="
    
    # Common MSVC paths (Windows style)
    local msvc_paths=(
        "C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Auxiliary/Build/vcvars64.bat"
        "C:/Program Files/Microsoft Visual Studio/2022/Professional/VC/Auxiliary/Build/vcvars64.bat"
        "C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Auxiliary/Build/vcvars64.bat"
        "C:/Program Files (x86)/Microsoft Visual Studio/2022/Enterprise/VC/Auxiliary/Build/vcvars64.bat"
        "C:/Program Files (x86)/Microsoft Visual Studio/2022/Professional/VC/Auxiliary/Build/vcvars64.bat"
        "C:/Program Files (x86)/Microsoft Visual Studio/2022/Community/VC/Auxiliary/Build/vcvars64.bat"
    )
    
    # Check if MSVC is available
    for vcvars_path in "${msvc_paths[@]}"; do
        if [[ -f "${vcvars_path}" ]]; then
            echo "Found MSVC at: ${vcvars_path}"
            return 0
        fi
    done
    
    # Check if we're in a developer command prompt (environment already set)
    if [[ -n "${VCINSTALLDIR}" ]] || [[ -n "${VS160COMNTOOLS}" ]] || [[ -n "${VS170COMNTOOLS}" ]]; then
        echo "MSVC environment already configured"
        return 0
    fi
    
    error_exit "MSVC installation not found. Please install Visual Studio 2022."
}

clean_build() {
    echo "=== Cleaning Previous Builds ==="
    
    if [[ -d "${BUILD_DIR}" ]]; then
        echo "Removing existing build directory: ${BUILD_DIR}"
        rm -rf "${BUILD_DIR}"
    fi
    
    if [[ -d "${DIST_DIR}" ]]; then
        echo "Removing existing dist directory: ${DIST_DIR}"
        rm -rf "${DIST_DIR}"
    fi
    
    if [[ -d "${DEPLOY_DIR}" ]]; then
        echo "Removing existing deploy directory: ${DEPLOY_DIR}"
        rm -rf "${DEPLOY_DIR}"
    fi
    
    echo "Clean completed"
}

configure_build() {
    echo "=== Configuring CMake Build ==="
    
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"
    
    # CMake arguments
    local cmake_args=(
        "-DCMAKE_BUILD_TYPE=${BUILD_TYPE}"
        "-DCMAKE_INSTALL_PREFIX=${DIST_DIR}"
        "-DQT_VERSION_MAJOR=6"
    )
    
    # Set Qt path for CMake
    if [[ -n "${QTDIR}" ]]; then
        cmake_args+=("-DCMAKE_PREFIX_PATH=${QTDIR}")
    elif [[ -n "${Qt6_DIR}" ]]; then
        cmake_args+=("-DCMAKE_PREFIX_PATH=${Qt6_DIR}")
    fi
    
    # Use Visual Studio generator instead of Ninja for better Windows compatibility
    # This avoids the CMAKE_CXX_COMPILER issue with Ninja
    local generator="Visual Studio 17 2022"
    if command_exists "cmake" && cmake --help | grep -q "Visual Studio 17 2022"; then
        cmake_args+=("-G" "${generator}")
        cmake_args+=("-A" "x64")
        echo "Using Visual Studio 2022 generator"
    else
        # Fallback to Ninja if Visual Studio generator not available
        # But ensure MSVC compiler is properly set
        cmake_args+=("-G" "Ninja")
        
        # Set compiler explicitly for Ninja
        if [[ -n "${VCINSTALLDIR}" ]]; then
            # Find cl.exe in MSVC installation
            local cl_path
            cl_path=$(find "${VCINSTALLDIR}" -name "cl.exe" -path "*/HostX64/x64/*" | head -1 2>/dev/null || true)
            if [[ -n "${cl_path}" ]]; then
                cmake_args+=("-DCMAKE_C_COMPILER=${cl_path}")
                cmake_args+=("-DCMAKE_CXX_COMPILER=${cl_path}")
            fi
        fi
        echo "Using Ninja generator with MSVC"
    fi
    
    echo "Running CMake with arguments: ${cmake_args[*]}"
    
    # Run CMake configuration
    if ! cmake "${cmake_args[@]}" "${PROJECT_DIR}"; then
        error_exit "CMake configuration failed"
    fi
    
    echo "CMake configuration completed successfully"
}

build_project() {
    echo "=== Building Project ==="
    
    cd "${BUILD_DIR}"
    
    # Build the project
    echo "Building with CMake..."
    if ! cmake --build . --config "${BUILD_TYPE}" --parallel; then
        error_exit "Build failed"
    fi
    
    echo "Build completed successfully"
}

install_project() {
    echo "=== Installing Project ==="
    
    cd "${BUILD_DIR}"
    
    # Install the project
    echo "Installing project to ${DIST_DIR}..."
    if ! cmake --install . --config "${BUILD_TYPE}"; then
        error_exit "Installation failed"
    fi
    
    echo "Installation completed successfully"
}

deploy_application() {
    echo "=== Deploying Application ==="
    
    # Create deployment directory
    mkdir -p "${DEPLOY_DIR}"
    
    # Find the main executable
    local exe_name="${APP_NAME}.exe"
    local exe_path
    
    # Look for executable in various locations
    if [[ -f "${DIST_DIR}/bin/${exe_name}" ]]; then
        exe_path="${DIST_DIR}/bin/${exe_name}"
    elif [[ -f "${DIST_DIR}/${exe_name}" ]]; then
        exe_path="${DIST_DIR}/${exe_name}"
    elif [[ -f "${BUILD_DIR}/${BUILD_TYPE}/${exe_name}" ]]; then
        exe_path="${BUILD_DIR}/${BUILD_TYPE}/${exe_name}"
    elif [[ -f "${BUILD_DIR}/${exe_name}" ]]; then
        exe_path="${BUILD_DIR}/${exe_name}"
    else
        error_exit "Could not find executable ${exe_name}"
    fi
    
    echo "Found executable at: ${exe_path}"
    
    # Copy executable to deployment directory
    cp "${exe_path}" "${DEPLOY_DIR}/"
    
    # Deploy Qt dependencies
    echo "Deploying Qt dependencies..."
    cd "${DEPLOY_DIR}"
    
    if ! windeployqt --release --qmldir "${PROJECT_DIR}" "${exe_name}"; then
        error_exit "windeployqt failed"
    fi
    
    echo "Qt deployment completed successfully"
}

create_archive() {
    echo "=== Creating Distribution Archive ==="
    
    cd "${PROJECT_DIR}"
    
    local archive_name="${APP_NAME}-${APP_VERSION}-windows-x64.zip"
    
    # Create zip archive
    if command_exists 7z; then
        7z a "${archive_name}" "${DEPLOY_DIR}/*"
    elif command_exists zip; then
        zip -r "${archive_name}" "${DEPLOY_DIR}"
    elif command_exists powershell; then
        powershell -Command "Compress-Archive -Path '${DEPLOY_DIR}\\*' -DestinationPath '${archive_name}'"
    else
        error_exit "No archive tool available (7z, zip, or PowerShell)"
    fi
    
    if [[ -f "${archive_name}" ]]; then
        echo "Archive created successfully: ${archive_name}"
        echo "Archive size: $(du -h "${archive_name}" | cut -f1)"
    else
        error_exit "Failed to create archive"
    fi
}

print_summary() {
    echo "=== Deployment Summary ==="
    echo "Project Directory: ${PROJECT_DIR}"
    echo "Build Directory: ${BUILD_DIR}"
    echo "Distribution Directory: ${DIST_DIR}"
    echo "Deployment Directory: ${DEPLOY_DIR}"
    echo "Qt Version: ${QT_VERSION}"
    echo "MSVC Version: ${MSVC_VERSION}"
    echo "Build Type: ${BUILD_TYPE}"
    echo "App Version: ${APP_VERSION}"
}

main() {
    echo "Starting Windows deployment process..."
    
    # Verify we're in the right directory
    if [[ ! -f "CMakeLists.txt" ]]; then
        error_exit "CMakeLists.txt not found. Please run this script from the project root directory."
    fi
    
    print_summary
    
    setup_qt_environment
    setup_msvc_environment
    clean_build
    configure_build
    build_project
    install_project
    deploy_application
    create_archive
    
    echo "Windows deployment completed successfully!"
    echo "Deployable application available in: ${DEPLOY_DIR}"
}

# Handle script arguments
case "${1:-}" in
    clean)
        clean_build
        ;;
    configure)
        setup_qt_environment
        setup_msvc_environment
        configure_build
        ;;
    build)
        build_project
        ;;
    deploy)
        deploy_application
        ;;
    archive)
        create_archive
        ;;
    *)
        main
        ;;
esac
