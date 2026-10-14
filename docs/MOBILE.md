# Direct iPhone and iPad checks

Life Preserver 1.2.0 checks all four provider APIs directly on each device. The Mac is used for initial browser sign-in and setup, not as an ongoing usage bridge.

## Set up

1. Build/install the signed Mac and mobile apps using [BUILDING.md](BUILDING.md).
2. Use the same iCloud account on the Mac, iPhone, and iPad, with iCloud Passwords & Keychain enabled.
3. In the Mac app, connect providers, then enable **Settings → iPhone & iPad → Enable direct mobile checks**.
4. Open the mobile app and pull to refresh. Initial Keychain synchronization may take time; the app distinguishes a missing encryption key from a provider error.

Existing Life Preserver sign-ins migrate automatically. OpenAI migration reads only the exact Keychain item created for this app's own UUID connection directory; it never searches another app's credential store. New OpenAI sign-ins use native browser OAuth + PKCE without a Codex helper.

After setup, the Mac can sleep or quit. Mobile refresh uses HTTPS requests to each provider, preserving the same subscription-only usage model. The mobile app checks on opening, pull to refresh, and once per minute while active. iOS controls background execution; closed-app readings are cached and marked stale when appropriate.

## Credential protection

- Credentials are encrypted with AES-GCM before reaching the private CloudKit database. Encryption authenticates the account record, provider, key ID, and session revision.
- Random 256-bit encryption keys synchronize through iCloud Keychain. Both signed apps need the same `keychain-access-groups` entitlement and matching `LifePreserverKeychainAccessGroup` metadata. The shared group defaults to your Mac bundle identifier plus `.sessions`, prefixed by Apple's app identifier prefix.
- No plaintext credential, provider response, or encrypted session payload is written to the mobile offline cache, Git, diagnostics, or a Life Preserver server.
- CloudKit saves use `ifServerRecordUnchanged`. A per-session lease allows only one device to exchange a rotating refresh token. A device seeing an already-replaced rejected bearer uses the newer token instead of rotating again.
- A completed renewal is journaled in local Keychain before its CloudKit save. Brief background execution lets a phone finish this critical save when its view closes. An interrupted or ambiguous exchange leaves the lease blocked rather than risking token reuse. Reopen the initiating device to finish a journaled save, or reconnect on the Mac if no completed response survived.
- CloudKit identity is checked before reading cached accounts. An actual iCloud account change clears mobile cache and stops automatic Mac sharing; initial or transient account notifications do not silently disable sharing.

Turning direct checks off first preserves current canonical credentials locally, then removes the shared provider directory and encrypted sessions. Reconnecting a provider replaces the shared session atomically; old renewal transactions cannot overwrite the new sign-in.

## Troubleshooting

- **Waiting for your secure sign-in key:** confirm iCloud Passwords & Keychain on both devices; keep them online and unlocked for initial synchronization.
- **Provider session expired:** reconnect that provider in Mac Settings → Accounts.
- **Another device is renewing:** refresh again shortly.
- **Renewal interrupted:** reopen the initiating device or reconnect the provider on the Mac.
- **No accounts:** enable direct mobile checks in the updated Mac build once.

Expand a provider card to see its specific error and last successful provider check. Mobile Settings has a brief direct-connection health indicator.

The current personal signed builds use CloudKit Development. Public/TestFlight distribution still requires the Production schema, appropriate signing, and provider-client review; see [RELEASE.md](RELEASE.md).
