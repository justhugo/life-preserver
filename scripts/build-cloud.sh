#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
python3 scripts/sync-project.py
xcodebuild -project LifePreserver.xcodeproj -scheme LifePreserver \
  -xcconfig Resources/MacCloud.xcconfig -configuration Debug \
  -derivedDataPath build/CloudDerivedData -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration -quiet build
mkdir -p build/Cloud
ditto 'build/CloudDerivedData/Build/Products/Debug/Life Preserver.app' 'build/Cloud/Life Preserver.app'
codesign --verify --deep --strict 'build/Cloud/Life Preserver.app'
echo 'Ready: build/Cloud/Life Preserver.app'
