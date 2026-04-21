import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private var iconTimer: Timer?
    private var blinkOn: Bool = true

    // Keep for backward compat with TxemAI_MLXApp.setServerState(_:)
    private(set) var serverState: ServerStateViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        startIconTimer()
    }

    func setServerState(_ state: ServerStateViewModel) {
        serverState = state
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = currentBrainImage()

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    // MARK: - Icon

    private func startIconTimer() {
        iconTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.blinkOn.toggle()
                self.statusItem?.button?.image = self.currentBrainImage()
            }
        }
    }

    private func currentBrainImage() -> NSImage {
        switch ServerManager.shared.state {
        case .stopped:
            let img = NSImage(systemSymbolName: "brain",
                              accessibilityDescription: "Server stopped")!
            img.isTemplate = true
            return img

        case .starting:
            let symbol = blinkOn ? "brain.fill" : "brain"
            return coloredSymbol(name: symbol, color: .systemOrange)

        case .running:
            return coloredSymbol(name: "brain.fill", color: .systemBlue)

        case .error:
            return coloredSymbol(name: "brain.fill", color: .systemRed)
        }
    }

    private func coloredSymbol(name: String, color: NSColor) -> NSImage {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return NSImage()
        }
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        return base.withSymbolConfiguration(config) ?? base
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        buildMenu(menu)
    }

    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let mgrState = ServerManager.shared.state
        let vm = ServerStateViewModel.shared

        // ── Section 1: Server status ──────────────────────────────────────────

        let statusItem = NSMenuItem()
        statusItem.isEnabled = false
        switch mgrState {
        case .stopped:
            statusItem.attributedTitle = colored("○ Stopped", .secondaryLabelColor)
        case .starting:
            statusItem.attributedTitle = colored("◐ Starting...", .systemOrange)
        case .running(let port):
            statusItem.attributedTitle = colored("● Running on port \(port)", .systemGreen)
        case .error(let msg):
            statusItem.attributedTitle = colored("✗ Error: \(msg)", .systemRed)
        }
        menu.addItem(statusItem)

        // ── Section 2: Loaded model (only when running) ───────────────────────

        guard case .running = mgrState else {
            appendActions(to: menu, mgrState: mgrState)
            return
        }

        menu.addItem(.separator())
        let modelItem = NSMenuItem()
        modelItem.isEnabled = false
        if let loaded = vm.models.first(where: { $0.status == .loaded }) {
            modelItem.title = "Model: \(loaded.name)"
        } else {
            modelItem.attributedTitle = colored("No model loaded", .secondaryLabelColor)
        }
        menu.addItem(modelItem)

        // ── Section 3: Metrics (only when a model is loaded) ─────────────────

        if vm.models.first(where: { $0.status == .loaded }) != nil {
            let m = vm.metrics
            let cacheEfficiency: Double = m.totalPrefillTokens > 0
                ? Double(m.cachedTokens) / Double(m.totalPrefillTokens) * 100.0
                : 0.0

            menu.addItem(.separator())
            for line in [
                String(format: "Throughput: %.1f t/s",     m.tokensPerSecond),
                String(format: "Memory: %.1f GB used",     m.memoryUsedGB),
                String(format: "Cache hit: %.0f%%",        m.cacheHitPercent),
                String(format: "Prefill: %.1f t/s",        m.promptProcessingTps),
                "Cached tokens: \(m.cachedTokens)",
                String(format: "Cache efficiency: %.0f%%", cacheEfficiency),
                String(format: "Memory pressure: %.0f%%",  m.memoryPressurePercent),
            ] {
                let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        appendActions(to: menu, mgrState: mgrState)
    }

    /// Appends the start/stop, open, and quit items to the menu.
    private func appendActions(to menu: NSMenu, mgrState: ServerManager.ServerState) {
        menu.addItem(.separator())

        switch mgrState {
        case .stopped, .error:
            menu.addItem(action("Start Server",    #selector(startServerAction)))
        case .running, .starting:
            menu.addItem(action("Stop Server",     #selector(stopServerAction)))
        }

        menu.addItem(.separator())
        menu.addItem(action("Open CortexML",          #selector(openMainWindowAction)))
        menu.addItem(.separator())

        let quitItem = action("Quit",              #selector(quitAction))
        quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)
    }

    // MARK: - Convenience helpers

    private func colored(_ string: String, _ color: NSColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.foregroundColor: color])
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Action Handlers

    @objc private func startServerAction() {
        let apiKey = UserDefaults.standard.string(forKey: "cortex_api_key") ?? ""
        Task {
            try? await ServerManager.shared.start(apiKey: apiKey)
        }
    }

    @objc private func stopServerAction() {
        ServerManager.shared.stop()
    }

    @objc private func openMainWindowAction() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitAction() {
        if case .running = ServerManager.shared.state {
            ServerManager.shared.stop()
        }
        NSApp.terminate(nil)
    }
}
