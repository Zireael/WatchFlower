#!/usr/bin/env bash
set -e

###############################################################################
#  deploy_windows.sh
#
#  1) Injects a dummy assets/windows/WatchFlower.rc (if missing), exactly
#     alongside CMakeLists.txt.
#  2) Creates an out‐of‐source “build/” folder at the same level as CMakeLists.
#  3) Configures + builds in Release (x64), letting CMake place WatchFlower.exe 
#     into ${PROJECT_SOURCE_DIR}/bin/ (as defined in CMakeLists).
#  4) Runs windeployqt on that bin/WatchFlower.exe.
#  5) Copies qml/ (and any other missing runtime assets) next to the EXE.
#  6) Renames “deploy_staging/” → “WatchFlower/” and zips with native Windows tar.
#  7) Optionally builds an NSIS installer if makensis is on PATH.
#  8) Optionally uploads ZIP/EXE to transfer.sh if “-u|--upload” is passed.
#
#  Usage:
#    # from the directory that contains CMakeLists.txt:
#    ./deploy_windows.sh [-u|--upload]
#
###############################################################################

APP_NAME="WatchFlower"
APP_VERSION="6.0"
GIT_VERSION=$(git rev-parse --short HEAD)

echo ""
echo "=============================================================="
echo "  $APP_NAME Windows Packager (x86_64) [v$APP_VERSION (git:$GIT_VERSION)]"
echo "=============================================================="
echo ""

#─────────────────────────────────────────────────────────────────────────────
# 1) PARSE ARGS
#─────────────────────────────────────────────────────────────────────────────
upload_package=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--upload)
      upload_package=true
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo ""
      echo "Usage: $0 [-u|--upload]"
      exit 1
      ;;
  esac
done

#─────────────────────────────────────────────────────────────────────────────
# 2) INJECT dummy assets/windows/WatchFlower.rc if MISSING
#─────────────────────────────────────────────────────────────────────────────
# We assume this script is being run from the same directory as CMakeLists.txt.

if [ ! -d assets/windows ]; then
  mkdir -p assets/windows
fi

if [ ! -f assets/windows/WatchFlower.rc ]; then
  echo "---- Creating dummy assets/windows/WatchFlower.rc"
  cat > assets/windows/WatchFlower.rc << 'EOF'
// Dummy resource stub so that CMake’s 
// “qt_add_executable(… assets/windows/WatchFlower.rc …)” line doesn’t fail
#include <windows.h>
1 VERSIONINFO
FILEVERSION     1,0,0,0
PRODUCTVERSION  1,0,0,0
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
# 3) CREATE / CLEAN build/ DIRECTORY
#─────────────────────────────────────────────────────────────────────────────
if [ -d build ]; then
  echo "---- Removing old build/"
  rm -rf build
fi
mkdir build
pushd build > /dev/null

#─────────────────────────────────────────────────────────────────────────────
# 4) CONFIGURE + BUILD via CMake
#─────────────────────────────────────────────────────────────────────────────
echo "---- Configuring CMake (Release x64)"
cmake -G "Visual Studio 17 2022" -A x64 -DCMAKE_BUILD_TYPE=Release ..

echo "---- Building WatchFlower (Release)"
cmake --build . --config Release

popd > /dev/null

#─────────────────────────────────────────────────────────────────────────────
# 5) LOCATE the newly built EXE
#─────────────────────────────────────────────────────────────────────────────
# According to the project’s CMakeLists, the runtime‐output is:
#   ${PROJECT_SOURCE_DIR}/bin/WatchFlower.exe
#
EXE_PATH="bin/WatchFlower.exe"
if [ ! -f "$EXE_PATH" ]; then
  echo "ERROR: Expected to find '$EXE_PATH' after build, but it does not exist."
  exit 1
fi

#─────────────────────────────────────────────────────────────────────────────
# 6) PREPARE deploy_staging/ AND copy EXE
#─────────────────────────────────────────────────────────────────────────────
echo "---- Preparing deploy_staging/"
rm -rf deploy_staging
mkdir deploy_staging

