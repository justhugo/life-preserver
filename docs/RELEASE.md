# Release status

Life Preserver 1.3.0 runs on macOS, iPhone, and iPad. Each device polls provider APIs directly, using app-owned sign-ins shared securely through iCloud.

## Changes in 1.3.0

- The Mac Accounts screen has a bordered Reconnect button with hover feedback and keyboard focus.
- Interrupted sign-in renewal can name the device that started it. An optional alert reminds you when that device has a renewed sign-in waiting to sync.
- Meters show `<1%` for a positive remainder below 1%. At a confirmed 0%, the expanded Grok and Grok Bot cards show extra-usage details, including available monthly spending room when reported, and a billing link.

## Included

- OpenAI, Claude, Grok, and Grok Bot subscription usage, reset times, plan names, and additional limits.
- Native provider cards with expandable details, stale-reading indicators, and connection errors.
- System, Light, and Dark appearance settings on each platform.
- Encrypted private CloudKit sessions, iCloud Keychain encryption keys, coordinated token renewal, and protected offline usage caches.
- MIT-licensed source and original artwork, bundled provider icon notices, and build/signing instructions.

## Validation

GitHub's automated workflow checks the core and sync tests, Mac and iOS simulator builds, app metadata, and bundled notices. The build and signing guide describes how to verify live provider requests on signed development builds.

## Source downloads

A GitHub source release contains the versioned repository in ZIP and tar.gz formats. Build and install using [BUILDING.md](BUILDING.md), then follow [mobile setup](MOBILE.md). App binaries are not attached to source releases.

## Ready-to-install distribution

The development builds use Apple development signing and CloudKit Development. Public installers or App Store/TestFlight distribution require:

1. Appropriate provider OAuth registration or another authorized arrangement for the consumer usage interfaces described in [PROVIDERS.md](PROVIDERS.md).
2. Developer ID signing and notarization for direct Mac downloads, or App Store signing and platform review.
3. Validation of sandboxed networking, browser callbacks, shared Keychain entitlements, and CloudKit Production schema/environment.
4. Distribution privacy metadata, a support contact, and an update strategy.
5. Broader accessibility, account-switching, interrupted-renewal, offline, and long-running reliability validation.

Personal signing overrides remain in the ignored local configuration. The repository includes a privacy manifest for UserDefaults access and license notices bundled with both apps.

Deploy the optional `leaseOrigin` Bytes field on the `ProviderSessionV1` record type to CloudKit Production before distributing builds that record renewal device labels.
