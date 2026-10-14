# Build and signing setup

Use Xcode with Swift 6 support and the macOS/iOS SDKs. Life Preserver requires Apple Silicon and macOS 15.6 or later on Mac, and iOS/iPadOS 18 or later on mobile. The repository has no third-party runtime dependencies.

## Local Mac app and tests

```sh
bash scripts/build.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The build script creates an Apple Silicon app and ZIP in `build/Release` using ad-hoc signing. The local Mac build and tests require no Apple developer account. Use the signed builds below for iCloud credential sharing and mobile installation.

The core Swift package targets macOS 15 for libraries and tests; the bundled Mac app requires macOS 15.6.

## Signing configuration

Copy `Resources/Local.xcconfig.example` to `Resources/Local.xcconfig`, then configure:

| Setting | Value |
| --- | --- |
| `LP_DEVELOPMENT_TEAM` | Your Apple developer team ID |
| `LP_MAC_BUNDLE_IDENTIFIER` | Your unique Mac app identifier |
| `LP_MOBILE_BUNDLE_IDENTIFIER` | Your unique mobile app identifier |
| `LP_CLOUD_CONTAINER_IDENTIFIER` | An iCloud container shared by both apps |
| `LP_SHARED_KEYCHAIN_GROUP` | A shared Keychain group; defaults to the Mac bundle identifier plus `.sessions` |

`Resources/Signing.xcconfig` loads the optional local file. Local signing settings are ignored by Git and are not copied into the app bundle. Keep app identifiers, the iCloud container, and the Keychain group consistent across your installations. Each developer should use their own identifiers and container.

Both signed apps must have the same expanded Keychain group in their `keychain-access-groups` entitlement and `LifePreserverKeychainAccessGroup` metadata. Apple supplies the app identifier prefix.

Do not commit certificates, private keys, provisioning profiles, credentials, or your local signing configuration.

## Signed Mac and device apps

Sign in to your Apple developer account in Xcode Settings, configure the local file, and run:

```sh
bash scripts/build-cloud.sh
bash scripts/build-mobile.sh device
```

Xcode automatic provisioning configures the app IDs, capabilities, and signing profiles. Both apps must use the same iCloud container, environment, and Keychain access group. Development builds use CloudKit Development.

The signed Mac product is `build/Cloud/Life Preserver.app`. The mobile device product is `build/MobileDeviceDerivedData/Build/Products/Debug-iphoneos/Life Preserver Mobile.app`. Install with Xcode on your registered devices, then follow [mobile setup](MOBILE.md).

## Simulator preview

```sh
bash scripts/build-mobile.sh
```

Install the product from `build/MobileDerivedData/Build/Products/Debug-iphonesimulator` in an iOS simulator. Launch with `--preview` for sample readings and `--show-settings` to inspect Settings. Simulator builds are unsigned; use preview mode for interface checks.

## Source and build validation

`scripts/sync-project.py` adds source/resource references without replacing signing or build settings. The GitHub workflow runs core/sync tests, builds the local Mac and mobile simulator apps, and checks app metadata and bundled license notices.

```sh
python3 scripts/check-build-metadata.py \
  'build/Release/Life Preserver.app' \
  'build/MobileDerivedData/Build/Products/Debug-iphonesimulator/Life Preserver Mobile.app'
```

For signed builds, also verify matching Keychain entitlements and app metadata, and test live provider requests on each device.

## Distribution

GitHub releases provide versioned source downloads. Ready-to-install distribution requires appropriate signing, provider authorization, CloudKit Production deployment, and platform release preparation. See [RELEASE.md](RELEASE.md).
