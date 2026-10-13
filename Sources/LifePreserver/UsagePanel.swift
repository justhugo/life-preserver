import SwiftUI
#if SWIFT_PACKAGE
import LifePreserverCore
#endif

struct UsagePanel: View {
    @ObservedObject var store: AppStore
    @State private var expanded: Set<UUID> = []
    @State private var measuredHeights: [String: CGFloat] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header.measurePanelPart("header")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if store.demo { demoBanner }
                    if let error = store.persistenceError { ErrorNote(message: error) }
                    if store.visibleAccounts.isEmpty { emptyState }
                    else {
                        SectionLabel(text: "USAGE REMAINING").padding(.horizontal, 2)
                        VStack(spacing: 9) {
                            ForEach(store.visibleAccounts) { account in
                                ProviderCard(account: account, expanded: expanded.contains(account.id), toggle: {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                        if expanded.contains(account.id) { expanded.remove(account.id) }
                                        else { expanded.insert(account.id) }
                                    }
                                })
                            }
                        }

                    }
                }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 19).measurePanelPart("content")
            }.scrollIndicators(.hidden)
            footer.measurePanelPart("footer")
        }
        .frame(width: 396, height: panelHeight)
        .onPreferenceChange(PanelPartHeights.self) { measuredHeights = $0 }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(store.appearance == "light" ? .light : store.appearance == "dark" ? .dark : nil)
        .onAppear { Task { await store.refresh() } }
        .onExitCommand { NSApp.keyWindow?.close() }
        .accessibilityElement(children: .contain)
    }

    private var panelHeight: CGFloat {
        if measuredHeights.count == 3 {
            return min(700, ceil(measuredHeights.values.reduce(0, +)))
        }
        if store.visibleAccounts.isEmpty { return 270 }
        let details = store.visibleAccounts.filter { expanded.contains($0.id) }.reduce(0) { $0 + 65 + $1.windows.count * 45 }
        return min(700, 135 + CGFloat(store.visibleAccounts.count) * 100 + CGFloat(details) + (store.demo ? 28 : 0))
    }
    private var header: some View {
        HStack(spacing: 8) {
            PreserverMark().frame(width: 27, height: 27)
            Wordmark()
            Spacer()
            if store.demo { Tag(text: "PREVIEW", color: Palette.blue) }
            Button { store.showSettings() } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 13)) }
                .buttonStyle(QuietButtonStyle()).focusable(false).focusEffectDisabled().help("Settings (⌘,)").accessibilityLabel("Open settings")
                .keyboardShortcut(",", modifiers: .command)
        }.padding(.horizontal, 20).padding(.top, 15).padding(.bottom, 14)
    }
    private var demoBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 10))
            Text("Sample data · not your live usage").font(.system(size: 10))
            Spacer(minLength: 0)
            Button("Connect") { store.exitDemo() }.font(.system(size: 10, weight: .semibold)).buttonStyle(.plain)
        }.foregroundStyle(Palette.blue)
    }
    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Connect your accounts.").font(.system(size: 18, design: .serif))
            Text("View your subscription usage for\nOpenAI, Claude, Grok, and Grok Bot.")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).lineSpacing(4)
            Button("Add your first provider") { store.showSettings() }.buttonStyle(PrimaryButtonStyle()).padding(.top, 5)
            Button("Take a look around") { store.demo = true }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.sea)
        }.padding(20).frame(maxWidth: .infinity).surfaceCard()
    }
    private var footer: some View {
        HStack(spacing: 5) {
            Button { Task { await store.refresh() } } label: {
                if store.refreshing { ProgressView().controlSize(.mini).frame(width: 12, height: 12) }
                else { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }
            }.buttonStyle(QuietButtonStyle()).disabled(store.refreshing || store.demo || !store.accounts.contains { $0.kind != .manual && $0.kind != .demo })
                .keyboardShortcut("r", modifiers: .command).help("Refresh live usage (⌘R)").accessibilityLabel("Refresh usage")
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(freshness(at: context.date)).font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            Spacer()

        }.padding(.horizontal, 17).padding(.vertical, 10)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 0.7) }
    }
    private func freshness(at now: Date) -> String {
        if store.demo { return "Preview · sample data" }
        if store.refreshing { return "Refreshing…" }
        let live = store.accounts.filter { $0.kind != .manual && $0.kind != .demo }
        if live.contains(where: { $0.error != nil }) { return "Couldn’t refresh · try again" }
        if live.isEmpty { return store.accounts.isEmpty ? "Ready when you are" : "Connect an account in Settings" }
        guard let oldest = live.compactMap(\.updatedAt).min() else { return "Waiting for first reading" }
        let minutes = max(0, Int(now.timeIntervalSince(oldest) / 60))
        return minutes == 0 ? "Updated just now" : "Updated \(minutes)m ago"
    }
}

