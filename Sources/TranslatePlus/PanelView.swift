import SwiftUI

struct PanelView: View {
    @ObservedObject var model: TranslatorModel
    let panel: TranslatorPanel
    @FocusState private var inputFocused: Bool

    var body: some View {
        Group {
            if model.showingSettings {
                SettingsView(model: model)
            } else {
                translator
            }
        }
        .padding(14)
        .frame(width: TranslatorPanel.size.width, height: TranslatorPanel.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.12)))
        .onChange(of: model.input) { _, _ in model.inputChanged() }
        .onChange(of: model.focusTick) { _, _ in inputFocused = true }
        .onChange(of: model.showingSettings) { _, showing in if !showing { inputFocused = true } }
    }

    private var translator: some View {
        VStack(spacing: 10) {
            header
            editor(text: $model.input, placeholder: model.activeMode.placeholder)
                .focused($inputFocused)
                .frame(height: 138)
            controls
            if model.needsAccess { accessNotice }
            if let engine = model.unavailable { unavailableNotice(engine) }
            editor(text: $model.output, placeholder: resultPlaceholder)
                .frame(maxHeight: .infinity)
            footer
        }
        .onAppear { inputFocused = true }
    }

    private var resultPlaceholder: String {
        if model.isRunning { return "Working…" }
        return model.usesGoogle ? "Translation appears as you type" : "Press ⌘↩"
    }

    /// From which language, into which, and a button to turn the pair around.
    private var languagePickers: some View {
        HStack(spacing: 6) {
            Picker("From", selection: $model.source) {
                Text("Detect language").tag(Language?.none)
                Divider()
                ForEach(Language.all) { Text($0.name).tag(Language?.some($0)) }
            }
            .labelsHidden()
            .fixedSize()
            .help("The language of your text")

            Button { model.swapLanguages() } label: {
                Image(systemName: "arrow.left.arrow.right").font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(model.swapLanguage == nil)
            .help("Swap the languages and translate the result back")

            Picker("To", selection: $model.target) {
                ForEach(Language.all) { Text($0.name).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .help("The language to translate into")
        }
    }

    /// Who answers. All three engines are always listed, so it is clear what can be switched on;
    /// choosing one that is off explains how to get it.
    private var header: some View {
        HStack(spacing: 8) {
            Picker("Engine", selection: Binding(get: { model.activeEngine }, set: { model.choose($0) })) {
                ForEach(Engine.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Google is instant. Claude and ChatGPT read more naturally and use your own plan. ⌘G switches.")

            if model.hasAssistant {
                Picker("Mode", selection: $model.mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Improve fixes grammar and phrasing without translating. ⌘1  ⌘2")
            }

            Spacer(minLength: 0)

            iconButton(model.pinned ? "pin.fill" : "pin", active: model.pinned,
                       help: model.pinned ? "Pinned: stays open (⌘P)" : "Keep open when clicking elsewhere (⌘P)") {
                model.pinned.toggle()
            }
            iconButton("gearshape", active: false, help: "Settings (⌘,)") { model.showingSettings = true }
        }
    }

    /// The same box for every header icon, so they sit on one line whatever their shapes.
    private func iconButton(_ symbol: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// The languages, and the button that asks an assistant.
    private var controls: some View {
        HStack(spacing: 8) {
            if model.activeMode == .translate {
                languagePickers
            } else {
                Text("Keeps the language and your wording").font(.callout).foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if model.isRunning { ProgressView().controlSize(.small) }
            if !model.usesGoogle {
                Button(model.activeMode.title) { model.run() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("⌘↩")
            }
        }
    }

    /// Shown after the shortcut, while the app is not allowed to read the selection.
    private var accessNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised").foregroundStyle(.secondary)
            Text("To pick up the text you selected, Translate That needs the Accessibility permission. Until then, copy the text first (⌘C), then press the shortcut.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Allow…") { FrontApp.requestTrust() }
            Button { model.needsAccess = false } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Dismiss")
        }
        .padding(10)
        .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        // Goes away by itself once the permission is given.
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            if FrontApp.isTrusted { model.needsAccess = false }
        }
    }

    /// Shown after choosing an engine that is not switched on yet.
    private func unavailableNotice(_ engine: Engine) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(model.unavailableReason(engine))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Open Settings") { model.showingSettings = true }
            Button { model.unavailable = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Dismiss")
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let error = model.errorText {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .help(error)
            } else {
                Text(model.note).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { model.swapIntoInput() } label: { Image(systemName: "arrow.up") }
                .help("Move the result up to work on it again")
            Button("Copy") { panel.copyAndClose() }.help("Copy and close (⇧⌘C)")
            Button("Insert") { panel.insert() }.help("Paste into the app you came from (⇧⌘↩)")
        }
        .font(.callout)
        .disabled(model.output.isEmpty && model.errorText == nil)
    }

    private func editor(text: Binding<String>, placeholder: String) -> some View {
        TextEditor(text: text)
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
            .background(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Shown in place of the translator when the gear is clicked.
struct SettingsView: View {
    @ObservedObject var model: TranslatorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings").font(.headline)
                Spacer()
                Button("Done") { model.showingSettings = false }.keyboardShortcut(.defaultAction)
            }

            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
            section {
                HStack {
                    Text("Open Translate That")
                    Spacer()
                    Button(model.recordingShortcut ? "Press the new shortcut…" : model.shortcut.label) {
                        if model.recordingShortcut { model.cancelRecording() } else { model.beginRecording() }
                    }
                    .help("Click, then press the keys you want. Esc cancels.")
                }
                if let problem = model.shortcutProblem {
                    Text(problem).font(.callout).foregroundStyle(.orange)
                } else {
                    caption("Works in any app. With text selected, it is translated straight away.")
                }
                Divider()
                switchRow("Translate copied text", isOn: $model.useClipboard)
                caption("When nothing is selected, text you copied since the window was last open is used.")
                Divider()
                switchRow("Launch at login", isOn: Binding(get: { model.launchAtLogin },
                                                           set: { model.launchAtLogin = $0 }))
                switchRow("Show in Dock", isOn: Binding(get: { model.showInDock }, set: {
                    model.showInDock = $0
                    if model.persists { TranslatorPanel.shared.applyDockSetting() }
                }))
            }

            section {
                Text("AI assistants").font(.subheadline.weight(.semibold))
                caption("""
                    If Claude Code or Codex is set up on this Mac, Translate That can ask it for more natural \
                    translations and for grammar fixes (Improve). It starts that program, which is already \
                    signed in as you. Translate That never sees your password or token and has no account of \
                    its own. Requests count against your own plan, and the text goes to that company.
                    """)
                Divider()
                assistantRow("Claude", program: "Claude Code", command: "claude",
                             found: model.claudeFound, isOn: $model.claudeEnabled)
                if model.claudeEnabled {
                    Picker("Claude model", selection: $model.claudeModel) {
                        ForEach(ClaudeCLI.Model.allCases) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                }
                Divider()
                assistantRow("ChatGPT", program: "Codex", command: "codex", note: "Experimental",
                             found: model.codexFound, isOn: $model.codexEnabled)
            }

            caption("Google Translate receives the text while you type. Nothing is stored on this Mac except these settings.")
            }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            caption("Translate That \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · homeapplabs.com")
        }
        .toggleStyle(.switch)
        .onAppear { model.findAssistants() }
    }

    /// One assistant: its switch, and whether its program is on this Mac.
    @ViewBuilder
    private func assistantRow(_ name: String, program: String, command: String, note: String? = nil,
                              found: Bool?, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name), through \(program)" + (note.map { " · \($0)" } ?? ""))
                switch found {
                case true?:
                    Label("\(program) found on this Mac", systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.green)
                case false?:
                    Text("\(program) not found. Install it and run “\(command)” in Terminal once to sign in.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                case nil:
                    Text("Looking for \(program)…").font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle(name, isOn: isOn).labelsHidden().disabled(found != true && !isOn.wrappedValue)
        }
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn).labelsHidden()
        }
    }

    private func section(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
