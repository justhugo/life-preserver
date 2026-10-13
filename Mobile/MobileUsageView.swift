import SwiftUI

private enum MobilePalette {
    // Identical light/dark values to the macOS Palette in Design.swift.
    static let background = adaptive(0xF6F5F1, 0x202524)
    static let card = adaptive(0xFFFFFF, 0x2A302F)
    static let ink = adaptive(0x243B39, 0xEDF1EC)
    static let secondary = adaptive(0x747D76, 0xA5B0A7)
    static let line = adaptive(0xE7E9E2, 0x3E4640)
    static let sea = adaptive(0x386B61, 0x9AC6B1)
    static let green = adaptive(0x5A8470, 0x95BBA4)
    static let amber = adaptive(0xA2722D, 0xE9BC72)
    static let red = adaptive(0xBC594B, 0xF19D89)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }

    static func meter(_ window: UsageWindow, stale: Bool) -> Color {
        if stale || window.usedPercent == nil { return secondary }
        switch window.pressure {
        case .critical, .exhausted: return red
        case .watch: return amber
        default: return green
        }
    }
}

struct MobileUsageView: View {
    @ObservedObject var store: MobileStore
    @AppStorage("appearance") private var appearance = "system"
    @State private var showSettings = CommandLine.arguments.contains("--show-settings")
    private var selectedColorScheme: ColorScheme? {
        appearance == "light" ? .light : appearance == "dark" ? .dark : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.preview { note("Sample data", symbol: "sparkles") }
                    if let message = store.message { note(message, symbol: "icloud.slash") }
                    if let snapshot = store.snapshot, snapshot.sharingEnabled, !snapshot.accounts.isEmpty {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 12)], alignment: .leading, spacing: 12) {
                                ForEach(snapshot.accounts) { item in
                                    MobileAccountCard(account: item.displayAccount, now: context.date)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Shared by your Mac \(snapshot.publishedAt.formatted(date: .abbreviated, time: .shortened))")
                            if let date = store.lastChecked { Text("iCloud checked \(date.formatted(date: .omitted, time: .shortened))") }
                            Text("Pull to refresh. Your Mac updates provider readings while it’s awake and Life Preserver is running.")
                        }.font(.footnote).foregroundStyle(MobilePalette.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 15) {
                            Image(systemName: "icloud").font(.largeTitle).foregroundStyle(MobilePalette.sea)
                            Text(store.snapshot?.sharingEnabled == false ? "Sharing is off." : "Let’s get you connected.").font(.system(.title2, design: .serif))
                            Text("On your Mac, open Life Preserver → Settings → iPhone & iPad and turn on sharing. Use the same iCloud account on both devices.")
                            Text("Your provider sign-ins stay on your Mac. This companion receives only your latest usage readings.").foregroundStyle(MobilePalette.secondary)
                            Button("Check iCloud") { Task { await store.refresh() } }.buttonStyle(.borderedProminent).disabled(store.refreshing)
                        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(MobilePalette.card, in: RoundedRectangle(cornerRadius: 20))
                    }
                }.padding(20).frame(maxWidth: 1000).frame(maxWidth: .infinity)
            }
            .background(MobilePalette.background)
            .navigationTitle("Life Preserver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MobilePalette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 7) {
                        Image("Preserver").resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
                        Text("Life Preserver").font(.custom("Baskerville-SemiBold", size: 20)).kerning(-0.45)
                    }.foregroundStyle(MobilePalette.ink).accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if store.refreshing { ProgressView().accessibilityLabel("Checking iCloud") }
                    else { Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } }.labelStyle(.iconOnly) }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Appearance").font(.headline)
                                Picker("Appearance", selection: $appearance) {
                                    Text("System").tag("system")
                                    Text("Light").tag("light")
                                    Text("Dark").tag("dark")
                                }.pickerStyle(.segmented)
                            }
                            Divider().overlay(MobilePalette.line)
                            Text("Version \(appVersion)").font(.caption).foregroundStyle(MobilePalette.secondary)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("About").font(.headline)
                                Text("Life Preserver keeps your remaining AI subscription usage in one place. This companion shows the latest readings your Mac shares through iCloud.")
                                    .font(.subheadline).foregroundStyle(MobilePalette.secondary)
                            }
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                connectionStatus(at: context.date)
                            }
                        }.padding(24).foregroundStyle(MobilePalette.ink)
                    }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
                }.presentationDetents([.medium, .large]).presentationBackground(MobilePalette.background)
                    .preferredColorScheme(selectedColorScheme)
            }
        }.tint(MobilePalette.sea).foregroundStyle(MobilePalette.ink)
            .preferredColorScheme(selectedColorScheme)
    }

    private func note(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.subheadline).foregroundStyle(MobilePalette.secondary)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(MobilePalette.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func connectionStatus(at now: Date) -> some View {
        let state = MobileLinkState.evaluate(snapshot: store.snapshot, lastChecked: store.lastChecked, checkFailed: store.checkFailed, at: now)
        let color = state == .healthy && !store.preview ? MobilePalette.green : state == .failed ? MobilePalette.red : MobilePalette.secondary
        let title = store.preview ? "Sample preview" : store.refreshing ? "Checking connection…" : state.title
        return VStack(alignment: .leading, spacing: 10) {
            Text("Mac connection").font(.headline)
            Button { Task { await store.refresh() } } label: {
                HStack(spacing: 8) {
                    if store.refreshing { ProgressView().controlSize(.small).tint(color) }
                    else { Image(systemName: state == .healthy && !store.preview ? "checkmark.circle.fill" : state == .failed ? "exclamationmark.circle" : "circle.dashed") }
                    Text(title).font(.subheadline.weight(.medium))
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.clockwise").font(.caption)
                }.padding(12).foregroundStyle(color)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).disabled(store.refreshing || store.preview)
                .accessibilityHint("Check the Mac’s shared readings through iCloud again")
            if store.preview {
                Text("The connection isn’t checked in sample previews.").font(.caption).foregroundStyle(MobilePalette.secondary)
            } else {
                if let date = store.snapshot?.publishedAt, store.snapshot?.sharingEnabled == true {
                    Text("Last shared \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(MobilePalette.secondary)
                }
                Text(connectionHelp(for: state)).font(.caption).foregroundStyle(MobilePalette.secondary)
            }
        }
    }

    private func connectionHelp(for state: MobileLinkState) -> String {
        switch state {
        case .healthy: return "Via iCloud. Tap above to check again."
        case .unchecked: return "Tap above to check iCloud for your Mac’s latest readings."
        case .waiting, .sharingOff:
            return "Turn on sharing in your Mac’s Settings → iPhone & iPad. Use the same iCloud account on both devices."
        case .stale:
            return "Make sure your Mac is awake, online, and running Life Preserver, then tap above to retry."
        case .failed:
            return store.message ?? "Check iCloud on this device, then tap above to retry."
        }
    }
}

private struct MobileAccountCard: View {
    let account: ProviderAccount
    let now: Date
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var stale: Bool { account.isStale(at: now) || account.error != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    MobileProviderMark(provider: account.provider)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(account.provider.name).font(.body.weight(.semibold)).lineLimit(1)
                            if !account.plan.isEmpty {
                                Text(account.plan).font(.caption2.weight(.medium)).lineLimit(1)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .foregroundStyle(MobilePalette.secondary)
                                    .background(MobilePalette.secondary.opacity(0.08), in: Capsule())
                                    .layoutPriority(-1)
                            }
                        }
                        if stale {
                            Text(account.error != nil ? "Connection needs attention" : "Reading needs an update")
                                .font(.caption2).foregroundStyle(MobilePalette.amber)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(MobilePalette.secondary.opacity(0.65))
                        .rotationEffect(.degrees(expanded ? 90 : 0)).accessibilityHidden(true)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("\(account.provider.name), \(account.plan)\(stale ? ", reading needs an update" : "")")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                .accessibilityHint(expanded ? "Collapse usage details" : "Expand usage details")
            if expanded {
                ForEach(account.windows) { meter($0) }
            } else {
                HStack(spacing: 16) {
                    ForEach(account.overviewWindows) { meter($0) }
                }
            }
            if account.windows.isEmpty { Text("No usage reading yet.").font(.subheadline).foregroundStyle(MobilePalette.secondary) }
            if expanded {
                Rectangle().fill(MobilePalette.line).frame(height: 0.7)
                VStack(alignment: .leading, spacing: 16) {
                    if let error = account.error { Text(error).font(.caption).foregroundStyle(MobilePalette.red) }
                    ForEach(account.windows) { window in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(window.title).font(.caption.weight(.medium))
                            Text(window.resetText(at: now)).font(.caption).foregroundStyle(MobilePalette.secondary)
                            if let reset = window.resetsAt { Text(reset.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(MobilePalette.secondary) }
                        }
                    }
                    if let date = account.updatedAt { Text("Provider checked \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(MobilePalette.secondary) }
                    else { Text("Provider hasn’t returned a reading yet.").font(.caption).foregroundStyle(MobilePalette.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(MobilePalette.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MobilePalette.line, lineWidth: 0.7))
    }

    private func meter(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(window.title).font(.caption).foregroundStyle(MobilePalette.secondary).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 5)
                Text(window.remainingPercent.map { "\(Int($0.rounded(.down)))%" } ?? "Not reported")
                    .font(.footnote.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(MobilePalette.meter(window, stale: stale)).fixedSize()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(MobilePalette.line.opacity(0.8))
                    if let remaining = window.remainingPercent, remaining > 0 {
                        Capsule().fill(MobilePalette.meter(window, stale: stale).opacity(stale ? 0.5 : 1))
                            .frame(width: max(3, geometry.size.width * remaining / 100))
                    }
                    HStack(spacing: 0) {
                        ForEach(0..<4) { _ in Spacer(); Rectangle().fill(MobilePalette.card.opacity(0.6)).frame(width: 1) }
                        Spacer()
                    }
                }
            }.frame(height: 5)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("\(window.title), \(window.remainingPercent.map { "\(Int($0.rounded(.down))) percent remaining" } ?? "unknown"), \(stale ? "stale reading, " : "")\(window.resetText(at: now))")
    }
}

private struct MobileProviderMark: View {
    let provider: Provider
    private var color: Color { provider == .claude ? MobilePalette.red : MobilePalette.ink }

    var body: some View {
        Image(provider == .grokBot ? "grok" : provider.rawValue)
            .resizable().renderingMode(.template).scaledToFit().foregroundStyle(color)
            .padding(4).frame(width: 32, height: 32)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}
