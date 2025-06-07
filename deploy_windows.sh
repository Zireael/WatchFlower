#!/usr/bin/env bash
set -euo pipefail

# must be run from repo root
qmake -r "CONFIG+=release" -spec win32-msvc \
  "INCLUDEPATH+=$PWD/3rdparty/json/include" WATCHFLOWER.pro

# use the appropriate make tool; on GitHub’s Windows-hosted runners this will pick up nmake
# but if you prefer mingw, you can switch to mingw32-make here.
nmake
