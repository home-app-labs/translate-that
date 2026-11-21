import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Debug.snapshotDirectory != nil { TranslatorModel.shared.persists = false }
        TranslatorModel.shared.registerShortcut()
        TranslatorModel.shared.findAssistants()
        setUpStatusItem()
        Debug.runHooks()
    }

    /// Opening the app again (Spotlight, Finder) shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        TranslatorPanel.shared.show(below: anchor)
        return false
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "translate", accessibilityDescription: "Translate That")
            ?? NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Translate That")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        menu.delegate = self
        statusItem = item
    }

    /// The icon's frame in screen coordinates.
    private var anchor: NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// Left click opens the translator, right click (or ⌃click) the menu.
    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            TranslatorPanel.shared.toggle(below: anchor)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let model = TranslatorModel.shared
        menu.removeAllItems()

        add(menu, "Open Translate That    \(model.shortcut.label)", #selector(openPanel))
        if let problem = model.shortcutProblem {
            add(menu, problem, nil)
        }
        if !FrontApp.isTrusted {
            add(menu, "Allow Accessibility to Read the Selection and Insert…", #selector(requestTrust))
        }
        menu.addItem(.separator())
        let settings = add(menu, "Settings…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(.separator())
        let quit = add(menu, "Quit Translate That", #selector(NSApplication.terminate(_:)))
        quit.target = NSApp
        quit.keyEquivalent = "q"
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = action == nil ? nil : self
        menu.addItem(item)
        return item
    }

    @objc private func openPanel() {
        TranslatorModel.shared.showingSettings = false
        TranslatorPanel.shared.show(below: anchor)
    }

    @objc private func openSettings() {
        TranslatorModel.shared.showingSettings = true
        TranslatorPanel.shared.show(below: anchor)
    }

    @objc private func requestTrust() { FrontApp.requestTrust() }
}

/// Developer aids, driven by environment variables:
/// TRANSLATEPLUS_SNAPSHOT_DIR=/path opens the panel, saves panel.png there and quits,
/// TRANSLATEPLUS_SNAPSHOT_DELAY=8 waits that many seconds first (default 6),
/// TRANSLATEPLUS_SHOW=settings opens the settings instead of the translator,
/// TRANSLATEPLUS_DEMO_CLAUDE=1 and TRANSLATEPLUS_DEMO_CODEX=1 switch the assistants on for the snapshot,
/// TRANSLATEPLUS_DEMO_TEXT=… fills the input and runs it,
/// TRANSLATEPLUS_DEMO_MODE=translate|improve and TRANSLATEPLUS_DEMO_ENGINE=google|claude|codex pick what runs,
/// TRANSLATEPLUS_CLAUDE_PATH and TRANSLATEPLUS_CODEX_PATH point at stand-in programs.
/// A snapshot run never changes saved settings and never registers the shortcut.
@MainActor
enum Debug {
    static let snapshotDirectory = ProcessInfo.processInfo.environment["TRANSLATEPLUS_SNAPSHOT_DIR"]

    static func runHooks() {
        guard let snapshotDirectory else { return }
        let env = ProcessInfo.processInfo.environment
        let directory = URL(fileURLWithPath: snapshotDirectory, isDirectory: true)
        let panel = TranslatorPanel.shared
        let model = panel.model
        panel.staysOpen = true
        model.claudeEnabled = env["TRANSLATEPLUS_DEMO_CLAUDE"] != nil
        model.codexEnabled = env["TRANSLATEPLUS_DEMO_CODEX"] != nil
        if let mode = env["TRANSLATEPLUS_DEMO_MODE"].flatMap(Mode.init) { model.mode = mode }
        model.activeEngine = env["TRANSLATEPLUS_DEMO_ENGINE"].flatMap(Engine.init) ?? .google
        model.showingSettings = env["TRANSLATEPLUS_SHOW"] == "settings"
        // TRANSLATEPLUS_DEMO_CHOOSE=claude|codex clicks that engine in the window, switched on or not.
        if let choice = env["TRANSLATEPLUS_DEMO_CHOOSE"].flatMap(Engine.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { model.choose(choice) }
        }
        panel.show(below: nil)
        if let text = env["TRANSLATEPLUS_DEMO_TEXT"] {
            model.input = text
            model.run()
        }
        let delay = env["TRANSLATEPLUS_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 6
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            panel.snapshot(to: directory.appendingPathComponent("panel.png"))
            let info = "trusted=\(FrontApp.isTrusted) running=\(model.isRunning) error=\(model.errorText ?? "none")\n---\n\(model.output)\n"
            try? info.write(to: directory.appendingPathComponent("info.txt"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }
}
