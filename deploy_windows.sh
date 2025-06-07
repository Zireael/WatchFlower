#!/bin/bash

# WatchFlower Windows deployment script
# Fixed version addressing common CI build issues

set -e  # Exit on any error
set -x  # Print commands for debugging

echo "===================="
echo "WatchFlower Windows CI Build"
echo "===================="

# Configuration
QT_VERSION="6.7.3"
QT_ARCH="win64_msvc2022_64"
QT_MODULES="qtconnectivity qtcharts qtpositioning qtshadertools"
BUILD_DIR="build_windows"
DEPLOY_DIR="WatchFlower_windows"

# Print system information for debugging
echo "System Information:"
echo "OS: $(uname -a)"
echo "Current directory: $(pwd)"
echo "User: $(whoami)"

# Clean previous builds
echo "Cleaning previous builds..."
rm -rf ${BUILD_DIR} ${DEPLOY_DIR}
mkdir -p ${BUILD_DIR} ${DEPLOY_DIR}

# Set up Qt installation directory
QT_DIR="${RUNNER_WORKSPACE}/Qt/${QT_VERSION}/${QT_ARCH}"
if [ -z "${RUNNER_WORKSPACE}" ]; then
    QT_DIR="${HOME}/Qt/${QT_VERSION}/${QT_ARCH}"
fi

echo "Qt installation directory: ${QT_DIR}"

# Check if Qt is installed, if not install it
if [ ! -d "${QT_DIR}" ]; then
    echo "Installing Qt ${QT_VERSION}..."
    
    # Install aqtinstall if not available
    python -m pip install --upgrade pip
    python -m pip install aqtinstall
    
    # Create Qt directory
    mkdir -p "$(dirname ${QT_DIR})"
    
    # Install Qt with required modules
    echo "Installing Qt base..."
    python -m aqt install-qt windows desktop ${QT_VERSION} ${QT_ARCH} -O "$(dirname $(dirname ${QT_DIR}))"
    
    echo "Installing Qt modules: ${QT_MODULES}"
    for module in ${QT_MODULES}; do
        echo "Installing module: ${module}"
        python -m aqt install-qt windows desktop ${QT_VERSION} ${QT_ARCH} -m ${module} -O "$(dirname $(dirname ${QT_DIR}))" || {
            echo "Warning: Failed to install module ${module}, continuing..."
        }
    done
    
    echo "Installing Qt tools..."
    python -m aqt install-tool windows desktop tools_cmake -O "$(dirname $(dirname ${QT_DIR}))" || echo "Warning: Failed to install CMake tools"
else
    echo "Qt ${QT_VERSION} already installed"
fi

# Verify Qt installation
if [ ! -d "${QT_DIR}" ]; then
    echo "ERROR: Qt installation failed or not found at ${QT_DIR}"
    exit 1
fi

echo "Qt installation verified at: ${QT_DIR}"

# Set up environment variables
export Qt6_DIR="${QT_DIR}/lib/cmake/Qt6"
export QT_QPA_PLATFORM_PLUGIN_PATH="${QT_DIR}/plugins/platforms"
export PATH="${QT_DIR}/bin:${PATH}"

# Add MSVC tools to PATH if available
if [ -d "/d/a/_temp/msys64/mingw64/bin" ]; then
    export PATH="/d/a/_temp/msys64/mingw64/bin:${PATH}"
fi

# Print Qt version for verification
echo "Qt version check:"
if command -v qmake >/dev/null 2>&1; then
    qmake --version
else
    echo "Warning: qmake not found in PATH"
fi

# Check for CMake
if ! command -v cmake >/dev/null 2>&1; then
    echo "ERROR: CMake not found"
    exit 1
fi

cmake --version

# Configure build with CMake
echo "Configuring build with CMake..."
cd ${BUILD_DIR}

# CMake configuration with explicit Qt6 paths and modules
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DQt6_DIR="${Qt6_DIR}" \
    -DCMAKE_PREFIX_PATH="${QT_DIR}" \
    -DCMAKE_INSTALL_PREFIX="../${DEPLOY_DIR}" \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_CXX_STANDARD_REQUIRED=ON \
    -G "Visual Studio 17 2022" -A x64 || {
    
    echo "Visual Studio 2022 not found, trying Visual Studio 2019..."
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DQt6_DIR="${Qt6_DIR}" \
        -DCMAKE_PREFIX_PATH="${QT_DIR}" \
        -DCMAKE_INSTALL_PREFIX="../${DEPLOY_DIR}" \
        -DCMAKE_CXX_STANDARD=17 \
        -DCMAKE_CXX_STANDARD_REQUIRED=ON \
        -G "Visual Studio 16 2019" -A x64 || {
        
        echo "Visual Studio generators not found, trying Ninja..."
        cmake .. \
            -DCMAKE_BUILD_TYPE=Release \
            -DQt6_DIR="${Qt6_DIR}" \
            -DCMAKE_PREFIX_PATH="${QT_DIR}" \
            -DCMAKE_INSTALL_PREFIX="../${DEPLOY_DIR}" \
            -DCMAKE_CXX_STANDARD=17 \
            -DCMAKE_CXX_STANDARD_REQUIRED=ON \
            -G "Ninja"
    }
}

