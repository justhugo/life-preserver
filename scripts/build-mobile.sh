#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ "${1:-simulator}" == "device" ]]; then
  xcodebuild -project Mobile/LifePreserverMobile.xcodeproj -scheme LifePreserverMobile \
    -configuration Debug -destination 'generic/platform=iOS' \
    -derivedDataPath build/MobileDeviceDerivedData -allowProvisioningUpdates -quiet build
else
  xcodebuild -project Mobile/LifePreserverMobile.xcodeproj -scheme LifePreserverMobile \
    -configuration Debug -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath build/MobileDerivedData CODE_SIGNING_ALLOWED=NO -quiet build
fi
