#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
python3 scripts/sync-project.py
xcodebuild -project LifePreserver.xcodeproj -scheme LifePreserver \
  -configuration Release -derivedDataPath build/DerivedData \
  -destination 'generic/platform=macOS' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO -quiet build
mkdir -p build/Release
ditto 'build/DerivedData/Build/Products/Release/Life Preserver.app' 'build/Release/Life Preserver.app'
codesign --verify --deep --strict 'build/Release/Life Preserver.app'
ditto -c -k --sequesterRsrc --keepParent 'build/Release/Life Preserver.app' 'build/Release/Life Preserver.zip'
echo 'Ready: build/Release/Life Preserver.app'
