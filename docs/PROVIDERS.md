# Provider integration evidence

Reviewed September 9–10, 2026. Only subscription allowances are displayed. No inference requests, API expenditure, or invented quota totals.

## OpenAI

[Official app-server documentation](https://developers.openai.com/codex/app-server) and [authentication](https://developers.openai.com/codex/auth).

Life Preserver initializes an isolated official app-server as `life_preserver`, uses account login/read/rate-limit/logout methods, and requires Keychain storage. The helper exits after polling. The parser prefers `rateLimitsByLimitId` and falls back to `rateLimits`; actual durations determine labels. The main pool supplies the overview; reserve/model pools only appear expanded. Missing session values remain unknown even when weekly data exists. These are the allowances returned by the coding/Work integration, not a fabricated claim about every ChatGPT feature limit.

## Claude

`GET https://api.anthropic.com/api/oauth/usage` with Bearer authentication and `anthropic-beta: oauth-2025-04-20` returns `five_hour`, `seven_day`, and optional model limits. `GET /api/oauth/profile` supplies account metadata. `extra_usage` spending is excluded.

Authorization code + S256 PKCE, state verification, and localhost callback use the provider-native public client `9d1c250a-e61b-44d9-88ed-5944d1962f5e`. Authorization goes to `https://claude.ai/oauth/authorize`; token exchange to `https://platform.claude.com/v1/oauth/token`. Only `user:profile` is requested. The provider’s consent page names this client Claude Code. A real sign-in and live usage refresh succeeded with this minimal scope in this workspace.

Protocol cross-check: [CodexBar’s Claude integration](https://github.com/steipete/CodexBar/blob/main/docs/claude.md) and [Happy’s native authentication implementation](https://github.com/slopus/happy/blob/main/packages/happy-cli/src/commands/connect/authenticateClaude.ts). Life Preserver identifies its HTTP user-agent as LifePreserver/1.0, stores its own credentials, and never reads Claude Code’s credentials.

## Grok / SuperGrok

[Official Grok overview](https://docs.x.ai/grok/overview) and [FAQ](https://docs.x.ai/grok/faq) describe the included weekly allowance shared across Grok products.

Native OAuth uses `https://auth.x.ai/oauth2/authorize` and `/oauth2/token`, public client `b1a00492-073a-47ea-816f-4c329264a828`, S256 PKCE, state, and a random loopback port. The provider-native scopes are `openid profile email offline_access grok-cli:access api:access`. Only usage/settings endpoints are called by Life Preserver.

`GET https://cli-chat-proxy.grok.com/v1/billing?format=credits`, with Bearer and `x-xai-token-auth: xai-grok-cli`, supplies the included `config.creditUsagePercent` and period metadata. `onDemandUsed` and `onDemandCap` are never divided into a subscription percentage. Settings supply the plan label. A bounded protobuf fallback reads `GrokBuildBilling/GetGrokCreditsConfig` on grok.com if JSON omits the scalar. Its proto3 omitted zero is accepted only with an explicit active subscription period; malformed or empty messages never look healthy. This behavior is covered by tests.

Protocol cross-check: [CodexBar Grok source](https://github.com/steipete/CodexBar/tree/main/Sources/CodexBarCore/Providers/Grok), provider web descriptors, and the installed official Grok CLI. A user-completed sign-in and a fresh live weekly quota read succeeded in this workspace.

## Grok Bot

[Official plans and billing](https://cursor.com/help/grok-bot/plans) explains that Bot usage is metered separately on the Cursor account, including when access comes from a linked SuperGrok subscription. Its normal included allowance resets weekly. Life Preserver never creates, changes, or removes the underlying subscription link.

The installed official Grok Bot 0.44.0 application’s static code confirms Cursor’s challenge/poll sign-in: `https://cursor.com/loginDeepControl` with a random UUID and SHA256 verifier challenge, then `https://api2.cursor.sh/auth/poll`. Tokens rotate at `/oauth/token` using the native public client. This creates an independent session in Life Preserver’s Keychain and does not inspect Grok Bot’s saved credentials.

Usage comes from `aiserver.v1.DashboardService/GetSandUsageStatus` on api2.cursor.sh. The compatibility dashboard path is `POST https://cursor.com/api/dashboard/get-sand-usage-status` using the same authenticated Cursor session. Only `usagePercent`, `hasNonZeroIncludedLimit`, reset metadata, and the plan label are used. Pooled enterprise spending, trial credits, and on-demand budgets are excluded. [CodexBar’s Sand usage parser](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Cursor/CursorSandUsage.swift) independently confirms the dashboard response fields. A real browser sign-in, SuperGrok plan label, independent weekly meter, reset time, and a fresh refresh succeeded in this workspace on September 10.

## Distribution boundary

These consumer compatibility interfaces are not documented, registered Life Preserver OAuth applications. Provider consent screens can name their native clients; behavior may change. Before public distribution, review provider authorization/terms, obtain appropriate client registration or another supported arrangement, and complete the App Sandbox/helper work. This limitation does not justify replacing working subscription meters with manual trackers.

Provider names and logos remain their owners’ trademarks. The bundled OpenAI, Claude, and Grok SVG path data comes from the MIT-licensed [Lobe Icons](https://github.com/lobehub/lobe-icons) project; the pinned upstream revision, adaptations, and copyright/license notice are recorded in `Sources/LifePreserver/Assets/ThirdPartyNotices.txt` and bundled in both apps. This licenses the icon data and does not grant provider trademark rights or imply endorsement. The Life Preserver icon is original code-rendered artwork.
