import SwiftUI
#if SWIFT_PACKAGE
import LifePreserverCore
#endif

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @State private var removing: ProviderAccount?
    @State private var busyRemoving = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(store.settingsPage.rawValue).font(.system(size: 28, design: .serif)).tracking(-0.5)
                        if store.settingsPage != .accounts { Text(pageSubtitle).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3) }
                    }.padding(.bottom, 2)
                    if let error = store.connectionError {
                        ErrorNote(message: error).onTapGesture { store.connectionError = nil }
                    }
                    if let error = store.persistenceError { ErrorNote(message: error) }
                    switch store.settingsPage {
                    case .accounts: accountsPage
                    case .general: generalPage
                    case .mobile: MobileSharingView(sharing: store.mobileSharing, accounts: store.accounts)
                    case .privacy: privacyPage
                    }
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.hidden)
        }.frame(width: 690, height: 590)
            .background(Palette.background).foregroundStyle(Palette.ink)
            .preferredColorScheme(store.appearance == "light" ? .light : store.appearance == "dark" ? .dark : nil)
            .alert("Remove \(removing?.provider.name ?? "account")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button("Cancel", role: .cancel) { removing = nil }
                Button("Remove", role: .destructive) {
                    if let account = removing {
                        busyRemoving = true
                        Task { await store.remove(account); busyRemoving = false }
                    }
                    removing = nil
                }
            } message: { Text("This removes the saved readings and credentials for this Life Preserver connection. Your subscription and other apps are unaffected.") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                PreserverMark().frame(width: 24, height: 24)
                Wordmark(size: 15)
            }.padding(.horizontal, 8).padding(.top, 27).padding(.bottom, 26)
            ForEach(SettingsPage.allCases) { page in
                Button { store.settingsPage = page } label: {
                    Label(page.rawValue, systemImage: page.symbol)
                        .font(.system(size: 12, weight: store.settingsPage == page ? .medium : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 11).padding(.vertical, 10)
                        .background(store.settingsPage == page ? Palette.sea.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).focusable(false).focusEffectDisabled().foregroundStyle(store.settingsPage == page ? Palette.sea : Palette.secondary)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 5) {
                Text("Keeps you afloat.").font(.system(size: 11, design: .serif)).foregroundStyle(Palette.secondary)
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0")").font(.system(size: 7, weight: .medium)).tracking(0.5).foregroundStyle(Palette.secondary.opacity(0.7))
            }.padding(.horizontal, 9).padding(.bottom, 21)
        }.padding(.horizontal, 12).frame(width: 167).background(Palette.wash.opacity(0.45))
            .overlay(alignment: .trailing) { Rectangle().fill(Palette.line).frame(width: 0.7) }
    }
    private var pageSubtitle: String {
        switch store.settingsPage {
        case .accounts: "Your AI providers, all aboard."
        case .general: "Customize behaviors to suit your preferences."
        case .mobile: "Your reserves, wherever you are."
        case .privacy: "Your sign-ins stay encrypted and private."
        }
    }
    private var availableProviders: [Provider] {
        Provider.allCases.filter { provider in !store.accounts.contains { $0.provider == provider } }
    }
    private var accountsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            if store.demo {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles").foregroundStyle(Palette.blue)
                    Text("You’re exploring with sample data. Add an account to see your own usage.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Exit") { store.demo = false }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Palette.sea)
                }.padding(13).surfaceCard()
            }
            if !store.accounts.isEmpty {
                SectionLabel(text: "CONNECTED")
                VStack(spacing: 8) {
                    ForEach(store.accounts) { account in
                        HStack(spacing: 11) {
                            ProviderMark(provider: account.provider)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(account.provider.name).font(.system(size: 12, weight: .semibold))
                                    if !account.plan.isEmpty { Tag(text: account.plan) }
                                }
                                Text(account.label).font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(1).truncationMode(.middle)
                                if let error = account.error {
                                    Text(error).font(.system(size: 10)).foregroundStyle(Palette.amber)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 3)
                            if account.error != nil || account.kind == .manual {
                                Button("Reconnect") { store.connect(account.provider, replacing: account.id) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.sea)
                            }
                            Button { removing = account } label: { Image(systemName: "minus.circle").font(.system(size: 13)) }
                                .buttonStyle(QuietButtonStyle()).help("Remove \(account.provider.name)").accessibilityLabel("Remove \(account.provider.name)")
                                .disabled(busyRemoving)
                        }.padding(12).surfaceCard()
                    }
                }
            }
            if !availableProviders.isEmpty { SectionLabel(text: "ADD A PROVIDER") }
            VStack(spacing: 8) {
                ForEach(availableProviders) { provider in
                    ConnectionRow(provider: provider, busy: provider == store.connectingProvider && store.connecting) {
                        store.connectionError = nil
                        store.connect(provider)
                    }
                }
            }
            if store.connecting {
                HStack {
                    ProgressView().controlSize(.mini)
                    Text("Continue in your browser…").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    Spacer()
                    Button("Cancel") { store.cancelLogin() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.sea)
                }
            }

        }
    }
    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 19) {
            SectionLabel(text: "AT HOME IN YOUR MENU BAR")
            VStack(spacing: 0) {
                settingRow("Launch at login", subtitle: "Ready whenever your Mac is.") {
                    Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider().overlay(Palette.line)
                settingRow("Show remaining percentage in menu bar", subtitle: "Shows the tightest limit beside the life preserver.") {
                    Toggle("Show remaining percentage in menu bar", isOn: $store.showMenuPressure).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider().overlay(Palette.line)
                settingRow("Appearance", subtitle: "Just the way you like it.") {
                    Picker("Appearance", selection: $store.appearance) {
                        Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }.labelsHidden().frame(width: 100)
                }
            }.surfaceCard()
            SectionLabel(text: "A GENTLE HEADS-UP")
            VStack(spacing: 0) {
                settingRow("Low-usage alerts", subtitle: "When a live limit crosses 90% used.") {
                    Toggle("Low-usage alerts", isOn: Binding(get: { store.notificationsEnabled }, set: { store.setNotifications($0) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider().overlay(Palette.line)
                settingRow("Check live usage", subtitle: "Slows down automatically in Low Power Mode.") {
                    Picker("Refresh interval", selection: $store.refreshMinutes) {
                        Text("Every minute").tag(1); Text("Every 5 min").tag(5); Text("Every 15 min").tag(15)
                    }.labelsHidden().frame(width: 115)
                }
            }.surfaceCard()
            Text("Alerts use live subscription readings. Sample data never sends alerts.")
                .font(.system(size: 10)).foregroundStyle(Palette.secondary).lineSpacing(3)
            Button("Explore with sample data") { store.demo = true; store.onShowPanel?() }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.sea)
        }.tint(Palette.sea)
    }
    private var privacyPage: some View {
        VStack(alignment: .leading, spacing: 17) {
            ZStack {
                RoundedRectangle(cornerRadius: 15).fill(Palette.hero)
                HStack(spacing: 14) {
                    Image(systemName: "lock.shield").font(.system(size: 32, weight: .light)).foregroundStyle(Palette.sea)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Safe in your own waters.").font(.system(size: 19, design: .serif))
                        Text("No Life Preserver account. No analytics.").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }
                }.padding(20)
            }.fixedSize(horizontal: false, vertical: true)
            privacyItem("key", "Encrypted on your Mac", "Sign-in credentials are encrypted in macOS Keychain. Passwords and verification codes stay in your provider’s sign-in page.")
            privacyItem("arrow.triangle.branch", "A separate connection", "Each account has its own sign-in. Adding or removing it never changes your login in Codex or ChatGPT.")
            privacyItem("eye", "Only what the meter needs", "Provider names, account labels, and quota readings are saved locally. Prompts and conversations are never requested.")
            privacyItem("icloud", "Optional direct mobile checks", "Your devices check providers directly. App-owned sign-ins are encrypted in your private iCloud database; encryption keys sync through iCloud Keychain. No plaintext credentials are uploaded.")
            Link("Read about Codex authentication ↗", destination: URL(string: "https://developers.openai.com/codex/auth")!)
                .font(.system(size: 11)).foregroundStyle(Palette.sea)
        }
    }
    private func privacyItem(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Palette.sea).frame(width: 20).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func settingRow<Content: View>(_ title: String, subtitle: String, @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            control()
        }.padding(15)
    }
}
