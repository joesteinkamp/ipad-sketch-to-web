import XCTest
@testable import SketchToWeb

final class AppErrorTests: XCTestCase {

    // MARK: - Mapping from GeminiError

    func testMapsInvalidAPIKey() {
        let error = AppError(GeminiClient.GeminiError.invalidAPIKey)
        XCTAssertEqual(error, .apiKeyMissing)
    }

    func testMapsRateLimited() {
        let error = AppError(GeminiClient.GeminiError.rateLimited(retryAfter: 30))
        XCTAssertEqual(error, .rateLimited(retryAfter: 30))
    }

    func testMapsServerError() {
        let error = AppError(GeminiClient.GeminiError.serverError("blocked"))
        XCTAssertEqual(error, .serverBlocked("blocked"))
    }

    func testMapsNetworkError() {
        let underlying = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "no internet"])
        let error = AppError(GeminiClient.GeminiError.networkError(underlying))
        XCTAssertEqual(error, .network("no internet"))
    }

    func testMapsParseError() {
        let error = AppError(GeminiClient.GeminiError.parseError("bad json"))
        XCTAssertEqual(error, .parsing("bad json"))
    }

    // MARK: - Mapping from Pipeline Errors

    func testMapsConversionPipelineImageRendering() {
        let error = AppError(AIConversionPipeline.PipelineError.imageRenderingFailed)
        XCTAssertEqual(error, .rendering)
    }

    func testMapsConversionPipelineMissingKey() {
        let error = AppError(AIConversionPipeline.PipelineError.apiKeyMissing)
        XCTAssertEqual(error, .apiKeyMissing)
    }

    func testMapsRefinementPipelineMissingKey() {
        let error = AppError(RefinementPipeline.RefinementError.apiKeyMissing)
        XCTAssertEqual(error, .apiKeyMissing)
    }

    func testMapsRefinementEmptyAnnotation() {
        let error = AppError(RefinementPipeline.RefinementError.emptyAnnotationImage)
        XCTAssertEqual(error, .imageEmpty)
    }

    // MARK: - Mapping from CodeGenerationResponse.ParseError

    func testMapsParseErrorFromResponseEnum() {
        let error = AppError(CodeGenerationResponse.ParseError.missingHTMLPreview)
        if case .parsing(let message) = error {
            XCTAssertTrue(message.contains("htmlPreview"))
        } else {
            XCTFail("Expected .parsing case but got \(error)")
        }
    }

    // MARK: - Identity Mapping

    func testAppErrorPassthrough() {
        let original = AppError.apiKeyMissing
        XCTAssertEqual(AppError(original), original)
    }

    // MARK: - Default Case

    func testUnknownErrorFallsThrough() {
        struct CustomError: Error, LocalizedError {
            var errorDescription: String? { "something else" }
        }
        let error = AppError(CustomError())
        XCTAssertEqual(error, .unknown("something else"))
    }

    // MARK: - Descriptions

    func testAllCasesHaveDescriptions() {
        let cases: [AppError] = [
            .apiKeyMissing,
            .network("x"),
            .rateLimited(retryAfter: 5),
            .serverBlocked("y"),
            .parsing("z"),
            .rendering,
            .imageEmpty,
            .unknown("w"),
        ]
        for error in cases {
            XCTAssertNotNil(error.errorDescription, "\(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "\(error) description should not be empty")
        }
    }
}
