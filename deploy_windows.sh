#!/bin/bash

## This script is meant to be used with GitHub Actions
## https://github.com/Zireael/WatchFlower/actions
## It should probably run on Windows...

echo "> deploy_windows.sh"

## CHECKS ######################################################################

if [ ${#} -eq 0 ] ; then
    echo "No argument supplied!"
    echo "You need to specify a build type: RelWithDebInfo, Release, Debug"
    exit 1
fi

BUILD_TYPE=$1
echo "- BUILD_TYPE: ${BUILD_TYPE}"

## SETTINGS ####################################################################

export APP_NAME="WatchFlower"
export APP_VERSION="1.0.0"
export QT_DIR="D:/a/WatchFlower/Qt/6.7.3/msvc2019_64"

## DEPLOY ######################################################################

echo '---- Running windeployqt'
cd build/
ls -la

# Basic deployment
${QT_DIR}/bin/windeployqt.exe --qmldir ../qml/ --compiler-runtime WatchFlower.exe

echo '---- Deployment content'
ls -la

## CREATE ARCHIVE ##############################################################

echo '---- Creating archive'
7z a ${APP_NAME}_${APP_VERSION}_win64.zip *

echo '---- Archive created'
ls -la *.zip

## UPLOAD ARTIFACT #############################################################

echo '---- Upload to transfer.sh'
curl --upload-file ${APP_NAME}_${APP_VERSION}_win64.zip https://transfer.sh/${APP_NAME}_${APP_VERSION}_win64.zip

echo ""
echo "> deploy_windows.sh DONE"
