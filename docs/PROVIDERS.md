# Provider integrations

Each Life Preserver app makes direct HTTPS requests to the provider usage interfaces below. Sign-ins belong to Life Preserver and are shared as encrypted sessions through private iCloud storage, with encryption keys synchronized through iCloud Keychain. Only subscription allowances are displayed.

## OpenAI

Usage comes from `GET https://chatgpt.com/backend-api/wham/usage`, using Bearer authentication and the session's `ChatGPT-Account-Id` when available. `rate_limit.primary_window`, `secondary_window`, and additional model limits provide subscription windows. Credits and on-demand balances are excluded. These are the coding/Work integration's reported allowances.

Browser authorization uses OpenAI's native public client, S256 PKCE, state verification, and the fixed localhost callback. Authorization-code exchange is form-encoded; token refresh is JSON.

References: [OpenAI authentication](https://learn.chatgpt.com/docs/auth), [OpenAI login implementation](https://github.com/openai/codex/tree/main/codex-rs/login/src), and [CodexBar's direct usage client](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift).

## Claude

`GET https://api.anthropic.com/api/oauth/usage` uses Bearer authentication and `anthropic-beta: oauth-2025-04-20`. It returns `five_hour`, `seven_day`, and optional model limits. `GET /api/oauth/profile` supplies account and plan metadata. `extra_usage` spending is excluded.

Authorization code + S256 PKCE, state verification, and a localhost callback use the provider-native public client `9d1c250a-e61b-44d9-88ed-5944d1962f5e`. Authorization goes to `https://claude.ai/oauth/authorize`; token exchange goes to `https://platform.claude.com/v1/oauth/token`. The requested scope is `user:profile`. The consent page names this client Claude Code.

References: [CodexBar's Claude integration](https://github.com/steipete/CodexBar/blob/main/docs/claude.md) and [Happy's authentication implementation](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/commands/connect/authenticateClaude.ts).

## Grok / SuperGrok

Native OAuth uses `https://auth.x.ai/oauth2/authorize` and `/oauth2/token`, public client `b1a00492-073a-47ea-816f-4c329264a828`, S256 PKCE, state verification, and a random loopback port. Scopes are `openid profile email offline_access grok-cli:access api:access`.

`GET https://cli-chat-proxy.grok.com/v1/billing?format=credits`, with Bearer authentication and `x-xai-token-auth: xai-grok-cli`, supplies the included `config.creditUsagePercent` and period metadata. Settings supply the plan label. On-demand spending is excluded.

A bounded protobuf fallback reads `GrokBuildBilling/GetGrokCreditsConfig` on grok.com if JSON omits the percentage scalar. An omitted proto3 zero is accepted only with an explicit active subscription period; malformed or empty messages remain unknown.

References: [Grok overview](https://docs.x.ai/grok/overview), [Grok FAQ](https://docs.x.ai/grok/faq), and [CodexBar's Grok integration](https://github.com/steipete/CodexBar/tree/main/Sources/CodexBarCore/Providers/Grok).

## Grok Bot

Grok Bot uses its associated Cursor account, including access through a linked SuperGrok subscription. Life Preserver does not create or change subscription links. Bot usage is metered separately from Grok usage.

Browser sign-in uses `https://cursor.com/loginDeepControl` with a random UUID and SHA256 verifier challenge, then polls `https://api2.cursor.sh/auth/poll`. Tokens rotate at `/oauth/token` using the native public client.

Usage comes from `aiserver.v1.DashboardService/GetSandUsageStatus` on api2.cursor.sh. The dashboard compatibility path is `POST https://cursor.com/api/dashboard/get-sand-usage-status`, using the same authenticated Cursor session. Only `usagePercent`, `hasNonZeroIncludedLimit`, reset metadata, and the plan label are used. Enterprise spending, trial credits, and on-demand budgets are excluded.

References: [Grok Bot plans and billing](https://cursor.com/help/grok-bot/plans) and [CodexBar's Sand usage parser](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Cursor/CursorSandUsage.swift).

## Transport and distribution

Life Preserver uses its own native transport with the `LifePreserver/1.2` user-agent, bounded requests, cache-free sessions, and refused redirects. Raw responses and credentials are excluded from diagnostics. Missing quota values remain unknown.

These consumer compatibility interfaces use provider-native public clients rather than registered Life Preserver OAuth applications. Consent screens can name the provider's native client. Public distribution requires appropriate provider authorization, signing, and platform validation; see [RELEASE.md](RELEASE.md).

## Provider icons

The OpenAI, Claude, and Grok SVG data comes from the MIT-licensed [Lobe Icons](https://github.com/lobehub/lobe-icons) project. The pinned revision, adaptations, and license notice are recorded in [ThirdPartyNotices.txt](../Sources/LifePreserver/Assets/ThirdPartyNotices.txt) and bundled with both apps. Provider names and logos remain their owners' trademarks. The Life Preserver icon is original artwork.