echo "---- Copying WatchFlower.exe → deploy_staging/"
cp "$EXE_PATH" deploy_staging/

#─────────────────────────────────────────────────────────────────────────────
# 7) RUN WINDEPLOYQT on that EXE
#─────────────────────────────────────────────────────────────────────────────
echo "---- Running windeployqt on deploy_staging/WatchFlower.exe"
# Point --qmldir at ../qml so windeployqt can find your QML imports.
windeployqt deploy_staging/WatchFlower.exe --qmldir ../qml

#─────────────────────────────────────────────────────────────────────────────
# 8) COPY QML (and any other assets) into deploy_staging/
#─────────────────────────────────────────────────────────────────────────────
echo "---- Copying qml/ into deploy_staging/"
cp -r qml deploy_staging/

# If you also need icons, translations, etc., do the same here:
#   cp -r i18n deploy_staging/
#   cp -r assets/images deploy_staging/

#─────────────────────────────────────────────────────────────────────────────
# 9) RENAME deploy_staging → final “WatchFlower/”
#─────────────────────────────────────────────────────────────────────────────
echo "---- Preparing final \"$APP_NAME/\" folder"
rm -rf "$APP_NAME"
mv deploy_staging "$APP_NAME"

#─────────────────────────────────────────────────────────────────────────────
# 10) ZIP using native Windows tar (built into Win10+)
#─────────────────────────────────────────────────────────────────────────────
ZIP_NAME="$APP_NAME-$APP_VERSION-win64.zip"
echo "---- Creating ZIP → $ZIP_NAME"
rm -f "$ZIP_NAME"
tar -a -c -f "$ZIP_NAME" "$APP_NAME"

#─────────────────────────────────────────────────────────────────────────────
# 11) OPTIONAL: NSIS installer (if makensis is on PATH)
#─────────────────────────────────────────────────────────────────────────────
if command -v makensis > /dev/null 2>&1; then
  echo "---- Building NSIS installer"
  # The NSIS script (assets/windows/setup.nsi) expects to find “WatchFlower/”
  # under assets/windows/, so we temporarily move it there:
  rm -rf assets/windows/"$APP_NAME"
  mkdir -p assets/windows
  mv "$APP_NAME" assets/windows/"$APP_NAME"

  makensis assets/windows/setup.nsi

  # NSIS normally emits something like “WatchFlower-6.0-win64.exe” in cwd
  if ls assets/windows/*.exe 1> /dev/null 2>&1; then
    mv assets/windows/*.exe "$APP_NAME-$APP_VERSION-win64-installer.exe"
  fi

  # Move the folder back so the repo root isn’t “broken”
  mv assets/windows/"$APP_NAME" "$APP_NAME"
else
  echo "---- Skipping NSIS (makensis not found)"
fi

#─────────────────────────────────────────────────────────────────────────────
# 12) OPTIONAL: UPLOAD to transfer.sh (if requested)
#─────────────────────────────────────────────────────────────────────────────
if [[ "$upload_package" == true ]]; then
  echo "---- Uploading ZIP to transfer.sh"
  curl --upload-file "$ZIP_NAME" \
       "https://transfer.sh/$ZIP_NAME-git$GIT_VERSION.zip"
  echo ""
  if [[ -f "$APP_NAME-$APP_VERSION-win64-installer.exe" ]]; then
    echo "---- Uploading EXE installer to transfer.sh"
    curl --upload-file "$APP_NAME-$APP_VERSION-win64-installer.exe" \
         "https://transfer.sh/$APP_NAME-$APP_VERSION-win64-installer-git$GIT_VERSION.exe"
    echo ""
  fi
fi

echo ""
echo "=============================================================="
echo "  Windows package completed."
echo "  • ZIP  → $ZIP_NAME"
if [[ -f "$APP_NAME-$APP_VERSION-win64-installer.exe" ]]; then
  echo "  • EXE  → $APP_NAME-$APP_VERSION-win64-installer.exe"
fi
if [[ "$upload_package" == true ]]; then
  echo "  (Artifacts uploaded to transfer.sh)"
fi
echo "=============================================================="
echo ""
