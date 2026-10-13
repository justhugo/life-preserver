import SwiftUI
#if SWIFT_PACKAGE
import LifePreserverCore
#endif

struct MobileSharingView: View {
    @ObservedObject var sharing: MobileSharing
    let accounts: [ProviderAccount]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "iphone.and.ipad").font(.system(size: 32, weight: .light)).foregroundStyle(Palette.sea)
                VStack(alignment: .leading, spacing: 6) {
                    Text("A little peace of mind. Anywhere.").font(.system(size: 19, design: .serif))
                    Text("Check your latest Mac readings on your iPhone or iPad, even when you’re away.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(18).surfaceCard()
            Toggle("Share readings through iCloud", isOn: Binding(get: { sharing.enabled }, set: { sharing.setEnabled($0, accounts: accounts) }))
                .toggleStyle(.switch).tint(Palette.sea).disabled(!sharing.configured)
            if !sharing.configured {
                Text("This Mac build runs locally. The mobile setup guide explains how to install the iCloud-enabled build with your Apple developer account.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 9) {
                if sharing.busy { ProgressView().controlSize(.small) }
                Text(sharing.status).font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                if sharing.configured {
                    Spacer()
                    Button("Retry") { sharing.retry() }.disabled(sharing.busy).buttonStyle(.plain).foregroundStyle(Palette.sea)
                }
            }
            if let date = sharing.lastPublished {
                Text("Last shared \(date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            SectionLabel(text: "GET CONNECTED")
            Text("1. Install the Life Preserver companion on your iPhone or iPad.\n2. Use the same iCloud account on both devices.\n3. Turn on sharing here, then open the companion.")
                .font(.system(size: 12)).lineSpacing(8).fixedSize(horizontal: false, vertical: true)
            Text("Your Mac supplies the readings while Life Preserver is running and the Mac is awake and online. The companion can show the last received readings while your Mac is asleep; it marks old readings as stale. Pull to refresh checks iCloud, rather than signing in to providers again.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Text("Only one Mac should share at a time. Turning sharing off clears the shared readings once your Mac reaches iCloud. Provider credentials and account labels always stay on your Mac.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
    }
}
