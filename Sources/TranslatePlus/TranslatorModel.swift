import AppKit
import ServiceManagement

enum Mode: String, CaseIterable, Identifiable {
    case translate, improve
    var id: String { rawValue }

    var title: String {
        switch self {
        case .translate: return "Translate"
        case .improve: return "Improve"
        }
    }

    var placeholder: String {
        switch self {
        case .translate: return "Text to translate"
        case .improve: return "Text to fix: grammar, spelling, phrasing"
        }
    }
}

enum Engine: String, CaseIterable, Identifiable {
    case google, claude, codex
    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: return "Google"
        case .claude: return "Claude"
        case .codex: return "ChatGPT"
        }
    }
}

/// Everything the panel shows, plus the choices that are remembered between launches.
@MainActor
final class TranslatorModel: ObservableObject {
    static let shared = TranslatorModel()

    @Published var input = ""
    @Published var output = ""
    /// A quiet line under the result: detected language, "Copied".
    @Published var note = ""
    @Published var errorText: String?
    @Published var isRunning = false
    /// Keeps the panel open when another window is clicked.
    @Published var pinned = false
    /// Bumped each time the panel opens, so the view can focus the input.
    @Published var focusTick = 0

    @Published var mode: Mode { didSet { save(mode.rawValue, "mode"); optionsChanged() } }
    /// The engine for Translate.
    @Published var engine: Engine { didSet { save(engine.rawValue, "engine"); optionsChanged() } }
    /// The assistant for Improve, which Google cannot do.
    @Published var assistant: Engine { didSet { save(assistant.rawValue, "assistant") } }
    /// The language to translate from. Nil means: detect it.
    @Published var source: Language? { didSet { save(source?.code ?? "auto", "source"); optionsChanged() } }
    @Published var target: Language { didSet { save(target.code, "target"); optionsChanged() } }
    /// What Google last detected, so the languages can be swapped while the source is on Detect.
    @Published private(set) var detected: Language?
    @Published var claudeModel: ClaudeCLI.Model { didSet { save(claudeModel.rawValue, "claudeModel") } }

    // MARK: Settings

    @Published var showingSettings = false {
        didSet { if showingSettings { unavailable = nil } else { cancelRecording() } }
    }
    /// The engine that was chosen in the window while it is not switched on. The window explains why.
    @Published var unavailable: Engine?
    /// Both off by default: the app is a plain Google translator until an assistant is switched on in Settings.
    @Published var claudeEnabled: Bool { didSet { save(claudeEnabled, "claudeEnabled"); optionsChanged() } }
    @Published var codexEnabled: Bool { didSet { save(codexEnabled, "codexEnabled"); optionsChanged() } }
    /// When nothing is selected, translate what was copied since the window was last open.
    @Published var useClipboard: Bool { didSet { save(useClipboard, "useClipboard") } }
    /// Shown in the window when the shortcut could not read the selection for lack of permission.
    @Published var needsAccess = false
    /// The Dock icon gives people who do not use the shortcut something to click. On by default.
    @Published var showInDock: Bool { didSet { save(showInDock, "showInDock") } }
    /// Nil until Settings looked for the programs.
    @Published var claudeFound: Bool?
    @Published var codexFound: Bool?
    @Published private(set) var shortcut: Shortcut
    /// True while Settings waits for the new key combination.
    @Published private(set) var recordingShortcut = false
    /// Shown in Settings and in the menu when the shortcut could not be registered.
    @Published private(set) var shortcutProblem: String?

    private let defaults = UserDefaults.standard
    /// Debug snapshots must not overwrite the real choices or grab the real shortcut.
    var persists = true
    private var job: Task<Void, Never>?
    private var debounce: Task<Void, Never>?

    private init() {
        mode = defaults.string(forKey: "mode").flatMap(Mode.init) ?? .translate
        engine = defaults.string(forKey: "engine").flatMap(Engine.init) ?? .google
        let code = defaults.string(forKey: "target") ?? "en"
        target = Language.all.first { $0.code == code } ?? Language.all[0]
        let sourceCode = defaults.string(forKey: "source")
        source = Language.all.first { $0.code == sourceCode }
        claudeModel = defaults.string(forKey: "claudeModel").flatMap(ClaudeCLI.Model.init) ?? .sonnet
        claudeEnabled = defaults.bool(forKey: "claudeEnabled")
        codexEnabled = defaults.bool(forKey: "codexEnabled")
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? true
        useClipboard = defaults.object(forKey: "useClipboard") as? Bool ?? true
        assistant = defaults.string(forKey: "assistant").flatMap(Engine.init) ?? .claude
        if defaults.object(forKey: "shortcutKeyCode") != nil {
            shortcut = Shortcut(keyCode: defaults.integer(forKey: "shortcutKeyCode"),
                                modifiers: defaults.integer(forKey: "shortcutModifiers"))
        } else {
            shortcut = .standard
        }
    }

    private func save(_ value: Any, _ key: String) {
        if persists { defaults.set(value, forKey: key) }
    }

    /// The assistants switched on in Settings.
    var assistants: [Engine] { (claudeEnabled ? [.claude] : []) + (codexEnabled ? [.codex] : []) }
    var hasAssistant: Bool { !assistants.isEmpty }
    /// What the engine picker offers in the current mode.
    var engineChoices: [Engine] { activeMode == .translate ? [.google] + assistants : assistants }
    /// What the panel is doing right now. Without an assistant there is only translation.
    var activeMode: Mode { hasAssistant ? mode : .translate }

    /// The engine that will answer, whatever was saved before an assistant was switched off.
    var activeEngine: Engine {
        get {
            if activeMode == .translate { return engineChoices.contains(engine) ? engine : .google }
            return assistants.contains(assistant) ? assistant : assistants.first ?? .google
        }
        set {
            if activeMode == .translate { engine = newValue } else { assistant = newValue }
            if newValue != .google { assistant = newValue }
        }
    }

