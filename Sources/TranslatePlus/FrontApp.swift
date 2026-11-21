import AppKit
import ApplicationServices

/// Talks to the app you were working in: reads its selected text and pastes the result back.
/// Both need the Accessibility permission; without it the panel simply opens empty and Insert only copies.
enum FrontApp {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks for the Accessibility permission, opening one thing only.
    ///
    /// The first request from a build makes macOS show its own prompt, which is also what puts the app
    /// into the Accessibility list; that prompt has a button to System Settings. macOS shows it once,
    /// so later requests open the list in System Settings directly.
    static func requestTrust() {
        let defaults = UserDefaults.standard
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let askedBefore = defaults.string(forKey: "accessAskedBuild") == build
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if askedBefore {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else {
            defaults.set(build, forKey: "accessAskedBuild")
        }
    }

    /// The text selected in the focused field or document, read without touching the clipboard.
    static func selectedText() -> String? {
        guard isTrusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    static func sendPaste() { press(9) }

    /// Presses ⌘ with the given key in the app in front.
    private static func press(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// For apps that do not share their selection (many browsers and chat apps): presses ⌘C there
    /// and takes what lands on the clipboard. Nil when nothing was copied.
    @MainActor
    static func copySelection() async -> String? {
        guard isTrusted else { return nil }
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        press(8)
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(25))
            if pasteboard.changeCount != before { break }
        }
        guard pasteboard.changeCount != before else { return nil }
        return Clipboard.takeFresh()
    }
}

/// Text that was copied and not yet used by the window.
@MainActor
enum Clipboard {
    /// The clipboard state already seen, so the same copy is never translated twice
    /// and nothing copied before the app started is picked up.
    private static var seen = NSPasteboard.general.changeCount
    /// Password managers mark what they copy with these types. Such text is never taken.
    private static let secret = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                                 "com.agilebits.onepassword"].map { NSPasteboard.PasteboardType($0) }

    /// Text copied since the last call, or nil.
    static func takeFresh() -> String? {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != seen else { return nil }
        seen = pasteboard.changeCount
        let types = pasteboard.types ?? []
        guard !secret.contains(where: types.contains),
              let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// Called after the app itself writes to the clipboard, and at launch.
    static func markSeen() { seen = NSPasteboard.general.changeCount }
}
