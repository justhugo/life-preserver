# Connection investigation — October 7, 2026

Two independent errors shared the generic “Connection needs attention” heading. Dates below use America/New_York.

## OpenAI: desktop helper moved

The saved error was `missingHelper`. The app searched `/Applications/Codex.app/Contents/Resources/codex` and `/Applications/ChatGPT.app/Contents/Resources/codex`; neither exists on this Mac now. The installed desktop app is named ChatGPT, retains bundle identifier `com.openai.codex`, and bundles its helper at `Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex` (version 0.160.1).

Running the existing Life Preserver connection through that helper successfully initialized the app-server, found its saved ChatGPT account, and returned live rate limits. Its sign-in did not need replacement. The previous successful snapshot was October 3 at 8:57 p.m.; snapshots do not record the exact first failure or installation time of the update.

The repair resolves installed apps by bundle identifier and checks the current and legacy helper locations. Account isolation and Keychain storage remain in place. The current helper still supports the app-server methods used here, as confirmed by the live diagnostic and [official documentation](https://learn.chatgpt.com/docs/app-server).

## Claude: renewal credential expired

The previous successful snapshot was October 6 at 9:13 p.m. The saved access credential expired October 7 at 2:27 a.m. A direct usage check returned HTTP 401 with `authentication_error` and an expiry description. With Life Preserver stopped to prevent concurrent renewal, one request to the existing token endpoint returned HTTP 400 with `invalid_grant`; its description indicated an expired refresh token.

The app already performs renewal, but discarded the OAuth error code and showed a generic HTTP 400 message. The repair interprets `invalid_grant` on renewal as requiring reconnect, retains the existing credential, and explains the next action in Settings → Accounts. Other HTTP 400 responses retain their ordinary error handling. Raw provider descriptions and credentials are never persisted as diagnostics.

Restore Claude with Settings → Accounts → Claude → Reconnect, then complete browser authorization. Replacing the existing connection preserves its identity. The rejected renewal grant cannot be restored with an automatic retry. The response establishes expiry; it does not establish Anthropic's exact refresh-token lifetime or why that lifetime was chosen.

## Validation and diagnostic tools

The repaired release build and strict code-signature verification passed, along with 23 core tests including the new OAuth failure regression check. The previous installed app was backed up under `build/Backup-2026-10-07`, and the repaired app was installed in Applications. Its first refresh restored OpenAI and kept Grok and Grok Bot healthy. Native UI verification showed live OpenAI readings and the specific Claude reconnect guidance, with Accounts left open for the user. Claude browser reauthorization remains a user action.

`scripts/check-connection.py` reports OpenAI protocol/schema status without credentials or identity. `scripts/check-subscription.swift` checks only Life Preserver's Claude credential, expiry, and usage HTTP status. Its optional `--refresh` attempts renewal and immediately saves a successful rotation back to the same Keychain item; stop Life Preserver first. It refuses authenticated redirects and prints only recognized error codes and description categories, never raw responses or credentials.
