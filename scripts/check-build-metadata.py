#!/usr/bin/env python3
"""Check built app metadata without reading credentials or calling services."""
from pathlib import Path
import plistlib
import sys

if len(sys.argv) != 3:
    raise SystemExit("Usage: check-build-metadata.py MAC_APP MOBILE_APP")

for platform, supplied_path in zip(("Mac", "Mobile"), sys.argv[1:]):
    app = Path(supplied_path)
    plist = app / ("Contents/Info.plist" if platform == "Mac" else "Info.plist")
    info = plistlib.loads(plist.read_bytes())
    for key in ("CFBundleIdentifier", "LifePreserverCloudContainerIdentifier"):
        value = info.get(key)
        if not isinstance(value, str) or not value or "$(" in value:
            raise SystemExit(f"{platform} build has missing/unexpanded {key}")
    if not info["LifePreserverCloudContainerIdentifier"].startswith("iCloud."):
        raise SystemExit(f"{platform} build has an invalid iCloud container")
    notice = app / ("Contents/Resources/Assets/ThirdPartyNotices.txt" if platform == "Mac" else "ThirdPartyNotices.txt")
    text = notice.read_text()
    if "Hugues de Saint Salvy" not in text or "LobeHub" not in text:
        raise SystemExit(f"{platform} build is missing a copyright/license notice")
    print(f"{platform} app metadata and bundled license notices verified.")
