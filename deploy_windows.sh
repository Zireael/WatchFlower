#!/usr/bin/env bash
set -euo pipefail

# must be run from the repo root
# generate Visual Studio makefiles
qmake -r \
  "CONFIG+=release" \
  -spec win32-msvc \
  "INCLUDEPATH+=$PWD/3rdparty/json/include" \
  WATCHFLOWER.pro

# build with MSVC’s nmake
nmake
