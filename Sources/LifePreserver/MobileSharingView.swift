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
                    Text("Direct checks. On every device.").font(.system(size: 19, design: .serif))
                    Text("Your iPhone and iPad retrieve current usage straight from the providers.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(18).surfaceCard()
            Toggle("Enable direct mobile checks", isOn: Binding(get: { sharing.enabled }, set: { sharing.setEnabled($0, accounts: accounts) }))
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
                Text("Sign-ins prepared \(date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            SectionLabel(text: "GET CONNECTED")
            Text("1. Install the Life Preserver companion on your iPhone or iPad.\n2. Use the same iCloud account on both devices.\n3. Turn on iCloud Passwords & Keychain, enable direct checks here, then open the companion.")
                .font(.system(size: 12)).lineSpacing(8).fixedSize(horizontal: false, vertical: true)
            Text("Each device checks provider APIs using sign-ins shared securely through iCloud. Pull to refresh retrieves current usage.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Text("Sign-ins are encrypted before they enter your private iCloud database. Encryption keys sync through iCloud Keychain. Devices coordinate sign-in renewal securely. Turning this off removes shared sign-ins and keeps the Mac connections local.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
    }
}
