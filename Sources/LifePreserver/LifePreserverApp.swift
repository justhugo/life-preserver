import AppKit
import SwiftUI
import Combine
#if SWIFT_PACKAGE
import LifePreserverCore
import LifePreserverSync
#endif

@main
struct LifePreserverApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var store: AppStore!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var previewWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var menuTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--check-direct") {
            Task {
                if CommandLine.arguments.contains("--prepare-direct") {
                    UserDefaults.standard.set(true, forKey: "mobileSharingEnabled")
                }
                let check = AppStore(diagnostic: true)
                await check.refresh()
                for account in check.accounts {
                    print("Direct provider check: \(account.provider.rawValue): \(account.error ?? (account.updatedAt == nil ? "no reading" : "success"))")
                }
                check.mobileSharing.retry()
                await Task.yield()
                for _ in 0..<30 {
                    if !check.mobileSharing.busy { break }
                    try? await Task.sleep(for: .seconds(1))
                }
                print("Mobile sign-ins: \(check.mobileSharing.status)")
                check.shutdown()
                NSApp.terminate(nil)
            }
            return
        }
        // Read-only deployment check: no account store, provider refresh or upload.
        if CommandLine.arguments.contains("--check-icloud") {
            Task {
                do {
                    let cloud = PrivateUsageCloud()
                    _ = try await cloud.ownerID()
                    let accounts = try await SharedProviderSessions.shared.accounts()
                    print("iCloud available. Shared provider connections: \(accounts.count).")
                } catch { print(PrivateUsageCloud.message(for: error)) }
                NSApp.terminate(nil)
            }
            return
        }
        let preview = CommandLine.arguments.contains("--preview")
        store = AppStore(preview: preview)
        store.onShowSettings = { [weak self] in self?.showSettings() }
        store.onShowPanel = { [weak self] in
            self?.onboardingWindow?.close()
            self?.showPopover()
        }
        setupMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = BrandAssets.menuBarImage
            button.imagePosition = .imageLeading
            button.target = self; button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Life Preserver. AI usage at a glance.")
        }
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        let controller = NSHostingController(rootView: UsagePanel(store: store))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateMenuBar() }
        }.store(in: &subscriptions)
        updateMenuBar()
        menuTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMenuBar() }
        }
        menuTimer?.tolerance = 15
        if preview {
            showPreviewWindow()
        } else if store.showOnboarding { showOnboarding() }
        if !preview { Task { await store.restoreConnections(); await store.refresh() } }
    }

    private func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let application = NSMenu(); appItem.submenu = application
        application.addItem(withTitle: "Settings…", action: #selector(settingsAction), keyEquivalent: ",").target = self
        application.addItem(.separator())
        application.addItem(withTitle: "Quit Life Preserver", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }
    @objc private func settingsAction() { store.showSettings() }
    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Life Preserver", action: #selector(openAction), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Settings…", action: #selector(settingsAction), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Life Preserver", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
        } else if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }
    @objc private func openAction() { showPopover() }
    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.contentViewController?.view.layoutSubtreeIfNeeded()
        if let size = popover.contentViewController?.view.fittingSize { popover.contentSize = size }
        let imageRect = button.cell?.imageRect(forBounds: button.bounds) ?? button.bounds
        let anchor = NSRect(x: imageRect.midX - 0.5, y: button.bounds.minY, width: 1, height: button.bounds.height)
        popover.show(relativeTo: anchor, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func updateMenuBar() {
        guard let button = statusItem.button else { return }
        if store.showMenuPressure, !store.hasUncertainReadings,
           let remaining = store.visibleAccounts.compactMap({ $0.tightestWindow?.remainingPercent }).min() {
            button.title = " \(Int(remaining.rounded(.down)))%"
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        } else { button.title = "" }
        button.toolTip = store.demo ? "Life Preserver · sample data" : "Life Preserver · \(store.headline)"
    }
    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Life Preserver Settings", view: SettingsView(store: store), size: NSSize(width: 690, height: 590))
        }
        settingsWindow?.center(); settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func showOnboarding() {
        onboardingWindow = makeWindow(title: "Welcome to Life Preserver", view: OnboardingView(store: store), size: NSSize(width: 500, height: 685))
        onboardingWindow?.center(); onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func showPreviewWindow() {
        previewWindow = makeWindow(title: "Life Preserver · Preview", view: UsagePanel(store: store), size: NSSize(width: 396, height: 720))
        previewWindow?.center(); previewWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func makeWindow<Content: View>(title: String, view: Content, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(Palette.background)
        let host = NSHostingController(rootView: view.padding(.top, 24).background(Palette.background))
        host.sizingOptions = [.preferredContentSize]
        window.contentViewController = host
        window.setContentSize(NSSize(width: size.width, height: size.height + 24))
        window.initialFirstResponder = nil
        window.delegate = self
        return window
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showPopover() }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { menuTimer?.invalidate(); store?.shutdown() }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === onboardingWindow { store.cancelLogin() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
