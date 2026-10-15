import AppKit
import Combine
import KeyboardShortcuts
import OTMCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var panel: PanelController!
    private var settings: SettingsWindowController!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Build-time packaging check (scripts/build-app.sh): touching the Recorder resolves
        // KeyboardShortcuts' Bundle.module, which traps if the resource bundle is not found.
        if ProcessInfo.processInfo.environment["GLANCE_SELFTEST"] == "1" {
            _ = KeyboardShortcuts.RecorderCocoa(for: .togglePanel)
            print("selftest ok")
            exit(0)
        }
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
            let alert = NSAlert()
            alert.messageText = "Glance is already running"
            alert.informativeText = "Quit the other Glance first, then open this one again."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let dir = ConfigStore.defaultDirectory()
        model = AppModel(
            configStore: ConfigStore(directory: dir), cache: IssueCache(directory: dir),
            tokenStore: KeychainTokenStore(), scheduler: RefreshScheduler(),
            makeClient: { site, email, token in JiraClient(site: site, email: email, token: token) }
        )
        setUpMainMenu()
        panel = PanelController(model: model)
        settings = SettingsWindowController(model: model) { [weak self] in
            guard let self, !self.model.config.accounts.isEmpty else { return }
            self.panel.show()
            Task { await self.model.refresh(.manual) }
        }
        panel.chart.onMessage = { [weak self] msg in self?.handle(msg) }
        setUpStatusItem()
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in self?.panel.toggle() }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.refresh(.timer) }
        }
        model.$renderState
            .map { $0.status.banner != nil }
            .removeDuplicates()
            .sink { [weak self] warn in self?.updateIcon(warning: warn) }
            .store(in: &bag)

        if model.isConfigured {
            panel.show()
            Task { await model.refresh(.manual) }
        } else {
            settings.show()
        }
    }

    /// Accessory apps never show the menu bar, but ⌘V/⌘C/⌘A/⌘X/⌘Z key equivalents only route through a main menu.
    private func setUpMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        main.addItem(appItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z").keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(warning: false)
        let menu = NSMenu()
        menu.addItem(withTitle: "Show / Hide Panel", action: #selector(togglePanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Glance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func updateIcon(warning: Bool) {
        let name = warning ? "exclamationmark.triangle" : "circle.hexagongrid"
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Glance")
    }

    @objc private func togglePanel() { panel.toggle() }
    @objc private func refreshNow() { Task { await model.refresh(.manual) } }
    @objc private func openSettings() { settings.show() }

    // MARK: - Messages from the chart

    private func handle(_ msg: [String: Any]) {
        switch msg["type"] as? String {
        case "openIssue":
            if let key = msg["key"] as? String, let url = model.issueURL(key: key) { NSWorkspace.shared.open(url) }
        case "refetch":
            Task { await model.refresh(.manual) }
        case "hide":
            panel.hide()
        case "openSettings":
            let tab = (msg["tab"] as? String).flatMap(SettingsTab.init(rawValue:))
            settings.show(tab: tab, accountId: tab == .accounts || tab == .axes ? model.activeAccount?.id : nil)
        case "newPreset":
            if model.config.accounts.isEmpty {
                settings.show(tab: .accounts)
            } else {
                settings.showNewPreset(accountId: msg["accountId"] as? String)
            }
        case "selectPreset":
            guard let id = msg["id"] as? String else { break }
            switch model.selectPreset(id: id) {
            case .selected: Task { await model.refresh(.manual) }
            case .accountMissing: settings.show(tab: .presets)
            case .notFound: break
            }
        case "quickSetting":
            if let key = msg["key"] as? String { model.setQuickSetting(key: key, value: JSONValue(any: msg["value"])) }
        case "saveDefaultView":
            if let yaw = msg["yaw"] as? Double, let pitch = msg["pitch"] as? Double, let zoom = msg["zoom"] as? Double,
               yaw.isFinite, pitch.isFinite, zoom.isFinite {
                model.saveDefaultView(yaw: yaw, pitch: pitch, zoom: zoom)
            }
        case "saveLastView":
            if let yaw = msg["yaw"] as? Double, let pitch = msg["pitch"] as? Double, let zoom = msg["zoom"] as? Double,
               yaw.isFinite, pitch.isFinite, zoom.isFinite {
                model.saveLastView(yaw: yaw, pitch: pitch, zoom: zoom)
            }
        default:
            break
        }
    }
}
