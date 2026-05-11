import XCTest
import CoreGraphics
@testable import SketchToWeb

final class RefinementPipelineTests: XCTestCase {

    // MARK: - Error Cases

    func testRefineThrowsOnEmptyAnnotationImage() async {
        let pipeline = RefinementPipeline(client: MockGeminiAPI())
        let code = GeneratedCode(htmlPreview: "<div>test</div>", reactCode: "function Test() {}")

        do {
            _ = try await pipeline.refine(
                currentCode: code,
                annotationImage: Data(),
                canvasSize: CGSize(width: 1024, height: 768)
            )
            XCTFail("Expected RefinementError.emptyAnnotationImage")
        } catch RefinementPipeline.RefinementError.emptyAnnotationImage {
            // Expected
        } catch {
            XCTFail("Expected .emptyAnnotationImage but got \(error)")
        }
    }

    func testRefineThrowsOnEmptyAnnotationImageWithComments() async {
        let pipeline = RefinementPipeline(client: MockGeminiAPI())
        let code = GeneratedCode(htmlPreview: "<div>test</div>", reactCode: "function Test() {}")

        do {
            _ = try await pipeline.refine(
                currentCode: code,
                annotationImage: Data(),
                canvasSize: CGSize(width: 1024, height: 768),
                comments: ["Pin 1: make this blue"]
            )
            XCTFail("Expected RefinementError.emptyAnnotationImage")
        } catch RefinementPipeline.RefinementError.emptyAnnotationImage {
            // Expected
        } catch {
            XCTFail("Expected .emptyAnnotationImage but got \(error)")
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

    // MARK: - Behavior With Mock Client

    func testRefineReturnsParsedGeneratedCode() async throws {
        let mock = MockGeminiAPI()
        await mock.setNextResponse(.success(
            #"{"htmlPreview": "<div>refined</div>", "reactCode": "function Refined() { return null; }"}"#
        ))
        let pipeline = RefinementPipeline(client: mock)
        let code = GeneratedCode(htmlPreview: "<div>orig</div>", reactCode: "function Orig() {}")

        let result = try await pipeline.refine(
            currentCode: code,
            annotationImage: Data([1, 2, 3]),
            canvasSize: CGSize(width: 1024, height: 768),
            comments: ["Pin 1: make this blue"]
        )

        XCTAssertEqual(result.htmlPreview, "<div>refined</div>")
        XCTAssertEqual(result.reactCode, "function Refined() { return null; }")
    }

    func testRefineForwardsAnnotationImageAndComments() async throws {
        let mock = MockGeminiAPI()
        let pipeline = RefinementPipeline(client: mock)
        let code = GeneratedCode(htmlPreview: "<div>orig</div>", reactCode: "function Orig() {}")
        let annotation = Data([0xAA, 0xBB, 0xCC])

        _ = try await pipeline.refine(
            currentCode: code,
            annotationImage: annotation,
            canvasSize: CGSize(width: 800, height: 600),
            comments: ["Pin 1: change color"]
        )

        let calls = await mock.imageCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].imageData, annotation)
        XCTAssertTrue(calls[0].userText.contains("Pin 1: change color"))
        XCTAssertTrue(calls[0].userText.contains("800x600"))
    }

    func testRefinePropagatesNetworkError() async {
        let mock = MockGeminiAPI()
        let underlying = NSError(domain: "test", code: -1009, userInfo: [NSLocalizedDescriptionKey: "offline"])
        await mock.setNextResponse(.failure(GeminiClient.GeminiError.networkError(underlying)))
        let pipeline = RefinementPipeline(client: mock)
        let code = GeneratedCode(htmlPreview: "<div>orig</div>", reactCode: "function Orig() {}")

        do {
            _ = try await pipeline.refine(
                currentCode: code,
                annotationImage: Data([1, 2, 3]),
                canvasSize: CGSize(width: 100, height: 100)
            )
            XCTFail("Expected GeminiError.networkError")
        } catch GeminiClient.GeminiError.networkError {
            // Expected
        } catch {
            XCTFail("Expected GeminiError.networkError but got \(error)")
        }
    }

    // MARK: - Live Factory

    func testLiveFactoryProducesPipelineWithGeminiClient() {
        let pipeline = RefinementPipeline.live(apiKey: "test-key", model: "gemini-2.5-flash")
        XCTAssertTrue(pipeline.client is GeminiClient)
    }
}
