import XCTest
import PencilKit
@testable import SketchToWeb

@MainActor
final class ConversionPipelineTests: XCTestCase {

    // MARK: - Happy Path

    func testConvertReturnsParsedGeneratedCode() async throws {
        let mock = MockGeminiAPI()
        await mock.setNextResponse(.success(
            #"{"htmlPreview": "<html><body>hi</body></html>", "reactCode": "export default function P() { return null; }"}"#
        ))
        let pipeline = AIConversionPipeline(client: mock)

        let result = try await pipeline.convert(
            drawing: PKDrawing(),
            canvasSize: CGSize(width: 1024, height: 768)
        )

        XCTAssertEqual(result.htmlPreview, "<html><body>hi</body></html>")
        XCTAssertEqual(result.reactCode, "export default function P() { return null; }")
    }

    func testConvertSendsImageDataToClient() async throws {
        let mock = MockGeminiAPI()
        let pipeline = AIConversionPipeline(client: mock)

        _ = try await pipeline.convert(
            drawing: PKDrawing(),
            canvasSize: CGSize(width: 800, height: 600)
        )

        let calls = await mock.imageCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertFalse(calls[0].imageData.isEmpty, "PNG payload should be non-empty even for an empty drawing")
        XCTAssertTrue(calls[0].imageData.starts(with: [0x89, 0x50, 0x4E, 0x47]), "Payload should be a PNG")
    }

    func testSystemPromptIncludesComponentCatalogContext() async throws {
        let mock = MockGeminiAPI()
        let pipeline = AIConversionPipeline(client: mock)

        _ = try await pipeline.convert(
            drawing: PKDrawing(),
            canvasSize: CGSize(width: 1024, height: 768)
        )

        let calls = await mock.imageCalls
        XCTAssertEqual(calls.count, 1)
        // The system prompt is built from SketchAnalysisPrompt + the loaded component catalog.
        // Check for a marker that the catalog made it in.
        XCTAssertTrue(
            calls[0].systemPrompt.contains("shadcn") || calls[0].systemPrompt.contains("component"),
            "System prompt should reference the component catalog"
        )
    }

    // MARK: - Error Paths

    func testConvertPropagatesNetworkError() async {
        let mock = MockGeminiAPI()
        let underlying = NSError(domain: "test", code: -1009, userInfo: [NSLocalizedDescriptionKey: "offline"])
        await mock.setNextResponse(.failure(GeminiClient.GeminiError.networkError(underlying)))
        let pipeline = AIConversionPipeline(client: mock)

        do {
            _ = try await pipeline.convert(
                drawing: PKDrawing(),
                canvasSize: CGSize(width: 1024, height: 768)
            )
            XCTFail("Expected GeminiError.networkError to propagate")
        } catch GeminiClient.GeminiError.networkError {
            // Expected
        } catch {
            XCTFail("Expected GeminiError.networkError but got \(error)")
        }
    }

    func testConvertPropagatesRateLimitError() async {
        let mock = MockGeminiAPI()
        await mock.setNextResponse(.failure(GeminiClient.GeminiError.rateLimited(retryAfter: 42)))
        let pipeline = AIConversionPipeline(client: mock)

        do {
            _ = try await pipeline.convert(
                drawing: PKDrawing(),
                canvasSize: CGSize(width: 1024, height: 768)
            )
            XCTFail("Expected rate-limit error to propagate")
        } catch GeminiClient.GeminiError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 42)
        } catch {
            XCTFail("Expected GeminiError.rateLimited but got \(error)")
        }
    }

    func testConvertThrowsParseErrorOnMalformedJSON() async {
        let mock = MockGeminiAPI()
        await mock.setNextResponse(.success("this is definitely not json"))
        let pipeline = AIConversionPipeline(client: mock)

        do {
            _ = try await pipeline.convert(
                drawing: PKDrawing(),
                canvasSize: CGSize(width: 1024, height: 768)
            )
            XCTFail("Expected ParseError")
        } catch is CodeGenerationResponse.ParseError {
            // Expected
        } catch {
            XCTFail("Expected CodeGenerationResponse.ParseError but got \(error)")
        }
    }

    // MARK: - Live Factory

    func testLiveFactoryProducesPipelineWithGeminiClient() {
        let pipeline = AIConversionPipeline.live(apiKey: "test-key", model: "gemini-2.5-flash")
        XCTAssertTrue(pipeline.client is GeminiClient)
    }
}
