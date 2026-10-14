# iPhone and iPad setup

Each Life Preserver app polls OpenAI, Claude, Grok, and Grok Bot directly. Devices share encrypted provider sign-ins through private iCloud storage, with encryption keys synchronized through iCloud Keychain.

## Set up

1. Build and install the signed Mac and mobile apps using [BUILDING.md](BUILDING.md).
2. Use the same iCloud account on your devices and enable iCloud Passwords & Keychain.
3. Connect providers in Mac **Settings → Accounts**, then enable **Settings → iPhone & iPad → Enable direct mobile checks**.
4. Open the mobile app and pull to refresh. Allow time for the secure sign-in keys to synchronize during setup.

Mobile apps check on opening, pull to refresh, and once per minute while active. iOS controls background execution. Cached readings are marked stale when they need an update.

## Settings and connection details

Mobile Settings contains appearance choices, the app version, a short About description, and a direct provider connection indicator. Expand a provider card to see its specific error and last successful provider check.

Manage provider sign-ins in Mac **Settings → Accounts**. Reconnecting a provider securely replaces its shared session. Turning direct mobile checks off preserves current credentials locally on the Mac and removes the shared provider directory and encrypted sessions.

## Credential protection

- App-owned credentials are encrypted with AES-GCM before upload to private CloudKit storage. Encryption authenticates the account record, provider, key ID, and session revision.
- Random 256-bit encryption keys synchronize through iCloud Keychain. Both signed apps use the same Keychain access group and matching app metadata.
- Offline caches contain usage display data. Credentials and session payloads remain in Keychain or authenticated encrypted storage and are excluded from diagnostics and the repository.
- CloudKit compare-and-swap saves and per-session leases coordinate rotating-token renewal across devices.
- Completed renewals are journaled in local Keychain until their shared save completes. Brief background execution lets mobile apps finish a renewal save. Ambiguous exchanges remain blocked to prevent refresh-token reuse.
- CloudKit identity is checked before loading cached accounts. An account change clears mobile caches and requires a fresh sharing opt-in.

## Troubleshooting

| Message or symptom | Action |
| --- | --- |
| Waiting for a secure sign-in key | Confirm iCloud Passwords & Keychain is enabled; keep devices online and unlocked for synchronization. |
| Provider session expired or revoked | Reconnect that provider in Mac Settings → Accounts. |
| Another device is renewing | Refresh again shortly. |
| Renewal interrupted | Reopen Life Preserver on the device that started renewal, or reconnect the provider on the Mac. |
| No connected providers | Connect providers and enable direct mobile checks in Mac Settings. |
| iCloud unavailable | Confirm the device's iCloud account and network connection, then retry. |

The signed apps must use the same iCloud container, environment, and Keychain access group. Development builds use CloudKit Development. See [release status](RELEASE.md) for public distribution requirements.