    /// Google answers instantly and for free, so it translates as you type. Assistants wait for ⌘↩.
    var usesGoogle: Bool { activeEngine == .google }

    /// A click in the window's engine picker.
    func choose(_ choice: Engine) {
        if choice == .google {
            unavailable = nil
            // Google cannot fix grammar, so choosing it means translating.
            if activeMode == .improve { mode = .translate }
            engine = .google
        } else if assistants.contains(choice) {
            unavailable = nil
            activeEngine = choice
        } else {
            unavailable = choice
        }
    }

    func unavailableReason(_ engine: Engine) -> String {
        let (name, program, found) = engine == .codex
            ? ("ChatGPT", "Codex", codexFound) : ("Claude", "Claude Code", claudeFound)
        if found == false {
            return "\(name) needs the \(program) program, which is not on this Mac. Settings explains how to add it."
        }
        return "\(name) is switched off. It can use \(program), already set up on this Mac. Switch it on in Settings."
    }

    func nextEngine() {
        let choices = engineChoices
        guard choices.count > 1, let index = choices.firstIndex(of: activeEngine) else { return }
        activeEngine = choices[(index + 1) % choices.count]
    }

    func inputChanged() {
        debounce?.cancel()
        guard usesGoogle else { return }
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { self?.run() }
        }
    }

    private func optionsChanged() {
        errorText = nil
        note = ""
        if usesGoogle { run() }
    }

    func run() {
        debounce?.cancel()
        job?.cancel()
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        errorText = nil
        note = ""
        guard !text.isEmpty else {
            output = ""
            isRunning = false
            return
        }
        isRunning = true

        let engine = activeEngine
        let source = source
        let target = target
        let system: String
        switch activeMode {
        case .translate: system = Prompts.translate(from: source, to: target)
        case .improve: system = Prompts.improve
        }
        let model = claudeModel

        job = Task { [weak self] in
            do {
                if engine == .google {
                    let result = try await GoogleTranslate.translate(text, from: source?.code, to: target.code)
                    guard let self, !Task.isCancelled else { return }
                    self.output = result.text
                    if source == nil, let code = result.detected {
                        self.detected = Language.all.first { $0.code == code }
                        if code != target.code { self.note = "Detected \(Language.named(code: code))" }
                    }
                } else {
                    var first = true
                    let answer = engine == .codex
                        ? CodexCLI.stream(system: system, text: text)
                        : ClaudeCLI.stream(system: system, text: text, model: model)
                    for try await piece in answer {
                        guard let self, !Task.isCancelled else { return }
                        if first { self.output = ""; first = false }
                        self.output += piece
                    }
                    guard let self, !Task.isCancelled else { return }
                    self.output = self.output.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.errorText = error.localizedDescription
            }
            guard let self, !Task.isCancelled else { return }
            self.isRunning = false
        }
    }

    func stop() {
        job?.cancel()
        isRunning = false
    }

    @discardableResult
    func copyOutput() -> Bool {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Clipboard.markSeen()
        note = "Copied"
        return true
    }

    /// The language the swap button would translate into: the chosen source, or the detected one.
    var swapLanguage: Language? {
        let candidate = source ?? detected
        return candidate == target ? nil : candidate
    }

    /// Turns the translation around: the result becomes the text, and it goes back into the other language.
    func swapLanguages() {
        guard let newTarget = swapLanguage else { return }
        let oldTarget = target
        let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
        job?.cancel()
        if !result.isEmpty { input = result; output = "" }
        // Set the pair without translating twice on the way.
        debounce?.cancel()
        source = oldTarget
        target = newTarget
    }

    /// Puts text picked up from the front app or the clipboard into the window and runs it.
    func take(_ text: String) {
        debounce?.cancel()
        input = text
        run()
    }

    func swapIntoInput() {
        guard !output.isEmpty else { return }
        input = output
        output = ""
        note = ""
    }

    // MARK: Shortcut

    /// Called once at launch.
    func registerShortcut() {
        guard persists else { return }
        if !ShortcutCenter.register(shortcut) {
            shortcutProblem = "\(shortcut.label) is taken by another app. Choose another shortcut."
        }
    }

    func beginRecording() {
        shortcutProblem = nil
        recordingShortcut = true
        ShortcutCenter.suspend()
    }

    func cancelRecording() {
        guard recordingShortcut else { return }
        recordingShortcut = false
        registerShortcut()
    }

    /// Takes the key press made while recording. Keeps the old shortcut when the new one is refused.
    func record(_ event: NSEvent) {
        guard let candidate = Shortcut(event: event) else {
            shortcutProblem = "Use ⌘, ⌃ or ⌥ together with a key."
            return
        }
        recordingShortcut = false
        guard persists else { shortcut = candidate; return }
        if ShortcutCenter.register(candidate) {
            shortcut = candidate
            shortcutProblem = nil
            defaults.set(candidate.keyCode, forKey: "shortcutKeyCode")
            defaults.set(candidate.modifiers, forKey: "shortcutModifiers")
        } else {
            let kept = ShortcutCenter.register(shortcut)
            shortcutProblem = "\(candidate.label) is taken by another app."
                + (kept ? " Still using \(shortcut.label)." : "")
        }
    }

    // MARK: Other settings

    /// Looks for Claude Code and Codex without blocking the window.
    func findAssistants() {
        Task.detached {
            let claude = ClaudeCLI.locate() != nil
            let codex = CodexCLI.locate() != nil
            await MainActor.run {
                TranslatorModel.shared.claudeFound = claude
                TranslatorModel.shared.codexFound = codex
            }
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Translate That: launch at login failed: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }
}
