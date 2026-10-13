# Life Preserver 🛟

A native macOS menu bar app for remaining AI subscription usage, with an iPhone and iPad companion.

This repository contains a personal development build. Provider integrations use the compatibility interfaces described below; mobile readings currently come from the Mac through optional private iCloud sharing.

## Run

Build the app using the instructions below, then open **build/Release/Life Preserver.app**, or copy it to Applications. The Mac app requires **macOS 15.6 or later**; the mobile companion requires **iOS/iPadOS 18 or later**. The personal development builds are not notarized or App Store releases.

Connect providers in **Settings → Accounts**. Browser sign-in and consent stay with the provider. Connected services disappear from the add list; removing an account deletes this app’s saved connection. General and Privacy controls retain their existing layout.

The menu bar panel shows remaining percentages. OpenAI and Claude always put **5-hour session** first and **Weekly** second. Grok and Grok Bot have separate weekly meters. Expand a card for model-specific pools and reset times. ⌘, opens Settings; ⌘R refreshes; ⌘Q quits. Right-click the menu bar icon for the app menu.

## Connections

| Provider | Sign-in | Subscription meter |
| --- | --- | --- |
| OpenAI | Official Codex helper’s browser OAuth | Session and weekly allowance reported by the local app-server; additional pools in details |
| Claude | Native authorization code + PKCE browser flow | Five-hour and seven-day usage, plus model-specific limits when provided |
| Grok | Native authorization code + PKCE browser flow | Included SuperGrok subscription allowance |
| Grok Bot | Cursor’s browser challenge/poll flow | Separate included weekly Grok Bot allowance on its Cursor account |

Grok Bot’s connection uses the Cursor account already associated with Grok Bot, including a linked SuperGrok subscription. Connecting in Life Preserver does not create or change a subscription link. API billing, on-demand spending, and trial credit budgets are excluded. Missing values stay unknown; quotas are never added into a fictional common token balance.

The Claude and Grok integrations use provider-native public clients and compatibility endpoints, as other quota utilities do. Consent pages may name Claude Code or Grok Build. These are working personal integrations, **not a claim of approved third-party OAuth registration for App Store distribution**. See [provider evidence](docs/PROVIDERS.md).

OpenAI requires the official Codex/ChatGPT desktop app or Codex CLI installed in a supported location. Other connections use native URLSession and require no helper installation.

## iPhone and iPad

The native companion can show your latest Mac readings from anywhere using optional private iCloud sharing. Provider credentials and account labels stay on your Mac. The Mac supplies new readings while awake and online; the companion marks old readings as stale. Use the signed cloud Mac build, enable **Settings → iPhone & iPad → Share readings through iCloud**, and open the companion on a device using the same iCloud account. See [mobile setup and installation](docs/MOBILE.md).

## Connection troubleshooting

Expand a provider card, or open Settings → Accounts, to see the specific error. An expired or revoked renewal credential requires **Reconnect** and a fresh browser sign-in; repeatedly refreshing usage cannot restore it. Reconnect the existing account rather than removing it.

OpenAI helper discovery supports both the older desktop layout and the newer `codex-cli/CodexCLI.app` layout, and resolves installed desktop apps by bundle identity so app renaming does not break the connection.

## Privacy and efficiency

- Credentials are encrypted in macOS Keychain, with no plaintext fallback. Claude, Grok, and Grok Bot use this app’s own per-account items; OpenAI uses an isolated official helper connection configured for Keychain.
- No reading of another app’s credential database, browser cookie database, passwords, prompts, or conversations. No analytics or Life Preserver server. Optional mobile sharing transfers only the allowlisted usage snapshot to your private iCloud database.
- Local labels and quota snapshots use a private Application Support directory. Removing an account cancels its pending work and removes its saved credentials; OpenAI uses the helper’s logout operation.
- Refresh intervals of 1, 5, or 15 minutes; slower checks in Low Power Mode; sleep/wake handling. The Codex helper exits after reading usage.
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

`LifePreserverCore` contains quota models and parsers. `CodexBridge`, `SubscriptionConnection`, and `GrokBotConnection` handle provider transport; `CredentialVault` owns local token storage. SwiftUI provides the panel, Accounts, onboarding, and settings within an AppKit menu bar shell. `scripts/make-icon.swift` renders the original dimensional icon with geometry shared by the monochrome menu mark.

See [release status](docs/RELEASE.md) for verification and distribution requirements.

## License and credits

Life Preserver's code and original artwork are available under the [MIT License](LICENSE), copyright © 2026 Hugues de Saint Salvy. Redistribution must retain the copyright and license notice.

Provider SVG icon data is adapted from the MIT-licensed [Lobe Icons](https://github.com/lobehub/lobe-icons) project. Its source revision and copyright/license notice are included in [ThirdPartyNotices.txt](Sources/LifePreserver/Assets/ThirdPartyNotices.txt) and bundled with both apps. Provider names and logos remain their owners' trademarks; their inclusion identifies services and does not imply endorsement.
