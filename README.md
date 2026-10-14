# Life Preserver 🛟

Life Preserver brings your remaining AI subscription usage together in a native macOS menu bar app and native iPhone and iPad apps. Each device polls provider APIs directly. Provider sign-ins are shared securely through iCloud, with encryption keys synchronized through iCloud Keychain.

## Requirements and setup

The Mac app requires Apple Silicon and **macOS 15.6 or later**. The mobile apps require **iOS/iPadOS 18 or later**. Build with Xcode using the [build and signing guide](docs/BUILDING.md).

1. Open the Mac app and connect providers in **Settings → Accounts**. Password entry and consent take place in the provider's browser sign-in page.
2. For iPhone and iPad access, install the signed apps and enable **Settings → iPhone & iPad → Enable direct mobile checks** on the Mac.
3. Use the same iCloud account on your devices and turn on **iCloud Passwords & Keychain**.
4. Open Life Preserver on each device to check usage. Pull to refresh on iPhone or iPad for a fresh provider check.

See [mobile setup and troubleshooting](docs/MOBILE.md).

## Usage overview

Provider cards show remaining percentages, reset times, and plan names. OpenAI and Claude show **5-hour session** and **Weekly** meters; Grok and Grok Bot have separate weekly meters. Expand a card for additional limits and connection details. Missing values remain unknown, and old readings are marked stale.

The Mac app refreshes at your selected 1-, 5-, or 15-minute interval, with slower checks in Low Power Mode. Mobile apps check on opening, pull to refresh, and once per minute while active. iOS controls background execution, so readings can become stale when the app is closed.

On the Mac, ⌘, opens Settings, ⌘R refreshes, and ⌘Q quits. Right-click the menu bar icon for the app menu. Appearance settings provide System, Light, and Dark choices on each platform.

## Providers

| Provider | Sign-in | Subscription meter |
| --- | --- | --- |
| OpenAI | Native browser OAuth + PKCE | Session and weekly allowance, with additional model limits in details |
| Claude | Native browser OAuth + PKCE | Five-hour and seven-day usage, plus model limits when provided |
| Grok | Native browser OAuth + PKCE | Included SuperGrok subscription allowance |
| Grok Bot | Cursor browser challenge/poll | Separate included weekly allowance on its Cursor account |

All four providers use native HTTPS requests and app-owned sign-ins. Grok Bot uses its associated Cursor account, including a linked SuperGrok subscription; Life Preserver does not change subscription links. API billing, on-demand spending, and trial credit budgets are excluded.

The integrations use provider-native public clients and consumer compatibility endpoints. Consent pages can name Claude Code or Grok Build. Public distribution requires suitable provider authorization and signing. See [provider integrations](docs/PROVIDERS.md) and [release status](docs/RELEASE.md).

## Privacy and credential sharing

- Local credentials are protected by Keychain. Passwords, verification codes, prompts, and conversations are not collected.
- Shared sessions are encrypted with AES-GCM before they enter your private CloudKit database. Random 256-bit encryption keys synchronize through a shared iCloud Keychain access group.
- Devices coordinate rotating-token renewal through CloudKit. A completed renewal is retained in local Keychain until its shared save completes.
- Offline caches contain only usage display data. No plaintext credentials enter files, diagnostics, or the repository. There is no Life Preserver server or analytics service.
- Removing a connection deletes its local and shared credentials. Turning direct mobile checks off removes shared sessions while preserving the Mac's local connections.

Expand a provider card for its specific error and last successful check. Reconnect an expired or revoked sign-in in Mac **Settings → Accounts**. See [troubleshooting](docs/MOBILE.md#troubleshooting) for Keychain sync and renewal issues.

## Build and test

```sh
bash scripts/build.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The local Mac build and tests require no Apple developer account. Signed device installation and iCloud credential sharing require your own Apple developer configuration in the ignored `Resources/Local.xcconfig` file. See [BUILDING.md](docs/BUILDING.md).

`LifePreserverCore` contains usage models and parsers. `LifePreserverProviders` handles direct HTTPS transport and token exchange. `LifePreserverSync` encrypts shared sessions and coordinates renewal. Platform code provides browser sign-in, local Keychain storage, settings, and the native interfaces.

## License and credits

Life Preserver's code and original artwork are available under the [MIT License](LICENSE), copyright © 2026 Hugues de Saint Salvy. Redistribution must retain the copyright and license notice.

Provider SVG icon data is adapted from the MIT-licensed [Lobe Icons](https://github.com/lobehub/lobe-icons) project. Its pinned source revision and copyright/license notice are included in [ThirdPartyNotices.txt](Sources/LifePreserver/Assets/ThirdPartyNotices.txt) and bundled with both apps. Provider names and logos remain their owners' trademarks and do not imply endorsement.
