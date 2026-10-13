import SwiftUI
#if SWIFT_PACKAGE
import LifePreserverCore
#endif

struct OnboardingView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Palette.hero).frame(width: 154, height: 154)
                Waves().stroke(Palette.sea.opacity(0.12), lineWidth: 1).frame(width: 220, height: 75).offset(y: 38)
                PreserverMark().frame(width: 89, height: 89).rotationEffect(.degrees(-12))
                    .shadow(color: Palette.ink.opacity(0.1), radius: 10, x: 0, y: 8)
                Image(systemName: "sparkle").font(.system(size: 19, weight: .light)).foregroundStyle(Palette.amber).offset(x: 64, y: -42)
                Circle().fill(Palette.sea.opacity(0.4)).frame(width: 4, height: 4).offset(x: -62, y: -24)
            }.frame(height: 157).padding(.top, 28)
            SectionLabel(text: "A SMALL COMPANION FOR BIG IDEAS").padding(.top, 17)
            Text("Stay in your flow.").font(.system(size: 34, design: .serif)).tracking(-1).padding(.top, 10)
            Text("Keep an eye on your AI limits,\nwithout losing sight of what you’re making.")
                .font(.system(size: 13)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).lineSpacing(5).padding(.top, 10)

            VStack(spacing: 9) {
                ForEach(Provider.allCases) { provider in
                    ConnectionRow(provider: provider, connected: store.accounts.contains { $0.provider == provider }, busy: provider == store.connectingProvider && store.connecting) {
                        store.connect(provider)
                    }
                }
            }.padding(.top, 25)
            if store.connecting {
                HStack {
                    Text("Finish signing in in your browser.")
                    Button("Cancel") { store.cancelLogin() }.buttonStyle(.plain).foregroundStyle(Palette.sea)
                }.font(.system(size: 11)).foregroundStyle(Palette.secondary).padding(.top, 12)
            }
            if let error = store.connectionError { ErrorNote(message: error).padding(.top, 12) }
            Spacer(minLength: 15)
            if !store.accounts.isEmpty {
                Button("Continue") { store.finishOnboarding() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            } else {
                Button("Take a look around") { store.finishOnboarding(preview: true) }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.sea)
                Text("Explore with sample data. Connect when you’re ready.")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary).padding(.top, 7)
            }
            HStack(spacing: 5) {
                Image(systemName: "lock.shield").font(.system(size: 10))
                Text("Local by nature. Private by design.").font(.system(size: 10))
            }.foregroundStyle(Palette.secondary).padding(.top, 24).padding(.bottom, 24)
        }.padding(.horizontal, 42).frame(width: 500, height: store.connectionError == nil ? 755 : 825)
            .background(Palette.background).foregroundStyle(Palette.ink)
            .preferredColorScheme(store.appearance == "light" ? .light : store.appearance == "dark" ? .dark : nil)
    }
}

struct ConnectionRow: View {
    let provider: Provider
    var connected = false
    var busy = false
    let action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            ProviderMark(provider: provider, size: 37)
            VStack(alignment: .leading, spacing: 4) {
                Text(provider.name).font(.system(size: 13, weight: .semibold))
                Text(provider == .openai ? "ChatGPT subscription" : provider == .claude ? "Claude subscription" : provider == .grokBot ? "Grok Bot · Cursor sign-in" : "SuperGrok subscription")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 6)
            if busy { ProgressView().controlSize(.small).frame(width: 65) }
            else if connected {
                Label("Added", systemImage: "checkmark").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.sea)
            } else {
                Button("Connect") { action() }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(provider == .openai ? Color.white : Palette.sea)
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(provider == .openai ? Color(red: 0.19, green: 0.36, blue: 0.32) : Palette.wash,
                        in: RoundedRectangle(cornerRadius: 7))
            }
        }.padding(13).surfaceCard()
    }
}

