# Build and signing setup

Life Preserver's Mac app requires macOS 15.6 or later. The iPhone/iPad companion
requires iOS/iPadOS 18 or later. Use Xcode with Swift 6 support and the relevant
platform SDKs. The repository has no third-party runtime dependencies.

## Local Mac app and tests

```sh
bash scripts/build.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The Mac script creates an Apple Silicon app and ZIP under `build/Release` using
ad-hoc local signing. This local build does not enable iCloud publishing. Neither
these tests nor the local Mac build require an Apple Developer Program membership.

The installed Mac app's minimum version is already 15.6 in both its Info.plist and
target deployment settings. The earlier README claim of macOS 14 support was
incorrect. The core Swift package's macOS 15 minimum is for its libraries/tests;
it does not lower the bundled Mac app's 15.6 requirement.

## Personal signing configuration

Copy `Resources/Local.xcconfig.example` to `Resources/Local.xcconfig`, then set:

| Setting | Value |
| --- | --- |
| `LP_DEVELOPMENT_TEAM` | Your Apple developer team ID |
| `LP_MAC_BUNDLE_IDENTIFIER` | Your unique Mac app identifier |
| `LP_MOBILE_BUNDLE_IDENTIFIER` | Your unique iPhone/iPad app identifier |
| `LP_CLOUD_CONTAINER_IDENTIFIER` | One iCloud container shared by both apps |

The shared `Resources/Signing.xcconfig` supplies public example defaults and loads
that optional local file. Each Xcode project uses those values. The local file is
ignored by Git and is not copied into the app bundle. Do not commit certificates,
private keys, provisioning profiles, or account credentials.

For an existing installation, keep its original app identifiers and iCloud
container in your local file to retain its preferences and access to its existing
shared readings. A developer cloning the repository should use their own unique
identifiers and container, rather than the public example defaults.

## iCloud-enabled Mac and device builds

Sign in to your Apple developer account in Xcode Settings, configure the local
file, and run:

```sh
bash scripts/build-cloud.sh
bash scripts/build-mobile.sh device
```

Xcode automatic provisioning creates or associates your app IDs, iCloud
capabilities, and signing profiles. Both apps must use the same iCloud container
and environment. The current personal builds use the Development environment.
Follow [mobile setup](MOBILE.md) for device installation and sharing.

## Simulator preview

```sh
bash scripts/build-mobile.sh
```

Install the simulator product and launch with `--preview` for clearly labelled
sample readings. Add `--show-settings` to inspect Settings directly. Simulator
builds are unsigned, so use the preview for interface checks.

## Public distribution

Publishing this source does not produce an App Store or notarized binary release.
Review the provider compatibility interfaces, helper architecture, signing,
CloudKit Production schema/environment, privacy metadata, and distribution steps
in [release status](RELEASE.md) before shipping binaries to other users.
