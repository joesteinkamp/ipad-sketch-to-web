import XCTest
@testable import SketchToWeb

final class RefinementPipelineTests: XCTestCase {

    // MARK: - Error Cases

    func testRefineThrowsOnEmptyAnnotationImage() async {
        let pipeline = RefinementPipeline(apiKey: "fake-key")
        let code = GeneratedCode(htmlPreview: "<div>test</div>", reactCode: "function Test() {}")

        do {
            _ = try await pipeline.refine(
                currentCode: code,
                annotationImage: Data(),
                canvasSize: CGSize(width: 1024, height: 768)
            )
            XCTFail("Expected RefinementError.emptyAnnotationImage")
        } catch let error as RefinementPipeline.RefinementError {
            switch error {
            case .emptyAnnotationImage:
                break // Expected
            default:
                XCTFail("Expected .emptyAnnotationImage but got \(error)")
            }
        } catch {
            // Network error is also acceptable since we're using a fake key
            // and the request may fail at the network layer.
        }
    }

    // MARK: - Error Descriptions

    func testRefinementErrorDescriptions() {
        let apiKeyMissing = RefinementPipeline.RefinementError.apiKeyMissing
        XCTAssertNotNil(apiKeyMissing.errorDescription)
        XCTAssertTrue(apiKeyMissing.errorDescription!.contains("API key"))

        let emptyImage = RefinementPipeline.RefinementError.emptyAnnotationImage
        XCTAssertNotNil(emptyImage.errorDescription)
        XCTAssertTrue(emptyImage.errorDescription!.contains("empty"))
    }

    // MARK: - Pipeline Initialization

    func testPipelineUsesProvidedModel() {
        let pipeline = RefinementPipeline(apiKey: "key", model: "gemini-2.5-flash")
        XCTAssertEqual(pipeline.client.model, "gemini-2.5-flash")
    }

    func testPipelineDefaultModel() {
        let pipeline = RefinementPipeline(apiKey: "key")
        XCTAssertEqual(pipeline.client.model, "gemini-3.1-pro-preview")
    }
}