# Build the application
echo "Building WatchFlower..."
cmake --build . --config Release --parallel $(nproc) || cmake --build . --config Release

# Install the application
echo "Installing WatchFlower..."
cmake --install . --config Release

cd ..

# Check if the executable was built
EXECUTABLE_PATH="${DEPLOY_DIR}/WatchFlower.exe"
if [ ! -f "${EXECUTABLE_PATH}" ]; then
    # Try alternative paths
    EXECUTABLE_PATH="${DEPLOY_DIR}/bin/WatchFlower.exe"
    if [ ! -f "${EXECUTABLE_PATH}" ]; then
        EXECUTABLE_PATH="${BUILD_DIR}/Release/WatchFlower.exe"
        if [ ! -f "${EXECUTABLE_PATH}" ]; then
            EXECUTABLE_PATH="${BUILD_DIR}/WatchFlower.exe"
            if [ ! -f "${EXECUTABLE_PATH}" ]; then
                echo "ERROR: WatchFlower.exe not found in expected locations"
                find . -name "WatchFlower.exe" -type f || echo "No WatchFlower.exe found anywhere"
                exit 1
            fi
        fi
    fi
fi

echo "Found executable at: ${EXECUTABLE_PATH}"

# Copy executable to deployment directory if not already there
if [ "${EXECUTABLE_PATH}" != "${DEPLOY_DIR}/WatchFlower.exe" ]; then
    cp "${EXECUTABLE_PATH}" "${DEPLOY_DIR}/"
fi

# Deploy Qt dependencies
echo "Deploying Qt dependencies..."
cd ${DEPLOY_DIR}

# Use windeployqt to deploy Qt libraries
if command -v windeployqt >/dev/null 2>&1; then
    windeployqt.exe --release --qmldir ../qml WatchFlower.exe
else
    echo "windeployqt not found, manually copying Qt libraries..."
    
    # Manually copy essential Qt libraries
    QT_LIBS="Qt6Core Qt6Gui Qt6Widgets Qt6Network Qt6Bluetooth Qt6Charts Qt6Positioning"
    for lib in ${QT_LIBS}; do
        if [ -f "${QT_DIR}/bin/${lib}.dll" ]; then
            cp "${QT_DIR}/bin/${lib}.dll" .
        else
            echo "Warning: ${lib}.dll not found"
        fi
    done
    
    # Copy platforms plugin
    mkdir -p platforms
    if [ -f "${QT_DIR}/plugins/platforms/qwindows.dll" ]; then
        cp "${QT_DIR}/plugins/platforms/qwindows.dll" platforms/
    fi
    
    # Copy other essential plugins
    mkdir -p imageformats bearer
    cp "${QT_DIR}/plugins/imageformats/"*.dll imageformats/ 2>/dev/null || echo "Warning: Image format plugins not found"
    cp "${QT_DIR}/plugins/bearer/"*.dll bearer/ 2>/dev/null || echo "Warning: Bearer plugins not found"
fi

# Copy MSVC runtime (if available)
MSVC_REDIST_PATH="/c/Program Files (x86)/Microsoft Visual Studio/2022/Enterprise/VC/Redist/MSVC"
if [ ! -d "${MSVC_REDIST_PATH}" ]; then
    MSVC_REDIST_PATH="/c/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Redist/MSVC"
fi
if [ ! -d "${MSVC_REDIST_PATH}" ]; then
    MSVC_REDIST_PATH="/c/Program Files (x86)/Microsoft Visual Studio/2019/Enterprise/VC/Redist/MSVC"
fi

if [ -d "${MSVC_REDIST_PATH}" ]; then
    echo "Copying MSVC runtime libraries..."
    find "${MSVC_REDIST_PATH}" -name "msvcp*.dll" -o -name "vcruntime*.dll" | head -10 | while read dll; do
        cp "$dll" . 2>/dev/null || echo "Warning: Could not copy $dll"
    done
fi

cd ..

# Verify deployment
echo "Verifying deployment..."
ls -la ${DEPLOY_DIR}/
echo "WatchFlower.exe info:"
file ${DEPLOY_DIR}/WatchFlower.exe || echo "file command not available"

# Create archive
echo "Creating deployment archive..."
ARCHIVE_NAME="WatchFlower_Windows_$(date +%Y%m%d).zip"
if command -v 7z >/dev/null 2>&1; then
    7z a ${ARCHIVE_NAME} ${DEPLOY_DIR}/*
elif command -v zip >/dev/null 2>&1; then
    zip -r ${ARCHIVE_NAME} ${DEPLOY_DIR}/
else
    echo "Warning: No archive tool available (7z or zip)"
fi

echo "===================="
echo "Windows deployment completed successfully!"
echo "Executable: ${DEPLOY_DIR}/WatchFlower.exe"
if [ -f "${ARCHIVE_NAME}" ]; then
    echo "Archive: ${ARCHIVE_NAME}"
fi
echo "===================="