struct ProviderCard: View {
    let account: ProviderAccount
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    ProviderMark(provider: account.provider)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(account.provider.name).font(.system(size: 13, weight: .semibold))
                            if !account.plan.isEmpty { Tag(text: account.plan) }
                        }
                        if account.error != nil || account.isStale() {
                            Text(subtitle).font(.system(size: 10)).foregroundStyle(statusColor)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.secondary.opacity(0.65)).rotationEffect(.degrees(expanded ? 90 : 0))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).focusable(false).focusEffectDisabled().accessibilityLabel("\(account.provider.name), \(subtitle). \(expanded ? "Collapse" : "Expand") details")
            if account.windows.isEmpty {
                Text(account.error ?? "Waiting for your first usage reading.").font(.system(size: 11))
                    .foregroundStyle(Palette.secondary).padding(.top, 12)
            } else {
                VStack(spacing: 11) {
                    if expanded {
                        ForEach(account.windows) { window in
                            QuotaBar(window: window, uncertain: account.error != nil || account.isStale())
                        }
                    } else {
                        HStack(spacing: 15) {
                            ForEach(account.overviewWindows) { window in
                                QuotaBar(window: window, uncertain: account.error != nil || account.isStale())
                            }
                        }
                    }

                }.padding(.top, 10)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Rectangle().fill(Palette.line).frame(height: 0.7)
                    if let error = account.error { Text(error).font(.system(size: 10)).foregroundStyle(Palette.red).fixedSize(horizontal: false, vertical: true) }
                    ForEach(account.windows) { window in
                        HStack {
                            Text(window.title).foregroundStyle(Palette.secondary)
                            Spacer()
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                Text(window.resetText(at: context.date)).foregroundStyle(Palette.ink)
                            }
                        }.font(.system(size: 10))
                        .help(window.resetsAt.map { $0.formatted(date: .complete, time: .shortened) } ?? "The provider did not supply a reset time")
                    }
                    HStack(spacing: 4) {
                        Image(systemName: account.kind == .manual ? "pencil" : "lock.shield").font(.system(size: 9))
                        Text(account.kind == .demo ? "Sample data" : "Live subscription usage")
                        Spacer()
                        Link(destination: account.provider.usageURL) {
                            Label("Open usage", systemImage: "arrow.up.right").foregroundStyle(Palette.sea)
                        }
                    }.font(.system(size: 10)).foregroundStyle(Palette.secondary).padding(.top, 3)
                    if account.kind != .demo {
                        Text(account.label).font(.system(size: 9)).foregroundStyle(Palette.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }.padding(.top, 13)
            }
        }.padding(12).surfaceCard()
    }
    private var subtitle: String {
        if account.error != nil { return "Connection needs attention" }
        if account.isStale() { return "Reading needs an update" }
        if account.kind == .manual { return "Manual reading · \(account.pressure.label.lowercased())" }
        return account.pressure.label
    }
    private var statusColor: Color {
        account.error != nil || account.isStale() ? Palette.amber : Palette.pressure(account.pressure)
    }
}

struct QuotaBar: View {
    let window: UsageWindow
    var uncertain = false
    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title).font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 5)
                if let remaining = window.remainingPercent {
                    Text("\(Int(remaining.rounded(.down)))%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(uncertain ? Palette.secondary : Palette.pressure(window.pressure))
                } else { Text("Not reported").font(.system(size: 10)).foregroundStyle(Palette.secondary) }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.line.opacity(0.8))
                    if let remaining = window.remainingPercent, remaining > 0 {
                        Capsule().fill(uncertain ? Palette.secondary.opacity(0.5) : Palette.pressure(window.pressure))
                            .frame(width: max(3, geo.size.width * remaining / 100))
                    }
                    HStack(spacing: 0) {
                        ForEach(0..<4) { _ in Spacer(); Rectangle().fill(Palette.surface.opacity(0.6)).frame(width: 1) }
                        Spacer()
                    }
                }
            }.frame(height: 4)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("\(window.title): \(window.remainingPercent.map { "\(Int($0)) percent remaining" } ?? "not reported")\(uncertain ? ", last known reading" : "")")
    }
}

private struct PanelPartHeights: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
private extension View {
    func measurePanelPart(_ part: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: PanelPartHeights.self, value: [part: geometry.size.height])
        })
    }
}
