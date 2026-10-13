# Life Preserver on iPhone and iPad

The companion shows your Mac's latest provider readings from anywhere through
your private iCloud database. It supports iOS and iPadOS 18 or later. Provider
sign-in remains on the Mac; the companion never needs those credentials.

## Start using it

1. Use the same iCloud account on the Mac, iPhone, and iPad.
2. Quit the old Life Preserver on the Mac and open
   `build/Cloud/Life Preserver.app`. It uses your existing local connections.
3. In **Settings → iPhone & iPad**, turn on **Share readings through iCloud**.
   Wait for “Your mobile readings are up to date.”
4. Open the installed **Life Preserver** companion on your phone or tablet.
   Pull to refresh if necessary.

Your Mac must be awake, online, and running Life Preserver to obtain new provider
readings. The mobile app refreshes iCloud on opening, while active every minute,
and when you pull to refresh. It cannot wake the Mac or refresh providers itself.
It preserves the original provider timestamps. Readings older than 15 minutes,
with a past reset, or with a connection problem are marked stale. A reset never
invents a full allowance. Already loaded readings remain visible if the mobile
connection goes offline. A disk cache is restored only after verifying the iCloud
account, so opening the app offline before identity verification may show no data.

Only one Mac should publish to this iCloud account. Enabling a second Mac replaces
the single shared snapshot with that Mac's connected providers.

## Appearance

On the iPhone or iPad, tap the gear at the top left, then choose **System**, **Light**,
or **Dark** under **Appearance**. The choice saves automatically on this device.
On the Mac, use **Settings → General → Appearance**. System follows each device's
own appearance; choose Dark on both devices to match the deep green theme, or
Light on both to match the cream theme. Appearance preferences are not synced.

## Connection check

The gear screen shows the current app version, a short About description, and a
**Mac connection** button. Tap it to check again. Green means the phone has
successfully read an enabled snapshot published by the Mac within the last
15 minutes. Gray distinguishes unchecked, waiting, stopped sharing, and an old
Mac update. Red means the latest iCloud check failed; a brief explanation suggests
the next step. This checks the Mac's shared readings through iCloud, rather than
pinging the Mac directly.

Refresh retains last-known readings if a check is interrupted. Network, iCloud
service, account, setup, and data-format failures have separate messages; an
interrupted check is not reported as an offline phone. Development diagnostics
include only failure stages and error domains/codes, with no credentials or quota
payloads.

## Privacy and stopping sharing

Sharing is off by default. The exported snapshot includes provider names, plans,
quota windows, update times, random account identifiers, and a connection-attention
flag. It excludes account labels/email addresses, raw provider errors, credentials,
prompts, and conversations. All CloudKit reads and writes use the private database.
There is no Life Preserver account or public usage dashboard.

Turning sharing off sends an empty disabled snapshot that clears the shared quotas.
If offline, the Mac reports that clearing is pending and retries on regular
refreshes or **Retry**, including after restart. Devices with cached data clear it
when they next reach iCloud. Account sign-out/change clears the mobile cache and
disables publishing until you explicitly enable it for the new account.

## Build and install with Xcode

Both projects read your developer team, app identifiers, and shared iCloud
container from the ignored `Resources/Local.xcconfig`. Copy the example file and
enter your own values before building. CloudKit requires an Apple Developer
Program membership, an iCloud container, and provisioned signing. See
[build and signing setup](BUILDING.md).

```sh
bash scripts/build-cloud.sh
bash scripts/build-mobile.sh device
```

The cloud build uses `Resources/MacCloud.xcconfig` and its separate entitlements;
the normal `scripts/build.sh` uses local ad-hoc Mac signing. Xcode
automatic provisioning configures the development container and registers this
Mac where necessary. Sign into your developer account in Xcode Settings if needed.

Open `Mobile/LifePreserverMobile.xcodeproj`, select **LifePreserverMobile**, choose
your connected iPhone or iPad, and run. Enable Developer Mode on the device if
required. The development app cannot be installed by tapping an unsigned ZIP.

For a simulator preview:

```sh
bash scripts/build-mobile.sh
```

Install the simulator product and launch with `--preview` for explicitly labelled
sample data. Without this flag, the app reads your iCloud account. Simulator builds
and local ad-hoc Mac builds cannot establish production iCloud readiness.

## TestFlight or public distribution

The current signed builds use the CloudKit **Development** environment. Both
devices must use the same environment. Before TestFlight or distribution, deploy
the `UsageSnapshot` schema (one `payload` Bytes field) to Production in CloudKit
Console, use Production entitlements for both apps, and create the appropriate
distribution profiles. Validate publishing, reading, account removal, stopping
sharing, and account switching in that environment before releasing.

Apple references:
- [Private CloudKit sample and membership requirements](https://github.com/apple/sample-cloudkit-privatedb)
- [Enable CloudKit and configure a container](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app)
- [CloudKit database design and environments](https://developer.apple.com/icloud/cloudkit/designing/)
