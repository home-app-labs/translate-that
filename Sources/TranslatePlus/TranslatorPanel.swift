import AppKit
import SwiftUI
import Carbon.HIToolbox

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The floating translator window. It never activates the app, so the app you were typing in
/// stays frontmost and can receive the result.
@MainActor
final class TranslatorPanel: NSObject, NSWindowDelegate {
    static let shared = TranslatorPanel()
    static let size = NSSize(width: 480, height: 520)

    let model = TranslatorModel.shared
    /// Set by debug snapshots so the panel survives losing focus.
    var staysOpen = false
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var hiddenByFocusLoss = Date.distantPast

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Menu bar icon: open under the icon, or close.
    func toggle(below anchor: NSRect?) {
        if isVisible { hide(); return }
        // The click that lands on the icon first takes focus away and closes the panel; do not reopen it.
        if Date().timeIntervalSince(hiddenByFocusLoss) < 0.3 { return }
        model.showingSettings = false
        show(below: anchor)
        takeCopiedText()
    }

    /// Shortcut: translate whatever is selected in the front app, or close.
    func toggleFromShortcut() {
        if isVisible { hide(returnFocus: true); return }
        Task { @MainActor in
            // The selection, read directly; else copied with ⌘C; else whatever was copied by hand just before.
            var text = FrontApp.selectedText()
            if text == nil { text = await FrontApp.copySelection() }
            if text == nil, model.useClipboard { text = Clipboard.takeFresh() }
            model.needsAccess = !FrontApp.isTrusted
            model.showingSettings = false
            show(below: nil)
            if let text { model.take(text) }
        }
    }

    /// For opening from an icon: translate what was copied since the window was last open.
    func takeCopiedText() {
        if model.useClipboard, let text = Clipboard.takeFresh() { model.take(text) }
    }

    func show(below anchor: NSRect?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        var origin: NSPoint
        if let anchor {
            origin = NSPoint(x: anchor.midX - Self.size.width / 2, y: anchor.minY - Self.size.height - 6)
        } else {
            origin = NSPoint(x: area.midX - Self.size.width / 2,
                             y: area.minY + (area.height - Self.size.height) * 0.62)
        }
        origin.x = min(max(origin.x, area.minX), area.maxX - Self.size.width)
        origin.y = min(max(origin.y, area.minY), area.maxY - Self.size.height)
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: true)
        panel.makeKeyAndOrderFront(nil)
        model.focusTick += 1

        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.panel else { return event }
                return self.handle(event) ? nil : event
            }
        }
    }

    /// Closes the panel. With `returnFocus`, and when Translate That itself is the active app (it was opened
    /// from the Dock), the app that was in front before comes back, so an inserted result lands there.
    func hide(returnFocus: Bool = false) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        model.cancelRecording()
        panel?.orderOut(nil)
        guard returnFocus, NSApp.isActive else { return }
        if let previousApp, !previousApp.isTerminated { previousApp.activate() } else { NSApp.hide(nil) }
    }

    /// The app the user was in before Translate That came to the front.
    private var previousApp: NSRunningApplication?

    /// Remembers which other app was active last. Needed when the panel is opened from the Dock,
    /// because that click makes Translate That the active app.
    func trackFrontmostApp() {
        let own = ProcessInfo.processInfo.processIdentifier
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != own { previousApp = app }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != own else { return }
            MainActor.assumeIsolated { self?.previousApp = app }
        }
    }

    /// Shows or removes the Dock icon without closing the panel the switch sits in.
    func applyDockSetting() {
        let wasOpen = isVisible
        staysOpen = true
        NSApp.setActivationPolicy(model.showInDock ? .regular : .accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
            staysOpen = false
            if wasOpen { panel?.makeKeyAndOrderFront(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: PanelView(model: model, panel: self))
        return panel
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !staysOpen, !model.pinned, isVisible else { return }
        hiddenByFocusLoss = Date()
        hide()
    }

    // MARK: Actions

    func copyAndClose() {
        if model.copyOutput() { hide(returnFocus: true) }
    }

    /// Puts the result on the clipboard, closes the panel and pastes into the app underneath.
    func insert() {
        guard model.copyOutput() else { return }
        guard FrontApp.isTrusted else {
            model.note = "Copied. Allow Accessibility to paste automatically."
            FrontApp.requestTrust()
            return
        }
        // Opened from the Dock, the other app first has to come back to the front: give it a moment longer.
        let delay = NSApp.isActive ? 0.35 : 0.12
        hide(returnFocus: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { FrontApp.sendPaste() }
    }

    // MARK: Keys

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = Int(event.keyCode)

        // While Settings waits for a new shortcut, every key press belongs to it.
        if model.recordingShortcut {
            if key == kVK_Escape, flags.isEmpty { model.cancelRecording() } else { model.record(event) }
            return true
        }
        if flags == .command, key == kVK_ANSI_Comma {
            model.showingSettings.toggle()
            return true
        }
        if key == kVK_Escape {
            if model.showingSettings {
                model.showingSettings = false
            } else if model.isRunning, !model.usesGoogle {
                model.stop()
            } else {
                hide(returnFocus: true)
            }
            return true
        }
        if model.showingSettings { return false }

        if key == kVK_Return || key == kVK_ANSI_KeypadEnter {
            if flags == .command { model.run(); return true }
            if flags == [.command, .shift] { insert(); return true }
            return false
        }
        if flags == [.command, .shift], key == kVK_ANSI_C { copyAndClose(); return true }
        guard flags == .command else {
            // The app has no menu bar, so Redo needs the same help as the other editing keys below.
            if flags == [.command, .shift], key == kVK_ANSI_Z { return send(Selector(("redo:"))) }
            return false
        }

        switch key {
        case kVK_ANSI_1 where model.hasAssistant: model.mode = .translate
        case kVK_ANSI_2 where model.hasAssistant: model.mode = .improve
        case kVK_ANSI_G where model.hasAssistant: model.nextEngine()
        case kVK_ANSI_P: model.pinned.toggle()
        // An agent app has no Edit menu to route these.
        case kVK_ANSI_C: return send(#selector(NSText.copy(_:)))
        case kVK_ANSI_V: return send(#selector(NSText.paste(_:)))
        case kVK_ANSI_X: return send(#selector(NSText.cut(_:)))
        case kVK_ANSI_A: return send(#selector(NSText.selectAll(_:)))
        case kVK_ANSI_Z: return send(Selector(("undo:")))
        default: return false
        }
        return true
    }

    private func send(_ action: Selector) -> Bool {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    func snapshot(to url: URL) {
        guard let view = panel?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
