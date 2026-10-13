# Release status

Life Preserver 1.1.0 is a native personal development build, not an App Store submission or notarized public release.

## Public source preparation

- Added the project MIT license and verified provider icon sources with the Lobe Icons copyright/license notice bundled in both apps.
- Redacted the historical feedback screenshot's account email. The original is preserved only in an ignored local backup.
- Moved personal signing overrides into the ignored `Resources/Local.xcconfig`; public projects use configurable team, bundle, and iCloud container identifiers. Added clone/build instructions and an automatic GitHub test workflow.
- Corrected the README to the Mac app's existing macOS 15.6 minimum. The application requirement itself is unchanged.
- Validation: a clean staged-source export without local signing overrides passed the local Mac Release build, iOS simulator build, and all 32 tests. The personal signed Mac and iOS builds also passed; app/iCloud identities and bundled notices were verified. CI also checks built metadata and bundled notices. The signed Mac's read-only iCloud check still read its enabled shared snapshot.

## October 12: mobile companion

### Brief Settings and connection check (build 5)

- Replaced the long Settings copy with the bundle's version/build number, a two-sentence About description, and a tappable Mac connection indicator with brief state-specific troubleshooting.
- Green requires a successful iCloud read and a recent enabled Mac publication. Gray distinguishes unchecked, waiting, stopped sharing, and stale updates; red indicates a failed check.
- Differentiated CloudKit network/service/account/setup/format errors and stopped treating cancelled checks as offline failures. Development diagnostics log only stages and error domains/codes, not credentials or payloads.
- 32 tests passed (29 core, 3 sync). Signed device and simulator builds passed. Inspected the simplified Settings layout. Actual iPhone checks read the Mac's enabled snapshot successfully, and the user confirmed manual pull to refresh updates normally after installing this revision.

### Appearance selection (build 4)

- Added a mobile Settings gear with persistent System, Light, and Dark choices. The selected scheme applies to the usage screen and Settings sheet; System remains the default. Mac appearance is still configured in Settings → General.
- Device and simulator builds passed. Verified Dark overrides a light-mode phone simulator. Updated and launched the signed build on the paired iPhone.

### Mobile interface revision (build 3)

- Matched the Mac's light/dark palette, serif wordmark, bordered cards, provider marks, inline plan pills, and segmented usage meters.
- Added the existing color preserver artwork immediately before the navigation title. Removed the introductory banner and separate Details disclosure row. Provider header buttons now expand/collapse usage details, with accessible state and Reduce Motion support.
- Signed device and simulator builds passed. Inspected the light iPhone and dark iPad simulator layouts. Updated the companion on the paired iPhone and confirmed it launches. The iPad's physical installation still awaits unlock.
- This revision changes presentation; service fetching continues to use Mac-published iCloud readings.

### Companion implementation

- Added a native iPhone/iPad companion (iOS/iPadOS 18+) with adaptive provider cards, details, reset times, pull to refresh, and stale-reading indicators.
- Added opt-in private CloudKit snapshot sharing from the Mac. The allowlist excludes account labels, raw connection errors, credentials, and demo/manual connections. Stopping sharing replaces the remote payload with an empty disabled snapshot; failed clears retry after refresh/restart.
- Added account-change handling and identity-checked mobile caching. One Mac publishes; mobile devices are read-only. Mac provider update times are preserved.
- Existing local Mac signing remains intact. A separate cloud build configuration uses the existing developer team and a shared development iCloud container. See [mobile setup](MOBILE.md).
- Validation: 27 core tests passed; local Mac Release, signed cloud Mac, signed iOS device, and iOS simulator builds passed. Both signed apps passed strict signature verification. Phone and tablet sample layouts were inspected. The companion installed and launched on the user's paired iPhone. The paired iPad is locked, so its physical installation is pending.
- The signed Mac's read-only deployment check confirmed iCloud access and no published snapshot yet. Actual provider snapshot publishing/reading and clearing still need validation after enabling sharing in Settings. TestFlight/Production deployment has not been performed.

## Previous Mac release

## This revision

- Compact usage overview with fixed session/weekly positions, expanded extra pools and reset details, matching monochrome menu icon, custom dimensional artwork, and a consistent serif wordmark.
- Removed the decorative banner, status dot, persistent selection outlines, duplicate footer menu, redundant counts, and rejected copy.
- Accounts lists each provider once. Connected providers leave the add list. Claude, Grok, and Grok Bot use secure sign-in; there are no manual-entry forms.
- OpenAI, Claude, and SuperGrok live usage verified after browser authorization. Grok Bot browser sign-in, SuperGrok plan detection, its separate weekly allowance, reset time, and a fresh refresh were verified on September 10.
- General and Privacy layouts retained; obsolete manual-tracking/security text corrected where behavior changed.
- User’s developer team, signing settings, and bundle identifier preserved. Project synchronization only adds file references.

## Validation

- 22 passing core tests: quota integrity, unknown versus zero, main pool selection, missing sessions, provider parsing, API/on-demand exclusion, Grok protobuf malformed frames/error trailers/implicit zero, separate Grok Bot allowance, stale readings, resets, pressure boundaries, and credential-free snapshot persistence.
- Apple Silicon Release build and strict code-signature verification.
- Native visual review of the compact and expanded panel and Accounts in dark mode. Actual OpenAI, Claude, SuperGrok, and Grok Bot refreshes succeeded. The four-provider panel and Accounts list were reviewed together. All four connections restored and refreshed after a full app restart. Expanded panel height was verified against its measured content.

## Before public distribution

1. Review provider approval and register suitable OAuth clients or establish another supported arrangement for consumer quota endpoints. Current integrations use the provider-native compatibility flows described in PROVIDERS.md.
2. Resolve distribution/version compatibility/licensing for the official Codex helper. The personal build locates an installed official executable.
3. Configure Developer ID or App Store signing as appropriate. Notarize direct downloads. Keep personal developer-team settings in the ignored local signing configuration.
4. Implement and validate an App Sandbox-compatible helper/auth architecture. The personal build is not sandboxed and is not represented as App Store-ready.
5. Add a public support contact/privacy policy, storefront metadata, and an update strategy.
6. Validate optional private iCloud snapshot sharing, stopped-sharing cleanup, account switching, offline behavior, and Production schema/environment. Provider credentials remain local and are not part of the synced snapshot.
7. Broaden device validation to supported Apple Silicon macOS versions, VoiceOver, multiple displays, token expiration, revoked access, provider cooldowns, login items, notifications, sleep/wake, and long-running memory/energy behavior.

The project includes a privacy manifest for local UserDefaults access. Review it when dependencies or data handling change.
