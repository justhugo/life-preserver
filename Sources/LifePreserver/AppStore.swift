import AppKit
import Combine
import ServiceManagement
import UserNotifications
#if SWIFT_PACKAGE
import LifePreserverCore
import LifePreserverProviders
import LifePreserverSync
#endif

@MainActor
final class AppStore: ObservableObject {
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Life Preserver", isDirectory: true)
    }
    @Published var accounts: [ProviderAccount] = []
    let mobileSharing = MobileSharing()
    @Published var demo = false
    @Published var refreshing = false
    @Published var connecting = false
    @Published var connectionError: String?
    @Published var persistenceError: String?
    @Published var settingsPage: SettingsPage = .accounts
    @Published var showOnboarding = false
    @Published var connectingProvider: Provider?
    @Published var refreshMinutes: Int { didSet { UserDefaults.standard.set(refreshMinutes, forKey: "refreshMinutes"); scheduleRefresh() } }
    @Published var showMenuPressure: Bool { didSet { UserDefaults.standard.set(showMenuPressure, forKey: "showMenuPressure") } }
    @Published var appearance: String { didSet { UserDefaults.standard.set(appearance, forKey: "appearance") } }
    @Published var notificationsEnabled: Bool { didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") } }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    var onShowSettings: (() -> Void)?
    var onShowPanel: (() -> Void)?
    private var connectionEpochs: [UUID: UUID] = [:]
    private let subscriptionsClient = SubscriptionUsageClient()
    private var subscriptionSignIn: SubscriptionSignIn?
    private var subscriptionTask: Task<Void, Never>?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var powerObserver: NSObjectProtocol?
    private var demoAccounts = SampleData.accounts()
    private let previewOnly: Bool
    private var ignoredConnections: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "ignoredConnections") ?? [])

    init(preview: Bool = false, diagnostic: Bool = false) {
        previewOnly = preview
        let defaults = UserDefaults.standard
        let interval = defaults.integer(forKey: "refreshMinutes")
        refreshMinutes = [1, 5, 15].contains(interval) ? interval : 5
        showMenuPressure = defaults.bool(forKey: "showMenuPressure")
        appearance = defaults.string(forKey: "appearance") ?? "system"
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        if preview { demo = true; return }
        load()
        if diagnostic { return }
        mobileSharing.update(accounts)
        showOnboarding = accounts.isEmpty && !defaults.bool(forKey: "onboarded")
        scheduleRefresh()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.timer?.invalidate(); self?.subscriptionsClient.cancelAll() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh(); await self?.refresh() }
        })
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            }
    }

    var visibleAccounts: [ProviderAccount] { demo ? demoAccounts : accounts }
    var overallPressure: Pressure { visibleAccounts.map { $0.reliablePressure() }.max() ?? .unknown }
    var hasUncertainReadings: Bool { visibleAccounts.contains { $0.reliablePressure() == .unknown } }
    var headline: String {
        if visibleAccounts.isEmpty { return "A little peace of mind." }
        if hasUncertainReadings { return "Let’s get our bearings." }
        switch overallPressure {
        case .exhausted: return "Time for a breather."
        case .critical: return "A little room to breathe."
        case .watch: return "Steady as you go."
        case .comfortable: return "Room to make waves."
        case .unknown: return "Let’s get our bearings."
        }
    }
    var summary: String {
        if visibleAccounts.isEmpty { return "All your AI limits. One calm little place." }
        if hasUncertainReadings { return "Some readings need an update." }
        if let tightest = visibleAccounts.max(by: { $0.pressure < $1.pressure }), tightest.pressure >= .watch {
            let count = visibleAccounts.filter { $0.pressure >= .watch }.count
            if count > 1 { return "\(count) providers are getting low. Check your reserves below." }
            return "\(tightest.provider.name) is \(tightest.pressure >= .critical ? "running low" : "getting a little full"). \(visibleAccounts.count > 1 ? "The rest is smooth sailing." : "Keep an eye on your reserves.")"
        }
        return "You have plenty of room to keep creating."
    }

    func finishOnboarding(preview: Bool = false) {
        demo = preview
        showOnboarding = false
        if !previewOnly { UserDefaults.standard.set(true, forKey: "onboarded") }
        onShowPanel?()
    }
    func showSettings(_ page: SettingsPage = .accounts) {
        settingsPage = page; onShowSettings?()
    }
    func exitDemo() { demo = false; showSettings() }

    func refresh() async {
        guard !refreshing, !previewOnly else { return }
        guard !demo else { return }
        refreshing = true
        defer { refreshing = false }
        let connectedIDs = accounts.filter { $0.kind != .manual && $0.kind != .demo }.map(\.id)
        await withTaskGroup(of: Void.self) { group in
            for id in connectedIDs { group.addTask { await self.refreshAccount(id) } }
        }
        save()
    }

    private func refreshAccount(_ id: UUID) async {
        guard let previous = accounts.first(where: { $0.id == id }) else { return }
        let epoch = connectionEpochs[id]
        do {
            let windows: [UsageWindow]
            let (credential, reading) = try await subscriptionsClient.read(previous)
            windows = reading
            guard connectionEpochs[id] == epoch else { return }
            if let index = accounts.firstIndex(where: { $0.id == id }) {
                accounts[index].label = credential.email ?? accounts[index].label
                accounts[index].plan = credential.plan ?? accounts[index].plan
            }
            guard connectionEpochs[id] == epoch, let index = accounts.firstIndex(where: { $0.id == id }) else { return }
            accounts[index].windows = windows
            accounts[index].updatedAt = Date()
            accounts[index].error = windows.isEmpty || windows.allSatisfy({ $0.usedPercent == nil }) ? "The provider hasn’t returned a subscription usage reading. Try refreshing shortly." : nil
            if previous.pressure < .critical, accounts[index].pressure >= .critical,
               notificationsEnabled { notifyLowUsage(accounts[index]) }
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            if connectionEpochs[id] == epoch, let index = accounts.firstIndex(where: { $0.id == id }) { accounts[index].error = error.localizedDescription }
        }
    }

    func connectCodex(replacing id: UUID? = nil) { connect(.openai, replacing: id) }

    /// Recover only Life Preserver's own legacy connection directories.
    func restoreConnections() async {
        guard !previewOnly, !connecting, accounts.isEmpty else { return }
        let directory = Self.supportDirectory.appendingPathComponent("Connections")
        guard let folders = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent), !ignoredConnections.contains(id.uuidString),
                  let credential = try? LegacyOpenAISession.importOwned(account: id) else { continue }
            accounts.append(ProviderAccount(id: id, provider: .openai, kind: .codex,
                label: credential.email ?? "Personal", plan: credential.plan ?? "ChatGPT"))
            save(); await refreshAccount(id); save(); break
        }
    }

    func cancelLogin() {
        subscriptionTask?.cancel(); subscriptionSignIn?.cancel()
        subscriptionSignIn = nil; connecting = false; connectingProvider = nil
    }

    func connect(_ provider: Provider, replacing id: UUID? = nil) {
        guard !connecting else { return }
        guard !previewOnly else { return }
        let signIn = SubscriptionSignIn()
        subscriptionSignIn = signIn
        connecting = true; connectingProvider = provider; connectionError = nil
        let accountID = id ?? UUID()
        subscriptionTask = Task {
            defer {
                if self.subscriptionSignIn === signIn {
                    self.subscriptionSignIn = nil; self.connecting = false; self.connectingProvider = nil
                }
            }
            do {
                let credential = try await signIn.signIn(provider: provider)
                try Task.checkCancellation()
                guard self.subscriptionSignIn === signIn else { return }
                subscriptionsClient.invalidate(accountID)
                connectionEpochs[accountID] = UUID()
                if SubscriptionUsageClient.sharingEnabled {
                    let owner = try await MobileSharing.validateOwner()
                    try await SharedProviderSessions.shared.share(credential,
                        account: SharedProviderAccount(id: accountID, provider: provider, plan: credential.plan ?? ""), expectedOwner: owner, replacing: true)
                }
                try CredentialVault.save(credential, account: accountID)
                let account = ProviderAccount(id: accountID, provider: provider,
                    kind: provider == .openai ? .codex : provider == .claude ? .claudeOAuth : provider == .grokBot ? .grokBotOAuth : .grokOAuth,
                    label: credential.email ?? "Personal", plan: credential.plan ?? "")
                if let index = accounts.firstIndex(where: { $0.id == accountID }) { accounts[index] = account }
                else { accounts.append(account) }
                demo = false; save()
                await refreshAccount(accountID); save()
            } catch is CancellationError {} catch {
                if self.subscriptionSignIn === signIn { connectionError = error.localizedDescription }
            }
        }
    }

    func remove(_ account: ProviderAccount) async {
        if account.kind != .manual && account.kind != .demo {
            do {
                if SubscriptionUsageClient.sharingEnabled { try await SharedProviderSessions.shared.remove(account.id) }
                try subscriptionsClient.disconnect(account.id)
            } catch { connectionError = error.localizedDescription; return }
        }
        accounts.removeAll { $0.id == account.id }; save()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { connectionError = "Allow Life Preserver in System Settings → General → Login Items." }
        } catch { connectionError = "Couldn’t update login items. \(error.localizedDescription)" }
    }

    func setNotifications(_ enabled: Bool) {
        guard enabled else { notificationsEnabled = false; return }
        Task {
            do {
                notificationsEnabled = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                if !notificationsEnabled { connectionError = "You can allow alerts in System Settings → Notifications → Life Preserver." }
            } catch { connectionError = "Notifications couldn’t be enabled. Please try again." }
        }
    }
    private func notifyLowUsage(_ account: ProviderAccount) {
        let content = UNMutableNotificationContent()
        content.title = "A little heads-up from Life Preserver"
        content.body = "\(account.provider.name) is running low. Open Life Preserver to check your remaining usage."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pressure-\(account.id)", content: content, trigger: nil))
    }
    private func scheduleRefresh() {
        guard !previewOnly else { return }
        timer?.invalidate()
        let interval = Double(refreshMinutes * 60) * (ProcessInfo.processInfo.isLowPowerModeEnabled ? 3 : 1)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer?.tolerance = min(30, interval * 0.1)
    }
    func shutdown() {
        mobileSharing.shutdown()
        timer?.invalidate(); subscriptionsClient.cancelAll(); subscriptionTask?.cancel(); subscriptionSignIn?.cancel()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
    }
    private func load() {
        let url = Self.supportDirectory.appendingPathComponent("accounts.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { accounts = try JSONDecoder().decode([ProviderAccount].self, from: Data(contentsOf: url)) }
        catch { persistenceError = "Your saved accounts couldn’t be read. Your original file has been kept." }
    }
    private func save() {
        if !previewOnly { mobileSharing.update(accounts) }
        guard !previewOnly, persistenceError == nil else { return }
        do {
            try FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let url = Self.supportDirectory.appendingPathComponent("accounts.json")
            try JSONEncoder().encode(accounts).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { persistenceError = "Your changes couldn’t be saved. Check that your disk has space and reopen the app." }
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case accounts = "Accounts", general = "General", mobile = "iPhone & iPad", privacy = "Privacy"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .accounts: "person.crop.circle"; case .general: "slider.horizontal.3"; case .mobile: "iphone"; case .privacy: "lock.shield" }
    }
}
