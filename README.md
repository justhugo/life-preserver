# Life Preserver 🛟

A native macOS menu bar app for remaining AI subscription usage, with an iPhone and iPad companion.

This repository contains a personal development build. Provider integrations use the compatibility interfaces described below; each device now checks provider APIs directly, using optionally shared encrypted sign-ins.

## Run

Build the app using the instructions below, then open **build/Release/Life Preserver.app**, or copy it to Applications. The Mac app requires **macOS 15.6 or later**; the mobile companion requires **iOS/iPadOS 18 or later**. The personal development builds are not notarized or App Store releases.

Connect providers in **Settings → Accounts**. Browser sign-in and consent stay with the provider. Connected services disappear from the add list; removing an account deletes this app’s saved connection. General and Privacy controls retain their existing layout.

The menu bar panel shows remaining percentages. OpenAI and Claude always put **5-hour session** first and **Weekly** second. Grok and Grok Bot have separate weekly meters. Expand a card for model-specific pools and reset times. ⌘, opens Settings; ⌘R refreshes; ⌘Q quits. Right-click the menu bar icon for the app menu.

## Connections

| Provider | Sign-in | Subscription meter |
| --- | --- | --- |
| OpenAI | Native browser OAuth + PKCE | Session and weekly allowance from the direct subscription usage endpoint; additional pools in details |
| Claude | Native authorization code + PKCE browser flow | Five-hour and seven-day usage, plus model-specific limits when provided |
| Grok | Native authorization code + PKCE browser flow | Included SuperGrok subscription allowance |
| Grok Bot | Cursor’s browser challenge/poll flow | Separate included weekly Grok Bot allowance on its Cursor account |

Grok Bot’s connection uses the Cursor account already associated with Grok Bot, including a linked SuperGrok subscription. Connecting in Life Preserver does not create or change a subscription link. API billing, on-demand spending, and trial credit budgets are excluded. Missing values stay unknown; quotas are never added into a fictional common token balance.

The Claude and Grok integrations use provider-native public clients and compatibility endpoints, as other quota utilities do. Consent pages may name Claude Code or Grok Build. These are working personal integrations, **not a claim of approved third-party OAuth registration for App Store distribution**. See [provider evidence](docs/PROVIDERS.md).

All four providers use native HTTPS requests. OpenAI no longer requires an installed Codex/ChatGPT helper. Life Preserver owns its separate provider sign-ins; it does not read other apps’ sessions.

## iPhone and iPad

The native companion retrieves usage directly from OpenAI, Claude, Grok, and Grok Bot. Your Mac can sleep or quit after the one-time connection setup. Enable **Settings → iPhone & iPad → Enable direct mobile checks** in the signed Mac build and use the same iCloud account with **iCloud Passwords & Keychain** enabled on your devices.

App-owned provider sessions are encrypted with AES-GCM before upload to your private CloudKit database. The encryption keys sync through a shared iCloud Keychain access group. Devices coordinate token renewal so they do not race to consume the same rotating refresh token. Usage readings are fetched independently on each device, never copied from the Mac. See [mobile setup](docs/MOBILE.md).

## Connection troubleshooting

Expand a provider card, or open Settings → Accounts, to see the specific error. An expired or revoked renewal credential requires **Reconnect** and a fresh browser sign-in; repeatedly refreshing usage cannot restore it. Reconnect the existing account rather than removing it.

If a token renewal is interrupted, reopen Life Preserver on the device that started it, or reconnect the provider on your Mac. The app preserves completed renewals in Keychain and never blindly retries a possibly consumed refresh token.

## Privacy and efficiency

- Local credentials stay in Keychain, with no plaintext fallback. Optional direct mobile checks store only authenticated encrypted sessions in private CloudKit; encryption keys sync through iCloud Keychain. All four connections are app-owned.
- No reading of another app’s credential database, browser cookie database, passwords, prompts, or conversations. No analytics or Life Preserver server. Optional sharing transfers encrypted sign-in sessions and a minimal provider directory to your private iCloud database; device-local offline caches contain only display readings.
- Local labels and quota snapshots use a private Application Support directory. Removing an account cancels its pending work and removes its saved local and shared credentials. It does not sign other apps out of the provider.
- Refresh intervals of 1, 5, or 15 minutes; slower checks in Low Power Mode; sleep/wake handling. The mobile app refreshes on opening, pull to refresh, and every minute while active. iOS controls background execution; there is no promise of continuous polling while the app is closed.
- OAuth uses cryptographic state and PKCE, bounded timeouts, encrypted token rotation, and cancellation. Authenticated HTTP redirects are refused. Provider rate-limit cooldowns are respected.
- Readings older than 15 minutes or past a supplied reset become stale. Passing a reset never invents a full allowance.

## Build and test

The app has no third-party runtime dependencies. Xcode with the macOS SDK is required.

For the local Mac app and tests, no Apple developer account is required. For signed mobile installation or iCloud sharing, copy `Resources/Local.xcconfig.example` to `Resources/Local.xcconfig` and enter your own developer team, unique app identifiers, and shared iCloud container. The local file is ignored by Git. See [build and signing setup](docs/BUILDING.md).

```sh
bash scripts/build.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The build script creates an Apple Silicon app and ZIP in `build/Release`. `LifePreserver.xcodeproj` is the app project; `Package.swift` also builds the executable and runs core/sync tests. `scripts/sync-project.py` adds new source/resource references **without replacing any signing or build settings**. Your local signing overrides are preserved.

`LifePreserverCore` contains quota models and parsers. `LifePreserverProviders` handles direct provider transport and token exchange; `SubscriptionConnection` and `GrokBotConnection` provide native browser sign-in; `CredentialVault` owns local token storage. `LifePreserverSync` encrypts shared sessions and coordinates renewal. SwiftUI provides the panel, Accounts, onboarding, and settings within an AppKit menu bar shell. `scripts/make-icon.swift` renders the original dimensional icon with geometry shared by the monochrome menu mark.

See [release status](docs/RELEASE.md) for verification and distribution requirements.

## License and credits

Life Preserver's code and original artwork are available under the [MIT License](LICENSE), copyright © 2026 Hugues de Saint Salvy. Redistribution must retain the copyright and license notice.

Provider SVG icon data is adapted from the MIT-licensed [Lobe Icons](https://github.com/lobehub/lobe-icons) project. Its source revision and copyright/license notice are included in [ThirdPartyNotices.txt](Sources/LifePreserver/Assets/ThirdPartyNotices.txt) and bundled with both apps. Provider names and logos remain their owners' trademarks; their inclusion identifies services and does not imply endorsement.
