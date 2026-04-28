import XCTest
@testable import SketchToWeb

final class SketchAnalysisPromptTests: XCTestCase {

    // MARK: - User prompt without labels

    func testUserPromptWithoutLabelsIsUnchanged() {
        let prompt = SketchAnalysisPrompt.buildUserPrompt()
        XCTAssertEqual(
            prompt,
            "Convert this hand-drawn wireframe sketch into a web UI. Analyze each element and map it to the appropriate shadcn/ui component. Return valid JSON."
        )
    }

    func testEmptyLabelsArrayProducesIdenticalPrompt() {
        let withDefault = SketchAnalysisPrompt.buildUserPrompt()
        let withEmptyArray = SketchAnalysisPrompt.buildUserPrompt(labeledBoxes: [])
        XCTAssertEqual(withDefault, withEmptyArray)
    }

    // MARK: - User prompt with labels

    func testLabeledBoxesAppendAuthoritativeSection() {
        let box = LabeledBoxDetector.LabeledBox(
            bounds: CGRect(x: 120, y: 80, width: 300, height: 60),
            componentName: "Input",
            rawText: "input",
            confidence: 1.0
        )
        let prompt = SketchAnalysisPrompt.buildUserPrompt(labeledBoxes: [box])

        XCTAssertTrue(prompt.contains("# User-provided labels"))
        XCTAssertTrue(prompt.contains("ground truth"))
        XCTAssertTrue(prompt.contains("Box at (x:120, y:80, w:300, h:60): Input"))
    }

    func testMultipleLabelsAllAppearInPrompt() {
        let labels = [
            LabeledBoxDetector.LabeledBox(
                bounds: CGRect(x: 0, y: 0, width: 100, height: 40),
                componentName: "Button",
                rawText: "button",
                confidence: 1.0
            ),
            LabeledBoxDetector.LabeledBox(
                bounds: CGRect(x: 0, y: 60, width: 300, height: 200),
                componentName: "Card",
                rawText: "card",
                confidence: 1.0
            )
        ]
        let prompt = SketchAnalysisPrompt.buildUserPrompt(labeledBoxes: labels)

        XCTAssertTrue(prompt.contains("Box at (x:0, y:0, w:100, h:40): Button"))
        XCTAssertTrue(prompt.contains("Box at (x:0, y:60, w:300, h:200): Card"))
    }

    func testCoordinatesAreRoundedToIntegers() {
        let box = LabeledBoxDetector.LabeledBox(
            bounds: CGRect(x: 10.7, y: 20.4, width: 99.6, height: 33.2),
            componentName: "Badge",
            rawText: "badge",
            confidence: 1.0
        )
        let prompt = SketchAnalysisPrompt.buildUserPrompt(labeledBoxes: [box])
        XCTAssertTrue(prompt.contains("Box at (x:11, y:20, w:100, h:33): Badge"))
    }
}
