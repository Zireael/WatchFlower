#!/usr/bin/env bash
set -e

###############################################################################
#  deploy_windows.sh
#
#  1) Creates a dummy assets/windows/WatchFlower.rc if missing (to avoid CMake 
#     errors).
#  2) Configures an out‐of‐source CMake build (Release x64).
#  3) Builds WatchFlower.
#  4) Runs windeployqt on the resulting EXE.
#  5) Copies QML/ and other assets into a single WatchFlower/ folder.
#  6) Zips that folder using native Windows tar (no 7z required).
#  7) (Optionally) Creates an NSIS installer if makensis is on PATH.
#
#  Usage:
#    cd WatchFlower/      # repository root
#    ./deploy_windows.sh [-u|--upload]
#
#  Options:
#    -u|--upload   : After packaging, also upload ZIP/EXE to transfer.sh
#
###############################################################################

#─────────────────────────────────────────────────────────────────────────────
# 1) METADATA
#─────────────────────────────────────────────────────────────────────────────
APP_NAME="WatchFlower"
APP_VERSION="6.0"
GIT_VERSION=$(git rev-parse --short HEAD)

echo ""
echo "================================================================"
echo "  $APP_NAME Windows Packager (x86_64) [v$APP_VERSION (git:$GIT_VERSION)]"
echo "================================================================"
echo ""

#─────────────────────────────────────────────────────────────────────────────
# 2) ARG PARSING
#─────────────────────────────────────────────────────────────────────────────
upload_package=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--upload)
      upload_package=true
      shift
      ;;
    *)
      echo "Unknown argument \"$1\""
      echo ""
      echo "Usage: $0 [-u|--upload]"
      exit 1
      ;;
  esac
done

#─────────────────────────────────────────────────────────────────────────────
# 3) ENSURE assets/windows/WatchFlower.rc EXISTS
#─────────────────────────────────────────────────────────────────────────────
# The upstream CMakeLists always tries to compile "assets/windows/WatchFlower.rc".
# If it’s missing, CMake Generate will fail with "Cannot find source file".
if [ ! -d assets/windows ]; then
  mkdir -p assets/windows
fi

if [ ! -f assets/windows/WatchFlower.rc ]; then
  echo "---- Creating dummy assets/windows/WatchFlower.rc"
  cat > assets/windows/WatchFlower.rc << 'EOF'
// Dummy resource file so that CMake’s “qt_add_executable(… assets/windows/WatchFlower.rc )” 
// line doesn’t break on CI. No real icons or version‐info here.
#include <windows.h>
1 VERSIONINFO
FILEVERSION 1,0,0,0
PRODUCTVERSION 1,0,0,0
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "040904B0"
    BEGIN
      VALUE "FileDescription", "WatchFlower\0"
      VALUE "FileVersion", "1.0.0.0\0"
      VALUE "ProductVersion", "1.0.0.0\0"
      VALUE "CompanyName", "Emeric Grange\0"
      VALUE "ProductName", "WatchFlower\0"
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x0409, 1200
  END
END
EOF
fi

#─────────────────────────────────────────────────────────────────────────────
# 4) CLEAN & SET UP BUILD DIR
#─────────────────────────────────────────────────────────────────────────────
echo "---- Removing previous build/ (if any)"
rm -rf build
mkdir build
pushd build > /dev/null

#─────────────────────────────────────────────────────────────────────────────
# 5) CMAKE CONFIGURE & BUILD
#─────────────────────────────────────────────────────────────────────────────
echo "---- Configuring CMake in Release mode (x64)"
cmake -G "Visual Studio 17 2022" -A x64 -DCMAKE_BUILD_TYPE=Release ..

echo "---- Building WatchFlower (Release)"
cmake --build . --config Release

# After this, you should have:
#   build/Release/WatchFlower.exe
popd > /dev/null

#─────────────────────────────────────────────────────────────────────────────
# 6) PREPARE “deploy_staging/” AND RUN WINDEPLOYQT
#─────────────────────────────────────────────────────────────────────────────
echo "---- Preparing deploy_staging/"
rm -rf deploy_staging
mkdir deploy_staging

# Copy the built EXE
cp build/Release/WatchFlower.exe deploy_staging/

echo "---- Running windeployqt on deploy_staging/WatchFlower.exe"
# The --qmldir must point to the QML folder relative to where the EXE lives:
windeployqt deploy_staging/WatchFlower.exe --qmldir ../qml

#─────────────────────────────────────────────────────────────────────────────
# 7) COPY QML & OTHER ASSETS
#─────────────────────────────────────────────────────────────────────────────
echo "---- Copying qml/ into deploy_staging/"
cp -r qml deploy_staging/

# If you ship icons, translations, or other assets, add lines like:
# cp -r assets/images deploy_staging/
# cp -r i18n deploy_staging/

#───────────────
