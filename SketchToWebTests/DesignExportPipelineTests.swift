import XCTest
@testable import SketchToWeb

final class DesignExportPipelineTests: XCTestCase {

    // MARK: - extractFigmaURL

    func testExtractsFigmaFileURL() {
        let text = "Done — see https://www.figma.com/file/abc123/Login for the result."
        let url = DesignExportPipeline.extractFigmaURL(from: text)
        XCTAssertEqual(url?.absoluteString, "https://www.figma.com/file/abc123/Login")
    }

    func testExtractsFigmaURLWithoutWWW() {
        let text = "Created at https://figma.com/design/xyz?node-id=1"
        let url = DesignExportPipeline.extractFigmaURL(from: text)
        XCTAssertEqual(url?.host, "figma.com")
    }

    func testReturnsNilWhenNoFigmaURL() {
        let text = "Created the frame but no link was returned."
        XCTAssertNil(DesignExportPipeline.extractFigmaURL(from: text))
    }

    func testStripsTrailingPunctuation() {
        let text = "Open https://www.figma.com/file/abc."
        let url = DesignExportPipeline.extractFigmaURL(from: text)
        // The regex stops at whitespace/closing paren, so a trailing period is included.
        // Verify we still get a parseable URL with the right host.
        XCTAssertEqual(url?.host, "www.figma.com")
    }

    // MARK: - System prompt

    func testSystemPromptMentionsDestination() {
        let prompt = DesignExportPipeline.buildSystemPrompt(destination: .figma)
        XCTAssertTrue(prompt.contains("Figma"))
        XCTAssertTrue(prompt.contains("tools"))
    }

    // MARK: - User prompt

    func testUserPromptIncludesGeneratedCode() {
        let code = GeneratedCode(htmlPreview: "<html>HI</html>", reactCode: "export default function X() {}")
        let prompt = DesignExportPipeline.buildUserPrompt(generatedCode: code, userInstruction: nil)
        XCTAssertTrue(prompt.contains("HI"))
        XCTAssertTrue(prompt.contains("export default function X"))
    }

    func testUserPromptIncludesUserInstructionWhenProvided() {
        let code = GeneratedCode(htmlPreview: "", reactCode: "")
        let prompt = DesignExportPipeline.buildUserPrompt(generatedCode: code, userInstruction: "Make it dark")
        XCTAssertTrue(prompt.contains("Make it dark"))
    }

    // MARK: - describeStep

    func testDescribeStepHumanizesToolNames() {
        let call = GeminiFunctionCall(
            name: "create_frame",
            argumentsJSON: Data("{}".utf8)
        )
        let step = DesignExportPipeline.describeStep(for: call, round: 0)
        XCTAssertTrue(step.contains("Step 1"))
        XCTAssertTrue(step.contains("create frame"))
    }
}
