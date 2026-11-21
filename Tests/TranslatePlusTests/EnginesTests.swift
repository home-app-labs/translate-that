import XCTest
@testable import TranslatePlus

final class EnginesTests: XCTestCase {
    func testGoogleResponseJoinsSegmentsAndReadsDetectedLanguage() throws {
        let json = #"[[["Hi, how are you? ","Hallo, wie geht es dir? ",null,null,10],["This is a test.\n","Das ist ein Test.\n",null,null,3],["Second line.","Zweite Zeile.",null,null,3]],null,"de",null,null,null,1,[]]"#
        let result = try GoogleTranslate.parse(Data(json.utf8))
        XCTAssertEqual(result.text, "Hi, how are you? This is a test.\nSecond line.")
        XCTAssertEqual(result.detected, "de")
    }

    func testGoogleCompactResponseWithAndWithoutDetectedLanguage() throws {
        let detected = try GoogleTranslate.parseCompact(Data(#"[["Good morning","de"]]"#.utf8))
        XCTAssertEqual(detected, GoogleTranslate.Result(text: "Good morning", detected: "de"))
        let plain = try GoogleTranslate.parseCompact(Data(#"["Good morning"]"#.utf8))
        XCTAssertEqual(plain, GoogleTranslate.Result(text: "Good morning", detected: nil))
        XCTAssertThrowsError(try GoogleTranslate.parseCompact(Data("<html>Sorry...</html>".utf8)))
    }

    func testGoogleResponseThatIsNotTheExpectedShapeThrows() {
        XCTAssertThrowsError(try GoogleTranslate.parse(Data("<html>blocked</html>".utf8)))
        XCTAssertThrowsError(try GoogleTranslate.parse(Data(#"{"error":"x"}"#.utf8)))
    }

    func testClaudeStreamYieldsTextDeltas() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hei, hvordan"}},"session_id":"x"}"#
        XCTAssertEqual(ClaudeCLI.parse(line: line), .text("Hei, hvordan"))
    }

    func testClaudeStreamIgnoresOtherEvents() {
        XCTAssertNil(ClaudeCLI.parse(line: #"{"type":"system","subtype":"init"}"#))
        XCTAssertNil(ClaudeCLI.parse(line: #"{"type":"stream_event","event":{"type":"message_stop"}}"#))
        XCTAssertNil(ClaudeCLI.parse(line: #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hm"}}}"#))
        XCTAssertNil(ClaudeCLI.parse(line: "not json"))
    }

    func testClaudeResultCarriesErrors() {
        XCTAssertEqual(ClaudeCLI.parse(line: #"{"type":"result","is_error":true,"result":"Not logged in"}"#),
                       .result("Not logged in", isError: true))
        XCTAssertEqual(ClaudeCLI.parse(line: #"{"type":"result","is_error":false,"result":"Hei"}"#),
                       .result("Hei", isError: false))
    }

    func testClaudeRunsWithoutToolsSettingsOrHistory() {
        let arguments = ClaudeCLI.arguments(system: "S", model: .haiku)
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--tools")! + 1], "")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--setting-sources")! + 1], "")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--model")! + 1], "haiku")
        XCTAssertTrue(arguments.contains("--no-session-persistence"))
        XCTAssertTrue(arguments.contains("--strict-mcp-config"))
    }

    func testTranslatePromptNamesTheLanguage() {
        let norwegian = Language(code: "no", name: "Norwegian")
        XCTAssertTrue(Prompts.translate(to: norwegian).contains("into Norwegian"))
        let german = Language(code: "de", name: "German")
        XCTAssertTrue(Prompts.translate(from: german, to: norwegian).contains("from German into Norwegian"))
        XCTAssertFalse(Prompts.translate(to: norwegian).contains(" from "))
        XCTAssertEqual(Prompts.wrap("abc"), "<text>\nabc\n</text>")
    }

    func testShortcutLabelsListModifiersInTheSystemOrder() {
        XCTAssertEqual(Shortcut.standard.label, "⌃⌘T")
        XCTAssertEqual(Shortcut(keyCode: 49, modifiers: 0x0800).label, "⌥Space")
        XCTAssertEqual(Shortcut(keyCode: 0, modifiers: 0x0100 | 0x0200 | 0x0800 | 0x1000).label, "⌃⌥⇧⌘A")
    }

    func testCodexAnswerIsTheAgentMessage() {
        let line = #"{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"Hei"}}"#
        XCTAssertEqual(CodexCLI.parse(line: line), .text("Hei"))
        XCTAssertNil(CodexCLI.parse(line: #"{"type":"item.completed","item":{"type":"reasoning","text":"hm"}}"#))
        XCTAssertNil(CodexCLI.parse(line: #"{"type":"turn.completed","usage":{}}"#))
    }

    func testCodexErrorsAreReported() {
        XCTAssertEqual(CodexCLI.parse(line: #"{"type":"error","message":"Not logged in"}"#),
                       .result("Not logged in", isError: true))
        XCTAssertEqual(CodexCLI.parse(line: #"{"type":"turn.failed","error":{"message":"Limit reached"}}"#),
                       .result("Limit reached", isError: true))
    }

    func testCodexRunsReadOnlyWithoutSavingASession() {
        let arguments = CodexCLI.arguments
        XCTAssertEqual(arguments.first, "exec")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--sandbox")! + 1], "read-only")
        XCTAssertTrue(arguments.contains("--ephemeral"))
        XCTAssertTrue(arguments.contains("--ignore-user-config"))
        XCTAssertTrue(CodexCLI.input(system: "RULES", text: "abc").hasPrefix("RULES"))
        XCTAssertTrue(CodexCLI.input(system: "RULES", text: "abc").hasSuffix("<text>\nabc\n</text>"))
    }
}
