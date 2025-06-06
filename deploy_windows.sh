#!/usr/bin/env bash
set -e

###############################################################################
#  deploy_windows.sh
#
#  This script does the following on a clean Windows CI runner:
#   1) Configures CMake in Release mode (x64).
#   2) Builds WatchFlower with MSVC 64-bit.
#   3) Runs windeployqt on the new WatchFlower.exe.
#   4) Collects the EXE + Qt runtime + QML files into a single WatchFlower/ folder.
#   5) Creates WatchFlower-<version>-win64.zip using Windows tar (built-in).
#   6) Optionally runs makensis if you want an NSIS installer.
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
# 1) APPLICATION METADATA
#─────────────────────────────────────────────────────────────────────────────
export APP_NAME="WatchFlower"
export APP_VERSION="6.0"
export GIT_VERSION=$(git rev-parse --short HEAD)

echo ""
echo "=============================================================="
echo "  $APP_NAME Windows Packager (x86_64) [v$APP_VERSION (git:$GIT_VERSION)]"
echo "=============================================================="
echo ""

#─────────────────────────────────────────────────────────────────────────────
# 2) ARGUMENT PARSING
#─────────────────────────────────────────────────────────────────────────────
upload_package=false

while [[ $# -gt 0 ]]; do
  case $1 in
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
# 3) CLEAN & PREPARE BUILD DIRECTORY
#─────────────────────────────────────────────────────────────────────────────
echo "---- Cleaning previous build (if any)"
if [ -d build ]; then
  rm -rf build
fi
mkdir build
pushd build > /dev/null

#─────────────────────────────────────────────────────────────────────────────
# 4) RUN CMAKE CONFIGURE & BUILD
#─────────────────────────────────────────────────────────────────────────────
echo "---- Configuring CMake in Release mode (x64)"
cmake -G "Visual Studio 17 2022" -A x64 -DCMAKE_BUILD_TYPE=Release ..

echo "---- Building WatchFlower (Release)"
cmake --build . --config Release

# After this, the built EXE should be in:
#   build/Release/WatchFlower.exe

#─────────────────────────────────────────────────────────────────────────────
# 5) RUN WINDEPLOYQT on the EXE
#─────────────────────────────────────────────────────────────────────────────
echo "---- Copying built EXE to a staging folder"
# Create a "deploy_staging" where we will collect everything
popd > /dev/null   # exit out of build/
mkdir -p deploy_staging
cp build/Release/WatchFlower.exe deploy_staging/

# Now run windeployqt on that single EXE file.  By default it will copy
# all required Qt DLLs (platforms, plugins, etc.) into deploy_staging/.
echo "---- Running windeployqt on deploy_staging/WatchFlower.exe"
windeployqt deploy_staging/WatchFlower.exe --qmldir ../qml

#─────────────────────────────────────────────────────────────────────────────
# 6) COLLECT QML + OTHER ASSETS
#─────────────────────────────────────────────────────────────────────────────
echo "---- Copying QML folder (and any other resources) into deploy_staging"
# The qml/ directory (from repo root) must be next to the EXE
cp -r qml deploy_staging/

# If you have any other folders (icons, translations, etc.) that WatchFlower
# expects at runtime, copy them here.  For example, if you ship i18n/ or assets/,
# do:
#   cp -r i18n deploy_staging/
#   cp -r assets deploy_staging/

#─────────────────────────────────────────────────────────────────────────────
# 7) MOVE staging → final “WatchFlower/” folder
#─────────────────────────────────────────────────────────────────────────────
echo "---- Preparing final folder \"$APP_NAME/\""
if [ -d "$APP_NAME" ]; then
  rm -rf "$APP_NAME"
fi
mv deploy_staging "$APP_NAME"

#─────────────────────────────────────────────────────────────────────────────
# 8) CREATE A ZIP USING WINDOWS ’tar’ (native since Win10)
#─────────────────────────────────────────────────────────────────────────────
echo "---- Creating ZIP: $APP_NAME-$APP_VERSION-win64.zip"
rm -f "$APP_NAME-$APP_VERSION-win64.zip"
# Windows’ built-in “tar.exe” can do zip with “-a -c”
tar -a -c -f "$APP_NAME-$APP_VERSION-win64.zip" "$APP_NAME"

#─────────────────────────────────────────────────────────────────────────────
# 9) OPTIONAL: RUN NSIS TO PRODUCE A .exe INSTALLER
#─────────────────────────────────────────────────────────────────────────────
if command -v makensis > /dev/null 2>&1; then
  echo "---- Running NSIS to build installer"
  # NSIS script expects the compiled files to be at assets/windows/WatchFlower/
  # so we move/overwrite that folder temporarily:
  if [ -d assets/windows/$APP_NAME ]; then
    rm -rf assets/windows/$APP_NAME
  fi
  mkdir -p assets/windows
  mv "$APP_NAME" assets/windows/$APP_NAME

  # Generate the installer
  makensis assets/windows/setup.nsi

  # After this, NSIS typically emits something like WatchFlower-6.0-win64.exe
  # in the current directory (root).
  # Let’s rename/move it so we end up with a consistent filename:
  mv assets/windows/*.exe "$APP_NAME-$APP_VERSION-win64-installer.exe"

  # Move the folder back so that the repository is not left in a “broken” state
  mv assets/windows/$APP_NAME "$APP_NAME"
else
  echo "---- Skipping NSIS (makensis not found)"
fi

#─────────────────────────────────────────────────────────────────────────────
# 10) OPTIONAL: UPLOAD via transfer.sh (if requested)
#─────────────────────────────────────────────────────────────────────────────
if [[ "$upload_package" = true ]]; then
  echo "---- Uploading ZIP to transfer.sh"
  curl --upload-file "$APP_NAME-$APP_VERSION-win64.zip" \
       "https://transfer.sh/$APP_NAME-$APP_VERSION-git$GIT_VERSION-win64.zip"
  echo ""
  if [ -f "$APP_NAME-$APP_VERSION-win64-installer.exe" ]; then
    echo "---- Uploading EXE Installer to transfer.sh"
    curl --upload-file "$APP_NAME-$APP_VERSION-win64-installer.exe" \
         "https://transfer.sh/$APP_NAME-$APP_VERSION-git$GIT_VERSION-win64-installer.exe"
    echo ""
  fi
fi

echo ""
echo "=============================================================="
echo "  Windows package completed."
echo "  • ZIP  → $APP_NAME-$APP_VERSION-win64.zip"
if [ -f "$APP_NAME-$APP_VERSION-win64-installer.exe" ]; then
  echo "  • EXE  → $APP_NAME-$APP_VERSION-win64-installer.exe"
fi
if [[ "$upload_package" = true ]]; then
  echo "  (Artifacts have also been uploaded to transfer.sh)"
fi
echo "=============================================================="
echo ""
