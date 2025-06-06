#!/usr/bin/env bash
set -e

###############################################################################
# deploy_windows.sh
#
#  1) Creates a dummy assets/windows/WatchFlower.rc if it’s missing,
#     so that “qt_add_executable(… assets/windows/WatchFlower.rc …)” never fails.
#  2) Runs an out-of-source CMake (Release x64) in build/ → builds WatchFlower.exe.
#  3) Copies the fresh EXE → deploy_staging/, runs windeployqt on it,
#     then bundles qml/ (and other assets) next to the EXE.
#  4) Renames “deploy_staging/” → “WatchFlower/” and zips with Windows tar.
#  5) (Optional) Builds an NSIS installer if makensis is on PATH.
#  6) (Optional) Uploads ZIP & EXE to transfer.sh (if -u/--upload is given).
#
# Usage:
#   # Must be run from the same folder as CMakeLists.txt:
#   ./deploy_windows.sh [-u|--upload]
#
###############################################################################

APP_NAME="WatchFlower"
APP_VERSION="6.0"
GIT_VERSION=$(git rev-parse --short HEAD)

echo ""
echo "=========================================================="
echo "  $APP_NAME Packager (Windows x64) [v$APP_VERSION | git $GIT_VERSION]"
echo "=========================================================="
echo ""

#─────────────────────────────────────────────────────────────────────────────
# 1) PARSE ARGS
#─────────────────────────────────────────────────────────────────────────────
upload_package=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--upload) upload_package=true; shift ;;
    *) 
      echo "Unknown argument: $1"
      echo "Usage: $0 [-u|--upload]"
      exit 1
      ;;
  esac
done

#─────────────────────────────────────────────────────────────────────────────
# 2) INJECT dummy assets/windows/WatchFlower.rc IF MISSING
#─────────────────────────────────────────────────────────────────────────────
# We assume this script is executed from the same directory that holds CMakeLists.txt.

if [ ! -d assets/windows ]; then
  mkdir -p assets/windows
fi

if [ ! -f assets/windows/WatchFlower.rc ]; then
  echo "---- Creating dummy assets/windows/WatchFlower.rc"
  cat > assets/windows/WatchFlower.rc << 'EOF'
// Dummy .rc so that CMake’s “qt_add_executable(… assets/windows/WatchFlower.rc …)”
// never errors if no real resource file is present.
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
# 3) CLEAN & CREATE build/ DIRECTORY
#─────────────────────────────────────────────────────────────────────────────
if [ -d build ]; then
  echo "---- Removing old build/"
  rm -rf build
fi
mkdir build
pushd build > /dev/null

#─────────────────────────────────────────────────────────────────────────────
# 4) CONFIGURE + BUILD (Release, x64)
#─────────────────────────────────────────────────────────────────────────────
echo "---- Configuring CMake (Release x64)"
cmake -G "Visual Studio 17 2022" -A x64 -DCMAKE_BUILD_TYPE=Release ..

echo "---- Building WatchFlower (Release)"
cmake --build . --config Release

popd > /dev/null

#─────────────────────────────────────────────────────────────────────────────
# 5) LOCATE the BUILT EXE
#─────────────────────────────────────────────────────────────────────────────
# According to this repo’s CMakeLists.txt, the EXE ends up in:
#   <PROJECT_SOURCE_DIR>/bin/WatchFlower.exe

EXE_PATH="bin/WatchFlower.exe"
if [ ! -f "$EXE_PATH" ]; then
  echo "ERROR: '$EXE_PATH' not found after build."
  exit 1
fi

#─────────────────────────────────────────────────────────────────────────────
# 6) PREPARE deploy_staging/ & COPY EXE
#─────────────────────────────────────────────────────────────────────────────
echo "---- Preparing deploy_staging/"
rm -rf deploy_staging
mkdir deploy_staging

echo "---- Copying WatchFlower.exe → deploy_staging/"
cp "$EXE_PATH" deploy_staging/

#─────────────────────────────────────────────────────────────────────────────
# 7) RUN WINDEPLOYQT on the EXE
#─────────────────────────────────────────────────────────────────────────────
echo "---- Running windeployqt on deploy_staging/WatchFlower.exe"
# --qmldir should point at your repo’s qml/ folder (one level up).
windeployqt deploy_staging/WatchFlower.exe --qmldir ../qml

#─────────────────────────────────────────────────────────────────────────────
# 8) COPY QML + ANY OTHER RUNTIME ASSETS
#─────────────────────────────────────────────────────────────────────────────
echo "---- Copying qml/ into deploy_staging/"
cp -r qml deploy_staging/

# If you have icons, translations, etc. under, say, assets/icons or i18n/,
# copy those folders as well. Example:
#   cp -r assets/images deploy_staging/
#   cp -r i18n deploy_staging/

#─────────────────────────────────────────────────────────────────────────────
# 9) RENAME deploy_staging/ → final “WatchFlower/” folder
#─────────────────────────────────────────────────────────────────────────────
echo "---- Renaming deploy_staging → $APP_NAME/"
rm -rf "$APP_NAME"
mv deploy_staging "$APP_NAME"

#─────────────────────────────────────────────────────────────────────────────
# 10) CREATE ZIP via native Windows tar (no 7z needed)
#─────────────────────────────────────────────────────────────────────────────
ZIP_NAME="$APP_NAME-$APP_VERSION-win64.zip"
echo "---- Creating ZIP → $ZIP_NAME"
rm -f "$ZIP_NAME"
tar -a -c -f "$ZIP_NAME" "$APP_NAME"

#─────────────────────────────────────────────────────────────────────────────
# 11) (Optional) CREATE NSIS installer if makensis is on PATH
#─────────────────────────────────────────────────────────────────────────────
if command -v makensis > /dev/null 2>&1; then
  echo "---- Building NSIS installer"
  # NSIS script (assets/windows/setup.nsi) expects to find WatchFlower/ under assets/windows/
  rm -rf assets/windows/"$APP_NAME"
  mkdir -p assets/windows
  mv "$APP_NAME" assets/windows/"$APP_NAME"

  makensis assets/windows/setup.nsi

  # NSIS will drop something like “WatchFlower-6.0-win64.exe” in cwd:
  if ls assets/windows/*.exe 1> /dev/null 2>&1; then
    mv assets/windows/*.exe "$APP_NAME-$APP_VERSION-win64-installer.exe"
  fi

  # Restore the WatchFlower/ folder so the repo root stays clean
  mv assets/windows/"$APP_NAME" "$APP_NAME"
else
  echo "---- Skipping NSIS (makensis not found)"
fi

#─────────────────────────────────────────────────────────────────────────────
# 12) (Optional) UPLOAD ZIP & EXE to transfer.sh
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
echo "=========================================================="
echo "  Package complete!"
echo "    • ZIP     → $ZIP_NAME"
if [[ -f "$APP_NAME-$APP_VERSION-win64-installer.exe" ]]; then
  echo "    • Installer → $APP_NAME-$APP_VERSION-win64-installer.exe"
fi
if [[ "$upload_package" == true ]]; then
  echo "    (Artifacts uploaded to transfer.sh)"
fi
echo "=========================================================="
echo ""
